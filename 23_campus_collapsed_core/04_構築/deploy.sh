#!/usr/bin/env bash
# =============================================================================
# deploy.sh — テーマ23 Collapsed Core デプロイヘルパー
# -----------------------------------------------------------------------------
# 実行場所: OrbStack Linux VM「clab」の中（このフォルダで実行）
#   ./deploy.sh deploy    campus.clab.yml をデプロイ＋iouyapを正しい引数で起動
#   ./deploy.sh iouyap    iouyapだけ起動し直す（再起動後の復旧用）
#   ./deploy.sh destroy   ラボを停止・削除
#
# 方針: テーマ22 build_and_deploy.sh と同一機構。
#   - カスタムentrypointは使わない（campus.clab.yml から bind 撤去済み）
#   - stock entrypoint が IOL起動・clab config注入(SSH/admin)・NETMAP生成を担当
#   - このイメージ(2017タグ)は iouyap を自動起動しない世代のため deploy後に手動起動
#   - iouyap の第1引数は NETIOベースポート=513（IOLインスタンスIDではない）
#   - -w /iol で iouyap.ini / NETMAP をカレントから読ませる
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"
TOPO="campus.clab.yml"
# campus.clab.yml の name: と一致（コンテナ名は clab-<name>-<node>）
NAME_PREFIX="clab-campus-collapsed-core-"

log(){ printf '\033[1;36m[clab]\033[0m %s\n' "$*"; }

start_iouyap(){
  log "各IOLノードで iouyap(513) を起動します..."
  sleep 5
  # IOLノードのみ対象（pc1/pc2/pc3 は linux kind なので除外）
  for c in $(sudo docker ps --format '{{.Names}}' \
              | grep "^${NAME_PREFIX}" | grep -v -E 'pc[0-9]'); do
    sudo docker exec -d -w /iol "$c" /usr/bin/iouyap 513 2>/dev/null || true
    log "  iouyap started: $c"
  done
  log "iouyap 起動完了。CDP/STP/HSRP は10〜20秒で収束し始めます。"
}

case "${1:-deploy}" in
  deploy)
    log "deploy $TOPO （各IOL約2分）"
    sudo containerlab deploy -t "$TOPO"
    start_iouyap
    ;;
  iouyap)  start_iouyap;;
  destroy) log "destroy $TOPO"; sudo containerlab destroy -t "$TOPO" --cleanup;;
  *) echo "usage: $0 {deploy|iouyap|destroy}"; exit 1;;
esac
