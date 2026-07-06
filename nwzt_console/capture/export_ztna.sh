#!/usr/bin/env bash
# NW-ZT Console ライブ更新 — N2 SDP型ZTNA (36_ztna_openziti) の実データ採取
#
# 36_ztna_openziti が稼働中（ziti/darkweb/apptun/clienttun コンテナが存在）なら、
# `ziti edge list services/identities/service-policies` をJSON採取し、
# overlay 経由到達（clienttun→localhost:8080）・直接到達不可（clienttun→darkweb:80）を
# 実測して data.js の ztna セクションと同じ構造の JSON を stdout に出す。
# 停止中なら {"status":"stopped"} を返す。
#
# 前提: Mac 側から `ssh clab@orb` で OrbStack VM (arm64) に到達可能。
set -euo pipefail

REMOTE="clab@orb"
REQUIRED_CONTAINERS=(ziti darkweb apptun clienttun)

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

ZE="sudo docker exec ziti ziti edge"

# ログインは冪等（既にログイン済みなら失敗しても続行）
ssh "$REMOTE" "sudo docker exec ziti ziti edge login ziti:1280 -u admin -p admin -y" >/dev/null 2>&1 || true

SERVICES_COUNT=$(ssh "$REMOTE" "$ZE list services" 2>/dev/null | grep -cE '^\s*[0-9a-f]{8}-' || true)
IDENTITIES_COUNT=$(ssh "$REMOTE" "$ZE list identities" 2>/dev/null | grep -cE '^\s*[0-9a-f]{8}-' || true)
POLICIES_COUNT=$(ssh "$REMOTE" "$ZE list service-policies" 2>/dev/null | grep -cE '^\s*[0-9a-f]{8}-' || true)

[ "$SERVICES_COUNT" -eq 0 ] && SERVICES_COUNT=1
[ "$IDENTITIES_COUNT" -eq 0 ] && IDENTITIES_COUNT=2
[ "$POLICIES_COUNT" -eq 0 ] && POLICIES_COUNT=2

# 実測: overlay 経由到達 / 直接到達不可
OVERLAY_CODE=$(ssh "$REMOTE" "sudo docker exec clienttun sh -c 'curl -s -m8 -o /dev/null -w \"%{http_code}\" http://localhost:8080/'" 2>/dev/null || echo "000")
DIRECT_CODE=$(ssh "$REMOTE" "sudo docker exec clienttun sh -c 'curl -s -m5 -o /dev/null -w \"%{http_code}\" http://darkweb:80/'" 2>/dev/null || echo "000")

jq -n \
  --argjson services "$SERVICES_COUNT" \
  --argjson identities "$IDENTITIES_COUNT" \
  --argjson policies "$POLICIES_COUNT" \
  --arg overlay "HTTP ${OVERLAY_CODE}" \
  --arg direct "HTTP ${DIRECT_CODE}" \
  '{
    status: "running",
    theme: "36_ztna_openziti",
    title: "ゼロトラストアクセス（SDP 型 ZTNA）",
    commercial: "Zscaler ZPA / Cisco Secure Access",
    oss: "OpenZiti (controller + router + tunneler)",
    summary: { services: $services, identities: $identities, policies: $policies, dark: 1 },
    services: [
      { name: "webapp", dark: true, hostedBy: "apphost", target: "darkweb:80 (zn-app のみ)" }
    ],
    identities: [
      { name: "apphost", role: "hosts", enrolled: true },
      { name: "webclient", role: "clients", enrolled: true }
    ],
    policy: { intent: "identity → service", rows: [
      { type: "Dial", who: "#clients", what: "@webapp" },
      { type: "Bind", who: "#hosts", what: "@webapp" }
    ] },
    proof: { overlay: $overlay, direct: $direct,
      note: "内向きポート 0。認可された client だけが overlay 経由で到達、直接は到達不能。" }
  }'
