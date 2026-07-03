import subprocess
import time
import re
import sys

project = 'cisco-bgp-route-control'

def get_pts(node):
    container = f'clab-{project}-{node}'
    pid_cmd = f"docker exec {container} sh -c \"for p in /proc/[0-9]*; do if cat \\$p/cmdline 2>/dev/null | grep -q /iol/iol.bin; then echo \\${{p##*/}}; fi; done\" | sort -n | head -1"
    pid = subprocess.check_output(f'ssh clab@orb "{pid_cmd}"', shell=True).decode().strip()
    pts_cmd = f'docker exec {container} sh -c "ls -l /proc/{pid}/fd" | grep -o "/dev/pts/[0-9]*" | head -1'
    pts = subprocess.check_output(f'ssh clab@orb \'{pts_cmd}\'', shell=True).decode().strip()
    return pts or '/dev/pts/1'

def inject_config(node, config):
    container = f'clab-{project}-{node}'
    pts_dev = get_pts(node)
    print(f'=== Configuring {node} (PTS={pts_dev}) ===')
    
    # Escape the config for embedding in Python string
    config_escaped = config.replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"')
    
    py_code = f"""
import fcntl, termios
config = '''{config}'''
fd = open('{pts_dev}', 'w')
for c in config:
    fcntl.ioctl(fd, termios.TIOCSTI, c.encode() if isinstance(c, str) else c)
fd.close()
"""
    
    # Write python code to a temp file, copy to container, execute
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
        f.write(py_code)
        tmp_path = f.name
    
    # Copy to VM then to container
    subprocess.run(f'scp {tmp_path} clab@orb:/tmp/inject_{node}.py', shell=True, capture_output=True)
    subprocess.run(f'ssh clab@orb "docker cp /tmp/inject_{node}.py {container}:/tmp/inject.py"', shell=True, capture_output=True)
    result = subprocess.run(f'ssh clab@orb "docker exec {container} python3 /tmp/inject.py"', shell=True, capture_output=True, text=True)
    
    if result.returncode == 0:
        print(f'  OK: {node} configured successfully')
    else:
        print(f'  FAIL: {node} - {result.stderr}')
    
    import os
    os.unlink(tmp_path)

# Wake up all routers first
print("Step 1: Waking up all routers...")
for node in ['isp-a', 'isp-b', 'r1', 'r2', 'r3']:
    container = f'clab-{project}-{node}'
    pts_dev = get_pts(node)
    py_code = f"import fcntl, termios; fd = open('{pts_dev}', 'w'); [fcntl.ioctl(fd, termios.TIOCSTI, b'\\r') for _ in range(5)]; fd.close()"
    subprocess.run(f'ssh clab@orb "docker exec {container} python3 -c \\"{py_code}\\""', shell=True, capture_output=True)
    print(f'  Woke up {node}')

time.sleep(3)
print("\nStep 2: Pushing configurations...\n")

# ISP-A
inject_config('isp-a', """
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
""")

time.sleep(8)

# ISP-B
inject_config('isp-b', """
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
""")

time.sleep(8)

# R1
inject_config('r1', """
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
""")

time.sleep(8)

# R2
inject_config('r2', """
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
""")

time.sleep(8)

# R3
inject_config('r3', """
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
""")

print("\n========================================")
print("All configs deployed!")
print("Wait about 60s for BGP/OSPF convergence")
print("========================================")
