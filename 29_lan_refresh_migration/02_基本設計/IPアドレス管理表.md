# IPアドレス管理表（IPAM）— テーマ29: 社内LAN更改・移行・移設

本ドキュメントはアドレス割り当ての**正本**です。構成図・パラメータシートと食い違いが出た場合はこの表を優先し、表側を直す場合は構成図も同時に更新します。

移行元（テーマ28）のアドレス設計をそのまま引き継ぎつつ、新設する新環境（new-core1/new-core2/new-rt）のアドレス（10.29系）を追加しています。ユーザーセグメント・機器管理セグメントのネットワークアドレス・GWアドレスは**移行前後で変更しません**（IP温存）。

## 1. アドレスプール全体ルール
| プール | 範囲 | 用途 | 備考 |
|---|---|---|---|
| 業務セグメント | `10.28.10.0/24`〜`10.28.30.0/24` | 営業部(VLAN10)・総務部(VLAN20)・サーバ(VLAN30) | **温存**。ネットワークアドレス・GWアドレスとも移行前後で不変 |
| 機器管理 | `10.28.90.0/24` | 全機器のin-band機器管理(VLAN90) | **温存**。GWのみold-core→new-coreへ移行 |
| 監視セグメント | `10.28.100.0/24` | 監視サーバ(nms)収容(VLAN100) | **温存**。mon-core配下、変更なし |
| 監視系transit | `10.28.0.0/29` | old-core⇔cap-sw⇔mon-core(VLAN900) | **温存**。old-core撤去後は使用停止（cap-sw⇔mon-core間の接続自体は残置） |
| WAN transit（旧） | `10.28.1.0/30` | old-rt⇔old-core(VLAN901) | **温存**。old-rt/old-core撤去まで使用、以後未使用 |
| 疑似インターネット（旧） | `203.0.113.1/32` | old-rt Loopback0 | **温存**。old-rt撤去まで使用 |
| **WAN transit（新・new-rt⇔new-core1）** | **`10.29.1.0/30`** | **new-rt⇔new-core1** | **新設** |
| **WAN transit（新・new-rt⇔new-core2）** | **`10.29.2.0/30`** | **new-rt⇔new-core2** | **新設** |
| **監視拡張transit（新）** | **`10.29.0.0/30`** | **mon-core⇔new-core1（ルーテッド）** | **新設**。監視戻り経路（10.28.100.0/24）の中継に使用 |
| **疑似インターネット（新）** | **`203.0.113.2/32`** | **new-rt Loopback0** | **新設** |
| containerlab管理(OOB) | `172.29.29.0/24` | 全ノードのmgmt IP | prefix `clab-lan-refresh-lab-`。テーマ28（172.28.28.0/24）とは別サブネットに採番し直し |

