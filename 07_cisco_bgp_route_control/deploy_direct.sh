#!/bin/bash
# Deploy configs by writing directly to /iol/config.txt and restarting containers
# This is the most reliable method for containerlab IOL

PROJECT="cisco-bgp-route-control"

write_config() {
    local NODE=$1
    local CONFIG=$2
    local CONTAINER="clab-${PROJECT}-${NODE}"
    
    echo "=== Writing config for ${NODE} ==="
    
    # Write config.txt directly into the container
    echo "${CONFIG}" | docker exec -i ${CONTAINER} sh -c 'cat > /iol/config.txt'
    
    if [ $? -eq 0 ]; then
        echo "  OK: ${NODE} config written"
    else
        echo "  FAIL: ${NODE}"
    fi
}

# ===== ISP-A config =====
write_config "isp-a" 'hostname ISP-A
!
no aaa new-model
!
ip domain name lab
!
ip cef
!
ipv6 unicast-routing
!
no ip domain lookup
!
username admin privilege 15 secret admin
!
vrf definition clab-mgmt
 description clab-mgmt
 address-family ipv4
 !
 address-family ipv6
 !
!
interface Loopback0
 ip address 8.8.8.8 255.255.255.255
!
interface Ethernet0/0
 vrf forwarding clab-mgmt
 description clab-mgmt
 ip address 172.20.20.4 255.255.255.0
 ipv6 address 3fff:172:20:20::4/64
 no shutdown
!
interface Ethernet0/1
 ip address 192.168.11.100 255.255.255.0
 bfd interval 100 min_rx 100 multiplier 3
 no shutdown
!
interface Ethernet0/2
 ip address 192.168.254.1 255.255.255.0
 no shutdown
!
interface Ethernet0/3
 no shutdown
!
router bgp 65001
 bgp router-id 8.8.8.1
 bgp log-neighbor-changes
 neighbor 192.168.11.1 remote-as 65002
 neighbor 192.168.11.1 fall-over bfd
 neighbor 192.168.254.2 remote-as 65003
 network 8.8.8.8 mask 255.255.255.255
!
ip forward-protocol nd
!
ip route vrf clab-mgmt 0.0.0.0 0.0.0.0 Ethernet0/0 172.20.20.1
ipv6 route vrf clab-mgmt ::/0 Ethernet0/0 3fff:172:20:20::1
!
ip ssh version 2
crypto key generate rsa modulus 2048
!
line vty 0 4
 login local
 transport input ssh
!
end'

# ===== ISP-B config =====
write_config "isp-b" 'hostname ISP-B
!
no aaa new-model
!
ip domain name lab
!
ip cef
!
ipv6 unicast-routing
!
no ip domain lookup
!
username admin privilege 15 secret admin
!
vrf definition clab-mgmt
 description clab-mgmt
 address-family ipv4
 !
 address-family ipv6
 !
!
interface Loopback0
 ip address 8.8.8.8 255.255.255.255
!
interface Ethernet0/0
 vrf forwarding clab-mgmt
 description clab-mgmt
 ip address 172.20.20.3 255.255.255.0
 ipv6 address 3fff:172:20:20::3/64
 no shutdown
!
interface Ethernet0/1
 ip address 192.168.22.100 255.255.255.0
 no shutdown
!
interface Ethernet0/2
 ip address 192.168.254.2 255.255.255.0
 no shutdown
!
interface Ethernet0/3
 no shutdown
!
router bgp 65003
 bgp router-id 8.8.8.2
 bgp log-neighbor-changes
 neighbor 192.168.22.2 remote-as 65002
 neighbor 192.168.254.1 remote-as 65001
 network 8.8.8.8 mask 255.255.255.255
!
ip forward-protocol nd
!
ip route vrf clab-mgmt 0.0.0.0 0.0.0.0 Ethernet0/0 172.20.20.1
ipv6 route vrf clab-mgmt ::/0 Ethernet0/0 3fff:172:20:20::1
!
ip ssh version 2
crypto key generate rsa modulus 2048
!
line vty 0 4
 login local
 transport input ssh
!
end'

# ===== R1 config =====
write_config "r1" 'hostname R1
!
no aaa new-model
!
ip domain name lab
!
ip cef
!
ipv6 unicast-routing
!
no ip domain lookup
!
username admin privilege 15 secret admin
!
vrf definition clab-mgmt
 description clab-mgmt
 address-family ipv4
 !
 address-family ipv6
 !
!
track 1 ip sla 1 reachability
!
interface Loopback0
 ip address 1.1.1.1 255.255.255.255
!
interface Ethernet0/0
 vrf forwarding clab-mgmt
 description clab-mgmt
 ip address 172.20.20.5 255.255.255.0
 ipv6 address 3fff:172:20:20::5/64
 no shutdown
!
interface Ethernet0/1
 ip address 192.168.11.1 255.255.255.0
 bfd interval 100 min_rx 100 multiplier 3
 no shutdown
!
interface Ethernet0/2
 ip address 192.168.12.1 255.255.255.0
 no shutdown
!
interface Ethernet0/3
 ip address 192.168.13.1 255.255.255.0
 no shutdown
!
router ospf 1
 network 1.1.1.1 0.0.0.0 area 0
 network 192.168.11.0 0.0.0.255 area 0
 network 192.168.12.0 0.0.0.255 area 0
 network 192.168.13.0 0.0.0.255 area 0
 default-information originate metric 10
