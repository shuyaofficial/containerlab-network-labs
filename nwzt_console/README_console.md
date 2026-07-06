---
type: readme
theme: "nwzt_console"
status: done
date: 2026-07-05
tags: [zero-trust, dashboard, console, single-pane-of-glass]
title: "NW-ZT Console — 統合ゼロトラスト運用コンソール"
---

# NW-ZT Console — 統合ゼロトラスト運用コンソール

NW-ZT トラック（N1 NAC / N2 SDP-ZTNA / N3 NDR / N4 μセグ）は全て CLI・設定ファイル駆動で実装した。本コンソールは、それらを **1 画面（single pane of glass）** で見せる運用 UI。Zscaler / Palo Alto / Meraki / Mist の商用 GUI が「使いやすい」理由を OSS ラボに移植する試み。

> **デザイン基準**: ライト運用コンソール。既存 `規約/ビルド/doc.css` の紙系トークン（--cisco 青・ゾーン色）を継承。**外部依存ゼロ**の静的 HTML で、GitHub Pages が配信。

## 商用 GUI の「使いやすさ」を移植した 5 原則

1. **単一画面**: 4 観点を 1 コンソールに（ポイント製品を行き来しない）
2. **CLI レス**: 設定ファイルの複雑さを表に出さず、状態と意図を見せる
3. **状態が先**: トップは「ヘルス」（KPI ＋ ゾーンマップ）。詳細は各セクションへ
4. **ポリシー = 意図（誰 → 何）**: NAC は user→VLAN、ZTNA は identity→service
5. **プロアクティブな可視化**: NDR の east-west アラート、μセグの allow/deny を前面に

## 構成

```
nwzt_console/
├── src/index.html     シェル（サイドバー + ヘルス行 + セクション）
├── src/styles.css     デザインシステム（doc.css 紙系トークン継承）
├── src/app.js         描画（vanilla JS・ゾーンマップ SVG 自前描画・外部依存ゼロ）
├── src/data.js        実データ（実機検証ラボからの採取値）
├── capture/           稼働中ラボ → data 再生成（ライブ更新）
└── build/publish.sh   src/ → docs/console/ 公開コピー
```

## 実データの出所

`src/data.js` の値は、各ラボの実機検証で採取した本物：
- NAC: `show authentication sessions`（alice / VLAN 10 / Authorized）
- ZTNA: `ziti edge list` ＋ 実測（overlay HTTP 200 / direct HTTP 000）
- NDR: Suricata eve.json（sid:1000001 east-west SYN scan、flow 300+）
- μセグ: IOL ACL カウンタ（www=6 / deny22=1）・nft ドロップ（3）・Cilium L7（200 / 403）

## 使い方

```bash
# 公開（GitHub Pages 配信）
./build/publish.sh              # src/ → docs/console/

# ローカル閲覧
python3 -m http.server 8791 --directory src   # → http://localhost:8791

# 稼働中ラボから最新化（ライブ更新）
./capture/refresh.sh            # 各ラボ export → data.js 再生成
```

公開 URL: `https://shuyaofficial.github.io/containerlab-network-labs/console/`

## 次段階

Faucet SDN（テーマ 35）実装 ＋ Meraki/Mist 風 SDN 管理ダッシュボード（トポロジ + ポートグリッド + クライアント一覧）。ライブ操作 GUI 化。
