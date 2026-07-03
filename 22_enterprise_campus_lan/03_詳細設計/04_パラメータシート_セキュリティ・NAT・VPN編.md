# パラメータシート④ セキュリティ・NAT・VPN編（記入済）

> **このシートは基本設計を元に記入済みです。** 設計方針は [../02_基本設計/基本設計書.md](../02_基本設計/基本設計書.md) §6〜§8。
> 要件の許可/拒否マトリクス（[../01_要件定義/要件定義書.md](../01_要件定義/要件定義書.md) §2.3）を実装に落とします。

## 1. 部署間ACL（営業⇔開発の制限）
> ⚠️ 適用先はHSRP冗長ペアの**dist-a1とdist-a2の両方**（基本設計 §8。片方だけだと切替後にACLが消える＝試験 T-503）。

### 通信マトリクス
| 送信元＼宛先 | 営業(10.10.10.0/24) | 開発(10.10.20.0/24) | サーバ(10.20.30.0/24) | インターネット |
|---|---|---|---|---|
| 営業 | — | 拒否 (deny) | 許可 (permit) | 許可 (permit) |
| 開発 | 拒否 (deny) | — | 許可 (permit) | 許可 (permit) |

### ACL定義
| ACL名 | 適用先IF / 方向 | エントリ（上から評価・最後の暗黙denyに注意） | 投入✅ dist-a1 | 投入✅ dist-a2 |
|---|---|---|---|---|
| ACL_VLAN10_IN | VLAN10 / IN | deny ip 10.10.10.0/24 10.10.20.0/24, permit ip any any | <input type="checkbox"> | <input type="checkbox"> |
| ACL_VLAN20_IN | VLAN20 / IN | deny ip 10.10.20.0/24 10.10.10.0/24, permit ip any any | <input type="checkbox"> | <input type="checkbox"> |

> 💡 考えどころ: 「開発→サーバは許可、開発→営業は拒否」をSVIの**どちら向き(in/out)**に置くか。
> 送信元VLANの SVI の IN 方向でドロップさせるのが最も無駄なルーティングを防ぐベストプラクティスです。

## 2. 境界ポリシー・NAT
> 2026-06-26のCisco置換版では `fgt-edge` はCisco IOLルーターとして動作しているため、下表のFortiGate IPv4 policy / SNATは対象外。FortiGate版またはASAv版でFW/NAT学習へ戻る場合の設計メモとして残す。

| ポリシーID | 送信元IF→宛先IF | 送信元アドレス | 宛先アドレス | サービス | アクション | NAT | 投入✅ |
|---|---|---|---|---|---|---|---|
| Policy1 | port3,4 → port2(WAN) | all (10.0.0.0/8) | all | all | accept | SNAT Enable (port2 IP) | <input type="checkbox"> |
| Policy2 | VPN(Tunnel) → port3,4 | 10.2.40.0/24 | 10.20.30.0/24 | all | accept | SNAT Disable | <input type="checkbox"> |
| Policy3 | port3,4 → VPN(Tunnel) | 10.20.30.0/24 | 10.2.40.0/24 | all | accept | SNAT Disable | <input type="checkbox"> |

> 💡 FortiGateは「ポリシーに一致しない通信は暗黙拒否」。WAN→社内のポリシーを作らないこと自体が防御になる。

## 3. 支社NAT（br-edge）
| 項目 | 設定内容 | 投入✅ |
|---|---|---|
| inside / outside の指定 | inside: e0/2, outside: e0/1 | <input type="checkbox"> |
| 変換対象（ACL） | VPN通信(本社サーバ宛)を除外した上で 10.2.40.0/24 を許可 | <input type="checkbox"> |
| 変換方式 | PAT (overload) | <input type="checkbox"> |

> 💡 考えどころ（VPN×NATの古典トラブル）: 支社→本社サーバの通信がPATで200.0.3.1に変換されてしまうと、
> VPNポリシー（送信元10.2.40.0/24のみ許可）に一致しなくなるため、**NAT Exempt（除外）ACL**の設計が必須です。

## 4. サイト間IPsec VPN（Cisco HQ edge ⇔ Cisco BR edge・route-based/IKEv2）
> FortiGate版はinvalid license/転送制限疑いで保留。Cisco置換版では両端Cisco IOS系のVTIとして明示的に揃える。

### Phase1（IKEv2）
| 項目 | fgt-edge側 | br-edge側 | 一致✅ |
|---|---|---|---|
| 認証方式 / PSK | pre-shared key (cisco123等) | pre-shared key (cisco123等) | <input type="checkbox"> |
| 暗号化 | des | des | <input type="checkbox"> |
| ハッシュ/PRF | sha256 | sha256 | <input type="checkbox"> |
| DHグループ | 14 | 14 | <input type="checkbox"> |
| ピアアドレス | 200.0.3.1 | 200.0.1.1 | <input type="checkbox"> |

### Phase2（IPsec SA）
| 項目 | fgt-edge側 | br-edge側 | 一致✅ |
|---|---|---|---|
| 暗号化/認証 | esp-des / sha256-hmac | esp-des / sha256-hmac | <input type="checkbox"> |
| PFS / DHグループ | Group 14 | Group 14 | <input type="checkbox"> |
| セレクタ | 0.0.0.0/0 ⇔ 0.0.0.0/0（VTI） | 0.0.0.0/0 ⇔ 0.0.0.0/0（VTI） | <input type="checkbox"> |

### トンネルインターフェース・経路
| 項目 | fgt-edge側 | br-edge側 | 投入✅ |
|---|---|---|---|
| トンネルIF名 / IP | Tunnel1 / 172.16.40.1/30 | Tunnel1 / 172.16.40.2/30 | <input type="checkbox"> |
| トンネル宛スタティック経路 | 10.2.40.0/24 → トンネルIF | 10.20.30.0/24 → トンネルIF | <input type="checkbox"> |

## 5. L2保護・管理アクセス
| 項目 | 設定内容 | 投入✅ |
|---|---|---|
| ポートセキュリティ | （シート②で記入済み） | <input type="checkbox"> |
| 未使用ポート | 全て shutdown | <input type="checkbox"> |
| 機器への管理アクセス | SSH/Telnet有効化、vtyへのログイン設定等 | <input type="checkbox"> |
