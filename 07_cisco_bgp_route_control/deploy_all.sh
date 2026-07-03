#!/bin/bash
# Full deployment script for Challenge 07: BGP Route Control
# Runs inside the clab OrbStack VM via ssh

PROJECT="cisco-bgp-route-control"

inject_config() {
    local NODE=$1
    local CONFIG=$2
    local CONTAINER="clab-${PROJECT}-${NODE}"
    
    echo "=== Configuring ${NODE}... ==="
    
    # Find the IOL process PID
    PID=$(docker exec ${CONTAINER} sh -c 'for p in /proc/[0-9]*; do if cat $p/cmdline 2>/dev/null | grep -q "/iol/iol.bin"; then echo ${p##*/}; fi; done' | sort -n | head -1)
    
    if [ -z "$PID" ]; then
        echo "ERROR: Could not find IOL process for ${NODE}"
        return 1
    fi
    
    # Find the pts device
    PTS_NUM=$(docker exec ${CONTAINER} sh -c "ls -l /proc/${PID}/fd" | grep -o '/dev/pts/[0-9]*' | head -1 | grep -o '[0-9]*$')
    PTS_DEV="/dev/pts/${PTS_NUM:-1}"
    
    echo "  PID=${PID}, PTS=${PTS_DEV}"
    
    # Inject config character by character via Python
    docker exec -i ${CONTAINER} python3 -c "
import fcntl, termios
config = '''${CONFIG}'''
fd = open('${PTS_DEV}', 'w')
for c in config:
    fcntl.ioctl(fd, termios.TIOCSTI, c.encode() if isinstance(c, str) else c)
fd.close()
"
    
    if [ $? -eq 0 ]; then
        echo "  OK: ${NODE} configured successfully"
    else
        echo "  FAIL: ${NODE} configuration failed"
    fi
}

echo "Step 1: Waking up all routers..."
for NODE in isp-a isp-b r1 r2 r3; do
    CONTAINER="clab-${PROJECT}-${NODE}"
    PID=$(docker exec ${CONTAINER} sh -c 'for p in /proc/[0-9]*; do if cat $p/cmdline 2>/dev/null | grep -q "/iol/iol.bin"; then echo ${p##*/}; fi; done' | sort -n | head -1)
    PTS_NUM=$(docker exec ${CONTAINER} sh -c "ls -l /proc/${PID}/fd" | grep -o '/dev/pts/[0-9]*' | head -1 | grep -o '[0-9]*$')
    PTS_DEV="/dev/pts/${PTS_NUM:-1}"
    docker exec -i ${CONTAINER} python3 -c "
import fcntl, termios
fd = open('${PTS_DEV}', 'w')
for _ in range(5):
    fcntl.ioctl(fd, termios.TIOCSTI, b'\r')
fd.close()
" 2>/dev/null
done

sleep 3
echo ""
echo "Step 2: Pushing configurations..."
echo ""

# ===== ISP-A =====
inject_config "isp-a" '
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
'

sleep 5

# ===== ISP-B =====
inject_config "isp-b" '
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
'

sleep 5

# ===== R1 =====
inject_config "r1" '
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
'

sleep 5

# ===== R2 =====
inject_config "r2" '
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
'

sleep 5

# ===== R3 =====
inject_config "r3" '
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
'

echo ""
echo "========================================"
echo "All configs deployed!"
echo "Wait about 60s for BGP/OSPF convergence"
echo "========================================"
