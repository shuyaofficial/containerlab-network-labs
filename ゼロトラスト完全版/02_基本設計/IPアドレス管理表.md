---
type: ip-table
theme: "ゼロトラスト完全版"
status: draft
date: 2026-07-08
tags: [zero-trust, ip-table, virtual-company, vlan, subnet]
title: "ゼロトラスト完全版｜IPアドレス管理表"
---

# ゼロトラスト完全版｜IPアドレス管理表

> **Phase番号（P0-P6）・N番号（N1-N4）・トラック区分は、各部品の出自ラボにおける管理単位として存続する。本書はそれらの到達点を1つの仮想企業LANへ再配置した設計であり、出自ラボ側のドキュメントそのものは変更しない。**

仮想企業（1拠点・従業員約100名）の社内LANを `172.31.0.0/16` に統一し、**第3オクテット＝VLAN ID**とする再マッピング方式でアドレス設計する。実機検証済のIP（31_nac_dot1x の SVI／FreeRADIUS 等）は無変更で採用し、他は全社設計値として新規に採番する。**本表が全社設計値の正**であり、出自ラボ側の管理表は検証時実値の正である（[ZERO_zero_trust IPアドレス管理表](../../ZERO_zero_trust/02_基本設計/IPアドレス管理表.md) 等、出自ラボ側は一切変更しない）。

## 再マッピング方式の判断理由

- 出自ラボは `172.30系`（ZERO_zero_trust）・`172.31系`（31_nac_dot1x/NW-ZT設計）・`172.40系`（42_ndr_flow）・`172.50系`（microseg_nftables）・`10.0.x系`（35_faucet_sdn）とアドレス空間がバラバラで、そのままでは1つの社内LANとして描けない。
- 802.1X動的VLAN（31実証）を全社設計の骨格に採用し、**VLAN ID＝第3オクテット**で統一することで、どのVLANのどのノードかをIPから即座に判別できるようにした（第4オクテット採番規則を参照）。
- 実機検証済のIP（core-sw SVI・FreeRADIUS）は変更コストとエビデンスの一貫性を優先し無変更のまま採用し、他の部品は出自ラボの元アドレスを保持せず全社設計値へ再採番する（部品ごとに元アドレス体系が競合するため）。

## セグメント表（設計値）

| セグメント | VLAN | サブネット | 状態・出自 |
|---|---|---|---|
| コア・認証管理 | VLAN100 | 172.31.0.0/24 | ✅ 31の実IP無変更（core-sw SVI .1／FreeRADIUS .10） |
| 営業 | VLAN10 | 172.31.10.0/24 | ✅ N1が動的割当を実機実証したVLAN10そのもの |
| 開発 | VLAN20 | 172.31.20.0/24 | ◐ 新設 |
| ゲスト | VLAN30 | 172.31.30.0/24 | ◐ 新設 |
| サーバ室 | VLAN50 | 172.31.50.0/24 | ◐ 配置（部品✅: 36/microseg_cilium） |
| DMZ認可層 | VLAN60 | 172.31.60.0/24 | ◐（ziti部品のみ✅） |
| 監視管理SOC | VLAN90 | 172.31.90.0/24 | ◐ 配置（部品✅: 42/35） |
| 隔離 | VLAN99 | 172.31.99.0/24 | ◐（T-N1-7残課題） |
| 外部（インターネット模擬） | — | 172.30.0.0/24 | ✅ 出自ZERO Untrust |
| ZTNA overlay | — | アドレスレス論理網 | ✅ 部品（36） |

## 第4オクテット採番規則

`.1`=GW/SVI、`.10`台=認証・ID系、`.20`台=NW/中継系、`.30`台=検査系、`.40`台=SIEM・証明書系、`.50`台=SOAR/自動化系、`.101〜`=端末。この規則は管理系セグメント（VLAN60/90等）の目安であり、業務VLAN（10/20/30/99）の端末は `.101` 〜から採番する。

## ノード一覧表

