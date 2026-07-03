# FortiGate x Cisco IKEv2 VPN: LAN間疎通未達の切り分け記録

## 1. 何ができなかったか

- 対象ラボ: `22_enterprise_campus_lan`
- 目的: 支社LAN `10.2.40.0/24` から本社サーバVLAN `10.20.30.0/24` へ、FortiGate x Cisco IOL の route-based IPsec VPN 経由で疎通させる。
- 未達の試験:
  - `br-edge` -> `10.20.30.254 source 10.2.40.254`: 失敗
  - `br-pc 10.2.40.100` -> `srv-portal 10.20.30.20`: ping/curl とも失敗
- 成功している試験:
  - IKEv2 SA: `READY`
  - IPsec Phase2 selector: FortiGate/Ciscoとも `0.0.0.0/0 <-> 0.0.0.0/0`
  - `br-edge` -> FortiGate tunnel IP `172.16.40.1`: 成功
  - FortiGate自身 -> `10.20.30.254`: 成功
  - HQ側OSPF: `10.2.40.0/24` の戻り経路あり

## 2. 現在の状況

- FortiGateはVPNから復号済みパケットを受け取れている。
- 例: `10.2.40.100 -> 10.20.30.20` が `VPN_to_Branch in` として見える。
- FortiGateは宛先への経路も解決している。
  - `10.20.30.20` / `10.20.30.254` は `10.0.1.33 via port4` などに解決。
- しかし、その後に firewall policy hit / session生成 / egress packet が出ない。
- `diagnose firewall iprope show 100004 3` の Policy3 hit counter は増えない。
- `diagnose sniffer packet any "host 10.2.40.100 and host 10.20.30.20"` では `VPN_to_Branch in` だけが見え、`port3/port4 out` が見えない。

## 3. 実施した切り分け

### 送信元IPの修正

- 以前のflow debugでは `172.16.40.2 -> 10.20.30.254` になっていた。
- これは支社LAN送信元ではなく、Cisco Tunnel1送信元の試験だった。
- `br-edge` で `ping 10.20.30.254 source 10.2.40.254` を実行し、FortiGate側で `10.2.40.254 -> 10.20.30.254` と見えることを確認。
- そのため「試験パケットの送信元が違う」問題は解消済み。

### FortiGate policy確認

- 既存policy:
  - Policy1: `port3 port4 -> port2`, NAT enable
  - Policy2: `port3 port4 -> VPN_to_Branch`, NAT disable
  - Policy3: `VPN_to_Branch -> port3 port4`, NAT disable
- 評価版制限により firewall policy は `vdom-max = 3` で、追加policyは作成不可。
- Policy3を一時的に `VPN_to_Branch -> port4` 単一に絞ったが改善なし。
- 最終的には既知正常点維持のため `VPN_to_Branch -> port4 port3` に戻した。

### FortiGate IPsec/route確認

- `show vpn ipsec phase2-interface`: Phase2 selectorは広いまま。
- `diagnose vpn tunnel list`: FortiGate側も `0.0.0.0/0 -> 0.0.0.0/0`。
- `show crypto ipsec sa`: Cisco側も local/remote ident は `0.0.0.0/0`。
- `get router info routing-table details 10.20.30.20`: FortiGateはHQ側routeを持つ。
- `get router info routing-table details 10.2.40.100`: FortiGateは支社LAN routeを `VPN_to_Branch` に持つ。

### Fortinet記事を踏まえた試行

- Fortinet KBに、IPsecトンネル利用時に送信元アドレス範囲とトンネルIF IP範囲の不一致で policy matching 前に詰まる事例がある。
- 参考: https://community.fortinet.com/fortigate-3/troubleshooting-tip-error-no-route-exists-from-source-address-with-policy-matching-194132
- そのため一時的に以下を試した。
  - `set net-device enable`
  - `VPN_to_Branch` tunnel IF の `ip/remote-ip` を `0.0.0.0/0` 相当に変更
