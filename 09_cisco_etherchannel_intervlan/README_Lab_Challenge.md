# Cisco EtherChannel & Inter-VLAN Routing Challenge

このドキュメントは、Mac上のContainerlab環境でCisco機器を用いた「EtherChannel」および「VLAN間ルーティング」の検証環境を構築するための要件と、これまでの検証で判明した環境依存のバグや注意点（トラブルシューティングログ）をまとめたものです。

一からご自身で設定に挑戦される際のガイドラインとしてご活用ください。

---

## 🎯 構築チャレンジ要件

### 1. 機器構成（トポロジ）
以下の4台のCisco IOL機器を使用します。

- **SW1 (Core Switch)**
  - 役割: L3スイッチ（VLAN間ルーティングおよびL2アグリゲーション）
  - イメージ: `vrnetlab/cisco_iol:L2-advipservices-2017` (L3ルーティング対応)
- **SW2 (Access Switch)**
  - 役割: L2スイッチ（PCの収容）
  - イメージ: `vrnetlab/cisco_iol:L2-15.2`
- **PC1 (End Host 1)**
  - 役割: VLAN 10 に所属するPC
  - イメージ: `vrnetlab/cisco_iol:L2-15.2`（疑似PCとして使用）
- **PC2 (End Host 2)**
  - 役割: VLAN 20 に所属するPC
  - イメージ: `vrnetlab/cisco_iol:L2-15.2`（疑似PCとして使用）

### 2. ネットワーク要件
1. **VLAN設定**
   - VLAN 10 (PC1用) / ネットワーク: `10.10.10.0/24`
   - VLAN 20 (PC2用) / ネットワーク: `10.10.20.0/24`
2. **EtherChannel (Port-Channel) 設定**
   - SW1 と SW2 の間を2本のケーブルで接続し、**LACP (mode active)** で論理的に1本のリンク（Port-channel 1）として束ねる。
   - 該当ポートはトランクポート（Trunk）とし、VLAN 10, 20 の通信を許可する。
3. **アクセスポート設定**
   - SW2 と PC1 の接続ポートは **VLAN 10** のアクセスポートとする。
   - SW2 と PC2 の接続ポートは **VLAN 20** のアクセスポートとする。
   - ※可能であれば、PC接続ポートに `spanning-tree portfast` を設定する。
4. **VLAN間ルーティング (SVI)**
   - SW1 に各VLANのSVI（デフォルトゲートウェイ）を作成する。
     - VLAN 10 SVI: `10.10.10.254`
     - VLAN 20 SVI: `10.10.20.254`
   - SW1 でIPルーティングを有効化する。
5. **PCのIP設定**
   - PC1: `10.10.10.11 /24`, ゲートウェイ: `10.10.10.254`
   - PC2: `10.10.20.12 /24`, ゲートウェイ: `10.10.20.254`

### 3. 最終目標
**PC1 から PC2 (10.10.20.12) に対してPingを送信し、通信が成功すること。**

---

## ⚠️ 環境構築時のバグ・注意点ログ (Lessons Learned)

これまでの構築で発生した数々のトラブルと、Containerlab×Cisco IOL特有のバグ・回避策のまとめです。このトラップを避けることでスムーズに構築が可能です。

### 🚨 1. Linuxコンテナ(Alpine)とCisco IOL間の物理層バグ
- **事象**: エンドホスト（PC）としてAlpine Linuxコンテナを使用し、Cisco IOLスイッチ（SW2）に接続してPingを打つと、SW2側で `%AMDP2_FE-6-EXCESSCOLL: Ethernet0/2 TDR=0, TRC=0` という大量のコリジョンエラーログが発生し、Pingが100%パケットロスする。
- **原因**: 仮想環境におけるLinux vethインターフェースと、Cisco IOLのエミュレーションインターフェース間でのDuplex/Speedのミスマッチバグ。
- **回避策**: エンドホスト（PC）にもLinuxではなく **Cisco IOLイメージ** を使用し、仮想的なPCとして扱うことで解決する。

### 🚨 2. L2イメージでのIPルーティングの罠
- **事象**: `vrnetlab/cisco_iol:L2-15.2` イメージで `ip routing` コマンドを入力でき、エラーも出ないが、VLAN間ルーティングが一切機能しない。
- **原因**: L2専用イメージのため、コマンド自体はパースされるがルーティングエンジンが動作しない。
- **回避策**: コアスイッチなどL3機能（VLAN間ルーティング）が必要なノードには、必ずL3機能が含まれたイメージ（例: `L2-advipservices-2017`）を使用する。

### 🚨 3. Containerlab (clab.yml) でのインターフェース名の罠
- **事象**: `cisco_etherchannel.clab.yml` の `endpoints` で `["sw1:Ethernet0/1", "sw2:Ethernet0/1"]` のようにCiscoのインターフェース名を直接指定すると、コンテナ間で正しく仮想ケーブルが結線されない。
- **原因**: Containerlabは内部的に `ethX` というLinuxの命名規則で仮想インターフェース（veth）をバインドしているため。
- **回避策**: トポロジファイル内では必ず `["sw1:eth1", "sw2:eth1"]` のように `eth1`, `eth2`... というフォーマットで記述する。※Cisco内部では `eth1` が `Ethernet0/1`、`eth2` が `Ethernet0/2` のようにマッピングされる。

### 🚨 4. Cisco IOLを「PC」として扱う際の設定の罠
- **事象**: Cisco IOLをPCとして使う際、ルーターとして動かないように `no ip routing` と `ip default-gateway` を設定したところ、Dockerが割り当てる管理用ネットワークのIP（通信）まで無効化され、外部からログインできなくなる（フリーズしたように見える）。
- **原因**: IOL上でIPルーティングを完全にオフにしてしまうと、管理用ポート（eth0）も影響を受け、応答できなくなる。
- **回避策**: PCとして使う場合でも `no ip routing` は設定せず、デフォルトルートをスタティックに設定する（`ip route 0.0.0.0 0.0.0.0 <ゲートウェイIP>`）ことで、ルーター化を防ぎつつ管理アクセスを維持できる。

---
*Good Luck! ぜひ一からの構築にチャレンジしてみてください！*
