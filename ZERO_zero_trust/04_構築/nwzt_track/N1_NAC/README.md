---
type: phase-doc
theme: "ZERO_zero_trust"
status: draft
date: 2026-07-04
tags: [zero-trust, nac, 802.1x, radius, freeradius, iol]
title: "テーマZERO｜N1 NAC / 802.1X 構築スタブ"
---

# テーマZERO｜N1 NAC / 802.1X 構築スタブ

> 今回スコープでは**未デプロイ**（設計値）。このスタブは実装着手時の作業起点。詳細な定義・比較表は [NW-ZT トラックロードマップ](../../../02_基本設計/NW-ZT_トラックロードマップ.md) N1 を正とする。

## 目的

認証されない端末を LAN に参加させない。802.1X/MAB で入口を締め、認証結果に応じて動的に VLAN を割り当てる。RADIUS CoA で稼働中セッションを強制再認証できるようにする。

## コンポーネント

| ノード | 役割 |
|---|---|
| FreeRADIUS | 認証サーバ（AAA）。dot1x/MAB のバックエンド |
| Cisco IOL L2 | 認証者（Authenticator）。ポート単位で 802.1X/MAB を実行するスイッチ |
| client | サプリカント（認証を受ける側の端末） |

任意で ZERO Phase 1 の Keycloak を LDAP/OIDC バックエンドとして FreeRADIUS に連携させる発展あり。

## 依存

- 単独で成立（ZERO Phase 1 の Keycloak 連携は任意）。
- N4（μセグ）はこの N1 の VLAN 基盤に乗るため、N1 が先行する。

## ゲート条件（次へ進む条件）

- 未認証端末が隔離 VLAN に落ちる。
- 認証成功端末が業務 VLAN に動的に割り当てられる（RADIUS 属性 Tunnel-Private-Group-ID 等）。
- RADIUS CoA（Change of Authorization）で稼働中セッションを強制再認証できる。

## 実装先

**テーマ29（RADIUS）＋テーマ31（NAC/802.1X）**。[ロードマップPHASE2](../../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md) を入口として参照する。実装フォルダは現状未作成のため、番号テーマ MD への直リンクは張らない。

## 実装時の作業リスト

- [ ] Cisco IOL L2 をデプロイ（起動に時間がかかる点を見積もりに含める）
- [ ] FreeRADIUS の設定（clients.conf、users、EAP 設定）
- [ ] スイッチ側 dot1x/MAB の設定投入
- [ ] 動的 VLAN 割当（RADIUS 属性による VLAN 切替）の設定
- [ ] RADIUS CoA によるセッション強制再認証の検証
- [ ] 未認証端末が隔離 VLAN に落ちることの確認
- [ ] 認証成功端末が業務 VLAN に入ることの確認
- [ ] 任意: Keycloak を LDAP/OIDC バックエンドとして連携

## 学べること

802.1X（EAP）/MAB/CoA/動的 VLAN の仕組み、RADIUS 属性（Tunnel-Private-Group-ID 等）による VLAN 制御、IP アドレスに依存しない入口制御。商用 NAC 製品（ISE/ClearPass）の内部構造理解。

## 参照

- [NW-ZT トラックロードマップ](../../../02_基本設計/NW-ZT_トラックロードマップ.md)
- [ロードマップPHASE2](../../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md)
- [親スタブ](../README_nwzt_トラック.md)
