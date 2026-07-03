# IPアドレス管理表

## 1. Loopbackアドレス（Router ID）
| 機器名 | Loopback0 | ルーティング上の役割 |
|---|---|---|
| hq-core | 10.27.255.1/32 | OSPF Router ID |
| hq-dist | 10.27.255.2/32 | OSPF Router ID |
| hq-edge | 10.27.255.254/32 | BGP Router ID, NAT境界 |
| hq-dmz | 10.27.255.3/32 | OSPF Router ID |
| br-core | 10.27.255.11/32 | OSPF Router ID |
| br-edge | 10.27.255.12/32 | BGP Router ID |
| isp | 10.27.255.100/32 | BGP Router ID |

## 2. 機器間接続（ポイントツーポイント /30）
| セグメント | IPアドレス帯 | 機器A (IP) | 機器B (IP) |
|---|---|---|---|
| HQ Core - Dist | 10.27.1.0/30 | hq-core (.1) | hq-dist (.2) |
| HQ Core - Edge | 10.27.1.4/30 | hq-core (.5) | hq-edge (.6) |
| HQ Core - DMZ | 10.27.1.8/30 | hq-core (.9) | hq-dmz (.10) |
| Branch Edge - Core| 10.27.2.0/30 | br-edge (.1) | br-core (.2) |
| HQ Edge - ISP | 198.51.100.8/30 | hq-edge (.9) | isp (.10) |
| ISP - Branch Edge | 198.51.100.12/30 | isp (.13) | br-edge (.14) |

## 3. エンドポイント（LAN /24）
| ネットワーク | 用途 | デフォルトGW | クライアントIP |
|---|---|---|---|
| 10.27.10.0/24 | HQ Trust PC (VLAN 10) | hq-dist (.1) | hq-pc (.10) |
| 10.27.50.0/24 | HQ Trust VoIP (VLAN 50) | hq-dist (.1) | hq-voip (.10) |
| 10.27.20.0/24 | Branch Trust (VLAN 20) | br-core (.1) | br-pc (.10) |
| 10.27.30.0/24 | DMZ Server (VLAN 30) | hq-dmz (.1) | dmz-srv (.10) |

## 4. 管理ネットワーク（OOB）
| 用途 | サブネット |
|---|---|
| containerlab 管理 | 172.27.27.0/24 |
