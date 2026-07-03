# 🏆 Theme 23: Collapsed Core Campus LAN

## 📝 ミッション
実務で最も採用されることの多い**「Collapsed Core（2階層モデル）」**のキャンパスLANを設計・構築・試験せよ。

伝統的な3階層モデルから「コア層」と「ディストリビューション層」を1組の強力なL3スイッチに統合し、ルーティング、HSRP（デフォルトGW冗長化）、そしてSTPルートブリッジの機能をすべて集約させること。

## 🗺️ トポロジ図 (Collapsed Core)

```mermaid
graph TD
    subgraph "Core & Distribution Layer (L3/L2)"
        CD1(CoreDist-1<br>L3 Switch) ---|Trunk / OSPF| CD2(CoreDist-2<br>L3 Switch)
    \end
    
    subgraph "Access Layer (L2)"
        Acc1(Access-1<br>L2 Switch)
        Acc2(Access-2<br>L2 Switch)
    \end
    
    subgraph "Endpoints"
        PC1(PC-1<br>VLAN 10)
        PC2(PC-2<br>VLAN 20)
        PC3(PC-3<br>VLAN 10)
    \end
    
    %% Trunks
    CD1 ---|Trunk| Acc1
    CD1 ---|Trunk| Acc2
    CD2 ---|Trunk| Acc1
    CD2 ---|Trunk| Acc2
    
    %% Access Ports
    Acc1 ---|VLAN 10| PC1
    Acc1 ---|VLAN 20| PC2
    Acc2 ---|VLAN 10| PC3
```

## ⚙️ 推奨コンテナイメージ（Apple Silicon / M4対応）
本環境では、コンテナベースの軽量かつ完全なCiscoルーター/スイッチ環境を使用する。

- **CoreDist (L3スイッチ役)**
  - `vrnetlab/cisco_iol:L3-adventerprisek9`
  - 理由: デフォルトで `ip routing` が有効であり、OSPFやHSRPの動作に完全対応しているため。
- **Access (L2スイッチ役)**
  - `vrnetlab/cisco_iol:L2-advipservices-2017` (または同等のL2イメージ)
  - 理由: VLAN, Trunk, STPの動作に最適化されており、L3ルーティングのオーバーヘッドがないため。
- **Endpoints (PC役)**
  - `parts_endpoints/` フォルダ内のスクリプトを利用（実体は `alpine` コンテナ等）。

## 🎯 達成条件 (Acceptance Criteria)
1. **L2設計**: CoreDist1がVLAN10のSTPルートブリッジ、CoreDist2がVLAN20のSTPルートブリッジとして機能し、負荷分散されていること。
2. **デフォルトGW冗長化**: VLANごとにHSRPを設定し、アクティブ側のHSRPルーターがSTPルートブリッジと一致していること。
3. **L3設計**: CoreDist-1とCoreDist-2の間はL3ルーティング（OSPF等）で経路交換を行い、障害時に迂回できること。
4. **疎通確認**: PC-1(VLAN10)からPC-2(VLAN20)への通信が成功すること。
5. **障害試験**: CoreDist-1へのリンクを全て切断（shutdown）した際に、通信断が数秒以内に収束し、CoreDist-2経由で通信が継続すること。

---
## 👣 進め方
1. `01_要件定義/` : ネットワーク要件、VLAN/IPアドレス体系の定義
2. `02_基本設計/` : 論理構成図、STP/HSRPの設計
3. `03_詳細設計/` : ポートアサイン、パラメータシートの作成
4. `04_構築/` : `campus.clab.yml` を作成し、Ciscoコンテナを起動・設定投入
5. `05_試験/` : テストケースの作成と、リンク切断時のフェイルオーバー挙動の確認
