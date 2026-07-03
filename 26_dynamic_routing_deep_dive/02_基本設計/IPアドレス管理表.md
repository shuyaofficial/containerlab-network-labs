# IPアドレス管理表

## 1. Loopbackアドレス（Router ID）
| 機器名 | Loopback0 | ルーティング上の役割 |
|---|---|---|
| hq-core | 10.26.255.1/32 | OSPF Router ID, 再配信ポイント |
| hq-dist | 10.26.255.2/32 | EIGRP Router ID |
| hq-dmz | 10.26.255.3/32 | OSPF Router ID |
| br-core | 10.26.255.11/32 | OSPF Router ID |
| br-edge | 10.26.255.12/32 | BGP Router ID |
| hq-edge | 10.26.255.254/32 | BGP Router ID, NAT境界 |
| isp | 10.26.255.100/32 | BGP Router ID |

## 2. 機器間接続（ポイントツーポイント /30）
| セグメント | IPアドレス帯 | 機器A (IP) | 機器B (IP) | プロトコル |
|---|---|---|---|---|
| HQ Core - Dist | 10.26.1.0/30 | hq-core (.1) | hq-dist (.2) | EIGRP |
| HQ Core - Edge | 10.26.1.4/30 | hq-core (.5) | hq-edge (.6) | OSPF |
| HQ Core - DMZ | 10.26.1.8/30 | hq-core (.9) | hq-dmz (.10) | OSPF |
| Branch Edge - Core| 10.26.2.0/30 | br-edge (.1) | br-core (.2) | OSPF |
| HQ Edge - ISP | 198.51.100.0/30 | hq-edge (.1) | isp (.2) | eBGP |
| ISP - Branch Edge | 198.51.100.4/30 | isp (.5) | br-edge (.6) | eBGP |

## 3. エンドポイント（LAN /24）
| ネットワーク | 用途 | デフォルトGW | クライアントIP |
|---|---|---|---|
| 10.26.10.0/24 | HQ Trust (VLAN 10) | hq-dist (.1) | hq-pc (.10) |
| 10.26.20.0/24 | Branch Trust (VLAN 20) | br-core (.1) | br-pc (.10) |
| 10.26.30.0/24 | DMZ (VLAN 30) | hq-dmz (.1) | dmz-srv (.10) |

## 4. 管理ネットワーク（OOB）
| 用途 | サブネット |
|---|---|
| containerlab 管理 | 172.26.26.0/24 |