- 結果: 改善なし。
- 既知正常点を壊さないため、以下へ戻した。
  - `set net-device disable`
  - `set ip 172.16.40.1 255.255.255.255`
  - `set remote-ip 172.16.40.2 255.255.255.252`

### Fortinet公式仕様として確認したこと

- Fortinet公式ドキュメントでは、route-based/dynamic IPsec tunnelで `net-device` がトンネル経路制御に関わる設定として扱われている。
- 参考: https://docs.fortinet.com/document/fortigate/6.4.0/administration-guide/239039/dynamic-tunnel-interface-creation
- 今回は `net-device enable` でも改善しなかったため、単純な `net-device` 設定不足ではなさそう。

## 4. 現時点の見立て

- 下回り、IKEv2、Phase2 selector、HQ側OSPF、支社側ルートは主因ではない。
- FortiGateは復号済みパケットを受け取り、宛先routeも解決している。
- それでも forward policy counter/session/egress に進まないため、FortiGate/FortiFirewall VM側の制限・バージョン差・ライセンス制限が濃い。
- 実機状態では `License Status: Invalid` で、policy数も `vdom-max = 3` に制限されている。
- 今回の構成をこのFortiFirewall-VMでさらに詰めるより、別imageで同じ要件を再現して比較する方が早い。

## 5. 次回やらないこと

- `ping 10.20.30.254` をsource未指定で試すだけでは意味が薄い。
- `172.16.40.2` 送信元の疎通を追い続けない。T-105の本命は支社LAN送信元。
- Policy3を `port4` 単一に絞るだけでは改善しなかったため、同じ試行を繰り返さない。
- `net-device enable` と tunnel IF無番化は一度試して改善なし。再試行するならFortiOS版やライセンス状態を変えて比較する。

## 6. 既存image一覧

| image | 用途メモ |
|---|---|
| `vrnetlab/cisco_iol:15.7.3M2` | Ciscoルーター用途。まずVPN代替検証に最適 |
| `vrnetlab/cisco_iol:15.6.3M3a` | Ciscoルーター用途。15.7.3M2の比較候補 |
| `vrnetlab/cisco_iol:L2-advipservices-2017` | L3スイッチ用途。テーマ22のcore/dist/br-edgeで使用中 |
| `vrnetlab/cisco_iol:L2-15.2` | L2スイッチ用途 |
| `vrnetlab/cisco_csr1000v:17.03.05` | Cisco IOS XEルーター。IPsec検証の有力候補 |
| `vrnetlab/cisco_csr1000v:16.12.05` | Cisco IOS XEルーター。17.03.05の比較候補 |
| `vrnetlab/cisco_c8000v:17.06.03` | Cisco IOS XE/SD-WAN系。高機能だが重い |
| `vrnetlab/cisco_c8000v:controller-17.06.03` | C8000v controller系。今回の単純VPN用途では優先度低 |
| `vrnetlab/cisco_asav:9-18-1` | Cisco ASA firewall。FortiGate代替のFW型VPN検証候補 |
| `vrnetlab/cisco_vios:159-3.M6` | Cisco IOSv系。軽量ルーター候補 |
| `vrnetlab/cisco_vios:L2-20200929` | IOSv L2系。L2検証向け |
| `vrnetlab/cisco_nxostitanium:7.3.0.D1.1` | NX-OS。データセンターL2/L3向けでIPsec主役ではない |
| `vrnetlab/vr-fortios:7.4.2.F` | 今回のFortiFirewall/FortiOS VM。LAN間transitで未解決 |
| `vrnetlab/fortinet_fortios:7.4.2.F` | 上記と同ID。実体は同じ |
| `vrnetlab/juniper_vsrx:24.4R1.9` | Juniper SRX。マルチベンダーVPN検証候補 |
| `vrnetlab/arista_veos:4.29.2F` | Arista L2/L3。IPsec主役ではない |
| `vrnetlab/mikrotik_routeros:7.5` | MikroTik RouterOS。IPsec検証候補 |
| `vrnetlab/canonical_ubuntu:jammy` / `vrnetlab/vr-ubuntu:jammy` | Linuxルーター/strongSwan検証候補 |
| `wbitt/network-multitool:latest` | PC/サーバ疎通試験用 |
| `debian:bookworm-slim` | 軽量Linux部材 |

