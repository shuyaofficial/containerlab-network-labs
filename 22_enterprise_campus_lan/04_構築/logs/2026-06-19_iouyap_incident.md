# トラブルシューティングログ: 全Cisco IOLノードでのL2通信不通（iouyap未起動バグ）

## 発生日時
2026-06-19

## 事象
* `clab deploy` 後、MSTPやEtherChannelの設定を正しく行っても、全Cisco IOLノード間で以下の症状が発生した。
  * `show cdp neighbors` が全機器で 0件になる。
  * LACP が `suspended` となりネゴシエーションに失敗する。
  * STP の BPDU が交換されず、各スイッチが自身を Root Bridge だと認識する。
  * VLAN 1 (SVI) への Ping が失敗する。
  * MACアドレステーブルが空のままになる。
* Cisco IOL上のインターフェース自体は `UP/UP` と表示されており、設定ミスは見当たらない。
* `show interfaces EtX/X | include packets` で確認すると、output（送信パケット）は増加するが、input（受信パケット）が常に 0 という「完全な片方向通信」状態になっていた。

## 切り分けプロセス
1. **Containerlab のポートマッピングの確認**: `eth` インターフェースと Cisco IOL の `Ethernet` インターフェースのマッピングを検証した結果、マッピング自体は正常（eth1=Et0/1, eth5=Et1/1 等）であり、問題の原因ではないと判明。
2. **Ping / MACアドレス / CDP / LLDP の動作確認**: どの L2/L3 プロトコルも動作していないことを確認。
3. **veth のパケットカウンター確認**: Linux ホスト側から `ip -s link show` で仮想ケーブル（veth）のパケットを確認したところ、veth レベルではパケットの送受信が行われていることが判明。
4. **Cisco IOL コンテナ内のプロセス確認**: これが決定打となった。コンテナ内で `ps` コマンド等を用いてプロセスを確認したところ、IOL本体 (`iol.bin`) は起動しているものの、IOLの内部ネットワークとLinuxのvethを橋渡しするデーモンである **`iouyap` プロセスが存在しない** ことが発覚した。

## 根本原因
`vrnetlab/cisco_iol` イメージの起動スクリプト (`entrypoint.sh`) に欠陥があり、最後に `exec /iol/iol.bin ...` としてIOL本体を起動しているのみで、`iouyap` プロセスを起動する処理が抜けていた。
`iouyap` が存在しないため、IOLから送出されたパケットはvethへ転送されず、vethから受信したパケットもIOLへ転送されない状態（ブラックホール状態）になっていた。

## 解決策
### 暫定対応（手動）
各Cisco IOLコンテナに入り、手動で `iouyap` プロセスをバックグラウンド起動した。
```bash
docker exec -d clab-campus-<ノード名> /usr/bin/iouyap -q -f /iol/iouyap.ini -n /iol/NETMAP 513
```
起動直後、約10〜20秒で各プロトコル（CDP, LACP, STP）のパケットが交換され始め、正常にネイバー関係が構築されることを確認した。

### 恒久対策
デプロイするたびに毎回手動で起動するのは非現実的であるため、環境構築用のスクリプト (`build_and_deploy.sh`) を改修した。
`sudo containerlab deploy` 実行直後に、Dockerコマンド経由で全Cisco IOLノードに対して自動で `iouyap` の起動コマンドを発行する処理を `deploy()` 関数に追加した。

```bash
  for container in $(sudo docker ps --format '{{.Names}}' | grep '^clab-campus-' | grep -v -E 'fgt-edge|pc-|srv-|br-pc'); do
    sudo docker exec -d "$container" /usr/bin/iouyap -q -f /iol/iouyap.ini -n /iol/NETMAP 513 2>/dev/null || true
  done
```
これにより、次回以降は `deploy` コマンドを叩くだけで自動的に通信可能な状態が構成されるようになった。
