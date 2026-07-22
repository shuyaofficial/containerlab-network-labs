# イメージ可用性検証ハーネス

containerlabラボ環境で稼働させる予定のネットワーク機器イメージ(vrnetlab製)15種について、
「実際にブートしてSSH/API操作ができるか」を1機種ずつ使い捨てトポロジで検証するためのハーネス。

## 1. 実行場所・前提

- 本ハーネスは **OrbStack VM上** で実行する。

  ```bash
  ssh clab@orb
  cd /Users/shuya/Documents/claude/Mac仮想環境構築/環境/イメージ検証
  ```

- VMには bash / sshpass / curl / python3 / docker / containerlab 0.77.0 がある。
  **jq と telnet は無い**ため、JSON整形が必要な場合は `python3 -m json.tool` や
  簡単な `python3 -c` スクリプトを使う(本ハーネスの RouterOS RESTフックがその例)。
- `containerlab` の操作はすべて `sudo containerlab ...`。プレーンな `docker`
  コマンド(inspect/ps/exec/stats/logs/run/rm)は sudo 不要（`clab` ユーザは
  docker グループに所属済み）。

## 2. 安全設計(最優先事項)

VM上には本ハーネスとは無関係の稼働中ラボが2つ存在し、**絶対に壊してはいけない**。

- `clab-qos-acl-policy-lab-*` (11コンテナ)
- `clab-nwzt-lan-*`

これを守るため、以下を徹底している。

1. **`check_labs_intact`**: `run_one.sh` の最初と最後に、上記2プレフィクスの
   稼働コンテナ数を数えて記録・比較する。実行開始時より1つでも減っていれば
   即座に `exit 1` して停止する（本ハーネスの操作が原因で減ったのか、他の要因か
   の切り分けは呼び出し側で行うこと）。
2. **destroy は必ず `-t <topoファイル>` を指定**する。`containerlab destroy --all`
   や裸の `docker rm`（プレフィクスなし・ワイルドカード）は一切使わない。
   `docker rm -f` を直接呼ぶのは、自分が作った `imgv-` / `clab-imgv-*-dut`
   という名前のコンテナに対してのみ。
3. **`ram_gate`**: 検証対象のクラス(S/M/L/XL)ごとに定めた必要空きRAM(GiB)を
   `free -g` の `available` 列と比較し、不足していれば起動を試みずに
   `NG-RESOURCE` として中断する。VMのリソースを食い潰して他ラボの動作に
   影響を与えることを防ぐ。

## 3. ディレクトリ構成

```
イメージ検証/
├── README.md                     # このファイル
├── lib.sh                        # 共通関数(run_one.shからsourceされる)
├── run_one.sh                    # 1イメージのdeploy→wait→検証→収集→destroy
├── topos/imgv-<name>.clab.yml    # 1ノード使い捨てトポ(dockerモード3機種を除く12個)
├── commands/
│   ├── default.cmds              # 汎用コマンド検証セット(show version確認のみ)
│   └── <name>.cmds               # 機種別コマンド検証セット(任意・別担当が随時追加)
└── results/
    └── results.tsv               # 実行結果の追記先(scrub済み要約のみ)
```

## 4. 対象機種一覧

