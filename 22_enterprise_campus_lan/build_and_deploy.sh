#!/usr/bin/env bash
# =============================================================================
# build_and_deploy.sh — テーマ22 キャンパスLAN 再構築ヘルパー
# -----------------------------------------------------------------------------
# 実行場所: OrbStack Linux VM「clab」の中
#   Mac から:  ssh clab@orb 'bash "/Users/shuya/Documents/claude/Mac仮想環境構築/22_enterprise_campus_lan/build_and_deploy.sh" status'
#   VM内で:    cd <このフォルダ> && ./build_and_deploy.sh all
#
# 使い方:
#   ./build_and_deploy.sh status    必要イメージの充足状況を表示（既定）
#   ./build_and_deploy.sh build     置かれた .bin / qcow2 からイメージをビルド
#   ./build_and_deploy.sh build-forti 旧FortiGate再検証用イメージをビルド（任意）
#   ./build_and_deploy.sh deploy    campus.clab.yml をデプロイ
#   ./build_and_deploy.sh all       build → status → deploy
#   ./build_and_deploy.sh destroy   ラボを停止・削除
#
# 事前準備（あなたの作業）: ライセンス素材を所定の名前で配置する
#   ~/vrnetlab/cisco/iol/cisco_iol-L2-advipservices-2017.bin   (L3SW + HQ/BR/ISP edge 用)
#   ~/vrnetlab/cisco/iol/cisco_iol-L2-15.2.bin                 (L2SW: acc 用)
#   ~/vrnetlab/cisco/iol/cisco_iol-15.7.3M2.bin                (任意: 旧Router検証用。現テーマ22では未使用)
#   ~/vrnetlab/fortigate/fortios-v7.2.4.qcow2                  (任意: 旧FortiGate再検証用。現fgt-edgeはCisco IOL)
#   ※ ファイル名の <タグ> 部分が、そのまま vrnetlab/cisco_iol:<タグ> になります。
#   ※ 旧世代IOL(15.x)は iourc ライセンスが必要です。詳細は同梱の手順書を参照。
# =============================================================================
set -euo pipefail

THEME_DIR="/Users/shuya/Documents/claude/Mac仮想環境構築/22_enterprise_campus_lan"
VRN="$HOME/vrnetlab"
IOL_DIR="$VRN/cisco/iol"
FGT_DIR="$VRN/fortigate"

# campus.clab.yml と一致させる必須タグ（fgt-edgeはCisco IOLへ置換済み）
IOL_TAGS=("L2-advipservices-2017" "L2-15.2")
OPTIONAL_IOL_TAGS=("15.7.3M2")
FGT_VER="7.2.4"

log(){ printf '\033[1;36m[clab]\033[0m %s\n' "$*"; }
err(){ printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; }
have_img(){ sudo docker image inspect "$1" >/dev/null 2>&1; }

build_iol(){
  local need=0
  for tag in "${IOL_TAGS[@]}"; do have_img "vrnetlab/cisco_iol:${tag}" || need=1; done
  if [ "$need" -eq 0 ]; then log "IOL: 全タグ既存。スキップ"; return; fi
  shopt -s nullglob
  local bins=("$IOL_DIR"/cisco_iol-*.bin)
  if [ ${#bins[@]} -eq 0 ]; then
    err "IOL .bin 未配置: $IOL_DIR に cisco_iol-<タグ>.bin を置いてください"
    return
  fi
  log "IOL build 対象: ${bins[*]##*/}"
  ( cd "$IOL_DIR" && sudo make docker-image )
}

build_fgt(){
  local img="vrnetlab/vr-fortios:${FGT_VER}"
  if have_img "$img"; then log "FortiGate: 既存。スキップ"; return; fi
  local q="$FGT_DIR/fortios-v${FGT_VER}.qcow2"
  if [ ! -f "$q" ]; then
    err "FortiGate qcow2 未配置: $q を置いてください"
    return
  fi
  log "FortiGate build: $img (旧FortiGate再検証用。通常のテーマ22 deploy では使用しません)"
  ( cd "$FGT_DIR" && sudo make )   # 既定ゴール docker-build-fortigate を使う（汎用 make docker-image はNG）
}

status(){
  log "必要イメージの充足状況:"
  for tag in "${IOL_TAGS[@]}"; do
    img="vrnetlab/cisco_iol:${tag}"; have_img "$img" && echo "  ✅ $img" || echo "  ❌ $img"
  done
  for tag in "${OPTIONAL_IOL_TAGS[@]}"; do
    img="vrnetlab/cisco_iol:${tag}"; have_img "$img" && echo "  任意 $img" || echo "  任意(未配置) $img"
  done
  img="vrnetlab/vr-fortios:${FGT_VER}"; have_img "$img" && echo "  任意 $img" || echo "  任意(未配置) $img"
  have_img "wbitt/network-multitool:latest" && echo "  ✅ wbitt/network-multitool:latest" || echo "  ❌ wbitt/network-multitool:latest"
}

deploy(){
  cd "$THEME_DIR"
  log "deploy campus.clab.yml （各IOL約2分）"
  sudo containerlab deploy -t campus.clab.yml
  
  log "IOLノードの iouyap 未起動バグを自動修正します..."
  sleep 5
  for container in $(sudo docker ps --format '{{.Names}}' | grep '^clab-campus-' | grep -v -E 'pc-|srv-|br-pc'); do
    sudo docker exec -d -w /iol "$container" /usr/bin/iouyap 513 2>/dev/null || true
  done
  log "iouyap の自動起動が完了しました。"
}
destroy(){ cd "$THEME_DIR"; log "destroy campus.clab.yml"; sudo containerlab destroy -t campus.clab.yml --cleanup; }

case "${1:-status}" in
  build)   build_iol; status;;
  build-forti) build_fgt; status;;
  deploy)  deploy;;
  all)     build_iol; status; deploy;;
  destroy) destroy;;
  status|*) status;;
esac
