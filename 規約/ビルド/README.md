---
type: standard
theme: "規約"
status: done
date: 2026-07-04
tags: [standard, build, html, tooling]
title: "ビルドシステム — MD→HTML 静的生成"
---

# ビルドシステム

`Mac仮想環境構築/` 配下の Markdown 設計書を、**印刷にも耐える閲覧HTML**へ変換する静的ビルダ。
Markdown がソース・オブ・トゥルース。HTML は生成ビューであり手編集禁止（[ドキュメント標準.md](../ドキュメント標準.md) §5）。

## 使い方

```bash
cd 規約/ビルド
npm install                  # 初回のみ

node build.mjs              # 全 .md → docs/ をビルド + ポータル index.html
node build.mjs --file <p>   # 単一ファイル（ROOT配下のみ）
node build.mjs --watch      # chokidar でファイル監視・自動再ビルド
node build.mjs --check      # 検証のみ（違反あれば終了コード非0）
```

`npm run build` / `npm run watch` / `npm run check` でも同じ。

## 出力

- `docs/` にソースと同じディレクトリ構造で `.html` を生成する（GitHub Pages 公開単位）。
- `docs/assets/` に共通アセットを配置する:
  - `doc.css` — 紙系デザイントークンの閲覧スタイル
  - `mermaid.min.js` — 図描画（node_modules から同梱コピー。**外部CDN不使用**）
  - `highlight.css` — highlight.js の淡色テーマ（github light）
- `docs/index.html` — テーマカード一覧のポータル。

## 対象と除外

- 対象: ROOT 配下の全 `*.md`。
- 除外ディレクトリ: `node_modules/` `docs/` `.git/` `log/` `rfc/` `切り分け/` `インターロップ/` `規約/雛形/`、および `clab-*` プレフィックスのディレクトリ。
- ルートは `path.resolve(スクリプト位置, '../..')` で解決する。**絶対パスはハードコードしない**（GitHub 移植性）。

## frontmatter とレガシー互換

- frontmatter は [gray-matter](https://www.npmjs.com/package/gray-matter) で分離し、`template.html` の
  `{{title}} {{breadcrumb}} {{tags}} {{status}} {{date}} {{toc}} {{content}} {{notice}} {{assets}}` を置換する。
- **strict パス**（`規約/` と `ZERO_zero_trust/`）は frontmatter 必須。
- **レガシー文書**（テーマ 02〜27 等）は frontmatter が無くてもビルドする。`title` は先頭 H1 を採用する（無ければファイル名）。
- 本文先頭の H1 はマストヘッドの `.doc-title` と重複するため、生成時に1つだけ除去する。

## Markdown 処理

- [markdown-it](https://github.com/markdown-it/markdown-it)（`html:true, linkify:true`）+ `markdown-it-anchor`（H2/H3 に id とアンカー）+ `markdown-it-attrs`。
- コードは highlight.js（`bash` / `yaml` / `text` / `python` ほか。`sh`→bash、`yml`→yaml も正規化）。
- ` ```mermaid ` フェンス → `<pre class="mermaid">`。テンプレ側の同梱 `mermaid.min.js` が `startOnLoad` で描画する。
- 内部リンク: 相対 `.md` → `.html` に書き換える（アンカー・クエリ保持）。外部URL・`#`アンカーはそのまま。
- 表は `.table-wrap` で囲み、横スクロールと印刷崩れを防ぐ。

## デザイン

- 紙系トークン（`--paper` `--canvas` `--ink` `--cisco`、ゾーン色、`--radius:16px`）を構成図HTMLから継承。
- 本文最大幅 ~76ch ＋ 右サイドに `position:sticky` の TOC（H2/H3から生成、スクロール連動でアクティブ表示）。
- 日本語タイポ（Hiragino Sans / Noto Sans JP、`line-height:1.65`、`tabular-nums`）。
- `--cisco` を見出し・リンク・アクティブTOCに意味的に使用。
- 表はヘッダ薄グレー・行ホバー・`@media print` で罫線明瞭＋`break-inside:avoid`＋TOC非表示。
- モーションは最小限（`cubic-bezier(.22,1,.36,1)`、`prefers-reduced-motion` 対応）。

## --check 検証

strict 対象（`規約/` `ZERO_zero_trust/`）は**エラー**、レガシーは**警告**。出力形式は `file:line 種別 詳細`。

| 種別 | 内容 | 適用範囲 |
|---|---|---|
| `NFD-FILENAME` | ファイル名が NFC 正規化されていない | 全域（エラー） |
| `FM-MISSING` | frontmatter が無い | strict |
| `FM-FIELD` | 必須フィールド欠落（type/theme/status/date/tags/title） | strict |
| `H1-COUNT` | H1 が 0 個 or 複数 | strict |
| `LINK-BROKEN` | 相対 `.md` リンクの参照先が存在しない | strict |
| `ABS-PATH` | 絶対パス（`/Users/…`）リンクの埋め込み | strict |

## ポータル index.html

- テーマ（トップレベルディレクトリ）ごとにカード表示。`ZERO_` を先頭、以降は番号順。
- 各カードにテーマ名・文書数・文書リンク一覧。
- `ロードマップ/進捗管理.md` が読めれば進捗状態の絵文字を各カードに表示する（読めなくても壊れない）。

## 既知の制限

- **レガシー NFD ファイル名**: テーマ 02〜27・`ロードマップ/`・`環境/` に NFC 未正規化のファイル名が残っており、`--check` が `NFD-FILENAME` エラーを出す（仕様上 NFD は全域エラー）。これらは本標準の遡及対象外（[規約/README.md](../README.md) 適用範囲）のため未修正。strict 対象（`規約/` `ZERO_zero_trust/`）には NFD 違反は無い。コミットゲートとして使う場合、当面はレガシー由来のエラーを許容するか、対象を strict に絞る運用が必要。
- `--check` はコードフェンス内の見出し・リンクを除外するが、インライン `<code>` 内の疑似リンクまでは判定しない（実害は軽微）。
- `mermaid.min.js` は約 3.4MB。図を含む文書でのみロードされ、含まない文書でも `<script>` タグ自体は残る（描画は `startOnLoad` が図の有無を判定）。
