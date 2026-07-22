#!/usr/bin/env bash
# Verona再現 — 網屋「Verona」(商用フルマネージドSASE)の機能をarm64 OSSで再現するdeployスクリプト。
# コア（本スクリプトで確実に起動・検証できる）  : OpenZiti(ZTNAダークサービス) / Squid(URLフィルタ)
#                                                  / Blocky(DNSフィルタ) / Suricata(IDSモード)
# 発展（config+docを用意。単独サブコマンドで起動可、連携までは求めない）
#                                                  : step-ca(デバイスポスチャー) / Keycloak(IdP連携)
#                                                  / Headscale(拠点間トンネル=SD-WAN相当)
#
# 36_ztna_openziti・42_ndr_flow のdeploy.sh作法を踏襲（sudo docker run直列、compose不使用）。
# 前提: OrbStack VM `clab`（arm64）、ssh clab@orb、docker（sudo NOPASSWD）。
set -euo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"

# --- イメージ（全てarm64実測済み） ---
IMG_ZITI=openziti/ziti-cli:latest
IMG_SURICATA=jasonish/suricata:latest
IMG_SQUID=ubuntu/squid:latest
IMG_BLOCKY=ghcr.io/0xerr0r/blocky:latest
IMG_STEPCA=smallstep/step-ca:latest
IMG_KEYCLOAK=quay.io/keycloak/keycloak:latest
IMG_HEADSCALE=headscale/headscale:latest
IMG_NGINX=nginx:alpine
IMG_MULTITOOL=wbitt/network-multitool:latest

# --- ネットワーク（衝突回避のため固定値。ALog再現のGrafana3001/Loki3101/MinIO9001等とは非重複） ---
NET_CLOUD=vsase-cloud     # SASEクラウド相当（ZTNAコントローラ・SWG群・IDS監視点）
NET_BRANCH=vsase-branch   # 拠点相当（branch-client のホームLAN）
NET_DARK=vsase-dark       # 保護対象アプリ専用（clientは非参加＝ダークサービス）
BR_CLOUD=vsase-br0        # vsase-cloud の bridge 名（Suricata host mode の監視対象）
SUBNET_CLOUD=172.60.10.0/24
SUBNET_BRANCH=172.60.20.0/24
SUBNET_DARK=172.60.30.0/24

# --- 固定IP（vsase-cloud。determinism確保のため全コンテナに静的割当） ---
IP_ZITI=172.60.10.10
IP_SQUID=172.60.10.11
IP_BLOCKY=172.60.10.12
IP_SAFESITE=172.60.10.13
IP_APPTUN_CLOUD=172.60.10.14
IP_CLIENTTUN=172.60.10.15
IP_BRANCHCLIENT_CLOUD=172.60.10.21
IP_KEYCLOAK=172.60.10.30
IP_STEPCA=172.60.10.31
IP_HEADSCALE=172.60.10.32
# --- 固定IP（vsase-branch / vsase-dark） ---
IP_BRANCHCLIENT_BRANCH=172.60.20.21
IP_PROTECTEDAPP=172.60.30.11
IP_APPTUN_DARK=172.60.30.14

# --- 公開ポート（host。53番は避け5353。他ラボと非重複の固定値） ---
PORT_SQUID=3128
PORT_BLOCKY_DNS=5353
PORT_BLOCKY_HTTP=4000
PORT_KEYCLOAK=8081
PORT_HEADSCALE=8082
PORT_STEPCA=9000

# --- SWG検証用テストドメイン（実在の危険サイトではなく.test＝IANA予約TLD。squid/blocklist.txtと共用） ---
DOMAIN_ALLOWED=safe.verona-lab.test
DOMAIN_BLOCKED=malware.verona-lab.test

ensure_networks() {
  sudo docker network create --driver bridge --subnet "$SUBNET_CLOUD" \
    --opt com.docker.network.bridge.name="$BR_CLOUD" "$NET_CLOUD" 2>/dev/null || true
  sudo docker network create --driver bridge --subnet "$SUBNET_BRANCH" "$NET_BRANCH" 2>/dev/null || true
  sudo docker network create --driver bridge --subnet "$SUBNET_DARK" "$NET_DARK" 2>/dev/null || true
}

