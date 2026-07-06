---
type: runbook
theme: "nwzt_console"
status: done
date: 2026-07-05
tags: [zero-trust, dashboard, console, capture, live-update]
title: "NW-ZT Console ライブ更新（capture/）— 稼働中ラボから data.js を再生成する仕組み"
---

# NW-ZT Console ライブ更新（capture/）

`nwzt_console/src/data.js` は静的な実データ（各ラボの実機検証で採取した本物の値）を持つ。
`capture/` はそれを**稼働中のラボから再採取して更新する**ための仕組み。書き込みは
`nwzt_console/capture/` 配下のみに限定し、既存ラボ本体・コンソール本体（`src/`）・
他テーマには一切書き込まない。

## 仕組み

```
capture/
├── export_nac.sh        N1 31_nac_dot1x の採取（stopped or JSON）
├── export_ztna.sh       N2 36_ztna_openziti の採取（stopped or JSON）
├── export_ndr.sh        N3 42_ndr_flow の採取（stopped or JSON）
├── export_microseg.sh   N4 microseg_nftables + microseg_cilium の採取（stopped or JSON）
├── refresh.sh           上記4本を呼び、結果から src/data.js を再生成
├── _regen.js            data.js 再生成の本体（Node、refresh.sh から呼ばれる）
├── out/                 各 export の採取結果 JSON（実行のたび上書き、監査・デバッグ用）
└── README_capture.md    このファイル
```

### 設計方針: 「稼働中なら採取、停止中なら既存値を保持（壊さない）」

- 各 `export_*.sh` は Mac 側から `ssh clab@orb` で OrbStack VM (arm64) に接続し、
  対象ラボのコンテナ（や k3d クラスタ）が**稼働中かどうかをまず判定**する。
  - 稼働中 → 実機から値を採取し、`data.js` の該当セクション（nac/ztna/ndr/microseg）と
    同じキー構造の JSON を **stdout** に出す（先頭に `"status":"running"`）。
  - 停止中 / 採取失敗 → `{"status":"stopped"}` を stdout に出して終了する（exit 0）。
    以降の処理でエラーにはしない。
- `refresh.sh` は4本の export を順に呼び、結果を `capture/out/<name>.json` に保存した上で
  `_regen.js`（Node）に渡す。`_regen.js` は既存の `src/data.js` を読み込み、
  **`status:"stopped"` のセクションは既存値のまま**、採取できたセクションだけを
  差し替えて書き戻す。`meta.capturedAt` は実行日に更新する。
- **安全弁**: `_regen.js` は再生成後に `meta/nac/ztna/ndr/microseg` の5キーが
  すべて存在し空でないことを確認してから書き込む。1つでも欠けたら
  例外を投げて **`data.js` を書き換えずに中断**する（壊れた状態で上書きしない）。
- 出力フォーマットは `window.NWZT_DATA = {...};` を厳守し、`file://` でそのまま開ける
  静的 HTML の前提を壊さない（`build/publish.sh` や既存の `src/index.html` は無改変）。

## 使い方

```bash
# 稼働中ラボから最新化（ライブ更新）。個別 export の失敗は他ラボに影響しない。
cd nwzt_console
./capture/refresh.sh

# 個別に採取結果だけ見たい場合
./capture/export_ndr.sh | jq .

# 再生成後の健全性チェック（壊れていないか・5セクション揃っているか）
node -e "global.window={};require('./src/data.js');console.log(Object.keys(window.NWZT_DATA))"
```

## 各ラボの採取コマンド対応表

| セクション | ラボ | 稼働判定 | 採取コマンド | data.js キー |
|---|---|---|---|---|
| nac | 31_nac_dot1x | `docker ps` に `clab-nac-*` が存在 | expect で `clab-nac-sw1` に attach → `show authentication sessions` / `show vlan brief` | `nac.summary` / `nac.sessions` / `nac.policy` |
| ztna | 36_ztna_openziti | `docker ps` に `ziti`/`darkweb`/`apptun`/`clienttun` が全て存在 | `ziti edge list services/identities/service-policies`（件数）＋ `clienttun` から `curl localhost:8080`（overlay）/ `curl darkweb:80`（direct）を実測 | `ztna.summary` / `ztna.proof` |
| ndr | 42_ndr_flow | `docker ps` に `attacker`/`victim`/`suricata` が全て存在 | `suricata/log/eve.json` を採取し `event_type=="alert"` / `event_type=="flow" and ip_v==4 and proto=="TCP"` を jq で集計（IPv6 ICMP/MLD 等のノイズは east-west 対象外として除外） | `ndr.summary` / `ndr.alerts` / `ndr.topTalkers` |
| microseg (nftables) | microseg_nftables | `docker ps` に `clab-microseg-*` が存在 | expect で `clab-microseg-sw1` に attach → `show ip access-lists`（ACL カウンタ）＋ `clab-microseg-pc10b` で `nft list ruleset`（drop カウンタ） | `microseg.approaches[id=nftables]` |
| microseg (cilium) | microseg_cilium | VM 上で `k3d cluster list` に `microseg` クラスタが存在 | `kubectl -n microseg get networkpolicy,ciliumnetworkpolicy` ＋ `microseg_cilium/04_構築/test.sh` を実行し frontend/other→backend の HTTP コード（L4/L7 の allow/deny）を実測 | `microseg.approaches[id=cilium]` |

nftables 版・Cilium 版はそれぞれ独立に判定する。`_regen.js` の `mergeMicroseg()` は
`microseg.approaches` 配列を **id（"nftables" / "cilium"）単位でマージ**するため、
片方だけ稼働中でももう片方の approach が消えることはない
（例: nftables だけ稼働中 → `approaches` は [採取した nftables, 既存の cilium] の
2件のまま維持される）。両方停止中の場合のみ `microseg` セクション全体を
既存値のまま保持する。

## 既知の制限

- `export_nac.sh` / `export_microseg.sh`（nftables 側）は IOL の CLI 出力を
  正規表現でパースしている。IOS の表示崩れ・改行位置によっては数値が拾えず
  デフォルト値（試験結果 doc の実測値）にフォールバックすることがある。
- `export_ztna.sh` の services/identities/policies 件数は `ziti edge list` の
  出力行数から数える簡易実装。OpenZiti CLI の出力フォーマット変更に弱い。
- `export_microseg.sh` の Cilium 側は `test.sh` の標準出力を**固定4行の順序**で
  読む実装（同じパス `/` が L4/L7 双方で出力され文字列一致では区別できないため）。
  `test.sh` の出力順序を変えると壊れる。
- どの export も SSH 接続失敗・コマンドタイムアウト時は `set -euo pipefail` の
  範囲外で `|| true` により停止扱いへフォールバックする設計。ただし SSH 自体が
  長時間ハングする場合の明示的なタイムアウトは未設定（次段階の改善候補）。
- 全 export・refresh は **capture/ 配下にのみ書き込む**。`ssh clab@orb` 経由で
  各ラボの deploy/destroy を呼ぶことはなく、あくまで「稼働中なら状態を読むだけ」。
