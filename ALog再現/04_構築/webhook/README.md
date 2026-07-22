---
type: build-log
theme: "ALog再現"
status: draft
date: 2026-07-21
tags: [alog, webhook, grafana-alerting, notification]
title: "簡易Webhook受信器 — ALog再現アラート通知確認用"
---

# 簡易Webhook受信器 — ALog再現アラート通知確認用

ALogのp18「メールやWebhookによるアラート通知」のうち、Webhook通知の受信確認を行うための最小構成。
`wbitt/network-multitool` コンテナ内の `socat` を用いてTCP 9099を待受させ、
Grafana Alerting の webhook contact point（[../grafana/provisioning/alerting/contactpoints.yaml](../grafana/provisioning/alerting/contactpoints.yaml)、宛先 `http://localhost:9099`）からのPOSTボディをファイルへ追記するだけの受信器。
専用のWebhook受信サーバ用イメージは、環境準備で確認済みのarm64イメージ一覧に含まれないため採用しない。

当初は`ncat`（nmap付属netcat）の`-lk -c`（keep-open＋接続コマンド実行）を想定していたが、
`wbitt/network-multitool`にはarm64実機で`ncat`が同梱されておらず（`nc`/`nmap`/`curl`/`socat`は同梱）、
`socat`へ切り替えた（実機確認の詳細は[../構築ログ_2026-07-21.md](../構築ログ_2026-07-21.md)を参照）。

## 起動方法（`deploy.sh deploy` に内包）

```bash
mkdir -p "${HERE}/webhook/log"
sudo docker run -d --name webhook \
  --network host \
  -v "${HERE}/webhook/log":/weblog \
  wbitt/network-multitool:latest \
  sh -c "socat -u TCP-LISTEN:9099,fork,reuseaddr OPEN:/weblog/webhook.log,creat,append"
```

- `TCP-LISTEN:9099,fork,reuseaddr`: 9099/tcpで待受し続け、`fork`により複数回の通知を連続して受け付ける。
- `OPEN:/weblog/webhook.log,creat,append`: 受信した接続内容（HTTPリクエスト全体、ヘッダ＋JSONボディ）をそのまま
  ホスト側 bind mount（`${HERE}/webhook/log/webhook.log`）へ`-u`（unidirectional）で片方向コピー・追記する。

## 確認方法

```bash
./deploy.sh alert
# 内部的には次を実行している:
#   tail -n 40 "${HERE}/webhook/log/webhook.log"
```

Grafana Alertingがルール発火時に `alog-webhook` contact point 経由でPOSTすると、
`webhook.log` に生のHTTPリクエスト（`POST / HTTP/1.1` ヘッダ＋JSONボディ）が追記される。
JSONボディには `alerts[].labels.axis`（count_change / new_appearance / value_change）が含まれ、
3観点のどれで発報したかを確認できる。

## 既知の制約

- `socat` は簡易TCPリスナーであり、HTTPステータスコードを返さない（Grafana側はレスポンス欠如を
  タイムアウトとして扱う可能性がある）。学習用の受信確認が目的であり、本番のWebhook受信実装としては
  推奨しない（実運用ではSlack/PagerDuty等の正規Webhookエンドポイント、またはHTTPレスポンスを返す
  簡易APIサーバに置き換えること）。
