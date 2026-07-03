# VPN代替案: 既存imageでの実装優先順位

## 【2026-06-26 実施結果 — 完了】

- **fgt-edge を Cisco IOL に置換し、T-105(br-pc→srv-portal) を開通させた**（ping 4/4・HTTP 200・ESP暗号化確認）。詳細: `../切り分け/fortigate_cisco_swap_RESOLVED_2026-06-26.md`。
- **重要な訂正**: 下表ランキング1位の `cisco_iol:15.7.3M2` は **このARM64ホストでは起動しない**（System Config Dialogハング。`../22_enterprise_campus_lan/環境_土台再構築_2026-06-15.md` §6）。
  → **実際に使ったのは `cisco_iol:L2-advipservices-2017`**（唯一の実証済みL3 IOL、br-edge/core/distと同一）。`no ip cef` でCEF-transit-VTIクセを回避。
- **永続性の注意**: イメージの `entrypoint.sh` が iouyap を起動しないため、再デプロイ/再起動でデータプレーンが死ぬ。恒久対策は entrypoint修正＋イメージ再ビルド（修正版は `~/vrnetlab/cisco/iol/docker/entrypoint.sh`）。

## 結論

- 最短で成功体験を作るなら `vrnetlab/cisco_iol:15.7.3M2` でCiscoルーター同士のIPsec VPNを組む。
- 今回のFortiGate x Cisco構成は、IKE/IPsec自体は成立するが、FortiGate側で復号済みLAN間パケットがforward policy/session/egressに進まない。
- FortiGateを続ける場合は、先にライセンス有効状態または別FortiOS版で比較する。

## 推奨ランキング

| rank | image | 使い方 | 採用理由 |
|---:|---|---|---|
| 1 | `vrnetlab/cisco_iol:15.7.3M2` | Cisco-Cisco IPsec | 軽い、既存ラボあり、まずT-105相当を通すのに最短 |
| 2 | `vrnetlab/cisco_csr1000v:17.03.05` | IOS XE IPsec | 実機寄りでIPsec検証に強い |
| 3 | `vrnetlab/cisco_asav:9-18-1` | FW型VPN代替 | FortiGateのFW役割をCisco ASAで代替可能 |
| 4 | `vrnetlab/cisco_vios:159-3.M6` | IOS系比較 | IOL以外のCisco比較候補 |
| 5 | `vrnetlab/juniper_vsrx:24.4R1.9` | マルチベンダーVPN | Forti以外のFW/VPN装置として有力 |
| 6 | `vrnetlab/mikrotik_routeros:7.5` | 軽量IPsec | 小さく試せるが学習軸はCisco/Fortiから外れる |
| 7 | `vrnetlab/vr-fortios:7.4.2.F` | Forti再検証 | 今回の未解決個体。invalid license制限が疑い |

## 次の実装候補

- `14_cisco_ipsec_vpn` をベースに、HQ `10.20.30.0/24` と支社 `10.2.40.0/24` のLAN間VPNへ拡張する。
- 成功後、テーマ22の `fgt-edge` を一時的にCisco VPN edgeへ置換する比較トポロジを作る。
- FortiGate再挑戦は、ライセンス有効化または別FortiOS build確認後に行う。

## 参照

- 詳細な切り分け記録: `../切り分け/fortigate_cisco_ipsec_transit_unresolved_2026-06-26.md`
- Fortinet KB: https://community.fortinet.com/fortigate-3/troubleshooting-tip-error-no-route-exists-from-source-address-with-policy-matching-194132
- Fortinet Docs: https://docs.fortinet.com/document/fortigate/6.4.0/administration-guide/239039/dynamic-tunnel-interface-creation
