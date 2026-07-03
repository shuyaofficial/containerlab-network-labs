# エンドポイント部材の説明（Claude提供・あなたは触らなくてOK）

「ネットワークはあなたが構築、サーバ・PCはClaudeが用意」という分担のための部品集です。
これらを組み込むと、ラボが「ただの疎通試験環境」ではなく**社内LANらしい環境**になります。

## 部材一覧

| ノード | 役割 | IP | 提供サービス |
|---|---|---|---|
| pc-sales | 営業部の社員PC | 10.10.10.100 | —（試験の起点） |
| pc-dev | 開発部の社員PC | 10.10.20.100 | —（試験の起点） |
| srv-file | ファイルサーバ | 10.20.30.10 | HTTP（共有ファイル配信。`shared_files/` の中身） |
| srv-portal | 社内ポータル | 10.20.30.20 | HTTP（社内システムのWeb画面。`portal_html/` の中身） |
| br-pc | 支社の社員PC | 10.2.40.100 | —（VPN試験の起点） |

## 組み込み方（あなたの作業は2ステップ）

1. [`endpoints.partial.clab.yml`](endpoints.partial.clab.yml) の5ノード定義を、あなたが作る `campus.clab.yml` の `topology.nodes` 配下へコピー
2. 結線表（`02_基本設計/ネットワーク物理構成図_テキスト版.md` の #18〜21, #24）どおりに `links` を追記

> ⚠️ `binds` のパスは `campus.clab.yml` を **テーマフォルダ直下**（`22_enterprise_campus_lan/`）に置く前提の相対パスです。別の場所に置く場合はパスを調整してください。

## 動作確認のしかた（ネットワーク完成後）

```bash
# 営業部PCに入る
sudo docker exec -it clab-<ラボ名>-pc-sales bash

# 社内ポータルが見えるか（L3＋HTTPの確認）
curl http://10.20.30.20/

# ファイルサーバの一覧と、ファイルのダウンロード
curl http://10.20.30.10/
curl -O http://10.20.30.10/全社共有_お知らせ.txt
```

ブラウザで見たい場合は、OrbStack側でポートフォワードするか、`curl` の出力で確認してください。

## トラブル時の切り分けヒント
- `curl` がダメで `ping` がOK → L3は生きている。サービス側（コンテナ）の問題か確認: `docker exec <node> netstat -tlnp`
- `ping` もダメ → ネットワーク側。GW（SVI/HSRP VIP）へのpingから順に切り分け（いつもの手順）
- エンドポイントのIP設定が消えた → コンテナ再起動時は `exec` が再実行されます。`docker exec <node> ip addr` で確認
- nginxはmultitoolイメージに内蔵・自動起動です（あなたが設定する必要はありません）
