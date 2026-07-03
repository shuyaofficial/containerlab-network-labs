# 作業ログ: テーマ23 Collapsed Core のL2全断（Split Brain / HSRP unknown）根本原因特定と修正

## 発生日時
2026-06-29

## 事象
- Collapsed Core（coredist1/2, access1/2 + pc1/2/3）で **L2が一切通らない**。
  - `show spanning-tree vlan 10` で coredist1 / coredist2 の **両方が "This bridge is the root"**（Split Brain）。
  - HSRP の Standby が永遠に `unknown`。
  - インターフェースは UP/UP、Trunk・VLAN(10,20)・`switchport trunk allowed vlan 10,20` は設定済み。
- これは設定ミスではなく、**コンテナ内の veth↔IOL ブリッジ(`iouyap`) が正しく動いていない**ことが原因だった。
- 同じ問題は **テーマ22(22_enterprise_campus_lan) で 2026-06-19 に解決済み**で、テーマ23だけが古い・壊れた起動方式のまま取り残されていた。

## 切り分けプロセス
1. 公式ドキュメント(containerlab cisco_iol)とテーマ22の実績構成を確認。
   - コンソールは **SSH / `docker exec`** が公式。`docker attach` は使わない。
   - L2ノードは **`type: l2`** が必須。
   - 旧2017タグ・15.x由来イメージの stock entrypoint は **iouyap を自動起動しない世代**で、テーマ22は deploy 後に手動起動して開通させていた。
2. 実績比較（決定的証拠）：

   | | テーマ22(動く) | テーマ23(壊れ) |
   |---|---|---|
   | カスタムentrypoint | 無し(stock) | 有り(壊れたiouyap) |
   | `type: l2` | 全ノード有り | **無し** |
   | iouyap起動 | deploy後 `iouyap 513`(`-w /iol`) | entrypoint内 `iouyap $IOL_PID`(誤) |
   | コンソール | SSH | docker attach(固まる) |

3. テーマ23の `entrypoint_fixed.sh:29` を確認し、誤起動を特定。

## 根本原因
### 主因A：`iouyap` の起動引数が壊れていた
`entrypoint_fixed.sh` の
```bash
( sleep 2 ; /usr/bin/iouyap $IOL_PID ) &
```
- `$IOL_PID` は containerlab が各ノードに振る **IOLインスタンスID（1,2,3…）**。`iouyap` の第1引数は本来 **NETIOベースポート=`513`**。インスタンスIDを渡すと IOL本体(`iol.bin 3`)が握る NETIO ID 3 と衝突し **`PID xx already has a lock on ID 3`** で iouyap が即死。
- `-f /iol/iouyap.ini -n /iol/NETMAP` と作業ディレクトリ `/iol` の指定が無く、起動してもブリッジ表が無いため **ブラックホール**（input=0：2026-06-19 incident と同症状）。
- 手動リトライ `/usr/bin/iouyap 3 &` も同じ誤り（ポート3・ini/NETMAP無し）で「ログは出るがL2は通らない」ままだった。
- **教訓：「iouyap が起動している」≠「iouyap が橋渡ししている」。**

### 主因B：`type: l2` 未指定
`campus.clab.yml` の4ノードに `type: l2` が無かった（テーマ22は全ノード付与）。cisco_iol kind はこのフィールドでL2/L3を区別する。

### 副次：カスタム entrypoint 自体が有害
- `docker attach` 固まり回避を動機に `iol.bin` を `exec` 無し起動していたが、コンソールは SSH/`docker exec` が公式で、PID1回避は不要だった。
- `-c config.txt` を使うため **containerlab の startup-config 自動注入（SSH/admin/admin・hostname・mgmt）をバイパス**していた。
- ライセンス(`.iourc`)注入もテーマ22が示す通りイメージにビルド時同梱済みで、ランタイム注入は不要だった。

## 解決策（テーマ22方式に揃える）
対象: `23_campus_collapsed_core/04_構築/`

