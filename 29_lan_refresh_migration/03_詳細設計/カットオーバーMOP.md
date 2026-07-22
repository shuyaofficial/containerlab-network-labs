# カットオーバーMOP: 社内LAN更改・移行・移設

## 0. 本書の読み方
- 本書は、移行計画書§3「移行フェーズ計画」（P0〜P8）を、実際に投入するコマンドレベルまで落とし込んだ作業手順書（MOP: Method of Procedure）である。各フェーズの設計根拠は基本設計書、コマンドの解答例はパラメータシートを参照すること。
- 各フェーズの表は、**No**（フェーズ内通番）／**T+目安**（作業開始T+0からの経過時間目安、移行計画書§6のスケジュールに対応）／**作業（投入コマンド）**／**確認（コマンド＋期待値）**／**切り戻し判断基準**／**実績記入欄**の6列で構成する。
- 「作業」列が「（なし）」の行は、コマンド投入を伴わない確認専用の手順である。
- **実績記入欄**は、実際の作業日に実施結果（実施時刻・実測値・確認者名等）を記入するための空欄であり、常に未記入の状態で運用する。
- 一部のセルには **「（Mission 2で記入）」** という空欄がある。これはコマンド投入のミスではなく、要件定義書・基本設計書・IPアドレス管理表・移行計画書の内容から学習者自身が導出して埋めるべき箇所として意図的に空欄にしてある（Mission 2「移行計画策定」の文書ミッションで完成させる）。
- 切り戻しが必要と判断した場合は、本書ではなく**切り戻し手順書**の該当フェーズの手順に従うこと。

## 断時間測定手順・トラップエビデンス保存手順（P2実施前に必ず準備する）
GWカットオーバーを伴うP2・P4・P5・P6・P7では、以下の手順で断時間を定量測定し、証跡を保存する。

### 断時間測定
1. nmsで対象GWに対し `ping -i 0.2 <対象GWアドレス> | tee /tmp/cutover_<対象>.log` を開始し、開始時刻を実績記入欄に記録する（`-i 0.2`＝200ms間隔。非rootユーザーが指定できる最小間隔）。
2. GW切替作業（各フェーズの作業列）を実施する。
3. 疎通が安定して復旧したことを確認したら、pingを停止しログを確認する。
4. ログ中の応答なし（`Request timeout`等の欠落行）の行数（損失数）を数える。
5. **損失数 × 0.2秒 ＝ 概算断時間**として算出する。要件定義書§3の許容値（60秒以内）に対応する許容損失数の上限は、P2-6にて学習者自身が算出する。
6. 算出した断時間を、各フェーズの実績記入欄に記入する。

### トラップエビデンス保存
1. nmsで`snmptrapd`を受信待機状態にしておく。**前提として、net-snmp（snmptrapd含む）はP0（本フェーズ表の着手前）までにnmsへ導入済みであること**。テーマ28で得たトラップ受信の仕組みを、本テーマでは初回カットオーバー（P2）より前から証跡取得に使う点に注意する。
2. GW切替作業に伴うold-core側SVIのlinkDown、new-core側インターフェースのlinkUp等のトラップ着信をターミナル上で確認する。
3. 着信ログ（着信時刻・送信元IP・トラップ種別）を構築ログへ転記し、カットオーバーの証跡として保存する。

> 参考: 書籍『ネットワーク「動作試験」入門』の`参考資料/ネットワーク技術/ネットワーク「動作試験」入門/_index/text/p109.md`。障害試験時のSyslog・SNMPトラップは、実際に何が起きたかを時系列で追える「ラストログ」であり、カットオーバー作業においても同様に、切替の瞬間に着信するリンク状態トラップを証跡として確実に保存しておくことが、事後の切り分け・報告の拠り所になる。

## フェーズ表

