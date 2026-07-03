---
type: runbook
theme: "環境"
status: review
date: 2026-07-03
tags: [runbook, orbstack, containerlab, vrnetlab, rebuild]
title: "VM再構築runbook — OrbStack clab環境"
---

# VM再構築runbook — OrbStack clab環境

> OrbStack VM「clab」が消失・破損した場合に、土台（VM・containerlab・vrnetlab・イメージビルド環境）をゼロから再構築するための実行手順。
> 出典: 2026-06-15の実際の復旧記録（[../22_enterprise_campus_lan/環境_土台再構築_2026-06-15.md](../22_enterprise_campus_lan/環境_土台再構築_2026-06-15.md)）を再実行可能な形に再構成したもの。
> 現状の環境全体像・アクセス方法は [環境説明.md](環境説明.md) を参照。稼働中イメージの一覧は `イメージマニフェスト.md`（別途生成）を参照。

---

## 前提

- Mac: Apple Silicon (arm64)、OrbStack導入済み
- 本runbookはインフラ手順書であり、学習テーマ（ラボ機器のCLI設定）とは異なる。コマンドをそのまま実行してよい。
- 各手順の所要時間目安は2026-06-15〜17の実測ベース。

---

## 手順1: OrbStack VM作成

**目安時間: 5〜10分**

```bash
# Mac側で実行
orb create ubuntu:24.04 clab
```

- ディストリビューション: Ubuntu 24.04 (noble) / arm64
- VM名: `clab`（既存手順・環境説明.mdの全記述がこの名前を前提にしているため変更しない）

### 検証コマンド

```bash
ssh clab@orb "cat /etc/os-release | grep VERSION_ID"
# 期待値: VERSION_ID="24.04"
ssh clab@orb "uname -m"
# 期待値: aarch64
```

---

## 手順2: containerlab・docker・関連パッケージ導入

**目安時間: 10〜15分**

```bash
ssh clab@orb

# containerlab公式インストーラ
sudo bash -c "$(curl -sL https://get.containerlab.dev)"

# Docker（OrbStackのUbuntuイメージには同梱されていない場合あり）
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# ビルド・エミュレーションに必要なパッケージ一式
sudo apt-get update
sudo apt-get install -y make qemu-system-x86 expect git qemu-utils unzip gdown sshpass python3 python3-pip
```

### x86エミュレーション（Rosetta + qemu binfmt）の確認

OrbStackはRosetta経由のx86エミュレーションをVM作成時に自動登録する。手動設定は基本的に不要だが、登録有無は以下で確認する。

```bash
# binfmt_misc にx86_64ハンドラが登録されているか確認
cat /proc/sys/fs/binfmt_misc/qemu-x86_64 2>/dev/null | head -3
# もしくは
update-binfmts --display | grep qemu-x86_64
```

### 検証コマンド

```bash
containerlab version
# 期待値: 0.76.1 以上
docker --version
# 期待値: 29.x系
docker run --rm --platform linux/amd64 hello-world
# x86イメージが起動できればエミュレーション経路OK
```

---

## 手順3: vrnetlab取得＋ARM64パッチ適用

**目安時間: 15〜20分（パッチ内容の突合含む）**

```bash
ssh clab@orb
cd ~
git clone https://github.com/hellt/vrnetlab.git
cd vrnetlab
git checkout v0.21.0
```

### 適用するARM64パッチ（4箇所）

必ず元ファイルを `.bak` として退避してから編集する（差分の切り戻しを可能にするため）。

| # | 対象ファイル | 変更内容 | 理由 |
|---|---|---|---|
| 1 | `common/vrnetlab.py` | `-cpu host` 起動オプションを、失敗時に `-cpu qemu64` へ自動フォールバックするよう修正 | arm64には `/dev/kvm` が無く、`-cpu host` はホストCPUパススルー前提のため失敗する |
| 2 | `cisco/iol/docker/Dockerfile` | `dpkg --add-architecture i386` を追加し、`libc6:i386 libgcc-s1:i386` をインストール対象に追加 | 旧世代IOLバイナリ(i386)の実行に必要 |
| 3 | `cisco/iol/docker/Dockerfile` | `iouyap` を直接 `.deb` からインストールする形に変更 | 標準ビルド手順ではiouyapの依存解決に失敗するケースがあったための回避 |
| 4 | 各種Dockerfile | `python3` パッケージの追加、`--platform=linux/amd64` の明示 | arm64ホスト上でx86ベースイメージを確実にビルドするため |