## 7. 代替機器ランキング

| rank | image | 推奨用途 | 理由 | 注意 |
|---:|---|---|---|---|
| 1 | `vrnetlab/cisco_iol:15.7.3M2` | Ciscoルーター同士のroute-based IPsec再現 | 既存の `14_cisco_ipsec_vpn` で利用済み。軽く、Cisco同士なのでまず成功形を作りやすい | FortiGate相互接続の学習にはならない |
| 2 | `vrnetlab/cisco_csr1000v:17.03.05` | IOS XEでの本格的IPsec再現 | IKEv2/IPsecの機能確認に強い。Cisco実機寄り | IOLより重い |
| 3 | `vrnetlab/cisco_asav:9-18-1` | Firewall型VPNのCisco代替 | FortiGateのFW型役割をCisco ASAで置き換えられる | ASA構文・ライセンス挙動の別学習が必要 |
| 4 | `vrnetlab/cisco_vios:159-3.M6` | 軽量Ciscoルーター比較 | IOL以外のCisco IOS系で比較できる | crypto機能差は要確認 |
| 5 | `vrnetlab/juniper_vsrx:24.4R1.9` | マルチベンダーVPN比較 | FortiGate以外のFW/VPN装置として有力 | Junos設定学習コストがある |
| 6 | `vrnetlab/mikrotik_routeros:7.5` | 軽量マルチベンダーIPsec | 小さく試せる | 企業Cisco/Forti文脈からは少し外れる |
| 7 | `vrnetlab/vr-fortios:7.4.2.F` | FortiGate再検証 | FortiGate固有仕様の学習には必要 | 今回の未解決個体。invalid license制限が疑い |

## 8. 推奨する代替実装

### 最短成功ルート

- 既存 `14_cisco_ipsec_vpn` をベースに、Cisco IOLルーター同士で `br-pc -> srv-portal` 相当のLAN間VPNを先に完成させる。
- 目的は「T-105相当の正解形」を作ること。
- 推奨image: `vrnetlab/cisco_iol:15.7.3M2`

### テーマ22へ戻すルート

- `22_enterprise_campus_lan` の `fgt-edge` 役を一時的にCiscoルーターへ置換する。
- HQ core側は既存のOSPF構成を維持し、支社経路 `10.2.40.0/24` の再配布とVPN終端だけをCiscoに寄せる。
- まずCisco-CiscoでLAN間疎通を証明し、その後FortiGate/FortiFirewall個体の問題として分離する。

### FortiGateを続ける場合

- ライセンス有効なFortiGate VMか、別FortiOS buildで同じ設定を再現する。
- 再試験時の最初の確認は以下:
  - `get system status` の `License Status`
  - firewall policy上限
  - `diagnose sniffer` で `VPN_to_Branch in` と `port3/port4 out` の両方が見えるか
  - `diagnose firewall iprope show 100004 <policy-id>` のhit counter

## 9. 次回の開始手順

1. `14_cisco_ipsec_vpn` をコピーして、支社LAN `10.2.40.0/24` とHQサーバVLAN `10.20.30.0/24` に合わせる。
2. VPN edgeは `vrnetlab/cisco_iol:15.7.3M2` で統一する。
3. `br-pc -> srv-portal` のping/curlを成功させる。
4. 成功したら同じアドレス設計をテーマ22へ戻し、FortiGate差分だけを比較する。
5. FortiGate再挑戦はライセンス/版差確認後に行う。