### P0: 移行前確認
| No | T+目安 | 作業（投入コマンド） | 確認（コマンド＋期待値） | 切り戻し判断基準 | 実績記入欄 |
|---|---|---|---|---|---|
| P0-1 | T+0 | （なし） | old-core・old-sw1・old-sw2・old-rtで`show ip interface brief`→既存インターフェースが全てup/up、想定外のdownがない | ― | |
| P0-2 | T+0 | （なし） | pc-a・pc-b・srv-fileからold-rt Lo0（203.0.113.1）へ`ping -c 4`→いずれも4/4成功（移行前ベースラインの再確認） | 疎通NGの場合は移行作業を開始しない | |
| P0-3 | T+0 | （なし） | new-core1・new-core2・new-rtが試験計画書Mission3（新環境単体試験、HSRPフェイルオーバー試験を含む）に合格済みであることを構築ログで確認する | 未合格の場合は着手しない | |
| P0-4 | T+0 | nmsで対象VLANのGWへ監視ping（`ping -i 0.2 <GW>`）をバックグラウンドで開始する | 開始直後のping応答が0% packet lossであることを確認する | 開始時点で疎通NGなら着手しない | |
| P0-5 | T+0 | nmsで`snmptrapd -f -Lo -c /tmp/snmptrapd.conf`を起動する | 起動ログにエラーが出ていないことを確認する | ― | |
| P0-6 | T+0 | （なし） | 作業時間帯が業務時間外であること（本ラボでは業務時間外作業として擬似的に扱う）を確認する | ― | |

### P1: 新旧トランク開通
| No | T+目安 | 作業（投入コマンド） | 確認（コマンド＋期待値） | 切り戻し判断基準 | 実績記入欄 |
|---|---|---|---|---|---|
| P1-1 | T+10分 | new-core1: `interface Ethernet0/2` → `no shutdown`（old-sw1向け） | new-core1で`show interfaces Ethernet0/2 status`→connected | リンクアップしない場合は物理配線を確認し、原因不明ならshutdownへ戻す | |
| P1-2 | T+10分 | new-core1: `interface Ethernet0/3` → `no shutdown`（old-sw2向け） | new-core1で`show interfaces Ethernet0/3 status`→connected | 同上 | |
| P1-3 | T+10分 | new-core2: `interface Ethernet0/2` → `no shutdown`（old-sw1向け） | new-core2で`show interfaces Ethernet0/2 status`→connected | 同上 | |
| P1-4 | T+10分 | new-core2: `interface Ethernet0/3` → `no shutdown`（old-sw2向け） | new-core2で`show interfaces Ethernet0/3 status`→connected | 同上 | |
| P1-5 | T+11分 | old-sw1: `interface Ethernet1/0`・`interface Ethernet1/1` → それぞれ`no shutdown` | old-sw1で`show interfaces trunk`→Et1/0・Et1/1がtrunkとして表示される | 同上 | |
| P1-6 | T+11分 | old-sw2: `interface Ethernet0/3`・`interface Ethernet1/0` → それぞれ`no shutdown` | old-sw2で`show interfaces trunk`→Et0/3・Et1/0がtrunkとして表示される | 同上 | |
| P1-7 | T+13分 | （なし。STP再収束を待機） | new-core1・new-core2で`show spanning-tree vlan 10`（20/30/90も同様）→new-core1がRoot、new-core2がRoot以外で、ポートロールが設計どおりに収束している | 再収束が（Mission 2で記入：許容再収束時間の目安）を超えて続く、または期待したRoot Bridgeにならない場合はP1-1〜P1-6のshutdownへ戻す | |
| P1-8 | T+14分 | （なし） | P0-4で開始した監視pingにP1作業中の想定外パケットロスが発生していないことを確認する（VLAN10/20/30のGWはまだold-core側のため影響が出ないはずである） | 想定外のロスが発生した場合はP1-1〜P1-6を切り戻す | |
| P1-9 | T+15分 | （なし） | new-core1・new-core2で`show ip ospf neighbor`→new-rtとの隣接がFULLである | FULLにならない場合はP2以降へ進まず原因切り分けを行う | |

