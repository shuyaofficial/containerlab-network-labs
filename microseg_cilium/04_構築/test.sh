#!/usr/bin/env bash
# テーマ43 段階疎通テスト。frontend/other から backend への HTTP コードを測る。
# 遮断はタイムアウトで 000（curl exit 28）として現れる。
set -uo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.local/bin:$PATH"
export KUBECONFIG="$HOME/.kube-microseg.yaml"
NS=microseg
K=kubectl

# frontend/other Pod 名を解決
FE=$($K -n $NS get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}')
OT=$($K -n $NS get pod -l app=other    -o jsonpath='{.items[0].metadata.name}')

# $1=Pod名 $2=ラベル $3=URL パス
probe() {
  local pod="$1" label="$2" path="$3"
  local code
  code=$($K -n $NS exec "$pod" -- \
    curl -s -o /dev/null -w '%{http_code}' --connect-timeout 4 --max-time 6 \
    "http://backend.microseg.svc.cluster.local${path}" 2>/dev/null)
  # curl が接続できないと空 or 000
  [ -z "$code" ] && code="000(timeout/blocked)"
  printf '  %-8s -> backend%-8s : %s\n' "$label" "$path" "$code"
}

echo "=== ${1:-current} 状態の east-west 疎通 ==="
echo "[L4] frontend/other → backend:80"
probe "$FE" frontend "/"
probe "$OT" other     "/"
echo "[L7] frontend → backend の パス別"
probe "$FE" frontend "/"
probe "$FE" frontend "/admin"
echo "--- 適用中ポリシー ---"
$K -n $NS get networkpolicy,ciliumnetworkpolicy --no-headers 2>/dev/null | sed 's/^/  /' || echo "  (なし)"