!
router bgp 65002
 bgp log-neighbor-changes
 neighbor 2.2.2.2 remote-as 65002
 neighbor 2.2.2.2 update-source Loopback0
 neighbor 2.2.2.2 next-hop-self
 neighbor 192.168.11.100 remote-as 65001
 neighbor 192.168.11.100 fall-over bfd
 redistribute ospf 1
!
ip forward-protocol nd
!
ip route 0.0.0.0 0.0.0.0 192.168.11.100 track 1
ip route vrf clab-mgmt 0.0.0.0 0.0.0.0 Ethernet0/0 172.20.20.1
ipv6 route vrf clab-mgmt ::/0 Ethernet0/0 3fff:172:20:20::1
!
ip sla 1
 icmp-echo 192.168.11.100
 timeout 2000
 frequency 5
ip sla schedule 1 start-time now life forever
!
ip ssh version 2
crypto key generate rsa modulus 2048
!
line vty 0 4
 login local
 transport input ssh
!
end'

# ===== R2 config =====
write_config "r2" 'hostname R2
!
no aaa new-model
!
ip domain name lab
!
ip cef
!
ipv6 unicast-routing
!
no ip domain lookup
!
username admin privilege 15 secret admin
!
vrf definition clab-mgmt
 description clab-mgmt
 address-family ipv4
 !
 address-family ipv6
 !
!
interface Loopback0
 ip address 2.2.2.2 255.255.255.255
!
interface Ethernet0/0
 vrf forwarding clab-mgmt
 description clab-mgmt
 ip address 172.20.20.2 255.255.255.0
 ipv6 address 3fff:172:20:20::2/64
 no shutdown
!
interface Ethernet0/1
 ip address 192.168.22.2 255.255.255.0
 no shutdown
!
interface Ethernet0/2
 ip address 192.168.12.2 255.255.255.0
 no shutdown
!
interface Ethernet0/3
 ip address 192.168.23.2 255.255.255.0
 no shutdown
!
router ospf 1
 network 2.2.2.2 0.0.0.0 area 0
 network 192.168.12.0 0.0.0.255 area 0
 network 192.168.22.0 0.0.0.255 area 0
 network 192.168.23.0 0.0.0.255 area 0
 default-information originate metric 100
!
router bgp 65002
 bgp log-neighbor-changes
 neighbor 1.1.1.1 remote-as 65002
 neighbor 1.1.1.1 update-source Loopback0
 neighbor 1.1.1.1 next-hop-self
 neighbor 192.168.22.100 remote-as 65003
 neighbor 192.168.22.100 route-map AS_PREPEND out
 redistribute ospf 1
!
ip forward-protocol nd
!
ip route 0.0.0.0 0.0.0.0 192.168.22.100
ip route vrf clab-mgmt 0.0.0.0 0.0.0.0 Ethernet0/0 172.20.20.1
ipv6 route vrf clab-mgmt ::/0 Ethernet0/0 3fff:172:20:20::1
!
ip ssh version 2
crypto key generate rsa modulus 2048
!
route-map AS_PREPEND permit 10
 set as-path prepend 65002 65002 65002
!
line vty 0 4
 login local
 transport input ssh
!
end'

# ===== R3 config =====
write_config "r3" 'hostname R3
!
no aaa new-model
!
ip domain name lab
!
ip cef
!
ipv6 unicast-routing
!
no ip domain lookup
!
username admin privilege 15 secret admin
!
vrf definition clab-mgmt
 description clab-mgmt
 address-family ipv4
 !
 address-family ipv6
 !
!
interface Loopback0
 ip address 3.3.3.3 255.255.255.255
!
interface Ethernet0/0
 vrf forwarding clab-mgmt
 description clab-mgmt
 ip address 172.20.20.6 255.255.255.0
 ipv6 address 3fff:172:20:20::6/64
 no shutdown
!
interface Ethernet0/1
 ip address 192.168.13.3 255.255.255.0
 no shutdown
!
interface Ethernet0/2
 ip address 192.168.23.3 255.255.255.0
 no shutdown
!
interface Ethernet0/3
 no shutdown
!
router ospf 1
 network 3.3.3.3 0.0.0.0 area 0
 network 192.168.13.0 0.0.0.255 area 0
 network 192.168.23.0 0.0.0.255 area 0
!
ip forward-protocol nd
!
ip route vrf clab-mgmt 0.0.0.0 0.0.0.0 Ethernet0/0 172.20.20.1
ipv6 route vrf clab-mgmt ::/0 Ethernet0/0 3fff:172:20:20::1
!
ip ssh version 2
crypto key generate rsa modulus 2048
!
line vty 0 4
 login local
 transport input ssh
!
end'

echo ""
echo "========================================"
echo "All configs written to /iol/config.txt"
echo "Now restarting containers to apply..."
echo "========================================"

# Restart all containers to load the new configs
for NODE in isp-a isp-b r1 r2 r3; do
    CONTAINER="clab-${PROJECT}-${NODE}"
    echo "Restarting ${NODE}..."
    docker restart ${CONTAINER}
done

echo ""
echo "All containers restarted."
echo "Wait 90 seconds for boot + BGP/OSPF convergence."
