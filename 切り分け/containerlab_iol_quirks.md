# Containerlab / Cisco IOL 環境特有の挙動とトラブルシューティング（切り分けノウハウ）

このファイルは、物理機器での本来の挙動とは異なる「仮想環境（エミュレータ）特有の仕様・バグ」や、ハマりやすい罠、トラブルシューティング時の切り分け方法について蓄積していくナレッジベースです。
ネットワーク構築が想定通りに動かない場合、まずはここに記載されている事象に該当しないか確認してください。

---

## 1. リンクダウン（Shutdown）の検知に関する仕様（EtherChannelでのブラックホール問題）

### 事象
* EtherChannelを `mode on`（LACP等のネゴシエーションなしの静的モード）で構築している環境下で発生。
* 一方のスイッチで物理インターフェースを `shutdown` してダウンさせても、**対向のスイッチでは該当インターフェースが「UP（Bundled）」のままと認識される。**
* 結果として、対向スイッチは「ダウンしているポート」に向かって負荷分散（ハッシュ）でパケットを送り続けてしまい、Ping等の通信が100%パケットロスする（ブラックホール化）。

### 物理環境との違い（原因）
物理のLANケーブルで直結されている場合、片方をシャットダウンすると電気信号のキャリアが途絶えるため、対向機器も瞬時に「リンクダウン」を検知し、リンクを無効化します。
しかし、Containerlabなどの仮想環境では、機器同士がLinuxの「仮想ケーブル（vethペア）」で繋がっています。Cisco IOL内部でポートを論理的に `shutdown` しても、外側の仮想ケーブル自体はホストOS上で繋がったままであるため、対向のIOLは「ケーブルは刺さっていてUPしている」と勘違いし続けてしまいます。

### 切り分け・回避策
* **LACP (`mode active`) を使用する**: LACPは定期的に生存確認パケット（LACP PDU）を交換するため、物理リンクがUPと見えていてもPDUが返ってこなければ安全に束から切り離してくれます。
* **対向側も手動で Shutdown する**: 検証のために疑似的に線を抜いた状態を作りたい場合は、対向機器側のポートも同時に `shutdown` する必要があります。

---

## 2. Linuxコンテナ（Alpine等）と Cisco IOL 間の L2 接続バグ

### 事象
* PCとしてLinuxコンテナ（Alpine等）を使用し、Cisco IOLスイッチのアクセスポートに接続して通信（Ping等）を行おうとする。
* スイッチ側で `%AMDP2_FE-6-EXCESSCOLL: Ethernet0/2 TDR=0, TRC=0` のような大量の「Excessive Collisions（過剰なコリジョン）」エラーログが発生し、通信が完全に遮断される。

### 原因
仮想環境上のインターフェース（Linux側のvethとIOL側のエミュレートNIC）の間で、Speed/Duplex（全二重・半二重）の自動ネゴシエーションが正しく機能せず、物理層のエラーとして扱われてしまうというエミュレータ同士の相性問題（バグ）です。

### 切り分け・回避策
* **Cisco IOL同士で統一する**: エンドホスト（PC）が必要な場合でもLinuxコンテナを使わず、Cisco IOLイメージを配置してルーター機能をオフ（またはデフォルトルートのみ設定）にして「仮想的なPC」として扱うことで完全に回避可能です。

---

## 3. L2 イメージでの IP ルーティングの罠

### 事象
* L2用のIOSイメージ（例: `vrnetlab/cisco_iol:L2-15.2`）において、`ip routing` コマンドを入力してもエラーにならない。
* VLANインターフェース（SVI）にIPアドレスを設定し、インターフェースもUPしているように見える。
* にもかかわらず、VLANをまたぐ通信（VLAN間ルーティング）が全く行われない。Pingが届かない。

### 原因
L2専用イメージの仕様として、CLIパーサーはルーティング系のコマンド（`ip routing` や `router ospf` など）を受け付けますが、内部のフォワーディングエンジン（L3ルーティング機能）が存在しない・または無効化されているため、パケットが転送されません。

### 切り分け・回避策
* **適切なイメージの選定**: L3機能（SVIでのルーティング、OSPFやBGPなどの動的ルーティング）が必要な機器には、必ず `L2-advipservices-2017` などの「Advanced IP Services」やL3スイッチとしての機能が含まれたイメージを使用してください。

---

## 4. Cisco IOL を「PC」として代用する際の罠

