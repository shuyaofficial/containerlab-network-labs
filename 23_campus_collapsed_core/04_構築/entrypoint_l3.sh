#!/bin/bash
IOL_PID=${IOL_PID:-513}
hostname gns3-iouvm
cat > /iol/.iourc << "IOURC"
[license]
# NOTE: IOL(IOU)ライセンスはCisco proprietaryのため公開しない。利用者自身のIOURC値（hostnameに対応するライセンス）を以下に設定すること
gns3-iouvm = 0000000000000000;
IOURC
export IOURC=/iol/.iourc
ip addr flush dev eth0 2>/dev/null
ip -6 addr flush dev eth0 2>/dev/null
rm -f /tmp/netio${IOL_PID}* /tmp/iol_lock_${IOL_PID}

max_eth=$(ls /sys/class/net 2>/dev/null | grep eth | grep -o -E "[0-9]+" | sort -n | tail -1)
num_slots=$(( (${max_eth:-0} + 4) / 4 ))

# Start iouyap in the background after waiting for IOL to initialize its sockets
( sleep 2 ; /usr/bin/iouyap $IOL_PID ) &

# Run IOL in the foreground so 'docker attach' can connect to its stdin/stdout
/iol/iol.bin $IOL_PID -e $num_slots -s 0 -c config.txt -n 1024
