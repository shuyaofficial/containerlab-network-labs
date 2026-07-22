# CLI投入コマンド — Phase 1（Loopback0）+ Phase 2（物理IF）

> [パラメータシート_設定順.md](パラメータシート_設定順.md) の Phase 1・2 を、機器ごとに**コピー&ペーストでそのまま投入できる形**にしたもの。
> 値の正本は [IPアドレス管理表](../02_基本設計/IPアドレス管理表.md) と一致。
> **ルーティング（Phase 3 以降）は含まない**（学習者が構成する）。
>
> 投入方法: `sudo docker attach --sig-proxy=false clab-qos-acl-policy-lab-<ノード名>` で接続し、
> ブロックごと貼り付け（離脱は `Ctrl-p` → `Ctrl-q`）。初回は `System Configuration Dialog` に `no` を答えてから投入する。

---

## hq-core

```text
enable
configure terminal
hostname hq-core
no ip domain-lookup
interface Loopback0
 description Router-ID
 ip address 10.27.255.1 255.255.255.255
interface Ethernet0/1
 description to hq-dist E0/1
 ip address 10.27.1.1 255.255.255.252
 no shutdown
interface Ethernet0/2
 description to hq-edge E0/1
 ip address 10.27.1.5 255.255.255.252
 no shutdown
interface Ethernet0/3
 description to hq-dmz E0/1
 ip address 10.27.1.9 255.255.255.252
 no shutdown
end
```

## hq-dist

```text
enable
configure terminal
hostname hq-dist
no ip domain-lookup
interface Loopback0
 description Router-ID
 ip address 10.27.255.2 255.255.255.255
interface Ethernet0/1
 description to hq-core E0/1
 ip address 10.27.1.2 255.255.255.252
 no shutdown
interface Ethernet0/2
 description to hq-pc eth1 (VLAN10)
 ip address 10.27.10.1 255.255.255.0
 no shutdown
interface Ethernet0/3
 description to hq-voip eth1 (VLAN50)
 ip address 10.27.50.1 255.255.255.0
 no shutdown
end
```

## hq-edge

```text
enable
configure terminal
hostname hq-edge
no ip domain-lookup
interface Loopback0
 description Router-ID
 ip address 10.27.255.254 255.255.255.255
interface Ethernet0/1
 description to hq-core E0/2
 ip address 10.27.1.6 255.255.255.252
 no shutdown
interface Ethernet0/2
 description to isp E0/1 (WAN)
 ip address 198.51.100.9 255.255.255.252
 no shutdown
end
```

## hq-dmz

```text
enable
configure terminal
hostname hq-dmz
no ip domain-lookup
interface Loopback0
 description Router-ID
 ip address 10.27.255.3 255.255.255.255
interface Ethernet0/1
 description to hq-core E0/3
 ip address 10.27.1.10 255.255.255.252
 no shutdown
interface Ethernet0/2
 description to dmz-srv eth1 (VLAN30)
 ip address 10.27.30.1 255.255.255.0
 no shutdown
end
```

## br-core

```text
enable
configure terminal
hostname br-core
no ip domain-lookup
interface Loopback0
 description Router-ID
 ip address 10.27.255.11 255.255.255.255
interface Ethernet0/1
 description to br-edge E0/2
 ip address 10.27.2.2 255.255.255.252
 no shutdown
interface Ethernet0/2
 description to br-pc eth1 (VLAN20)
 ip address 10.27.20.1 255.255.255.0
 no shutdown
end
```

## br-edge

```text
enable
configure terminal
hostname br-edge
no ip domain-lookup
interface Loopback0
 description Router-ID
 ip address 10.27.255.12 255.255.255.255
interface Ethernet0/1
 description to isp E0/2 (WAN)
 ip address 198.51.100.14 255.255.255.252
 no shutdown
interface Ethernet0/2
 description to br-core E0/1
 ip address 10.27.2.1 255.255.255.252
 no shutdown
end
```

## isp

```text
enable
configure terminal
hostname isp
no ip domain-lookup
interface Loopback0
 description Router-ID
 ip address 10.27.255.100 255.255.255.255
interface Ethernet0/1
 description to hq-edge E0/2 (WAN)
 ip address 198.51.100.10 255.255.255.252
 no shutdown
interface Ethernet0/2
 description to br-edge E0/1 (WAN)
 ip address 198.51.100.13 255.255.255.252
 no shutdown
end
```

---

## 投入後の確認（各機器）

```text
show ip interface brief
```

期待: 設定した Loopback0 / Ethernet が `up/up`（対向未設定のIFは対向投入後に up）。

隣接リンクの対向IPへ ping が通れば Phase 2 完了（例: hq-core から）:

```text
ping 10.27.1.2
ping 10.27.1.6
ping 10.27.1.10
```

> 注意: この時点では **ルーティング未設定のため、直結セグメント以外へは届かない**のが正常。
> 続きは [パラメータシート_設定順.md](パラメータシート_設定順.md) Phase 3（OSPF）へ。
> 設定を残す場合は各機器で `write memory` を忘れずに。
