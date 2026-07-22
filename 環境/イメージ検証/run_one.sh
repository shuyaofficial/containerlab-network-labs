#!/usr/bin/env bash
# ============================================================
# run_one.sh — 1イメージの deploy→wait→検証→収集→destroy を実行する
# ============================================================
# usage: ./run_one.sh <name> [--extend-done]
#
# --extend-done: 起動タイムアウト時の「1回だけ延長」を行わず、
#                即座に timeout 扱いにする(手動で延長を使い切った後の
#                再実行や、厳密なタイムアウト検証をしたい場合に使う任意フラグ)。
#
# set -e は使わない(判定分岐が多く、個別にハンドリングするため)。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# ------------------------------------------------------------
# 機種メタデータ: name -> mode(clab|docker) / kind / image / class(S/M/L/XL)
# ------------------------------------------------------------
declare -A IMGV_MODE IMGV_KIND IMGV_IMAGE IMGV_CLASS

register() {
  local n="$1"
  IMGV_MODE["$n"]="$2"
  IMGV_KIND["$n"]="$3"
  IMGV_IMAGE["$n"]="$4"
  IMGV_CLASS["$n"]="$5"
}

register routeros    clab   mikrotik_ros       "vrnetlab/mikrotik_routeros:7.5"           M
register chr7214     clab   mikrotik_ros       "vrnetlab/mikrotik_routeros:7.21.4"        M
register veos        clab   arista_veos        "vrnetlab/arista_veos:4.29.2F"             M
register asav        clab   cisco_asav         "vrnetlab/cisco_asav:9-18-1"               M
register fortios     clab   fortinet_fortigate "vrnetlab/fortinet_fortios:7.4.2.F"        M
register csr17       clab   cisco_csr1000v     "vrnetlab/cisco_csr1000v:17.03.05"         L
register csr16       clab   cisco_csr1000v     "vrnetlab/cisco_csr1000v:16.12.05"         L
register c8000v      clab   cisco_c8000v       "vrnetlab/cisco_c8000v:17.06.03"           L
register vsrx        clab   juniper_vsrx       "vrnetlab/juniper_vsrx:24.4R1.9"           XL
register vios        clab   cisco_vios         "vrnetlab/cisco_vios:159-3.M6"             M
register viosl2      clab   cisco_vios         "vrnetlab/cisco_vios:L2-20200929"          M
register iol-1563    clab   cisco_iol          "vrnetlab/cisco_iol:15.6.3M3a"             S
register iol-l2152   clab   cisco_iol          "vrnetlab/cisco_iol:L2-15.2"               S
register nxos        docker ""                 "vrnetlab/cisco_nxostitanium:7.3.0.D1.1"   L
register c8000v-ctrl docker ""                 "vrnetlab/cisco_c8000v:controller-17.06.03" L
register c9800cl     docker ""                 "vrnetlab/cisco_c9800cl:17.17.01"          XL

usage() {
  echo "usage: $0 <name> [--extend-done]" >&2
  echo "  name: ${!IMGV_IMAGE[*]}" >&2
  exit 1
}

[ $# -ge 1 ] || usage
NAME="$1"
EXTEND_DONE="false"
[ "${2:-}" = "--extend-done" ] && EXTEND_DONE="true"

if [ -z "${IMGV_IMAGE[$NAME]:-}" ]; then
  echo "ERROR: 未知の name '${NAME}'" >&2
  usage
fi

MODE="${IMGV_MODE[$NAME]}"
IMAGE="${IMGV_IMAGE[$NAME]}"
CLASS="${IMGV_CLASS[$NAME]}"

case "$CLASS" in
  S)  RAM_GIB=2;  BOOT_TIMEOUT=300;  EXTEND_SEC=300  ;;
  M)  RAM_GIB=4;  BOOT_TIMEOUT=1800; EXTEND_SEC=900  ;;
  L)  RAM_GIB=6;  BOOT_TIMEOUT=3600; EXTEND_SEC=1800 ;;
  XL) RAM_GIB=10; BOOT_TIMEOUT=5400; EXTEND_SEC=1800 ;;
  *)  echo "ERROR: 未知のクラス '${CLASS}'" >&2; exit 1 ;;
esac

