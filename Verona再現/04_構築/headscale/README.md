---
type: runbook
theme: "Verona再現"
status: done
date: 2026-07-21
tags: [verona, headscale, tailscale, sd-wan, sase]
title: "Headscale 手順 — 拠点間トンネル（発展）"
---

# Headscale 手順 — 拠点間トンネル（発展）

Verona p6「Verona Edge（SASEルータ）」・p27「SD-WANベースで、プロキシより高度＆広範囲」
（拠点間通信をVerona Edgeで制御する）を、[Headscale](https://headscale.net/)
（tailscaleのOSS control-plane実装）＋ tailscale クライアントで再現する
（△簡略化。WAN冗長化・IaaS接続・5G対応デュアルSIM等は対象外＝❌）。

## 位置づけ（コア/発展の区分）

本機能は「発展」（config・docを用意し単独サブコマンドで起動できる形にする。2拠点間の
データプレーン実疎通までは求めない）。**2026-07-21、メインセッションが実機デプロイし、
Headscaleコーディネータの起動＋user/preauthkey発行までを確認済み**（詳細:
[構築ログ_2026-07-21.md](../構築ログ_2026-07-21.md)）。tailscaleクライアントの参加による
データプレーン疎通（拠点間の実トンネル確立）は次段階（本ラボでは未実施）。

## 起動

```bash
./deploy.sh deploy-tunnel
# → headscale/headscale:latest イメージの ENTRYPOINT は既に `headscale` のため、
#   コンテナに渡すコマンドは `serve` 単体（`headscale serve` ではない。
#   `headscale serve` と書くと `headscale headscale serve` になり
#   "unknown command headscale" エラーになる＝2026-07-21実機デプロイで確認）。
#   deploy.sh（メインセッション修正済み）は `"$IMG_HEADSCALE" serve` で起動する。
```

## config.yaml の必須要件（v0.29.2で確認・2026-07-21実機デプロイで確定）

`headscale/headscale:latest`（実機確認時点でv0.29.2）は、当初の最小構成のままでは起動に
失敗し、以下2点の追加が必要だった。[config.yaml](config.yaml) は既にメインセッションが
反映済み（本READMEでは変更内容の説明のみ行う。config.yaml自体はこのREADMEでは変更しない）。

1. **`dns.nameservers.global` が必須**: `dns.override_local_dns` の既定値が `true` であり、
   その場合 `dns.nameservers.global` を明示しないと起動エラーになる。本ラボは
   `override_local_dns: false` としつつ `nameservers.global: [1.1.1.1]` も明示している
   （`false` にしても項目自体は要求されるため）。
2. **埋め込みDERPサーバの有効化が必須**: v0.29 は DERPMap が非空である必要があり、
   `urls: []` かつ外部DERPも設定しない場合は起動しない。外部Tailscale DERPに依存せず
   ラボ内で完結させるため、`derp.server.enabled: true`（region_id: 999、
   private_key_path: `/var/lib/headscale/derp_server_private.key`）で埋め込みDERP
   サーバを有効化した。

## ユーザー・事前認証キー作成（2026-07-21 実機確認済み）

以下のコマンド列を実機で実行し、user作成からpreauthkey発行までの成功を確認した
（`headscale users` / `--user` 構文がv0.29.2で有効であることも合わせて確認済み）。

```bash
# 拠点ごとにユーザー（旧namespace）を作成
sudo docker exec headscale headscale users create branch-a
sudo docker exec headscale headscale users create branch-b

# 各拠点用の事前認証キーを発行（24時間有効・再利用不可）
sudo docker exec headscale headscale preauthkeys create --user branch-a --expiration 24h
sudo docker exec headscale headscale preauthkeys create --user branch-b --expiration 24h
```

## 拠点ノードの接続（次段階・本ラボでは未実施）

各拠点を代表するコンテナ（例: branch-client、または新規のtailscaleクライアントコンテナ）で
以下を実行すれば、Headscale経由のオーバーレイに参加できる想定だが、**tailscaleクライアントの
実際の参加・データプレーン疎通（拠点間の実トンネル確立）は本ラボでは未実施**（正直に明記）。

```bash
tailscale up --login-server=http://headscale:8080 --authkey=<preauthkeyの値>
```

2拠点が同じHeadscaleインスタンスに参加すれば、tailscaleのメッシュVPNにより拠点間で
直接プライベートアクセスできるようになる想定（＝Verona Edgeの拠点間トンネルに相当）。

## 再現度・簡略化ポイント

| Verona機能 | 本ラボでの再現 |
|---|---|
| 拠点間の安全なプライベートアクセス | △ Headscaleコーディネータ起動＋user/preauthkey発行まで2026-07-21実機確認済み。tailscaleクライアント参加によるデータプレーン疎通（拠点間の実トンネル確立）は次段階 |
| WAN冗長化（メイン/サブ回線フェイルオーバー） | ❌ 対象外 |
| ローカルブレイクアウト | ❌ 対象外（SWG側で概念的にURLフィルタ通過後は直接到達するため部分的に類似するが未実装） |
| IaaS接続（AWS/Azure/GCP等） | ❌ 対象外 |
| デュアルSIM(5G)対応ルータ | ❌ 対象外（ハードウェア機能） |

## 参照

- [config.yaml](config.yaml)
- [構築ログ_2026-07-21.md](../構築ログ_2026-07-21.md)（Headscale調整の事象/原因/対処）
- [02_基本設計/網屋Verona_OSS対応表.md](../../02_基本設計/網屋Verona_OSS対応表.md)
- [05_試験/試験計画書.md](../../05_試験/試験計画書.md) T-V7
