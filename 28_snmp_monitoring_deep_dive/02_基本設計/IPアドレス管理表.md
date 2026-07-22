# IPアドレス管理表（IPAM）— テーマ28: 監視基盤とSNMP深堀り

本ドキュメントはアドレス割り当ての**正本**です。構成図・パラメータシートと食い違いが出た場合はこの表を優先し、表側を直す場合は構成図も同時に更新します。

## 1. アドレスプール全体ルール
| プール | 範囲 | 用途 | 備考 |
|---|---|---|---|
| 業務セグメント | `10.28.10.0/24`〜`10.28.30.0/24` | 営業部(VLAN10)・総務部(VLAN20)・サーバ(VLAN30) | 老朽LAN側、既存構成のまま |
| 機器管理 | `10.28.90.0/24` | 全機器のin-band機器管理(VLAN90) | old-core/old-sw1/old-sw2のSVI |
| 監視セグメント | `10.28.100.0/24` | 監視サーバ(nms)収容(VLAN100) | mon-core配下 |
| 監視系transit | `10.28.0.0/29` | old-core⇔cap-sw⇔mon-core(VLAN900) | インラインのcap-swにもIPを割り当てるため/29 |
| WAN transit | `10.28.1.0/30` | old-rt⇔old-core(VLAN901) | 老朽LAN側、既存 |
| 疑似インターネット | `203.0.113.1/32` | old-rt Loopback0 | RFC5737 TEST-NET-3 |
| containerlab管理(OOB) | `172.28.28.0/24` | 全ノードのmgmt IP | prefix `clab-snmp-monitoring-lab-` |

## 2. セグメント（VLAN）一覧
| セグメント名 | ネットワーク | CIDR | VLAN ID | デフォルトGW | 備考 |
|---|---|---|---|---|---|
| 営業部 | 10.28.10.0 | /24 | 10 | old-core (.1) | old-sw1収容 |
| 総務部 | 10.28.20.0 | /24 | 20 | old-core (.1) | old-sw1・old-sw2の両方に跨るL2延伸＝老朽ポイント |
| サーバ | 10.28.30.0 | /24 | 30 | old-core (.1) | old-sw2収容 |
| 機器管理 | 10.28.90.0 | /24 | 90 | — | old-core(.1)/old-sw1(.13)/old-sw2(.14)にSVI。old-sw1/2は`ip default-gateway`運用 |
| 監視 | 10.28.100.0 | /24 | 100 | mon-core (.1) | nms・zbx-srv収容 |
| 監視系transit | 10.28.0.0 | /29 | 900 | — | old-core(.1)/mon-core(.2)/cap-sw(.3)。インラインcap-swの管理用に/29 |
| WAN transit | 10.28.1.0 | /30 | 901 | — | old-rt(.1)/old-core(.2、VLAN901 SVI) |

## 3. WAN・P2Pリンク
| リンクID | サブネット | A側（IP） | B側（IP） | 備考 |
|---|---|---|---|---|
| L01 | 10.28.1.0/30 | old-rt Eth0/1 (.1、ルーテッド) | old-core VLAN901 SVI (.2) | old-core側の物理IFはVLAN901アクセスポート（SVIでルーティング） |

## 4. 機器ごとのIPアドレス割り当て表

> IOLの `ethN`（clab.yml）⇔ IOS上のIF名: eth1=Ethernet0/1, eth2=Ethernet0/2, eth3=Ethernet0/3, eth4=Ethernet1/0

### old-rt（老朽WANルータ・ルーテッドのみ）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | 10.28.1.1/30（ルーテッド） | old-core | WAN transit(VLAN901) |
| Loopback0 | 203.0.113.1/32 | — | 疑似インターネット |
| mgmt | 172.28.28.11 | — | OOB(containerlab) |

### old-core（単一コアL3SW・SPOF）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | アクセス VLAN901 | old-rt | WAN transit。ルーティングはVLAN901 SVIで実施 |
| eth2 (E0/2) | トランク（VLAN10,20,90） | old-sw1 | |
| eth3 (E0/3) | トランク（VLAN20,30,90） | old-sw2 | |
| eth4 (E1/0) | アクセス VLAN900 | cap-sw | 監視系transit |
| SVI VLAN10 | 10.28.10.1/24 | — | 営業部GW |
| SVI VLAN20 | 10.28.20.1/24 | — | 総務部GW |
| SVI VLAN30 | 10.28.30.1/24 | — | サーバGW |
| SVI VLAN90 | 10.28.90.1/24 | — | 機器管理 |
| SVI VLAN900 | 10.28.0.1/29 | — | 監視系transit |
| SVI VLAN901 | 10.28.1.2/30 | old-rt | WAN transit |
| mgmt | 172.28.28.12 | — | OOB(containerlab) |