### P2: VLAN10 GW移行
| No | T+目安 | 作業（投入コマンド） | 確認（コマンド＋期待値） | 切り戻し判断基準 | 実績記入欄 |
|---|---|---|---|---|---|
| P2-1 | T+20分 | nmsで`ping -i 0.2 10.28.10.1 \| tee /tmp/cutover_vlan10.log`を開始する | pingが0% packet lossで安定応答していることを確認してから次工程へ進む | ― | 開始時刻: |
| P2-2 | T+20分 | old-core: `interface Vlan10` → `shutdown` | old-coreで`show ip interface brief \| include Vlan10`→administratively down | ― | |
| P2-3 | T+20分 | new-core1: `interface Vlan10` → `no shutdown` | new-core1で`show ip interface brief \| include Vlan10`→up/up | ― | |
| P2-4 | T+20分 | new-core2: `interface Vlan10` → `no shutdown` | new-core2で`show ip interface brief \| include Vlan10`→up/up | ― | |
| P2-5 | T+20分 | （standby 10 preemptはパラメータシートで投入済み。追加投入は不要） | new-core1で`show standby vlan 10 brief`→State=Active | Activeにならない場合はP2-2〜P2-4を切り戻す | |
| P2-6 | T+21分 | nmsでP2-1のpingを停止しログを確認する | 損失数×0.2秒 ≦ 60秒であること。60秒に対応する許容損失数の上限は（Mission 2で記入） | 60秒を超過した場合は切り戻し手順書P2を実施する | 実測断時間: 秒 |
| P2-7 | T+21分 | （なし） | nmsのsnmptrapd出力に、old-core Vlan10のlinkDownと、new-core1・new-core2 Vlan10のlinkUpが着信していることを確認し、構築ログへ転記する | ― | |

### P3: カットオーバー判定（VLAN10）
| No | T+目安 | 作業（投入コマンド） | 確認（コマンド＋期待値） | 切り戻し判断基準 | 実績記入欄 |
|---|---|---|---|---|---|
| P3-1 | T+25分 | （なし） | pc-aから`ping -c 4 10.28.10.1`（GW疎通）→4/4成功 | NGなら切り戻し手順書P2を実施 | |
| P3-2 | T+25分 | （なし） | pc-aから`ping -c 4 203.0.113.2`（new-rt Lo0）→4/4成功。VLAN10のGW移行時点で経路決定権も新環境（new-core→new-rt経由のOSPFデフォルトルート）へ移っているため、この時点で既にWAN到達性が成立する | NGなら切り戻し手順書P2を実施 | |
| P3-3 | T+25分 | （なし） | new-core1で`show standby vlan 10 brief`→State=Active | 期待状態でなければ切り戻し手順書P2を実施 | |
| P3-4 | T+25分 | （なし） | new-core2で`show standby vlan 10 brief`→State=Standby | 期待状態でなければ切り戻し手順書P2を実施 | |
| P3-5 | T+25分 | （なし） | P2-7で記録したトラップ着信・構築ログへの転記が完了していることを確認する | ― | |
| P3-6 | T+25分 | （なし） | 上記P3-1〜P3-5が全てOKであることを判定者として確認する | いずれかNGならP4へ進まず、切り戻し手順書P2を実施し原因究明後に再カットオーバーする | 判定: 続行／切り戻し |

### P4: VLAN20 GW移行
> Mission5では、本フェーズを1回実施した後、意図的に切り戻し手順書P4の手順で切り戻しを行い、復旧を確認したうえで、本フェーズを再実行して成功させる（切り戻し訓練）。以下の表は、切り戻しを伴わない通常時の手順である。

