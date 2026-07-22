#!/usr/bin/env bash
# テーマ35 Faucet SDN — ovs1 の起動スクリプト（部材）
#
# ここで行うのは「プラミング」（br0の生成・データポート収容・コントローラ指定）までであり、
# VLAN/ACLのフローポリシーは一切含めない。ポリシーは faucet.yaml（学習者が編集）側で宣言する。
set -euo pipefail

FAUCET_MGMT_IP="172.35.35.11"
FAUCET_OF_PORT="6653"
DATAPATH_ID="0000000000000001"

mkdir -p /var/run/openvswitch /etc/openvswitch /var/log/openvswitch

echo "[bootstrap] ovsdb-server を起動します"
ovsdb-tool create /etc/openvswitch/conf.db /usr/share/openvswitch/vswitch.ovsschema 2>/dev/null || true
ovsdb-server --remote=punix:/var/run/openvswitch/db.sock \
             --pidfile --detach --log-file
ovs-vsctl --no-wait init

echo "[bootstrap] ovs-vswitchd を起動します"
ovs-vswitchd --pidfile --detach --log-file

echo "[bootstrap] br0 (datapath_type=netdev) を作成します"
ovs-vsctl --may-exist add-br br0 -- set bridge br0 datapath_type=netdev

echo "[bootstrap] データポート（eth1/eth2/eth3）の配線を待って br0 へ収容します"
# containerlab はコンテナ起動後にveth(ethN)をnetnsへ配線するため、entrypoint時点では
# まだ存在しないことがある。各インターフェースの出現を最大30秒待ってから収容する。
for i in 1 2 3; do
  for _ in $(seq 1 30); do
    ip link show "eth${i}" >/dev/null 2>&1 && break
    sleep 1
  done
  if ip link show "eth${i}" >/dev/null 2>&1; then
    ip link set "eth${i}" up
    ovs-vsctl --may-exist add-port br0 "eth${i}" -- \
      set interface "eth${i}" ofport_request="${i}"
  else
    echo "[bootstrap] WARN: eth${i} が現れませんでした（配線未完の可能性）"
  fi
done

echo "[bootstrap] fail-mode / controller / protocols / datapath-id を設定します"
ovs-vsctl set-fail-mode br0 secure
ovs-vsctl set-controller br0 "tcp:${FAUCET_MGMT_IP}:${FAUCET_OF_PORT}"
ovs-vsctl set bridge br0 protocols=OpenFlow13
ovs-vsctl set bridge br0 other-config:datapath-id="${DATAPATH_ID}"

echo "[bootstrap] 完了。br0の状態:"
ovs-vsctl show

# PID1としてフォアグラウンド維持（docker attach 前提）。ovs-vswitchd のログを追い続ける。
tail -F /var/log/openvswitch/ovs-vswitchd.log