```bash
# バックアップ退避の例（編集前に必ず実施）
cp common/vrnetlab.py common/vrnetlab.py.bak
cp cisco/iol/docker/Dockerfile cisco/iol/docker/Dockerfile.bak
cp fortigate/docker/Dockerfile fortigate/docker/Dockerfile.bak
```

FortiGateをビルドする場合は追加で以下を実施する。

```bash
# fortigate/docker/Dockerfile の apt パッケージ一覧に qemu-system-x86 を追加
# （arm64ホストでx86 QEMUを動かすために必須。1回のみ）
```

### 検証コマンド

```bash
diff ~/vrnetlab/common/vrnetlab.py ~/vrnetlab/common/vrnetlab.py.bak
# 差分が出ていればパッチ適用済み（.bakは無編集の原本）
grep -n "qemu64" ~/vrnetlab/common/vrnetlab.py
# フォールバック処理が入っているか確認
```

---

## 手順4: Google Driveからのプリビルトイメージロード

**目安時間: イメージ数・回線速度に依存（実績: 13イメージで1〜2時間）**

OrbStack VM内はFUSEマウント（Google Drive for desktop等）が使えないため、**Mac側でマウントしたGoogle DriveのファイルをSSHパイプで直接VM内のdockerへ流し込む**方式を取る。

```bash
# Mac側で実行（Google Driveがマウント済みである前提）
# 例: マイドライブ/Images/Dockerimege/ 配下の各tarファイルを転送
for f in "/path/to/GoogleDrive/マイドライブ/Images/Dockerimege/"*.tar; do
  echo "loading: $f"
  ssh clab@orb "docker load" < "$f"
done
```

- 1ファイルずつ `docker load` の完了を待つ（並列実行すると帯域を食い合い失敗しやすい）。
- 大容量イメージ（C9800-CL 3.5GB、C8000v 2.2GB等）は特に時間がかかるため、`docker images` で個別に完了確認する。

### 検証コマンド

```bash
ssh clab@orb "docker images | grep vrnetlab | wc -l"
# 期待値: ロードしたイメージ数と一致（2026-06-16実績: 13個ロード後、追加ビルドで合計24個）
```

---

## 手順5: IOLライセンス（IOURC）の適用

**目安時間: 30分〜1時間（entrypoint調整含む）**

旧世代Cisco IOLバイナリ（`i86bi_*`系）は modern vrnetlab(v0.21.0) のIOLビルダーが持たない **iourcライセンス生成機構**を必要とする。ライセンスファイルをentrypointに埋め込む方式で対応する。

```bash
# 1) Google Drive「マイドライブ/Images/IOURC.zip」を取得しVM内に展開
ssh clab@orb
mkdir -p ~/iourc_src && cd ~/iourc_src
unzip /path/to/IOURC.zip

# 2) entrypoint.sh にライセンスを埋め込み、hostnameを固定
#    対象: ~/vrnetlab/cisco/iol/docker/entrypoint.sh
#    - IOURCファイルの内容を埋め込む
#    - hostname を `gns3-iouvm` に固定（ライセンスがこのhostname前提で発行されているため）
#    - 起動順序を IOL → iouyap の順に変更（逆順だとsock lockエラーが発生する）
```

entrypoint.shの要点（実装済みの構成、再実装時の参考）:

- `hostname gns3-iouvm` を明示的に設定してからIOLを起動する。
- IOLプロセスは `exec` で直接起動する（`&` によるバックグラウンド起動だと、`docker attach` 時にfd 0が `/dev/null` に落ちてコンソール接続できない）。
- iouyapはIOL起動後に起動する。

