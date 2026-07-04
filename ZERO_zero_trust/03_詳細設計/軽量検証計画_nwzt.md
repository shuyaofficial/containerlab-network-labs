---
type: feasibility
theme: "ZERO_zero_trust"
status: draft
date: 2026-07-04
tags: [zero-trust, feasibility, arm64, nac, ndr, verification]
title: "テーマZERO｜NW-ZT arm64 軽量検証計画"
---

# テーマZERO｜NW-ZT arm64 軽量検証計画

NW-ZT トラック（N1 NAC / N2 SDP-ZTNA / N3 NDR / N4 μセグ）で使う **コンテナ OSS** が arm64 で動く見込みを軽量に確かめる計画。実測は本計画の対象外で、メインセッションが別途実施する。

> **本計画は NW-ZT トラック（N1-N4）専用。** L7 トラック（Phase 0-6）の OSS 検証は [軽量検証計画](軽量検証計画.md) に分離している。

## 検証の目的とスコープ

- 目的: N1-N4 で使う **コンテナ OSS 各イメージの arm64 manifest 有無**と、起動可否の見込みを確認する。
- スコープ内: manifest 確認（静的判定）＋ 不確実なものの pull/起動の軽量確認。
- スコープ外（**arm64 検証対象外**）:
  - Cisco IOL L2 の dot1x/MAB/CoA/動的 VLAN の機能可否 — IOL は x86 エミュレーションで動作し、機能面はコンテナの arm64 manifest 確認では判定できない。**N1 実装時の実機検証**として明確に切り分ける（詳細は後述の「IOL機能検証の切り分け」を参照）。
  - tinyproxy 等、本トラックで採用していない OSS。
  - Phase 1-6 の本格デプロイ・結合試験。
- 前提: VM `clab`（Ubuntu 24.04 / arm64）。

## 判定基準

[軽量検証計画](軽量検証計画.md) の表記を踏襲する。

| 判定 | 条件 | 次のアクション |
|---|---|---|
| **High** | 公式 arm64 manifest が有る（`docker manifest inspect` に `arm64` が含まれる） | 採用確定。実検証は起動確認のみ |
| **Med** | manifest は有るが起動/機能に不確実性、または未確認 | pull して起動確認を実検証 |
| **Low** | arm64 manifest が無い or 明示非対応 | 代替差し替えルールを適用 |

## 検証対象イメージ一覧

| # | 観点(N) | イメージ | 役割 | arm64見込み | 判定見込み | 検証方法 | 代替案 |
|---|---|---|---|---|---|---|---|
| 1 | N1 | `freeradius/freeradius-server` | RADIUS 認証サーバ（Authenticator の裏側） | 有・取得済 | High | 起動確認のみ | — |
| 2 | N1 | Cisco IOL L2 | 認証者（802.1X/MAB/CoA/動的VLAN） | x86 エミュ・機能は別途判定 | 対象外 | **N1 実装時に実機検証**（下記参照） | — |
| 3 | N2 | `openziti/ziti-controller` | SDP コントローラ | 有・確定済 | High | 起動確認のみ | — |
| 4 | N2 | `openziti/ziti-router` | SDP ルータ（app-connector） | 有・確定済 | High | 起動確認のみ | — |
| 5 | N2 | `netbirdio/netbird` | メッシュ VPN 型 ZTNA（発展） | 未確認 | Med | manifest 確認 + pull 起動確認 | Headscale |
| 6 | N2 | `headscale/headscale` | メッシュ VPN 型 ZTNA（発展） | 未確認 | Med | manifest 確認 + pull 起動確認 | Netbird |
| 7 | N3 | `zeek/zeek` | DPI 振る舞い検知 | 未確認 | Med | manifest 確認 + pull 起動確認 | Suricata 単独 |
| 8 | N3 | `jasonish/suricata` | DPI 振る舞い検知・IDS | 実測済（L7トラックで確定） | High | **既存結果を流用**（manifest listにamd64/arm64の2platform、そのまま利用可） | — |
| 9 | N3 | `netsampler/goflow2` | NetFlow/IPFIX 収集 | 未確認 | Med | manifest 確認 + pull 起動確認 | nfdump 系 |
| 10 | N3 | `ntop/ntopng` | フロー可視化 | 未確認 | Med | manifest 確認 + pull 起動確認 | ElastiFlow / Grafana |
| 11 | N3 | ElastiFlow | フロー可視化（発展） | 未確認・重量懸念 | Med/Low寄り | manifest 確認（重量なら早期に Low 判定） | ntopng 一本 |
| 12 | N3 | `faucet/faucet` + OVS | ミラー環境補助（SDN コントローラ） | 未確認 | Med | manifest 確認 + pull 起動確認 | — |
| 13 | N1（代替検討） | PacketFence | NAC（統合型、当初検討） | x86 中心 | Low → **確定** | 判定確定済（代替へ移行済） | **FreeRADIUS 自作に確定** |

