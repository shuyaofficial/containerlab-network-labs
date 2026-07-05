#!/usr/bin/env bash
# N4 マイクロセグメンテーション（nftables/IOL VLAN・ACL 版）deploy スクリプト
# 重要: IOL のデータプレーンは iouyap を起動しないとフレームが一切通らない
#       （テーマ22/26/31 と同じ落とし穴。未起動だと sw1↔端末 全断）
set -euo pipefail
cd "$(dirname "$0")"

TOPO="microseg.clab.yml"
NAME_PREFIX="clab-microseg-"
ENDPOINT_IMAGE="microseg-endpoint:local"

PC10A="${NAME_PREFIX}pc10a"
PC10B="${NAME_PREFIX}pc10b"
SRV20="${NAME_PREFIX}srv20"
SW1="${NAME_PREFIX}sw1"

build_image() {
  sudo docker build -t "$ENDPOINT_IMAGE" ./endpoint
}

start_iouyap() {
  # IOL ノード（sw1）で iouyap を起動。ポート 513 は NETMAP 由来（全テーマ共通実績）。
  sleep 5
  for c in $(sudo docker ps --format '{{.Names}}' \
      | grep "^${NAME_PREFIX}" | grep -vE 'pc10a$|pc10b$|srv20$'); do
    sudo docker exec -d -w /iol "$c" /usr/bin/iouyap 513 2>/dev/null || true
    echo "iouyap started on $c"
  done
}

fix_dataplane() {
  # Linux 側データ IF のオフロードを無効化（IOL 系の取りこぼし対策の保険）
  for c in pc10a pc10b srv20; do
    pid=$(sudo docker inspect -f '{{.State.Pid}}' "${NAME_PREFIX}${c}" 2>/dev/null) || continue
    sudo nsenter -t "$pid" -n ethtool -K eth1 rx off tx off gso off gro off tso off 2>/dev/null || true
  done
}

setup_endpoints() {
  # 端末 IP/GW 設定とサーバサービス起動
  sudo docker exec "$PC10A" ip addr add 172.50.10.11/24 dev eth1 2>/dev/null || true
  sudo docker exec "$PC10A" ip link set eth1 up
  sudo docker exec "$PC10A" ip route replace default via 172.50.10.1

  sudo docker exec "$PC10B" ip addr add 172.50.10.12/24 dev eth1 2>/dev/null || true
  sudo docker exec "$PC10B" ip link set eth1 up
  sudo docker exec "$PC10B" ip route replace default via 172.50.10.1

  sudo docker exec "$SRV20" ip addr add 172.50.20.11/24 dev eth1 2>/dev/null || true
  sudo docker exec "$SRV20" ip link set eth1 up
  sudo docker exec "$SRV20" ip route replace default via 172.50.20.1

  # srv20: http/80 (python http.server) と tcp/22 疑似サービス (ncat) を常駐起動
  sudo docker exec -d -w /srv/www "$SRV20" python3 -m http.server 80
  sudo docker exec -d "$SRV20" ncat -lk -p 22 -c 'echo MICROSEG-SRV20-SSH-OK'
  echo "endpoints configured: pc10a=172.50.10.11 pc10b=172.50.10.12 srv20=172.50.20.11"
}

wait_for_switch() {
  # sw1 のコンソールが応答するまで待つ（IOL boot 待ち）
  sleep 15
}

run_test() {
  local log="test_$(date +%Y%m%d_%H%M%S).log"
  {
    echo "=== G2: inter-VLAN ACL (pc10a -> srv20) ==="
    echo "--- pc10a -> srv20:80 (期待: 到達/200) ---"
    sudo docker exec "$PC10A" curl -s -o /dev/null -w 'HTTP=%{http_code}\n' --max-time 5 http://172.50.20.11:80/ || echo "HTTP=000(blocked)"
    echo "--- pc10a -> srv20:22 (期待: 遮断) ---"
    sudo docker exec "$PC10A" bash -c "timeout 5 bash -c '</dev/tcp/172.50.20.11/22' && echo REACHABLE || echo BLOCKED" 2>&1 || true

    echo ""
    echo "=== G3: intra-VLAN10 host nftables (pc10a -> pc10b) ==="
    echo "--- nftables 適用前: pc10a -> pc10b ping (期待: 到達) ---"
    sudo docker exec "$PC10A" ping -c 3 -W 2 172.50.10.12 || true
  } | tee "$log"
  echo "test log: $log"
}

apply_nft() {
  # 層2: pc10b で pc10a からの着信を drop（同一VLAN内の横移動遮断）
  sudo docker exec "$PC10B" nft add table inet filter 2>/dev/null || true
  sudo docker exec "$PC10B" nft add chain inet filter input '{ type filter hook input priority 0 ; policy accept ; }' 2>/dev/null || true
  sudo docker exec "$PC10B" nft add rule inet filter input ip saddr 172.50.10.11 counter drop
  echo "nftables applied on pc10b: drop from 172.50.10.11"
  sudo docker exec "$PC10B" nft list ruleset
}

flush_nft() {
  sudo docker exec "$PC10B" nft flush ruleset 2>/dev/null || true
  echo "nftables flushed on pc10b"
}

test_g3_after() {
  local log="test_g3_after_$(date +%Y%m%d_%H%M%S).log"
  {
    echo "=== G3: nftables 適用後: pc10a -> pc10b ping (期待: 遮断) ==="
    sudo docker exec "$PC10A" ping -c 3 -W 2 172.50.10.12 || true
    echo ""
    echo "--- pc10b nft ruleset (counter確認) ---"
    sudo docker exec "$PC10B" nft list ruleset
  } | tee "$log"
  echo "test log: $log"
}

case "${1:-deploy}" in
  deploy)
    build_image
    sudo containerlab deploy -t "$TOPO"
    start_iouyap
    fix_dataplane
    wait_for_switch
    setup_endpoints
    echo "--- 次はスイッチ設定投入: sudo expect run_microseg.exp ${SW1} sw1_microseg.cfg ---"
    ;;
  iouyap)
    start_iouyap
    fix_dataplane
    ;;
  config)
    sudo expect run_microseg.exp "$SW1" sw1_microseg.cfg
    ;;
  nft)
    apply_nft
    ;;
  nft-flush)
    flush_nft
    ;;
  test)
    run_test
    ;;
  test-g3-after)
    test_g3_after
    ;;
  inspect)
    sudo containerlab inspect -t "$TOPO"
    ;;
  destroy)
    sudo containerlab destroy -t "$TOPO" --cleanup
    ;;
  *)
    echo "usage: $0 {deploy|iouyap|config|nft|nft-flush|test|test-g3-after|inspect|destroy}" >&2
    exit 1
    ;;
esac