TOPO_FILE="${SCRIPT_DIR}/topos/imgv-${NAME}.clab.yml"
LOG_DIR="${HOME}/imgverify_logs/${NAME}"
mkdir -p "$LOG_DIR"

if [ "$MODE" = "clab" ]; then
  CONTAINER="clab-imgv-${NAME}-dut"
else
  CONTAINER="imgv-${NAME}"
fi

# ------------------------------------------------------------
# バージョン照合コマンド(機種によりCLI方言が異なるため個別対応)
# ------------------------------------------------------------
version_cmd_for() {
  case "$1" in
    routeros|chr7214) echo "/system resource print" ;;
    fortios)          echo "get system status" ;;
    *)                echo "show version" ;;
  esac
}

# ------------------------------------------------------------
# 機種別フック関数
# ------------------------------------------------------------

# routeros: REST API検証シーケンス(可逆変更込み)
hooks_routeros() {
  local ip="$1" user="$2" pass="$3" logdir="$4"

  ssh_cmd "$ip" "$user" "$pass" "/ip service print" 30 \
    > "${logdir}/hook_ros_service_before.log" 2>&1
  ssh_cmd "$ip" "$user" "$pass" "/ip service set www disabled=no" 30 \
    >> "${logdir}/hook_ros_service_before.log" 2>&1

  local resource base="http://${ip}"
  resource=$(rest_get "${base}/rest/system/resource" "$user" "$pass")
  printf '%s\n' "$resource" > "${logdir}/hook_ros_rest_resource.log"

  if [ -z "$resource" ] || printf '%s' "$resource" | grep -qi '404\|<html'; then
    # RouterOSのsshコマンド実行は1接続1コマンドが確実なため分割して投入
    ssh_cmd "$ip" "$user" "$pass" \
      '/certificate add name=local common-name=chr key-usage=key-cert-sign,digital-signature,key-encipherment,tls-server' \
      60 > "${logdir}/hook_ros_cert.log" 2>&1
    ssh_cmd "$ip" "$user" "$pass" '/certificate sign local' 60 >> "${logdir}/hook_ros_cert.log" 2>&1
    sleep 3
    ssh_cmd "$ip" "$user" "$pass" '/ip service set www-ssl certificate=local disabled=no' 60 \
      >> "${logdir}/hook_ros_cert.log" 2>&1
    resource=$(rest_get "https://${ip}/rest/system/resource" "$user" "$pass")
    printf '%s\n' "$resource" >> "${logdir}/hook_ros_rest_resource.log"
    # HTTPSフォールバックが成功したら以降のREST呼び出しもhttpsを使う
    if printf '%s' "$resource" | grep -q '"version"\|"board-name"'; then
      base="https://${ip}"
    fi
  fi

  rest_get "${base}/rest/interface" "$user" "$pass" \
    > "${logdir}/hook_ros_rest_interface.log"
  rest_get "${base}/rest/ip/address" "$user" "$pass" \
    > "${logdir}/hook_ros_rest_address.log"

  ssh_cmd "$ip" "$user" "$pass" "/export" 30 > "${logdir}/before.rsc" 2>&1

  local put_result addr new_id
  # interfaceは lo だと7.5に存在せず400になる(2026-07-17実測)。ether1は全CHRに存在し可逆
  put_result=$(rest_put "${base}/rest/ip/address" "$user" "$pass" \
    '{"address":"192.0.2.1/32","interface":"ether1"}')
  printf '%s\n' "$put_result" > "${logdir}/hook_ros_rest_put.log"

  addr=$(rest_get "${base}/rest/ip/address" "$user" "$pass")
  printf '%s\n' "$addr" > "${logdir}/hook_ros_rest_address_after_put.log"
  new_id=$(printf '%s' "$addr" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in data:
    if row.get("address") == "192.0.2.1/32":
        print(row.get(".id", ""))
        break
' 2>/dev/null)

  if [ -n "${new_id:-}" ]; then
    rest_delete "${base}/rest/ip/address/${new_id}" "$user" "$pass" \
      > "${logdir}/hook_ros_rest_delete.log" 2>&1
  fi

  ssh_cmd "$ip" "$user" "$pass" "/export" 30 > "${logdir}/after.rsc" 2>&1
  diff "${logdir}/before.rsc" "${logdir}/after.rsc" > "${logdir}/hook_ros_diff.log" 2>&1 || true

  rest_post "${base}/rest/system/identity/print" "$user" "$pass" '{}' \
    > "${logdir}/hook_ros_identity.log" 2>&1

  if [ -n "${new_id:-}" ]; then echo "ok"; else echo "ng"; fi
}

# csr17/c8000v: RESTCONF有効化→取得→無効化に戻す
hooks_restconf() {
  local ip="$1" user="$2" pass="$3" logdir="$4"
  local cmdfile_on="${logdir}/hook_restconf_enable_cmds.txt"

  { echo "conf t"; echo "restconf"; echo "ip http secure-server"; echo "end"; } \
    > "$cmdfile_on"
  ssh_interactive "$ip" "$user" "$pass" "$cmdfile_on" 90 \
    > "${logdir}/hook_restconf_enable.log"

  sleep 5
  local restconf_out
  restconf_out=$(curl -sk --max-time 20 -u "${user}:${pass}" \
    -H 'Accept: application/yang-data+json' \
    "https://${ip}/restconf/data/Cisco-IOS-XE-native:native/hostname" 2>&1)
  printf '%s\n' "$restconf_out" > "${logdir}/hook_restconf_get.log"

  local cmdfile_off="${logdir}/hook_restconf_disable_cmds.txt"
  { echo "conf t"; echo "no restconf"; echo "no ip http secure-server"; echo "end"; } \
    > "$cmdfile_off"
  ssh_interactive "$ip" "$user" "$pass" "$cmdfile_off" 90 \
    > "${logdir}/hook_restconf_disable.log"

  if printf '%s' "$restconf_out" | grep -qi "hostname"; then echo "ok"; else echo "ng"; fi
}

# vsrx: NETCONFバナー確認 + configure/commit check/rollback
hooks_vsrx() {
  local ip="$1" user="$2" pass="$3" logdir="$4"

  local netconf_banner
  netconf_banner=$(timeout 15 sshpass -p "$pass" ssh \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
    -p 830 "${user}@${ip}" -s netconf 2>&1 | head -1)
  printf '%s\n' "$netconf_banner" > "${logdir}/hook_vsrx_netconf_banner.log"

  local cmdfile="${logdir}/hook_vsrx_cmds.txt"
  {
    echo "configure"
    echo "set system host-name imgv-test"
    echo "commit check"
    echo "rollback 0"
    echo "exit"
  } > "$cmdfile"
  local out
  out=$(ssh_interactive "$ip" "$user" "$pass" "$cmdfile" 90)
  printf '%s\n' "$out" > "${logdir}/hook_vsrx_output.log"

  if printf '%s' "$netconf_banner" | grep -qi "netconf" \
     && printf '%s' "$out" | grep -qi "commit check"; then
    echo "ok"
  else
    echo "ng"
  fi
}

# fortios: hostname可逆変更
hooks_fortios() {
  local ip="$1" user="$2" pass="$3" logdir="$4"

  local orig_hostname
  orig_hostname=$(ssh_cmd "$ip" "$user" "$pass" "get system status" 30 2>/dev/null \
    | grep -i '^Hostname' | awk -F': *' '{print $2}' | head -1)
  [ -z "$orig_hostname" ] && orig_hostname="FortiGate-VM64"

  local cmdfile="${logdir}/hook_fortios_cmds.txt"
  {
    echo "config system global"
    echo "set hostname imgv-test"
    echo "end"
    echo "get system status"
    echo "config system global"
    echo "set hostname ${orig_hostname}"
    echo "end"
  } > "$cmdfile"
  local out
  out=$(ssh_interactive "$ip" "$user" "$pass" "$cmdfile" 90)
  printf '%s\n' "$out" > "${logdir}/hook_fortios_output.log"

  if printf '%s' "$out" | grep -qi "imgv-test"; then echo "ok"; else echo "ng"; fi
}

# vios/csr/c8000v/iol共通: hostname可逆変更(IOS方言)
hooks_iosish() {
  local name="$1" ip="$2" user="$3" pass="$4" logdir="$5"

  local orig_hostname
  orig_hostname=$(ssh_cmd "$ip" "$user" "$pass" "show running-config | include ^hostname" 30 2>/dev/null \
    | grep -oE '^hostname [^ ]+' | awk '{print $2}' | head -1)
  [ -z "$orig_hostname" ] && orig_hostname="Router"

  local cmdfile="${logdir}/hook_iosish_cmds.txt"
  {
    echo "conf t"
    echo "hostname imgv-test"
    echo "end"
    echo "show run | include hostname"
    echo "conf t"
    echo "hostname ${orig_hostname}"
    echo "end"
  } > "$cmdfile"
  local out
  out=$(ssh_interactive "$ip" "$user" "$pass" "$cmdfile" 90)
  printf '%s\n' "$out" > "${logdir}/hook_iosish_output.log"

  if printf '%s' "$out" | grep -q "hostname imgv-test"; then echo "ok"; else echo "ng"; fi
}

# ------------------------------------------------------------
# コマンド検証(commands/<name>.cmds、無ければdefault.cmds)
# ------------------------------------------------------------
# フォーマット: TAB区切り3フィールド(コマンド<TAB>期待regex<TAB>出典)、#行はコメント
run_cmds_verification() {
  local name="$1" ip="$2" user="$3" pass="$4" logdir="$5"
  local cmds_name="$name"
  # IOLの2タグはコマンド体系が同一のため iol.cmds を共用する
  # CHR 7.21.4 はRouterOS系のため routeros.cmds を共用する(バージョン行のみ個別判定)
  case "$name" in
    iol-*)   cmds_name="iol" ;;
    chr7214) cmds_name="routeros" ;;
  esac
  local cmds_file="${SCRIPT_DIR}/commands/${cmds_name}.cmds"
  [ -f "$cmds_file" ] || cmds_file="${SCRIPT_DIR}/commands/default.cmds"

  local total=0 pass_count=0
  while IFS=$'\t' read -r cmd expect origin || [ -n "${cmd:-}" ]; do
    [ -z "${cmd:-}" ] && continue
    case "$cmd" in "#"*) continue ;; esac

    total=$((total + 1))
    local out
    out=$(ssh_cmd "$ip" "$user" "$pass" "$cmd" 60 2>&1)
    printf '%s\n' "$out" > "${logdir}/cmd_${total}.log"
    if printf '%s' "$out" | grep -qE "$expect"; then
      pass_count=$((pass_count + 1))
    fi
    unset origin
  done < "$cmds_file"

  CMDS_PASS="$pass_count"
  CMDS_TOTAL="$total"
}

