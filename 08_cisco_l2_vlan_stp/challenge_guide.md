# 🚀 Challenge 08: VLAN / 802.1Q トランク ＆ STP・RSTP（L2冗長の基礎）

> 🧩 **雛形（ドラフト）です。** 第2章「LAN/L2 スイッチングと冗長」の入口。
> ここから先は L3 ルーティングを離れ、**社内ローカルの冗長化**＝スイッチングの世界に入ります。
> ⚠ VLAN/STP は **IEEE規格（802.1Q / 802.1D / 802.1w）でRFCカタログには無い**領域。
> 第1章で身につけた「Hello→断検知→切替」の感覚が、ここでも丸ごと効きます（メンターTheme F）。

メンター対応: **Theme F（STP / L2ループ防止）**　｜　難易度: 初〜中級

---

## 🗺️ トポロジーと設計要件

スイッチ3台を**三角形（＝物理ループ）**に結線し、STP がどのポートを **Blocking** にするかを観測します。
PC2台を同一VLANに置き、ループを跨いだ疎通と、リンク断時の **RSTP高速収束** を体験します。

```
                 [ PC1 ]                         [ PC2 ]
              VLAN10 10.10.10.11             VLAN10 10.10.10.12
                  │ (access e0/3)                │ (access e0/3)
              ┌─[ SW1 ]──────── trunk ───────[ SW3 ]─┐
              │   e0/1   (802.1Q)        e0/1    │   │
              │                                   │   │
            trunk e0/2                       e0/2 trunk
              │                                   │   │
              └──────────────[ SW2 ]─────────────┘   │
                        e0/1        e0/2                │
              （SW1-SW2-SW3-SW1 の三角ループ → STPが1ポートをBlockingにする）
```

> 💡 ループがあると放置すればブロードキャストストームでL2が全滅する。
> それを **STP が自動でループを1か所切って（Blocking）防ぐ** ——これがこのラボの主役。

### 1. VLAN / IP 設計

| デバイス | 役割 | インターフェース | 設定 |
|---|---|---|---|
| **SW1** | L2スイッチ | e0/1, e0/2 | トランク（802.1Q, allow VLAN10,20） |
| **SW1** | 〃 | e0/3 | アクセス VLAN10（PC1収容） |
| **SW2** | L2スイッチ | e0/1, e0/2 | トランク |
| **SW3** | L2スイッチ | e0/1, e0/2 | トランク |
| **SW3** | 〃 | e0/3 | アクセス VLAN10（PC2収容） |
| **PC1** | linux(alpine) | eth1 | `10.10.10.11/24`（VLAN10） |
| **PC2** | linux(alpine) | eth1 | `10.10.10.12/24`（VLAN10） |

| VLAN | 用途 | サブネット |
|---|---|---|
| 10 | 営業（本ラボの疎通対象） | 10.10.10.0/24 |
| 20 | 開発（拡張課題用に定義のみ） | 10.10.20.0/24 |

> ⚠ インターフェース名（`Ethernet0/1`〜）は使用イメージで異なる場合あり。
> `show ip int brief` / `show interfaces status` で実機の名前を確認してから設定すること。

---

## 🎯 3つのミッション

### Mission 1: VLAN とトランクで疎通させる
1. SW1/SW3 にVLAN10を作成し、PC収容ポート（e0/3）を **アクセスVLAN10** にする。
2. スイッチ間リンク（e0/1, e0/2）を **802.1Q トランク**にし、VLAN10/20を許可する。
   ```ios
   vlan 10
    name Sales
   !
   interface Ethernet0/3
    switchport mode access
    switchport access vlan 10
   !
   interface range Ethernet0/1 - 2
    switchport trunk encapsulation dot1q   ! 必要な機種のみ
    switchport mode trunk
    switchport trunk allowed vlan 10,20
   ```
3. PC側（alpine）でIP付与:
   ```sh
   ip addr add 10.10.10.11/24 dev eth1 && ip link set eth1 up   # PC1
   ip addr add 10.10.10.12/24 dev eth1 && ip link set eth1 up   # PC2
   ```
4. **観測**: `PC1 → ping 10.10.10.12` が成功。`show vlan brief` / `show interfaces trunk` で確認。

### Mission 2: STP の Root選出と Blocking ポートを観測
1. 3台が三角ループになっている状態で、各SWで `show spanning-tree vlan 10` を確認。
2. **観測ポイント**:
   - **Root Bridge** はどれか（既定ではBridge IDが最小＝MAC最小のSW）。
   - どのSWのどのポートが **BLK(Blocking/ALTN)** になっているか（ループが1か所切れている）。
   - ポートの **Role（Root/Designated/Alternate）** と **State** を読み解く。
3. **設計してみる**: `spanning-tree vlan 10 root primary`（または `priority 4096`）で
   **狙ったSWをRootに固定**し、Blockingポートが意図通り移動することを確認。
   ```ios
   spanning-tree vlan 10 root primary       ! このSWをRootにする
   ```

### Mission 3: RSTP 高速収束（リンク断フェイルオーバ）
1. 収束を速くするため RSTP を有効化（対応機種）:
   ```ios
   spanning-tree mode rapid-pvst
   ```
2. `PC1 → ping 10.10.10.12` を**流しっぱなし**にする。
3. その状態で、現在 **Forwarding** している経路上のトランクを片方 `shutdown`。
4. **観測ポイント**:
   - これまで **Blocking** だったポートが **Forwarding** に昇格し、**数秒以内**で ping が復活する。
   - 旧STP（802.1D）なら最大 ~30〜50秒、**RSTP（802.1w）なら数秒**で収束する差を体感する。
   - `show spanning-tree` の Role/State 変化と、収束に要したping落ち数を記録する。

---

## 🔎 仕上げの確認（振り返りシートに書くと良い観点）
- Root Bridge を「MAC任せ」にせず**明示設計**すべき理由は？（経路最適化・予測可能性）
- トランクの **native VLAN** を既定(1)のままにするリスクは？（VLANホッピング）
- 第1章の **BFD/Helloタイマー** と STP/RSTP の収束は、考え方がどう同じでどう違う？

---

## ▶️ 次テーマ（09）への布石
09 では **EtherChannel(LACP)** で複数リンクを1本に束ねて「STPに切られない冗長」を作り、
**L3スイッチ + SVI** で VLAN間ルーティングへ進みます。STPで「切る」冗長との対比を意識して。

---

### 🛠 起動メモ（環境共通）
```bash
ssh clab@orb
cd <このフォルダの clab マシン上のパス>
sudo containerlab deploy  -t cisco_l2_vlan_stp.clab.yml   # 各ノード起動（IOLは約2分）
sudo containerlab destroy -t cisco_l2_vlan_stp.clab.yml   # 破棄
# CLI: sudo docker attach clab-cisco-l2-vlan-stp-sw1  （抜ける: Ctrl-P → Ctrl-Q）
```
> STP の BPDU は EdgeShark/Wireshark（`../環境/環境説明.md` §8）で覗くと挙動が腑に落ちる。
