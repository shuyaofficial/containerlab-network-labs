---
type: standard
theme: "規約"
status: done
date: 2026-07-03
tags: [standard, containerlab, deploy, iol]
title: "clab運用規約 — 配置・deploy.sh・実行パターン"
---

# clab運用規約

containerlabトポロジファイル（`.clab.yml`）と `deploy.sh` の標準構成、およびVM実行パターンを定義する。
基準実装は [26_dynamic_routing_deep_dive/04_構築/deploy.sh](../26_dynamic_routing_deep_dive/04_構築/deploy.sh)。

## 1. clab.yml配置

| 項目 | 規約 |
|---|---|
| 配置場所 | `04_構築/<topo>.clab.yml` に統一 |
| 禁止 | テーマルート直置き禁止（`NN_theme_name/*.clab.yml` は不可） |
| ファイル名 | `<topo>` はテーマの主題を表す短い英語スラッグ（例: `campus.clab.yml`） |
| mgmtネットワーク名 | `topology.mgmt.network` は `<lab-name>-mgmt` 形式 |

```yaml
name: dynamic-routing-lab

mgmt:
  network: dynamic-routing-mgmt
  ipv4-subnet: 172.26.26.0/24
```

## 2. deploy.sh標準

テーマ26を基準実装とする4サブコマンド構成 `{deploy|iouyap|inspect|destroy}` を必須とする。

### 2.1 必須要素

| 要素 | 規約 |
|---|---|
| シェバン | `#!/usr/bin/env bash` |
| 安全設定 | `set -euo pipefail` を先頭付近に必須 |
| 実行位置固定 | `cd "$(dirname "$0")"` でスクリプト自身の位置に移動してから処理 |
| ノード特定 | `NAME_PREFIX="clab-<lab-name>-"` を定義し、`docker ps` の絞り込みに使う |
| サブコマンド分岐 | `case "${1:-deploy}" in deploy|iouyap|inspect|destroy)` |
| usage表示 | 不明な引数は `usage: $0 {deploy|iouyap|inspect|destroy}` を`stderr`に出し `exit 1` |

### 2.2 サブコマンドの役割

| サブコマンド | 処理内容 |
|---|---|
| `deploy` | `sudo containerlab deploy -t "$TOPO"` → IOL使用時は続けて `start_iouyap` を呼ぶ |
| `iouyap` | IOLコンテナへ `iouyap` を後付けで起動し直す（deploy後の再適用・障害復旧用） |
| `inspect` | `sudo containerlab inspect -t "$TOPO"` でノード一覧・状態を表示 |
| `destroy` | `sudo containerlab destroy -t "$TOPO" --cleanup` で完全破棄 |

### 2.3 iouyap（IOL使用テーマのみ）

- `start_iouyap` 関数は `sleep 5` 等で起動待機後、`docker ps` を `NAME_PREFIX` でフィルタし、
  エンドポイント系ノード（`pc$` / `srv$` 等の命名サフィックス）を `grep -v -E` で除外してIOLノードのみへ実行する。
- 各コンテナに対し `sudo docker exec -d -w /iol "$container" /usr/bin/iouyap 513 2>/dev/null || true` を実行する。
- IOLを使わないテーマ（FRR/cRPD/vEOS等arm64ネイティブのみで構成）は `iouyap` サブコマンドを省略してよい。

### 2.4 サンプル（基準実装）

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
TOPO="campus.clab.yml"
NAME_PREFIX="clab-dynamic-routing-lab-"

start_iouyap() {
  sleep 5
  for container in $(sudo docker ps --format '{{.Names}}' \
      | grep "^${NAME_PREFIX}" | grep -v -E 'pc$|srv$'); do
    sudo docker exec -d -w /iol "$container" /usr/bin/iouyap 513 2>/dev/null || true
  done
}

case "${1:-deploy}" in
  deploy)
    sudo containerlab deploy -t "$TOPO"
    start_iouyap
    ;;
  iouyap)
    start_iouyap
    ;;
  inspect)
    sudo containerlab inspect -t "$TOPO"
    ;;
  destroy)
    sudo containerlab destroy -t "$TOPO" --cleanup
    ;;
  *)
    echo "usage: $0 {deploy|iouyap|inspect|destroy}" >&2
    exit 1
    ;;
