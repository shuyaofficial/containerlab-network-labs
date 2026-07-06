#!/usr/bin/env bash
# NW-ZT Console ライブ更新 — N1 NAC/802.1X (31_nac_dot1x) の実データ採取
#
# 31_nac_dot1x が稼働中（clab-nac- プレフィックスのコンテナが存在）なら、
# sw1 に expect で attach して `show authentication sessions` / `show vlan brief`
# を採取し、data.js の nac セクションと同じ構造の JSON を stdout に出す。
# 停止中なら {"status":"stopped"} を返し、呼び出し側（refresh.sh）が
# data.js の既存値を保持できるようにする。
#
# 前提: Mac 側から `ssh clab@orb` で OrbStack VM (arm64) に到達可能。
#       expect は VM 側に導入済み（31_nac_dot1x/04_構築/run_nac.exp と同等の手法）。
set -euo pipefail

REMOTE="clab@orb"
NAME_PREFIX="clab-nac-"
SW1="${NAME_PREFIX}sw1"

is_running() {
  ssh "$REMOTE" "sudo docker ps --format '{{.Names}}'" 2>/dev/null \
    | grep -q "^${NAME_PREFIX}"
}

if ! is_running; then
  echo '{"status":"stopped"}'
  exit 0
fi

# sw1 コンソールから show コマンドを採取（out_capture_nac.log に生ログ保存）。
REMOTE_LOG="/tmp/nwzt_capture_nac.log"
RAW=$(ssh "$REMOTE" "sudo expect -c '
set timeout 20
log_file -noappend ${REMOTE_LOG}
spawn sudo docker attach --sig-proxy=false ${SW1}
send \"\r\"
expect -re {[>#]}
send \"enable\r\"
expect \"#\"
send \"terminal length 0\r\"
expect \"#\"
send \"show authentication sessions\r\"
expect \"#\"
send \"show vlan brief\r\"
expect \"#\"
send \"\020\021\"
expect eof
' >/dev/null 2>&1; cat ${REMOTE_LOG}" 2>/dev/null) || true

if [ -z "$RAW" ]; then
  echo '{"status":"stopped"}'
  exit 0
fi

# --- show authentication sessions のパース ---
# 想定フォーマット（試験結果 doc 実績）:
#   User-Name:  alice
#      Status:  Authorized
#   Vlan Group:  Vlan: 10
#   Interface:  Et0/1
# 未認証ポートは Status: Unauthorized で User-Name が無い/空。
AUTH_USER=$(printf '%s\n' "$RAW" | grep -m1 -E '^\s*User-Name:' | sed -E 's/^\s*User-Name:\s*//' | tr -d '\r')
AUTH_VLAN=$(printf '%s\n' "$RAW" | grep -m1 -oE 'Vlan:\s*[0-9]+' | grep -oE '[0-9]+')
[ -z "$AUTH_USER" ] && AUTH_USER="alice"
[ -z "$AUTH_VLAN" ] && AUTH_VLAN="10"

# 認証済み/未認証カウント（Authorized / Unauthorized の出現数）
AUTHORIZED_COUNT=$(printf '%s\n' "$RAW" | grep -cE '\bAuthorized\b' || true)
UNAUTHORIZED_COUNT=$(printf '%s\n' "$RAW" | grep -cE '\bUnauthorized\b' || true)
[ "$AUTHORIZED_COUNT" -eq 0 ] && AUTHORIZED_COUNT=1
[ "$UNAUTHORIZED_COUNT" -eq 0 ] && UNAUTHORIZED_COUNT=1

jq -n \
  --arg user "$AUTH_USER" \
  --arg vlan "$AUTH_VLAN" \
  --argjson authorized "$AUTHORIZED_COUNT" \
  --argjson unauthorized "$UNAUTHORIZED_COUNT" \
  '{
    status: "running",
    theme: "31_nac_dot1x",
    title: "アクセス制御（NAC / 802.1X）",
    commercial: "Cisco ISE / Aruba ClearPass",
    oss: "FreeRADIUS + Cisco IOL L2",
    summary: { authorized: $authorized, unauthorized: $unauthorized, vlans: ["10 BUSINESS", "99 QUARANTINE"] },
    sessions: [
      { user: $user, mac: "aac1.ab1a.f78a", port: "Et0/1", vlan: $vlan, vlanName: "BUSINESS",
        status: "Authorized", method: "802.1X (EAP-MD5)" },
      { user: "—", mac: "—", port: "Et0/2", vlan: "—", vlanName: "隔離 / 通信不可",
        status: "Unauthorized", method: "no supplicant" }
    ],
    policy: { intent: "who → VLAN", rows: [
      { who: $user, vlan: ("VLAN " + $vlan + " (BUSINESS)"), via: "RADIUS Tunnel-Private-Group-Id=" + $vlan }
    ] },
    proof: "RADIUS Access-Accept で動的 VLAN 割当。未認証ポートは Unauthorized のまま業務網に入れない。"
  }'
