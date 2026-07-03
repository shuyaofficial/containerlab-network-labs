---
type: phase-doc
theme: "ZERO_zero_trust"
phase: 0
status: done
date: 2026-07-04
tags: [zero-trust, phase, base, containerlab]
title: "テーマZERO｜Phase 0 土台"
---

# テーマZERO｜Phase 0 土台

docker bridge 4ゾーンのうち Phase 0 で使う `zt-untrust` / `zt-trust` の2ゾーンと、エンドポイント3台（`client` / `external` / `app`）で疎通の骨格を作る。以降の全 Phase の土台。詳細は [段階ロードマップ](../../02_基本設計/段階ロードマップ.md) Phase 0、[論理構成設計](../../02_基本設計/論理構成設計.md)。

## 目的

- docker bridge によるゾーン分離（Untrust / Trust）を containerlab 上に構築する。
- 関所（Phase 2 以降）が無い状態で、Untrust→Trust の直通が「設計上許可した経路のみ」であることを確認する土台とする。
- 規約一式（frontmatter / HTML ビルド / git）が回ることを確認する。

## ノード表

| ノード | 役割 | ゾーン | bridge | IP（データ面） | mgmt-ipv4 |
|---|---|---|---|---|---|
| client | 利用者端末（multitool） | Untrust | zt-untrust | 172.30.0.11/24 | 172.30.99.11 |
| external | 外部/未管理端末（multitool） | Untrust | zt-untrust | 172.30.0.12/24 | 172.30.99.12 |
| app | 保護対象サービス（multitool） | Trust | zt-trust | 172.30.20.21/24 | 172.30.99.21 |

- イメージ: `wbitt/network-multitool:latest`（内蔵 nginx で 80/tcp 応答）。
- `zt-untrust` / `zt-trust` は containerlab の `bridge` kind（ホスト側 Linux bridge）で表現。`deploy.sh` がデプロイ前に作成し、撤収時に削除する。
- mgmt ネットワークは `zt-base-mgmt`（172.30.99.0/24、他テーマと非衝突のレンジ）。データ面のゾーンサブネットは [IPアドレス管理表](../../02_基本設計/IPアドレス管理表.md) に準拠。

## デプロイ・確認・撤収コマンド

VM (`clab@orb`) 経由で実行する（[clab運用規約](../../../規約/clab運用規約.md) 準拠）。

```bash
# デプロイ（zt-untrust/zt-trust bridge 作成 → containerlab deploy）
ssh clab@orb "cd /Users/shuya/Documents/claude/Mac仮想環境構築/ZERO_zero_trust/04_構築/phase0_base && ./deploy.sh deploy"

# ノード状態確認
ssh clab@orb "cd /Users/shuya/Documents/claude/Mac仮想環境構築/ZERO_zero_trust/04_構築/phase0_base && ./deploy.sh inspect"

# 疎通確認（client → app）
ssh clab@orb "docker exec clab-zt-base-client ping -c3 172.30.20.21"
ssh clab@orb "docker exec clab-zt-base-client curl -sS http://172.30.20.21/"

# 撤収（containerlab destroy → bridge 削除）
ssh clab@orb "cd /Users/shuya/Documents/claude/Mac仮想環境構築/ZERO_zero_trust/04_構築/phase0_base && ./deploy.sh destroy"
```

- `iouyap` サブコマンドは IOL 不使用のため「本テーマでは不要」のメッセージのみ表示する。

## ゲート条件（次へ進む条件）

`client` → `app` の ping / curl が通り、`node 規約/ビルド/build.mjs --check` が pass すること（[段階ロードマップ](../../02_基本設計/段階ロードマップ.md) Phase 0）。試験結果は [試験結果_2026-07-04](../../05_試験/試験結果_2026-07-04.md)、試験項目は [試験計画書](../../05_試験/試験計画書.md) T-0-*。

## 学べること

docker bridge によるゾーン分離、containerlab のノード命名規約、Untrust→Trust 直通禁止の効き方。

## 参照

- [段階ロードマップ](../../02_基本設計/段階ロードマップ.md)
- [論理構成設計](../../02_基本設計/論理構成設計.md)
- [IPアドレス管理表](../../02_基本設計/IPアドレス管理表.md)
- [試験計画書](../../05_試験/試験計画書.md)
- [clab運用規約](../../../規約/clab運用規約.md)