### 検証コマンド

```bash
# entrypoint内にライセンス埋め込みとhostname固定が反映されているか
ssh clab@orb "grep -n 'gns3-iouvm' ~/vrnetlab/cisco/iol/docker/entrypoint.sh"
```

---

## 手順6: イメージビルド

**目安時間: 1ノードあたり数分〜（初回ビルドはDockerレイヤ生成込みでやや長い）**

```bash
ssh clab@orb
cd ~/vrnetlab/cisco/iol
rm -f cisco_iol*.bin                                       # 前回分の掃除
cp /path/to/iol_l3sw.bin ./cisco_iol-L2-advipservices-2017.bin
cp /path/to/iol_l2sw.bin ./cisco_iol-L2-15.2.bin
cp /path/to/iol_router.bin ./cisco_iol-15.7.3M2.bin
DOCKER_BUILDKIT=1 make docker-image
docker images | grep cisco_iol
```

FortiGateの場合はビルドコマンドが異なる点に注意。

```bash
cd ~/vrnetlab/fortinet/fortigate
cp /path/to/virtioa.qcow2 ./fortios-v7.4.2.qcow2   # 命名規則厳守（fortios-v...）
make                                                # "make docker-image" ではなく "make"
```

他ベンダーの追加手順は [他ベンダー追加手順.md](他ベンダー追加手順.md) を参照。

---

## 手順7: 動作確認

**目安時間: 10〜15分（IOLは1ノード約2分の起動待ちを含む）**

```bash
ssh clab@orb
cd ~/network-lab/ospf3   # または対象テーマのclab.yml配置先
sudo containerlab deploy -t <対象>.clab.yml

# 起動状態の確認
sudo containerlab inspect -t <対象>.clab.yml

# IOS CLIへのコンソール接続確認
sudo docker attach --sig-proxy=false clab-<lab名>-<node名>
# Enterキーでプロンプト表示 → r1# などが出れば起動確認OK
# 切断: Ctrl-P → Ctrl-Q（Ctrl-Cで切ると強制終了扱いになるため使わない）
```

### FortiGateの場合

```bash
ssh admin@<mgmt-ip>
# 初回パスワード未設定（そのままEnter）
```

### 既知の詰まりどころ（実績ベース）

| 症状 | 原因 | 対処 |
|---|---|---|
| IOLルータ(15.7.3M2)がConfig Dialogでハング（CPU 96%で無限ループ） | ARM64 QEMU上でダイアログ表示処理が固まる | `L2-advipservices-2017` イメージに切り替える（L3ルーティング機能を持ち、ダイアログを出さない） |
| `docker attach` してもコンソールに何も出ない | entrypoint.shが `&` でIOLをバックグラウンド起動しておりfd 0が `/dev/null` | entrypoint.shを `exec` でのIOL直接起動に修正（手順5参照） |
| FortiGateがQEMUクラッシュで起動しない | arm64で `-cpu host` 指定不可 | clab.ymlの環境変数に `QEMU_CPU: qemu64` を設定 |
| `ssh admin@clab-<node>` が `No route to host` | 旧IOLイメージは管理インターフェース/SSHが未設定 | SSHではなく `docker attach` でコンソール接続する |

---

## 撤去・作り直し

```bash
# VM自体を削除して手順1からやり直す場合
orb delete clab
```

個別ラボのみ止める場合はVMは残したまま `sudo containerlab destroy -t <対象>.clab.yml` で十分。VM自体の作り直しが必要になるのは、OrbStack VMそのものが破損・消失した場合のみ。

---

## 関連ファイル

- [環境説明.md](環境説明.md) — 現在の環境の全体像・アクセス方法・使用可能イメージ一覧
- [他ベンダー追加手順.md](他ベンダー追加手順.md) — IOL以外のベンダー機器の追加手順
- `イメージマニフェスト.md`（別途生成中） — 稼働イメージの棚卸し一覧
- [../規約/提案_運用改善.md](../規約/提案_運用改善.md) — 本runbookの維持運用・四半期棚卸しの提案