### 事象
* PC代わりのIOL機器で `no ip routing` を設定し、`ip default-gateway` を設定したところ、外部（Containerlabのホストマシン等）からのSSHログインやPing応答が一切できなくなり、機器がフリーズしたような状態になる。

### 原因
Containerlabでは、管理用のインターフェース（`eth0` / `Management0/0` など）にDockerのブリッジネットワークのIPアドレスを動的に割り当てて通信を行っています。
Cisco IOL上で `no ip routing` をグローバルに設定してしまうと、エミュレータ全体でのルーティング機能が完全に停止するため、この「管理用インターフェース」のルーティングも動作しなくなり、ホストとの通信が遮断されてしまいます。

### 切り分け・回避策
* **スタティックルートで代用する**: `no ip routing` は使用せず、IPルーティング機能は有効（デフォルト）のままで、`ip route 0.0.0.0 0.0.0.0 <ゲートウェイIP>` のようにデフォルトルートを静的に設定します。これにより、PCと同じようにデフォルトゲートウェイへ通信を投げつつ、管理用ネットワークの通信も正常に維持できます。

---

## 5. Containerlab (`.clab.yml`) のインターフェース命名規則

### 事象
* `.clab.yml` ファイルの `endpoints` において、`["sw1:Ethernet0/1", "sw2:Ethernet0/1"]` のようにCiscoのインターフェース名を直接指定すると、コンテナが起動しないか、仮想ケーブルが正しく接続されない。

### 原因
Containerlabが仮想ケーブル（veth）をコンテナにアタッチする際は、Linux OSレベルのインターフェース名を使用します。そのため、Cisco固有の表記（`Ethernet` や `GigabitEthernet`）はLinux側では認識されません。

### 切り分け・回避策
* トポロジファイル内では、必ず `["sw1:eth1", "sw2:eth1"]` のようにLinux標準の命名規則（`eth1`, `eth2`...）を使用します。
* 内部でCisco IOSが起動した際、自動的に `eth1` → `Ethernet0/1`、`eth2` → `Ethernet0/2` とマッピングされて認識されます。

---

## 6. 機器の「役割」に応じたイメージ選定と `type` 設定（超重要）

### 事象
* ルーターとして使いたい機器（R1など）に対し、トポロジファイルで `type: l2` をグローバル設定したり、L2スイッチ用イメージを使用してしまうと、ルーターではなく「L2スイッチ」として起動してしまう。
* 結果、`no switchport` が不要なはずの物理インターフェースに `switchport` モードが適用され、ルーティングが意図通りに動作しない。
* 逆に、L3スイッチ（SVI・VLAN・トランクなどL2機能も必要）に `type: l2` を付け忘れると、L3ルーターモードで起動し、VLAN関連のコマンドが一切使えない。

### 原則：役割ごとの正しいイメージと `type` 設定

| 役割 | 使用する機能 | イメージ例 | `type` 設定 |
|---|---|---|---|
| **ルーター** (R1等) | OSPF, BGP, ルーティングのみ | `vrnetlab/cisco_iol:15.7.3M2` (L2-プレフィックスなし) | 指定しない（デフォルト = ルーター） |
| **L3スイッチ** (SW1, SW2等) | VLAN, トランク, SVI, HSRP, OSPF | `vrnetlab/cisco_iol:L2-advipservices-2017` | `type: l2` （必須） |
| **L2スイッチ** (SW3等) | VLAN, トランク, STPのみ | `vrnetlab/cisco_iol:L2-15.2` | `type: l2` （必須） |
| **疑似PC** (PC1等) | IPアドレスとデフォルトルートのみ | `vrnetlab/cisco_iol:L2-15.2` | `type: l2` |

### 注意点
* **`type: l2` をグローバル設定（`kinds` 配下）にしない**こと。ルーターとスイッチが混在するトポロジでは、各ノードに個別で `type` を設定する。
* イメージ名の `L2-` プレフィックスは「L2スイッチモード用のイメージ」を意味する。ルーターとして使うノードには `L2-` プレフィックスのないイメージ（例: `15.7.3M2`）を選定すること。

### .clab.yml の正しい書き方の例
```yaml
topology:
  nodes:
    r1:
      kind: cisco_iol
      image: vrnetlab/cisco_iol:15.7.3M2      # ルーター用イメージ（L2-なし）
      # type 指定なし = ルーターモード
    sw1:
      kind: cisco_iol
      image: vrnetlab/cisco_iol:L2-advipservices-2017  # L3スイッチ用
      type: l2                                          # L2モードで起動
    sw3:
      kind: cisco_iol
      image: vrnetlab/cisco_iol:L2-15.2        # L2スイッチ用
      type: l2
```

