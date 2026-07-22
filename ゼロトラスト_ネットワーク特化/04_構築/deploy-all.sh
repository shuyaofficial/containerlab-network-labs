#!/usr/bin/env bash
# ゼロトラスト_ネットワーク特化 統合ラボ オーケストレーション
# N1(NAC/802.1X) + N4(μセグ) を単一IOLコアclabで、N2(ZTNA) + N3(NDR) を docker 併走で束ねる。
#
# 重要な運用定石（既存テーマの教訓を継承）:
#   - IOL のデータプレーンは deploy 直後に iouyap(513) を起動しないと全断（テーマ22/26/31/microseg）
#   - config 投入は expect の 1 attach 直列（docker attach 多重起動NG）
#   - サーバ室VLAN50は docker network nwzt-srv0（GW .254 で IOL SVI .1 と非衝突）として実体化し、
#     clab の kind:bridge がこの既存ブリッジに core-sw:eth6 / srv-app1 / host-infected を収容、
#     N3 Suricata が host mode でこのブリッジの東西を DPI、N2 apptun を後付け接続して srv-app1 を dial。
# 前提: ssh clab@orb（OrbStack VM, arm64）。Mac 側ファイルは VM に同一パスでマウント済み。sudo NOPASSWD。
set -euo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"

TOPO="nwzt.clab.yml"
PREFIX="clab-nwzt-lan-"
SRV_NET="nwzt-srv0"          # サーバ室VLAN50の実体（docker network かつ Suricata 監視IF）
SRV_SUBNET="172.31.50.0/24"
SRV_GW="172.31.50.254"       # IOL SVI(.1) と衝突しないダミーGW
APPTUN_IP="172.31.50.50"     # ziti apptun をサーバ室に固定IPで後付け

Z=openziti/ziti-cli:latest
IMG_SURICATA=jasonish/suricata:latest
IMG_LOKI=grafana/loki:latest
IMG_PROMTAIL=grafana/promtail:latest
IMG_GRAFANA=grafana/grafana:latest
LOGDIR="${HERE}/ndr/suricata/log"

# ---- IOL(core-sw) と Linux 端末群 ----
prep_net() {
  # サーバ室ブリッジを clab deploy より前に作成（kind:bridge が既存ブリッジを要求）
  sudo docker network create --driver bridge \
    --subnet "$SRV_SUBNET" --gateway "$SRV_GW" \
    --opt com.docker.network.bridge.name="$SRV_NET" \
    "$SRV_NET" 2>/dev/null || true
  echo "prep: docker network ${SRV_NET} (${SRV_SUBNET}, gw ${SRV_GW}) ready"
}

start_iouyap() {
  sleep 5
  for c in $(sudo docker ps --format '{{.Names}}' | grep "^${PREFIX}core-sw$"); do
    sudo docker exec -d -w /iol "$c" /usr/bin/iouyap 513 2>/dev/null || true
    echo "iouyap started on $c"
  done
}

fix_dataplane() {
  for c in radius pc-sales pc-dev guest-pc pc-unauth srv-app1 host-infected; do
    pid=$(sudo docker inspect -f '{{.State.Pid}}' "${PREFIX}${c}" 2>/dev/null) || continue
    sudo nsenter -t "$pid" -n ethtool -K eth1 rx off tx off gso off gro off tso off 2>/dev/null || true
  done
  sudo docker exec "${PREFIX}radius" ip addr add 172.31.0.10/24 dev eth1 2>/dev/null || true
}

wait_for_switch() { sleep 15; }

config_switch() {
  sudo pkill -f 'docker attach' 2>/dev/null || true
  sudo expect run_nwzt.exp "${PREFIX}core-sw" core_sw_merged.cfg
  sudo pkill -f 'docker attach' 2>/dev/null || true
}