| ノード名 | 役割 | 設計IP | セグメント | 状態 | 実装出自 |
|---|---|---|---|---|---|
| core-sw SVI（VLAN100） | コア認証管理セグメントのL3ゲートウェイ | 172.31.0.1 | VLAN100 コア・認証管理 | ✅ | 31_nac_dot1x（interface Vlan100実証）／microseg_nftables（SVI+ACLパターン） |
| radius | FreeRADIUS認証サーバ | 172.31.0.10 | VLAN100 コア・認証管理 | ✅ | 31_nac_dot1x |
| floor-sw1 | アクセス層L2スイッチ（802.1X認証・動的VLAN割当、営業VLAN10/ゲストVLAN30収容） | ―（L2、設計IP対象外） | VLAN10/30/99 直下 | ✅ | 31_nac_dot1x（Cisco IOL L2、pc1のVLAN10動的割当を実証） |
| floor-sw2 | アクセス層L2スイッチ（802.1X認証者、開発VLAN20収容） | ―（L2、設計IP対象外） | VLAN20/99 直下 | ◐ | 新設（31_nac_dot1xのfloor-sw1と同パターン） |
| GW（VLAN10） | 営業セグメントL3ゲートウェイ | 172.31.10.1 | VLAN10 営業 | ◐ | 新設（L2動的割当はfloor-sw1で✅実証、L3ゲートウェイ自体は未実施） |
| pc-sales1 | 営業端末（802.1X認証成功端末） | 172.31.10.101 | VLAN10 営業 | ✅（部品） | 31_nac_dot1x（pc1/alice） |
| GW（VLAN20） | 開発セグメントL3ゲートウェイ | 172.31.20.1 | VLAN20 開発 | ◐ | 新設 |
| pc-dev1 | 開発端末 | 172.31.20.101 | VLAN20 開発 | ◐ | 新設 |
| GW（VLAN30） | ゲストセグメントL3ゲートウェイ | 172.31.30.1 | VLAN30 ゲスト | ◐ | 新設 |
| guest-pc1 | ゲスト端末 | 172.31.30.101 | VLAN30 ゲスト | ◐ | 新設 |
| GW（VLAN99） | 隔離セグメントL3ゲートウェイ（remediation用途のみ） | 172.31.99.1 | VLAN99 隔離 | ◐ | 新設（T-N1-7残課題） |
| GW（VLAN50） | サーバ室セグメントL3ゲートウェイ | 172.31.50.1 | VLAN50 サーバ室 | ◐ | 新設 |
| srv-app1 | 保護対象サービス（overlay/IAP経由のみ到達） | 172.31.50.11 | VLAN50 サーバ室 | ✅（部品） | 36_ztna_openziti（dark service）／ZERO_zero_trust（app） |
| k8s-cilium | μセグ対象ワークロード群 | 172.31.50.21〜.29 | VLAN50 サーバ室 | ✅（部品） | microseg_cilium |
| GW（VLAN60） | DMZ認可層L3ゲートウェイ | 172.31.60.1 | VLAN60 DMZ認可層 | ◐ | 新設 |
| keycloak | ID統制（OIDC IdP） | 172.31.60.11 | VLAN60 DMZ認可層 | ◐ | 新設（ZERO Phase1着想） |
| pomerium | IAP（認可ポリシー） | 172.31.60.21 | VLAN60 DMZ認可層 | ◐ | 新設（ZERO Phase2着想） |
| oauth2-proxy | IAP起点（未認証拒否） | 172.31.60.22 | VLAN60 DMZ認可層 | ◐ | 新設（ZERO Phase2着想） |
| ziti-ctrl | SDP-ZTNAコントローラ | 172.31.60.23 | VLAN60 DMZ認可層 | ✅（部品） | 36_ztna_openziti |
| ziti-router | SDP-ZTNAルータ/ブローカー | 172.31.60.24 | VLAN60 DMZ認可層 | ✅（部品） | 36_ztna_openziti |
| mitmproxy | SWG+DLP兼務 | 172.31.60.31 | VLAN60 DMZ認可層 | ◐ | 新設（ZERO Phase4/5着想） |
| step-ca | デバイス統制（mTLS/posture） | 172.31.60.41 | VLAN60 DMZ認可層 | ◐ | 新設（ZERO Phase6着想） |
| GW（VLAN90） | 監視管理SOC L3ゲートウェイ | 172.31.90.1 | VLAN90 監視管理SOC | ◐ | 新設 |
| faucet | SDN宣言型アクセス層コントローラ | 172.31.90.21 | VLAN90 監視管理SOC | ✅（部品） | 35_faucet_sdn |
| suricata | NDRセンサー | 172.31.90.31 | VLAN90 監視管理SOC | ✅（部品） | 42_ndr_flow |
| loki | ログ保存 | 172.31.90.41 | VLAN90 監視管理SOC | ✅（部品）／◐（全社統合） | 42_ndr_flow |
| promtail | ログ収集 | 172.31.90.42 | VLAN90 監視管理SOC | ✅（部品）／◐（全社統合） | 42_ndr_flow |
| grafana | 可視化 | 172.31.90.43 | VLAN90 監視管理SOC | ✅（部品）／◐（全社統合） | 42_ndr_flow |
| soar-lite | 検知→対応の自動化（CoA webhook起点） | 172.31.90.51 | VLAN90 監視管理SOC | ◐ | 新設（発展課題） |
| remote-pc | リモート社員端末（ziti tunneler内蔵） | 172.30.0.11 | 外部（インターネット模擬） | ✅（部品） | ZERO_zero_trust（client）／36_ztna_openziti（clienttun） |
| attacker | 攻撃者/脅威モデル（参考。全社構成には配置しない） | 172.30.0.12 | 外部（インターネット模擬） | 参考 | 42_ndr_flow（attacker）／ZERO_zero_trust（external） |

