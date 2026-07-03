# Ansible を用いた一括設定マニュアル

今回はシェルスクリプト (`configure_all.sh`) と Expectスクリプト で自動化を行いましたが、本番環境などで **Ansible** を使用して構成管理を行う場合のサンプルファイルを作成しました。

## ディレクトリ構成
```text
04_構築/ansible_demo/
├── ansible.cfg       # Ansible の動作設定
├── inventory.ini     # 接続先ルーター/スイッチのIP一覧
├── site.yml          # 実行するPlaybook
└── configs/          # 各機器に流し込むConfigファイル (.cfg)
    ├── isp.cfg
    ├── hq-edge1.cfg
    └── ...
```

## 事前準備
1. Ansible本体とCiscoモジュールがインストールされている必要があります。
   ```bash
   pip install ansible
   ansible-galaxy collection install cisco.ios
   ```
2. `configs/` ディレクトリ配下に、流し込みたい設定ファイル（例: `hq-edge1.cfg`）を機器のホスト名に合わせて作成・保存しておきます。

## 実行方法
`ansible_demo` ディレクトリに移動し、以下のコマンドを実行します。

```bash
cd 04_構築/ansible_demo/
ansible-playbook -i inventory.ini site.yml
```

### 処理内容
Playbook (`site.yml`) は以下の順序で動作します。
1. `inventory.ini` に記載された対象機器（172.20.20.X）にSSH接続します。
2. `configs/<ホスト名>.cfg` ファイルの中身を読み込み、ルーターの Running-Config に適用します（差分反映）。
3. 変更があった場合のみ、自動的に `write memory` (Save) を実行します。

## 注意点（Cisco IOL環境での制約）
今回 Ansible をメインで使わなかった理由として、「L2スイッチ (`hq-core1`, `hq-core2`) がデフォルトで管理IPを受け取れない状態（スイッチポート）で起動する」という問題があったためです。
AnsibleはSSHで通信できることが前提となるため、今回のような**IPアドレスを持たない初期状態の機器**に対しては、直接コンソール操作を行うツール（`expect` やコンソールケーブル経由でのスクリプト）で初期設定（アンダーレイ）を行う必要があります。
