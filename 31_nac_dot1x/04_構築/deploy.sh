#!/usr/bin/env bash
# N1 NAC / 802.1X ラボ deploy スクリプト
# 重要: IOL のデータプレーンは iouyap を起動しないとフレームが通らない
#       （テーマ22/26 と同じ。未起動だと switch↔RADIUS も dot1x も無反応になる）
set -euo pipefail
cd "$(dirname "$0")"

TOPO="nac.clab.yml"
NAME_PREFIX="clab-nac-"

start_iouyap() {
  # IOL ノード（pc/radius 以外）で iouyap を起動。ポート 513 は NETMAP 由来。
  sleep 5
  for c in $(sudo docker ps --format '{{.Names}}' \
      | grep "^${NAME_PREFIX}" | grep -vE 'pc[0-9]$|radius$'); do
    sudo docker exec -d -w /iol "$c" /usr/bin/iouyap 513 2>/dev/null || true
    echo "iouyap started on $c"
  done
}

fix_dataplane() {
  # Linux 側データ IF のオフロードを無効化（IOL 系の取りこぼし対策の保険）
  for c in radius pc1 pc2; do
    pid=$(sudo docker inspect -f '{{.State.Pid}}' "${NAME_PREFIX}${c}" 2>/dev/null) || continue
    sudo nsenter -t "$pid" -n ethtool -K eth1 rx off tx off gso off gro off tso off 2>/dev/null || true
  done
  # radius のデータ側 IP（SVI 172.31.0.1 到達用）。clab exec が入れ損ねた場合の保険。
  sudo docker exec "${NAME_PREFIX}radius" ip addr add 172.31.0.10/24 dev eth1 2>/dev/null || true
}

case "${1:-deploy}" in
  deploy)
    sudo containerlab deploy -t "$TOPO"
    start_iouyap
    fix_dataplane
    echo "--- 次は sw1 に設定投入: sudo expect run_nac.exp ${NAME_PREFIX}sw1 sw1_dot1x.cfg ---"
    ;;
  iouyap)
    start_iouyap
    fix_dataplane
    ;;
  inspect)
    sudo containerlab inspect -t "$TOPO"
    ;;
  destroy)
    sudo containerlab destroy -t "$TOPO" --cleanup
    ;;
  *)
    echo "usage: $0 {deploy|iouyap|inspect|destroy}" >&2
    exit 1
    ;;
esac
