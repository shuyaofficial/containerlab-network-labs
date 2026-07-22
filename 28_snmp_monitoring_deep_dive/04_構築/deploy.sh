#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
TOPO="legacy-lan.clab.yml"
NAME_PREFIX="clab-snmp-monitoring-lab-"
IOURC_FILE="/opt/clab/.iourc"

# IOL実ライセンスをVMローカルの固定パス(/opt/clab/.iourc)に用意する。
# 本テーマのL2系イメージ(L2-15.2等)はライセンスが/iol/.iourcファイルではなく
# イメージ側/entrypoint.sh内にあり、entrypoint_attach.shのbindで隠れるため、
# デプロイ前にイメージから抽出してbind(/opt/clab/.iourc:/iol/.iourc:ro)で渡す。
# ライセンス値はVM内(Dockerイメージと本ファイル)にのみ存在させ、gitリポジトリには一切置かないこと。
ensure_iourc() {
  if sudo test -s "$IOURC_FILE" \
     && sudo grep -qE 'gns3-iouvm *= *[0-9a-fA-F]{16} *;' "$IOURC_FILE" \
     && ! sudo grep -qE 'gns3-iouvm *= *0{16} *;' "$IOURC_FILE"; then
    return 0
  fi
  local img lic
  for img in vrnetlab/cisco_iol:15.7.3M2 vrnetlab/cisco_iol:L2-advipservices-2017 \
             vrnetlab/cisco_iol:L2-15.2 vrnetlab/cisco_iol:15.6.3M3a; do
    lic=$(docker run --rm --entrypoint sh "$img" -c \
        'cat /iol/.iourc 2>/dev/null; grep -h -oE "gns3-iouvm = [0-9a-fA-F]{16}" /entrypoint.sh 2>/dev/null' \
        2>/dev/null | grep -oE '[0-9a-fA-F]{16}' | grep -v '^0\{16\}$' | head -1) || true
    if [ -n "${lic:-}" ]; then
      sudo mkdir -p "$(dirname "$IOURC_FILE")"
      printf '[license]\ngns3-iouvm = %s;\n' "$lic" | sudo tee "$IOURC_FILE" >/dev/null
      sudo chmod 600 "$IOURC_FILE"
      echo "IOURC: ${img} からライセンスを抽出し ${IOURC_FILE} を作成しました。"
      return 0
    fi
  done
  echo "ERROR: IOLライセンスをイメージから抽出できませんでした。${IOURC_FILE} を手動で用意してください。" >&2
  exit 1
}

# iouyap は entrypoint_attach.sh がIOLブート後(+60秒)に自動起動・自己修復する。
# 本関数は自動起動が働かない場合の手動リカバリ用（./deploy.sh iouyap）。
start_iouyap() {
  sleep 5
  for container in $(sudo docker ps --format '{{.Names}}' \
      | grep "^${NAME_PREFIX}" | grep -v -E 'nms$|cap$|pc-a$|pc-b$|srv-file$|zbx-'); do
    sudo docker exec -d -w /iol "$container" /usr/bin/iouyap 513 2>/dev/null || true
  done
}

# zbx-srvのeth1（VLAN100 in-band、10.28.100.20/24）を設定する。
# zabbixイメージは非rootユーザーで動くためclab.ymlのexecでは投入できず、
# deploy後にroot指定(-u 0)で投入する。コンテナを再起動した場合は
# `./deploy.sh zbx-net` で再投入すること。defaultルートはmgmt(eth0)側に残す。
zbx_net() {
  local c="${NAME_PREFIX}zbx-srv"
  sudo docker exec -u 0 "$c" ip link set eth1 up
  sudo docker exec -u 0 "$c" ip link set eth1 mtu 1500
  sudo docker exec -u 0 "$c" ip address replace 10.28.100.20/24 dev eth1
  sudo docker exec -u 0 "$c" ip route replace 10.28.0.0/16 via 10.28.100.1 dev eth1
  echo "zbx-srv: eth1=10.28.100.20/24 / 経路 10.28.0.0/16 via 10.28.100.1 を設定しました。"
}

case "${1:-deploy}" in
  deploy)
    ensure_iourc
    sudo containerlab deploy -t "$TOPO"
    zbx_net
    echo "NOTE: iouyapはIOLブート後(約60秒)にentrypointが自動起動します。"
    ;;
  iouyap)
    start_iouyap
    ;;
  zbx-net)
    zbx_net
    ;;
  inspect)
    sudo containerlab inspect -t "$TOPO"
    ;;
  destroy)
    # --cleanup はnvram(保存済みコンフィグ)ごと削除する。コンフィグを残したい場合は
    # `sudo containerlab destroy -t legacy-lan.clab.yml` を直接実行すること（--cleanupなし）。
    sudo containerlab destroy -t "$TOPO" --cleanup
    ;;
  *)
    echo "usage: $0 {deploy|iouyap|zbx-net|inspect|destroy}" >&2
    exit 1
    ;;
esac
