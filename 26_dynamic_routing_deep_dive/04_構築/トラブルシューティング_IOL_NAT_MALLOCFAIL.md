# トラブルシューティングログ: Cisco IOLのNAT設定時のメモリ枯渇（MALLOCFAIL）対応

**作成日**: 2026-07-03
**関連フェーズ**: Phase 8 (NAT/PAT設定)
**タグ**: #IOL #NAT #MALLOCFAIL #Containerlab #Troubleshooting #Memory

## 1. 事象 (Symptom)
Cisco IOL（`vrnetlab/cisco_iol:15.7.3M2` 等）のインターフェースに対して `ip nat inside` または `ip nat outside` を設定すると、以下のエラーが連発し、最終的にNAT機能（NVI0インターフェースやCFT）が初期化できずに失敗する。

```text
%SYS-2-MALLOCFAIL: Memory allocation of 2852 bytes failed...
%NBAR Error: Unable to allocate memory for cfg list
CFT initialization failed!
```

## 2. 原因 (Root Cause)
Cisco IOLは、デフォルトで **256MB** の極小メモリ（RAM）で起動する仕様となっている。NATやNBARといった負荷の高い機能を有効化すると、このデフォルトメモリ量では変換テーブルなどの領域を確保できずパニック（Memory fragmentation）に陥る。

## 3. 過去の対応との違い（落とし穴）
過去のプロジェクト（21_cisco_capstone等）では、`clab.yml` に環境変数 `IOL_MEMORY: "1024"` を記述することで解決できていた。
しかし、今回のラボのように**独自の起動スクリプト（`entrypoint_attach.sh`）をバインドしてIOLを直接起動している環境**においては、`clab.yml` 側の環境変数がスクリプト内で解釈されないため無視されてしまう。

## 4. 解決策 (Solution)
独自の起動スクリプト（`entrypoint_attach.sh`）の中で、`iol.bin` を実行している行に、**明示的にRAM容量を指定する `-m 1024` オプション**を追記する。

**【修正前】**
```bash
exec /iol/iol.bin "$IOL_PID" -e "$num_slots" -s 0 -c config.txt -n 1024
```
※ `-n 1024` は NVRAM（設定保存用メモリ）の指定であり、RAMの拡張ではない。

**【修正後】**
```bash
exec /iol/iol.bin "$IOL_PID" -e "$num_slots" -s 0 -c config.txt -m 1024 -n 1024
```
※ `-m 1024` を追加することで、ルータのメインメモリ(RAM)が1GBとなり、NATプロセスが正常に起動（`Line protocol on Interface NVI0, changed state to up`）するようになる。

## 5. 備考
今後、ContainerlabでIOLを使用し、かつ `entrypoint_attach.sh` を使用して構築を行う場合は、必ずテンプレート時点で `-m 1024` が含まれているかを確認すること。
