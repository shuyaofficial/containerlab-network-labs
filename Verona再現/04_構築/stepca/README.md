---
type: runbook
theme: "Verona再現"
status: draft
date: 2026-07-21
tags: [verona, stepca, posture, pki, sase]
title: "step-ca 手順 — デバイスポスチャー（発展）"
---

# step-ca 手順 — デバイスポスチャー（発展）

Verona p34「デバイスポスチャー機能」（接続前に端末のセキュリティ状態を自動チェックし、要件を
満たさない端末は接続をブロックする）を、[smallstep/step-ca](https://smallstep.com/docs/step-ca)
のクライアント証明書発行 ＋ [check_posture.sh](../posture/check_posture.sh) の簡易チェックで
再現する（△簡略化。osqueryはarm64非対応のため実際のEDR製品連携は行わない）。

## 位置づけ（コア/発展の区分）

本機能は「発展」（config・docのみ用意。単独サブコマンドで起動できる形にする。連携までは求めない）。
[deploy.sh](../deploy.sh) の `deploy-posture` サブコマンドで step-ca コンテナ単体は起動できるが、
「発行した証明書を実際にOpenZiti/Squidの認可判断に接続する」統合は行わない。

## 初期化手順

`./deploy.sh deploy-posture` は `smallstep/step-ca:latest` イメージの自動初期化用環境変数
（`DOCKER_STEPCA_INIT_*`）を使い、コンテナ起動時にルートCA・中間CA・デフォルトプロビジョナを
自動生成する想定。

```bash
./deploy.sh deploy-posture
# 内部で以下相当が実行される（DOCKER_STEPCA_INIT_* env varによる自動init）:
#   DOCKER_STEPCA_INIT_NAME=Verona-Lab-CA
#   DOCKER_STEPCA_INIT_DNS_NAMES=step-ca,localhost,127.0.0.1
#   DOCKER_STEPCA_INIT_PASSWORD=verona-lab-posture
```

> 注意（未検証事項）: `DOCKER_STEPCA_INIT_*` 環境変数によるコンテナ内自動初期化は
> smallstep公式イメージのentrypoint仕様に基づくが、本タスクではdocker実行検証をしていない。
> `latest` タグでの挙動がドキュメントと差異がある場合は `docker logs step-ca` を確認し、
> 必要であれば手動初期化（`step ca init`）に切り替えること。

## クライアント証明書の発行（想定手順）

```bash
# コンテナ内でCA fingerprintを確認
sudo docker exec step-ca step certificate fingerprint /home/step/certs/root_ca.crt

# クライアント（branch-client等）側でCAをブートストラップし証明書を発行
sudo docker exec branch-client step ca bootstrap \
  --ca-url https://step-ca:9000 --fingerprint <上記fingerprint>
sudo docker exec branch-client step ca certificate "verona-branch-client" \
  /tmp/posture/client.crt /tmp/posture/client.key
```

## ポスチャーチェックとの連携（モック）

発行した証明書を [check_posture.sh](../posture/check_posture.sh) に渡すことで、
「証明書の有無」を接続可否の一次条件として扱う（Verona本来の「ドメイン参加有無・EDR稼働状況」の
簡略代替）。

```bash
# 証明書あり・擬似EDRバージョン要件を満たす場合 → OK
VERONA_EDR_VERSION=2.1 ./posture/check_posture.sh /tmp/posture/client.crt

# 証明書が無い場合 → NG（接続拒否）
./posture/check_posture.sh /tmp/posture/nonexistent.crt

# 擬似EDRバージョンが要件未満の場合 → NG（接続拒否）
VERONA_EDR_VERSION=1.0 ./posture/check_posture.sh /tmp/posture/client.crt
```

## 再現度・簡略化ポイント

| Verona機能 | 本ラボでの再現 |
|---|---|
| ドメイン参加有無チェック | ❌ 未実装（Windows AD相当の概念が本ラボの構成に存在しない） |
| EDR製品（Defender/ESET/SentinelOne）の稼働状況・バージョンチェック | △ 環境変数によるモック判定に簡略化 |
| クライアント証明書の存在確認 | ✅ step-ca発行証明書の有無で代替再現 |
| 接続拒否のブロッキング動作 | △ check_posture.sh単体のexit code判定まで。OpenZiti/Squidの実際の認可フローへの自動連携は未実装 |

## 参照

- [check_posture.sh](../posture/check_posture.sh)
- [02_基本設計/網屋Verona_OSS対応表.md](../../02_基本設計/網屋Verona_OSS対応表.md)
- [05_試験/試験計画書.md](../../05_試験/試験計画書.md) T-V5