| No | T+目安 | 作業（投入コマンド） | 確認（コマンド＋期待値） | 切り戻し判断基準 | 実績記入欄 |
|---|---|---|---|---|---|
| P4-1 | T+35分 | nmsで`ping -i 0.2 10.28.20.1 \| tee /tmp/cutover_vlan20.log`を開始する | pingが0% packet lossで安定応答していることを確認してから次工程へ進む | ― | 開始時刻: |
| P4-2 | T+35分 | old-core: `interface Vlan20` → `shutdown` | old-coreで`show ip interface brief \| include Vlan20`→administratively down | ― | |
| P4-3 | T+35分 | new-core1: `interface Vlan20` → `no shutdown` | new-core1で`show ip interface brief \| include Vlan20`→up/up | ― | |
| P4-4 | T+35分 | new-core2: `interface Vlan20` → `no shutdown` | new-core2で`show ip interface brief \| include Vlan20`→up/up | ― | |
| P4-5 | T+35分 | （standby 20 preemptは投入済み） | new-core1で`show standby vlan 20 brief`→State=Active、new-core2で`show standby vlan 20 brief`→State=（Mission 2で記入） | 期待状態にならない場合はP4-2〜P4-4を切り戻す | |
| P4-6 | T+36分 | nmsでP4-1のpingを停止しログを確認する | 損失数×0.2秒 ≦ 60秒であること（許容損失数はP2-6と同じ基準） | 60秒を超過した場合は切り戻し手順書P4を実施する | 実測断時間: 秒 |
| P4-7 | T+36分 | （なし） | pc-bから`ping -c 4 10.28.20.1`→4/4成功、`ping -c 4 203.0.113.2`→4/4成功 | NGなら切り戻し手順書P4を実施 | |
| P4-8 | T+36分 | （なし） | nmsのsnmptrapd出力に、old-core Vlan20のlinkDownと、new-core1・new-core2 Vlan20のlinkUpが着信していることを確認し、構築ログへ転記する | ― | |
| P4-9 | T+36分 | （なし） | 上記が全てOKであることを判定者として確認する | いずれかNGならP5へ進まず、切り戻し手順書P4を実施する | 判定: 続行／切り戻し |

### P5: VLAN30 GW移行
| No | T+目安 | 作業（投入コマンド） | 確認（コマンド＋期待値） | 切り戻し判断基準 | 実績記入欄 |
|---|---|---|---|---|---|
| P5-1 | （Mission 2で記入：移行計画書のスケジュールを参照） | nmsで`ping -i 0.2 10.28.30.1 \| tee /tmp/cutover_vlan30.log`を開始する | pingが0% packet lossで安定応答していることを確認してから次工程へ進む | ― | 開始時刻: |
| P5-2 | 同上 | old-core: `interface Vlan30` → `shutdown` | old-coreで`show ip interface brief \| include Vlan30`→administratively down | ― | |
| P5-3 | 同上 | new-core1: `interface Vlan30` → `no shutdown` | new-core1で`show ip interface brief \| include Vlan30`→up/up | ― | |
| P5-4 | 同上 | new-core2: `interface Vlan30` → `no shutdown` | new-core2で`show ip interface brief \| include Vlan30`→up/up | ― | |
| P5-5 | 同上 | （standby 30 preemptは投入済み） | new-core1で`show standby vlan 30 brief`→State=Active | Activeにならない場合はP5-2〜P5-4を切り戻す | |
| P5-6 | 同上 | nmsでP5-1のpingを停止しログを確認する | 損失数×0.2秒 ≦ 60秒であること（許容損失数はP2-6と同じ基準） | 60秒を超過した場合は切り戻し手順書P5を実施する | 実測断時間: 秒 |
| P5-7 | 同上 | （なし） | srv-fileから`ping -c 4 10.28.30.1`→4/4成功、`ping -c 4 203.0.113.2`→4/4成功 | NGなら切り戻し手順書P5を実施 | |
| P5-8 | 同上 | （なし） | nmsのsnmptrapd出力に、old-core Vlan30のlinkDownと、new-core1・new-core2 Vlan30のlinkUpが着信していることを確認し、構築ログへ転記する | ― | |
| P5-9 | 同上 | （なし） | 上記が全てOKであることを判定者として確認する | いずれかNGならP6へ進まず、切り戻し手順書P5を実施する | 判定: 続行／切り戻し |

### P6: WAN切替（old-core default依存解消・VLAN90 GW移行）
VLAN10/20/30は既にP2/P4/P5で移行済みのため、本フェーズの対象はVLAN90（機器管理）のGW移行と、old-coreのWANルーティング依存が解消されたことの最終確認である。VLAN90はユーザーVLANではなく要件定義書§3の60秒要件の直接対象ではないが、同じ基準で断時間を測定・記録する。

