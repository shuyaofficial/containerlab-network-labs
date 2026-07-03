#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
TOPO="zt-base.clab.yml"
NAME_PREFIX="clab-zt-base-"
# bridge名:GW IP（IPアドレス管理表のゾーン GW と一致）
BRIDGES=("zt-untrust:172.30.0.1/24" "zt-trust:172.30.20.1/24")

create_bridges() {
  for entry in "${BRIDGES[@]}"; do
    br="${entry%%:*}"
    gw="${entry#*:}"
    if ! ip link show "$br" &>/dev/null; then
      sudo ip link add name "$br" type bridge
      sudo ip link set "$br" up
    fi
    # ブリッジに GW IP を付与（論理構成設計の bridge GW と一致）。
    # Phase 0 は関所が無いため、client<->app 疎通は「ホスト L3 でのゾーン間中継」に限定し、
    # Phase 2 で関所（Pomerium/oauth2-proxy）が入ったら経路をそちらに置き換える。
    ip addr show "$br" | grep -q "${gw%/*}" || sudo ip addr add "$gw" dev "$br"
  done
  # ゾーン間中継のための IPv4 フォワーディングを有効化（Phase 0 限定の暫定経路）
  sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

remove_bridges() {
  for entry in "${BRIDGES[@]}"; do
    br="${entry%%:*}"
    if ip link show "$br" &>/dev/null; then
      sudo ip link del "$br" || true
    fi
  done
}

case "${1:-deploy}" in
  deploy)
    create_bridges
    sudo containerlab deploy -t "$TOPO"
    ;;
  iouyap)
    echo "本テーマでは不要（IOL 不使用）"
    ;;
  inspect)
    sudo containerlab inspect -t "$TOPO"
    ;;
  destroy)
    sudo containerlab destroy -t "$TOPO" --cleanup
    remove_bridges
    ;;
  *)
    echo "usage: $0 {deploy|iouyap|inspect|destroy}" >&2
    exit 1
    ;;
esac
