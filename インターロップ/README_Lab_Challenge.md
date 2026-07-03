# Interop Tokyo 2026 ShowNet 再現ラボ

## 目的

- Interop Tokyo 2026 ShowNet を、Containerlab で動かせる軽量MVPとして抽象再現する。
- 完全コピーではなく、ShowNet 2026 の主要テーマを手元で観察できる構成に落とす。
- 既存の Theme 22 `../22_enterprise_campus_lan/` は変更・削除・redeploy・destroy しない。

## Theme 22 保護ルール

- このフォルダ以外へはファイルを追加・修正しない。
- lab name は `interop-shownet` を使う。Theme 22 の `campus` とは別名。
- 管理ネットワークは `interop-mgmt` / `172.20.30.0/24` を使う。Theme 22 の `172.20.20.0/24` とは分離。
- `containerlab destroy --all` や `docker rm` の広域削除は使わない。
- Theme 22 を止める必要がある場合でも、このラボ側からは操作しない。

## 再現するShowNet要素

| ShowNet 2026要素 | このラボでの再現 |
|---|---|
| AS290 / Peering Portal / 対外接続 | `edge-n1`, `edge-n2` を AS290 相当、`ext-bbix`, `ext-jpix` を外部ASとして eBGP |
| 高速バックボーン / SRv6 uSID L3VPN | Cisco IOL制約のため、OSPF + iBGP + VRF風の設計文書で抽象化 |
| IOWN APN / 大容量トランスポート | `transport-n4` を APN/長距離トランスポート相当として配置 |
| Media over IP | `media-x`, `yokohama-foh`, `hamamatsu-mocap` の3拠点をUDP疎通で検証 |
| AI Grid / 統合監視 | `monitor-ai` から ping/traceroute/UDP の観測点を提供 |
| サイバー脅威検出 / セキュアリモートアクセス | `sec-s4`, `remote-s5` で管理アクセス制限を抽象再現 |

## ファイル構成

| パス | 内容 |
|---|---|
| `interop-shownet.clab.yml` | Containerlabトポロジ |
| `index.html` | 物理構成図・技術説明のHTML |
| `config/*.cfg` | Cisco IOL初期config |
| `01_research/ShowNet2026調査メモ.md` | 公式情報・写真からの抽出 |
| `02_design/基本設計.md` | 役割・技術マッピング・制約 |
| `02_design/IPアドレス管理表.md` | IPアドレスとリンク表 |
| `04_構築/構築ログ_テンプレート.md` | 構築時の記録テンプレート |
| `05_試験/試験計画書.md` | 試験項目 |
| `tools/deploy_interop.sh` | 新規ラボだけをdeployする補助スクリプト |
| `tools/start_iouyap.sh` | Cisco IOLのデータプレーン補助 |

## デプロイ手順

```bash
ssh clab@orb
cd /Users/shuya/Documents/claude/Mac仮想環境構築/インターロップ
sudo containerlab inspect --all
./tools/deploy_interop.sh
```

Theme 22 が起動中でリソースが重い場合は、先にこのラボの静的確認だけ行う。

```bash
python3 - <<'PY'
import yaml
with open("interop-shownet.clab.yml", "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)
print(data["name"], len(data["topology"]["nodes"]), len(data["topology"]["links"]))
PY
```

## 基本確認コマンド

```text
show ip interface brief
show ip ospf neighbor
show ip route ospf
show ip bgp summary
show ip bgp
show access-lists
```

Linuxノードでは次を使う。

```bash
ping 10.90.41.10
traceroute 10.90.42.10
nc -u -l -p 5004
printf shownet-media-test | nc -u 10.90.41.10 5004
```

## 参考リンク

- [ShowNet 2026公式](https://www.interop.jp/2026/shownet/concept/)
- [ShowNetセッション](https://www.interop.jp/2026/shownet/session/)
- [Yamaha Media over IP発表](https://prtimes.jp/main/html/rd/p/000001141.000010701.html)
- [NTT IOWN APN発表](https://www.ntt.com/about-us/press-releases/news/article/2026/0610.html)
