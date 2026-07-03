---
type: standard
theme: "規約"
status: done
date: 2026-07-03
tags: [standard, frontmatter, metadata]
title: "frontmatterスキーマ — 値辞書"
---

# frontmatterスキーマ

全Markdownファイルの先頭に必ずYAML frontmatterを付ける。用途は2つ：
**grep横断検索**（Obsidian/CLIからテーマ・状態・種別で絞り込む）と **HTMLビルド**（title・パンくず・タグチップ・最終更新・警告バナーの描画）。

## フィールド定義

| フィールド | 必須 | 型 | 説明 |
|---|---|---|---|
| `type` | ✅ | 列挙（下表） | ドキュメント種別 |
| `theme` | ✅ | 文字列（引用符付き） | テーマフォルダ名と完全一致（例: `"ZERO_zero_trust"`） |
| `phase` | フェーズ型のみ | 整数 0-6 | ゼロトラスト等のフェーズ番号 |
| `status` | ✅ | 列挙（下表） | 文書の状態 |
| `date` | ✅ | YYYY-MM-DD | 最終更新日（ISO 8601） |
| `tags` | ✅ | 配列 | 3〜6個。小文字kebab-case、日本語可 |
| `title` | ✅ | 文字列 | HTML `<title>`・TOC・パンくず用の表示名 |

## type の値辞書

| 値 | 対象ファイル |
|---|---|
| `readme` | README_Lab_Challenge.md |
| `login` | 00_ログイン/ログインコマンド.md |
| `requirements` | 01_要件定義/要件定義書.md |
| `basic-design` | 02_基本設計/基本設計書.md・論理構成設計.md |
| `ip-table` | 02_基本設計/IPアドレス管理表.md |
| `param-sheet` | 03_詳細設計/パラメータシート*.md |
| `cli-commands` | 03_詳細設計/CLI投入コマンド.md |
| `build-log` | 04_構築/構築ログ*.md |
| `test-plan` | 05_試験/試験計画書.md |
| `test-result` | 05_試験/試験結果_YYYY-MM-DD.md |
| `troubleshoot` | 05_試験/切り分けシート.md |
| `feasibility` | 実装可能性マトリクス・軽量検証計画/結果 |
| `roadmap` | 段階ロードマップ・ロードマップ/配下 |
| `phase-doc` | 04_構築/phaseN 設計文書 |
| `explainer` | 解説/phaseN_解説.md（なぜこの構成か／触って確認する手順） |
| `runbook` | 手順書（rebuild_runbook 等） |
| `standard` | 規約/配下 |
| `proposal` | 改善提案文書 |

## status の値辞書

| 値 | 意味 | HTMLビルド時の扱い |
|---|---|---|
| `draft` | 執筆中 | 「下書き」バッジ |
| `review` | レビュー待ち | 「レビュー中」バッジ |
| `done` | 確定 | バッジなし |
| `superseded` | 新版に置換済み | **警告バナー表示**（誤読防止） |

## 記入例

```yaml
---
type: feasibility
theme: "ZERO_zero_trust"
phase: 0
status: review
date: 2026-07-03
tags: [zero-trust, arm64, keycloak, feasibility]
title: "ゼロトラスト6観点 実装可能性マトリクス"
---
```

## grepレシピ（横断検索の定型）

```bash
# テーマ横断: あるテーマの全文書
grep -rl 'theme: "ZERO_zero_trust"' Mac仮想環境構築/ --include='*.md'

# 未完文書の棚卸し
grep -rl 'status: draft' Mac仮想環境構築/ --include='*.md'

# 種別で抽出（全テーマの試験計画だけ）
grep -rl 'type: test-plan' Mac仮想環境構築/ --include='*.md'

# タグ検索
grep -rl 'zero-trust' Mac仮想環境構築/ --include='*.md' -l
```

## 規則

- frontmatterの直後に空行を1つ置き、その次の行を `# H1見出し` にする（H1は1ファイル1つ）。
- `date` はファイル名の日付（試験結果等）とは独立に「最終更新日」を表す。内容を更新したら必ず更新する。
- `.tmpl` 雛形ファイルにはプレースホルダ入りfrontmatter（`{{THEME}}` 等）を含め、生成時に置換する。
