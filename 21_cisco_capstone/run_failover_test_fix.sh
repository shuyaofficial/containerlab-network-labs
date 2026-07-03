#!/bin/bash
PCAP_FILE="/Users/shuya/Documents/claude/Mac仮想環境構築/21_cisco_capstone/failover_test.pcap"
rm -f "$PCAP_FILE"

echo "Starting tcpdump in background..."
orb -m clab docker exec clab-capstone-hq-pc-sales tcpdump -n -i eth1 -w /tmp/capture.pcap &
TCPDUMP_PID=$!

echo "Starting ping in background..."
orb -m clab docker exec clab-capstone-hq-pc-sales ping 8.8.8.8 > /dev/null &
PING_PID=$!

echo "Waiting for traffic to flow normally (5s)..."
sleep 5

echo "Shutting down HQ-Edge1 e0/1..."
printf "terminal length 0\nconf t\nint e0/1\nshut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.12 > /dev/null

echo "Waiting for failover and BGP convergence (15s)..."
sleep 15

echo "Bringing HQ-Edge1 e0/1 back up..."
printf "terminal length 0\nconf t\nint e0/1\nno shut\nend\n" | orb -m clab sshpass -p admin ssh -o StrictHostKeyChecking=no -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa admin@172.20.20.12 > /dev/null

echo "Waiting for traffic to restore (10s)..."
sleep 10

echo "Stopping ping and tcpdump..."
kill $PING_PID
orb -m clab docker exec clab-capstone-hq-pc-sales pkill tcpdump
orb -m clab docker exec clab-capstone-hq-pc-sales pkill ping

echo "Extracting pcap file from container..."
orb -m clab docker exec clab-capstone-hq-pc-sales cat /tmp/capture.pcap > "$PCAP_FILE"

echo "Opening Wireshark..."
open -a Wireshark "$PCAP_FILE"
echo "Done!"
