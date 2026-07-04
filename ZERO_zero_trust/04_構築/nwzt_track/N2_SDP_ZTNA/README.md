---
type: phase-doc
theme: "ZERO_zero_trust"
status: draft
date: 2026-07-04
tags: [zero-trust, ztna, sdp, openziti]
title: "テーマZERO｜N2 SDP型ZTNA 構築スタブ"
---

# テーマZERO｜N2 SDP型ZTNA 構築スタブ

> 今回スコープでは**未デプロイ**（設計値）。このスタブは実装着手時の作業起点。詳細な定義・比較表は [NW-ZT トラックロードマップ](../../../02_基本設計/NW-ZT_トラックロードマップ.md) N2 を正とする。

## 目的

IAP型（アプリ手前の関所）に対し、SDP型（内向きポートを一切開けず、外向きの張り出しでのみ到達可能にする）を体験する。Zscaler ZPA 相当の仕組みを理解する。

## コンポーネント

| ノード | 役割 |
|---|---|
| OpenZiti controller | ポリシー・identity・service の管理 |
| OpenZiti router | オーバーレイ経路の中継（edge router） |
| tunneler | クライアント/アプリ側の透過的接続エージェント |

発展として Headscale / Netbird（メッシュ VPN 型）を比較検証する余地あり。

## 依存

- ZERO Phase 2（IAP）の概念を前提とし、その対比として実装する。IAP と SDP の実装差を体験するのが目的のため、Phase 2 の完了自体は必須ではない。

## ゲート条件（次へ進む条件）

- `app` 側は内向きポートを一切開けない。
- app-connector（外向き接続）経由でのみ、認可済みクライアントが到達できる。
- 未認可のクライアントは名前解決すら行えない（暗黙拒否＝ dark to unauthorized）。

## 実装先

**新規（番号未採番）**。ZERO 内で設計を進め、実装着手時に番号テーマとして採番する。現時点では [ロードマップPHASE2](../../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md) のIAP関連記述を対比の参照先とする。

## 実装時の作業リスト

- [ ] OpenZiti controller / router のデプロイ
- [ ] identity の enrollment（クライアント/アプリ双方）
- [ ] service 定義（`app` への到達経路をサービスとして表現）
- [ ] policy 定義（identity ↔ service の認可紐付け）
- [ ] tunneler の設定（透過的アクセスの確認）
- [ ] `app` 側で内向きポートが非開放のままであることの確認
- [ ] 未認可クライアントから名前解決・到達ともに不可であることの確認（暗黙拒否）
- [ ] IAP型（ZERO Phase 2）との実装差の整理・比較メモ作成

## 学べること

SDP vs IAP の実装差、「内向きを一切開けない」ネットワークモデル、broker/connector アーキテクチャ、アプリ埋め込み型 ZTNA（Zscaler ZPA 系）の内部構造理解。

## 参照

- [NW-ZT トラックロードマップ](../../../02_基本設計/NW-ZT_トラックロードマップ.md)
- [ロードマップPHASE2](../../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md)
- [親スタブ](../README_nwzt_トラック.md)
