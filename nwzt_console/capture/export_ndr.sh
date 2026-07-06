#!/usr/bin/env bash
# NW-ZT Console ライブ更新 — N3 NDR (42_ndr_flow) の実データ採取
#
# 42_ndr_flow が稼働中（attacker/victim/suricata コンテナが存在）なら、
# suricata の eve.json から alert(event_type=alert) / flow(event_type=flow) を
# 集計し、data.js の ndr セクションと同じ構造の JSON を stdout に出す。
# 停止中なら {"status":"stopped"} を返す。
#
# 前提: Mac 側から `ssh clab@orb` で OrbStack VM (arm64) に到達可能。
#       eve.json は 42_ndr_flow/04_構築/deploy.sh の LOGDIR
#       (=このリポジトリと同一パスで VM にもマウント済み) にある。
set -euo pipefail

REMOTE="clab@orb"
REQUIRED_CONTAINERS=(attacker victim suricata)
NDR_ROOT="/Users/shuya/Documents/claude/Mac仮想環境構築/42_ndr_flow/04_構築"
EVE="${NDR_ROOT}/suricata/log/eve.json"

running_names() {
  ssh "$REMOTE" "sudo docker ps --format '{{.Names}}'" 2>/dev/null
}

NAMES="$(running_names || true)"

is_running() {
  for c in "${REQUIRED_CONTAINERS[@]}"; do
    printf '%s\n' "$NAMES" | grep -qx "$c" || return 1
  done
  return 0
}

if [ -z "$NAMES" ] || ! is_running; then
  echo '{"status":"stopped"}'
  exit 0
fi

if ! ssh "$REMOTE" "sudo test -s '${EVE}'" 2>/dev/null; then
  echo '{"status":"stopped"}'
  exit 0
fi

# eve.json は VM 側にも同一パスでマウントされているため sudo cat で読む。
EVE_CONTENT=$(ssh "$REMOTE" "sudo cat '${EVE}'" 2>/dev/null || true)

if [ -z "$EVE_CONTENT" ]; then
  echo '{"status":"stopped"}'
  exit 0
fi

# alert/flow の件数・重大度別カウント（jq で集計、壊れた行は無視）。
# flow は east-west（IPv4/TCP・監視サブネット内）のみを対象にする。
# IPv6 の ICMPv6/MLD 等の管理ノイズは east-west 可視化の対象外のため除外する。
ALERTS_JSON=$(printf '%s\n' "$EVE_CONTENT" | jq -c 'select(.event_type=="alert")' 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')
FLOWS_JSON=$(printf '%s\n' "$EVE_CONTENT" | jq -c 'select(.event_type=="flow" and .ip_v==4 and .proto=="TCP")' 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')
FLOWS_COUNT=$(printf '%s' "$FLOWS_JSON" | jq 'length' 2>/dev/null || echo 0)

ALERTS_COUNT=$(printf '%s' "$ALERTS_JSON" | jq 'length' 2>/dev/null || echo 0)
CRITICAL_COUNT=$(printf '%s' "$ALERTS_JSON" | jq '[.[] | select(.alert.severity==1)] | length' 2>/dev/null || echo 0)
HIGH_COUNT=$(printf '%s' "$ALERTS_JSON" | jq '[.[] | select(.alert.severity==2)] | length' 2>/dev/null || echo 0)
MEDIUM_COUNT=$(printf '%s' "$ALERTS_JSON" | jq '[.[] | select(.alert.severity==3)] | length' 2>/dev/null || echo 0)

SEV_LABEL() {
  case "$1" in
    1) echo "重大" ;;
    2) echo "高" ;;
    3) echo "中" ;;
    *) echo "低" ;;
  esac
}

# alert を signature_id ごとに代表1件へ集約（severity昇順=重大優先、最大5種）。
# 同一 sid が閾値内で複数回発報しても一覧では1件に見せる（data.js の元設計に合わせる）。
ALERTS_ARR=$(printf '%s' "$ALERTS_JSON" | jq -c '
  group_by(.alert.signature_id)
  | map(.[0])
  | sort_by(.alert.severity)
  | .[0:5]
  | map({
      sid: .alert.signature_id,
      sig: .alert.signature,
      src: .src_ip,
      dst: .dest_ip,
      proto: .proto,
      severity: .alert.severity,
      sevLabel: (if .alert.severity==1 then "重大" elif .alert.severity==2 then "高" elif .alert.severity==3 then "中" else "低" end),
      iface: .in_iface,
      note: .alert.category
    })' 2>/dev/null || echo '[]')

# top talkers（east-west flow の src→dst 件数上位1件。IPv4/TCP のみ、上で除外済み）
TOP_TALKER=$(printf '%s' "$FLOWS_JSON" | jq -c '
    group_by([.src_ip, .dest_ip])
    | map({src: .[0].src_ip, dst: .[0].dest_ip, flows: length})
    | sort_by(-.flows)
    | .[0]
  ' 2>/dev/null || echo 'null')

if [ "$TOP_TALKER" = "null" ] || [ -z "$TOP_TALKER" ]; then
  TOP_TALKERS_ARR='[]'
else
  TOP_TALKERS_ARR=$(printf '%s' "$TOP_TALKER" | jq -c '[. + {kind: "SYN スキャン（1→多ポート）"}]')
fi

[ "$ALERTS_COUNT" -eq 0 ] && ALERTS_COUNT=0
[ "$FLOWS_COUNT" -eq 0 ] && FLOWS_COUNT=0

jq -n \
  --argjson alerts_count "$ALERTS_COUNT" \
  --argjson flows_count "$FLOWS_COUNT" \
  --argjson critical "$CRITICAL_COUNT" \
  --argjson high "$HIGH_COUNT" \
  --argjson medium "$MEDIUM_COUNT" \
  --argjson alerts "$ALERTS_ARR" \
  --argjson topTalkers "$TOP_TALKERS_ARR" \
  '{
    status: "running",
    theme: "42_ndr_flow",
    title: "脅威・フロー（NDR / east-west 可視化）",
    commercial: "Darktrace / Cisco Secure Network Analytics",
    oss: "Suricata + Loki / Grafana",
    summary: { alerts: $alerts_count, flows: $flows_count, critical: $critical, high: $high, medium: $medium },
    alerts: $alerts,
    topTalkers: $topTalkers,
    proof: "docker bridge を host mode Suricata で監視。SYN スキャンを DPI(alert) とフロー(flow) の両面で捕捉。"
  }'
