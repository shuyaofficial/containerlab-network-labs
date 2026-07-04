---
type: phase-doc
theme: "ZERO_zero_trust"
status: draft
date: 2026-07-04
tags: [zero-trust, nwzt, roadmap, nac, ztna, ndr, microsegmentation]
title: "テーマZERO｜NW-ZTトラック 構築起点（親スタブ）"
---

# テーマZERO｜NW-ZTトラック 構築起点（親スタブ）

> 今回スコープでは**未デプロイ**（設計・教材・arm64検証まで）。実装は番号テーマへ委譲する。このスタブは実装着手時の作業起点であり、ここ自体は構築を持たない。

## 位置づけ

ZERO は NW-ZT トラックの**設計ハブ（司令塔）**。N1-N4 それぞれの目的・依存・ゲート条件をここで定義し、実装の実体は既存の番号テーマ側に置く。詳細な定義・比較表・依存関係図は [NW-ZT トラックロードマップ](../../02_基本設計/NW-ZT_トラックロードマップ.md) を正とする。本ファイルは構築フォルダ側から見た「入口」に過ぎない。

## N1-N4 一覧と実装委譲先

| N | 観点 | スタブ | 主実装先 |
|---|---|---|---|
| N1 | NAC / 802.1X | [N1_NAC/README.md](N1_NAC/README.md) | テーマ29（RADIUS）＋テーマ31（NAC/802.1X）— [ロードマップPHASE2](../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md) 経由 |
| N2 | SDP型ZTNA | [N2_SDP_ZTNA/README.md](N2_SDP_ZTNA/README.md) | 新規（OpenZiti、番号未採番） |
| N3 | NDR | [N3_NDR/README.md](N3_NDR/README.md) | テーマ42（フロー可視化＆NDR）— [ロードマップPHASE2](../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md) 経由 |
| N4 | μセグメンテーション | [N4_microseg/README.md](N4_microseg/README.md) | テーマ31拡張＋テーマ22参照 |

番号テーマのフォルダは現状未作成または中身が薄いため、各スタブから番号テーマ MD へは直リンクしない。実在する [ロードマップPHASE2](../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md) を入口として参照する。

## 着手順序

「できそうな順」＝ arm64 確度が高い・依存が少ないものを優先する。

1. **N1 NAC** — 土台。認証で入口を締め、動的 VLAN でセグメントを割り当てる。N4 はこの VLAN 基盤に乗る。
2. **N2 SDP-ZTNA** — ZERO Phase 2（IAP）の概念を前提に、その対比として実装。IAP型との実装差を体験する。
3. **N3 NDR** — 既存 SIEM（ZERO Phase 3）に乗る。フロー/DPI ログの集約先として Loki/Grafana を再利用する。
4. **N4 μセグ** — 最後。N1 の VLAN 基盤とテーマ22 の既存資産を前提にする。

## 共通の前提

- **IOL L2 起動に時間がかかる**。N1・N4 は Cisco IOL L2 を使うため、検証セッションの最初にコールドスタートで起動しておく。
- **接続は `ssh clab@orb`**。containerlab ホストへの入口はこの1本に統一する。
- **D-7 で IOL 連携を解禁**。NW-ZT トラックは L7 トラック（Phase 0-6、docker 完結、D-1）とは独立した別トラックであり、IOL（実機相当）連携は D-7 から扱う。Phase 番号と N 番号を混同しない。

## 依存

- [NW-ZT トラックロードマップ](../../02_基本設計/NW-ZT_トラックロードマップ.md)（N1-N4 の定義・ゲート条件・番号テーマ対応表の正）
- ZERO Phase 1（Keycloak、N1 の認証源として任意連携）
- ZERO Phase 2（IAP、N2 の対比先）
- ZERO Phase 3（Loki/Grafana、N3 のログ集約先）

## ゲート条件（次へ進む条件）

本スタブ自体はゲートを持たない。各 N のゲート条件は個別スタブおよび [NW-ZT トラックロードマップ](../../02_基本設計/NW-ZT_トラックロードマップ.md) の N ↔ 番号テーマ対応表を参照する。

## 実装時の作業リスト

- [ ] IOL L2 のコールドスタート時間を見積もり、検証セッション計画に組み込む
- [ ] `ssh clab@orb` での接続確認
- [ ] N1 から着手し、動的 VLAN 基盤を先に固める
- [ ] N1 完了後、N2・N3 は並行着手可能（相互依存なし）
- [ ] N4 は N1 完了後・テーマ22 資産確認後に着手
- [ ] 各 N のスタブ内チェックリストを実装先の番号テーマ側で消化

## 学べること

設計ハブと実装テーマを分離する委譲構造そのもの。「司令塔が定義し、実装は既存資産に寄せる」設計の型。NAC→ZTNA→NDR→μセグという防御層の積み上げ順序と依存関係。

## 参照

- [NW-ZT トラックロードマップ](../../02_基本設計/NW-ZT_トラックロードマップ.md)
- [ロードマップPHASE2](../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md)
- [frontmatterスキーマ](../../../規約/frontmatterスキーマ.md)
