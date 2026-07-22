---
type: ip-table
theme: "マルチベンダ環境"
status: draft
date: 2026-07-17
tags: [containerlab, ip-address, ip-table, multi-vendor]
title: "IPアドレス管理表: マルチベンダ環境"
---

# IPアドレス管理表: マルチベンダ環境

## 1. 管理サブネット

| 用途 | サブネット | clabネットワーク名 |
|---|---|---|
| containerlab 管理（mgmt） | 172.20.50.0/24 | `mvlab-mgmt` |

## 2. ノード一覧表

| ノード名 | 役割 | mgmt-ipv4 | Loopback | 備考 |
|---|---|---|---|---|
| hq-edge | HQ WANエッジ | 172.20.50.11 | — | RouterOS CHR 7.21.4。Router IDは識別子専用値（§5） |
| hq-core | HQキャンパスコア | 172.20.50.12 | — | Cisco IOL 15.7.3M2。OSPF/eBGP境界 |
| dc-leaf1 | DCリーフ1 | 172.20.50.13 | — | Nokia SR Linux v26.3.3 |
| dc-leaf2 | DCリーフ2 | 172.20.50.14 | — | Nokia SR Linux v26.3.3 |
| hq-sw | HQキャンパススイッチ | 172.20.50.15 | — | Cisco IOL L2-advipservices-2017。VLAN10/20 SVI |
| br-edge | ブランチCPE | 172.20.50.16 | — | OpenWrt 24.10.7（rootfs）。BGP/OSPF不参加 |
| isp-a | ISP1 | 172.20.50.21 | 198.51.100.1/32 | FRR 10.2.1。ループバックはインターネット上のサービス役 |
| isp-b | ISP2 | 172.20.50.22 | 198.51.100.2/32 | FRR 10.2.1。同上 |
| hq-pc1 | HQ端末（VLAN10） | 172.20.50.101 | — | multitool |
| hq-pc2 | HQ端末（VLAN20） | 172.20.50.102 | — | multitool |
| srv-web | DCサーバ（dc-leaf1配下） | 172.20.50.103 | — | multitool |
| srv-db | DCサーバ（dc-leaf2配下） | 172.20.50.104 | — | multitool |
| br-pc | ブランチ端末 | 172.20.50.105 | — | multitool。NAT裏 |

## 3. P2Pリンク一覧（すべて/30）

| リンク | サブネット | Aエンド | Bエンド | プロトコル |
|---|---|---|---|---|
| isp-a ⇔ isp-b | 10.50.255.0/30 | isp-a: .1 | isp-b: .2 | eBGP（AS65001⇔AS65002） |
| isp-a ⇔ hq-edge | 10.50.255.4/30 | isp-a: .5 | hq-edge: .6 | eBGP（AS65001⇔AS65010） |
| isp-b ⇔ hq-edge | 10.50.255.8/30 | isp-b: .9 | hq-edge: .10 | eBGP（AS65002⇔AS65010） |
| isp-b ⇔ br-edge | 10.50.255.12/30 | isp-b: .13 | br-edge: .14 | 静的経路（br-edge→isp-b既定ルート）+ NAT |
| hq-edge ⇔ hq-core | 10.50.255.16/30 | hq-edge: .17 | hq-core: .18 | OSPF area0 |
| hq-core ⇔ dc-leaf1 | 10.50.255.20/30 | hq-core: .21 | dc-leaf1: .22 | eBGP（AS65011⇔AS65021） |
| hq-core ⇔ dc-leaf2 | 10.50.255.24/30 | hq-core: .25 | dc-leaf2: .26 | eBGP（AS65011⇔AS65022） |
| hq-core ⇔ hq-sw | 10.50.255.28/30 | hq-core: .29 | hq-sw: .30 | OSPF area0（ルーテッドリンク、トランクではない） |

> `10.50.255.0/24` はP2Pリンク専用のサブネットプールとして予約する（§5のRouter ID識別子はこのプール外）。

## 4. LANセグメント一覧

| セグメント | サブネット | GW（.1） | 提供機器 | 備考 |
|---|---|---|---|---|
| VLAN10（HQ） | 10.50.10.0/24 | 10.50.10.1 | hq-sw（SVI `interface Vlan10`） | hq-pc1: 10.50.10.101/24 |
| VLAN20（HQ） | 10.50.20.0/24 | 10.50.20.1 | hq-sw（SVI `interface Vlan20`） | hq-pc2: 10.50.20.102/24 |
| DC1（dc-leaf1配下） | 10.50.30.0/24 | 10.50.30.1 | dc-leaf1 | srv-web: 10.50.30.103/24 |
| DC2（dc-leaf2配下） | 10.50.31.0/24 | 10.50.31.1 | dc-leaf2 | srv-db: 10.50.31.104/24 |
| ブランチLAN | 192.168.40.0/24 | 192.168.40.1 | br-edge | br-pc: 192.168.40.100/24（NAT裏、masquerade） |

## 5. Router ID（識別子専用、インターフェース未払い出し）

OSPF/BGPのRouter IDをインターフェース状態に依存させないため、経路上に現れない識別子専用の値を
明示設定する（設計判断の根拠は[基本設計書.md](基本設計書.md)§6）。

| ノード | Router ID | 用途 |
|---|---|---|
| hq-edge | 10.50.255.101 | OSPF（hq-core向け）/ BGP（AS65010） |
| hq-core | 10.50.255.102 | OSPF / BGP（AS65011） |
| hq-sw | 10.50.255.105 | OSPF |
| dc-leaf1 | 10.50.255.103 | BGP（AS65021） |
| dc-leaf2 | 10.50.255.104 | BGP（AS65022） |
| isp-a | 198.51.100.1 | BGP（AS65001）。ループバックをそのまま流用 |
| isp-b | 198.51.100.2 | BGP（AS65002）。同上 |