## 4. L2スイッチのSVI（VLANインターフェース）におけるDHCPクライアント機能の制限
- **対象イメージ**: `vrnetlab/cisco_iol:L2-15.2` などの純粋なL2スイッチイメージ
- **事象**:
  クライアントPCの代わりとしてL2スイッチを配置し、`interface Vlan 10` のようなSVIに対して `ip address dhcp` を設定しようとしても、`dhcp` オプションが存在せず弾かれる（手動IPかpoolしか選べない）。
- **原因**:
  該当バージョンのL2スイッチイメージでは、SVIでのDHCPクライアント機能がサポートされていないため。
- **回避策（ワークアラウンド）**:
  SVIではなく、物理インターフェース（例: `Ethernet0/1`）を `no switchport` コマンドでL3ポート化し、その物理ポートに対して `ip address dhcp` を設定する。対向のスイッチポートが `switchport access vlan X` であれば、正常にDHCPリレー等の検証が可能。

---

## 7. iouyap 未起動バグ（全ノードで L2 通信が完全に不通になる重大な問題）【2026-06-19 発見】

### 事象
* `clab deploy` 後、全てのCisco IOLノードで以下の症状が発生する。
  * `show cdp neighbors` が **0件**（全ノード共通）
  * 全ポートで **Ping不通**、**MACアドレステーブルが空**
  * STP（MST/RSTP）の **BPDU が交換されず**、全スイッチが自分をRoot Bridgeだと主張する
  * LAGの `show etherchannel summary` は `Po1(SU)` で正常に見えるが、実際のデータ転送は行われない
* IOL内部のインターフェースは `UP/UP` と表示されるため、一見正常に見える。
* `show interfaces EtX/X | include packets` で確認すると、**output は増加するが input が常に 0** という決定的な片方向通信状態になる。

### 原因
Cisco IOLコンテナの `entrypoint.sh` に **`iouyap`（IOL Data Plane Relay）プロセスの起動行が欠落**している。

IOLのアーキテクチャでは、IOL本体（`iol.bin`、IOLインスタンス ID=8等）はUnixドメインソケット経由で仮想インスタンス ID=513 と通信する設計になっている。`iouyap` はこのインスタンス513として動作し、IOLの内部ネットワークとコンテナの `eth` インターフェース（Containerlabのvethペア）を橋渡しする**必須プロセス**である。

しかし、`entrypoint.sh` は IOL本体を `exec` で起動するだけで、事前に `iouyap` を起動する処理が存在しない。そのため：
1. IOL → instance 513 へパケットを送信するが、誰も受け取らない（output だけが増加）
2. コンテナの eth → IOL へのパケットも橋渡しされない（input が常に 0）
3. 結果として、全ノードが完全に孤立した状態になる

### 確認方法（切り分けコマンド）
```bash
# 1. iouyap が動いているか確認（全ノードで実行）
docker exec clab-campus-<ノード名> find /proc -maxdepth 2 -name exe -exec ls -la {} \; 2>/dev/null | grep iouyap

# 2. iouyap がいなければ → このバグに該当
# 3. パケットカウンターで片方向通信を確認
docker exec clab-campus-<ノード名> ip -s link show eth1

# 4. iouyap の設定ファイルが存在するか確認
docker exec clab-campus-<ノード名> cat /iol/iouyap.ini
docker exec clab-campus-<ノード名> cat /iol/NETMAP
```

### 回避策（手動）
各Cisco IOLコンテナ内で、手動で `iouyap` を起動する：
```bash
# 単体起動
docker exec -d clab-campus-<ノード名> /usr/bin/iouyap -q -f /iol/iouyap.ini -n /iol/NETMAP 513

# 全ノード一括起動（テーマ22用）
for node in core1 core2 dist-a1 dist-a2 dist-b1 acc-a1 acc-a2 acc-b1 isp br-edge; do
  docker exec -d clab-campus-$node /usr/bin/iouyap -q -f /iol/iouyap.ini -n /iol/NETMAP 513
done
```