| No | T+目安 | 作業（投入コマンド） | 確認（コマンド＋期待値） | 切り戻し判断基準 | 実績記入欄 |
|---|---|---|---|---|---|
| P6-1 | T+55分 | nmsで`ping -i 0.2 10.28.90.1 \| tee /tmp/cutover_vlan90.log`を開始する | pingが0% packet lossで安定応答していることを確認してから次工程へ進む | ― | 開始時刻: |
| P6-2 | T+55分 | old-core: `interface Vlan90` → `shutdown` | old-coreで`show ip interface brief \| include Vlan90`→administratively down | ― | |
| P6-3 | T+55分 | new-core1: `interface Vlan90` → `no shutdown` | new-core1で`show ip interface brief \| include Vlan90`→up/up | ― | |
| P6-4 | T+55分 | new-core2: `interface Vlan90` → `no shutdown` | new-core2で`show ip interface brief \| include Vlan90`→up/up | ― | |
| P6-5 | T+55分 | （standby 90 preemptは投入済み） | new-core1で`show standby vlan 90 brief`→State=Active | Activeにならない場合はP6-2〜P6-4を切り戻す | |
| P6-6 | T+56分 | nmsでP6-1のpingを停止しログを確認する | 損失数×0.2秒 ≦ 60秒であること（許容損失数はP2-6と同じ基準） | 60秒を超過した場合は切り戻し手順書P6を実施する | 実測断時間: 秒 |
| P6-7 | T+56分 | （なし） | old-sw1・old-sw2から`ping -c 4 10.28.90.1`→いずれも4/4成功（`ip default-gateway`の設定文自体は変更していないが、GWの実体がnew-core側に切り替わっていることを確認） | NGなら切り戻し手順書P6を実施 | |
| P6-8 | T+56分 | （なし） | old-sw1・old-sw2から`ping -c 4 203.0.113.2`→いずれも4/4成功。VLAN10/20/30/90の全GWが新環境へ移行済みであることの最終確認 | NGなら切り戻し手順書P6を実施 | |
| P6-9 | T+56分 | （なし） | **pc-a**から`ping -c 4 203.0.113.2`→4/4成功。VLAN10のGW自体はP2の時点で既に新環境の経路（new-core→new-rt経由のOSPFデフォルトルート）を使っている（P3-2参照）が、ここではVLAN10/20/30/90の全GW移行が完了した状態で改めて確認し、社内のどのセグメントからもnew-rt経由でWANへ到達できることを再確認する | NGなら切り戻し手順書P6を実施 | |
| P6-10 | T+57分 | （なし） | old-coreで`show ip route static`を実行し、defaultルート（`0.0.0.0/0 via 10.28.1.1`）が（Mission 2で記入：old-coreのdefaultルートに「依存が無い」と言える具体的な根拠・確認方法）であることを確認する | ― | |
| P6-11 | T+57分 | （なし） | nmsのsnmptrapd出力に、old-core Vlan90のlinkDownと、new-core1・new-core2 Vlan90のlinkUpが着信していることを確認し、構築ログへ転記する | ― | |
| P6-12 | T+57分 | （なし） | 上記が全てOKであることを判定者として確認する | いずれかNGならP7へ進まず、切り戻し手順書P6を実施する | 判定: 続行／切り戻し |

### P7: pc-b移設・VLAN20整理
| No | T+目安 | 作業（投入コマンド） | 確認（コマンド＋期待値） | 切り戻し判断基準 | 実績記入欄 |
|---|---|---|---|---|---|
| P7-1 | T+70分 | nmsで`ping -i 0.2 10.28.20.10 \| tee /tmp/relocate_pcb.log`を開始する（pc-b自身への監視ping） | pingが0% packet lossで安定応答していることを確認してから次工程へ進む | ― | 開始時刻: |
| P7-2 | T+70分 | old-sw1: `interface Ethernet0/3` → `shutdown`（pc-b旧収容ポート） | old-sw1で`show interfaces Ethernet0/3 status`→disabled | ― | |
| P7-3 | T+70分 | old-sw2: `interface Ethernet1/1` → `no shutdown`（pc-b新収容ポート、access vlan20は投入済み） | old-sw2で`show interfaces Ethernet1/1 switchport`→Access Mode VLAN: 20、`show interfaces Ethernet1/1 status`→connected | ― | |
| P7-4 | T+70分 | pc-bで`ip link set eth1 down`、`ip addr add 10.28.20.10/24 dev eth2`、`ip link set eth2 up`、`ip route replace default via 10.28.20.1 dev eth2`（ラボでは物理ケーブル移設をeth1 down／eth2 upで模擬する） | pc-bで`ip addr show eth2`→10.28.20.10/24が付与されている | ― | |
| P7-5 | T+71分 | nmsでP7-1のpingを停止しログを確認する | 損失数×0.2秒 ≦ 60秒であること（許容損失数はP2-6と同じ基準） | 60秒を超過した場合は切り戻し手順書P7を実施する | 実測断時間: 秒 |
| P7-6 | T+71分 | （なし） | pc-bから`ping -c 4 10.28.20.1`→4/4成功、`ping -c 4 203.0.113.2`→4/4成功 | NGなら切り戻し手順書P7を実施 | |
| P7-7 | T+71分 | （なし） | old-sw1・old-sw2それぞれで`show vlan brief`→VLAN20がold-sw2のみに存在し、old-sw1にはVLAN20が存在しない（L2延伸の解消を確認） | NGなら切り戻し手順書P7を実施 | |
| P7-8 | T+71分 | （なし） | 上記が全てOKであることを判定者として確認する | いずれかNGならP8へ進まず、切り戻し手順書P7を実施する | 判定: 続行／切り戻し |

