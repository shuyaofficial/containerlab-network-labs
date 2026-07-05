#!/usr/bin/env bash
# テーマ43 マイクロセグメンテーション（Cilium/eBPF + NetworkPolicy）deploy — NW-ZT N4 実装
#
# 構成:
#   k3d(k3s in docker) で 1 クラスタを作り、標準 CNI(flannel)/network-policy を無効化して
#   Cilium(eBPF) を CNI として導入。microseg ns に frontend/backend/other の 3 Pod を置き、
#   L3/L4(NetworkPolicy) → L7(CiliumNetworkPolicy) の順で east-west を default-deny 化する。
#
# 前提: OrbStack VM clab (arm64)、docker（compose 不在）。sudo NOPASSWD。
#   ツール（kubectl/k3d/cilium CLI）は ~/.local/bin に配置済み（無ければ ./deploy.sh tools）。
set -euo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"
export PATH="$HOME/.local/bin:$PATH"

# --- パラメータ ---
CLUSTER=microseg
NS=microseg
ARCH=arm64
BIN="$HOME/.local/bin"
K="kubectl"

tools() {
  mkdir -p "$BIN"
  if ! command -v kubectl >/dev/null 2>&1; then
    KV=$(curl -sL https://dl.k8s.io/release/stable.txt)
    curl -sL -o "$BIN/kubectl" "https://dl.k8s.io/release/$KV/bin/linux/$ARCH/kubectl"; chmod +x "$BIN/kubectl"
  fi
  if ! command -v k3d >/dev/null 2>&1; then
    curl -sL -o "$BIN/k3d" "https://github.com/k3d-io/k3d/releases/latest/download/k3d-linux-$ARCH"; chmod +x "$BIN/k3d"
  fi
  if ! command -v cilium >/dev/null 2>&1; then
    CV=$(curl -sL https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    curl -sL -o /tmp/cilium.tar.gz "https://github.com/cilium/cilium-cli/releases/download/${CV}/cilium-linux-${ARCH}.tar.gz"
    tar xzf /tmp/cilium.tar.gz -C "$BIN" cilium; chmod +x "$BIN/cilium"
  fi
  echo "tools ready: kubectl / k3d / cilium in $BIN"
}

case "${1:-deploy}" in
  tools)
    tools
    ;;

  deploy)
    tools
    # --- k3d クラスタ（標準 CNI(flannel) と kube-router の NetworkPolicy を無効化） ---
    #   Cilium を後入れするため flannel/network-policy/traefik/servicelb を殺しておく。
    #   このユーザーは docker グループ所属なので k3d は sudo 不要（sudo だと PATH を失う）。
    k3d cluster create "$CLUSTER" \
      --k3s-arg '--flannel-backend=none@server:*' \
      --k3s-arg '--disable-network-policy@server:*' \
      --k3s-arg '--disable=traefik@server:*' \
      --k3s-arg '--disable=servicelb@server:*' \
      --wait

    # kubeconfig を取得（ユーザー所有で書き出す）
    k3d kubeconfig get "$CLUSTER" > "$HOME/.kube-microseg.yaml"
    export KUBECONFIG="$HOME/.kube-microseg.yaml"
    echo "export KUBECONFIG=$HOME/.kube-microseg.yaml" > "$HERE/.kubeenv"

    # --- Cilium 導入（eBPF CNI）。Hubble も有効化（L7 可視化用）。---
    #   k3d の k3s は kube-proxy 有り → kubeProxyReplacement=false（共存）。
    #   【重要】cilium CLI は k3d の API サーバアドレスを自動検出できず k8sServiceHost が
    #   空になり Pod が https://0.0.0.0:PORT へ繋ごうとして CrashLoop する。
    #   k3d が hostAlias に注入する server コンテナ名を明示して回避する。
    K8S_HOST="k3d-${CLUSTER}-server-0"
    cilium install --wait --wait-duration 5m \
      --set kubeProxyReplacement=false \
      --set k8sServiceHost="$K8S_HOST" \
      --set k8sServicePort=6443 \
      --set l7Proxy=true \
      --set hubble.enabled=true \
      --set hubble.relay.enabled=true

    cilium status --wait || true
    echo "クラスタ+Cilium 起動完了。次: ./deploy.sh workload"
    ;;

  workload)
    export KUBECONFIG="$HOME/.kube-microseg.yaml"
    $K apply -f "$HERE/manifests/00-namespace.yaml"
    $K apply -f "$HERE/manifests/10-workloads.yaml"
    $K -n "$NS" rollout status deploy/frontend --timeout=120s
    $K -n "$NS" rollout status deploy/backend  --timeout=120s
    $K -n "$NS" rollout status deploy/other     --timeout=120s
    echo "ワークロード起動完了。疎通確認: ./deploy.sh test"
    ;;

  policy-l4)
    export KUBECONFIG="$HOME/.kube-microseg.yaml"
    $K apply -f "$HERE/manifests/20-netpol-l4.yaml"
    echo "L3/L4 NetworkPolicy 適用（backend ingress default-deny + frontend:80 のみ許可）。"
    ;;

  policy-l7)
    export KUBECONFIG="$HOME/.kube-microseg.yaml"
    # 【重要】標準 NetworkPolicy（L7 指定なしの :80 全許可）を残したまま CNP を足すと、
    #   Cilium は両者を OR マージし「制限なし :80 許可」が L7 制限を上書きして全通になる。
    #   L7 段階では L3/L4/L7 を一括表現できる CNP に一本化する（標準 NetworkPolicy を外す）。
    $K -n "$NS" delete networkpolicy backend-allow-frontend 2>/dev/null || true
    $K apply -f "$HERE/manifests/30-cnp-l7.yaml"
    echo "L7 CiliumNetworkPolicy 適用（標準 NetworkPolicy は撤去し CNP に一本化）。"
    echo "  → frontend GET /=200 / GET /admin=403 / other=遮断。"
    ;;

  unpolicy)
    export KUBECONFIG="$HOME/.kube-microseg.yaml"
    $K -n "$NS" delete networkpolicy --all 2>/dev/null || true
    $K -n "$NS" delete ciliumnetworkpolicy --all 2>/dev/null || true
    echo "全ポリシー削除（素通し状態に戻す）。"
    ;;

  test)
    exec "$HERE/test.sh"
    ;;

  status)
    export KUBECONFIG="$HOME/.kube-microseg.yaml"
    $K get nodes
    echo '---'
    $K -n kube-system get pods -l k8s-app=cilium -o wide 2>/dev/null || $K -n kube-system get pods | grep -i cilium
    echo '---'
    $K -n "$NS" get pods -o wide 2>/dev/null || true
    echo '---'
    $K -n "$NS" get networkpolicy,ciliumnetworkpolicy 2>/dev/null || true
    ;;

  hubble)
    export KUBECONFIG="$HOME/.kube-microseg.yaml"
    # cilium hubble port-forward をバックグラウンドで張り、observe する
    cilium hubble port-forward >/tmp/hubble-pf.log 2>&1 &
    sleep 4
    echo "=== hubble observe (namespace microseg, 直近) ==="
    hubble observe --namespace "$NS" --last 40 2>/dev/null || echo "(hubble CLI 未取得 or relay 未起動)"
    ;;

  destroy)
    export KUBECONFIG="${HOME}/.kube-microseg.yaml"
    k3d cluster delete "$CLUSTER" 2>/dev/null || true
    rm -f "$HOME/.kube-microseg.yaml" "$HERE/.kubeenv" 2>/dev/null || true
    echo "撤去完了（k3d クラスタ ${CLUSTER} と関連 docker リソースを削除）。"
    ;;

  *)
    echo "usage: $0 {tools|deploy|workload|policy-l4|policy-l7|unpolicy|test|status|hubble|destroy}" >&2
    echo "  deploy     : k3d クラスタ作成＋Cilium 導入（G1）" >&2
    echo "  workload   : microseg ns に frontend/backend/other（G2）" >&2
    echo "  test       : 段階疎通テスト（G2/G3/G4 の HTTP コード確認）" >&2
    echo "  policy-l4  : L3/L4 default-deny + frontend のみ許可（G3）" >&2
    echo "  policy-l7  : L7 GET / 許可・/admin 拒否（G4）" >&2
    echo "  hubble     : hubble observe で verdict 観測（G5）" >&2
    echo "  status/destroy : 状態表示 / 全撤去" >&2
    exit 1
    ;;
esac
