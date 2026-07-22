#!/usr/bin/env bash
# ============================================================
# lib.sh — イメージ可用性検証ハーネス 共通関数
# ============================================================
# run_one.sh から `source` して使う前提。単独実行は想定しない。
# 呼び出し側は `set -uo pipefail` を使う想定（-e は使わない）。
#
# 注意: ensure_iourc / ram_gate は失敗時に exit する（元の設計を踏襲）。
# 呼び出し側でスクリプト全体を落とさず結果を記録したい場合は
#   if ! ( ensure_iourc "$IMAGE" ); then ... fi
# のようにサブシェルで包んで exit を隔離すること。

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOURC_FILE="/opt/clab/.iourc"
RESULTS_FILE="${LIB_DIR}/results/results.tsv"

# check_labs_intact が初回呼び出し時に記録する既存ラボのコンテナ数
IMGV_QOS_ACL_BASELINE=""
IMGV_NWZT_BASELINE=""

# judge_boot_failure が「起動継続中」と見なすCPU使用率の閾値(%)
IMGV_CPU_BUSY_THRESHOLD=3

# ------------------------------------------------------------
# 1. ensure_iourc <image>
# ------------------------------------------------------------
# IOL実ライセンスをVMローカル固定パス(/opt/clab/.iourc)に用意する。
# 28_snmp_monitoring_deep_dive/04_構築/deploy.sh の同名関数の移植版。
# 差分: 元は候補イメージ4つを順に試す全探索だったが、本ハーネスは
#       検証対象の image が呼び出し時点で確定しているため引数で1つだけ受け取る。
ensure_iourc() {
  local img="$1"

  if sudo test -s "$IOURC_FILE" \
     && sudo grep -qE 'gns3-iouvm *= *[0-9a-fA-F]{16} *;' "$IOURC_FILE" \
     && ! sudo grep -qE 'gns3-iouvm *= *0{16} *;' "$IOURC_FILE"; then
    return 0
  fi

  local lic
  lic=$(docker run --rm --entrypoint sh "$img" -c \
      'cat /iol/.iourc 2>/dev/null; grep -h -oE "gns3-iouvm = [0-9a-fA-F]{16}" /entrypoint.sh 2>/dev/null' \
      2>/dev/null | grep -oE '[0-9a-fA-F]{16}' | grep -v '^0\{16\}$' | head -1) || true

  if [ -n "${lic:-}" ]; then
    sudo mkdir -p "$(dirname "$IOURC_FILE")"
    printf '[license]\ngns3-iouvm = %s;\n' "$lic" | sudo tee "$IOURC_FILE" >/dev/null
    sudo chmod 600 "$IOURC_FILE"
    echo "IOURC: ${img} からライセンスを抽出し ${IOURC_FILE} を作成しました。"
    return 0
  fi

  echo "ERROR: IOLライセンスをイメージ ${img} から抽出できませんでした。${IOURC_FILE} を手動で用意してください。" >&2
  exit 1
}

# ------------------------------------------------------------
# 2. wait_boot <container> <timeout_sec>
# ------------------------------------------------------------
# 30秒間隔でヘルスチェック状態をポーリングする。
# healthy → 0 で復帰。ヘルスチェック未定義(<no value>/空)のコンテナは
# running状態が累計120秒続いたら 0 で復帰。
# 結果種別はグローバル変数 WAIT_BOOT_RESULT (healthy/running/timeout) で返す。
wait_boot() {
  local container="$1" timeout_sec="$2"
  local elapsed=0 running_streak=0
  local -r running_ok_sec=120
  local -r poll_interval=30

  WAIT_BOOT_RESULT="timeout"

  while [ "$elapsed" -lt "$timeout_sec" ]; do
    local status running
    status=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null)
    running=$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null)

    if [ "$status" = "healthy" ]; then
      WAIT_BOOT_RESULT="healthy"
      return 0
    fi

    if [ -z "$status" ] || [ "$status" = "<no value>" ]; then
      if [ "$running" = "true" ]; then
        running_streak=$((running_streak + poll_interval))
        if [ "$running_streak" -ge "$running_ok_sec" ]; then
          WAIT_BOOT_RESULT="running"
          return 0
        fi
      else
        running_streak=0
      fi
    else
      # starting/unhealthy等はカウンタをリセットして様子を見る
      running_streak=0
    fi

    sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  WAIT_BOOT_RESULT="timeout"
  return 1
}

