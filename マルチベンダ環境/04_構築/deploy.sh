#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
TOPO="multivendor.clab.yml"
NAME_PREFIX="clab-mvlab-"
IOURC_FILE="/opt/clab/.iourc"
EDGE_IP="172.20.50.11"
EDGE_USER="admin"
EDGE_PASS="admin"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

# IOL実ライセンスをVMローカルの固定パス(/opt/clab/.iourc)に用意する。
# 本ラボのIOLイメージ(15.7.3M2 / L2-advipservices-2017)はライセンスが
# /iol/.iourc ではなくイメージ側 /entrypoint.sh 内にあり、entrypoint_attach.sh の
# bind で隠れるため、デプロイ前にイメージから抽出して
# bind(/opt/clab/.iourc:/iol/.iourc:ro) で渡す。
# ライセンス値はVM内(Dockerイメージと本ファイル)にのみ存在させ、gitへは一切置かないこと。
ensure_iourc() {
  if sudo test -s "$IOURC_FILE" \
     && sudo grep -qE 'gns3-iouvm *= *[0-9a-fA-F]{16} *;' "$IOURC_FILE" \
     && ! sudo grep -qE 'gns3-iouvm *= *0{16} *;' "$IOURC_FILE"; then
    return 0
  fi
  local img lic
  for img in vrnetlab/cisco_iol:15.7.3M2 vrnetlab/cisco_iol:L2-advipservices-2017; do
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
  done
  echo "ERROR: IOLライセンスをイメージから抽出できませんでした。${IOURC_FILE} を手動で用意してください。" >&2
  exit 1
}

# iouyap は entrypoint_attach.sh がIOLブート後(+60秒)に自動起動・自己修復する。
# 本関数は自動起動が働かない場合の手動リカバリ用（./deploy.sh iouyap）。
# 対象はIOLコンテナのみ。除外: pc|srv|br-|isp|leaf|edge
#   → hq-edge(MikroTik) と br-edge(OpenWrt) はIOLではないため edge/br- で除外。
#     残るのは hq-core / hq-sw の2台。
start_iouyap() {
  sleep 5
  for container in $(sudo docker ps --format '{{.Names}}' \
      | grep "^${NAME_PREFIX}" | grep -v -E 'pc|srv|br-|isp|leaf|edge'); do
    sudo docker exec -d -w /iol "$container" /usr/bin/iouyap 513 2>/dev/null || true
  done
}

# ---------------------------------------------------------------------------
# RouterOS(hq-edge) / SR Linux(dc-leaf1,dc-leaf2) への「ブート後config投入」。
# 2026-07-17実機テストで、両ベンダーとも clab startup-config（FTP自動投入 /
# コンテナへのバインド）が不達・構文エラーで全滅することが判明したため、
# ブート完了をポーリングで待ってから ssh / sr_cli で流し込む方式に変更した。
# ---------------------------------------------------------------------------

# RouterOS(hq-edge): configs/hq-edge.rsc を1行ずつsshで投入する。
# #行・空行はスキップ（インラインコメントは構文エラーの原因になるため
# hq-edge.rsc側にも一切含めていない）。
push_routeros() {
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "ERROR: sshpassが見つかりません（VMに導入してください: sudo apt-get install -y sshpass）。" >&2
    return 1
  fi
  echo "hq-edge(${EDGE_IP}): ブート待ち（最大120秒）..."
  local waited=0
  until sshpass -p "$EDGE_PASS" ssh "${SSH_OPTS[@]}" -o ConnectTimeout=5 \
        "${EDGE_USER}@${EDGE_IP}" "/system/resource print" >/dev/null 2>&1; do
    waited=$((waited + 5))
    if [ "$waited" -ge 120 ]; then
      echo "ERROR: hq-edge(${EDGE_IP})が120秒以内に応答しませんでした。手動で ./deploy.sh config を再実行してください。" >&2
      return 1
    fi
    sleep 5
  done
  echo "hq-edge: 起動確認。configs/hq-edge.rsc を投入します..."
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    # -n 必須: これが無いと while ループ内の ssh が stdin(=hq-edge.rsc)を
    # 食い潰し、2行目以降が消えて最初の1コマンドしか投入されない
    # （2026-07-17に addr=2/BGP無しで再現。run_one.sh で直したのと同じ罠）。
    sshpass -p "$EDGE_PASS" ssh -n "${SSH_OPTS[@]}" -o ConnectTimeout=8 \
      "${EDGE_USER}@${EDGE_IP}" "$line" \
      || echo "WARN: hq-edge 行投入失敗: $line" >&2
  done < configs/hq-edge.rsc
  echo "hq-edge: config投入完了。"
}

