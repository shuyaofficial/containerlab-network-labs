---
type: phase-doc
theme: "ZERO_zero_trust"
phase: 6
status: draft
date: 2026-07-04
tags: [zero-trust, phase, device, step-ca, mtls]
title: "テーマZERO｜Phase 6 デバイス統制（step-ca mTLS）"
---

# テーマZERO｜Phase 6 デバイス統制（step-ca mTLS）

> 今回スコープでは**未デプロイ**（設計値）。このスタブは実装着手時の作業起点。詳細は [段階ロードマップ](../../02_基本設計/段階ロードマップ.md) Phase 6。

## 目的

端末証明書（mTLS）で「管理された端末か」を検証し、posture claim（端末状態を表す属性）を認可判断の入力にして条件分岐する。ID（誰か）＋デバイス（何の端末か）の二軸で「明示的検証」を成立させる。

## コンポーネント

| ノード | 役割 | ゾーン | 予定 IP | 待受 |
|---|---|---|---|---|
| step-ca | mTLS 証明書発行・posture claim モック | DMZ (zt-dmz) | 172.30.10.41 | 9000/HTTPS (ACME) |

- posture 収集は osquery 補助。実収集が難しければ posture claim を**モック**（固定属性で分岐を示す。FR-2）。発展: Wazuh エージェント。
- 判定連携先は Phase 2 の IAP（Pomerium）。証明書と posture を認可ポリシーの入力にする。

## 依存

- Phase 2（posture を渡す先の IAP）、Phase 3（判定ログの確認）。

## ゲート条件（次へ進む条件）

証明書を持たない端末を拒否し、posture claim（例: 準拠/非準拠）で `app` への到達可否を条件分岐できる（[要件定義書](../../01_要件定義/要件定義書.md) AC-6 / 試験 T-6-*）。

## 実装時の作業リスト

- [ ] `phase6_device/` に clab.yml（step-ca ノード）と deploy.sh
- [ ] arm64 manifest 確認（step-ca は Med。発行フローを軽く確認）
- [ ] CA を初期化し、端末証明書の発行フロー（ACME/mTLS）を用意
- [ ] `client` に端末証明書を配布、`external` は証明書なしのまま
- [ ] Pomerium に mTLS 検証を設定（証明書なし端末を拒否）（T-6-1）
- [ ] posture claim をモック（準拠/非準拠の属性）
- [ ] posture で到達可否が変わることを確認（T-6-2）
- [ ] 拒否・許可の判定が SIEM に記録されることを確認（T-6-3）
- [ ] [構築ログ](../構築ログ_テンプレート.md) を複製して記録

## 学べること

デバイス識別の mTLS、posture ベース認可、ID＋デバイスの二軸で明示的検証を成立させる設計、モックで実装可能性を先行確認する考え方。

## 参照

- [段階ロードマップ](../../02_基本設計/段階ロードマップ.md)
- [論理構成設計](../../02_基本設計/論理構成設計.md)（デバイス統制）
- [phase2_iap](../phase2_iap/README.md)
- [試験計画書](../../05_試験/試験計画書.md)
