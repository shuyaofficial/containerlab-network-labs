#!/usr/bin/env bash
# mvlabラボへのMac直接到達(02_ping等ICMP/HTTP用)を有効化する。sudoで1回実行。
# SSH(mv-*エイリアス)とツール06/05/07はこのスクリプト不要。
set -euo pipefail
VM_IP=$(ssh -o BatchMode=yes clab@orb "ip -4 addr show dev eth0 | grep -oE '192\.168\.[0-9.]+' | head -1")
echo "OrbStack VM IP: $VM_IP"
if netstat -rn | grep -q "^172.20.50"; then
  echo "既存ルートを更新します"
  sudo route -n delete -net 172.20.50.0/24 >/dev/null 2>&1 || true
fi
sudo route -n add -net 172.20.50.0/24 "$VM_IP"
echo "追加しました。疎通確認:"
ping -c 2 -W 2000 172.20.50.21 || echo "NG: ラボが起動しているか(./deploy.sh deploy)、VM側iptables許可を確認してください"
echo "注意: このルートはMac再起動で消えます。必要時に再実行してください。"
