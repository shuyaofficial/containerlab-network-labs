# CLI投入コマンド（コピー＆ペースト用）

本ファイルは、`パラメータシート_設定順.md` のフェーズに沿って、各機器のコンソールにそのままペーストして実行できるCLIコマンドをまとめたものです。

## Phase 1. Loopback0 を最初に作る（全7台）

### hq-core
```text
en
conf t
interface Loopback0
 ip address 10.26.255.1 255.255.255.255
 no shutdown
exit
```

### hq-dist
```text
en
conf t
interface Loopback0
 ip address 10.26.255.2 255.255.255.255
 no shutdown
exit
```

### hq-edge
```text
en
conf t
interface Loopback0
 ip address 10.26.255.254 255.255.255.255
 no shutdown
exit
```

### hq-dmz
```text
en
conf t
interface Loopback0
 ip address 10.26.255.3 255.255.255.255
 no shutdown
exit
```

### isp
```text
en
conf t
interface Loopback0
 ip address 10.26.255.100 255.255.255.255
 no shutdown
exit
```

### br-edge
```text
en
conf t
interface Loopback0
 ip address 10.26.255.12 255.255.255.255
 no shutdown
exit
```

### br-core
```text
en
conf t
interface Loopback0
 ip address 10.26.255.11 255.255.255.255
 no shutdown
exit
```

---

## Phase 2. 物理IFのIPを設定（全7台）

### hq-core
```text
en
conf t
interface Ethernet0/1
 ip address 10.26.1.1 255.255.255.252
 no shutdown
exit
interface Ethernet0/2
 ip address 10.26.1.5 255.255.255.252
 no shutdown
exit
interface Ethernet0/3
 ip address 10.26.1.9 255.255.255.252
 no shutdown
exit
```

### hq-dist
```text
en
conf t
interface Ethernet0/1
 ip address 10.26.1.2 255.255.255.252
 no shutdown
exit
interface Ethernet0/2
 ip address 10.26.10.1 255.255.255.0
 no shutdown
exit
```

### hq-edge
```text
en
conf t
interface Ethernet0/1
 ip address 10.26.1.6 255.255.255.252
 no shutdown
exit
interface Ethernet0/2
 ip address 198.51.100.1 255.255.255.252
 no shutdown
exit
```

### hq-dmz
```text
en
conf t
interface Ethernet0/1
 ip address 10.26.1.10 255.255.255.252
 no shutdown
exit
interface Ethernet0/2
 ip address 10.26.30.1 255.255.255.0
 no shutdown
exit
```

### isp
```text
en
conf t
interface Ethernet0/1
 ip address 198.51.100.2 255.255.255.252
 no shutdown
exit
interface Ethernet0/2
 ip address 198.51.100.5 255.255.255.252
 no shutdown
exit
```

### br-edge
```text
en
conf t
interface Ethernet0/1
 ip address 198.51.100.6 255.255.255.252
 no shutdown
exit
interface Ethernet0/2
 ip address 10.26.2.1 255.255.255.252
 no shutdown
exit
```

### br-core
```text
en
conf t
interface Ethernet0/1
 ip address 10.26.2.2 255.255.255.252
 no shutdown
exit
interface Ethernet0/2
 ip address 10.26.20.1 255.255.255.0
 no shutdown
exit
```

---
※ 以降のフェーズ（ルーティング設定など）は、学習の目的上、手動での構築を推奨しています。