esac
```

## 3. VM実行パターン（必須）

- Macホスト上で `containerlab` や `deploy.sh` を直接実行しない（sudoパスワード要求・Dockerソケット不一致で失敗する）。
- **必ず OrbStack の Linux VM に対して SSH 経由で実行する**（`containerlab-setup` スキル準拠）。

```bash
ssh clab@orb "cd /Users/shuya/Documents/claude/Mac仮想環境構築/<テーマ名>/04_構築 && ./deploy.sh deploy"
ssh clab@orb "cd /Users/shuya/Documents/claude/Mac仮想環境構築/<テーマ名>/04_構築 && ./deploy.sh inspect"
ssh clab@orb "cd /Users/shuya/Documents/claude/Mac仮想環境構築/<テーマ名>/04_構築 && ./deploy.sh destroy"
```

- Macファイルのパス（`/Users/shuya/...`）はOrbStack VM内に同一パスでマウントされているため、絶対パスをそのまま使える。
- コンソール接続は `sudo docker attach --sig-proxy=false clab-<lab-name>-<node>` を用いる（`--sig-proxy=false` 必須。付けないとCtrl-Cがコンテナごと終了させてしまう）。抜けるのは `Ctrl-P → Ctrl-Q`。

## 4. mgmt-ipv4 静的固定規約

既存慣行（テーマ26等）を正式ルールとして明文化する。

| 系統 | アドレス範囲 | 対象 |
|---|---|---|
| router系（本拠地・拠点内の階層ノード） | `.11`〜`.14` | 例: hq-core / hq-dist / hq-edge / hq-dmz |
| core系（拠点間・中継ノード） | `.21`〜`.22` | 例: br-core / br-edge |
| ISP・外部中継 | `.100` 台前半 | 例: isp |
| エンドポイント（PC・サーバ） | `.101` 以降 | 例: hq-pc / br-pc / dmz-srv |

- 全ノードに `mgmt-ipv4` を静的固定する（DHCP任せにしない。`docker attach` 前提のコンソール接続でIPが不定だと運用しづらいため）。
- mgmtサブネットは `172.26.26.0/24` のように各テーマで独立したレンジを使う（テーマ間の衝突を避ける）。

## 5. ノード命名・NAME_PREFIX規約

- ノード名は `<拠点略称>-<役割>` 形式（例: `hq-core`, `hq-dist`, `br-edge`）。役割名は `core` / `dist` / `edge` / `dmz` 等、階層構造がわかる語を使う。
- `deploy.sh` の `NAME_PREFIX` は `clab-<lab-name>-`（`lab-name` は `clab.yml` の `name:` と一致させる）。
- エンドポイント（PC/サーバ）は `pc` / `srv` 等の識別しやすいサフィックスを付け、`iouyap` 起動対象から除外できるようにする。

## 6. IOL注意事項

| 項目 | 内容 |
|---|---|
| 起動時間 | x86イメージのarm64エミュレーションのため、1ノードあたり起動に**約2分**かかる（回避不可・仕様として受け入れる） |
| entrypoint起動方式 | `exec /iol/iol.bin ...` のように **`exec` で直接起動**する。バックグラウンド化（末尾`&`）は禁止 |
| バックグラウンド禁止の理由 | `&` で起動するとIOLプロセスがPID1にならず、`docker attach` でコンソールに接続できなくなる（標準入出力がIOSに直結しない） |
| コンソール接続 | `sudo docker attach --sig-proxy=false <container>` を使う |
| ライセンス | `IOURC`（`gns3-iouvm` 用ライセンス）をentrypoint内に埋め込み、hostname `gns3-iouvm` を固定する |
| 起動順序 | IOL起動 → iouyap起動の順（逆順だと `sock lock` エラーが発生する） |

## 7. 禁止事項

| 禁止事項 | 理由 |
|---|---|
| `clab.yml` への設定コマンドの答え直書き | 学習テーマは`mentor_guidelines.md`準拠でユーザー自身が設定を考える機会を奪わない（[../mentor_guidelines.md](../mentor_guidelines.md)） |
| per-themeイメージの直ビルド | 廃止済みの方式。イメージは共通の `~/vrnetlab` ビルド済みイメージ群を使い回す（[../環境/環境説明.md](../環境/環境説明.md) §4-6参照） |
| `clab-*` ランタイムディレクトリのgit管理 | `containerlab deploy` が生成する `clab-<lab-name>/` はランタイム生成物（topology-data.json・証明書等）であり、ソースではない。`.gitignore` 対象とする |
