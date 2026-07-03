#!/usr/bin/env bash
set -euo pipefail

lab="interop-shownet"
nodes=(
  ext-bbix
  ext-jpix
  edge-n1
  edge-n2
  core-n3a
  core-n3b
  transport-n4
  sec-s4
  remote-s5
)

for node in "${nodes[@]}"; do
  container="clab-${lab}-${node}"
  if ! docker ps --format '{{.Names}}' | grep -qx "${container}"; then
    echo "skip ${container}: not running"
    continue
  fi

  if docker exec "${container}" sh -lc "ps -ef | grep '[i]ouyap' >/dev/null 2>&1"; then
    echo "ok ${container}: iouyap already running"
    continue
  fi

  echo "start ${container}: iouyap"
  docker exec -d "${container}" /usr/bin/iouyap -q -f /iol/iouyap.ini -n /iol/NETMAP 513
done