### P8: 旧機器撤去・監視切替・完了判定
| No | T+目安 | 作業（投入コマンド） | 確認（コマンド＋期待値） | 切り戻し判断基準 | 実績記入欄 |
|---|---|---|---|---|---|
| P8-1 | T+85分 | （なし） | nmsから9台（old-rt/old-core/old-sw1/old-sw2/mon-core/cap-sw/new-core1/new-core2/new-rt）全てへSNMPv3ポーリング（`snmpwalk -v3 -l authPriv -u nmsuser -a SHA -A 'SnmpAuth28!' -x AES -X 'SnmpPriv28!' <IP> system`）が成功する（decommission直前の最終全数確認） | いずれか失敗する場合は原因切り分けを優先し、撤去作業に進まない | |
| P8-2 | T+85分 | old-core: 残るインターフェース（Ethernet0/1〜Ethernet1/0、VLAN900/901 SVI含む）を全て`shutdown` | old-coreで`show ip interface brief`→全てadministratively down | ― | |
| P8-3 | T+85分 | old-rt: `interface Ethernet0/1` → `shutdown` | old-rtで`show ip interface brief`→administratively down | ― | |
| P8-4 | T+86分 | （containerlabホスト上で）`docker stop clab-lan-refresh-lab-old-core` | `docker ps`にold-coreコンテナが表示されない | ― | |
| P8-5 | T+86分 | （containerlabホスト上で）`docker stop clab-lan-refresh-lab-old-rt` | `docker ps`にold-rtコンテナが表示されない | ― | |
| P8-6 | T+87分 | mon-core: `no ip route 0.0.0.0 0.0.0.0 10.28.0.1` → `ip route 0.0.0.0 0.0.0.0 10.29.0.2` | mon-coreで`show ip route static`→defaultが10.29.0.2経由になっている | ― | |
| P8-7 | T+87分 | nmsのポーリング対象からold-rt（10.28.1.1）・old-core（10.28.90.1）を除外する（new-core1/2・new-rtはMission3で追加済み） | nmsのポーリング対象一覧が、基本設計書§7で定めた移行後の7台構成（old-sw1/old-sw2/mon-core/cap-sw/new-core1/new-core2/new-rt）になっている | ― | |
| P8-8 | T+88分 | （なし） | nmsから残り7台（old-sw1/old-sw2/mon-core/cap-sw/new-core1/new-core2/new-rt）全てへSNMPv3ポーリングが成功する | 失敗する機器があれば原因切り分けを行う | |
| P8-9 | T+88分 | （なし） | 全点疎通マトリクスを実施する（pc-a/pc-b/srv-fileから203.0.113.2、機器管理IP相互、nmsからの全ポーリング対象等） | NG項目がある場合は該当区間を切り分け、必要に応じて該当フェーズの切り戻し手順書を参照する | |
| P8-10 | T+88分 | （なし） | 上記が全てOKであることを判定者として確認し、移行完了と判定する | いずれかNGなら完了と判定しない | 判定: 完了／継続対応 |