case "${1:-deploy-core}" in
  deploy-core)
    echo "== ネットワーク作成（vsase-cloud/vsase-branch/vsase-dark） =="
    ensure_networks

    echo "== OpenZiti コントローラ+ルータ一体（vsase-cloud、quickstart） =="
    sudo docker run -d --name ziti --hostname ziti \
      --network "$NET_CLOUD" --ip "$IP_ZITI" \
      "$IMG_ZITI" edge quickstart --ctrl-address ziti --router-address ziti --password admin --home /tmp/ziti

    echo "== 保護対象アプリ（vsase-dark のみ・公開ポート無し＝ダークサービス。36_ztna_openzitiパターン流用） =="
    sudo docker run -d --name protected-app \
      --network "$NET_DARK" --ip "$IP_PROTECTEDAPP" \
      "$IMG_NGINX"

    echo "== apptun（vsase-cloud + vsase-dark。protected-appをdialしoverlayへhost） =="
    sudo docker run -d --name apptun --network "$NET_CLOUD" --ip "$IP_APPTUN_CLOUD" \
      --entrypoint sleep "$IMG_ZITI" infinity
    sudo docker network connect --ip "$IP_APPTUN_DARK" "$NET_DARK" apptun

    echo "== clienttun（vsase-cloudのみ＝リモート社員端末。protected-appへ直接到達不能） =="
    sudo docker run -d --name clienttun --network "$NET_CLOUD" --ip "$IP_CLIENTTUN" \
      --entrypoint sleep "$IMG_ZITI" infinity

    echo "== safe-site（許可サイト相当。URL/DNSフィルタの許可ケース確認用） =="
    sudo docker run -d --name safe-site \
      --network "$NET_CLOUD" --ip "$IP_SAFESITE" \
      "$IMG_NGINX"

    echo "== Blocky（SWG/DNSセキュリティ。vsase-cloud・host:${PORT_BLOCKY_DNS}/${PORT_BLOCKY_HTTP}） =="
    sudo docker run -d --name blocky \
      --network "$NET_CLOUD" --ip "$IP_BLOCKY" \
      -p "${PORT_BLOCKY_DNS}:53/udp" -p "${PORT_BLOCKY_DNS}:53/tcp" -p "${PORT_BLOCKY_HTTP}:4000" \
      -v "${HERE}/blocky/config.yml":/app/config.yml:ro \
      -v "${HERE}/squid/blocklist.txt":/app/lists/blocklist.txt:ro \
      "$IMG_BLOCKY"

    echo "== Squid（SWG/URLフィルタ。vsase-cloud・host:${PORT_SQUID}。DNSはBlockyへ委譲=二重防御） =="
    sudo docker run -d --name squid \
      --network "$NET_CLOUD" --ip "$IP_SQUID" --dns "$IP_BLOCKY" \
      --add-host "${DOMAIN_ALLOWED}:${IP_SAFESITE}" \
      -p "${PORT_SQUID}:3128" \
      -v "${HERE}/squid/squid.conf":/etc/squid/squid.conf:ro \
      -v "${HERE}/squid/blocklist.txt":/etc/squid/blocklist.txt:ro \
      "$IMG_SQUID"

    echo "== branch-client（拠点端末相当。vsase-branch+vsase-cloud。SWG/IDS検証の起点） =="
    sudo docker run -d --name branch-client --network "$NET_BRANCH" --ip "$IP_BRANCHCLIENT_BRANCH" \
      "$IMG_MULTITOOL" sleep infinity
    sudo docker network connect --ip "$IP_BRANCHCLIENT_CLOUD" "$NET_CLOUD" branch-client

    echo "== Suricata（FWaaS/IDSモード。vsase-br0をhost modeで監視。インライン遮断はしない） =="
    mkdir -p "${HERE}/suricata/log"
    sudo docker run -d --name suricata \
      --network host --cap-add NET_ADMIN --cap-add NET_RAW --cap-add SYS_NICE \
      -v "${HERE}/suricata/local.rules":/rules/local.rules:ro \
      -v "${HERE}/suricata/log":/var/log/suricata \
      "$IMG_SURICATA" \
      -i "$BR_CLOUD" \
      -S /rules/local.rules \
      --set default-rule-path=/rules \
      --set vars.address-groups.HOME_NET="[${SUBNET_CLOUD}]" \
      --set vars.address-groups.EXTERNAL_NET=any

    echo "コア4機能 起動完了（OpenZiti / Squid / Blocky / Suricata）。"
    echo "  次のゲート : ./deploy.sh setup-ziti   （ZTNAダークサービス構成＋実証）"
    echo "  SWG検証    : ./deploy.sh test-swg     （URL/DNSブロックのcurl/dig検証）"
    echo "  IDS検証    : ./deploy.sh test-ids     （スキャンでSuricata検知）"
    ;;

  setup-ziti)
    exec "${HERE}/setup_ziti.sh"
    ;;

  test-swg)
    echo "== URL層（Squid dstdomain, branch-client -x http://squid:3128） =="
    echo -n "[1] 許可ドメイン ${DOMAIN_ALLOWED} 経由 squid（200期待）        : "
    sudo docker exec branch-client sh -c \
      "curl -s -m8 -o /dev/null -w 'HTTP %{http_code}\n' -x http://squid:3128 http://${DOMAIN_ALLOWED}/" || true
    echo -n "[2] ブロックドメイン ${DOMAIN_BLOCKED} 経由 squid（403期待）    : "
    sudo docker exec branch-client sh -c \
      "curl -s -m8 -o /dev/null -w 'HTTP %{http_code}\n' -x http://squid:3128 http://${DOMAIN_BLOCKED}/" || true
    echo "== DNS層（Blocky。branch-client→blocky:53） =="
    echo -n "[3] 許可ドメイン ${DOMAIN_ALLOWED} の名前解決（customDNSで${IP_SAFESITE}期待） : "
    sudo docker exec branch-client dig @blocky +short "$DOMAIN_ALLOWED" || true
    echo -n "[4] ブロックドメイン ${DOMAIN_BLOCKED} の名前解決（0.0.0.0期待・denylist）      : "
    sudo docker exec branch-client dig @blocky +short "$DOMAIN_BLOCKED" || true
    echo "URL層／DNS層の二重防御（Verona SWG p40-42 相当）の実演完了。"
    ;;

  test-ids)
    echo "branch-client(${IP_BRANCHCLIENT_CLOUD}) → squid(${IP_SQUID}) へ SYNスキャンを実行（vsase-br0をSuricataが監視）..."
    sudo docker exec branch-client nmap -sS -p 1-200 "$IP_SQUID" || true
    echo "検知確認（sid:2000001 recon SYN scan）を待機・表示:"
    sleep 3
    sudo grep -h '"event_type":"alert"' "${HERE}/suricata/log/eve.json" 2>/dev/null | grep '2000001' | tail -5 \
      || echo "(まだ検知ログなし。数秒後に再実行: ./deploy.sh test-ids)"
    ;;

  deploy-idp)
    ensure_networks
    sudo docker run -d --name keycloak \
      --network "$NET_CLOUD" --ip "$IP_KEYCLOAK" \
      -p "${PORT_KEYCLOAK}:8080" \
      -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin \
      "$IMG_KEYCLOAK" start-dev
    echo "Keycloak起動。http://localhost:${PORT_KEYCLOAK}/ (admin/admin)。"
    echo "realm/client作成手順・OpenZiti external-jwt-signer連携方針は keycloak/README.md 参照。"
    ;;

  deploy-posture)
    ensure_networks
    sudo docker run -d --name step-ca \
      --network "$NET_CLOUD" --ip "$IP_STEPCA" \
      -p "${PORT_STEPCA}:9000" \
      -e "DOCKER_STEPCA_INIT_NAME=Verona-Lab-CA" \
      -e "DOCKER_STEPCA_INIT_DNS_NAMES=step-ca,localhost,127.0.0.1" \
      -e "DOCKER_STEPCA_INIT_PASSWORD=verona-lab-posture" \
      "$IMG_STEPCA"
    echo "step-ca起動。ルートCA初期化・クライアント証明書発行手順は stepca/README.md 参照。"
    echo "ポスチャーチェックのモック実行例: ./posture/check_posture.sh <証明書パス>"
    ;;

  deploy-tunnel)
    ensure_networks
    mkdir -p "${HERE}/headscale/data"
    sudo docker run -d --name headscale \
      --network "$NET_CLOUD" --ip "$IP_HEADSCALE" \
      -p "${PORT_HEADSCALE}:8080" \
      -v "${HERE}/headscale/config.yaml":/etc/headscale/config.yaml:ro \
      -v "${HERE}/headscale/data":/var/lib/headscale \
      "$IMG_HEADSCALE" serve
    echo "Headscale起動。拠点間トンネル(tailscale)の接続手順は headscale/README.md 参照。"
    ;;

  ps)
    sudo docker ps -a --filter name='ziti|protected-app|apptun|clienttun|squid|blocky|safe-site|branch-client|suricata|keycloak|step-ca|headscale' \
      --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    ;;

  destroy)
    sudo docker rm -f ziti protected-app apptun clienttun squid blocky safe-site branch-client suricata \
      keycloak step-ca headscale 2>/dev/null || true
    sudo docker network rm "$NET_CLOUD" "$NET_BRANCH" "$NET_DARK" 2>/dev/null || true
    echo "撤去完了（コア9コンテナ＋発展3コンテナ＋3ネットワークを削除）。"
    ;;

  *)
    echo "usage: $0 {deploy-core|setup-ziti|test-swg|test-ids|deploy-idp|deploy-posture|deploy-tunnel|ps|destroy}" >&2
    echo "  deploy-core    : OpenZiti+Squid+Blocky+Suricata 起動（コア4機能）" >&2
    echo "  setup-ziti     : ZTNAダークサービス設定＋enrollment＋実証（36_ztna_openziti流用）" >&2
    echo "  test-swg       : URL/DNSフィルタのブロック/許可をcurl/digで検証" >&2
    echo "  test-ids       : branch-client→squidへSYNスキャンを送りSuricata検知を確認" >&2
    echo "  deploy-idp     : Keycloak起動（発展・IdP連携）" >&2
    echo "  deploy-posture : step-ca起動（発展・デバイスポスチャー）" >&2
    echo "  deploy-tunnel  : Headscale起動（発展・拠点間トンネル/SD-WAN相当）" >&2
    echo "  ps/destroy     : 状態表示 / 全撤去" >&2
    exit 1
    ;;
esac
