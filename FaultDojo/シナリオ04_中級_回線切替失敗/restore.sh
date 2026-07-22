#!/bin/bash
set -euo pipefail
# =============================================================================
# NW Fault Dojo — シナリオ04 切り戻しスクリプト
#  - clab VM 内で実行する想定: sudo bash restore.sh
#  - SSH_OPTS / getip() / wait_ssh() は 21_cisco_capstone/configure_all.sh と同一方式。
#  - ペイロードは base64 化されており、復号後にSSH経由で対象機器へ流し込む。
# =============================================================================

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
-o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
USER=admin
PASS=admin

# コンテナ名から管理IPv4を解決
getip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "clab-capstone-$1" 2>/dev/null
}

# SSHが立ち上がるまで待機
wait_ssh() {
  local ip=$1 name=$2 i
  for i in $(seq 1 60); do
    if sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ip" "exit" </dev/null 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  echo "[FAIL] $name ($ip): SSH not reachable"; return 1
}

PAYLOAD_B64_1="Y29uZiB0CmludGVyZmFjZSBlMC8yCiBpcCBuYXQgaW5zaWRlCmludGVyZmFjZSBlMC8zCiBpcCBuYXQgaW5zaWRlCmVuZAo="
PAYLOAD_B64_2="Y29uZiB0CmludGVyZmFjZSBlMC8xCiBubyBzaHV0ZG93bgplbmQK"

fail() {
  echo "切り戻し失敗。../02_ベースライン/切り戻し・完全リセット手順.md を参照してください。"
  exit 1
}

trap fail ERR

echo "[1/2] 対象機器を切り戻し中..."

ip1=$(getip hq-edge2)
if [ -z "$ip1" ]; then fail; fi
wait_ssh "$ip1" hq-edge2 || fail
printf '%s' "$PAYLOAD_B64_1" | base64 -d | sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ip1" > /dev/null 2>&1

echo "[2/2] 計画メンテ状態を解除中..."

ip2=$(getip hq-edge1)
if [ -z "$ip2" ]; then fail; fi
wait_ssh "$ip2" hq-edge1 || fail
printf '%s' "$PAYLOAD_B64_2" | base64 -d | sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ip2" > /dev/null 2>&1

echo "切り戻し完了。ベースライン健全性チェックを再実行してください。"