# ------------------------------------------------------------
# バージョン一致判定(imageタグの主要バージョン番号が出力に含まれるか)
# ------------------------------------------------------------
compute_version_match() {
  local image="$1" output="$2"
  local tag ver_frag
  tag="${image##*:}"
  # 数字のみダッシュ区切りのタグ(例: asavの 9-18-1)はドット区切りへ正規化
  if printf '%s' "$tag" | grep -qE '^[0-9]+(-[0-9]+)+$'; then
    tag=$(printf '%s' "$tag" | tr '-' '.')
  fi
  ver_frag=$(printf '%s' "$tag" | grep -oE '[0-9]+\.[0-9]+' | head -1)

  if [ -z "$ver_frag" ]; then
    echo "n/a"
    return
  fi
  if printf '%s' "$output" | grep -qF "$ver_frag"; then
    echo "yes"
  else
    echo "no"
  fi
}

# ------------------------------------------------------------
# docker network "imgv" が無ければ作成(dockerモード用)
# ------------------------------------------------------------
ensure_imgv_network() {
  if ! docker network inspect imgv >/dev/null 2>&1; then
    docker network create --subnet 172.20.60.0/24 imgv
  fi
}

# ============================================================
# メインフロー
# ============================================================
check_labs_intact

if ! ( ram_gate "$RAM_GIB" ); then
  append_result "$IMAGE" "$CLASS" "-" "-" "-" "n/a" "NG-RESOURCE" 0 "ram-insufficient"
  scrub "$RESULTS_FILE"
  exit 2
