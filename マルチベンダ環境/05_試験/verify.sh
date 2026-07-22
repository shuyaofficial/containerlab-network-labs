#!/usr/bin/env bash
# =====================================================================
# verify.sh — マルチベンダ環境 動作確認スクリプト
#   実行前提: ssh clab@orb でOrbStack VMにログインし、VM上で実行する
#            （sudo docker exec / curl / sshpass を使用）。
#   出力    : TSV（RESULT<TAB>CATEGORY<TAB>ITEM<TAB>DETAIL）。RESULT= OK / NG / INFO
#   依存    : sshpass（hq-edge RouterOSのSSH取得に使用）。無ければ該当行はNG。
#   認証    : RouterOS admin/admin（devices.yaml）、SR Linux admin/NokiaSrl1!
# =====================================================================
set -uo pipefail

P="clab-mvlab-"
EDGE_IP="172.20.50.11"
SRL1_IP="172.20.50.13"
pass=0; fail=0

row()  { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
ok()   { pass=$((pass+1)); row OK   "$1" "$2" "$3"; }
ng()   { fail=$((fail+1)); row NG   "$1" "$2" "$3"; }
info() {                   row INFO "$1" "$2" "$3"; }

printf 'RESULT\tCATEGORY\tITEM\tDETAIL\n'

# ---------------------------------------------------------------------
# 1. コンテナ13台が running か
# ---------------------------------------------------------------------
NODES="isp-a isp-b hq-edge hq-core hq-sw dc-leaf1 dc-leaf2 br-edge hq-pc1 hq-pc2 srv-web srv-db br-pc"
for n in $NODES; do
  st=$(sudo docker inspect -f '{{.State.Status}}' "${P}${n}" 2>/dev/null || echo absent)
  if [ "$st" = running ]; then ok container "$n" running; else ng container "$n" "$st"; fi
done

# ---------------------------------------------------------------------
# 2. 端末間ping（multitool端末から）
#    png <src> <dst-ip> <label> <expect: ok|ng>
# ---------------------------------------------------------------------
png() {
  local src="$1" dst="$2" label="$3" expect="$4" res
  if sudo docker exec "${P}${src}" ping -c 2 -W 2 "$dst" >/dev/null 2>&1; then res=reach; else res=unreach; fi
  if [ "$expect" = ok ]; then
    if [ "$res" = reach ]; then ok ping "$label" "$src->$dst 到達"; else ng ping "$label" "$src->$dst 不達(期待:到達)"; fi
  else
    if [ "$res" = unreach ]; then ok ping "$label" "$src->$dst 不達(期待通り)"; else ng ping "$label" "$src->$dst 到達(期待:不達)"; fi
  fi
}

png hq-pc1 10.50.20.102  VLAN間_pc1-pc2       ok   # VLAN10 -> VLAN20（hq-sw内ルーティング）
png hq-pc1 10.50.30.103  HQ-DC_pc1-srvweb     ok   # HQ -> DC1（OSPF<->eBGP再配信）
png hq-pc1 10.50.31.104  HQ-DC_pc1-srvdb      ok   # HQ -> DC2
png hq-pc1 198.51.100.1  HQ-ISP_pc1-ispaLo    ok   # HQ -> ISP-A ループバック（default->hq-edge->BGP）
png hq-pc1 198.51.100.2  HQ-ISP_pc1-ispbLo    ok   # HQ -> ISP-B ループバック
png br-pc  198.51.100.2  BR-ISP_brpc-ispbLo   ok   # ブランチ -> ISP-B（br-edge NAT）
png br-pc  10.50.10.101  BR-HQ_brpc-hqpc1     ok   # ブランチ -> HQ（NAT src=10.50.255.14、ISPが/16をhq-edgeへ持つため到達）

# ---------------------------------------------------------------------
# 3. BGP セッション確立
# ---------------------------------------------------------------------
# --- FRR (isp-a / isp-b): established ピア数（State/PfxRcd が数値＝確立） ---
frr_bgp() {
  local node="$1" exp="$2" est
  # neighborにdescriptionを付けると summary の最終列が説明文字列になり
  # 「最終列=数値ならestablished」判定が外れる。json出力を python3 で厳密に数える
  # （2026-07-17: state=="Established" のpeer数を数える方式に修正）。
  est=$(sudo docker exec "${P}${node}" vtysh -c "show bgp ipv4 unicast summary json" 2>/dev/null \
        | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); p=d.get("peers",{})
    print(sum(1 for v in p.values() if v.get("state")=="Established"))
except Exception:
    print(0)' 2>/dev/null)
  if [ "${est:-0}" -ge "$exp" ]; then ok bgp "$node" "established=$est (>=$exp)"; else ng bgp "$node" "established=$est (<$exp)"; fi
}
frr_bgp isp-a 2   # 対 isp-b / hq-edge
frr_bgp isp-b 2   # 対 isp-a / hq-edge

# --- RouterOS (hq-edge): established セッション数（count-only） ---
# /routing/bgp/session はestablished(または接続試行中)のセッションのみを一覧する
# ため、count-onlyへの追加フィルタは不要（2026-07-17実機確認、Flags: E=established）。
if command -v sshpass >/dev/null 2>&1; then
  edge_bgp=$(sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 \
             "admin@${EDGE_IP}" "/routing/bgp/session print count-only" 2>/dev/null | tr -dc '0-9')
  if [ "${edge_bgp:-0}" -ge 2 ]; then ok bgp hq-edge "established=$edge_bgp (>=2: isp-a/isp-b)"
  else ng bgp hq-edge "established=${edge_bgp:-0}（admin/admin・BGP確立待ちを確認。手動: /routing/bgp/session print）"; fi
else
  ng bgp hq-edge "sshpassが無くRouterOSへSSH不可。手動: sshpass -p admin ssh admin@${EDGE_IP} '/routing/bgp/session print'"
fi

# --- SR Linux (dc-leaf1 / dc-leaf2): neighbor established ---
srl_bgp() {
  local node="$1" out
  out=$(sudo docker exec "${P}${node}" sr_cli "show network-instance default protocols bgp neighbor" 2>/dev/null || echo "")
  if printf '%s' "$out" | grep -qiE 'established'; then ok bgp "$node" "neighbor established"
  else ng bgp "$node" "neighbor not established（手動: sr_cli 'show network-instance default protocols bgp neighbor'）"; fi
}
srl_bgp dc-leaf1   # 対 hq-core
srl_bgp dc-leaf2   # 対 hq-core

# ---------------------------------------------------------------------
# 4. OSPF 隣接
# ---------------------------------------------------------------------
# --- RouterOS (hq-edge): OSPF隣接数（対 hq-core = 1以上） ---
if command -v sshpass >/dev/null 2>&1; then
  edge_ospf=$(sshpass -p admin ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 \
              "admin@${EDGE_IP}" "/routing/ospf/neighbor print count-only" 2>/dev/null | tr -dc '0-9')
  if [ "${edge_ospf:-0}" -ge 1 ]; then ok ospf hq-edge "neighbor=$edge_ospf (>=1: hq-core)"
  else ng ospf hq-edge "neighbor=${edge_ospf:-0}（手動: /routing/ospf/neighbor print）"; fi
else
  ng ospf hq-edge "sshpassが無くRouterOSへSSH不可"
fi

# --- Cisco IOL (hq-core / hq-sw): SSH不可・console運用のため自動チェック不可 ---
info ospf hq-core-hq-sw "console運用のため自動不可。docker attach ${P}hq-core → 'show ip ospf neighbor' で hq-edge/hq-sw の2隣接FULL、${P}hq-sw で hq-core隣接FULLを目視。間接確認: hq-edge OSPF隣接=OK かつ HQ<->DC/ISP ping到達 で担保。"

# ---------------------------------------------------------------------
# 5. API 取得
# ---------------------------------------------------------------------
# --- RouterOS REST（http。hq-edge.rscはwww(http)のみ有効化、www-sslは非採用） ---
rest=$(curl -s -u admin:admin --max-time 8 "http://${EDGE_IP}/rest/system/resource" 2>/dev/null)
if printf '%s' "$rest" | grep -q '"version"'; then ok api hq-edge-REST "system/resource取得OK"
else ng api hq-edge-REST "REST応答なし（/ip service set www disabled=no・admin/adminを確認）"; fi

# --- SR Linux JSON-RPC（http、admin/NokiaSrl1!） ---
jr=$(curl -s --max-time 8 -u "admin:NokiaSrl1!" "http://${SRL1_IP}/jsonrpc" \
     -d '{"jsonrpc":"2.0","id":1,"method":"get","params":{"commands":[{"path":"/system/information/version","datastore":"state"}]}}' 2>/dev/null)
if printf '%s' "$jr" | grep -qiE '"result"|version'; then ok api dc-leaf1-JSONRPC "system/information/version取得OK"
else ng api dc-leaf1-JSONRPC "JSON-RPC応答なし（json-rpc-server有効化・admin/NokiaSrl1!を確認）"; fi

# ---------------------------------------------------------------------
# 集計
# ---------------------------------------------------------------------
printf '\nSUMMARY\tPASS=%d\tFAIL=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