auth_and_services() {
  # pc-sales: 802.1X サプリカント起動 → 認証成功で動的VLAN10。認証後にデータIP付与。
  sudo docker exec -d "${PREFIX}pc-sales" wpa_supplicant -i eth1 -D wired -c /etc/wpa_supplicant.conf 2>/dev/null || true
  echo "pc-sales: wpa_supplicant(alice) 起動。認証待ち..."
  sleep 12
  sudo docker exec "${PREFIX}pc-sales" ip addr add 172.31.10.101/24 dev eth1 2>/dev/null || true
  sudo docker exec "${PREFIX}pc-sales" ip route replace 172.31.0.0/16 via 172.31.10.1 2>/dev/null || true
  # pc-dev/guest はデフォルト経路（inter-VLAN 用）
  sudo docker exec "${PREFIX}pc-dev"  ip route replace 172.31.0.0/16 via 172.31.20.1 2>/dev/null || true
  sudo docker exec "${PREFIX}guest-pc" ip route replace 172.31.0.0/16 via 172.31.30.1 2>/dev/null || true
  # srv-app1: http/80 と 疑似ssh/22 を常駐起動（N4 ACL / N2 dark の対象）
  sudo docker exec -d -w /srv/www "${PREFIX}srv-app1" python3 -m http.server 80 2>/dev/null || true
  sudo docker exec -d "${PREFIX}srv-app1" ncat -lk -p 22 -c 'echo NWZT-SRV-APP1-SSH-OK' 2>/dev/null || true
  echo "services: srv-app1 http/80 + ncat/22 起動"
}

# ---- N2 ZTNA(OpenZiti) ----
ziti_up() {
  sudo docker network create zn-ziti 2>/dev/null || true
  sudo docker run -d --name ziti --hostname ziti --network zn-ziti \
    "$Z" edge quickstart --ctrl-address ziti --router-address ziti --password admin --home /tmp/ziti
  # app 側 tunneler: zn-ziti(router到達) + nwzt-srv0(srv-app1 dial) に接続
  sudo docker run -d --name apptun --network zn-ziti --entrypoint sleep "$Z" infinity
  sudo docker network connect --ip "$APPTUN_IP" "$SRV_NET" apptun
  # client 側 tunneler（= リモート社員端末。zn-ziti のみ = srv-app1 直達不可）
  sudo docker run -d --name clienttun --network zn-ziti --entrypoint sleep "$Z" infinity
  # ダーク化: サーバ室ブリッジのホストGW(.254)を除去し、docker ホストが
  # zn-ziti→サーバ室VLAN50 を L3 転送しないようにする（apptun は同一ブリッジL2で到達を維持）。
  sudo ip addr del "${SRV_GW}/24" dev "$SRV_NET" 2>/dev/null || true
  echo "ziti 起動完了。setup_ziti.sh で サービス/enrollment を実行する。"
  sleep 20
  sudo bash ztna/setup_ziti.sh
}

