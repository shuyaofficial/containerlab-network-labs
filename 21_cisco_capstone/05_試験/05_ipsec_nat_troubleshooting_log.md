# IPsec & NAT トラブルシューティング ログ（Theme 21 Capstone）

本ドキュメントは、Capstone演習における「IPsec VPNとNAT」の構築・試験時に発生したトラブルとその解決プロセスを記録したものです。今後のネットワークトラブルシューティングのナレッジとして活用してください。

## 1. NAT NVI (NAT Virtual Interface) の誤設定による通信断

### 事象
- HQ-Edge1からISP（8.8.8.8）へはPingが通るが、HQ-Core1からのPingがISPへ届かない（NAT変換が実行されていない）。

### 原因と分析
HQ-Edge1にて、NATの適用コマンドを入力する際、`inside` というキーワードが抜けていたことが原因です。
- ❌ 誤：`ip nat source list 100 interface Ethernet0/1 overload`
- ⭕ 正：`ip nat inside source list 100 interface Ethernet0/1 overload`

`inside` が抜けると、Cisco IOSはこれを「旧式の NVI (NAT Virtual Interface)」設定と解釈し、各インターフェースに設定された `ip nat inside / outside` のタグを完全に無視してしまいます。結果としてNATが発動せず、プライベートIPのままISPへパケットが送られ、ISP側で破棄されていました。

### 解決策
誤ったコマンドを削除し、正しいコマンドを投入して解決しました。
```cisco
conf t
no ip nat source list 100 interface Ethernet0/1 overload
ip nat inside source list 100 interface Ethernet0/1 overload
```

---

## 2. デフォルトルート（Gateway of last resort）の欠落によるVPN交渉失敗

### 事象
- BR-EdgeからHQ-Edge1の外部IP（200.0.1.1）へのPingが失敗する。
- IPsecトンネル（ISAKMP / ESP）が一切立ち上がらない。

### 原因と分析
BR-EdgeにBGPが設定されておらず、かつ「デフォルトルート（`0.0.0.0/0`）」も設定されていなかったため、BR-Edgeは「インターネット（ISPの先）への行き方」を全く知らない状態でした。
VPNの交渉パケット（UDP 500）すらインターネット側（HQ-Edge1）へ届かないため、トンネルが形成されません。

### 解決策
BR-EdgeにISP（200.0.3.254）を向くスタティックデフォルトルートを追加しました。
```cisco
conf t
ip route 0.0.0.0 0.0.0.0 200.0.3.254
```

---

## 3. IKEv2 Keyring 内の `address` パラメータ指定漏れ

### 事象
- IKEv2（Phase 1）の認証が通らず、IPsecトンネルが張れない。

### 原因と分析
HQ-Edge1の `crypto ikev2 keyring` 設定にて、ピアを識別する `address` コマンドが抜けていました。
```cisco
! 【エラーとなった設定】
crypto ikev2 keyring IKEV2_KEY
 peer 200.0.3.1
  pre-shared-key CiscoSecretKey123!
```
`peer 200.0.3.1` というのはただの「名前（ラベル）」であり、ルーターはこのラベル名だけでは相手のIPアドレスを特定できません。そのため、該当IPからのVPN接続要求に対して正しい事前共有鍵（PSK）を引き当てることができませんでした。

### 解決策
peerブロックの中に、明示的に `address` を追加しました。
```cisco
conf t
crypto ikev2 keyring IKEV2_KEY
 peer 200.0.3.1
  address 200.0.3.1
```

---

## 4. OSPFネットワーク追加漏れによる拠点間LAN通信不可

### 事象
- IPsecトンネル自体はUPし、ルーター間での暗号化通信（ESP）は成功している。
- しかし、本社のPC（10.1.10.100）から支社のPC（10.2.40.100）へのPingが失敗する。

### 原因と分析
BR-Edgeの `Tunnel0` ではOSPFが有効になっておりネイバーは張れていましたが、**BR-EdgeのLAN側インターフェース（`Ethernet0/2`）がOSPFに参加していませんでした**。
その結果、HQ-Edge1（およびその先のHQ-Core1）は「支社のネットワーク（10.2.40.0/24）」の存在（ルーティング）を知ることができず、パケットをデフォルトルート（ISP）へ投げてしまい通信断となっていました。

### 解決策
BR-EdgeのLAN側インターフェースでOSPFを有効化し、HQ側へルートを広報させることで解決しました。
```cisco
conf t
interface Ethernet0/2
 ip ospf 1 area 0
```

---

## 💡 【Tips】NAT ACLの「deny」と「permit」の正しい解釈

NATの適用条件を定義するACL（例：`access-list 100`）において、初心者が陥りやすい「`deny` だと通信が遮断されるのでは？」という疑問に対する回答です。

- セキュリティフィルタ（`ip access-group`）として使う場合の `deny` ＝ **「パケットを破棄しろ」**
- NATの仕分け（`ip nat inside source list`）として使う場合の `deny` ＝ **「NAT（IP変換）を行わず、元のIPのまま普通にルーティングしろ（NAT Exempt）」**

拠点間VPN（IPsec）では、LANからLANへの通信をパブリックIPに変換（NAT）してしまうとVPNトンネルに入れなくなるため、ACLの最初に `deny` を記述して「NATの対象から意図的に除外する」のが鉄則です。
