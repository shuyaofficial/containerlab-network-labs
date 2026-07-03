#!/usr/bin/env bash
set -euo pipefail

IOL_PID=${IOL_PID:-513}

hostname gns3-iouvm
cat > /iol/.iourc <<'IOURC'
[license]
# NOTE: IOL(IOU)ライセンスはCisco proprietaryのため公開しない。利用者自身のIOURC値（hostnameに対応するライセンス）を以下に設定すること
gns3-iouvm = 0000000000000000;
IOURC
export IOURC=/iol/.iourc

ip addr flush dev eth0 2>/dev/null || true
ip -6 addr flush dev eth0 2>/dev/null || true
rm -f "/tmp/netio${IOL_PID}"* "/tmp/iol_lock_${IOL_PID}"

previous_count=0
stable_count=0
for _ in $(seq 1 30); do
  current_count=$(find /sys/class/net -maxdepth 1 -name 'eth*' | wc -l)
  if [ "$current_count" -eq "$previous_count" ] && [ "$current_count" -gt 0 ]; then
    stable_count=$((stable_count + 1))
    [ "$stable_count" -ge 3 ] && break
  else
    stable_count=0
  fi
  previous_count=$current_count
  sleep 1
done

max_eth=$(find /sys/class/net -maxdepth 1 -name 'eth*' -printf '%f\n' \
  | sed 's/^eth//' | sort -n | tail -1)
num_slots=$(( (${max_eth:-0} + 4) / 4 ))

# IOLをPID1にしてdocker attachの標準入力をIOSへ直結する。
exec /iol/iol.bin "$IOL_PID" -e "$num_slots" -s 0 -c config.txt -m 1024 -n 1024
