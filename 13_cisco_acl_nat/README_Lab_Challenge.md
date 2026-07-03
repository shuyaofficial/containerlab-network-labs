# アクセス制御とアドレス変換（ACL / NAT / Port Security）チャレンジ

第4章の第一歩として、社内LANを「保護」し、かつ「インターネットと安全に通信させる」ためのコア技術を構築します。
このテーマをクリアすれば、実務における「なぜ通信が通らないのか」の切り分け（FWのポートブロックやNAT漏れなど）の基礎が完全に身につきます。

---

## 🎯 トポロジとIPアドレス設計

### ログイン情報
- ユーザー/パス: `admin` / `admin`
- **PC1** (正規PC): `172.20.20.2`
- **PC2** (不正/テストPC): `172.20.20.3`
- **SW1** (アクセススイッチ): `172.20.20.4`
- **SRV1** (インターネット外部サーバー): `172.20.20.5`
- **R1** (境界エッジルーター): `172.20.20.6`

### ネットワーク設計
**【内部ネットワーク (Inside)】**
- ネットワーク: `192.168.10.0 /24`
- **PC1 (e0/1)**: `192.168.10.10` （デフォルトGW: `192.168.10.254`）
- **PC2 (e0/1)**: `192.168.10.20` （デフォルトGW: `192.168.10.254`）
- **R1 (e0/1)**: `192.168.10.254`

**【外部ネットワーク (Outside)】**
- ネットワーク: `200.1.1.0 /24`
- **R1 (e0/2)**: `200.1.1.1`
- **SRV1 (e0/1)**: `200.1.1.8`

> 💡 **ヒント**: PC1とPC2はルーターのイメージを使っていますが、ホストとして振る舞わせるために `no ip routing` と `ip default-gateway 192.168.10.254` を設定してください。

---

## 🏗️ 構築要件

### 1. 物理の疎通（L2/L3の土台）を作る
各機器に上記のIPアドレスを設定し、PC1/PC2 から R1 の内部インターフェース（`192.168.10.254`）へ Ping が飛ぶようにします。
SW1はデフォルトで全ポートがVLAN 1に所属しているため、そのままL2スイッチとしてパケットを中継させます。（特にVLANを切る必要はありません）

> ✅ **【検証1】**
> PC1から `ping 192.168.10.254` が通ることを確認します。
> （※この時点ではまだ、PC1から SRV1 `200.1.1.8` へはPingが通りません。インターネット側であるSRV1が、プライベートIPである `192.168.10.0/24` の戻りルートを知らないためです）

### 2. インターネットへ出るための「NAT (PAT)」を設定する
R1に、内部のプライベートIPをすべて R1 の外部インターフェースのグローバルIP（`200.1.1.1`）に変換するNAT Overload（PAT）を設定します。

- 内部（Inside）と外部（Outside）のインターフェース指定: `ip nat inside` / `ip nat outside`
- 変換対象の定義: `access-list 1 permit 192.168.10.0 0.0.0.255`
- NATの適用: `ip nat inside source list 1 interface e0/2 overload`

> ✅ **【検証2】**
> PC1からSRV1（`ping 200.1.1.8`）が通るようになります！
> そのPingを打った後、R1で `show ip nat translations` を確認し、`192.168.10.10` が `200.1.1.1` に変換された証拠を見つけてください。

### 3. 不要な通信を遮断する「拡張ACL」を設定する
R1の外部インターフェース（Outside）の「入力方向（in）」に、セキュリティフィルター（拡張ACL）をかけます。
- **要件1**: SRV1 からの「Pingの返事（echo-reply）」は許可する
- **要件2**: 外部からの不正な「Telnet（ポート23）」による侵入は明示的にログを残して拒否（deny）する
- **要件3**: その他の通信もすべて拒否する（暗黙のdeny）

```bash
R1(config)# access-list 100 permit icmp any any echo-reply
R1(config)# access-list 100 deny tcp any any eq 23 log
R1(config)# access-list 100 deny ip any any
R1(config)# interface e0/2
R1(config-if)# ip access-group 100 in
```

> ✅ **【検証3】**
> PC1からSRV1へのPingは引き続き通ります。
> しかし、SRV1側からR1宛てに `telnet 200.1.1.1` を試みると拒否され、さらにR1のコンソールに `%SEC-6-IPACCESSLOGP` というセキュリティブロックのログが出現します！

### 4. 物理的に不正アクセスを遮断する「Port Security」
最後に、社内のL2スイッチ（SW1）の e0/1（PC1が繋がっているポート）に対して、**「PC1のMACアドレスだけを許可し、違うPCが繋がれたらポートを強制シャットダウンする」** ポートセキュリティを設定します。

```bash
SW1(config)# interface e0/1
SW1(config-if)# switchport mode access
SW1(config-if)# switchport port-security
SW1(config-if)# switchport port-security mac-address sticky
SW1(config-if)# switchport port-security violation shutdown
```

> ✅ **【検証4】**
> 1. まずPC1から何でもいいのでPingを打ちます（これでPC1のMACアドレスがSW1に記憶＝stickyされます）。
> 2. SW1で `show port-security interface e0/1` を確認し、MACアドレスが登録されたことを見ます。
> 3. （**アタックテスト**）PC2のMACアドレスを意図的に偽装して、e0/1に繋がったと見せかけます。
>    ※コンテナの配線をいじる代わりに、PC1で一時的にMACアドレスを変更することでシミュレートできます。
>    ```bash
>    PC1(config)# interface e0/1
>    PC1(config-if)# mac-address 0000.1111.2222
>    ```
> 4. この状態でPC1からPingを打つと……SW1側で `%PM-4-ERR_DISABLE` が発動し、e0/1が強制シャットダウン（死）する様子を観察してください！