1. **`campus.clab.yml`**：4 cisco_iol ノードから `binds: ./entrypoint_fixed.sh:/entrypoint.sh:ro` を撤去し、`kind: cisco_iol` 直後に **`type: l2`** を追加。
2. **`deploy.sh`（新規）**：`containerlab deploy` の後に、全IOLノードへ正しい引数で iouyap を起動。
   ```bash
   for c in $(sudo docker ps --format '{{.Names}}' \
               | grep '^clab-campus-collapsed-core-' | grep -v -E 'pc[0-9]'); do
     sudo docker exec -d -w /iol "$c" /usr/bin/iouyap 513 2>/dev/null || true
   done
   ```
   ポイント：**`513`**（インスタンスIDではない） + **`-w /iol`**（iouyap.ini/NETMAP をカレントで参照）。
3. **`entrypoint_fixed.sh`**：先頭に非推奨バナーを付与。どのノードからも bind しない（記録目的で残置）。
4. **コンソール接続**：`docker attach` をやめ、`ssh admin@clab-campus-collapsed-core-coredist1`（admin/admin）または `docker exec -it <node> bash`。

### 検証手順（構築はユーザー本人が実施）
1. `docker exec <c> ps aux | grep iouyap` → `513` で常駐・`lock on ID` ログが無いこと。
2. IOL CLI：`show cdp neighbors`（隣接表示）／`show interfaces Et0/2 | inc packets`（**input が増える**）。
3. `show spanning-tree vlan 10` → Root が1台に収束（Split Brain 解消）。
4. `show standby brief` → Active/Standby 確立（`unknown` 解消）。
5. pc1→pc3（VLAN10）ping → VLAN間（10⇄20）ping。

ロールバック：`./deploy.sh destroy` 後、変更前の `campus.clab.yml` に戻すだけ（可逆）。

## 実機適用・検証（2026-06-29、Claudeが clab VM 上で実施）
ユーザー依頼により、OrbStack「clab」VM 上の稼働ラボを **非破壊で**（デバイス設定は触らず）診断・修正。
- **現状**: ユーザーは既に修正版 yaml で再デプロイ済み（mounts にカスタム entrypoint 無し、`clab-node-type=l2` 確認）。だが `./deploy.sh` ではなく `containerlab deploy` を直接実行したため **iouyap 起動ステップが未実行**だった。
- **確定診断**: 全4ノードで `iouyap` プロセス = **0**（`/proc/*/cmdline` で確認）。`iol.bin`(qemu-i386) は稼働、`/iol/iouyap.ini`・`NETMAP` は clab 生成で正常（IOLインスタンス=3 ↔ iouyap port=513）。→ HSRP standby unknown の主因＝iouyap 未起動で確定。
- **適用**: 全4ノードに `docker exec -d -w /iol <node> /usr/bin/iouyap 513` を実行。4台とも `iouyap 513` で常駐、`lock on ID` エラー無し。
- **検証(L2開通)**: 各トランクの TX↔RX が完全一致（576↔576 / 577↔577 / 583↔583 / 305↔305 等）。修正前 RX=0 のブラックホールが両方向疎通に回復。BPDU/HSRP/CDP が流れ始めた。
- **未確認(ユーザー側)**: `show standby brief` の Standby 表示は各自コンソールで確認（mgmt SSH 172.20.20.x は L2イメージのEt0/0ルーテッドmgmtの癖で ARP 不応答＝本件のL2データプレーンとは別問題、任意対応）。
- **注意（揮発性）**: 今回の iouyap 起動は稼働中コンテナへの手動適用。`destroy`→`deploy` 時は必ず `./deploy.sh deploy`（または plain deploy 後に `./deploy.sh iouyap`）で再起動すること。

## 追記2：iouyap 修正後も残った「standby unknown」＝第2の原因（デバイス設定）
iouyap 修正で L2 ファブリックは開通（coredist1 の `show cdp neighbors` が coredist2/access1/access2 を全て表示）。だが HSRP は依然 `standby unknown`・両コア Split Brain のまま。実機を切り分けた結果、**iouyap とは別の、coredist2 のコンフィグ不備**が判明。

