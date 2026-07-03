#!/bin/bash
echo "=== [T4] OSPF Internal Path Failover Test ==="

echo "1. Starting continuous ping to 8.8.8.8..."
orb -m clab docker exec clab-capstone-hq-pc-sales ping -O 8.8.8.8 > /tmp/ping_t4.log &
PING_PID=$!
sleep 3

echo "2. Shutting down HQ-Core1 Et0/1 (Link to HQ-Edge1)..."
printf "terminal length 0\nconf t\nint e0/1\nshut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.21 > /dev/null

echo "3. Waiting 15 seconds for OSPF convergence..."
sleep 15

echo "4. Checking OSPF route on HQ-Core1..."
orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.21 "show ip route 0.0.0.0" | grep -A 5 "Routing entry" > /tmp/route_t4.log

echo "5. Restoring HQ-Core1 Et0/1..."
printf "terminal length 0\nconf t\nint e0/1\nno shut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.21 > /dev/null

echo "6. Waiting 10 seconds for OSPF recovery..."
sleep 10

echo "7. Stopping ping..."
kill $PING_PID
orb -m clab docker exec clab-capstone-hq-pc-sales pkill ping

echo "--- Ping Results (last 20 lines) ---"
tail -n 20 /tmp/ping_t4.log

echo "--- HQ-Core1 Route during failover ---"
cat /tmp/route_t4.log
echo "=== T4 Complete ==="