### 恒久対策
`build_and_deploy.sh` の `deploy()` 関数に iouyap 自動起動処理を追加済み（2026-06-19）。
詳細は `22_enterprise_campus_lan/build_and_deploy.sh` の `start_iouyap()` 関数を参照。

### eth → Cisco IOL インターフェースマッピング表（iouyap.ini による正式マッピング）

| Containerlab (eth) | Cisco IOL | 用途（テーマ22 dist-a1 の例） |
|---|---|---|
| eth0 | Ethernet0/0 | **管理用（予約・使用禁止）** |
| eth1 | Ethernet0/1 | core1 向けアップリンク |
| eth2 | Ethernet0/2 | core2 向けアップリンク |
| eth3 | Ethernet0/3 | acc-a1 向けトランク |
| eth4 | Ethernet1/0 | acc-a2 向けトランク |
| eth5 | Ethernet1/1 | Po1 メンバー（dist-a2 向け） |
| eth6 | Ethernet1/2 | Po1 メンバー（dist-a2 向け） |
| eth7 | Ethernet1/3 | （未使用） |

※ マッピングは固定（スキップしてもズレない）。4ポート単位でスロットが繰り上がる。

---

## 8. 「VLANを作ってもHSRP/L2が上がらない」＝SVIのautostateダウン（同一症状の多層化に注意）【2026-06-29 テーマ23】

### 事象
* HSRP の `show standby brief` で **Standby が永遠に `unknown`**、`show spanning-tree` で各コアが自分をRootと主張する（Split Brain）。
* iouyap を直し、さらに不足していた `vlan 10/20` を **VLANデータベースに作成しても、まだ収束しない**。
* `show standby` を詳しく見ると **`State is Init (interface down)`**。つまり **SVI（`interface Vlan10`）自体がダウン**していてHSRPが起動していない。

### 原因（バグではなく仕様。だが切り分けで超ハマる）
SVI(`interface VlanX`)が line-protocol **up** になる条件は、`no shutdown` に加えて
**「そのVLANに属する”up”なポートが最低1つ存在し、かつSTPで forwarding」**（autostate）。
コア機のように **VLANがトランク上にしか存在しない**構成では、
`vlan X` をDB作成 → **トランクでVLAN Xが active** → **STP forwarding** → ようやくSVIがUp、という連鎖が全部揃って初めてHSRPが Init を抜けて収束する。
`vlan X` を作った直後はまだ active/forwarding になりきっておらず、数秒〜STP収束ぶんのラグがあるため「作ったのに通らない→少し経って急に通る」という挙動になる。

### 決定的な切り分けコマンド（同一症状を層で切り分ける順番）
```
show standby brief           # State が Init なら → SVIダウン（VLAN/autostate側）。unknownでInitでないなら → L2到達側
show standby Vlan10           # "State is Init (interface down)" を確認
show ip interface brief | inc Vlan   # SVI が up/up か down か
show interfaces trunk        # 該当VLANが「allowed and active」「forwarding state」に出ているか（none ならVLAN未活性）
show vlan brief              # VLAN X が active で存在するか（無ければDB未作成）
show spanning-tree vlan 10   # "instance does not exist" ならVLAN未活性
```

### 同一症状（standby unknown / Split Brain）の3層チェックリスト
| 層 | 症状の見え方 | 確認 | 対処 |
|---|---|---|---|
| ①インフラ: iouyap未起動 | 全ノードCDP=0、input常時0、全機Root | `find /proc -name exe|grep iouyap` 無し | `iouyap 513`(`-w /iol`) 起動（本ノート#7） |
| ②設定: VLAN未作成 | trunkは allowed だが active=none、STP instance無し | `show vlan brief` に該当VLAN無し | VLANデータベースに `vlan X` 作成 |
| ③連鎖: SVI autostateダウン | HSRPが `State Init (interface down)` | `show standby` が Init | VLAN活性化＋STP forwarding待ち（数秒）。trunk/STPが上がればSVI自動Up |

### 教訓
* **「standby unknown」だけでは原因を1つに決めない**。①L2到達(iouyap) → ②VLAN存在 → ③SVI Up、の順で必ず切り分ける。
* SVIが上がらないときは真っ先に `show standby`（Init=interface down）と `show interfaces trunk` の **active/forwarding 列**を見る。`allowed` 列だけ見て満足しない。
* コア機はVLANがトランクのみに存在するため、autostateの影響を受けやすい。検証で焦って何度も設定し直す前に、STP収束（最大~30秒）を待つ。
