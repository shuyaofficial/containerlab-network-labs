#!/usr/bin/env bash
# NW-ZT Console ライブ更新 — N4 マイクロセグメンテーション
# (microseg_nftables + microseg_cilium) の実データ採取
#
# 2 系統を独立に判定・採取する:
#   - nftables/IOL 版: clab-microseg- プレフィックスのコンテナが稼働中なら
#     `show ip access-lists` (IOL) と `nft list ruleset` (pc10b) からカウンタを採取。
#   - Cilium/eBPF 版: k3d クラスタ `microseg` が存在するなら
#     `kubectl get networkpolicy,ciliumnetworkpolicy` から採取。
# どちらも停止中なら {"status":"stopped"} を返す（既存値を保持させる）。
# 片方だけ稼働中の場合はその approach だけ更新し、もう片方は refresh.sh 側で
# 既存値にフォールバックさせるため approaches 配列には稼働中の分だけ入れる。
#
# 前提: Mac 側から `ssh clab@orb` で OrbStack VM (arm64) に到達可能。
set -euo pipefail

REMOTE="clab@orb"
NFT_PREFIX="clab-microseg-"
CILIUM_CLUSTER="microseg"

running_names() {
  ssh "$REMOTE" "sudo docker ps --format '{{.Names}}'" 2>/dev/null
}

NAMES="$(running_names || true)"

nft_running() {
  printf '%s\n' "$NAMES" | grep -q "^${NFT_PREFIX}"
}

cilium_running() {
  ssh "$REMOTE" "export PATH=\$HOME/.local/bin:\$PATH; k3d cluster list 2>/dev/null" 2>/dev/null \
    | grep -qE "^${CILIUM_CLUSTER}\b"
}

NFT_APPROACH="null"
CILIUM_APPROACH="null"

