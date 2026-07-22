---
type: phase-doc
theme: "ZERO_zero_trust"
status: draft
date: 2026-07-04
tags: [zero-trust, ndr, netflow, zeek, suricata, siem]
title: "テーマZERO｜N3 NDR 構築スタブ"
---

# テーマZERO｜N3 NDR 構築スタブ

> **2026-07-05 実装済み・実機検証済み。** east-west（同一サブネット横方向）の SYN スキャンを host mode Suricata（ndr-br0 監視）で検知し、alert/flow を Loki/Grafana へ集約（実装先: テーマ42 `42_ndr_flow/`）。sid:1000001 の east-west alert（172.40.0.21→172.40.0.22）をメインセッションが独立に再検証。NetFlow は softflowd(arm64) 制限のため Suricata flow で代替。詳細は [試験結果](../../../../42_ndr_flow/05_試験/試験結果_2026-07-05.md)・[構築ログ](../../../../42_ndr_flow/04_構築/構築ログ_2026-07-05.md)。以下は当初の設計スタブ。

## 目的

east-west を含む通信を可視化し、フロー統計と DPI（Deep Packet Inspection）振る舞いから異常を検知して SIEM に集約する。「侵害前提（assume breach）」の検知面を成立させる。

## コンポーネント

| ノード | 役割 |
|---|---|
| Zeek / Suricata | ミラーからの DPI・振る舞い検知 |
| goflow2 | NetFlow/IPFIX の収集 |
| ntopng / ElastiFlow | フロー可視化 |
| 既存 Loki/Grafana（ZERO Phase 3） | ログ・メトリクスの集約先ダッシュボード |
| Faucet + OVS(mirror/SPAN) | 東西トラフィックを宣言的ミラーでセンサへ複製 |
| gauge(Prometheus:9303) | ポート統計/フローテレメトリ供給 |

## 依存

- ZERO Phase 3（Loki/Grafana）。フロー/DPI ログの集約先として既存構築を再利用する。
- ミラーポートまたは NetFlow の出力源として IOL または OVS が必要。

## ゲート条件（次へ進む条件）

- ミラーポートまたは NetFlow エクスポートから異常フロー（想定外の east-west 通信、スキャン挙動等）を検知できる。
- 検知結果を Loki/Grafana のダッシュボードで可視化できる。

## 実装先

**テーマ42（フロー可視化＆NDR）**。[ロードマップPHASE2](../../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md) を入口として参照する。テーマ35（Faucet／[README](../../../../35_faucet_sdn/README_Lab_Challenge.md)）：SDN基礎(Phase A)＋ミラー/SPAN・gauge統計→NDR(Phase B)を実機連携（2026-07-07検証済）。

## 実装時の作業リスト

- [ ] ミラーポートまたは NetFlow/IPFIX エクスポートの設定（IOL または OVS 側）
- [ ] goflow2 のデプロイとフロー収集の疎通確認
- [ ] Zeek/Suricata のデプロイと DPI ルール適用
- [ ] ntopng / ElastiFlow のデプロイとフロー可視化確認
- [ ] 既存 Loki/Grafana（ZERO Phase 3）への連携設定
- [ ] Faucetミラーポートをセンサ入力に使う
- [ ] 想定外の east-west 通信を意図的に発生させ検知できることを確認
- [ ] スキャン挙動を模擬し検知できることを確認
- [ ] Grafana ダッシュボードでの可視化確認

## 学べること

フロー可視化と DPI 振る舞い検知の役割分担、SIEM 連携の実務、Palo Alto Content-ID や Darktrace 系 NDR 製品の内部構造理解、NetFlow/IPFIX の実務知識。

## 参照

- [NW-ZT トラックロードマップ](../../../02_基本設計/NW-ZT_トラックロードマップ.md)
- [ロードマップPHASE2](../../../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md)
- [親スタブ](../README_nwzt_トラック.md)