- **access1（正常）**: `show spanning-tree vlan 10` で Root = coredist1(aabb.cc00.0300) を正しく認識、Et0/2(coredist2向け)=Desg FWD。トランクは VLAN10,20 が allowed **かつ active**。→ access 層は健全で、coredist1 の BPDU を coredist2 側へ中継している。
- **coredist2（異常）**:
  - `show spanning-tree vlan 10` → **「Spanning tree instance(s) for vlan 10 does not exist.」**
  - `show interfaces trunk` → Et0/2,Et0/3 は VLAN10,20 が *allowed* だが **「allowed and active … none」「forwarding state … none」**。
  - `show vlan brief` → **VLAN 10 / 20 がデータベースに存在しない**（VLAN1 と既定1002-1005のみ）。
- **根本原因（第2）**: coredist2 の **VLANデータベースに VLAN 10/20 が無い**。SVI(`interface vlan 10`)を作っても L2 VLAN は自動生成されない。L2 VLAN が無いため、coredist2 はトランク上の VLAN10/20 フレーム（STP BPDU・HSRP Hello）を処理できず、STPインスタンス未生成・SVIダウン・HSRP不参加 → coredist1 から見て standby unknown、両コア Split Brain。
- **対応**: coredist2（必要なら全ノード）で VLAN 10/20 を VLANデータベースに作成する。**設定投入はユーザー本人**（本ラボは自分で設定を考えて投入する学習課題のため、コマンドは記載しない）。作成後、VLAN10/20 の STP インスタンス生成 → SVI Up → HSRP 収束 → Split Brain 解消を確認する。
- パラメータシート設計値の再確認推奨: CoreDist1=VLAN10 Root Primary(4096)/VLAN20 Secondary(8192)、CoreDist2=VLAN10 Secondary(8192)/VLAN20 Root Primary(4096)。HSRP Active と STP Root を一致させる（達成条件#1,#2）。

## 追記3：解決（2026-06-29）— SVIダウンが最後の関門だった
VLAN作成後も `standby unknown` が残ったため再追跡。coredist2 の HSRP は **State=Init「interface down」**＝SVI Vlan10/20 自体がダウンしていた。SVI(`interface VlanX`)は autostate により「当該VLANが trunk 上で active かつ STP forwarding」になって初めて line-protocol up する。VLANデータベース作成→trunkでVLAN active→SVI Up の連鎖が揃った時点で HSRP が Init を脱し収束。

最終確認（coredist1 `show standby brief`）:
- Vl10: **Active**(pri110)/Standby=10.10.10.252(coredist2)
- Vl20: **Standby**/Active=10.10.20.252(coredist2)
→ `unknown` 解消、VLANごとに Active を分ける負荷分散（達成条件#1・#2）も成立。**RESOLVED**。

### 原因の全体像（同一症状 standby unknown に3層が重なっていた）
1. インフラ: iouyap 未起動（Claudeが `iouyap 513`/`-w /iol` で修正・確認）。
2. 設定: coredist2 の VLANデータベースに VLAN10/20 が無い（ユーザーが作成）。
3. 連鎖: VLAN作成だけでは SVI が上がらず、trunkでVLAN activeになりSVIがautostateでUp→HSRP収束（自然解消）。

### 残タスク（ユーザー）
- STPルート配置が設計通りか（CD1=VLAN10 Root/CD2=VLAN20 Root）を `show spanning-tree root` で確認。
- PC間 end-to-end（達成条件#4, #5）。※Linuxコンテナ(network-multitool)をIOLアクセスポートに繋ぐと `%AMDP2_FE-6-EXCESSCOLL`（duplex不一致のエミュレータ既知バグ、切り分けノート#2）が出て不通になる場合あり。出たら該当ポートで speed/duplex 固定 か 擬似PCをIOL化で回避。

## 担当
- 根本原因特定・部材(yaml/deploy.sh/entrypoint非推奨化)修正：Claude
- 実デプロイ・STP/HSRP等のデバイスCLI設定・試験：ユーザー本人（学習対象）

## 参考
- containerlab Cisco IOL: https://containerlab.dev/manual/kinds/cisco_iol/
- packetswitch「Running Cisco IOL Devices in Containerlab」: https://www.packetswitch.co.uk/running-cisco-iol-devices-in-containerlab/
- 関連: `22_enterprise_campus_lan/04_構築/logs/2026-06-19_iouyap_incident.md`（同根の先行事例）
