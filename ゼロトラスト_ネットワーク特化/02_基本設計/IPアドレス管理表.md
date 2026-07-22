---
type: ip-table
theme: "ゼロトラスト_ネットワーク特化"
status: draft
date: 2026-07-08
tags: [zero-trust, ip-table, vlan, subnet, virtual-company]
title: "IPアドレス管理表: ゼロトラスト_ネットワーク特化"
---

# IPアドレス管理表: ゼロトラスト_ネットワーク特化

[ゼロトラスト完全版 IPアドレス管理表](../../ゼロトラスト完全版/02_基本設計/IPアドレス管理表.md) の設計値（`172.31.0.0/16`・第3オクテット＝VLAN ID）を無変更で踏襲する。本表は本テーマの実ファイル（[nwzt.clab.yml](../04_構築/nwzt.clab.yml)・[core_sw_merged.cfg](../04_構築/core_sw_merged.cfg)）と一致する値のみを記載する。

## 1. 管理サブネット

| 用途 | サブネット | 備考 |
|---|---|---|
| containerlab 管理（core-sw / radius / pc-* / srv-app1 / host-infected） | 172.20.40.0/24 | `mgmt.network: clab-nwzt-lan-mgmt`（[nwzt.clab.yml](../04_構築/nwzt.clab.yml)） |
| サーバ室VLAN50実体（docker network `nwzt-srv0`） | 172.31.50.0/24 | GW `.254`（IOL SVI `.1` と非衝突。[deploy-all.sh](../04_構築/deploy-all.sh) `SRV_GW`） |
| N2 ZTNA overlay（docker network `zn-ziti`） | アドレスレス論理網 | ziti / apptun / clienttun が接続 |

## 2. セグメント表

| セグメント | VLAN | サブネット | GW/SVI | 状態 |
|---|---|---|---|---|
| コア・認証管理 | 100 | 172.31.0.0/24 | SVI 172.31.0.1 | core-sw SVI + radius 収容 |
| 営業 | 10 | 172.31.10.0/24 | 172.31.10.1（ACL `SEG10-OUT` 適用） | 802.1X動的割当 |
| 開発 | 20 | 172.31.20.0/24 | 172.31.20.1 | 静的アクセス |
| ゲスト | 30 | 172.31.30.0/24 | 172.31.30.1 | 静的アクセス |
| 隔離 | 99 | 172.31.99.0/24 | 172.31.99.1 | 未認証端末の自動割当先 |
| サーバ室 | 50 | 172.31.50.0/24 | SVI 172.31.50.1（docker bridge `nwzt-srv0` で実体化） | srv-app1 / host-infected 収容 |
| 監視SOC | 90 | 172.31.90.0/24（論理・採番のみ） | ― | suricata/loki/grafana は `--network host` で実質localhost。VLAN90としてのL2/L3実装は持たない |
| 外部 | ― | ― | ― | clienttun（＝リモート社員のziti tunneler。`zn-ziti`上） |
| mgmt基盤 | ― | 172.20.40.0/24 | ― | clab管理網。全社計画外（[出自ラボ実IP対応表](../../ゼロトラスト完全版/02_基本設計/IPアドレス管理表.md)と同様の扱い） |

## 3. 第4オクテット採番規則

`.1`=GW/SVI、`.10`台=認証、`.101〜`=端末。mgmt系は [clab運用規約](../../規約/clab運用規約.md) の慣行に従い個別に採番する（下表参照）。

## 4. ノード一覧表（clabノード）

| ノード名 | 役割 | mgmt-ipv4 | データIP（VLAN） | Loopback | 備考 |
|---|---|---|---|---|---|
| core-sw | 802.1X認証者 + L3 SVI + inter-VLAN ACL | 172.20.40.11 | SVI群（Vlan10=.10.1／Vlan20=.20.1／Vlan30=.30.1／Vlan50=.50.1／Vlan99=.99.1／Vlan100=172.31.0.1） | ― | IOL、単一ノードでN1+N4を兼務 |
| radius | FreeRADIUS認証サーバ | 172.20.40.10 | 172.31.0.10/24（VLAN100） | ― | NAS共有鍵 `radlab123`、UDP1812/1813 |
| pc-sales | 営業端末（802.1X動的割当） | 172.20.40.21 | 172.31.10.101/24（VLAN10、認証成功後に付与） | ― | wpa_supplicant(alice/EAP-MD5) |
| pc-dev | 開発端末（静的） | 172.20.40.22 | 172.31.20.101/24（VLAN20） | ― | clab.yml execで自動設定 |
| guest-pc | ゲスト端末（静的） | 172.20.40.23 | 172.31.30.101/24（VLAN30） | ― | clab.yml execで自動設定 |
| pc-unauth | 未認証端末 | 172.20.40.24 | 割当なし（no-response→隔離VLAN99） | ― | サプリカント未起動 |
| nwzt-srv0 | サーバ室VLAN50実体ブリッジ | ―（clabの`kind:bridge`、mgmt対象外） | 172.31.50.0/24（GW .254） | ― | `deploy-all.sh prep_net` が事前作成 |
| srv-app1 | 保護対象サーバ（http/80・疑似ssh/22） | 172.20.40.31 | 172.31.50.11/24（VLAN50） | ― | N2ダークサービス対象・N4層2 nft遮断対象 |
| host-infected | 感染端末役（東西スキャン源） | 172.20.40.32 | 172.31.50.31/24（VLAN50） | ― | nmap同梱（wbitt/network-multitool） |

## 5. ノード一覧表（docker併走・clab管理外）

| ノード名 | 役割 | 接続ネットワーク | IP | 備考 |
|---|---|---|---|---|
| ziti | N2 ZTNAコントローラ+ルータ | zn-ziti | 論理（ziti overlay） | `openziti/ziti-cli:latest`、edge quickstart |
| apptun | app側tunneler（srv-app1をdial） | zn-ziti + nwzt-srv0 | 172.31.50.50（`APPTUN_IP`固定） | サーバ室ブリッジに後付け接続 |
| clienttun | client側tunneler（＝リモート社員端末） | zn-zitiのみ | 論理（zn-ziti上） | srv-app1へ直接到達不可（overlay経由のみ） |
| suricata | NDRセンサー | `--network host`、`-i nwzt-srv0` | ホスト実IP準拠 | HOME_NET=172.31.50.0/24 |
| loki | ログ保存 | ブリッジ + `-p 3100:3100` | ホスト:3100 | ― |
| promtail | ログ収集 | `--network host` | ホスト実IP準拠 | eve.jsonをtail |
| grafana | 可視化 | `--network host` | ホスト:3000 | 匿名Admin有効（ラボ用途） |

## 参照

- [基本設計書](基本設計書.md)
- [ネットワーク物理構成図](ネットワーク物理構成図.mermaid)
- [ゼロトラスト完全版 IPアドレス管理表](../../ゼロトラスト完全版/02_基本設計/IPアドレス管理表.md)
- [04_構築/nwzt.clab.yml](../04_構築/nwzt.clab.yml)
- [04_構築/core_sw_merged.cfg](../04_構築/core_sw_merged.cfg)
- [04_構築/deploy-all.sh](../04_構築/deploy-all.sh)
