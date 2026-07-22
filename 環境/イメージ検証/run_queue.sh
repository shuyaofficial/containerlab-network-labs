#!/usr/bin/env bash
# ============================================================
# run_queue.sh — 宣言RAM予算に基づく並列実行キュー
# ============================================================
# 従来の run_one.sh 単体運用は free実測ベースの ram_gate で並列制御していたが、
# qemuのメモリ遅延確保により「ゲート通過後に膨張して枯渇」する事故(偽NG)が
# 起きた。本スクリプトはそれに代わり、機種ごとに宣言したRAM予算を
# 予約台帳(claimファイル)で管理し、予算内に収まるジョブだけを並列実行する。
#
# usage:
#   ./run_queue.sh [-b TOTAL_GIB] [-j MAX_JOBS] <name>[,<name>...]
#   ./run_queue.sh [-b TOTAL_GIB] [-j MAX_JOBS] <name1> <name2> ...
#
# 例:
#   ./run_queue.sh vsrx asav
#   ./run_queue.sh -b 12 -j 1 routeros,chr7214
#
# 環境変数(通常は指定不要。テスト/差し替え用途):
#   RUN_ONE_SCRIPT : 起動するスクリプトのパス(既定: run_queue.shと同じディレクトリのrun_one.sh)
#   RESULTS_FILE   : サマリ表示で読む results.tsv のパス
#   QUEUE_DIR      : 予約台帳(claimファイル)を置くディレクトリ
#
# set -e は使わない(待機ループ・ジョブ個別の異常系を個別にハンドリングするため)。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUN_ONE_SCRIPT="${RUN_ONE_SCRIPT:-${SCRIPT_DIR}/run_one.sh}"
RESULTS_FILE="${RESULTS_FILE:-${SCRIPT_DIR}/results/results.tsv}"
QUEUE_DIR="${QUEUE_DIR:-${HOME}/imgverify_logs/.queue}"

# ------------------------------------------------------------
# 機種→宣言RAM(GiB)表(run_one.shのregister表と同じ機種名)
# ------------------------------------------------------------
declare -A IMGV_RAM_GIB
for n in routeros chr7214 iol-1563 iol-l2152; do IMGV_RAM_GIB["$n"]=1; done
for n in vios viosl2 veos asav fortios;       do IMGV_RAM_GIB["$n"]=3; done
for n in csr17 csr16 c8000v c8000v-ctrl nxos; do IMGV_RAM_GIB["$n"]=5; done
IMGV_RAM_GIB[vsrx]=5
IMGV_RAM_GIB[c9800cl]=9

usage() {
  echo "usage: $0 [-b TOTAL_GIB] [-j MAX_JOBS] <name>[,<name>...]" >&2
  echo "  name: ${!IMGV_RAM_GIB[*]}" >&2
  exit 1
}

# ------------------------------------------------------------
# オプション解析
# ------------------------------------------------------------
TOTAL_GIB=""
MAX_JOBS=2

while getopts "b:j:h" opt; do
  case "$opt" in
    b) TOTAL_GIB="$OPTARG" ;;
    j) MAX_JOBS="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

