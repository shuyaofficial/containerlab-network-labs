#!/usr/bin/env bash
# Verona再現: デバイスポスチャーチェック（モック）
#
# Verona p34「デバイスポスチャー機能」の簡易再現。実際のVeronaはドメイン参加有無・
# エンドポイントセキュリティ製品（Windows Defender/ESET/SentinelOne）の稼働状況を
# チェックするが、本ラボはosqueryがarm64非対応のため、以下3点の擬似チェックに
# 簡略化する（正直に明記。詳細は ../../02_基本設計/網屋Verona_OSS対応表.md）:
#   1. クライアント証明書の有無（step-ca enrollmentの代替確認）
#   2. OS種別（uname）
#   3. 擬似エンドポイントセキュリティのバージョン（環境変数 VERONA_EDR_VERSION）
#
# 要件を満たさない場合は接続拒否(exit 1)、満たす場合は許可(exit 0)を返す。
# 使い方: ./check_posture.sh [証明書パス] （環境変数 MIN_EDR_VERSION / VERONA_EDR_VERSION で調整可）
set -euo pipefail

CERT_PATH="${1:-/tmp/posture/client.crt}"
MIN_EDR_VERSION="${MIN_EDR_VERSION:-2.0}"
EDR_VERSION="${VERONA_EDR_VERSION:-0.0}"

fail() {
  echo "NG: $1"
  echo "== 判定: NG（接続拒否） =="
  exit 1
}

echo "== Verona再現 デバイスポスチャーチェック（モック） =="

# 1. クライアント証明書の有無
if [ ! -f "$CERT_PATH" ]; then
  fail "クライアント証明書が見つかりません（${CERT_PATH}）。step-ca enrollment未実施。"
fi
echo "[1] クライアント証明書: OK (${CERT_PATH})"

# 2. OS種別チェック（対応OSのみ許可。実運用のVeronaはWindows/Macのみ対応=p34,p35注記）
OS_KERNEL="$(uname -s)"
case "$OS_KERNEL" in
  Linux|Darwin) echo "[2] OS種別: OK (${OS_KERNEL})" ;;
  *) fail "非対応OS（${OS_KERNEL}）" ;;
esac

# 3. 擬似エンドポイントセキュリティのバージョンチェック（sort -Vによる簡易バージョン比較）
if [ "$(printf '%s\n%s\n' "$MIN_EDR_VERSION" "$EDR_VERSION" | sort -V | head -1)" != "$MIN_EDR_VERSION" ]; then
  fail "擬似EDRバージョンが要件未満（現在:${EDR_VERSION} / 要求:${MIN_EDR_VERSION}以上）"
fi
echo "[3] 擬似EDRバージョン: OK (${EDR_VERSION} >= ${MIN_EDR_VERSION})"

echo "== 判定: OK（接続許可） =="
exit 0
