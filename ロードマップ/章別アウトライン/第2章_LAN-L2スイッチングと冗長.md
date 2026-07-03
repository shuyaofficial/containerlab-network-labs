# 第2章: LAN/L2 スイッチングと冗長（✅ 完了）

> **制覇済みの章**（08〜11 完了）。社内LANは L3 だけでは動かない——
> 「PCの最初の1ホップ」を支える L2（VLAN/STP/EtherChannel）と GW冗長（HSRP）、さらに統合冗長まで固めた。
> ⚠ この章の中核は **IEEE/Cisco規格でRFCカタログに無い**（`00_カリキュラム対応表.md` B表で補完）。

---

## 🎯 章の狙い
- VLAN で部署/用途ごとにブロードキャストドメインを分割し、トランクで束ねられる
- STP/RSTP で L2ループを防ぎ、Root と Blocking ポートを意図通り設計できる
- EtherChannel で帯域集約・リンク冗長、L3スイッチで Inter-VLAN ルーティングができる
- HSRP/VRRP でデフォルトGWを冗長化できる
- **【山場】** 上流断を Track で検知し、HSRP・OSPF・BGP を**連動**させて一斉迂回できる

## 前提
- 第1章（OSPF/BGP/Track の感覚、`docker attach` での構築、障害試験の作法）

---

## 📋 テーマ一覧

| # | タイトル | 狙い | 規格 | 難易度 | 到達条件 |
|---|---|---|---|---|---|
| **08** | VLAN / 802.1Q / STP・RSTP | VLAN分割・トランク疎通、STP Root選出と Blockingポート観測、RSTP高速収束 | 802.1Q/D/w | 初〜中級 | ループ構成でブロッキングを目視→リンク断でRSTP収束を観測（=**Theme F**） |
| 09 | EtherChannel / L3SW・Inter-VLAN | LACPで束ねる、SVIでVLAN間ルーティング | 802.3ad/Cisco | 中級 | 1本抜いても無瞬断、VLAN10⇔20がSVI経由で疎通 |
| 10 | FHRP: HSRP / VRRP | 仮想IP/MAC、Active/Standby、Priority/Preempt | Cisco/RFC5798 | 中級 | Active落として仮想GW無瞬断、`show standby`理解（=**Theme G**） |
| **11** | 統合冗長: Track×HSRP×OSPF/BGP | 上流断→HSRP切替→IGP/BGP迂回を一斉連動 | 統合 | 上級 | 「社内PCの上流リンク断→GW切替→BGP経由で外へ」を自力構築（=**Theme H**） |

---

## 💡 第1章との「本質は同じ」つながり（メンターの開眼ポイント）
| 観点 | L3（第1章） | L2/FHRP（第2章） |
|---|---|---|
| 生存確認 | Hello（OSPF/BGP Keepalive） | Hello（STP BPDU / HSRP Hello） |
| 断検知 | Dead/Hold タイマー、BFD | Max Age、HSRP Holdtime |
| 切替 | 経路再計算・再収束 | Root再選出 / Active→Standby |
| 高速化 | RSTP相当＝BFD | RSTP（802.1w）／HSRP短縮タイマー |

> 「世界の冗長化（BGP）」も「社内の冗長化（STP/HSRP）」も *Hello→断検知→切替* で同じ。
> 11 で両者を **物理的に連動**させると、エンタープライズ冗長化が完成する。

---

## 🖥️ 環境メモ
- スイッチは L2 IOL イメージ（例 `vrnetlab/cisco_iol:L2-15.2`、`../環境/環境説明.md` §4）
- PCは軽量 linux コンテナ（alpine）で代用可
- STP観測は EdgeShark/Wireshark（`../環境/環境説明.md` §8）で BPDU を見ると理解が深まる

## ✅ 章末チェック
- [ ] `show spanning-tree` から Root Bridge・Role・State を読み、設計意図通りか判断できる
- [ ] トランクの allowed vlan / native vlan の事故（VLAN hopping含む）を説明できる
- [ ] L3スイッチの SVI と ルーテッドポートの違いを使い分けられる
- [ ] HSRP の Active/Standby を Priority と Preempt で意図通り固定できる
- [ ] **11**: 上流断時に「GW(HSRP)・経路(OSPF/BGP)が連動して切り替わる」図を描いて説明できる
- [ ] 各テーマの `振り返りシート` を作成済み
