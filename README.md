---
type: readme
theme: "リポジトリ"
status: done
date: 2026-07-04
tags: [containerlab, network-lab, cisco, zero-trust]
title: "Mac Containerlab ネットワーク学習ラボ"
---

# Mac Containerlab ネットワーク学習ラボ

Apple Silicon Mac 上の [Containerlab](https://containerlab.dev/)（OrbStack Linux VM）で、
Cisco IOL を中心に企業ネットワークを再現・検証する学習ラボ集。基礎ルーティングから
大規模キャンパス LAN、そしてゼロトラストの OSS 実装検証（テーマZERO）までを段階的に扱う。

## このリポジトリの歩き方

| 入口 | 内容 |
|---|---|
| [規約/](規約/README.md) | ラボ作成の標準（ディレクトリ構成・ドキュメント雛形・clab運用規約・MD→HTMLビルド） |
| [ロードマップ/](ロードマップ/) | 学習ロードマップ（全43テーマ計画）と進捗管理 |
| [環境/](環境/) | 実行環境の説明・再構築 runbook・イメージマニフェスト |
| [ZERO_zero_trust/](ZERO_zero_trust/README_Lab_Challenge.md) | ゼロトラスト6観点を OSS × arm64 で実装する検証ラボ |
| `NN_*/` | 個別テーマ（`01_要件定義`〜`05_試験` の標準5階層） |

各テーマは要件定義 → 基本設計 → 詳細設計 → 構築 → 試験の順で設計文書を備える。
設計文書は Markdown をソースとし、[規約/ビルド/](規約/ビルド/README.md) で
閲覧用 HTML（`docs/`）を生成する。

## 実行環境

- ホスト: Apple Silicon Mac（arm64）
- 仮想化: OrbStack Linux VM `clab`（Ubuntu 24.04 / arm64）
- ラボ: Containerlab 0.76.1 + Docker、Cisco IOL は x86 エミュレーション
- 詳細・再構築手順: [環境/rebuild_runbook.md](環境/rebuild_runbook.md)

## ライセンス・注意事項

- **Cisco IOL/IOU イメージおよびライセンス（IOURC）は本リポジトリに含まれない。** 各自で正規に用意すること。
  entrypoint スクリプトのライセンス欄はプレースホルダ（`0000...`）で、利用者自身の値に置き換える。
- `clab-*/` のランタイム生成物（TLS 秘密鍵を含む）は `.gitignore` で除外している。
- ラボ内の認証情報（`admin/admin` 等）は検証用の既定値であり、本番設定ではない。

## テーマZERO（ゼロトラスト）

商用ゼロトラスト製品（Cisco Secure Access / Palo Alto / Zscaler 等）はライセンス上
個人検証が難しいため、OSS で 6観点（ID統制 / デバイス統制 / ネットワーク /
WEBセキュリティ / DLP / SIEM）を arm64 上に再現できるかを先行検証する。
2026-07-04 の実測で対象17イメージ中15が arm64 ネイティブ対応と確定し、
Phase 0（土台）は疎通ゲートに合格済み。詳細は
[ZERO_zero_trust/02_基本設計/実装可能性マトリクス.md](ZERO_zero_trust/02_基本設計/実装可能性マトリクス.md)。
