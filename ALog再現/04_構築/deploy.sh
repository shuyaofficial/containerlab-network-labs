#!/usr/bin/env bash
# ALog再現 deploy スクリプト — 商用SIEM「ALog」のOSS学習再現
#
# 構成:
#   alog-lan (172.41.0.0/24, bridge名=alog-br0 固定) 上に logsrc/scanner を配置。
#   logsrc が syslog(AD/サーバ/NW機器の代表ログ)を Vector(5514)へ送信 → VRLで正規化 → Loki(3101)へpush。
#   Suricata を host mode で alog-br0 に張り付け、scanner→logsrc のSYNスキャンを検知しeve.json化。
#   Promtail が eve.json を Loki へ集約。Loki の chunks は MinIO(S3互換, 9001/9002) にオフロード。
#   Grafana(3001) が Loki を可視化し、3観点(件数変化/新規出現/値変化)のアラートをWebhook(9099)へ通知。
#
# 前提: OrbStack VM clab (arm64)、docker（compose 不在）。sudo NOPASSWD。
#   ssh clab@orb で接続。Mac 側ファイルは VM に同一パスでマウント済み。
set -euo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"

# --- ネットワークパラメータ（他ラボと衝突回避のため固定） ---
NET=alog-lan
BR=alog-br0
SUBNET=172.41.0.0/24
GW_IP=172.41.0.1        # dockerがsubnetの先頭アドレスに自動割当するbridge gateway。
                         # alog-lan上のコンテナはこのIP経由でhost modeサービス(Vector等)へ到達する。
LOGSRC_IP=172.41.0.11
SCANNER_IP=172.41.0.12

# --- ポートパラメータ（他ラボと衝突回避のため固定） ---
GRAFANA_PORT=3001
LOKI_PORT=3101
MINIO_API_PORT=9001
MINIO_CONSOLE_PORT=9002
VECTOR_SYSLOG_PORT=5514
VECTOR_METRICS_PORT=9598
WEBHOOK_PORT=9099

# --- イメージ（全て arm64 実測済み） ---
IMG_MULTITOOL=wbitt/network-multitool:latest
IMG_VECTOR=timberio/vector:latest-alpine
IMG_LOKI=grafana/loki:latest
IMG_PROMTAIL=grafana/promtail:latest
IMG_GRAFANA=grafana/grafana:latest
IMG_MINIO=minio/minio:latest
IMG_SURICATA=jasonish/suricata:latest

# --- MinIO（ラボ用ダミー認証情報。本番運用では秘密情報管理を必須とする） ---
MINIO_ROOT_USER=alogadmin
MINIO_ROOT_PASSWORD=alogadminpass123
MINIO_BUCKET=loki

# --- bind mount先（同一パスでVM/Macから参照可能） ---
LOGDIR="${HERE}/suricata/log"
WEBLOGDIR="${HERE}/webhook/log"
MINIODIR="${HERE}/minio/data"

# --- syslog行の組み立て（RFC3164簡易形式: <PRI>Mon dd hh:mm:ss HOSTNAME TAG: MSG） ---
#   RFC3164のタイムスタンプはTZを持たず、VectorはこれをUTCとして解釈する。VMのローカルTZが
#   JST等だと未来時刻になりLokiが "timestamp too new" で拒否するため、必ず date -u(UTC) で出力する。
syslog_line() {
  local hostname="$1" tag="$2" msg="$3"
  printf '<134>%s %s %s: %s' "$(date -u '+%b %e %H:%M:%S')" "$hostname" "$tag" "$msg"
}

# --- logsrcコンテナ経由でVectorのsyslog(5514)へ1行送信する ---
#   docker exec -i でホスト側bashの文字列をそのままstdin転送する（入れ子クォート事故を避ける）。
#   wbitt/network-multitool には ncat が無く nc がある（arm64実機で確認）。nc -w1 のTCP送信で
#   Vector の syslog_tcp(0.0.0.0:5514) へ配送する。
send_syslog() {
  local line="$1"
  echo "$line" | sudo docker exec -i logsrc nc -w1 "$GW_IP" "$VECTOR_SYSLOG_PORT"
}

