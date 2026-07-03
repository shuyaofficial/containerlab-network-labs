#!/bin/bash
echo "=== [T1] Internet Failover Test ==="

echo "1. Starting continuous ping to 8.8.8.8..."
orb -m clab docker exec clab-capstone-hq-pc-sales ping -O 8.8.8.8 > /tmp/ping_t1.log &
PING_PID=$!
sleep 3

echo "2. Shutting down HQ-Edge1 e0/1..."
printf "terminal length 0\nconf t\nint e0/1\nshut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.12 > /dev/null

echo "3. Waiting 20 seconds for failover..."
sleep 20

echo "4. Checking default route on HQ-Core1..."
orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.21 "show ip route 0.0.0.0" | grep -A 3 "Routing entry" > /tmp/route_t1.log

echo "5. Restoring HQ-Edge1 e0/1..."
printf "terminal length 0\nconf t\nint e0/1\nno shut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.12 > /dev/null

echo "6. Stopping ping..."
kill $PING_PID
orb -m clab docker exec clab-capstone-hq-pc-sales pkill ping

echo "--- Ping Results (last 25 lines) ---"
tail -n 25 /tmp/ping_t1.log

echo "--- HQ-Core1 Route ---"
cat /tmp/route_t1.log
echo "=== T1 Complete ==="
