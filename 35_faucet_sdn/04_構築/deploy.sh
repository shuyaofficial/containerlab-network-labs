#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
TOPO="faucet.clab.yml"
NAME_PREFIX="clab-faucet-sdn-"

case "${1:-deploy}" in
  deploy)
    # OVSは公式arm64イメージが無いため、初回のみ ovs/Dockerfile から自前ビルドする。
    if ! sudo docker image inspect local/ovs:arm64 >/dev/null 2>&1; then
      echo "[build] local/ovs:arm64 を ovs/Dockerfile からビルドします"
      sudo docker build -t local/ovs:arm64 ovs/
    fi
    sudo containerlab deploy -t "$TOPO"
    # ovs1 では イメージに焼き込んだ bootstrap.sh が entrypoint として実行され、
    # br0(netdev) の生成 → データポート収容 → fail-mode=secure →
    # controller=tcp:172.35.35.11:6653 → protocols=OpenFlow13 の設定まで完了する。
    echo "確認: sudo docker exec ${NAME_PREFIX}ovs1 ovs-vsctl show"
    ;;
  inspect)
    sudo containerlab inspect -t "$TOPO"
    ;;
  destroy)
    sudo containerlab destroy -t "$TOPO" --cleanup
    ;;
  *)
    echo "usage: $0 {deploy|inspect|destroy}" >&2
    exit 1
    ;;
esac
