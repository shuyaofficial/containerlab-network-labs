---
type: phase-doc
theme: "ZERO_zero_trust"
phase: 2
status: draft
date: 2026-07-04
tags: [zero-trust, phase, iap, pomerium, oauth2-proxy]
title: "テーマZERO｜Phase 2 NWセキュリティ（IAP）"
---

# テーマZERO｜Phase 2 NWセキュリティ（IAP）

> 今回スコープでは**未デプロイ**（設計値）。このスタブは実装着手時の作業起点。詳細は [段階ロードマップ](../../02_基本設計/段階ロードマップ.md) Phase 2。

## 目的

`app` の手前に関所（IAP）を置き、未認証アクセスを拒否する。認証を Keycloak に委譲し、認可済みリクエストのみ Trust の `app` へ転送する。ZTNA/IAP の「アプリ手前で毎回検証」を成立させる。

## コンポーネント

| ノード | 役割 | ゾーン | 予定 IP | 待受 |
|---|---|---|---|---|
| oauth2-proxy | IAP 起点（最小の未認証拒否） | DMZ（Untrust/Trust に足） | 172.30.10.22 | 4180/HTTP |
| pomerium | IAP（認可ポリシー適用） | DMZ（Untrust/Trust に足） | 172.30.10.21 | 443/80 |

- 起点は oauth2-proxy（D-5）。まず「未認証拒否」を最小で示し、Pomerium で認可ポリシーへ高度化する。発展: OpenZiti。

## 依存

- Phase 1（OIDC トークン取得が前提。IdP 連携先が必要）。

## ゲート条件（次へ進む条件）

未認証で `app` にアクセスすると拒否され、Keycloak ログイン後のみ `app` に到達できる。Untrust から Trust への直通は不可（[要件定義書](../../01_要件定義/要件定義書.md) AC-2 / 試験 T-2-*）。

## 実装時の作業リスト

- [ ] `phase2_iap/` に clab.yml（IAP ノード、Untrust/DMZ/Trust マルチホーム）と deploy.sh
- [ ] Keycloak を OIDC プロバイダとして設定（client id/secret はシークレット注入）
- [ ] redirect URL を Phase 1 の client 設定と一致させる
- [ ] `app` への upstream/転送経路（Trust 側の足）を設定
- [ ] 未認証アクセスが拒否/リダイレクトされることを確認（T-2-1）
- [ ] ログイン後に `app` へ到達できることを確認（T-2-2）
- [ ] Untrust→Trust の直通が不可であることを確認（T-2-3）
- [ ] 認可 allow/deny ログの出力を確認（Phase 3 で集約）
- [ ] [構築ログ](../構築ログ_テンプレート.md) を複製して記録

## 学べること

IAP/ZTNA の実装、認証委譲、認可の入口を1点に集約する設計、Untrust→Trust 直通禁止の効き方。

## 参照

- [段階ロードマップ](../../02_基本設計/段階ロードマップ.md)
- [論理構成設計](../../02_基本設計/論理構成設計.md)（認証フロー）
- [phase1_id](../phase1_id/README.md)
- [試験計画書](../../05_試験/試験計画書.md)