# ---- N3 NDR(Suricata + Loki/Grafana) ----
ndr_up() {
  mkdir -p "$LOGDIR"
  sudo rm -f "$LOGDIR"/eve.json "$LOGDIR"/*.log 2>/dev/null || true
  sudo docker run -d --name suricata \
    --network host --cap-add NET_ADMIN --cap-add NET_RAW --cap-add SYS_NICE \
    -v "${HERE}/ndr/suricata/local.rules":/rules/local.rules:ro \
    -v "${LOGDIR}":/var/log/suricata \
    "$IMG_SURICATA" \
    -i "$SRV_NET" \
    -S /rules/local.rules \
    --set default-rule-path=/rules \
    --set vars.address-groups.HOME_NET="[172.31.50.0/24]" \
    --set vars.address-groups.EXTERNAL_NET=any
  # 集約基盤
  sudo docker run -d --name loki -p 3100:3100 \
    -v "${HERE}/ndr/loki/loki-config.yml":/etc/loki/loki-config.yml:ro \
    "$IMG_LOKI" -config.file=/etc/loki/loki-config.yml
  sudo docker run -d --name promtail --network host \
    -v "${HERE}/ndr/promtail/promtail-config.yml":/etc/promtail/promtail-config.yml:ro \
    -v "${LOGDIR}":/var/log/suricata:ro \
    "$IMG_PROMTAIL" -config.file=/etc/promtail/promtail-config.yml
  sudo docker run -d --name grafana --network host \
    -e GF_AUTH_ANONYMOUS_ENABLED=true -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
    -e GF_SECURITY_ADMIN_PASSWORD=admin \
    -v "${HERE}/ndr/grafana/provisioning":/etc/grafana/provisioning:ro \
    "$IMG_GRAFANA"
  echo "Suricata(-i ${SRV_NET}) + Loki:3100 + Grafana:3000 起動完了。"
}

# ---- N4 層2: ホスト nftables（同一VLAN内 東西遮断） ----
apply_nft() {
  # srv-app1 で host-infected(172.31.50.31) からの着信を drop
  sudo docker exec "${PREFIX}srv-app1" nft add table inet filter 2>/dev/null || true
  sudo docker exec "${PREFIX}srv-app1" nft add chain inet filter input '{ type filter hook input priority 0 ; policy accept ; }' 2>/dev/null || true
  sudo docker exec "${PREFIX}srv-app1" nft add rule inet filter input ip saddr 172.31.50.31 counter drop
  echo "nftables applied on srv-app1: drop from 172.31.50.31 (host-infected)"
  sudo docker exec "${PREFIX}srv-app1" nft list ruleset
}
flush_nft() {
  sudo docker exec "${PREFIX}srv-app1" nft flush ruleset 2>/dev/null || true
  echo "nftables flushed on srv-app1"
}

# ---- N3 トリガ: 東西 SYN スキャン ----
scan() {
  echo "host-infected(172.31.50.31) → srv-app1(172.31.50.11) へ SYN スキャン..."
  sudo docker exec "${PREFIX}host-infected" nmap -sS -p 1-200 172.31.50.11 || true
  echo "eve.json の sid:1000001 を確認: ./deploy-all.sh eve"
}
eve() {
  echo "=== alert (sid 1000001/1000002) ==="
  sudo grep -h '"event_type":"alert"' "${LOGDIR}/eve.json" 2>/dev/null | tail -5 || echo "(なし)"
  echo "=== flow (east-west 172.31.50.31→172.31.50.11) ==="
  sudo grep -h '"event_type":"flow"' "${LOGDIR}/eve.json" 2>/dev/null | grep '172.31.50.31' | tail -5 || echo "(なし)"
}

verify() {
  echo "### B2 認証セッション/VLAN（core-sw） ###"
  sudo expect verify_nwzt.exp "${PREFIX}core-sw" || true
  sudo pkill -f 'docker attach' 2>/dev/null || true
  echo "### B3 μセグ inter-VLAN ACL（営業pc-sales→srv-app1） ###"
  echo -n "  pc-sales→srv-app1:80 (期待200): "
  sudo docker exec "${PREFIX}pc-sales" curl -s -o /dev/null -w 'HTTP=%{http_code}\n' --max-time 6 http://172.31.50.11:80/ || echo "HTTP=000"
  echo -n "  pc-sales→srv-app1:22 (期待遮断): "
  sudo docker exec "${PREFIX}pc-sales" bash -c "timeout 5 bash -c '</dev/tcp/172.31.50.11/22' && echo REACHABLE || echo BLOCKED" 2>&1 || true
  echo "### B4/B5 は scan / eve / ziti の実証コマンドで確認 ###"
}

case "${1:-deploy}" in
  deploy)
    prep_net
    sudo containerlab deploy -t "$TOPO"
    start_iouyap
    fix_dataplane
    wait_for_switch
    echo "--- 次: ./deploy-all.sh config （設定投入）→ auth → ziti → ndr ---"
    ;;
  iouyap)   start_iouyap; fix_dataplane ;;
  config)   config_switch ;;
  auth)     auth_and_services ;;
  ziti)     ziti_up ;;
  ndr)      ndr_up ;;
  nft)      apply_nft ;;
  nft-flush) flush_nft ;;
  scan)     scan ;;
  eve)      eve ;;
  verify)   verify ;;
  inspect)  sudo containerlab inspect -t "$TOPO" ;;
  destroy)
    sudo docker rm -f ziti apptun clienttun suricata loki promtail grafana 2>/dev/null || true
    sudo containerlab destroy -t "$TOPO" --cleanup 2>/dev/null || true
    sudo docker network rm "$SRV_NET" zn-ziti 2>/dev/null || true
    echo "撤去完了（clab + ziti + ndr + networks）。"
    ;;
  *)
    echo "usage: $0 {deploy|config|auth|ziti|ndr|nft|nft-flush|scan|eve|verify|iouyap|inspect|destroy}" >&2
    exit 1
    ;;
esac