fi

case "$NAME" in
  iol-1563|iol-l2152)
    if ! ( ensure_iourc "$IMAGE" ); then
      append_result "$IMAGE" "$CLASS" "-" "-" "-" "n/a" "NG" 0 "iourc-extract-failed"
      scrub "$RESULTS_FILE"
      exit 1
    fi
    ;;
esac

START_TS=$(date +%s)

DEPLOY_OK="true"
if [ "$MODE" = "clab" ]; then
  # deploy自体がノードのreadiness待ちでブロックすることがあるため上限を設ける
  # (タイムアウトで中断されてもコンテナは残り、wait_boot以降で拾える)
  timeout $((BOOT_TIMEOUT + EXTEND_SEC + 300)) \
    sudo containerlab deploy -t "$TOPO_FILE" --reconfigure < /dev/null
  DEPLOY_RC=$?
  if [ "$DEPLOY_RC" -eq 124 ]; then
    echo "WARNING: deployがタイムアウトしました。コンテナ状態をwait_bootで再判定します。"
  elif [ "$DEPLOY_RC" -ne 0 ]; then
    DEPLOY_OK="false"
  fi
else
  ensure_imgv_network
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  # QEMU_CPU=max: KVM無しホストでは既定の -cpu host がqemu即死を招くため必須(2026-07-17判明)
  docker run -d --privileged -e QEMU_CPU=max --network imgv --name "$CONTAINER" "$IMAGE" >/dev/null \
    || DEPLOY_OK="false"
