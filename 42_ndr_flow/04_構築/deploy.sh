#!/usr/bin/env bash
# テーマ42 NDR（east-west 可視化）deploy スクリプト — NW-ZT N3 実装
#
# 構成:
#   ndr-lan (172.40.0.0/24, bridge名=ndr-br0 固定) 上に attacker/victim を配置＝east-west。
#   Suricata を host mode で ndr-br0 に張り付け、配下コンテナ間フレームを DPI 監視。
#   Loki + Promtail + Grafana で eve.json を集約・可視化。goflow2 で NetFlow 受信を試す。
#
# 前提: OrbStack VM clab (arm64)、docker（compose 不在）。sudo NOPASSWD。
#   ssh clab@orb で接続。Mac 側ファイルは VM に同一パスでマウント済み。
set -euo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"

# --- パラメータ ---
NET=ndr-lan
BR=ndr-br0
SUBNET=172.40.0.0/24
ATTACKER_IP=172.40.0.21
VICTIM_IP=172.40.0.22

IMG_MULTITOOL=wbitt/network-multitool:latest
IMG_NGINX=nginx:alpine
IMG_SURICATA=jasonish/suricata:latest
IMG_LOKI=grafana/loki:latest
IMG_PROMTAIL=grafana/promtail:latest
IMG_GRAFANA=grafana/grafana:latest
IMG_GOFLOW2=netsampler/goflow2:latest

# Suricata の eve.json 出力先（VM 側 = Mac 側同一パス。grep しやすいよう bind する）
LOGDIR="${HERE}/suricata/log"