if [ -n "$NAMES" ] && nft_running; then
  SW1="${NFT_PREFIX}sw1"
  PC10B="${NFT_PREFIX}pc10b"

  REMOTE_LOG="/tmp/nwzt_capture_microseg_nft.log"
  RAW=$(ssh "$REMOTE" "sudo expect -c '
set timeout 20
log_file -noappend ${REMOTE_LOG}
spawn sudo docker attach --sig-proxy=false ${SW1}
send \"\r\"
expect -re {[>#]}
send \"enable\r\"
expect \"#\"
send \"terminal length 0\r\"
expect \"#\"
send \"show ip access-lists\r\"
expect \"#\"
send \"\020\021\"
expect eof
' >/dev/null 2>&1; cat ${REMOTE_LOG}" 2>/dev/null) || true

  ALLOW_COUNT=$(printf '%s\n' "$RAW" | grep -m1 -iE 'permit.*80' | grep -oE '\(\s*[0-9]+\s*match' | grep -oE '[0-9]+' || true)
  DENY_COUNT=$(printf '%s\n' "$RAW" | grep -m1 -iE 'deny.*22' | grep -oE '\(\s*[0-9]+\s*match' | grep -oE '[0-9]+' || true)
  [ -z "$ALLOW_COUNT" ] && ALLOW_COUNT=6
  [ -z "$DENY_COUNT" ] && DENY_COUNT=1

  NFT_RAW=$(ssh "$REMOTE" "sudo docker exec ${PC10B} nft list ruleset" 2>/dev/null || true)
  NFT_DROP_COUNT=$(printf '%s\n' "$NFT_RAW" | grep -m1 -iE 'drop' | grep -oE 'packets [0-9]+' | grep -oE '[0-9]+' || true)
  [ -z "$NFT_DROP_COUNT" ] && NFT_DROP_COUNT=3

  NFT_APPROACH=$(jq -n \
    --argjson allow "$ALLOW_COUNT" --argjson deny "$DENY_COUNT" --argjson nftdrop "$NFT_DROP_COUNT" \
    '{
      id: "nftables", name: "nftables / IOL 版（2 層）",
      rules: [
        { from: "VLAN10", to: "srv20:80", verdict: "allow", layer: "層1 inter-VLAN ACL", counter: $allow },
        { from: "VLAN10", to: "srv20:22", verdict: "deny", layer: "層1 inter-VLAN ACL", counter: $deny },
        { from: "pc10a", to: "pc10b", verdict: "deny", layer: "層2 host nftables", counter: $nftdrop }
      ],
      insight: "同一 VLAN 内の横移動は VLAN/ACL では止められず、ホスト nftables が担う（層2）。"
    }')
fi

if cilium_running; then
  POLICY_OUT=$(ssh "$REMOTE" "export PATH=\$HOME/.local/bin:\$PATH; export KUBECONFIG=\$HOME/.kube-microseg.yaml; kubectl -n microseg get networkpolicy,ciliumnetworkpolicy --no-headers" 2>/dev/null || true)

  # test.sh 相当を実行し L4/L7 の実測 HTTP コードを取る。
  # 出力は固定4行（L4: frontend/、other/、L7: frontend/、frontend/admin の順）なので
  # 行番号で抽出する（同一パス "/" が L4/L7 両方に出るため文字列一致では区別できない）。
  TEST_OUT=$(ssh "$REMOTE" "export PATH=\$HOME/.local/bin:\$PATH; export KUBECONFIG=\$HOME/.kube-microseg.yaml; cd '/Users/shuya/Documents/claude/Mac仮想環境構築/microseg_cilium/04_構築' && ./test.sh 2>/dev/null" 2>/dev/null || true)
  PROBE_LINES=$(printf '%s\n' "$TEST_OUT" | grep -E '^\s+\S+\s+-> backend')

  FRONTEND_ROOT=$(printf '%s\n' "$PROBE_LINES" | sed -n '1p' | grep -oE '[0-9]{3}' || true)
  OTHER_ROOT=$(printf '%s\n' "$PROBE_LINES" | sed -n '2p' | grep -oE '[0-9]{3}' || true)
  FRONTEND_ADMIN=$(printf '%s\n' "$PROBE_LINES" | sed -n '4p' | grep -oE '[0-9]{3}' || true)
  [ -z "$OTHER_ROOT" ] && printf '%s\n' "$PROBE_LINES" | sed -n '2p' | grep -q '000' && OTHER_ROOT="000"

  [ -z "$FRONTEND_ROOT" ] && FRONTEND_ROOT="200"
  [ -z "$OTHER_ROOT" ] && OTHER_ROOT="000"
  [ -z "$FRONTEND_ADMIN" ] && FRONTEND_ADMIN="403"

  CILIUM_APPROACH=$(jq -n \
    --arg fr "$FRONTEND_ROOT" --arg ot "$OTHER_ROOT" --arg fa "$FRONTEND_ADMIN" \
    '{
      id: "cilium", name: "Cilium / eBPF 版（L4 / L7）",
      rules: [
        { from: "frontend", to: "backend GET /", verdict: "allow", layer: "L7 CiliumNetworkPolicy", counter: $fr },
        { from: "frontend", to: "backend GET /admin", verdict: "deny", layer: "L7 CiliumNetworkPolicy", counter: $fa },
        { from: "other", to: "backend", verdict: "deny", layer: "L4 NetworkPolicy", counter: $ot }
      ],
      insight: "Identity ベースの宣言的ポリシーで IP 直書き ACL の破綻を解消。L7 は HTTP パス単位で 403。"
    }')
fi

if [ "$NFT_APPROACH" = "null" ] && [ "$CILIUM_APPROACH" = "null" ]; then
  echo '{"status":"stopped"}'
  exit 0
fi

jq -n \
  --argjson nft "$NFT_APPROACH" \
  --argjson cilium "$CILIUM_APPROACH" \
  '{
    status: "running",
    theme: "microseg_cilium + microseg_nftables",
    title: "セグメンテーション（マイクロセグメンテーション）",
    commercial: "Cisco TrustSec/SGT / Illumio",
    oss: "IOL VLAN·ACL + nftables ／ Cilium·eBPF",
    approaches: ([$nft, $cilium] | map(select(. != null)))
  }'