# ------------------------------------------------------------
# 3. judge_boot_failure <container>
# ------------------------------------------------------------
# wait_boot がタイムアウトした際の切り分け。
# qemuプロセスが生存 かつ CPU消費中なら "still-booting"(呼び出し側が1回だけ延長)。
# qemu消滅、またはログ末尾にTraceback/exitedがあれば "failed"。
# 結果は echo で返す（呼び出し側は $(judge_boot_failure "$ct") で受ける）。
judge_boot_failure() {
  local container="$1"
  local qemu_alive="false"

  if docker exec "$container" pgrep -f qemu >/dev/null 2>&1; then
    qemu_alive="true"
  elif pgrep -f "qemu.*${container}" >/dev/null 2>&1; then
    # dockerモードでexecできない(コンテナ停止済み等)場合のVM側フォールバック
    qemu_alive="true"
  fi

  if [ "$qemu_alive" = "true" ]; then
    local cpu_raw cpu_int
    cpu_raw=$(docker stats --no-stream --format '{{.CPUPerc}}' "$container" 2>/dev/null | tr -d '%')
    cpu_int="${cpu_raw%%.*}"
    if [ -n "$cpu_int" ] && [ "$cpu_int" -ge "$IMGV_CPU_BUSY_THRESHOLD" ] 2>/dev/null; then
      echo "still-booting"
      return 0
    fi
    # qemuは生きているがCPUがほぼアイドル → ハング疑いとして failed 扱い
    echo "failed"
    return 1
  fi

  echo "failed"
  return 1
}

# ------------------------------------------------------------
# 4. ssh_cmd <ip> <user> <pass> <cmd> [timeout_sec=60]
# ------------------------------------------------------------
# 旧NOS(vIOS/CSR16/ASA/NXOS等)はUbuntu24.04のOpenSSH既定だと鍵交換で
# 拒否されるため、古いアルゴリズムを明示的に許可して接続する。
ssh_cmd() {
  local ip="$1" user="$2" pass="$3" cmd="$4" tmo="${5:-60}"

  # -n 必須: while read ループ内から呼ばれるため、stdinを継承すると
  # ループの入力(cmdsファイル)をsshが食い潰して2行目以降が消える
  timeout "$tmo" sshpass -p "$pass" ssh -n \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1 \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -o Ciphers=+aes128-cbc,aes256-cbc \
    "${user}@${ip}" "$cmd"
}

# ------------------------------------------------------------
# 5. ssh_interactive <ip> <user> <pass> <cmdfile> [timeout_sec=120]
# ------------------------------------------------------------
# config モード等、対話的な複数コマンド投入が必要な機種向け。
# cmdfile の各行を2秒間隔で `ssh -tt` の標準入力へ流し込み、出力を返す。
ssh_interactive() {
  local ip="$1" user="$2" pass="$3" cmdfile="$4" tmo="${5:-120}"

  timeout "$tmo" bash -c '
    ip="$1"; user="$2"; pass="$3"; cmdfile="$4"
    (
      while IFS= read -r line || [ -n "$line" ]; do
        printf "%s\n" "$line"
        sleep 2
      done < "$cmdfile"
    ) | sshpass -p "$pass" ssh -tt \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1 \
        -o HostKeyAlgorithms=+ssh-rsa \
        -o PubkeyAcceptedAlgorithms=+ssh-rsa \
        -o Ciphers=+aes128-cbc,aes256-cbc \
        "${user}@${ip}" 2>&1
  ' _ "$ip" "$user" "$pass" "$cmdfile"
}

# ------------------------------------------------------------
# 6. rest_get / rest_post / rest_put / rest_delete
# ------------------------------------------------------------
# curl -sk --max-time 30 + Basic認証。RouterOS REST等の機種別フックから使用。
rest_get() {
  local url="$1" user="$2" pass="$3"
  curl -sk --max-time 30 -u "${user}:${pass}" "$url"
}

rest_post() {
  local url="$1" user="$2" pass="$3" json="$4"
  curl -sk --max-time 30 -u "${user}:${pass}" \
    -H 'Content-Type: application/json' -X POST -d "$json" "$url"
}

rest_put() {
  local url="$1" user="$2" pass="$3" json="$4"
  curl -sk --max-time 30 -u "${user}:${pass}" \
    -H 'Content-Type: application/json' -X PUT -d "$json" "$url"
}

rest_delete() {
  local url="$1" user="$2" pass="$3"
  curl -sk --max-time 30 -u "${user}:${pass}" -X DELETE "$url"
}