> #8（Suricata）は L7 トラックの軽量検証結果（[軽量検証結果_2026-07-04.md](軽量検証結果_2026-07-04.md)）で既に実測済みのため、本計画では再検証せず結果を流用する。
> #13（PacketFence）は arm64 x86 中心のため既に Low 判定が確定しており、N1 は FreeRADIUS 自作構成に決定済み。検証対象としては記録のみで、追加の manifest 確認は不要。

**イメージ総数: 13件**（内訳: 検証要 9件 = #1,3,4,5,6,7,9,10,12 / 既存結果流用 1件 = #8 / arm64対象外・実機検証へ切り分け 1件 = #2 / 判定確定済（代替へ移行済） 1件 = #13 / 重量懸念で早期Low寄り 1件 = #11。#11は「検証要」にも重複カウントしうるため、検証実施の実数としては9〜10件目安）

## IOL機能検証の切り分け

Cisco IOL L2 の **dot1x / MAB / CoA / 動的VLAN** の対応可否は、本計画（コンテナ OSS の arm64 manifest 確認）では判定できない。IOL は x86 イメージをエミュレーション実行するため、「動くかどうか」はコンテナの arm64 対応可否とは別軸の問題であり、機能検証にはスイッチ設定・RADIUS 連携・実端末（またはサプリカント）を用いた実機確認が必要になる。

- **今回（本計画）の範囲**: IOL が VM 上でエミュレーション起動できること自体は前提（既存 clab VM 環境で起動実績あり）。dot1x 等の機能可否は判定しない。
- **先送りする検証**: N1 実装着手時に、実機（IOL L2 + FreeRADIUS + client）を組んだ上で以下を確認する。
  - `show dot1x all` — 802.1X セッション状態
  - `show authentication sessions` — MAB フォールバック含む認証セッション一覧
  - RADIUS Access-Accept の VLAN 属性（`Tunnel-Private-Group-ID` 等）反映によるポートの動的 VLAN 切り替え
  - CoA（Change of Authorization）によるセッション強制再認証・切断
- **切り分けの理由**: arm64 軽量検証はコンテナイメージの可搬性判定が目的であり、IOL のようなネットワーク OS エミュレーションの機能検証は性質が異なる（設定投入・プロトコル動作の確認が主体で、pull/起動確認では代替できない）。

## 代替差し替えルール

| 対象 | 事象 | 差し替え | 根拠 |
|---|---|---|---|
| N1 NAC | PacketFence が arm64 不可 / x86 中心 | **FreeRADIUS 自作**（確定済） | 統合型 NAC より軽量な自作構成が arm64 環境に適する |
| N3 可視化 | ntopng が arm64 不可 | **ElastiFlow または Grafana** で代替 | フロー可視化の目的（既存 SIEM 連携）を維持 |
| N3 収集 | goflow2 が arm64 不可 | **nfdump 系**へ差し替え | NetFlow/IPFIX 収集の役割を維持 |
| N3 DPI | Zeek が arm64 不可 | **Suricata 単独**で代替 | Suricata は実測済み High。DPI 振る舞い検知の役割は維持 |
| N3 可視化（重量） | ElastiFlow が重すぎる | **ntopng 一本**に集約 | 軽量・単一ツールへ寄せる |

差し替えの優先原則（[軽量検証計画](軽量検証計画.md) と同一の考え方）:

1. arm64 で動くことを最優先。動かないものは代替する。
2. 観点の目的（NAC の入口制御／NDR の可視化＋検知）を維持する。
3. 軽量・集約を選ぶ（重量級は単一ツールへ寄せる）。

## 検証手順

1. メインセッションが `ssh clab@orb "docker manifest inspect <image>"` を対象イメージ（#1, 3-7, 9, 10, 12）に対して実行し、`arm64` の有無を確認する。
2. 結果があいまい（Med判定）なものは pull して起動するところまで軽量に実証する。
3. #8（Suricata）は既存の軽量検証結果（[軽量検証結果_2026-07-04.md](軽量検証結果_2026-07-04.md)）をそのまま流用し、再検証しない。
4. #2（IOL 機能）と #13（PacketFence）は本検証の対象外・確定済みとして結果ファイルに明記のみ行う。
5. 結果を `軽量検証結果_nwzt_2026-07-04.md`（type: feasibility）に記録する。
6. [NW-ZT_トラックロードマップ](../02_基本設計/NW-ZT_トラックロードマップ.md) の arm64 列を確定値に更新する。

## 参照

- [NW-ZT_トラックロードマップ](../02_基本設計/NW-ZT_トラックロードマップ.md)
- [NW-ZT_論理構成設計](../02_基本設計/NW-ZT_論理構成設計.md)
- [軽量検証計画](軽量検証計画.md)（L7トラック版）
