#!/bin/bash
# =============================================================================
# !!! DEPRECATED / 使用しないこと（2026-06-29）!!!
# このカスタム entrypoint がテーマ23のL2全断(Split Brain / HSRP unknown)の主因。
#   - `iouyap $IOL_PID` はインスタンスID(=3等)をiouyapに渡し "lock on ID 3" で即死。
#     正しくは NETIOベースポート=513。さらに -f iouyap.ini -n NETMAP と cwd /iol が必須。
#   - stock entrypoint が担う clab config注入(SSH/admin)も -c config.txt でバイパスしていた。
# 対応: campus.clab.yml から bind を撤去し stock entrypoint に戻した。
#       iouyap は deploy.sh が deploy 後に `iouyap 513`(-w /iol) で起動する。
# このファイルは記録目的で残すのみ。どのノードからも bind しないこと。
# =============================================================================
IOL_PID=${IOL_PID:-513}
hostname gns3-iouvm
# NOTE: IOL(IOU)ライセンスはCisco proprietaryのため公開しない。利用者自身のIOURC値（hostnameに対応するライセンス）を以下に設定すること
printf "[license]\ngns3-iouvm = 0000000000000000;\n" > /iol/.iourc
export IOURC=/iol/.iourc
ip addr flush dev eth0 2>/dev/null
ip -6 addr flush dev eth0 2>/dev/null
rm -f /tmp/netio${IOL_PID}* /tmp/iol_lock_${IOL_PID}

# Wait for container interfaces to stabilize (race with containerlab link creation)
prev_count=0
stable=0
for i in $(seq 1 30); do
  cur_count=$(ls /sys/class/net 2>/dev/null | grep -c eth)
  if [ "$cur_count" -eq "$prev_count" ] && [ "$cur_count" -gt 0 ]; then
    stable=$((stable + 1))
    [ "$stable" -ge 3 ] && break
  else
    stable=0
  fi
  prev_count=$cur_count
  sleep 1
done

max_eth=$(ls /sys/class/net 2>/dev/null | grep eth | grep -o -E "[0-9]+" | sort -n | tail -1)
num_slots=$(( (${max_eth:-0} + 4) / 4 ))

# Start iouyap in the background. It will wait for IOL to create the socket.
( sleep 2 ; /usr/bin/iouyap $IOL_PID ) &

# Run IOL in the foreground WITHOUT exec so it doesn't take PID 1!
# This allows iouyap to connect, and docker attach to work!
/iol/iol.bin $IOL_PID -e $num_slots -s 0 -c config.txt -n 1024