### old-sw1（フロアA L2SW）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | トランク（VLAN10,20,90） | old-core | |
| eth2 (E0/2) | アクセス VLAN10 | pc-a | |
| eth3 (E0/3) | アクセス VLAN20 | pc-b | |
| SVI VLAN90 | 10.28.90.13/24 | — | `ip default-gateway 10.28.90.1` |
| mgmt | 172.28.28.13 | — | OOB(containerlab) |

### old-sw2（フロアB L2SW）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | トランク（VLAN20,30,90） | old-core | |
| eth2 (E0/2) | アクセス VLAN30 | srv-file | |
| SVI VLAN90 | 10.28.90.14/24 | — | `ip default-gateway 10.28.90.1` |
| mgmt | 172.28.28.14 | — | OOB(containerlab) |

### mon-core（監視L3SW）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | アクセス VLAN900 | cap-sw | 監視系transit |
| eth2 (E0/2) | アクセス VLAN100 | nms | |
| SVI VLAN900 | 10.28.0.2/29 | — | 監視系transit |
| SVI VLAN100 | 10.28.100.1/24 | — | 監視セグメントGW |
| mgmt | 172.28.28.21 | — | OOB(containerlab) |

### cap-sw（Wireshark用SW・SPAN）
| IF（clab） | IP / モード | 接続先 | 備考 |
|---|---|---|---|
| eth1 (E0/1) | アクセス VLAN900 | old-core | インライン挿入点（SPAN source） |
| eth2 (E0/2) | アクセス VLAN900 | mon-core | インライン挿入点 |
| eth3 (E0/3) | VLAN無所属（SPAN destination） | cap | `monitor session`の宛先ポート |
| SVI VLAN900 | 10.28.0.3/29 | — | `ip default-gateway 10.28.0.1` |
| mgmt | 172.28.28.22 | — | OOB(containerlab) |

### エンドポイント（Linuxコンテナ・wbitt/network-multitool）
| ノード | IF | IP | GW | 役割 |
|---|---|---|---|---|
| nms | eth1 | 10.28.100.10/24 | 10.28.100.1 | 監視サーバ |
| cap | eth1 | IPなし（promiscuous） | — | キャプチャホスト（SPAN受け） |
| pc-a | eth1 | 10.28.10.10/24 | 10.28.10.1 | 営業部PC |
| pc-b | eth1 | 10.28.20.10/24 | 10.28.20.1 | 総務部PC |
| srv-file | eth1 | 10.28.30.10/24 | 10.28.30.1 | ファイルサーバ |
| zbx-srv | eth1 | 10.28.100.20/24 | なし（`10.28.0.0/16 via 10.28.100.1`の個別経路のみ） | Zabbix Server（in-bandポーリング） |

> 💡 zbx-db・zbx-webはデータプレーンIPを持たない（mgmt IPのみ、下記§5参照）。zbx-srvもmgmt IPと合わせて2枚持ち（mgmt=eth0、データプレーン=eth1）で、eth1のIP/経路は`deploy.sh`の`zbx_net()`が投入する（zabbixイメージが非rootのためclab execでは不可）。

## 5. 管理ネットワーク（OOB）
| ノード | mgmt IP |
|---|---|
| old-rt | 172.28.28.11 |
| old-core | 172.28.28.12 |
| old-sw1 | 172.28.28.13 |
| old-sw2 | 172.28.28.14 |
| mon-core | 172.28.28.21 |
| cap-sw | 172.28.28.22 |
| nms | 172.28.28.101 |
| cap | 172.28.28.102 |
| pc-a | 172.28.28.103 |
| pc-b | 172.28.28.104 |
| srv-file | 172.28.28.105 |
| zbx-db | 172.28.28.111 |
| zbx-srv | 172.28.28.112 |
| zbx-web | 172.28.28.113 |

> 💡 **VLAN900が/29である理由**: old-core⇔mon-core間の監視系transitはP2Pなら/30で足りるが、cap-swがこの区間にインラインで挿入され、cap-sw自身もin-band管理IP（.3）を持つ必要があるため、3ホスト分（old-core=.1、mon-core=.2、cap-sw=.3）を収容できる/29（利用可能ホスト6個）を採用している。
