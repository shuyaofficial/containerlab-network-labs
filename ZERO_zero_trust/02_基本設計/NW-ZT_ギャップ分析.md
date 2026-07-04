---
type: feasibility
theme: "ZERO_zero_trust"
status: draft
date: 2026-07-04
tags: [zero-trust, gap-analysis, nac, ndr, ztna, network]
title: "テーマZERO｜NW-ZT ギャップ分析（ネットワーク側ゼロトラストの被覆度）"
---

# テーマZERO｜NW-ZT ギャップ分析（ネットワーク側ゼロトラストの被覆度）

L7 トラック（Phase 0-6、docker 完結）が「クラウド/アプリ寄りのゼロトラスト」をどこまで押さえ、**ネットワーク側のゼロトラスト**（NAC・NDR・SDP型ZTNA・μセグ）に何が欠けているかを、NIST SP 800-207 系の5レイヤーで棚卸しする。埋め方は NW-ZT トラック（N1-N4）へつなぐ。

## 分析のスコープと視点

- **視点**: NW エンジニアの本業（スイッチ/ルータ/L2-L3/認証基盤）から見て、実務で語れる「ネットワークのゼロトラスト」がラボで扱えるか。
- **レイヤー定義**: 貼付の5レイヤー（①ZTNA ②NAC/SDA ③μセグ ④IdP/IAM ⑤EDR/UEM）に、運用面の SIEM/NDR を加えて棚卸しする。ベンダー軸でなく**技術軸**で見る（ZTNA/NDR 等）。
- **原則**: 欠落は「欠陥」ではなく L7 トラックの D-1（IOL 非連携）による**スコープの線引き**の結果である。

## 被覆度マトリクス（5レイヤー × ZERO 現状 × 埋め方）

| # | レイヤー | 主な技術 | ZERO L7 トラックの現状 | 被覆度 | 埋め方（NW-ZT） |
|---|---|---|---|---|---|
| ④ | IdP / IAM | OIDC/SAML SSO、MFA、動的認可 | Phase 1 Keycloak（OIDC IdP）＋ Phase 2 Pomerium（認可ポリシー） | ✅ 充足 | 既存を N1/N2 の認証源として再利用 |
| ① | ZTNA | SDP、IAP、リバースプロキシ | Phase 2 は **IAP型**（Pomerium＝アプリ前関所）。**SDP型**（ZPAの broker+connector・内向き非開放）は発展止まり | 🔺 IAP型のみ | **N2**: OpenZiti で SDP 型を体験 |
| ⑤ | EDR / ポスチャ | 振る舞い検知、デバイスコンプライアンス | Phase 6 step-ca mTLS ＋ posture claim モック（osquery は arm64 非対応で代替） | 🔺 モック | N3 の NDR で「感染後の振る舞い」を補完。EDR 本体は範囲外（教材で商用を解説） |
| ③ | μセグメンテーション | ホスト分散FW、SGT タグ、east-west 制御 | docker bridge 4ゾーン分離のみ。ホスト間分散FW・east-west 制御なし | 🔺 ゾーンのみ | **N4**: IOL VLAN/ACL ＋ ホスト nftables の二層μセグ |
| ② | NAC / 802.1X | 802.1X/MAB、動的VLAN、CoA | **未カバー**（L7 トラックは L2 を持たない） | ❌ **最大の欠落** | **N1**: FreeRADIUS ＋ Cisco IOL L2 |
| — | SIEM | ログ集約・相関分析 | Phase 3 Loki + Grafana | ✅ 充足 | N3 のフロー/検知ログの集約先に再利用 |
| — | NDR | フロー分析、DPI 振る舞い検知 | Phase 4 Suricata は SWG 経路の IDS のみ。**east-west ミラー/フロー分析なし** | ❌ 欠落 | **N3**: Zeek/Suricata ＋ NetFlow(goflow2)→Loki/Grafana |
| — | SOAR | 自動封じ込め（プレイブック） | なし | ❌ 欠落 | 任意: Grafana アラート→webhook で Keycloak 無効化/Pomerium ポリシー変更（N2/N3 の発展） |

## ギャップの重大度

1. **② NAC/802.1X = 最優先の欠落**。オンプレ LAN の「社内だから安全」を排除する入口制御で、NW エンジニアの本業ど真ん中。Cisco スキル（スイッチ設定）と直結し、転職市場でも語れる。→ **N1 を先頭に置く**。
2. **NDR = 二番目の欠落**。「侵害前提」を成立させる可視化。既存 SIEM（Loki/Grafana）に乗るため追加コストは中。→ **N3**。
3. **① SDP型ZTNA**。IAP型は L7 トラックで実装済みだが、Zscaler ZPA の「内向きを一切開けない」モデルは体験していない。→ **N2**。
4. **③ μセグ**。ゾーン分離はあるが、TrustSec/SGT 的な east-west 最小権限化は未着手。N1 の VLAN 基盤に依存。→ **N4**。

## 埋め方と NW-ZT トラックの対応

| ギャップ | 埋める N | 主 OSS | 商用の対応（教材で解説） |
|---|---|---|---|
| NAC/802.1X | N1 | FreeRADIUS + Cisco IOL L2 | Cisco ISE / Aruba ClearPass |
| SDP型ZTNA | N2 | OpenZiti（発展: Headscale/Netbird） | Zscaler ZPA / Cisco Secure Access |
| NDR | N3 | Zeek/Suricata + goflow2 + ntopng | Darktrace / Cisco Secure Network Analytics |
| μセグ | N4 | IOL VLAN/ACL + ホスト nftables | Cisco TrustSec/SGT / Illumio |

詳細なフェーズ設計は [NW-ZT_トラックロードマップ](NW-ZT_トラックロードマップ.md)、論理構成は [NW-ZT_論理構成設計](NW-ZT_論理構成設計.md)、商用製品の仕組みは [教材](../教材/README_教材ガイド.md) を参照。

## 結論

L7 トラックは「クラウド/アプリ寄りの ZT」を良く押さえている。NW-ZT トラック（N1-N4）を増設することで、**NW エンジニア本業の「ネットワーク側 ZT」を技術軸で被覆**でき、かつ全て OSS × arm64（IOL 部分を除く）で実装見込みが立つ。実装可能性の実測は [軽量検証計画_nwzt](../03_詳細設計/軽量検証計画_nwzt.md) で確定する。

## 参照

- [基本設計書](基本設計書.md)（D-7: NW-ZT トラックの IOL 連携解禁）
- [NW-ZT_トラックロードマップ](NW-ZT_トラックロードマップ.md)
- [NW-ZT_論理構成設計](NW-ZT_論理構成設計.md)
- [教材ガイド](../教材/README_教材ガイド.md)
- [ロードマップ PHASE2](../../ロードマップ/PHASE2_MODERN_ENTERPRISE.md)（実装委譲先の番号テーマ）
