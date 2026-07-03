#!/bin/bash
echo "=== [T2] Default Gateway (HSRP) Failover Test ==="

echo "1. Starting continuous ping to 8.8.8.8..."
orb -m clab docker exec clab-capstone-hq-pc-sales ping -O 8.8.8.8 > /tmp/ping_t2.log &
PING_PID=$!
sleep 3

echo "2. Shutting down HQ-Core1 Vlan10..."
printf "terminal length 0\nconf t\nint vlan 10\nshut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.21 > /dev/null

echo "3. Waiting 15 seconds for HSRP failover..."
sleep 15

echo "4. Checking HSRP status on HQ-Core2..."
orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.22 "show standby brief" > /tmp/hsrp_t2.log

echo "5. Restoring HQ-Core1 Vlan10..."
printf "terminal length 0\nconf t\nint vlan 10\nno shut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.21 > /dev/null

echo "6. Waiting 15 seconds for HSRP preempt..."
sleep 15

echo "7. Stopping ping..."
kill $PING_PID
orb -m clab docker exec clab-capstone-hq-pc-sales pkill ping

echo "--- Ping Results (last 30 lines) ---"
tail -n 30 /tmp/ping_t2.log

echo "--- HQ-Core2 HSRP Status during failover ---"
cat /tmp/hsrp_t2.log
echo "=== T2 Complete ==="