# SR Linux(dc-leaf1/dc-leaf2): configs/dc-leafN.cli の set行を集め、
# candidateモードで一括commitする（"enter candidate" → set行群 → "commit stay"）。
# sr_cliへは引数ではなくstdinパイプで渡す（2026-07-17実機で
# "All changes have been committed" を確認済みの方式）。
push_srl() {
  # 注: `local a=$1 b=${a}` は同一行内で a の展開が未定義になりうる（set -u で
  #     unbound variable）ため、node を先に確定させてから他を組み立てる。
  local node="$1"
  local cfg="configs/${node}.cli"
  local container="${NAME_PREFIX}${node}"
  echo "${node}: sr_cli へconfig投入..."
  {
    printf 'enter candidate\n'
    local line
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        ''|'#'*) continue ;;
      esac
      printf '%s\n' "$line"
    done < "$cfg"
    printf 'commit stay\n'
    printf 'quit\n'
  } | sudo docker exec -i "$container" sr_cli \
    || echo "WARN: ${node} config投入に失敗しました。手動で ./deploy.sh config を再実行してください。" >&2
  echo "${node}: config投入完了。"
}

# IOL(hq-core/hq-sw)の初期設定ダイアログに "no" を自動応答する。
# このGNS3世代IOLはブート時に "Would you like to enter the initial
# configuration dialog? [yes/no]:" を表示し、応答するまで startup-config
# (config.txt)をロードせず OSPF/BGP も起動しない(2026-07-17実機で確認:
# "no" 応答の瞬間に全隣接がFULL/Upになる)。expectでconsoleに応答する。
answer_iol_dialog() {
  local node="$1" container="${NAME_PREFIX}${node}"
  if ! command -v expect >/dev/null 2>&1; then
    echo "WARN: expect未導入のため ${node} のダイアログ自動応答をスキップ。" \
         "手動で: sudo docker attach ${container} → 'no' 入力 → Ctrl-P Ctrl-Q" >&2
    return 0
  fi
  echo "${node}: IOL初期設定ダイアログに応答します..."
  expect <<EOF >/dev/null 2>&1
set timeout 30
spawn sudo docker attach --detach-keys=ctrl-x $container
send "\r"
expect {
  "dialog? \[yes/no\]:" { send "no\r"; exp_continue }
  -re {${node}[>#]}     { send "\x18" }
  -re {[Rr]outer[>#]}   { send "\x18" }
  timeout               { send "\x18" }
}
EOF
  echo "${node}: ダイアログ応答完了。"
}

push_config() {
  # 先にIOLのダイアログを解除しないと config.txt がロードされず OSPF/BGP が上がらない
  answer_iol_dialog hq-core || true
  answer_iol_dialog hq-sw   || true
  push_routeros || echo "WARN: hq-edgeのconfig投入をスキップしました。"
  push_srl dc-leaf1 || true
  push_srl dc-leaf2 || true
}

case "${1:-deploy}" in
  deploy)
    ensure_iourc
    sudo containerlab deploy -t "$TOPO"
    echo "NOTE: iouyap(hq-core/hq-sw)はIOLブート後(約60秒)にentrypointが自動起動します。"
    echo "NOTE: hq-edge(RouterOS CHR)のブートは約2分。config投入を自動実行します。"
    push_config
    ;;
  config)
    push_config
    ;;
  iouyap)
    start_iouyap
    ;;
  inspect)
    sudo containerlab inspect -t "$TOPO"
    ;;
  status)
    sudo docker ps --filter "name=^${NAME_PREFIX}" \
      --format 'table {{.Names}}\t{{.Status}}'
    ;;
  destroy)
    # --cleanup はnvram(保存済みコンフィグ)ごと削除する。コンフィグを残したい場合は
    # `sudo containerlab destroy -t multivendor.clab.yml` を直接実行すること（--cleanupなし）。
    sudo containerlab destroy -t "$TOPO" --cleanup
    ;;
  *)
    echo "usage: $0 {deploy|config|iouyap|inspect|status|destroy}" >&2
    exit 1
    ;;
esac
