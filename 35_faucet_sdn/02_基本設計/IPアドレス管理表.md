---
type: ip-table
theme: "35_faucet_sdn"
status: draft
date: 2026-07-07
tags: [sdn, openflow, faucet, ip-table]
title: "IPアドレス管理表: Faucet SDN"
---

# IPアドレス管理表: Faucet SDN

## 1. 管理サブネット

| 用途 | サブネット |
|---|---|
| containerlab 管理（mgmt） | 172.35.35.0/24 |

## 2. ノード一覧表

| ノード名 | 役割 | mgmt-ipv4 | データ面IP | 備考 |
|---|---|---|---|---|
| faucet | OpenFlowコントローラ | 172.35.35.11 | — | OpenFlow待受 TCP 6653（mgmt経由） |
| ovs1 | OpenFlowスイッチ（データパス、br0） | 172.35.35.21 | — | datapath-id=0x1（bootstrap.shで固定）。eth1/eth2/eth3がデータ面ポート |
| pc-a | エンドポイント | 172.35.35.101 | 10.0.100.11/24 | VLAN100想定（faucet.yamlで確定） |
| pc-b | エンドポイント | 172.35.35.102 | 10.0.100.12/24 | VLAN100想定（faucet.yamlで確定） |
| pc-c | エンドポイント | 172.35.35.103 | 10.0.200.13/24 | VLAN200想定（faucet.yamlで確定） |

- mgmt-ipv4 は [clab運用規約.md](../../規約/clab運用規約.md) §4に従い、router系相当の `faucet` を `.11`、core系相当の `ovs1` を `.21`、エンドポイントを `.101`〜 で採番している。
- データ面IPのVLAN所属（100/200）は「設計上の狙い」であり、実際にどのVLANに割り当てられるかは `faucet.yaml`（学習者が作成）の内容で決まる。
