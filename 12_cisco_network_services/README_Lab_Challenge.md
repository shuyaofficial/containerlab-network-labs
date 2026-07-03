# ネットワークサービス（DHCP / DNS / NTP）チャレンジ

ネットワークインフラの上に、クライアントPCが通信するためのコアサービスを構築します。
今回はLinuxサーバーを使わず、Ciscoルーター（SRV1）の強力な組み込み機能を活用して、「1台でDHCP/DNS/NTPを兼任するインフラサーバー」を作ります。

---

## 🎯 トポロジ設計とIPアドレス

### 機器構成とログインIP
- **SRV1**: `172.20.20.4` (インフラサーバー: DHCP, DNS, NTP)
- **SW1**: `172.20.20.2` (L3スイッチ: デフォルトGW, DHCPリレー)
- **PC1**: `172.20.20.3` (クライアントPC: DHCPでIP取得)

※ユーザ/パスはすべて `admin` / `admin`

### IP設計
**【サーバー側ネットワーク】**
- ネットワーク: `10.1.1.0 /24`
- **SRV1** (e0/0): `10.1.1.1`
- **SW1** (e0/1): `10.1.1.2`  *(※ `no switchport` が必要)*

**【クライアント側ネットワーク (VLAN 10)】**
- ネットワーク: `10.10.10.0 /24`
- **SW1** (VLAN 10 SVI): `10.10.10.254`
- **PC1** (VLAN 10): DHCPで取得

---

## 🏗️ 構築要件（ステップバイステップ）

### 1. 物理の疎通（L2/L3の土台）を作る
まずは「サーバー ⇔ SW1」と「SW1 ⇔ PC」のIP通信ができるようにします。
- **SRV1**: `Ethernet0/0` にIP（10.1.1.1）を設定。
- **SW1**:
  - `Ethernet0/1` をL3ポート化（`no switchport`）し、IP（10.1.1.2）を設定。
  - `Ethernet0/2` を `switchport access vlan 10` に設定。
  - `interface vlan 10` を作成し、IP（10.10.10.254）を設定して `no shut`。
- **PC1**:
  - `Ethernet0/1` をL3ポート化（`no switchport`）し、IPは設定せずに `ip address dhcp` と設定して `no shut` します。（※L2イメージの仕様上、VLANインターフェースではDHCPが使えないための回避策です）

> 💡 ここまで終わると、SW1からSRV1（10.1.1.1）へPingが通るはずです。

### 2. SRV1 を「DHCPサーバー」にする
SRV1で、PC1向け（10.10.10.0/24）のDHCPプールを作成します。
```bash
SRV1(config)# ip dhcp pool VLAN10_POOL
SRV1(dhcp-config)# network 10.10.10.0 255.255.255.0
SRV1(dhcp-config)# default-router 10.10.10.254
SRV1(dhcp-config)# dns-server 10.1.1.1
SRV1(dhcp-config)# exit
```

### 3. SW1 を「DHCPリレーエージェント」にする（超重要）
PC1が発する「DHCP要求」はブロードキャスト（VLAN 10内のみ）なので、そのままではルーター（SW1）を越えてSRV1に届きません。
そこで、SW1の **VLAN 10 インターフェース** に、ブロードキャストをユニキャストに変換してSRV1へ転送する設定（ヘルパーアドレス）を入れます。
```bash
SW1(config)# interface vlan 10
SW1(config-if)# ip helper-address 10.1.1.1
```

> ✅ **【検証1: DHCP】**
> この設定を入れると、PC1に自動的に `10.10.10.1` などのIPが割り当てられるはずです！
> （PC1で `show ip int brief` を打って確認してください。もし降ってこない場合はPC1のVlan10で一度 `shutdown` → `no shutdown` してみてください）

### 4. SRV1 を「DNSサーバー」にする
SRV1に自分自身をDNSサーバーとして動かす設定と、ホスト名とIPの紐付け（Aレコードのようなもの）を登録します。
```bash
SRV1(config)# ip dns server
SRV1(config)# ip host srv1.lab.local 10.1.1.1
SRV1(config)# ip domain lookup
```

> ✅ **【検証2: DNS】**
> PC1から `ping srv1.lab.local` を実行し、名前解決されてPingが通ることを確認します！
> （PC1に `ip domain lookup` が入っている必要があります）

### 5. SRV1 と SW1 で「NTP」を動かす
ネットワーク機器の時刻を同期させます。
まず、SRV1を「基準となるマスターサーバー」にします。
```bash
SRV1(config)# ntp master 3
```
次に、SW1に「SRV1へ時刻を同期しにいく」設定を入れます。
```bash
SW1(config)# ntp server 10.1.1.1
```

> ✅ **【検証3: NTP】**
> SW1で `show ntp associations` を実行し、10.1.1.1 の前に `*`（同期完了マーク）が付くか確認します。
> （※NTPの同期には数分かかる場合があります）
