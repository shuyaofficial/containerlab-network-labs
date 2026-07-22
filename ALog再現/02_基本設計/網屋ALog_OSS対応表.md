---
type: basic-design
theme: "ALog再現"
status: draft
date: 2026-07-21
tags: [siem, alog, oss-mapping, gap-analysis]
title: "網屋ALog機能 — 本ラボOSS対応表"
---

# 網屋ALog機能 — 本ラボOSS対応表

網屋ALogサービス概要資料（Document Ver.2.1）の機能紹介（p14〜p21）を基準に、本ラボのOSS実装との対応・再現度を整理する。凡例: **✅ 概ね再現**／**△ 簡略化して再現（考え方のみ）**／**❌ 対象外（非目標）**。

## 1. 機能対応表

| ALogの商用機能（資料の頁） | 本ラボのOSS対応 | 再現度 | 簡略化ポイント |
|---|---|---|---|
| 対応ログソース（ファイルサーバ/DB/APサーバ/ADサーバ/PC/Webプロキシ/NW機器/クラウド、p6） | syslog(Vector)でAD/Linuxサーバ/NW機器の3カテゴリを模擬、eve.json(Suricata)で検知ログを追加 | △ | 実機のADサーバ・NW機器は用意せず、代表的なログパターンをシミュレーション生成する。ファイルサーバ/DB/クラウドサービスのログソースは対象外 |
| 自動ログ解析・翻訳変換（特許第6501159号、p15） | Vector VRLによる正規表現ベースの構造化変換（4パターン: SSH認証失敗/sudo実行/AD風ログオン失敗/NW機器インターフェース変化） | △ | 特許技術そのものは再現できない。対応パターン数もALogの全対応システム（Windows/NetApp/EMC/Linux/Oracle等、p43）よりごく少数。データ量削減（1GB→1MB→25KB、p15）の圧縮率は測定していない |
| AI検知・分析（件数変化・値変化・新規出現の3観点、p16） | Grafana AlertingのLogQLルール（count_over_time / unless集合演算 / 固定閾値） | △ | AIの教師なし学習・ユーザー行動スコアリングは実装しない。固定閾値・固定時間窓のルールベース近似であり、学習・適応能力はない |
| リスクスコアリング（ユーザー単位のスコア推移・ランキング、p16） | 未実装 | ❌ | 個々のユーザーへのスコア付与・ランキング表示は本ラボのスコープ外 |
| 検索・分析画面（時系列グラフ・ドリルダウン、p17） | GrafanaのExplore機能 + ダッシュボードのtimeseries/tableパネル | ✅ | Grafana標準機能でLogQLの時系列可視化・絞り込みが可能。ファセット集計（Host/User/SourceType別カウント）はダッシュボードのtable パネルで簡易再現 |
| 監視テンプレート（Azure AD/Microsoft365等、p18） | 未実装（固定の3ルールのみ） | ❌ | テンプレートカタログ・カテゴリ別選択UIは対象外。3観点検知ルールを手動でYAML記述する |
| アラート通知（メール/Webhook、p18） | Grafana AlertingのWebhook contact pointのみ | △ | メール通知は対象外。Webhook受信確認も簡易socatリスナーであり、実運用のインシデント管理システム連携は再現しない |
| 可視化パネル・ダッシュボード（p19） | Grafana provisioningダッシュボード（未確認アラート数相当/Top送信元IP/event種別時系列/認証失敗推移） | ✅ | パネル構成・指標はALogのキャプチャ例を参考に近似。地理的可視化（海外トラフィックの地図表示）は対象外 |
| マルチノード構成（スケールアウト・高可用性、p20） | 未実装（単一プロセス構成） | ❌ | Loki/Vector/Grafanaいずれも単一コンテナで動作させる。分散処理・レプリカは対象外 |
| アクセスログのオフロード機能（S3への自動移行、p21） | LokiのchunksをMinIO(S3互換)へ配置し、compactorのretention設定で自動削除を再現 | ✅ | 保管期限は学習用に大幅短縮（2h）。実運用のAWS S3ではなくセルフホストMinIOを使用 |
| ALog MDRサービス（運用代行、p22〜p27） | 対象外 | ❌ | 人的な監視・分析・報告代行サービスであり、OSS技術で再現する性質のものではない |
| ライセンス体系・コンパクト術（データ量1/200圧縮課金、p12） | 対象外 | ❌ | 課金モデルの再現は本ラボの目的外 |

## 2. 3観点検知の対応関係（p16の詳細）

| ALogの観点 | 定義（資料の例） | 本ラボのLogQL近似 | 使用ルール |
|---|---|---|---|
| 件数の変化 | ログイン失敗の急増など | `sum(count_over_time({job="alog",event="auth_fail"} \| json [5m])) > 10` | `alog-count-change-auth-fail` |
| 値の変化 | 通信量の異常増大など | `sum(count_over_time({job="alog"} \| json [5m])) > 50`（全イベント件数の急増で近似） | `alog-value-change-event-volume` |
| 新規出現 | 過去30日間で初登場のアカウント/IPなど | `sum by (src_ip)(...[5m]) unless sum by (src_ip)(...[1h] offset 5m)` | `alog-new-appearance-src-ip` |

いずれも[grafana/provisioning/alerting/rules.yaml](../04_構築/grafana/provisioning/alerting/rules.yaml)で定義。**ALogの実装（教師なし学習による行動ベースライン）とは異なり、固定閾値・固定時間窓によるルールベースの近似である点に注意する**（過大評価しない）。

## 3. 翻訳変換の対応関係（p15の思想）

| ALogの例（p15） | 本ラボの実装（Vector VRL） |
|---|---|
| READ → 「ファイルを開いた」 | `Failed password for X from Y` → `event=auth_fail, user=X, src_ip=Y, message_ja="Xが Yからの SSHログインに失敗した"` |
| WRITE → 「保存した」 | `alice : ... USER=root ; COMMAND=Z` → `event=priv_exec, user=alice, command=Z, message_ja="aliceが管理者権限(sudo)で「Z」を実行した"` |
| DELETE → （同様の人間可読化） | `EventID=4625 Account Name: bob Source Network Address: W` → `event=ad_logon_fail, user=bob, src_ip=W, message_ja="bobのドメインログオンが失敗した（送信元 W）"` |

詳細実装は[04_構築/vector/vector.yaml](../04_構築/vector/vector.yaml)を参照。

## 参照

- [README_Lab_Challenge.md](../README_Lab_Challenge.md)
- [01_要件定義/要件定義書.md](../01_要件定義/要件定義書.md)
- [基本設計書.md](基本設計書.md)