fi

VERDICT=""
NOTES=""
BOOT_STATE=""

if [ "$DEPLOY_OK" != "true" ]; then
  VERDICT="NG"
  NOTES="deploy-failed"
else
  if wait_boot "$CONTAINER" "$BOOT_TIMEOUT"; then
    BOOT_STATE="$WAIT_BOOT_RESULT"
  else
    if [ "$EXTEND_DONE" = "false" ]; then
      JUDGE=$(judge_boot_failure "$CONTAINER")
      if [ "$JUDGE" = "still-booting" ]; then
        echo "起動継続中と判断し ${EXTEND_SEC}秒延長します。"
        if wait_boot "$CONTAINER" "$EXTEND_SEC"; then
          BOOT_STATE="$WAIT_BOOT_RESULT"
        else
          BOOT_STATE="timeout"
        fi
      else
        BOOT_STATE="failed"
      fi
    else
      BOOT_STATE="timeout"
    fi
  fi

  if [ "$BOOT_STATE" = "failed" ] || [ "$BOOT_STATE" = "timeout" ]; then
    VERDICT="NG"
    NOTES="boot=${BOOT_STATE}"
  fi
fi

# ------------------------------------------------------------
# 起動成功時のみ: アクセス/コマンド検証/機種別フック
# ------------------------------------------------------------
ACCESS_OK="false"
SSH_USER=""
SSH_PASS=""
ACCESS_OUTPUT=""
CMDS_PASS=0
CMDS_TOTAL=0
VERSION_MATCH="n/a"
HOOK_NOTES=""
HOOK_ALL_OK="true"

run_hook() {
  local hook_name="$1" result
  shift
  result=$("$@")
  HOOK_NOTES="${HOOK_NOTES}${hook_name}=${result} "
  [ "$result" != "ok" ] && HOOK_ALL_OK="false"
}