## 2. セグメント（VLAN）一覧
| セグメント名 | ネットワーク | CIDR | VLAN ID | 移行前GW | 移行後GW | 備考 |
|---|---|---|---|---|---|---|
| 営業部 | 10.28.10.0 | /24 | 10 | old-core (.1) | HSRP VIP (.1)＝new-core1/2 | old-sw1収容。GWアドレスは`.1`のまま不変 |
| 総務部 | 10.28.20.0 | /24 | 20 | old-core (.1) | HSRP VIP (.1)＝new-core1/2 | 移行後はold-sw2のみに収容（L2延伸を解消、pc-b移設） |
| サーバ | 10.28.30.0 | /24 | 30 | old-core (.1) | HSRP VIP (.1)＝new-core1/2 | old-sw2収容 |
| 機器管理 | 10.28.90.0 | /24 | 90 | old-core (.1) | HSRP VIP (.1)＝new-core1/2 | old-sw1(.13)/old-sw2(.14)は`ip default-gateway`運用のまま |
| 監視 | 10.28.100.0 | /24 | 100 | mon-core (.1) | mon-core (.1、変更なし) | nms収容。移行対象外 |
| 監視系transit | 10.28.0.0 | /29 | 900 | — | — | old-core(.1)/mon-core(.2)/cap-sw(.3)。old-core撤去後、old-core側は使用停止 |
| WAN transit（旧） | 10.28.1.0 | /30 | 901 | — | — | old-rt(.1)/old-core(.2)。old-rt/old-core撤去まで使用 |
| WAN transit（新・new-core1側） | 10.29.1.0 | /30 | — | — | — | new-rt(.1)/new-core1(.2、ルーテッド）。VLAN未割当（P2P） |
| WAN transit（新・new-core2側） | 10.29.2.0 | /30 | — | — | — | new-rt(.1)/new-core2(.2、ルーテッド）。VLAN未割当（P2P） |
| 監視拡張transit（新） | 10.29.0.0 | /30 | — | — | — | mon-core(.1)/new-core1(.2、いずれもルーテッド）。VLAN未割当（P2P） |

## 3. WAN・P2Pリンク
| リンクID | サブネット | A側（IP） | B側（IP） | 備考 |
|---|---|---|---|---|
| L01 | 10.28.1.0/30 | old-rt Eth0/1 (.1、ルーテッド) | old-core VLAN901 SVI (.2) | 旧WAN。old-rt/old-core撤去まで使用 |
| L02 | 10.29.1.0/30 | new-rt Eth0/1 (.1、ルーテッド) | new-core1 Eth1/0 (.2、ルーテッド) | 新WAN（new-core1側）。OSPF area 0 |
| L03 | 10.29.2.0/30 | new-rt Eth0/2 (.1、ルーテッド) | new-core2 Eth1/0 (.2、ルーテッド) | 新WAN（new-core2側）。OSPF area 0 |
| L04 | 10.29.0.0/30 | mon-core Eth0/3 (.1、ルーテッド) | new-core1 Eth1/1 (.2、ルーテッド) | 監視拡張transit。OSPF未参加、static+redistributeで到達性確保 |
| L05 | ― | new-core1 Eth0/1（トランク VLAN10,20,30,90） | new-core2 Eth0/1（トランク VLAN10,20,30,90） | 新コア間トランク |

## 4. 機器ごとのIPアドレス割り当て表

> IOLの `ethN`（clab.yml）⇔ IOS上のIF名: eth1=Ethernet0/1, eth2=Ethernet0/2, eth3=Ethernet0/3, eth4=Ethernet1/0, eth5=Ethernet1/1

### old-rt（老朽WANルータ・移行完了後に撤去）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | 10.28.1.1/30（ルーテッド） | old-core | WAN transit(VLAN901)。P8で撤去 |
| Loopback0 | 203.0.113.1/32 | — | 疑似インターネット（旧）。P8で撤去 |
| mgmt | 172.29.29.11 | — | OOB(containerlab) |

### old-core（単一コアL3SW・SPOF、移行完了後に撤去）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | アクセス VLAN901 | old-rt | WAN transit |
| eth2 (E0/2) | トランク（VLAN10,20,90） | old-sw1 | |
| eth3 (E0/3) | トランク（VLAN20,30,90） | old-sw2 | |
| eth4 (E1/0) | アクセス VLAN900 | cap-sw | 監視系transit |
| SVI VLAN10 | 10.28.10.1/24 | — | 営業部GW。P2でshutdown |
| SVI VLAN20 | 10.28.20.1/24 | — | 総務部GW。P4でshutdown |
| SVI VLAN30 | 10.28.30.1/24 | — | サーバGW。P5でshutdown |
| SVI VLAN90 | 10.28.90.1/24 | — | 機器管理GW。P6でshutdown |
| SVI VLAN900 | 10.28.0.1/29 | — | 監視系transit |
| SVI VLAN901 | 10.28.1.2/30 | old-rt | WAN transit |
| mgmt | 172.29.29.12 | — | OOB(containerlab)。P8で撤去 |

### old-sw1（フロアA L2SW・存置）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | トランク（VLAN10,20,90） | old-core | 既存。変更なし |
| eth2 (E0/2) | アクセス VLAN10 | pc-a | 既存 |
| eth3 (E0/3) | アクセス VLAN20 | pc-b | 既存。P7でshutdown（pc-b移設に伴い不要化） |
| eth4 (E1/0) | トランク（VLAN10,20,30,90） | new-core1 | **新設**。P1まで shutdown |
| eth5 (E1/1) | トランク（VLAN10,20,30,90） | new-core2 | **新設**。P1まで shutdown |
| SVI VLAN90 | 10.28.90.13/24 | — | `ip default-gateway 10.28.90.1`（P6以降もアドレス・default-gateway設定文自体は不変。GWの実体のみnew-coreへ移行） |
| mgmt | 172.29.29.13 | — | OOB(containerlab) |

### old-sw2（フロアB L2SW・存置。VLAN20整理後の総務部集約先）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | トランク（VLAN20,30,90） | old-core | 既存。変更なし |
| eth2 (E0/2) | アクセス VLAN30 | srv-file | 既存 |
| eth3 (E0/3) | トランク（VLAN10,20,30,90） | new-core1 | **新設**。P1まで shutdown |
| eth4 (E1/0) | トランク（VLAN10,20,30,90） | new-core2 | **新設**。P1まで shutdown |
| eth5 (E1/1) | アクセス VLAN20 | pc-b（移設先） | **新設**。P7で`no shutdown`＋`switchport access vlan 20` |
| SVI VLAN90 | 10.28.90.14/24 | — | `ip default-gateway 10.28.90.1`（GWの実体のみnew-coreへ移行） |
| mgmt | 172.29.29.14 | — | OOB(containerlab) |

### mon-core（監視L3SW・存置）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | アクセス VLAN900 | cap-sw | 既存。変更なし |
| eth2 (E0/2) | アクセス VLAN100 | nms | 既存 |
| eth3 (E0/3) | 10.29.0.1/30（ルーテッド） | new-core1 | **新設**。監視拡張transit |
| SVI VLAN900 | 10.28.0.2/29 | — | 既存 |
| SVI VLAN100 | 10.28.100.1/24 | — | 既存 |
| mgmt | 172.29.29.21 | — | OOB(containerlab) |

### cap-sw（Wireshark用SW・SPAN・存置）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | アクセス VLAN900 | old-core | 変更なし。old-core撤去後もリンクは残置 |
| eth2 (E0/2) | アクセス VLAN900 | mon-core | 変更なし |
| eth3 (E0/3) | VLAN無所属（SPAN destination） | cap | 変更なし |
| SVI VLAN900 | 10.28.0.3/29 | — | `ip default-gateway 10.28.0.1` |
| mgmt | 172.29.29.22 | — | OOB(containerlab) |

### new-core1（新コアL3SW・優先系＝HSRP Active／STP root primary）【新設】
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | トランク（VLAN10,20,30,90） | new-core2 | 新コア間トランク |
| eth2 (E0/2) | トランク（VLAN10,20,30,90） | old-sw1 (E1/0) | P1まで shutdown |
| eth3 (E0/3) | トランク（VLAN10,20,30,90） | old-sw2 (E0/3) | P1まで shutdown |
| eth4 (E1/0) | 10.29.1.2/30（ルーテッド） | new-rt | OSPF area 0 |
| eth5 (E1/1) | 10.29.0.2/30（ルーテッド） | mon-core | 監視拡張transit。OSPF未参加 |
| SVI VLAN10 | 10.28.10.2/24 | — | HSRP standby 10、priority 110、preempt。VIP=10.28.10.1。P2まで shutdown |
| SVI VLAN20 | 10.28.20.2/24 | — | HSRP standby 20、priority 110、preempt。VIP=10.28.20.1。P4まで shutdown |
| SVI VLAN30 | 10.28.30.2/24 | — | HSRP standby 30、priority 110、preempt。VIP=10.28.30.1。P5まで shutdown |
| SVI VLAN90 | 10.28.90.2/24 | — | HSRP standby 90、priority 110、preempt。VIP=10.28.90.1。P6まで shutdown |
| mgmt | 172.29.29.31 | — | OOB(containerlab) |

### new-core2（新コアL3SW・予備系＝HSRP Standby／STP root secondary）【新設】
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | トランク（VLAN10,20,30,90） | new-core1 | 新コア間トランク |
| eth2 (E0/2) | トランク（VLAN10,20,30,90） | old-sw1 (E1/1) | P1まで shutdown |
| eth3 (E0/3) | トランク（VLAN10,20,30,90） | old-sw2 (E1/0) | P1まで shutdown |
| eth4 (E1/0) | 10.29.2.2/30（ルーテッド） | new-rt | OSPF area 0 |
| SVI VLAN10 | 10.28.10.3/24 | — | HSRP standby 10、priority 100、preempt。VIP=10.28.10.1。P2まで shutdown |
| SVI VLAN20 | 10.28.20.3/24 | — | HSRP standby 20、priority 100、preempt。VIP=10.28.20.1。P4まで shutdown |
| SVI VLAN30 | 10.28.30.3/24 | — | HSRP standby 30、priority 100、preempt。VIP=10.28.30.1。P5まで shutdown |
| SVI VLAN90 | 10.28.90.3/24 | — | HSRP standby 90、priority 100、preempt。VIP=10.28.90.1。P6まで shutdown |
| mgmt | 172.29.29.32 | — | OOB(containerlab) |

### new-rt（新WANルータ）【新設】
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | 10.29.1.1/30（ルーテッド） | new-core1 | OSPF area 0 |
| eth2 (E0/2) | 10.29.2.1/30（ルーテッド） | new-core2 | OSPF area 0 |
| Loopback0 | 203.0.113.2/32 | — | 疑似インターネット（新）。OSPF area 0で広報、`default-information originate always` |
| mgmt | 172.29.29.33 | — | OOB(containerlab) |

### エンドポイント（Linuxコンテナ・wbitt/network-multitool）
| ノード | IF | IP | GW | 役割 | 備考 |
|---|---|---|---|---|---|
| nms | eth1 | 10.28.100.10/24 | 10.28.100.1 | 監視サーバ | 変更なし |
| cap | eth1 | IPなし（promiscuous） | — | キャプチャホスト（SPAN受け） | 変更なし |
| pc-a | eth1 | 10.28.10.10/24 | 10.28.10.1 | 営業部PC | IPアドレス・GWアドレスとも不変（GWの実体のみ移行） |
| pc-b | eth1 | 10.28.20.10/24 | 10.28.20.1 | 総務部PC（移行前・old-sw1収容） | P7でeth2側へ切替 |
| pc-b | eth2 | 10.28.20.10/24 | 10.28.20.1 | 総務部PC（移設後・old-sw2収容） | **新設**。IPアドレス・GWアドレスは移設前後で不変、収容SWのみold-sw1→old-sw2 |
| srv-file | eth1 | 10.28.30.10/24 | 10.28.30.1 | ファイルサーバ | 変更なし |

## 5. 管理ネットワーク（OOB）
| ノード | mgmt IP |
|---|---|
| old-rt | 172.29.29.11 |
| old-core | 172.29.29.12 |
| old-sw1 | 172.29.29.13 |
| old-sw2 | 172.29.29.14 |
| mon-core | 172.29.29.21 |
| cap-sw | 172.29.29.22 |
| new-core1 | 172.29.29.31 |
| new-core2 | 172.29.29.32 |
| new-rt | 172.29.29.33 |
| nms | 172.29.29.101 |
| cap | 172.29.29.102 |
| pc-a | 172.29.29.103 |
| pc-b | 172.29.29.104 |
| srv-file | 172.29.29.105 |

## 6. 移行前後で変わるもの・変わらないもの
| 項目 | 変わらないもの（IP温存） | 変わるもの |
|---|---|---|
| ユーザーセグメントのネットワークアドレス | 10.28.10.0/24、10.28.20.0/24、10.28.30.0/24 | ― |
| ユーザーセグメントのGWアドレス | `.1`（各VLANとも） | GWの実体（old-core SVI → new-core1/2のHSRP VIP） |
| 機器管理セグメント（VLAN90） | ネットワークアドレス・GWアドレス（10.28.90.1） | GWの実体（old-core SVI → new-core1/2のHSRP VIP） |
| 監視セグメント（VLAN100・900） | ネットワークアドレス・GWアドレスとも不変 | mon-coreのdefault routeの向き先（old-core→new-core1） |
| WANルータのLoopback | ― | 203.0.113.1（old-rt）→ 203.0.113.2（new-rt）に変更（疑似インターネット側のアドレスであり、ユーザーセグメントではないため許容） |
| ルーティング方式 | ― | static → OSPF（area 0）へ変更 |
| containerlab管理(OOB) | ― | 172.28.28.0/24 → 172.29.29.0/24（ラボ環境の管理系であり、業務トラフィックには影響しない） |
| VLAN20の収容 | ネットワークアドレス・GWアドレス | 収容SW（old-sw1・old-sw2の両方 → old-sw2のみ）、pc-bの収容ポート |

> 💡 移行の核心は「ユーザーが認識するアドレス（セグメント・GW）は一切変えず、その実体（どの機器がそのIPを応答するか）だけを入れ替える」という設計にある。これにより端末側の設定変更をゼロにしたまま、コア・WANルータという実体を更改できる。
