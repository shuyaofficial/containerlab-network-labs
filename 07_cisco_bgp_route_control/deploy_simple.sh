#!/bin/bash
# Simple deploy script - creates inject files inside containers directly
# Run via: ssh clab@orb "bash -s" < deploy_simple.sh

PROJECT="cisco-bgp-route-control"

get_pts() {
    local CONTAINER=$1
    local PID=$(docker exec ${CONTAINER} sh -c 'for p in /proc/[0-9]*; do if cat $p/cmdline 2>/dev/null | grep -q "/iol/iol.bin"; then echo ${p##*/}; fi; done' | sort -n | head -1)
    local PTS=$(docker exec ${CONTAINER} sh -c "ls -l /proc/${PID}/fd" | grep -o '/dev/pts/[0-9]*' | head -1)
    echo "${PTS:-/dev/pts/1}"
}

inject() {
    local NODE=$1
    local CONTAINER="clab-${PROJECT}-${NODE}"
    local PTS=$(get_pts ${CONTAINER})
    
    echo "=== Configuring ${NODE} (PTS=${PTS}) ==="
    
    # Read config from stdin, create python script inside container
    docker exec -i ${CONTAINER} python3 -c "
import sys, fcntl, termios
config = sys.stdin.read()
fd = open('${PTS}', 'w')
for c in config:
    fcntl.ioctl(fd, termios.TIOCSTI, c.encode())
fd.close()
print('OK: injected', len(config), 'chars')
" <<'CONFIGEOF'
$2
CONFIGEOF
}

# Wake up all routers
echo "Step 1: Waking up all routers..."
for NODE in isp-a isp-b r1 r2 r3; do
    CONTAINER="clab-${PROJECT}-${NODE}"
    PTS=$(get_pts ${CONTAINER})
    docker exec ${CONTAINER} python3 -c "
import fcntl, termios
fd = open('${PTS}', 'w')
for _ in range(5):
    fcntl.ioctl(fd, termios.TIOCSTI, b'\r')
fd.close()
" 2>/dev/null
    echo "  Woke up ${NODE}"
done

sleep 3
echo ""
echo "Step 2: Pushing configurations..."
echo ""

# ISP-A
echo "=== Configuring ISP-A ==="
CONTAINER="clab-${PROJECT}-isp-a"
PTS=$(get_pts ${CONTAINER})
docker exec -i ${CONTAINER} python3 -c "
import sys, fcntl, termios
config = sys.stdin.read()
fd = open('${PTS}', 'w')
for c in config:
    fcntl.ioctl(fd, termios.TIOCSTI, c.encode())
fd.close()
print('OK:', len(config), 'chars')
" <<'EOF'

enable
configure terminal
hostname ISP-A
!
interface Loopback0
 ip address 8.8.8.8 255.255.255.255
 exit
!
interface Ethernet0/1
 ip address 192.168.11.100 255.255.255.0
 bfd interval 100 min_rx 100 multiplier 3
 no shutdown
 exit
!
interface Ethernet0/2
 ip address 192.168.254.1 255.255.255.0
 no shutdown
 exit
!
router bgp 65001
 bgp router-id 8.8.8.1
 bgp log-neighbor-changes
 neighbor 192.168.11.1 remote-as 65002
 neighbor 192.168.11.1 fall-over bfd
 neighbor 192.168.254.2 remote-as 65003
 network 8.8.8.8 mask 255.255.255.255
 exit
!
end
write memory
EOF
echo "  ISP-A done"
sleep 8

# ISP-B
echo "=== Configuring ISP-B ==="
CONTAINER="clab-${PROJECT}-isp-b"
PTS=$(get_pts ${CONTAINER})
docker exec -i ${CONTAINER} python3 -c "
import sys, fcntl, termios
config = sys.stdin.read()
fd = open('${PTS}', 'w')
for c in config:
    fcntl.ioctl(fd, termios.TIOCSTI, c.encode())
fd.close()
print('OK:', len(config), 'chars')
" <<'EOF'

enable
configure terminal
hostname ISP-B
!
interface Loopback0
 ip address 8.8.8.8 255.255.255.255
 exit
!
interface Ethernet0/1
 ip address 192.168.22.100 255.255.255.0
 no shutdown
 exit
!
interface Ethernet0/2
 ip address 192.168.254.2 255.255.255.0
 no shutdown
 exit
!
router bgp 65003
 bgp router-id 8.8.8.2
 bgp log-neighbor-changes
 neighbor 192.168.22.2 remote-as 65002
 neighbor 192.168.254.1 remote-as 65001
 network 8.8.8.8 mask 255.255.255.255
 exit
!
end
write memory
EOF
echo "  ISP-B done"
sleep 8

# R1
echo "=== Configuring R1 ==="
CONTAINER="clab-${PROJECT}-r1"
PTS=$(get_pts ${CONTAINER})
docker exec -i ${CONTAINER} python3 -c "
import sys, fcntl, termios
config = sys.stdin.read()
fd = open('${PTS}', 'w')
for c in config:
    fcntl.ioctl(fd, termios.TIOCSTI, c.encode())