if [ -z "$VERDICT" ]; then
  IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)

  declare -a CRED_USERS=(admin)
  declare -a CRED_PASSES=(admin)
  case "$NAME" in
    routeros) CRED_USERS+=(admin); CRED_PASSES+=("") ;;
    vsrx)     CRED_USERS+=(admin); CRED_PASSES+=("admin@123") ;;
    # asav: ASAのパスワード複雑性要件により、bootstrapは admin/CiscoAsa1! を作る(2026-07-17実測、launch.py L16)
    asav)    CRED_USERS+=(admin vrnetlab); CRED_PASSES+=("CiscoAsa1!" "VR-netlab9") ;;
    fortios) CRED_USERS+=(vrnetlab); CRED_PASSES+=("VR-netlab9") ;;
  esac

  # healthy直後はSSHデーモンがまだ上がっていない機種があるため、リトライ付きで試行
  ACCESS_RETRIES=5
  ACCESS_INTERVAL=30
  if [ -n "${IP:-}" ]; then
    VCMD=$(version_cmd_for "$NAME")
    for attempt in $(seq 1 "$ACCESS_RETRIES"); do
      for idx in "${!CRED_USERS[@]}"; do
        u="${CRED_USERS[$idx]}"
        p="${CRED_PASSES[$idx]}"
        out=$(ssh_cmd "$IP" "$u" "$p" "$VCMD" 30 2>&1)
        rc=$?
        if [ $rc -eq 0 ] && ! printf '%s' "$out" | grep -qiE 'permission denied|connection refused|no route to host'; then
          ACCESS_OK="true"
          SSH_USER="$u"
          SSH_PASS="$p"
          ACCESS_OUTPUT="$out"
          printf '%s\n' "$out" > "${LOG_DIR}/access_version.log"
          break 2
        fi
        # 失敗時の出力も診断用に残す(最後の試行分)
        printf 'attempt=%s user=%s rc=%s\n%s\n' "$attempt" "$u" "$rc" "$out" > "${LOG_DIR}/access_fail_last.log"
      done
      [ "$attempt" -lt "$ACCESS_RETRIES" ] && sleep "$ACCESS_INTERVAL"
    done
  fi

  if [ "$ACCESS_OK" = "true" ]; then
    VERSION_MATCH=$(compute_version_match "$IMAGE" "$ACCESS_OUTPUT")

    run_cmds_verification "$NAME" "$IP" "$SSH_USER" "$SSH_PASS" "$LOG_DIR"

    case "$NAME" in
      routeros|chr7214) run_hook "routeros-rest" hooks_routeros "$IP" "$SSH_USER" "$SSH_PASS" "$LOG_DIR" ;;
      vsrx)     run_hook "vsrx-netconf" hooks_vsrx "$IP" "$SSH_USER" "$SSH_PASS" "$LOG_DIR" ;;
      fortios)  run_hook "fortios-hostname" hooks_fortios "$IP" "$SSH_USER" "$SSH_PASS" "$LOG_DIR" ;;
    esac
    case "$NAME" in
      vios|viosl2|csr16|csr17|c8000v|iol-1563|iol-l2152)
        run_hook "iosish-hostname" hooks_iosish "$NAME" "$IP" "$SSH_USER" "$SSH_PASS" "$LOG_DIR"
        ;;
    esac
    case "$NAME" in
      csr17|c8000v) run_hook "restconf" hooks_restconf "$IP" "$SSH_USER" "$SSH_PASS" "$LOG_DIR" ;;
    esac

    if [ "$CMDS_TOTAL" -gt 0 ] && [ "$CMDS_PASS" -eq "$CMDS_TOTAL" ] && [ "$HOOK_ALL_OK" = "true" ]; then
      VERDICT="FULL"
    else
      VERDICT="PARTIAL"
    fi
    NOTES="boot=${BOOT_STATE} access=ok(${SSH_USER}) cmds=${CMDS_PASS}/${CMDS_TOTAL} ${HOOK_NOTES}"
  else
    VERDICT="BOOT_ONLY"
    NOTES="boot=${BOOT_STATE} access=ng"
  fi
fi

# ------------------------------------------------------------
# 後処理: destroy + 残骸確認 + 既存ラボ健全性確認
# ------------------------------------------------------------
if [ "$DEPLOY_OK" = "true" ]; then
  # 破棄前に診断用ログを全量収集(VM側LOG_DIRのみ、リポジトリへは出さない)
  # tail 100では原因究明に不足した実績(2026-07-17 veos/csr17)があるため全量
  docker logs "$CONTAINER" > "${LOG_DIR}/docker_logs_full.log" 2>&1 || true
  tail -100 "${LOG_DIR}/docker_logs_full.log" > "${LOG_DIR}/docker_logs_tail.log" 2>/dev/null || true
  if [ "$MODE" = "clab" ]; then
    sudo containerlab destroy -t "$TOPO_FILE" --cleanup < /dev/null
  else
    docker rm -f "$CONTAINER" >/dev/null 2>&1
  fi
fi

sleep 3
if pgrep -f "qemu.*${NAME}" >/dev/null 2>&1; then
  echo "WARNING: destroy後もqemuプロセス残骸が検出されました (${NAME})。手動確認してください。" >&2
  NOTES="${NOTES} qemu-residue-warning"
fi

check_labs_intact

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))

append_result "$IMAGE" "$CLASS" "$BOOT_STATE" "$ACCESS_OK" "${CMDS_PASS}/${CMDS_TOTAL}" \
  "$VERSION_MATCH" "$VERDICT" "$DURATION" "$NOTES"
scrub "$RESULTS_FILE"

echo "結果: ${NAME} -> ${VERDICT} (duration=${DURATION}s)"
exit 0