# --- MinIOにLoki用バケットを作成する ---
#   minio/minio イメージには mc(MinIO Client) が同梱されないため、
#   curlのAWS SigV4対応(--aws-sigv4, curl>=7.75必須)でS3 PUT Bucketを直接叩く。
create_minio_bucket() {
  echo "MinIO起動待ち..."
  for i in $(seq 1 30); do
    curl -sf "http://localhost:${MINIO_API_PORT}/minio/health/live" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -sf -X PUT \
    --aws-sigv4 "aws:amz:us-east-1:s3" \
    -u "${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}" \
    "http://localhost:${MINIO_API_PORT}/${MINIO_BUCKET}" \
    && echo "MinIOバケット ${MINIO_BUCKET} 作成完了" \
    || echo "MinIOバケット作成に失敗（既に存在する場合は無視して問題なし）"
}

case "${1:-deploy}" in
  deploy)
    # --- alog-lan（bridge名を alog-br0 に固定） ---
    sudo docker network create \
      --driver bridge \
      --subnet "$SUBNET" \
      --opt com.docker.network.bridge.name="$BR" \
      "$NET" 2>/dev/null || true

    # --- logsrc（AD/サーバ/NW機器の代表ログを送信する送信元。SYNスキャンの標的にもなる） ---
    sudo docker run -d --name logsrc \
      --network "$NET" --ip "$LOGSRC_IP" \
      "$IMG_MULTITOOL" sleep infinity

    # --- scanner（attack時にlogsrcへSYNスキャンを行う。nmap入りmultitool） ---
    sudo docker run -d --name scanner \
      --network "$NET" --ip "$SCANNER_IP" \
      "$IMG_MULTITOOL" sleep infinity

    # --- MinIO（S3互換。Lokiのchunksオフロード先。host modeで9001/9002を直接listen） ---
    mkdir -p "$MINIODIR"
    sudo docker run -d --name minio \
      --network host \
      -e MINIO_ROOT_USER="$MINIO_ROOT_USER" \
      -e MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD" \
      -v "${MINIODIR}":/data \
      "$IMG_MINIO" server /data --address ":${MINIO_API_PORT}" --console-address ":${MINIO_CONSOLE_PORT}"
    create_minio_bucket

    # --- Loki（host modeで3101を直接listen。chunksはMinIOへ。retentionはconfig参照） ---
    sudo docker run -d --name loki \
      --network host \
      -e MINIO_ROOT_USER="$MINIO_ROOT_USER" \
      -e MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD" \
      -v "${HERE}/loki/loki-config.yml":/etc/loki/loki-config.yml:ro \
      "$IMG_LOKI" -config.file=/etc/loki/loki-config.yml -config.expand-env=true

    # --- Vector（syslog 5514受信→VRLで正規化→Loki push。host modeで5514/9598を直接listen） ---
    sudo docker run -d --name vector \
      --network host \
      -v "${HERE}/vector/vector.yaml":/etc/vector/vector.yaml:ro \
      "$IMG_VECTOR" --config /etc/vector/vector.yaml

    # --- Suricata（host modeで alog-br0 を監視。scanner→logsrc のSYNスキャンを検知） ---
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
      --set vars.address-groups.HOME_NET="[${SUBNET}]" \
      --set vars.address-groups.EXTERNAL_NET=any

    # --- Promtail（eve.jsonをtail→Loki push） ---
    sudo docker run -d --name promtail \
      --network host \
      -v "${HERE}/promtail/promtail-config.yml":/etc/promtail/promtail-config.yml:ro \
      -v "${LOGDIR}":/var/log/suricata:ro \
      "$IMG_PROMTAIL" -config.file=/etc/promtail/promtail-config.yml

    # --- Grafana（Loki datasource + 3観点アラート + ダッシュボードを自動プロビジョン） ---
    sudo docker run -d --name grafana \
      --network host \
      -e GF_SERVER_HTTP_PORT="$GRAFANA_PORT" \
      -e GF_AUTH_ANONYMOUS_ENABLED=true \
      -e GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
      -e GF_SECURITY_ADMIN_PASSWORD=admin \
      -v "${HERE}/grafana/provisioning":/etc/grafana/provisioning:ro \
      "$IMG_GRAFANA"

    # --- Webhook受信器（アラート通知の受信確認用。詳細: webhook/README.md） ---
    #   ncat の -lk -c は multitool に無い（ncat自体が無い）。socat で TCP:9099 を待受し、
    #   fork で各接続の生バイト（GrafanaのHTTP POSTヘッダ＋JSON本文）をログに追記する。
    #   HTTPステータスは返さないが、アラート発報→Webhook到達の証跡取得が目的。
    mkdir -p "$WEBLOGDIR"
    sudo docker run -d --name webhook \
      --network host \
      -v "${WEBLOGDIR}":/weblog \
      "$IMG_MULTITOOL" sh -c "socat -u TCP-LISTEN:${WEBHOOK_PORT},fork,reuseaddr OPEN:/weblog/webhook.log,creat,append"

    echo "起動完了。"
    echo "  Loki:    curl -s 'http://localhost:${LOKI_PORT}/ready'"
    echo "  Grafana: curl -s localhost:${GRAFANA_PORT}/api/health"
    echo "  MinIO:   curl -s 'http://localhost:${MINIO_API_PORT}/minio/health/live'"
    echo "  次のゲート: ./deploy.sh logs でベースラインログ注入 → ./deploy.sh attack で異常トリガ"
    ;;

  logs)
    # --- ベースラインログ注入（正常系。3種の出自の代表ログ + 既知の送信元IP群） ---
    echo "ベースラインログを注入します（logsrc → vector:${VECTOR_SYSLOG_PORT}）..."
    for ip in 203.0.113.10 203.0.113.11 198.51.100.20; do
      send_syslog "$(syslog_line web01 "sshd[1111]" "Failed password for invalid user test from ${ip} port 51515 ssh2")"
    done
    send_syslog "$(syslog_line web01 sudo "alice : TTY=pts/0 ; PWD=/home/alice ; USER=root ; COMMAND=/usr/bin/cat /etc/shadow")"
    send_syslog "$(syslog_line dc01 eventlog "EventID=4625 Account Name: bob Source Network Address: 203.0.113.12")"
    send_syslog "$(syslog_line core-sw1 kernel "%LINEPROTO-5-UPDOWN: Line protocol on Interface GigabitEthernet0/1, changed state to down")"
    echo "注入完了。LogQLで確認: ./deploy.sh query"
    echo "※ 新規出現(attack b)を正しく検知させるには、logs実行から5分以上経過してから attack を実行すること。"
    ;;

  attack)
    # --- (a) 件数の変化: 既知IP(198.51.100.20)からのauth_fail連打 ---
    echo "=== (a) 件数の変化トリガ: 198.51.100.20 から認証失敗18連打 ==="
    for i in $(seq 1 18); do
      send_syslog "$(syslog_line web01 "sshd[2000]" "Failed password for invalid user root from 198.51.100.20 port 5$((1000 + i)) ssh2")"
    done

    # --- (b) 新規出現: 過去に出現実績のないsrc_ipからのauth_fail ---
    echo "=== (b) 新規出現トリガ: 未知の送信元IP(203.0.113.200)から認証失敗 ==="
    send_syslog "$(syslog_line web01 "sshd[2001]" "Failed password for invalid user admin from 203.0.113.200 port 51999 ssh2")"

    # --- (c) 値の変化: 直近5分の全イベント件数を閾値超過させる ---
    echo "=== (c) 値の変化トリガ: sudo実行ログを35件追加注入（イベント件数急増） ==="
    for i in $(seq 1 35); do
      send_syslog "$(syslog_line web01 sudo "alice : TTY=pts/0 ; PWD=/home/alice ; USER=root ; COMMAND=/usr/bin/id")"
    done

    # --- 参考: SYNスキャン（scanner→logsrc, Suricata sid:2000001 検知） ---
    echo "=== 参考: scanner(${SCANNER_IP}) → logsrc(${LOGSRC_IP}) へSYNスキャン ==="
    sudo docker exec scanner nmap -sS -p 1-200 "$LOGSRC_IP" || true

    echo "attack完了。5分以内に './deploy.sh query' と './deploy.sh alert' で3観点を確認してください。"
    ;;

  query)
    # --- LogQLで3観点を確認（Loki HTTP API） ---
    echo "=== (a) 件数の変化: 直近5分の auth_fail 件数 ==="
    curl -s -G "http://localhost:${LOKI_PORT}/loki/api/v1/query" \
      --data-urlencode 'query=sum(count_over_time({job="alog",event="auth_fail"} | json [5m]))'
    echo

    echo "=== (b) 新規出現: 過去1h(直近5分除く)に出現実績のないsrc_ip ==="
    curl -s -G "http://localhost:${LOKI_PORT}/loki/api/v1/query" \
      --data-urlencode 'query=sum by (src_ip) (count_over_time({job="alog",event="auth_fail"} | json [5m])) unless sum by (src_ip) (count_over_time({job="alog",event="auth_fail"} | json [1h] offset 5m))'
    echo

    echo "=== (c) 値の変化: 直近5分の全イベント件数 ==="
    curl -s -G "http://localhost:${LOKI_PORT}/loki/api/v1/query" \
      --data-urlencode 'query=sum(count_over_time({job="alog"} | json [5m]))'
    echo

    echo "=== 参考: Suricata SYNスキャン検知(eve.json alert, sid:2000001) ==="
    sudo grep -h '"event_type":"alert"' "${LOGDIR}/eve.json" 2>/dev/null | tail -5 || echo "(なし)"
    ;;

  alert)
    # --- Grafana Alertingの状態確認 + Webhook受信ログ確認 ---
    echo "=== Grafana Alerting 発報中アラート一覧 ==="
    curl -s "http://localhost:${GRAFANA_PORT}/api/alertmanager/grafana/api/v2/alerts" \
      || echo "(Grafana Alerting APIへの到達に失敗。起動直後は評価間隔(1m)の待ちが必要)"
    echo

    echo "=== Webhook受信ログ（直近40行, ${WEBLOGDIR}/webhook.log） ==="
    tail -n 40 "${WEBLOGDIR}/webhook.log" 2>/dev/null || echo "(まだ受信なし)"
    ;;

  ps)
    sudo docker ps --filter name='logsrc|scanner|vector|loki|promtail|grafana|minio|suricata|webhook' \
      --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
    ;;

  destroy)
    sudo docker rm -f logsrc scanner vector loki promtail grafana minio suricata webhook 2>/dev/null || true
    sudo docker network rm "$NET" 2>/dev/null || true
    echo "撤去完了（コンテナ9種＋${NET} を削除）。"
    ;;

  *)
    echo "usage: $0 {deploy|logs|attack|query|alert|ps|destroy}" >&2
    echo "  deploy  : alog-lan作成＋logsrc/scanner/minio/loki/vector/suricata/promtail/grafana/webhook起動" >&2
    echo "  logs    : ベースライン(正常系)ログをlogsrc→vectorへ注入" >&2
    echo "  attack  : 異常トリガ（認証失敗連打・新規IP出現・イベント急増・SYNスキャン）" >&2
    echo "  query   : LogQLで3観点(件数変化/新規出現/値変化)を確認" >&2
    echo "  alert   : Grafana Alerting状態 + Webhook受信ログを確認" >&2
    echo "  ps/destroy : 状態表示 / 全撤去" >&2
    exit 1
    ;;
esac
