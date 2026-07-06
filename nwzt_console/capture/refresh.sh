#!/usr/bin/env bash
# NW-ZT Console ライブ更新 — 稼働中ラボから src/data.js を再生成する。
#
# 手順:
#   1. capture/export_*.sh を順に呼び、各ラボの稼働状況を判定・採取する。
#      （export_*.sh は自己完結: 稼働中なら採取 JSON を stdout、停止中なら
#       {"status":"stopped"} を stdout に返す。落ちても他のラボに影響しない。）
#   2. 採取結果を capture/out/<name>.json に保存（デバッグ・監査用の記録）。
#   3. Node (_regen.js) で既存 data.js を読み込み、採取できたセクションだけ
#      差し替えて再生成する。停止中・失敗したセクションは既存値を保持する
#      （data.js の実データが空になることは絶対に避ける設計）。
#
# 使い方: ./capture/refresh.sh
set -uo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"
OUT_DIR="${HERE}/out"
mkdir -p "$OUT_DIR"

run_export() {
  local name="$1" script="$2"
  local out_file="${OUT_DIR}/${name}.json"
  local result

  echo "== ${name}: ${script} 実行中 ==" >&2
  if result=$("${HERE}/${script}" 2>"${OUT_DIR}/${name}.stderr.log"); then
    printf '%s' "$result" > "$out_file"
    printf '%s' "$result"
  else
    echo "[refresh] ${name}: export スクリプトが異常終了。停止扱いにして既存値を保持" >&2
    printf '{"status":"stopped"}' > "$out_file"
    printf '{"status":"stopped"}'
  fi
}

NAC_JSON=$(run_export "nac" "export_nac.sh")
ZTNA_JSON=$(run_export "ztna" "export_ztna.sh")
NDR_JSON=$(run_export "ndr" "export_ndr.sh")
MICROSEG_JSON=$(run_export "microseg" "export_microseg.sh")

export NAC_JSON ZTNA_JSON NDR_JSON MICROSEG_JSON

if ! command -v node >/dev/null 2>&1; then
  echo "[refresh] エラー: node コマンドが見つかりません。data.js は再生成しません。" >&2
  exit 1
fi

node "${HERE}/_regen.js"
REGEN_STATUS=$?

if [ "$REGEN_STATUS" -ne 0 ]; then
  echo "[refresh] data.js 再生成に失敗しました（既存ファイルは変更されていません）。" >&2
  exit 1
fi

echo "[refresh] 完了。capture/out/*.json に採取結果を保存しました。" >&2
