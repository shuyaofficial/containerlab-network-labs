# 実務案件ログ（マスキング済み・参照用）

実務で扱った／参照した3案件のネットワーク技術棚卸し（**マスキング済み**）。
顧客名・案件名・拠点名・IPアドレス・機器固有名・ファイル名・認証情報などは除外済みで、**機密は含まない**。
ここは原本の保管庫で、これを学習計画に落とし込んだのが親フォルダの
[`../実務案件_再現ロードマップ.md`](../実務案件_再現ロードマップ.md)。

| ファイル | 案件の「顔」 | 濃い領域 |
|---|---|---|
| `1ch案件ネットワーク技術.log` | 報道/通信社系 | VRF分離×iBGP/eBGP×HSRPv2＋FortiGate多VDOM、監視/フロー分析(NDR/NetFlow/IPFIX)、特権アクセス(CyberArk/PIM)、MQ/NewsML |
| `Boat案件ネットワーク技術.log` | 店舗/集配信系 | Catalyst中心の王道キャンパス。L2冗長(PVST+/Flex Link+/L2ループ防止/Stack)とQoS(優先制御/帯域制御装置) |
| `C案件.log` | DC/クラウド/ゼロトラスト系 | NTTキャリア閉域網(Arcstar/UNO/FIC)＋AWS/Azure/OCI、ASA/Firepower→FortiGate更改、Zscaler/ZPA/ZIA/FRA、BIG-IP、Smart Licensing |

> 出典: `~/Downloads/天野秀哉-selected/` のコピー（2026-06-26時点）。
