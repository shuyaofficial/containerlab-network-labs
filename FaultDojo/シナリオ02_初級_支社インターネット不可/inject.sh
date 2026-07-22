#!/bin/bash
set -euo pipefail
# =============================================================================
# NW Fault Dojo — シナリオ02 障害注入スクリプト
#  - clab VM 内で実行する想定: sudo bash inject.sh
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

PAYLOAD_B64_1="Y29uZiB0Cm5vIGlwIG5hdCBpbnNpZGUgc291cmNlIGxpc3QgMSBpbnRlcmZhY2UgRXRoZXJuZXQwLzEgb3ZlcmxvYWQKaXAgbmF0IHNvdXJjZSBsaXN0IDEgaW50ZXJmYWNlIEV0aGVybmV0MC8xIG92ZXJsb2FkCmVuZAo="

fail() {
  echo "注入失敗。切り戻し・完全リセット手順.md を参照してください。"
  exit 1
}

trap fail ERR

echo "[1/1] 対象機器へ注入中..."

ip=$(getip br-edge)
if [ -z "$ip" ]; then fail; fi
wait_ssh "$ip" br-edge || fail
printf '%s' "$PAYLOAD_B64_1" | base64 -d | sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ip" > /dev/null 2>&1

echo "注入完了。ブリーフィングに従い切り分けを開始してください。"
