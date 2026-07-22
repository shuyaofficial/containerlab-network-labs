---
type: cli-commands
theme: "ゼロトラスト_ネットワーク特化"
status: draft
date: 2026-07-08
tags: [cli-commands, "ゼロトラスト_ネットワーク特化", ios, dot1x, acl]
title: "CLI投入コマンド — ゼロトラスト_ネットワーク特化"
---

# CLI投入コマンド — ゼロトラスト_ネットワーク特化

本テーマは Claude 実装テーマであり（[要件定義書](../01_要件定義/要件定義書.md) 制約）、実際に投入するコマンドを記載する。core-sw への投入は [run_nwzt.exp](../04_構築/run_nwzt.exp) が [core_sw_merged.cfg](../04_構築/core_sw_merged.cfg) を1行ずつ流し込む（`docker attach` の多重起動は禁止のため、1 attach 直列で完結させる）。**本書のコマンドは実ファイルと一致させる**。フェーズ分けは投入順の意図を示すためのもので、実際の投入は expect が一括で行う。

## Phase 1. AAA / RADIUS 基盤

### core-sw
```text
aaa new-model
aaa authentication dot1x default group radius
aaa authorization network default group radius
dot1x system-auth-control
ip routing
radius server RAD
 address ipv4 172.31.0.10 auth-port 1812 acct-port 1813
 key radlab123
 exit
```

---

## Phase 2. VLAN定義

### core-sw
```text
vlan 10
 name SALES
 exit
vlan 20
 name DEV
 exit
vlan 30
 name GUEST
 exit
vlan 50
 name SERVER
 exit
vlan 99
 name QUARANTINE
 exit
vlan 100
 name MGMT
 exit
```

---

## Phase 3. SVI（L3）とACL適用

### core-sw
```text
interface Vlan10
 ip address 172.31.10.1 255.255.255.0
 ip access-group SEG10-OUT in
 no shutdown
 exit
interface Vlan20
 ip address 172.31.20.1 255.255.255.0
 no shutdown
 exit
interface Vlan30
 ip address 172.31.30.1 255.255.255.0
 no shutdown
 exit
interface Vlan50
 ip address 172.31.50.1 255.255.255.0
 no shutdown
 exit
interface Vlan99
 ip address 172.31.99.1 255.255.255.0
 no shutdown
 exit
interface Vlan100
 ip address 172.31.0.1 255.255.255.0
 no shutdown
 exit
ip radius source-interface Vlan100
```

---

## Phase 4. インターフェース（802.1X / アクセスVLAN）

### core-sw
```text
interface Ethernet0/1
 switchport mode access
 authentication port-control auto
 authentication event no-response action authorize vlan 99
 dot1x pae authenticator
 dot1x timeout tx-period 10
 dot1x max-reauth-req 2
 spanning-tree portfast
 exit
interface Ethernet0/2
 switchport mode access
 switchport access vlan 20
 spanning-tree portfast
 exit
interface Ethernet0/3
 switchport mode access
 switchport access vlan 30
 spanning-tree portfast
 exit
interface Ethernet1/0
 switchport mode access
 authentication port-control auto
 authentication event no-response action authorize vlan 99
 dot1x pae authenticator
 dot1x timeout tx-period 10
 dot1x max-reauth-req 2
 spanning-tree portfast
 exit
interface Ethernet1/1
 switchport mode access
 switchport access vlan 100
 exit
interface Ethernet1/2
 switchport mode access
 switchport access vlan 50
 exit
```

---

## Phase 5. inter-VLAN ACL（N4層1）

### core-sw
```text
ip access-list extended SEG10-OUT
 permit tcp 172.31.10.0 0.0.0.255 host 172.31.50.11 eq 80
 permit icmp 172.31.10.0 0.0.0.255 172.31.50.0 0.0.0.255
 deny tcp 172.31.10.0 0.0.0.255 host 172.31.50.11 eq 22
 permit ip any any
 exit
```

---

## Phase 6. 投入後の確認（run_nwzt.exp が自動実行）

```text
write memory
show authentication sessions
show ip interface brief | include Vlan
```

検証専用（設定投入なし）は [verify_nwzt.exp](../04_構築/verify_nwzt.exp) が以下を追加で採取する。

```text
show dot1x all summary
show ip access-lists SEG10-OUT
show vlan brief
```

---

## Phase 7. 運用オーケストレーション（deploy-all.sh）

core-sw以外（N2/N3/N4層2・端末サービス）の投入は [deploy-all.sh](../04_構築/deploy-all.sh) が担う。実行順は以下の通り。

```bash
./deploy-all.sh deploy   # prep_net(nwzt-srv0作成) → clab deploy → iouyap → データプレーン補正
./deploy-all.sh config   # run_nwzt.exp で core_sw_merged.cfg を投入（Phase 1-6）
./deploy-all.sh auth     # pc-sales サプリカント起動 + データIP付与 + srv-app1/host-infected サービス起動
./deploy-all.sh ziti     # N2: ziti/apptun/clienttun 起動 + setup_ziti.sh
./deploy-all.sh ndr      # N3: suricata + loki + promtail + grafana 起動
./deploy-all.sh nft      # N4層2: srv-app1 に host-infected 拒否ルールを投入
./deploy-all.sh scan     # host-infected → srv-app1 へ SYN スキャン（N3トリガ）
./deploy-all.sh eve      # eve.json の alert/flow 抜粋
./deploy-all.sh verify   # B2/B3 の到達性確認
```

## メモ・つまずいた点

- iouyap未起動だとIOLは全断になる（[clab運用規約](../../規約/clab運用規約.md) 6章）。`deploy-all.sh deploy` が自動起動するが、失敗時は `./deploy-all.sh iouyap` で個別再実行する。
- `docker attach` の多重起動はNG。`config_switch()` は投入前後で `pkill -f 'docker attach'` している。
- サーバ室ブリッジ `nwzt-srv0` は `containerlab deploy` より前に存在している必要がある（`kind:bridge` が既存ブリッジを要求するため）。

## 参照

- [パラメータシート.md](パラメータシート.md)
- [04_構築/core_sw_merged.cfg](../04_構築/core_sw_merged.cfg)
- [04_構築/run_nwzt.exp](../04_構築/run_nwzt.exp)
- [04_構築/verify_nwzt.exp](../04_構築/verify_nwzt.exp)
- [04_構築/deploy-all.sh](../04_構築/deploy-all.sh)