case "${1:-deploy}" in
  deploy)
    # --- east-west 用ネットワーク（bridge名を ndr-br0 に固定） ---
    sudo docker network create \
      --driver bridge \
      --subnet "$SUBNET" \
      --opt com.docker.network.bridge.name="$BR" \
      "$NET" 2>/dev/null || true

    # --- victim（狙われる側 nginx） ---
    sudo docker run -d --name victim \
      --network "$NET" --ip "$VICTIM_IP" \
      "$IMG_NGINX"

    # --- attacker（スキャンする側。nmap 入り multitool） ---
    sudo docker run -d --name attacker \
      --network "$NET" --ip "$ATTACKER_IP" \
      "$IMG_MULTITOOL" sleep infinity

    # --- Suricata（host mode で ndr-br0 を監視） ---
    #   -S local.rules を追加ロード、HOME_NET を 172.40.0.0/24 に上書き。
    #   eve.json は /var/log/suricata（=bind した LOGDIR）へ。alert/flow はデフォルト有効。
    mkdir -p "$LOGDIR"
    sudo rm -f "$LOGDIR"/eve.json "$LOGDIR"/*.log 2>/dev/null || true
    sudo docker run -d --name suricata \
      --network host --cap-add NET_ADMIN --cap-add NET_RAW --cap-add SYS_NICE \
      -v "${HERE}/suricata/local.rules":/rules/local.rules:ro \
      -v "${LOGDIR}":/var/log/suricata \
      "$IMG_SURICATA" \
      -i "$BR" \
      -S /rules/local.rules \
      --set default-rule-path=/rules \
      --set vars.address-groups.HOME_NET="[172.40.0.0/24]" \
      --set vars.address-groups.EXTERNAL_NET=any

    echo "起動完了。bridge=${BR} を Suricata が監視中。"
    echo "  ネットワーク確認: sudo docker network inspect ${NET}"
    echo "  次のゲート: ./deploy.sh scan で east-west SYN スキャンを流し eve.json を確認。"
    echo "  可視化まで含めるなら: ./deploy.sh monitoring"
    ;;

  monitoring)
    # --- Loki + Promtail + Grafana（eve.json を集約） ---
    # Loki（TSDB。設定を bind） host ポート 3100 で受ける。
    sudo docker run -d --name loki \
      -p 3100:3100 \
      -v "${HERE}/loki/loki-config.yml":/etc/loki/loki-config.yml:ro \
      "$IMG_LOKI" -config.file=/etc/loki/loki-config.yml

    # Promtail（eve.json を tail → Loki push）。host mode で localhost:3100 の Loki へ。
    sudo docker run -d --name promtail \
      --network host \
      -v "${HERE}/promtail/promtail-config.yml":/etc/promtail/promtail-config.yml:ro \
      -v "${LOGDIR}":/var/log/suricata:ro \
      "$IMG_PROMTAIL" -config.file=/etc/promtail/promtail-config.yml

    # Grafana（Loki を datasource に自動プロビジョン）。
    #   host mode: datasource url=localhost:3100（host に publish 済みの Loki）へ確実に届く。
    #   3000 も host で listen するので localhost:3000 で確認可能。
    sudo docker run -d --name grafana \
      --network host \
      -e GF_AUTH_ANONYMOUS_ENABLED=true \
      -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
      -e GF_SECURITY_ADMIN_PASSWORD=admin \
      -v "${HERE}/grafana/provisioning":/etc/grafana/provisioning:ro \
      "$IMG_GRAFANA"

    echo "集約基盤 起動完了（Loki:3100 / Grafana:3000）。"
    echo "  Loki:    curl -s 'http://localhost:3100/ready'"
    echo "  Grafana: curl -s localhost:3000/api/health"
    ;;

  netflow)
    # --- goflow2 + softflowd（NetFlow/IPFIX を試す・ボーナス G5） ---
    #   goflow2: UDP 2055 で NetFlow を受信し JSON を stdout に（host mode で loopback 受信）。
    #   softflowd: ndr-br0 を pcap し NetFlow v9 を 127.0.0.1:2055 へエクスポート（alpine/arm64）。
    #
    #   【既知の制限・代替判断】softflowd v1.1.0(alpine/arm64) は ndr-br0 の
    #   フレームを libpcap で受信できる（Packets received by libpcap > 0）が
    #   Packets processed=0 でフロー化できず、goflow2 に届かない。goflow2 自体は
    #   arm64 で NetFlow 受信待受を起動可能（実証済み）。よって east-west の
    #   フロー統計は Suricata の flow イベント（deploy.sh eve / G3）で代替する。
    sudo docker run -d --name goflow2 --network host \
      "$IMG_GOFLOW2" -listen "netflow://:2055"
    sudo docker run -d --name softflowd --network host \
      --cap-add NET_ADMIN --cap-add NET_RAW \
      alpine:latest sh -c \
      'apk add --no-cache softflowd >/dev/null 2>&1 && \
       softflowd -i '"$BR"' -n 127.0.0.1:2055 -v 9 -t maxlife=3 -t tcp=3 -d "ip"'
    echo "goflow2(UDP2055待受) + softflowd(ndr-br0→NetFlow) 起動。"
    echo "  受信確認: sudo docker logs goflow2 | grep 172.40.0.21"
    echo "  softflowd 統計: sudo docker exec softflowd softflowctl statistics"
    echo "  ※arm64 softflowd の制限で processed=0 の場合は Suricata flow で代替（G3）。"
    ;;

  scan)
    # --- east-west SYN スキャン（G2 検証用トリガ） ---
    echo "attacker(${ATTACKER_IP}) → victim(${VICTIM_IP}) へ SYN スキャンを実行..."
    sudo docker exec attacker nmap -sS -p 1-200 "$VICTIM_IP" || true
    echo "スキャン完了。eve.json の sid:1000001 を確認: ./deploy.sh eve"
    ;;

  eve)
    # eve.json から alert / flow を抜粋表示
    echo "=== alert (sid 1000001/1000002) ==="
    sudo grep -h '"event_type":"alert"' "${LOGDIR}/eve.json" 2>/dev/null | tail -5 || echo "(なし)"
    echo "=== flow (east-west 172.40.0.21→172.40.0.22) ==="
    sudo grep -h '"event_type":"flow"' "${LOGDIR}/eve.json" 2>/dev/null | grep '172.40.0.21' | tail -5 || echo "(なし)"
    ;;

  ps)
    sudo docker ps --filter name='attacker|victim|suricata|loki|promtail|grafana|goflow2|softflowd' \
      --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    ;;

  destroy)
    sudo docker rm -f attacker victim suricata loki promtail grafana goflow2 softflowd 2>/dev/null || true
    sudo docker network rm "$NET" 2>/dev/null || true
    echo "撤去完了（コンテナ8種＋${NET} を削除）。"
    ;;

  *)
    echo "usage: $0 {deploy|monitoring|netflow|scan|eve|ps|destroy}" >&2
    echo "  deploy     : ndr-lan 作成＋attacker/victim/suricata 起動（G1）" >&2
    echo "  scan       : attacker→victim へ SYN スキャン（G2 トリガ）" >&2
    echo "  eve        : eve.json の alert/flow を抜粋（G2/G3 確認）" >&2
    echo "  monitoring : Loki+Promtail+Grafana 起動（G4 集約）" >&2
    echo "  netflow    : goflow2+softflowd で NetFlow を試す（G5 ボーナス）" >&2
    echo "  ps/destroy : 状態表示 / 全撤去" >&2
    exit 1
    ;;
esac
