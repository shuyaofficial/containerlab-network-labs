# パラメータシート② L2・MST・HSRP編（記入済）

## 1. VLAN定義
| VLAN ID | 名前 | 定義するスイッチ | 備考 |
|---|---|---|---|
| 10 | 営業部 | dist-a1, dist-a2, acc-a1 | 営業部 |
| 20 | 開発部 | dist-a1, dist-a2, acc-a2 | 開発部 |
| 901 | OSPF連携 | dist-a1, dist-a2 | ディストリ間L3連携 |
| 30 | サーバ | dist-b1, acc-b1 | サーバ |
| 99 | 管理 | dist-b1 | 運用管理 |

## 2. EtherChannel
| Po番号 | 機器ペア | メンバーポート | モード | トランク許可VLAN | 投入✅ |
|---|---|---|---|---|---|
| 1 | dist-a1 ⇔ dist-a2 | e0/3, e0/4 | active | 10, 20, 901 | <input type="checkbox"> |
| 1 | dist-b1 ⇔ acc-b1 | e0/3, e1/0 (acc-b1側 e0/1, e0/2) | active | 30 | <input type="checkbox"> |

## 3. MST
### A棟リージョン（dist-a1 / dist-a2 / acc-a1 / acc-a2 の4台共通）
| 項目 | 設計値（基本設計より） | 記入値 | 投入✅ |
|---|---|---|---|
| Region名 | CAMPUS-A | CAMPUS-A | <input type="checkbox"> |
| Revision | 1 | 1 | <input type="checkbox"> |
| インスタンス→VLANマッピング | MST1 = VLAN 10,20,901 | instance 1 vlan 10,20,901 | <input type="checkbox"> |
| Root Primary（MST1） | dist-a1 | priority: 4096 | <input type="checkbox"> |
| Root Secondary（MST1） | dist-a2 | priority: 8192 | <input type="checkbox"> |

### B棟リージョン（dist-b1 / acc-b1 の2台共通）
| 項目 | 設計値（基本設計より） | 記入値 | 投入✅ |
|---|---|---|---|
| Region名 | CAMPUS-B | CAMPUS-B | <input type="checkbox"> |
| Revision | 1 | 1 | <input type="checkbox"> |
| インスタンス→VLANマッピング | MST1 = VLAN 30,99 | instance 1 vlan 30,99 | <input type="checkbox"> |
| Root（MST1） | dist-b1 | priority: 4096 | <input type="checkbox"> |

### 予想されるブロッキングポート（記入してから構築で答え合わせ）
| 場所 | 予想 | 実測 |
|---|---|---|
| acc-a1 の上位2本のうちブロックされる側 | dist-a2側 (e0/2) | □ |
| acc-a2 の上位2本のうちブロックされる側 | dist-a2側 (e0/2) | □ |

## 4. HSRP（A棟）
| VLAN | グループ番号 | VIP | Active機 / 優先度 | Standby機 / 優先度 | preempt | トラッキング対象 / 減算値 | 投入✅ |
|---|---|---|---|---|---|---|---|
| 10 | 10 | 10.10.10.254 | dist-a1 / 110 | dist-a2 / 90 | yes | e0/1, e0/2 / 20 | <input type="checkbox"> |
| 20 | 20 | 10.10.20.254 | dist-a1 / 110 | dist-a2 / 90 | yes | e0/1, e0/2 / 20 | <input type="checkbox"> |

## 5. ポートセキュリティ・アクセス層保護
| 機器 | ポート | 最大MAC数 | 違反時動作 | 未使用ポート処置 | 投入✅ |
|---|---|---|---|---|---|
| acc-a1 | E0/3 | 1 | restrict | shutdown | <input type="checkbox"> |
| acc-a2 | E0/3 | 1 | restrict | shutdown | <input type="checkbox"> |
| acc-b1 | E0/3, E1/0 | 1 | restrict | shutdown | <input type="checkbox"> |
