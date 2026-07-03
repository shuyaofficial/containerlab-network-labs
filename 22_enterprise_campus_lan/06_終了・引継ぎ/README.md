# テーマ22 終了・引継ぎ

## 1. まず結論

テーマ22は2026-06-29に、部分達成の状態で終了した。

できたことは、支社PCから本社サーバまでのCisco-Cisco IPsec VPN通信である。できなかったことは、A棟LANの完全復旧、FortiGateによるFW/NAT、Cisco IOLでのNAT、全試験項目の完走である。

このフォルダは「あとで再挑戦するときの入口」であり、次テーマを始めるためにテーマ22を直す必要はない。

## 2. 環境を全く知らない人向けの説明

### 2.1 何を作っていたか

会社のネットワークをPCの中に仮想的に再現していた。

- 本社: A棟とB棟があり、コア、ディストリビューション、アクセスという3階層のスイッチ構成
- 支社: 支社PCと支社ルーター
- インターネット役: ISPルーター
- 拠点間接続: 本社と支社を暗号化して結ぶIPsec VPN
- サーバ: 社内ポータルとファイルサーバ

実機を何台も用意する代わりに、`containerlab` がDockerコンテナとして仮想ルーター、スイッチ、PCを接続する。Cisco機器は `vrnetlab/cisco_iol` イメージを使う。

### 2.2 Macと仮想環境の関係

```text
Mac mini（操作・資料保存）
  -> OrbStack
     -> Linux VM「clab」（containerlabの実行場所）
        -> 仮想Cisco機器とLinux PC/サーバ
```

- Mac本体はApple Siliconの`arm64`。
- `ssh clab@orb` で入るOrbStack Linux VMは`aarch64`で、`/usr/bin/containerlab`がある。
- テーマ22の実行用イメージは主にLinux VM「clab」側にある。
- Mac側の`docker images`と、`ssh clab@orb`後の`docker images`は同じ一覧とは限らない。確認場所を必ず明記する。
- x86仮想FWのASAvやFortiGateは、イメージが存在しても`/dev/kvm`がないApple Silicon/OrbStackでは実用的な実行が難しい。

### 2.3 終了時点の機器構成

- `core1/core2`: 本社の中心となるCisco IOL
- `dist-a1/dist-a2`: A棟のL3スイッチ
- `dist-b1`: B棟のL3スイッチ
- `acc-a1/acc-a2/acc-b1`: PCやサーバを収容するL2スイッチ
- `isp`: インターネットを模擬するCisco IOL
- `br-edge`: 支社側Cisco VPNルーター
- `fgt-edge`: 名前はFortiGateの名残だが、終了時点の実体はCisco IOLの本社VPNルーター
- `pc-sales/pc-dev/br-pc`: 利用者PC役のLinuxコンテナ
- `srv-file/srv-portal`: 社内サーバ役のLinuxコンテナ

## 3. 最初の状態から何が変わったか

1. 当初は、本社境界の`fgt-edge`にFortiGate VMを置き、支社CiscoとのマルチベンダーVPNを作ろうとした。
2. IKE/IPsecの確立とFortiGateでの復号までは確認できたが、復号後のLAN転送が成立しなかった。
3. FortiGateはinvalid license状態で、Apple Silicon/OrbStackにはx86 KVMもなかった。KVM不足だけが原因と断定はできないが、安定したFW検証環境ではなかった。
4. 切り分けのため、ノード名`fgt-edge`を残したまま実体をCisco IOLへ置換した。
5. Cisco同士のVTI/IKEv2/IPsecとして再構成し、支社PCから本社ポータルへのpingとHTTP 200に成功した。
6. VPN成功を優先したため、FortiGateのFWポリシーとSNAT、A棟のSVI、全障害試験は未完のまま残した。

## 4. できたこと

- 要件定義、基本設計、IPアドレス管理、論理・物理構成図を作成した。
- 大規模な3階層キャンパスLAN、OSPFマルチエリア、MST、HSRP、VPNの設計資料を作成した。
- FortiGate-Cisco VPNで、暗号化確立と復号後転送を段階的に切り分けた。
- FortiGateをCisco IOLへ置換し、`br-pc -> srv-portal`のpingとHTTP 200を確認した。
- Cisco-Cisco IKEv2/IPsec VTI、OSPF、静的経路の設定を再利用可能な形で保存した。
- deploy後にIOLのデータプレーンを動かす`iouyap`起動処理を`build_and_deploy.sh`へ追加した。

## 5. できなかったこと

- A棟VLAN10/20のSVI復旧と、`pc-sales`/`pc-dev`からサーバへの疎通
- MST、HSRP、経路集約、片系断など全試験項目の実施と証跡採取
- 本社および支社のPAT/SNAT
- FortiGateのステートフルFWポリシー、NAT、GUI運用
- ASAvによるFW/NAT/VPNの代替実装
- ライブ設定と全`config_commands`ファイルの完全一致確認

## 6. 再開するときに最初に読む順番

1. 本書
2. `../05_試験/試験結果_2026-06-29.md`
3. `../../切り分け/fortigate_cisco_swap_RESOLVED_2026-06-26.md`
4. `../../切り分け/fortigate_cisco_ipsec_transit_unresolved_2026-06-26.md`
5. `../02_基本設計/IPアドレス管理表.md`
6. `../campus.clab.yml`
7. `../03_詳細設計/config_commands/fgt-edge.txt`と`br-edge.txt`
8. `../build_and_deploy.sh`

## 7. 再開時の安全ルール

- 最初に`status`と読み取り専用の確認を行い、いきなり`deploy`や`destroy`を実行しない。
- `destroy --cleanup`はNVRAMや実行状態を失う可能性がある。必要な設定を退避してから使う。
- `fgt-edge`という名前からFortiGateだと思い込まない。`campus.clab.yml`の`kind`と`image`を確認する。
- `running-config`と保存済みファイルが一致するとは限らない。ライブ状態を正とする場合は先にバックアップする。
- ASAv/FortiGateを試す場合は、Mac上のイメージ有無ではなく、x86_64 Linux KVMホストと有効なライセンスの有無を先に判定する。

## 8. 次に進む方針

次はテーマ23「業務用の内部DNS」を推奨する。理由は、ARM64対応のLinuxコンテナで小さく始められ、FortiGateやCisco IOLの不安定要因から一度離れられるためである。

最小構成はDNSサーバ1台とクライアント1台でよい。正引き、逆引き、存在しない名前、キャッシュ、ログ確認までを試験する。作成用の具体的な依頼文は`次テーマ開始プロンプト_初心者向け.md`に保存した。

