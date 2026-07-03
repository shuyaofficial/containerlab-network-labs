#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
TOPO="campus.clab.yml"
NAME_PREFIX="clab-dynamic-routing-lab-"

start_iouyap() {
  sleep 5
  for container in $(sudo docker ps --format '{{.Names}}' \
      | grep "^${NAME_PREFIX}" | grep -v -E 'pc$|srv$'); do
    sudo docker exec -d -w /iol "$container" /usr/bin/iouyap 513 2>/dev/null || true
  done
}

case "${1:-deploy}" in
  deploy)
    sudo containerlab deploy -t "$TOPO"
    start_iouyap
    ;;
  iouyap)
    start_iouyap
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
