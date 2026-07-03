# 🚀 Challenge 09: EtherChannel (LACP) & Inter-VLAN Routing (SVI)

メンター対応: **Theme G / Theme F発展**　｜　難易度: 中級

---

## 🗺️ トポロジーと設計要件

SW1（コア・L3）と SW2（アクセス・L2）の間を **2本のケーブル** で繋ぎます。
STPのままだとループを防ぐために1本が「通行止め（Blocking）」になりますが、今回は **EtherChannel（LACP）** を使って2本を「極太の1本」に論理的に束ね、両方とも通信に使えるようにします。
さらに、SW1 で **SVI（Switch Virtual Interface）** を作成し、異なるVLAN間（営業部と開発部）でルーティング（通信）できるようにします。

```text
        [ SW1 (Core/L3) ]
          │          │ 
     e0/1 │          │ e0/2
   (LACP EtherChannel: Po1)
          │          │
     e0/1 │          │ e0/2
        [ SW2 (Access/L2) ]
          │          │
     e0/3 │          │ e1/0
       VLAN10      VLAN20
        [PC1]      [PC2]
    10.10.10.11  10.10.20.12
```

### 1. VLAN / IP 設計

| デバイス | 役割 | インターフェース | 設定 |
|---|---|---|---|
| **SW1** | コア/L3SW | e0/1, e0/2 | LACP トランク (Port-channel 1) |
| **SW1** | 〃 | SVI (VLAN 10) | `10.10.10.254/24` (VLAN10のゲートウェイ) |
| **SW1** | 〃 | SVI (VLAN 20) | `10.10.20.254/24` (VLAN20のゲートウェイ) |
| **SW2** | アクセスSW | e0/1, e0/2 | LACP トランク (Port-channel 1) |
| **SW2** | 〃 | e0/3 | アクセス VLAN 10 |
| **SW2** | 〃 | e1/0 | アクセス VLAN 20 |
| **PC1** | linux | eth1 | `10.10.10.11/24`, GW: `10.10.10.254` |
| **PC2** | linux | eth1 | `10.10.20.12/24`, GW: `10.10.20.254` |

---

## 🎯 3つのミッション（要件）

※ `mentor_guidelines.md` に則り、コマンドは記載していません！設定の目的を読み解いてチャレンジしてください。

### Mission 1: EtherChannel (LACP) の構築
1. **SW1** と **SW2** の `e0/1` と `e0/2` を束ねて、**Port-channel 1** を作成してください。プロトコルは標準規格の **LACP (active)** を使用します。
2. 作成した論理インターフェース（`Port-channel 1`）を **802.1Q トランク** に設定し、VLAN 10 と 20 の通信を許可してください。
   - *確認ポイント:* `show etherchannel summary` で `Po1(SU)` になっているか？ `show spanning-tree` で e0/1 や e0/2 が個別にブロックされず、`Po1` としてFWDになっているか？

### Mission 2: アクセスVLANの割り当て
1. **SW2** に VLAN 10 と 20 を作成してください。
2. `e0/3` を VLAN 10 のアクセスポート、`e1/0` を VLAN 20 のアクセスポートに設定してください。

### Mission 3: SVI による VLAN間ルーティング
現状では、PC1(VLAN10)とPC2(VLAN20)は別の部屋にいるため通信できません。ルーターの代わりに、コアスイッチ（SW1）にルーティングをさせます。
1. **SW1** に VLAN 10 と 20 を作成してください。
2. **SW1** に **SVI（interface vlan 10, interface vlan 20）** を作成し、それぞれのゲートウェイIPアドレス（`10.10.10.254` と `10.10.20.254`）を設定してください。
3. **SW1** でIPルーティング機能を有効化（`ip routing`）してください。
   - *確認ポイント:* PC1 から PC2（`10.10.20.12`）へのPingが通るか？

---

### 🛠 起動メモ
```bash
ssh clab@orb
cd <このフォルダのパス>
sudo containerlab deploy -t cisco_etherchannel.clab.yml
```

### 🦈 Wireshark パケットキャプチャ（Macのターミナルで実行）
SW1 と SW2 を繋ぐケーブル（`Ethernet0/1` に相当する `eth1`）に流れるLACPやVLANのパケットを観察するためのコマンドです。
```bash
ssh clab@orb "sudo nsenter -t \$(docker inspect -f '{{.State.Pid}}' clab-cisco-etherchannel-sw1) -n tcpdump -U -nni eth1 -w -" | /Applications/Wireshark.app/Contents/MacOS/Wireshark -k -i -
```