fd.close()
print('OK:', len(config), 'chars')
" <<'EOF'

enable
configure terminal
hostname R1
!
interface Loopback0
 ip address 1.1.1.1 255.255.255.255
 exit
!
interface Ethernet0/1
 ip address 192.168.11.1 255.255.255.0
 bfd interval 100 min_rx 100 multiplier 3
 no shutdown
 exit
!
interface Ethernet0/2
 ip address 192.168.12.1 255.255.255.0
 no shutdown
 exit
!
interface Ethernet0/3
 ip address 192.168.13.1 255.255.255.0
 no shutdown
 exit
!
router ospf 1
 network 1.1.1.1 0.0.0.0 area 0
 network 192.168.12.0 0.0.0.255 area 0
 network 192.168.13.0 0.0.0.255 area 0
 network 192.168.11.0 0.0.0.255 area 0
 default-information originate metric 10
 exit
!
router bgp 65002
 bgp log-neighbor-changes
 neighbor 2.2.2.2 remote-as 65002
 neighbor 2.2.2.2 update-source Loopback0
 neighbor 2.2.2.2 next-hop-self
 neighbor 192.168.11.100 remote-as 65001
 neighbor 192.168.11.100 fall-over bfd
 redistribute ospf 1
 exit
!
ip sla 1
 icmp-echo 192.168.11.100
 timeout 2000
 frequency 5
 exit
ip sla schedule 1 start-time now life forever
track 1 ip sla 1 reachability
!
ip route 0.0.0.0 0.0.0.0 192.168.11.100 track 1
!
end
write memory
EOF
echo "  R1 done"
sleep 8

# R2
echo "=== Configuring R2 ==="
CONTAINER="clab-${PROJECT}-r2"
PTS=$(get_pts ${CONTAINER})
docker exec -i ${CONTAINER} python3 -c "
import sys, fcntl, termios
config = sys.stdin.read()
fd = open('${PTS}', 'w')
for c in config:
    fcntl.ioctl(fd, termios.TIOCSTI, c.encode())
fd.close()
print('OK:', len(config), 'chars')
" <<'EOF'

enable
configure terminal
hostname R2
!
interface Loopback0
 ip address 2.2.2.2 255.255.255.255
 exit
!
interface Ethernet0/1
 ip address 192.168.22.2 255.255.255.0
 no shutdown
 exit
!
interface Ethernet0/2
 ip address 192.168.12.2 255.255.255.0
 no shutdown
 exit
!
interface Ethernet0/3
 ip address 192.168.23.2 255.255.255.0
 no shutdown
 exit
!
router ospf 1
 network 2.2.2.2 0.0.0.0 area 0
 network 192.168.12.0 0.0.0.255 area 0
 network 192.168.23.0 0.0.0.255 area 0
 network 192.168.22.0 0.0.0.255 area 0
 default-information originate metric 100
 exit
!
route-map AS_PREPEND permit 10
 set as-path prepend 65002 65002 65002
 exit
!
router bgp 65002
 bgp log-neighbor-changes
 neighbor 1.1.1.1 remote-as 65002
 neighbor 1.1.1.1 update-source Loopback0
 neighbor 1.1.1.1 next-hop-self
 neighbor 192.168.22.100 remote-as 65003
 neighbor 192.168.22.100 route-map AS_PREPEND out
 redistribute ospf 1
 exit
!
ip route 0.0.0.0 0.0.0.0 192.168.22.100
!
end
write memory
EOF
echo "  R2 done"
sleep 8

# R3
echo "=== Configuring R3 ==="
CONTAINER="clab-${PROJECT}-r3"
PTS=$(get_pts ${CONTAINER})
docker exec -i ${CONTAINER} python3 -c "
import sys, fcntl, termios
config = sys.stdin.read()
fd = open('${PTS}', 'w')
for c in config:
    fcntl.ioctl(fd, termios.TIOCSTI, c.encode())
fd.close()
print('OK:', len(config), 'chars')
" <<'EOF'

enable
configure terminal
hostname R3
!
interface Loopback0
 ip address 3.3.3.3 255.255.255.255
 exit
!
interface Ethernet0/1
 ip address 192.168.13.3 255.255.255.0
 no shutdown
 exit
!
interface Ethernet0/2
 ip address 192.168.23.3 255.255.255.0
 no shutdown
 exit
!
router ospf 1
 network 3.3.3.3 0.0.0.0 area 0
 network 192.168.13.0 0.0.0.255 area 0
 network 192.168.23.0 0.0.0.255 area 0
 exit
!
end
write memory
EOF
echo "  R3 done"

echo ""
echo "========================================"
echo "All configs deployed!"
echo "Wait 60s for BGP/OSPF to converge."
echo "========================================"