[ $# -ge 1 ] || usage

if ! [[ "$MAX_JOBS" =~ ^[0-9]+$ ]] || [ "$MAX_JOBS" -lt 1 ]; then
  echo "ERROR: -j には1以上の整数を指定してください(指定値: ${MAX_JOBS})" >&2
  exit 1
fi
if [ -n "$TOTAL_GIB" ] && ! [[ "$TOTAL_GIB" =~ ^[0-9]+$ ]]; then
  echo "ERROR: -b には0以上の整数を指定してください(指定値: ${TOTAL_GIB})" >&2
  exit 1
fi

# 残り引数は「カンマ区切り1個」「スペース区切り複数個」の両方を許容する
RAW_NAMES="$*"
IFS=',' read -r -a NAMES <<< "${RAW_NAMES// /,}"

# 未知の機種名は起動前に即エラー(1台でも不正ならジョブを一切開始しない)
for name in "${NAMES[@]}"; do
  [ -n "$name" ] || continue
  if [ -z "${IMGV_RAM_GIB[$name]:-}" ]; then
    echo "ERROR: 未知の機種名 '${name}'" >&2
    usage
  fi
done

# 総予算: 既定は `free -g` の total から 5GiB(稼働ラボ+システム予約)を引いた値
if [ -z "$TOTAL_GIB" ]; then
  if ! command -v free >/dev/null 2>&1; then
    echo "ERROR: freeコマンドが見つかりません。-b でTOTAL_GIBを明示指定してください。" >&2
    exit 1
  fi
  MEM_TOTAL_GIB=$(free -g | awk '/^Mem:/ {print $2}')
  TOTAL_GIB=$((MEM_TOTAL_GIB - 5))
  [ "$TOTAL_GIB" -lt 0 ] && TOTAL_GIB=0
fi

echo "run_queue: TOTAL_GIB=${TOTAL_GIB} MAX_JOBS=${MAX_JOBS} QUEUE_DIR=${QUEUE_DIR}"

mkdir -p "$QUEUE_DIR"
QUEUE_LOCK="${QUEUE_DIR}/.lock"

# flockが使えるか(macOSには標準で無いため、無ければmkdirスピンロックへ)
HAVE_FLOCK="false"
command -v flock >/dev/null 2>&1 && HAVE_FLOCK="true"

# ------------------------------------------------------------
# with_queue_lock <command...>
# ------------------------------------------------------------
# 台帳ディレクトリを排他制御して "$@" を実行し、その終了コードを返す。
with_queue_lock() {
  if [ "$HAVE_FLOCK" = "true" ]; then
    (
      flock -x 200
      "$@"
    ) 200>"$QUEUE_LOCK"
    return $?
  fi

  # mkdirはアトミックなのでロック代わりに使う(macOS等flock不在環境向け)
  local lockdir="${QUEUE_DIR}/.lockdir"
  local waited_ms=0
  local -r max_wait_ms=30000
  until mkdir "$lockdir" 2>/dev/null; do
    sleep 0.2
    waited_ms=$((waited_ms + 200))
    if [ "$waited_ms" -ge "$max_wait_ms" ]; then
      echo "WARNING: mkdirロックの取得に${max_wait_ms}ms待っても失敗しました。ロック無しで続行します。" >&2
      break
    fi
  done
  "$@"
  local rc=$?
  rmdir "$lockdir" 2>/dev/null || true
  return "$rc"
}

# ------------------------------------------------------------
# try_reserve <name> <declared_gib>
# ------------------------------------------------------------
# 台帳合計+自分の宣言が予算以下、かつ実行中ジョブ数がMAX_JOBS未満なら
# claimファイルを作成して0を返す。呼び出しは必ず with_queue_lock 経由にすること。
try_reserve() {
  local name="$1" gib="$2"
  local total=0 count=0 f v

  for f in "$QUEUE_DIR"/*.claim; do
    [ -e "$f" ] || continue
    v=$(cat "$f" 2>/dev/null || echo 0)
    [[ "$v" =~ ^[0-9]+$ ]] || v=0
    total=$((total + v))
    count=$((count + 1))
  done

  if [ $((total + gib)) -le "$TOTAL_GIB" ] && [ "$count" -lt "$MAX_JOBS" ]; then
    echo "$gib" > "${QUEUE_DIR}/${name}.claim"
    return 0
  fi
  return 1
}

# ------------------------------------------------------------
# cleanup_stale_claims
# ------------------------------------------------------------
# 対応するrun_one.shプロセスが存在しないclaim(残骸)を警告して削除する。
cleanup_stale_claims() {
  local run_one_base f base
  run_one_base="$(basename "$RUN_ONE_SCRIPT")"

  for f in "$QUEUE_DIR"/*.claim; do
    [ -e "$f" ] || continue
    base="$(basename "$f" .claim)"
    if ! pgrep -f "${run_one_base}[[:space:]]+${base}([[:space:]]|\$)" >/dev/null 2>&1; then
      echo "WARNING: claim残骸を検出したため削除します: $(basename "$f")(宣言$(cat "$f" 2>/dev/null || echo '?')GiB)" >&2
      rm -f "$f"
    fi
  done
}
with_queue_lock cleanup_stale_claims

# ------------------------------------------------------------
# メインループ: 各ジョブを予算/並列上限が空くまで待機してから起動
# ------------------------------------------------------------
declare -a PIDS=()
declare -a PID_NAMES=()

for name in "${NAMES[@]}"; do
  [ -n "$name" ] || continue
  gib="${IMGV_RAM_GIB[$name]}"

  while ! with_queue_lock try_reserve "$name" "$gib"; do
    echo "queue: ${name}(${gib}GiB) は予算/並列上限待ち — 60秒後に再確認します"
    sleep 60
  done

  echo "queue: ${name}(${gib}GiB) を起動します"
  (
    trap 'rm -f "${QUEUE_DIR}/${name}.claim"' EXIT
    bash "$RUN_ONE_SCRIPT" "$name" </dev/null
  ) &
  PIDS+=("$!")
  PID_NAMES+=("$name")
done

# ------------------------------------------------------------
# 全ジョブ終了待ち + サマリ表示
# ------------------------------------------------------------
echo ""
echo "===== 全ジョブ終了待機 ====="

FAIL_COUNT=0
for i in "${!PIDS[@]}"; do
  pid="${PIDS[$i]}"
  jname="${PID_NAMES[$i]}"
  wait "$pid"
  rc=$?
  [ "$rc" -ne 0 ] && FAIL_COUNT=$((FAIL_COUNT + 1))

  # 注意: 複数ジョブがほぼ同時に完了した場合、tail -1 は直前に完了した
  # 別ジョブの行を指すことがある(results.tsvにジョブ名の列が無いため)。
  # 正確な行が必要な場合は results/results.tsv を image:tag で直接確認すること。
  last_line="(results.tsvなし)"
  [ -f "$RESULTS_FILE" ] && last_line=$(tail -n 1 "$RESULTS_FILE")

  printf '%s\texit=%s\t%s\n' "$jname" "$rc" "$last_line"
done

echo ""
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "全 ${#PIDS[@]} ジョブが exit 0 で終了しました。"
  exit 0
else
  echo "WARNING: ${#PIDS[@]} ジョブ中 ${FAIL_COUNT} ジョブが非0 exit codeで終了しました。"
  exit 1
fi