# ------------------------------------------------------------
# 7. check_labs_intact
# ------------------------------------------------------------
# 稼働中の既存ラボ(qos-acl-policy-lab / nwzt-lan)のコンテナ数を数え、
# 初回呼び出し時の値より減っていたら即 exit 1 する安全弁。
check_labs_intact() {
  local qos_count nwzt_count
  qos_count=$(docker ps --format '{{.Names}}' | grep -c '^clab-qos-acl-policy-lab-')
  nwzt_count=$(docker ps --format '{{.Names}}' | grep -c '^clab-nwzt-lan-')

  if [ -z "$IMGV_QOS_ACL_BASELINE" ]; then
    IMGV_QOS_ACL_BASELINE="$qos_count"
    IMGV_NWZT_BASELINE="$nwzt_count"
    echo "check_labs_intact: 初期値を記録しました (qos-acl-policy-lab=${qos_count}, nwzt-lan=${nwzt_count})"
    return 0
  fi

  if [ "$qos_count" -lt "$IMGV_QOS_ACL_BASELINE" ]; then
    echo "FATAL: clab-qos-acl-policy-lab- のコンテナ数が ${IMGV_QOS_ACL_BASELINE} → ${qos_count} に減少しました。既存ラボが壊れた可能性があるため即座に停止します。" >&2
    exit 1
  fi
  if [ "$nwzt_count" -lt "$IMGV_NWZT_BASELINE" ]; then
    echo "FATAL: clab-nwzt-lan- のコンテナ数が ${IMGV_NWZT_BASELINE} → ${nwzt_count} に減少しました。既存ラボが壊れた可能性があるため即座に停止します。" >&2
    exit 1
  fi
  return 0
}

# ------------------------------------------------------------
# 8. ram_gate <required_gib>
# ------------------------------------------------------------
# 空きRAM(available)が required_gib GiB未満なら exit 2 (NG-RESOURCE)。
# クラス→必要GiBの対応(S=2,M=4,L=6,XL=10)は呼び出し側(run_one.sh)で決定する。
ram_gate() {
  local required_gib="$1"
  local available_gib waited=0
  local -r max_wait=7200  # 並列レーン運用時、他レーンのdestroyでRAMが空くのを最大2時間待つ(XL級はL級2台の完了待ちがありうる)

  while :; do
    available_gib=$(free -g | awk '/^Mem:/ {print $7}')
    if [ -z "$available_gib" ]; then
      # available列(第7フィールド)が無い古い free の場合は free列(第4フィールド)で代替
      available_gib=$(free -g | awk '/^Mem:/ {print $4}')
    fi

    if [ -n "$available_gib" ] && [ "$available_gib" -ge "$required_gib" ]; then
      return 0
    fi
    if [ "$waited" -ge "$max_wait" ]; then
      echo "NG-RESOURCE: 空きRAM ${available_gib:-不明}GiB < 必要 ${required_gib}GiB (${max_wait}秒待機後も不足)のため中断します。" >&2
      exit 2
    fi
    echo "ram_gate: 空き${available_gib:-不明}GiB < 必要${required_gib}GiB — 60秒待機して再確認します"
    sleep 60
    waited=$((waited + 60))
  done
}

# ------------------------------------------------------------
# 9. scrub <file>
# ------------------------------------------------------------
# 16桁hex(IOLライセンス gns3-iouvm 値等)を [REDACTED] に置換する。
# results/ 配下(リポジトリにコミットされうる範囲)へ書く内容は必ず本関数を通すこと。
scrub() {
  local file="$1"
  [ -f "$file" ] || return 0
  sed -i -E 's/[0-9a-fA-F]{16}/[REDACTED]/g' "$file"
}

# ------------------------------------------------------------
# 10. append_result <image:tag> <class> <boot> <access> <cmds_pass/total> \
#                   <version_match> <verdict> <duration_s> <notes>
# ------------------------------------------------------------
# results/results.tsv へ1行追記する。verdict は
# FULL/PARTIAL/BOOT_ONLY/NG/NG-RESOURCE/SKIP のいずれか。
append_result() {
  local image="$1" class="$2" boot="$3" access="$4" cmds="$5"
  local version_match="$6" verdict="$7" duration_s="$8" notes="$9"
  local today
  today=$(date +%F)

  mkdir -p "$(dirname "$RESULTS_FILE")"
  if [ ! -f "$RESULTS_FILE" ]; then
    printf 'date\timage:tag\tclass\tboot\taccess\tcmds_pass/total\tversion_match\tverdict\tduration_s\tnotes\n' \
      > "$RESULTS_FILE"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$today" "$image" "$class" "$boot" "$access" "$cmds" \
    "$version_match" "$verdict" "$duration_s" "$notes" \
    >> "$RESULTS_FILE"
}
