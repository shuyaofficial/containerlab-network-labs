---
type: phase-doc
theme: "ZERO_zero_trust"
phase: 4
status: draft
date: 2026-07-04
tags: [zero-trust, phase, swg, mitmproxy, suricata]
title: "テーマZERO｜Phase 4 WEBセキュリティ（SWG）"
---

# テーマZERO｜Phase 4 WEBセキュリティ（SWG）

> 今回スコープでは**未デプロイ**（設計値）。このスタブは実装着手時の作業起点。詳細は [段階ロードマップ](../../02_基本設計/段階ロードマップ.md) Phase 4。

## 目的

外向き Web 通信を proxy に強制経由させ、SSL bump（TLS 復号）で内容を可視化し、不審通信を IDS で検知して SIEM に発報する。SWG/CASB を OSS で代替する。

## コンポーネント

| ノード | 役割 | ゾーン | 予定 IP | 待受 |
|---|---|---|---|---|
| mitmproxy | SWG（SSL bump）※第一候補 | DMZ（Untrust に足） | 172.30.10.31 | 8080 (proxy) / 8081 (web UI) |
| squid | SWG 代替（SSL bump） | DMZ（Untrust に足） | 172.30.10.32 | 3128 |
| suricata | IDS 代替 | DMZ (zt-dmz) | 172.30.10.33 | − |

- 第一候補は mitmproxy に集約（D-2）。squid の SSL bump / suricata が arm64 で不可なら **mitmproxy 一本化**（[軽量検証計画](../../03_詳細設計/軽量検証計画.md) 代替ルール）。IDS 不可でも「検知→SIEM 通知」の導線は Loki 側ルールで維持する。

## 依存

- Phase 3（IDS/検査の発報先 SIEM）。

## ゲート条件（次へ進む条件）

`client` の外向き通信が proxy 経由に強制され、SSL bump で内容が可視化でき、IDS 発報が Loki に届く（[要件定義書](../../01_要件定義/要件定義書.md) AC-4 / 試験 T-4-*）。

## 実装時の作業リスト

- [ ] `phase4_swg/` に clab.yml（SWG ノード、Untrust に足）と deploy.sh
- [ ] arm64 manifest 確認（mitmproxy は High、squid/suricata は Med）
- [ ] `client` の外向き通信を proxy に強制経由させる（環境変数/経路設定）
- [ ] SWG の CA 証明書を `client` に信頼させる（SSL bump 前提）
- [ ] SSL bump で HTTPS 内容が可視化できることを確認（T-4-2）
- [ ] IDS ルール（or Loki 側検知ルール）で不審通信を検知（T-4-3）
- [ ] 検知が Loki に届き Grafana で見えることを確認
- [ ] SSL bump はラボ内限定である前提を明記（基本設計書 セキュリティ方針）
- [ ] [構築ログ](../構築ログ_テンプレート.md) を複製して記録

## 学べること

SWG の透過/明示プロキシ、TLS 復号の仕組みとリスク、IDS 発報から SIEM までの導線、共通基盤集約（mitmproxy 兼務）の効き方。

## 参照

- [段階ロードマップ](../../02_基本設計/段階ロードマップ.md)
- [論理構成設計](../../02_基本設計/論理構成設計.md)（プロキシフロー）
- [軽量検証計画](../../03_詳細設計/軽量検証計画.md)
- [試験計画書](../../05_試験/試験計画書.md)
