---
type: runbook
theme: "Verona再現"
status: draft
date: 2026-07-21
tags: [verona, keycloak, idaas, sso, sase]
title: "Keycloak 手順 — IdP連携（発展）"
---

# Keycloak 手順 — IdP連携（発展）

Verona p26「証明書認証×IDaaS認証」（証明書認証にIDaaSアカウントでのユーザ認証を加えた
2要素認証・SSO）・p37「IDaaS連携でユーザ管理も効率化」を、[Keycloak](https://www.keycloak.org/)
で再現する（△簡略化。実際のVeronaが対応するEntra ID/Okta等の商用IDaaSではなく、OSSのKeycloak
自身をIdPとして使う）。

## 位置づけ（コア/発展の区分）

本機能は「発展」（config・docのみ用意。単独サブコマンドで起動できる形にする。SSO/証明書との
2要素連携までの完全な疎通は求めない）。[deploy.sh](../deploy.sh) の `deploy-idp` サブコマンドで
Keycloak単体（`start-dev`開発モード）は起動できる。

## 起動

```bash
./deploy.sh deploy-idp
# → http://localhost:8081/ (admin/admin) でAdmin Consoleにアクセス可能
```

## realm/client作成手順（想定）

```bash
# コンテナ内 kcadm.sh でログイン
sudo docker exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password admin

# Veronaラボ用realmを作成
sudo docker exec keycloak /opt/keycloak/bin/kcadm.sh create realms \
  -s realm=verona-lab -s enabled=true

# ZTNAクライアント向けのOIDCクライアントを作成
sudo docker exec keycloak /opt/keycloak/bin/kcadm.sh create clients \
  -r verona-lab -s clientId=verona-client -s publicClient=true \
  -s 'redirectUris=["http://localhost:8080/*"]' -s enabled=true

# テストユーザー作成
sudo docker exec keycloak /opt/keycloak/bin/kcadm.sh create users \
  -r verona-lab -s username=branch-user -s enabled=true
```

> 注意（未検証事項）: `kcadm.sh` のパスはKeycloakのバージョンにより
> `/opt/keycloak/bin/kcadm.sh`（Quarkus版, v17+）を想定しているが、`latest` タグでの
> 実際のパス・コマンド構文は本タスクでは検証していない。

## OpenZiti external-jwt-signer 連携の方針（発展・未実装）

Verona同様「証明書認証＋IDaaS認証の2要素」を目指す場合、OpenZitiの
[external-jwt-signer](https://openziti.io/docs/learn/core-concepts/security/authentication/jwt-signer)
機能を使い、Keycloakが発行したJWTをOpenZitiのidentity認証に組み込む方針が考えられる。

1. KeycloakでOIDCクライアント（verona-client）を発行し、JWKS URLを公開する。
2. `ziti edge create external-jwt-signer` でKeycloakのJWKS URLを登録し、
   `--issuer`／`--audience` をKeycloak realmの値に合わせる。
3. identity側の認証をJWTベースに切り替え、証明書認証（mTLS）とJWT認証の2要素で
   dial/bindを許可するpolicyを設計する。

本ラボでは上記を設計方針として記載するに留め、実装・疎通検証はスコープ外とする
（[02_基本設計/網屋Verona_OSS対応表.md](../../02_基本設計/網屋Verona_OSS対応表.md) で△評価）。

## 参照

- [02_基本設計/網屋Verona_OSS対応表.md](../../02_基本設計/網屋Verona_OSS対応表.md)
- [05_試験/試験計画書.md](../../05_試験/試験計画書.md) T-V6
- [36_ztna_openziti/04_構築/setup_ziti.sh](../../../36_ztna_openziti/04_構築/setup_ziti.sh)
