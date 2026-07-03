---
type: phase-doc
theme: "ZERO_zero_trust"
phase: 1
status: draft
date: 2026-07-04
tags: [zero-trust, phase, id, keycloak, oidc]
title: "テーマZERO｜Phase 1 ID統制（Keycloak）"
---

# テーマZERO｜Phase 1 ID統制（Keycloak）

> 今回スコープでは**未デプロイ**（設計値）。このスタブは実装着手時の作業起点。詳細は [段階ロードマップ](../../02_基本設計/段階ロードマップ.md) Phase 1。

## 目的

OIDC IdP を立て、認可コードフローで ID/アクセストークンを発行できる状態を作る。以降の認可（Phase 2）とデバイス統制（Phase 6）の認証起点となる。

## コンポーネント

| ノード | 役割 | ゾーン | 予定 IP | 待受 |
|---|---|---|---|---|
| keycloak | OIDC IdP・ユーザー/ロール管理（内蔵 DB） | DMZ (zt-dmz) | 172.30.10.11 | 8080/HTTP |

- 発展: OpenLDAP 連携（[実装可能性マトリクス](../../02_基本設計/実装可能性マトリクス.md)）。今回は内蔵 DB で完結。

## 依存

- Phase 0（ネットワーク・docker DNS）が合格していること。

## ゲート条件（次へ進む条件）

管理画面で realm/client を作成し、token endpoint から `curl` またはブラウザで OIDC トークンを取得できる（[要件定義書](../../01_要件定義/要件定義書.md) AC-1 / 試験 T-1-*）。

## 実装時の作業リスト

- [ ] `phase1_id/` に clab.yml（keycloak ノード追加）と deploy.sh を用意
- [ ] arm64 manifest を確認して起動（[軽量検証計画](../../03_詳細設計/軽量検証計画.md)）
- [ ] admin 初期認証情報を**環境変数/シークレットで注入**（設定に直書きしない）
- [ ] realm を作成
- [ ] client（認可コードフロー用、redirect URL は Phase 2 の IAP に合わせる）を作成
- [ ] テストユーザー・ロールを作成
- [ ] token endpoint から `curl` でトークン取得を確認（T-1-3）
- [ ] Promtail 連携に備えログ出力先を確認（Phase 3 で集約）
- [ ] [構築ログ](../構築ログ_テンプレート.md) を複製して記録

## 学べること

OIDC 認可コードフロー、realm/client/scope の役割、IdP をアプリから分離する意味。

## 参照

- [段階ロードマップ](../../02_基本設計/段階ロードマップ.md)
- [論理構成設計](../../02_基本設計/論理構成設計.md)（認証フロー）
- [試験計画書](../../05_試験/試験計画書.md)