同じセグメント内でもノード粒度で状態が異なる場合がある（例: VLAN10はfloor-sw1のL2動的割当が✅実証済である一方、GWのL3ゲートウェイは◐新設）。ノード（部品）の状態と接続（統合ポイント、[統合アーキテクチャマップ](統合アーキテクチャマップ.md)参照）の状態は別々に扱う。

## 出自ラボ実IP対応表

| 出自ラボ | ラボ実値 | 全社設計での対応 |
|---|---|---|
| 31_nac_dot1x | SVI 172.31.0.1・FreeRADIUS 172.31.0.10 | **無変更採用**。pc1 → pc-sales1 |
| ZERO_zero_trust | client 172.30.0.11／external 172.30.0.12／app 172.30.20.21 | client → remote-pc、external → attacker（参考）、app → srv-app1 172.31.50.11 |
| 42_ndr_flow | attacker 172.40.0.21／victim 172.40.0.22 | F-Cの感染端末役／被害サーバ役（ラボ実値としてのみ記載。全社設計IPは持たない） |
| microseg_nftables | pc10a 172.50.10.11・pc10b 172.50.10.12・srv20 172.50.20.11 | pc-sales/srv-app相当（ラボ実値としてのみ記載。全社設計IPは持たない） |
| 35_faucet_sdn | 10.0.100.x／10.0.200.x | アクセス層統計の出自（ラボ実値としてのみ記載） |

mgmt網（172.20.20.0/24等、各ラボの containerlab/OrbStack VM 管理ネットワーク）は**ラボ実行基盤であり全社計画の対象外**。

> **注記**: ZERO側の旧NW-ZT論理設計（[NW-ZT_論理構成設計](../../ZERO_zero_trust/02_基本設計/NW-ZT_論理構成設計.md)）は「監視＝172.31.30.0/24」としていたが、全社統合ではVLAN90（172.31.90.0/24）へ再配置する。172.31.30.0/24は本表でゲスト（VLAN30）に割り当てる。**本表が全社設計値の正、出自ラボ側管理表は検証時実値の正**（[NW-ZT_論理構成設計](../../ZERO_zero_trust/02_基本設計/NW-ZT_論理構成設計.md) は変更しない）。

## 参照

- [基本設計書](基本設計書.md)
- [統合アーキテクチャマップ](統合アーキテクチャマップ.md)
- [ZERO_zero_trust IPアドレス管理表](../../ZERO_zero_trust/02_基本設計/IPアドレス管理表.md)
- [NW-ZT_論理構成設計](../../ZERO_zero_trust/02_基本設計/NW-ZT_論理構成設計.md)
- [31_nac_dot1x 試験結果](../../31_nac_dot1x/05_試験/試験結果_2026-07-05.md)
- [42_ndr_flow 試験結果](../../42_ndr_flow/05_試験/試験結果_2026-07-05.md)
- [microseg_nftables 試験結果](../../microseg_nftables/05_試験/試験結果_2026-07-05.md)
- [35_faucet_sdn 試験結果](../../35_faucet_sdn/05_試験/試験結果_2026-07-07.md)
