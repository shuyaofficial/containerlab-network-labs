#!/usr/bin/env bash
# N2 SDP型ZTNA（OpenZiti）ダークサービス検証 deploy スクリプト
# darkweb(nginx) は appnet のみ → client からは直接到達不能。
# ziti オーバーレイ経由でのみ apptun が darkweb を公開する。
set -euo pipefail
Z=openziti/ziti-cli:latest

case "${1:-deploy}" in
  deploy)
    sudo docker network create zn-ziti 2>/dev/null || true   # 制御/データプレーン
    sudo docker network create zn-app  2>/dev/null || true   # アプリ専用（client不参加）
    # コントローラ+ルータ一体（quickstart）
    sudo docker run -d --name ziti --hostname ziti --network zn-ziti \
      "$Z" edge quickstart --ctrl-address ziti --router-address ziti --password admin --home /tmp/ziti
    # ダークな Web（appnet のみ・ポート非公開）
    sudo docker run -d --name darkweb --network zn-app nginx:alpine
    # app 側 tunneler（zn-ziti で router 到達 + zn-app で darkweb を dial）
    sudo docker run -d --name apptun --network zn-ziti --entrypoint sleep "$Z" infinity
    sudo docker network connect zn-app apptun
    # client 側 tunneler（zn-ziti のみ = darkweb 直達不可）
    sudo docker run -d --name clienttun --network zn-ziti --entrypoint sleep "$Z" infinity
    echo "起動完了。次に ./deploy.sh setup で ziti 設定＋enrollment を行う。"
    ;;
  setup)
    exec "$(dirname "$0")/setup_ziti.sh"
    ;;
  destroy)
    sudo docker rm -f ziti darkweb apptun clienttun 2>/dev/null || true
    sudo docker network rm zn-ziti zn-app 2>/dev/null || true
    echo "撤去完了"
    ;;
  *)
    echo "usage: $0 {deploy|setup|destroy}" >&2; exit 1 ;;
esac
