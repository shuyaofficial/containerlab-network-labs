# 【解決】FortiGate→Cisco 置換でサイト間VPN(T-105)開通 — 2026-06-26

> 前提の未解決記録: `fortigate_cisco_ipsec_transit_unresolved_2026-06-26.md`（FortiFirewall-VM invalid license で復号後forwardをpre-policy破棄）。
> 本書はその対策＝**fgt-edge を Cisco IOL ルーターに置換して T-105 を通した**実施記録。

## 結論

- **T-105 成功**: `br-pc(10.2.40.100) → srv-portal(10.20.30.20)` **ping 4/4・HTTP 200**、`→ 10.20.30.254` 3/3。
- **VPN**: IKEv2 **READY**（DES/SHA256/DH14/PSK）、Tunnel1 UP-ACTIVE、br-edge crypto enc'ed/dec'ed カウンタ増加＝**ESP暗号化動作**（T-602相当）。
- FortiGate特有の「policy無いとIKE拒否」「invalid licenseで復号後forward破棄」は、**Ciscoルーターでは発生しない**（復号後は素直にルーティング）。置換が正解だった。

## やったこと（手順）

1. `campus.clab.yml` の `fgt-edge` を `fortinet_fortigate/vr-fortios:7.4.2.F` → `cisco_iol/L2-advipservices-2017`(type: l2) に変更（`env QEMU_CPU` 削除）。リンク3本(eth1↔isp / eth2↔core1 / eth3↔core2)は不変。
2. 全IOLノードを `write memory` → 退避（`config_commands/_live_backup_2026-06-26/*.txt`）。
3. clabは**1ノードだけの差し替え不可**（`deploy`/`--node-filter` とも "already deployed" で拒否）→ `destroy --cleanup` + `deploy` のクリーン再構築。
4. 各IOLへ退避configを再投入（mgmt VRF/E0/0/username行は除外して貼付）。
5. **HQ Cisco edge(fgt-edge)** を br-edge の VTI 鏡写し＋campus側で設定（下記）。
6. 検証 → 残課題を順次修正 → T-105 開通。

### HQ edge(fgt-edge) のキモ（br-edgeの鏡写し）
- IF: E0/1=200.0.1.1/24(WAN,FGT port2継承) / E0/2=10.0.1.30/30(core1) / E0/3=10.0.1.34/30(core2、両者 `ip ospf network point-to-point`)
- IKEv2: proposal des/sha256/group14、keyring peer 200.0.3.1 psk cisco123、profile `match identity remote 200.0.3.1` + `identity local 200.0.1.1`
- IPsec: transform-set esp-des esp-sha256-hmac、profile pfs group14 + ikev2-profile
- Tunnel1: 172.16.40.1/30、source E0/1、`tunnel mode ipsec ipv4`、dest 200.0.3.1、protection
- route: `ip route 10.2.40.0/24 Tunnel1` / `0.0.0.0/0 200.0.1.254`、`router ospf 1`(router-id 10.255.0.254 / redistribute static subnets / network 10.0.1.28・10.0.1.32 area 0)
- **`no ip cef`**（br-edgeと同じ＝L2-advipservices の CEF-transit-VTI 暗号化クセ回避）
- br-edge側は無変更（トンネル宛先200.0.1.1を継承）。

## ハマった所と対策（次回の時短ポイント）

| 事象 | 原因 | 対策 |
|---|---|---|
| **再デプロイ後、全ノードのデータプレーン断**（直結pingも0、`packets input 0`） | **iouyap が起動していない**。イメージにbakeされた `entrypoint.sh` が `exec iol.bin` のみで iouyap を起動しない（`~/vrnetlab/cisco/iol/docker/entrypoint.sh` の修正版は `/usr/bin/iouyap 513 &` を含むが、イメージ未リビルド） | 各コンテナで手動起動: `docker exec -d -w /iol clab-campus-<node> /usr/bin/iouyap 513` |
| `plain destroy`+`deploy` で復活せず | 旧 `clab-campus/` の stale state を再利用 | `destroy --cleanup` してから `deploy`（nvramは失うので退避configから再投入） |
| IKEv2 IN-NEG / `Tunnel source UNKNOWN ... on deleted interface` | configペースト順で Tunnel1 が E0/1 のIP確定前に作られ、`no switchport` で E0/1 が再生成され source追跡が旧IFを指したまま | `interface Tunnel1` → `no tunnel source` → `tunnel source Ethernet0/1` で再バインド |
| 本社サーバ網が OSPF に出ず、HQ到達不可 | dist-b1 の **VLAN30/99 が VLAN DBに無い**（ペーストの `vlan 30/name` 未コミット）＋ SVI が admin-down | `vlan 30/99` 作成 + `interface Vlan30/99` `no shutdown` |

## 重要な未対応・フォロー

1. **永続性（最重要）**: 上記 iouyap は手動起動。**コンテナ/VM再起動でデータプレーンが再び死ぬ**。恒久対策は **イメージの entrypoint 修正＋リビルド**（修正版entrypointは `~/vrnetlab/cisco/iol/docker/entrypoint.sh` に既存）。暫定運用は「デプロイ後に全ノードへ iouyap を流す1行スクリプト」。
2. **A棟未確認**: 同じVLAN未コミット問題で dist-a1/a2 の VLAN10/20 や pc-sales/pc-dev→サーバが切れている可能性。T-105(支社→本社)とは別系統。要確認・同手順で修正可。
3. **FortiGateのFW/NAT役は消失**: 本社→Internet の SNAT・セキュリティポリシーは plain Ciscoルーターでは無い（L2-advipserviceは `ip nat` 非対応）。FW学習継続なら別途 `cisco_asav` 等を検討。
4. ノード名は `fgt-edge` 据え置き（実体Cisco）。混乱するなら `hq-edge` へ改称可。

## 2026-06-26 追補: Cisco置換状態の固定化

- `build_and_deploy.sh` をCisco置換後の前提へ更新。
  - `fgt-edge` はCisco IOLになったため、deploy後の `iouyap` 自動起動対象に含める。
  - 必須IOL imageは `L2-advipservices-2017` / `L2-15.2`。`15.7.3M2` とFortiGate imageは任意・旧検証用として扱う。
- `03_詳細設計/config_commands/fgt-edge.txt` をFortiOS設定からCisco HQ edge設定へ置換。
  - E0/1 WAN、E0/2/E0/3 core向け、Tunnel1、IKEv2/IPsec、OSPF、`no ip cef`、支社LAN向けstaticを含む。
- 設計シートと試験計画をCisco置換後の読み方に更新。
  - T-105/T-602はCisco-Cisco VPNとして扱う。
  - FortiGate policy/NAT系は旧Forti版またはASAv版へ戻す際の観点として残す。
- 追加確認:
  - `br-pc -> 10.20.30.254`: 3/3成功。
  - `br-pc -> 10.20.30.20`: 4/4成功。
  - `curl -I http://10.20.30.20/`: HTTP 200。
  - `curl -r 0-200 http://10.20.30.20/`: HTML先頭取得成功。
- 残課題:
  - `config_commands/` は今回 `fgt-edge.txt` のみ同期。br-edge/core/dist/accessのライブ全量同期は別途実施すると再現性がさらに上がる。
  - A棟VLAN10/20は現状 `dist-a1/a2` のSVIがdownで、T-101/T-102は未復旧。今回のCisco VPN固定化とは別タスク。
