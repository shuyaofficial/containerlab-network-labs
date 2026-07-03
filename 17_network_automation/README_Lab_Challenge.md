# テーマ17：ネットワーク自動化基盤の構築（Ansible / Python）

## 🎯 目的
これまでのラボでは、ルーターにログインして1台ずつコマンドを手打ちしてきました。
しかし実際のデータセンターや大規模ネットワークでは、数百台のルーターの設定変更を人間が手作業で行うのは非現実的であり、ミスの原因にもなります。

今回は **「Ansible（アンシブル）」** というオープンソースの自動化ツールを使い、人間がルーターに触れることなく、プログラム（Playbook）から全自動で設定を流し込む「Network Programmability」の世界を体験します。

## 🏗️ ネットワーク構成
- **Controller**: Ubuntuコンテナ（自動化指令サーバー / Ansibleインストール済）
- **R1**: Cisco IOLルーター (管理IP: 自動割当)
- **R2**: Cisco IOLルーター (管理IP: 自動割当)
- **接続**: R1 (e0/1) ⇔ R2 (e0/1)
  ※今回は管理ネットワーク経由で自動化を実行し、e0/1同士をOSPFで繋ぎます。

---

## 🛠️ 検証ステップ（自動化の魔法を体験する）

### 1. ラボのデプロイ
まずは環境を立ち上げます。
※起動時にControllerコンテナ内部でPythonやAnsibleのインストールが自動実行されるため、完了まで少し時間がかかります。
```bash
cd /Users/shuya/Documents/claude/Mac仮想環境構築/17_network_automation
sudo containerlab deploy -t automation.clab.yml
```

### 2. Controllerサーバーにログイン
人間の代わりに作業をしてくれる「自動化指令サーバー（Controller）」の中に入ります。
```bash
docker exec -it clab-automation-controller bash
```
> [!NOTE]
> ログイン後、`cd /workspace` コマンドで作業ディレクトリに移動してください。ここにはMac側にあるファイル（Playbookなど）が見えています。

### 3. 【検証1】ルーターの疎通確認（一斉Ping）
Ansibleを使って、インベントリ（名簿）に登録されているすべてのルーター（R1とR2）に対して一斉に接続テストを行います。
人間が個別にログインしてPingを打つ必要はありません。

Controller内で以下のコマンドを実行します。
```bash
ansible -m ping all
```
> 👉 `r1 | SUCCESS` と `r2 | SUCCESS` が表示されれば、Ansibleが両方のルーターへのアクセス権を獲得しています！

### 4. 【検証2】魔法の実行（一発でOSPFを全構築）
それでは、本番です。
以下のコマンドを打ち込むと、Ansibleが `ospf_setup.yml` の手順書（Playbook）を読み込み、R1とR2に同時にログインし、IPアドレスの設定からOSPFの立ち上げまでを**数秒で全自動実行**します。

```bash
ansible-playbook ospf_setup.yml
```
> 👉 画面に `changed` と表示されれば、設定の書き換えが成功しています！

### 5. 【検証3】結果の確認（人間による確認）
Ansibleの実行が終わったら、本当に設定が入ったのか疑い深い目で確認してみましょう。
Macのターミナル（別のタブ）から、R1にログインします。
```bash
docker exec -it clab-automation-r1 ssh admin@localhost
```

R1の中で以下のコマンドを打ち、設定が入っているか確認してください。
```bash
R1# show ip ospf neighbor
R1# show run
```

> **🎉 【ゴール】**
> あなたは一切 `conf t` などの設定コマンドを打っていないのに、R2との間でOSPFネイバーが確立され、ルーティングテーブルができあがっているはずです！これが自動化（インフラのコード化＝IaC）の力です。
