# 監視と運用（Syslog / SNMP / NetFlow）チャレンジ：パラメータシート形式

このドキュメントは、ネットワーク監視における実務の「要件定義（パラメータシート）」を記載したチャレンジ用資料です。
今回はルーター（R1）から、監視専用のLinuxサーバー（NMS）に対して様々なログや稼働状況を飛ばす設定を行います。

---

## 🎯 トポロジとIPアドレス設計

### ログイン情報
- **PC1 (ルーター兼用)**: `telnet 172.20.20.4` (ユーザー/パス: `admin` / `admin`)
- **R1**: `telnet 172.20.20.3` (ユーザー/パス: `admin` / `admin`)
- **NMS (Linuxサーバー)**: `docker exec -it clab-monitoring-nms bash` (または `ssh 172.20.20.2` / パスワードなし)

### インターフェース設計
**【クライアント側】**
- PC1 (e0/1): `192.168.10.10 /24` （GW: `192.168.10.254`）
- R1 (e0/1): `192.168.10.254 /24` （PC1側）

**【監視サーバー側】**
- R1 (e0/2): `10.0.0.254 /24` （NMS側）
- NMS (e0/1): `10.0.0.100 /24` （GW: `10.0.0.254`）

---

## 🏗️ 設定パラメータ要件

### 要件1：IPアドレスとルーティングの基礎
各機器に上記のIPを設定し、疎通を確保してください。（PC1には `no ip routing` とデフォルトゲートウェイを設定。NMSはコンテナデプロイ時に自動でIPが振られるようになっていますが、ルーティングを確認してください）

> ✅ **【検証1】**
> PC1 から NMS（`ping 10.0.0.100`）へPingが通ることを確認。

---

### 要件2：Syslog（システムログ）の転送設定（R1にて）
R1上で発生したエラーログ（例: インターフェースのDown/Upなど）を、NMS（Linuxサーバー）に自動転送する設定を行います。

| 項目 | 指定パラメータ |
|---|---|
| ログの送信先 (Host) | NMSのIPアドレス (`10.0.0.100`) |
| 送信するログレベル (Traps) | **informational** (情報レベル以上すべて) |
| タイムスタンプ機能 | ログに日時を含める (`service timestamps log datetime msec`) |

💡 **【構造のヒント】**
```bash
R1(config)# logging host [NMSのIP]
R1(config)# logging trap informational
R1(config)# service timestamps log datetime msec
```

---

### 要件3：SNMP（簡易ネットワーク管理プロトコル）の設定（R1にて）
NMSからR1の健康状態（CPU使用率、ポートの状態など）を「監視・ポーリング」できるように、SNMPの受け入れ口（エージェント）を設定します。今回は簡易的な v2c を使います。

| 項目 | 指定パラメータ |
|---|---|
| コミュニティ名 (Community) | **public** (パスワードのようなもの) |
| 権限 | **RO** (Read-Only: 読み取り専用) |
| SNMPトラップ送信先 (Host) | NMSのIPアドレス (`10.0.0.100`) |
| 有効化するトラップ | 全て (`snmp-server enable traps`) |

💡 **【構造のヒント】**
```bash
R1(config)# snmp-server community [コミュニティ名] RO
R1(config)# snmp-server host [NMS的IP] version 2c [コミュニティ名]
R1(config)# snmp-server enable traps
```

### 🏁 最終検証（NMS側での確認）
設定が完了したら、実際に **NMS（Linuxサーバー）** にログインして、R1からのデータを受信・取得できるかテストします。

#### 1. LinuxサーバのIP設定
Linuxサーバコンテナの `eth1` にIPアドレスを設定し、R1と通信できるようにします。
```bash
NMS# ip addr add 10.0.0.100/24 dev eth1
NMS# ip link set eth1 up
```

#### 2. Syslogの受信テスト
まず、**NMS（Linuxサーバー）**に入り、Syslogの受信ポート（UDP 514番）で待ち受けるプログラム（Netcat）を起動します。
```bash
NMS# nc -ul -p 514
```
この状態のまま、別のターミナルを開くか、R1のコンソールで意図的にインターフェースを落とします。
```bash
R1(config)# interface e0/1
R1(config-if)# shutdown
R1(config-if)# no shutdown
```
すると、待ち受けているNMSの画面上に `Interface Ethernet0/1, changed state to administratively down` というログがリアルタイムに飛んでくれば大成功！

#### 3. SNMPポーリングテスト
**NMS（Linuxサーバー）**から、R1に対して「お前の名前は何だ？」とSNMPで質問（ポーリング）を投げます。
```bash
NMS# snmpwalk -v 2c -c public 10.0.0.254 sysName
```
→ `SNMPv2-MIB::sysName.0 = STRING: R1` のように、R1のホスト名が返ってくればSNMPポーリング大成功！
（※ `sysDescr` に変えると、Cisco IOSのバージョン情報などがドバーッと取得できます）