| name | kind | image | クラス | 備考 |
|---|---|---|---|---|
| routeros | mikrotik_ros | vrnetlab/mikrotik_routeros:7.5 | M | REST APIフックあり |
| veos | arista_veos | vrnetlab/arista_veos:4.29.2F | M | |
| asav | cisco_asav | vrnetlab/cisco_asav:9-18-1 | M | |
| fortios | fortinet_fortigate | vrnetlab/fortinet_fortios:7.4.2.F | M | hostname可逆変更フックあり |
| csr17 | cisco_csr1000v | vrnetlab/cisco_csr1000v:17.03.05 | L | hostname+RESTCONFフックあり |
| csr16 | cisco_csr1000v | vrnetlab/cisco_csr1000v:16.12.05 | L | hostname可逆変更フックあり |
| c8000v | cisco_c8000v | vrnetlab/cisco_c8000v:17.06.03 | L | hostname+RESTCONFフックあり |
| vsrx | juniper_vsrx | vrnetlab/juniper_vsrx:24.4R1.9 | XL | NETCONF+commit checkフックあり |
| vios | cisco_vios | vrnetlab/cisco_vios:159-3.M6 | M | hostname可逆変更フックあり |
| viosl2 | cisco_vios | vrnetlab/cisco_vios:L2-20200929 | M | hostname可逆変更フックあり |
| iol-1563 | cisco_iol | vrnetlab/cisco_iol:15.6.3M3a | S | IOLライセンス必須・hostname可逆変更フックあり |
| iol-l2152 | cisco_iol (type: l2) | vrnetlab/cisco_iol:L2-15.2 | S | IOLライセンス必須・hostname可逆変更フックあり |
| nxos | (kindなし→dockerモード) | vrnetlab/cisco_nxostitanium:7.3.0.D1.1 | L | topoファイル無し、`docker run`で直起動 |
| c8000v-ctrl | (dockerモード) | vrnetlab/cisco_c8000v:controller-17.06.03 | L | topoファイル無し。ブート確認が主目的 |
| c9800cl | (dockerモード) | vrnetlab/cisco_c9800cl:17.17.01 | XL | topoファイル無し。ブート確認が主目的(cmdsがあれば実行) |

`nxos` / `c8000v-ctrl` / `c9800cl` の3機種は containerlab 0.77.0 に対応する
`kind` が無いため、`topos/` にファイルを置かず `run_one.sh` 内で
`docker run -d --privileged --network imgv <image>` により直接起動する
(`MODE=docker` 分岐)。`docker network imgv` が無ければ
`docker network create --subnet 172.20.60.0/24 imgv` で自動作成する。

## 5. 使い方

```bash
./run_one.sh <name>                 # 通常実行
./run_one.sh <name> --extend-done   # 起動タイムアウト時の自動延長(1回)を行わない
```

`--extend-done` は、起動タイムアウトを検知した際に本来1回だけ行う自動延長
(下記「クラス別タイムアウト」参照)を **スキップして即座にタイムアウト扱いにする**
任意フラグ。手動で既に延長を使い切った状態から再実行したい場合や、
延長ロジックを介さない厳密なタイムアウト挙動を確認したい場合に使う。
通常運用では付けなくてよい。

### クラス別の必要RAM・起動タイムアウト・延長時間

| クラス | 必要空きRAM | 初回タイムアウト | 延長(1回のみ) |
|---|---|---|---|
| S | 2 GiB | 300秒 | +300秒 |
| M | 4 GiB | 1800秒 | +900秒 |
| L | 6 GiB | 3600秒 | +1800秒 |
| XL | 10 GiB | 5400秒 | +1800秒 |

延長するかどうかは `judge_boot_failure` がタイムアウト時に
「qemuプロセスが生存 かつ CPUを消費中」であれば `still-booting` と判定して
1回だけ延長し、「qemuが消滅」または挙動が掴めなければ `failed` として
即座に `NG` 判定へ進む。

## 6. 実行フロー(run_one.sh内部)

1. `check_labs_intact` で既存ラボの初期コンテナ数を記録
2. `ram_gate` でクラス別の必要RAMを満たすか確認(不足なら`NG-RESOURCE`で中断)
3. IOL機種(`iol-1563`/`iol-l2152`)なら `ensure_iourc` でVM上の
   `/opt/clab/.iourc` を用意(既にあれば何もしない)
4. deploy(clabモードは`containerlab deploy -t <topo> --reconfigure`、
   dockerモードは`docker run`)
