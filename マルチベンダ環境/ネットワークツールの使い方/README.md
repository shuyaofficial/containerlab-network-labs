---
type: runbook
theme: "マルチベンダ環境"
status: done
date: 2026-07-17
tags: [containerlab, fastapi, multi-vendor, runbook, network-tools]
title: "マルチベンダ環境ラボ ネットワークツールの使い方"
---

# マルチベンダ環境ラボ ネットワークツールの使い方

自作のFastAPI製ネットワークツール7本（`01_macro`〜`07_triage`、ポート8601〜8607、
出典: [ネットワークツール](/Users/shuya/Documents/claude/ネットワークツール/)）を、
このマルチベンダcontainerlabラボ（mvlab: RouterOS / Cisco IOL / Nokia SR Linux / FRR / OpenWrt の6ベンダー構成、
13ノード）でどう使うかをまとめたHTMLガイド一式。

全ツール共通: 各フォルダで`bash start.sh`（初回はvenv構築で要ネット接続）、127.0.0.1固定、
`NT_NO_OPEN=1`でブラウザ自動オープンを抑止。

## 各ページへの誘導

- [index.html](index.html) — ハブ。mvlabノード一覧・ツールカード7枚・セットアップ状況・推奨ワークフロー図
- [01_macro.html](01_macro.html) — マクロ作成（:8601、補助）— Cisco IOS投入コマンド生成 → IOLのconsoleへ貼付
- [02_ping.html](02_ping.html) — Ping実行・確認（:8602、主力）— 13ノード死活監視・障害試験・CSV。要ルート追加
- [03_log.html](03_log.html) — ログ取得・差分（:8603、限定的）— device_type固定のため本ラボでは参考記載のみ
- [04_fwpolicy.html](04_fwpolicy.html) — FWポリシー管理（:8604、補助）— ゾーンポリシー設計のモデリング
- [05_config.html](05_config.html) — コンフィグ管理（:8605、主力）— 全ベンダー貼付インポートで版管理・diff
- [06_terminal.html](06_terminal.html) — ターミナル（:8606、主力）— mv-*エイリアスで直接SSH。スイートの主力
- [07_triage.html](07_triage.html) — 障害トリアージAI（:8607、補助）— 症状+show出力を貼ってAIが原因仮説を提示

## セットアップ

Macから172.20.50.0/24（mvlab mgmt）へICMP/HTTPで直接到達させたい場合（`02_ping`や直接`curl`）のみ、
1回だけ`setup_mac.sh`を実行する（sudo要求・Mac再起動でルートは消える）。

```bash
./setup_mac.sh
```

`06_terminal`（ProxyJump経由SSH）・`05_config`（貼付インポート）・`07_triage`（貼付のみ）・
`01_macro`／`04_fwpolicy`（機器接続なし）は、このスクリプトなしでそのまま使える。

詳細（実データ・使い方ステップ・制約）は[index.html](index.html)から各ツールページを参照。
