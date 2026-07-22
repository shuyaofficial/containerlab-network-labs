#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
TOPO="campus.clab.yml"
NAME_PREFIX="clab-qos-acl-policy-lab-"

# iouyap は entrypoint_attach.sh がIOLブート後(+60秒)に自動起動・自己修復する。
# 本関数は自動起動が働かない場合の手動リカバリ用（./deploy.sh iouyap）。
start_iouyap() {
  sleep 5
  for container in $(sudo docker ps --format '{{.Names}}' \
      | grep "^${NAME_PREFIX}" | grep -v -E 'pc$|srv$|voip$'); do
    sudo docker exec -d -w /iol "$container" /usr/bin/iouyap 513 2>/dev/null || true
  done
}

case "${1:-deploy}" in
  deploy)
    sudo containerlab deploy -t "$TOPO"
    echo "NOTE: iouyapはIOLブート後(約60秒)にentrypointが自動起動します。"
    ;;
  iouyap)
    start_iouyap
    ;;
  inspect)
    sudo containerlab inspect -t "$TOPO"
    ;;
  destroy)
    # --cleanup はnvram(保存済みコンフィグ)ごと削除する。コンフィグを残したい場合は
    # `sudo containerlab destroy -t campus.clab.yml` を直接実行すること（--cleanupなし）。
    sudo containerlab destroy -t "$TOPO" --cleanup
    ;;
  *)
    echo "usage: $0 {deploy|iouyap|inspect|destroy}" >&2
    exit 1
    ;;
esac
