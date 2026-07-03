#!/bin/bash
echo "=== [T3] EtherChannel Link Failover Test ==="

echo "1. Starting continuous ping to 8.8.8.8..."
orb -m clab docker exec clab-capstone-hq-pc-sales ping -O 8.8.8.8 > /tmp/ping_t3.log &
PING_PID=$!
sleep 3

echo "2. Shutting down HQ-Core1 Et1/1 (one link in Po1)..."
printf "terminal length 0\nconf t\nint e1/1\nshut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.21 > /dev/null

echo "3. Waiting 10 seconds for LACP failover..."
sleep 10

echo "4. Checking EtherChannel status on HQ-Core1..."
orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.21 "show etherchannel summary" > /tmp/po_t3.log

echo "5. Restoring HQ-Core1 Et1/1..."
printf "terminal length 0\nconf t\nint e1/1\nno shut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.21 > /dev/null

echo "6. Stopping ping..."
kill $PING_PID
orb -m clab docker exec clab-capstone-hq-pc-sales pkill ping

echo "--- Ping Results (last 20 lines) ---"
tail -n 20 /tmp/ping_t3.log

echo "--- HQ-Core1 EtherChannel Status during failover ---"
cat /tmp/po_t3.log
echo "=== T3 Complete ==="
