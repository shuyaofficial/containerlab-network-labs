# ShowNet 2026 調査メモ

作成日: 2026-06-19

## 公式情報からの抽出

- ShowNet 2026 のテーマは `Engineering Everything Connected`。
- 公式ページでは ShowNet を「2年後、3年後のネットワークのひとつの姿」を示すコンセプトネットワークとして説明している。
- Peering Portal では ShowNet AS290 に IX 経由で接続できる案内があり、対外接続とBGPを中心テーマとして扱える。
- ShowNet contributor コメントでは、対外接続ルータが IOWN や IPA などの高速回線を収容し、SRv6 uSID L3VPN でShowNet Backboneを支えたことが示されている。
- セッション一覧では、AI Grid、キャリア5G x IOWN APN、統合監視、トラフィックモニタリング、Wi-Fi 2026、ルーティングセキュリティ、広帯域化が扱われている。
- Yamaha の Media over IP 発表では、幕張、ヤマハ横浜オフィス、ヤマハ本社を接続し、NUROアクセスと IOWN APN を組み合わせる構成が示されている。
- NTTドコモビジネス発表では、IOWN APN を使った約10,000kmの広域実証が説明されている。

## 添付写真からの読み取り

- `#N-1`, `#N-2` は対外接続回線/対外接続ルータとして展示されている。
- `#N-3` はコアネットワークとして展示され、バックボーンの中心に置くのが自然。
- `#N-4` は大容量トランスポートとして展示され、APN/広域伝送の抽象ノードにできる。
- `#N-5` は高密度パッチパネル/ロボット配線システムで、物理配線自動化として文書化対象に留める。
- `#S-4` はサイバー脅威検出、`#S-5` はセキュアリモートアクセスで、監視・管理アクセス制御として再現できる。
- 大型トポロジー画面には `800G/1.6T接続`, `長距離RDMA`, `分散AI基盤`, `DCクラウド` といったキーワードが見えるため、ラボでは高速物理層そのものではなく、広域・冗長・観測可能な論理構成として再現する。

## 再現するもの

- AS290相当の対外BGP。
- 2台edge、2台coreの冗長バックボーン。
- APN/長距離トランスポートを表す中継ノード。
- Media over IPの3拠点UDP疎通。
- 監視/AI観測点。
- セキュアリモートアクセスから管理系だけに到達できる制限。

## 再現しないもの

- 800G/1.6Tなどの物理速度。
- 実IOWN APN、実キャリア5G、光波長制御。
- 本物のSRv6 uSID L3VPN。Cisco IOLの対応範囲が限られるため、MVPではVRF風の設計と経路分離の考え方に留める。
- PTP GrandmasterやST 2110/NMOSの実装。MVPではNTP/UDP疎通観測で代替する。
- ロボット配線システム。配線表と運用メモで表現する。

## ECC活用メモ

- `cisco-ios-patterns`: showコマンド、BGP/OSPF/ACLの確認観点に使う。
- `network-config-validation`: 生成configの危険コマンド、IP重複、ACL/route-map参照を確認する。
- `network-bgp-diagnostics`: eBGP/iBGPが上がらないときのread-only切り分け手順に使う。
- `homelab-network-setup`: 小さく始めて拡張できるIP計画、役割分離に使う。
- `homelab-network-readiness`: 既存Theme 22を汚さない段階構築と復旧導線の確認に使う。

## 主要ソース

- ShowNet 2026公式: https://www.interop.jp/2026/shownet/concept/
- ShowNetセッション: https://www.interop.jp/2026/shownet/session/
- Yamaha Media over IP発表: https://prtimes.jp/main/html/rd/p/000001141.000010701.html
- NTT IOWN APN発表: https://www.ntt.com/about-us/press-releases/news/article/2026/0610.html