5. `wait_boot` で起動待ち。タイムアウト時は`judge_boot_failure`で1回だけ延長判定
6. mgmt IPを`docker inspect`で取得
7. 認証リスト(既定`admin/admin`。`routeros`は`admin/(空)`を、`vsrx`は
   `admin/admin@123`を追加で試行)で疎通確認し、成功した組を採用
8. `commands/<name>.cmds`(無ければ`commands/default.cmds`)の各行を実行し
   期待regexとの一致を集計。出力は `~/imgverify_logs/<name>/` へ保存
9. 機種別フック(hostname可逆変更、RESTCONF試行、RouterOS RESTシーケンス等)。
   フック失敗は verdict を `FULL`→`PARTIAL` に落とすが処理は継続する
10. destroy(`-t <topoファイル>`指定、またはdockerモードは`docker rm -f`) +
    qemu残骸確認(`pgrep -f qemu.*<name>`) + `check_labs_intact`で再確認
11. `results/results.tsv` へ1行追記(`scrub`でIOLライセンス等の16桁hexを
    `[REDACTED]`に置換してから書き込む)

## 7. 判定基準(verdict)

| verdict | 意味 |
|---|---|
| `FULL` | 起動成功・SSH/API疎通成功・コマンド検証全pass・機種別フックも全て成功 |
| `PARTIAL` | 起動・疎通は成功したが、コマンド検証の一部失敗 or 機種別フックが失敗 |
| `BOOT_ONLY` | 起動(healthy/running)までは確認できたが、用意した認証情報でSSH/API疎通ができなかった |
| `NG` | 起動タイムアウト(延長後も失敗)、またはqemu消滅等で起動失敗と判定、またはdeploy自体が失敗 |
| `NG-RESOURCE` | 空きRAMが必要量に満たず、起動を試みずに中断(`ram_gate`) |
| `SKIP` | 自動フローでは使用しない予約値。手動で除外・保留した対象を記録する際に使う |

## 8. ログ・結果の扱い

- 生ログ(SSH出力、REST応答、RESTCONF応答等)は **VM側 `~/imgverify_logs/<name>/`**
  にのみ保存する。これらはリポジトリにコミットしない。
- リポジトリの `results/results.tsv` に書き込むのは、`scrub`で16桁hex
  (IOLライセンス`gns3-iouvm`値の漏洩防止)を`[REDACTED]`に置換した後の
  要約1行のみ。列は以下の順:

  ```
  date  image:tag  class  boot  access  cmds_pass/total  version_match  verdict  duration_s  notes
  ```

## 9. commands/*.cmds のフォーマット

TAB区切り3フィールド、`#`で始まる行はコメントとして無視する。

```
<コマンド>	<期待regex>	<出典>
```

コマンド自体がパイプ(`|`)を含むケース(例: `show run | include hostname`)が
あるため、フィールド区切りには必ずTABを使う(スペースやパイプを区切りに
使わないこと)。`commands/default.cmds` は本ハーネス標準の1行のみ:

```
show version	Version	generic
```

機種別の `commands/<name>.cmds` は別担当が随時追加する想定。`csr16` 用の
`commands/csr16.cmds`(show versionのみ)が来る想定。`c8000v-ctrl` と
`c9800cl` はブート確認が主目的のためcmdsファイルが無くてもよい
(`c9800cl`はcmdsがあれば実行される)。

## 10. ensure_iourc について

`lib.sh` の `ensure_iourc` は
`28_snmp_monitoring_deep_dive/04_構築/deploy.sh` の同名関数を移植したもの。
イメージ内の `/entrypoint.sh` または `/iol/.iourc` から
`gns3-iouvm = <16桁hex>;` を抽出し、VM側 `/opt/clab/.iourc` を
mode 600 で生成する。差分は「元は候補イメージ4つを順に試す全探索だったが、
本ハーネスは検証対象イメージが1つに確定しているため引数で受け取った
イメージのみを試す」点のみ。ライセンス値はVM内にのみ存在し、
リポジトリには一切含めない(`.gitignore`で`*iourc*`等を除外済み)。
