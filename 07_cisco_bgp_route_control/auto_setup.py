import os
import sys
import time
import subprocess
import re

nodes = ['isp-a', 'isp-b', 'r1', 'r2', 'r3']
project = 'cisco-bgp-route-control'

configs = {
    'isp-a': """
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
 neighbor 192.168.254.2 remote-as 65003
 network 8.8.8.8 mask 255.255.255.255
 exit
!
end
write memory
""",
    'isp-b': """
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
""",
    'r1': """
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
""",
    'r2': """
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
router bgp 65002
 bgp log-neighbor-changes
 neighbor 1.1.1.1 remote-as 65002
 neighbor 1.1.1.1 update-source Loopback0
 neighbor 1.1.1.1 next-hop-self
 neighbor 192.168.22.100 remote-as 65003
 redistribute ospf 1
 exit
!
ip route 0.0.0.0 0.0.0.0 192.168.22.100
!
end
write memory
""",
    'r3': """
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
"""
}

# 機器の起動を待つためのエンターキー連続送信スクリプト
print("Waiting for routers to boot up... Sending RETURN to active terminals.")
for node in nodes:
    container = f'clab-{project}-{node}'
    try:
        # "/iol/iol.bin" を含むものだけを検索（自分自身のgrep等を排除するため）
        pid_cmd = "sudo docker exec " + container + " sh -c 'for p in /proc/[0-9]*; do if cat $p/cmdline 2>/dev/null | grep -q \"/iol/iol.bin\"; then echo ${p##*/}; fi; done'"
        pid_out = subprocess.check_output(pid_cmd, shell=True).decode().strip()
        pids = [int(p) for p in pid_out.split('\n') if p.strip()]
        pid = str(min(pids))
        
        fds = subprocess.check_output(f"sudo docker exec {container} sh -c 'ls -l /proc/{pid}/fd'", shell=True).decode()
        pts_match = re.search(r'/dev/pts/(\d+)', fds)
        pts_dev = f'/dev/pts/{pts_match.group(1)}' if pts_match else '/dev/pts/1'
        
        # エンターを数回送って活性化
        py_inject = f"import fcntl, termios; fd = open('{pts_dev}', 'w'); [fcntl.ioctl(fd, termios.TIOCSTI, '\\r') for _ in range(5)]; fd.close()"
        subprocess.check_call(f"sudo docker exec -i {container} python3 -c {repr(py_inject)}", shell=True)
    except Exception as e:
        print(f"Active err for {node}: {e}")

time.sleep(2)

# 各ルータにコンフィグを注入
for node in nodes:
    container = f'clab-{project}-{node}'
    print(f'\n--- Instantiating config on {node}... ---')
    
    # PID / pts を再取得
    try:
        pid_cmd = "sudo docker exec " + container + " sh -c 'for p in /proc/[0-9]*; do if cat $p/cmdline 2>/dev/null | grep -q \"/iol/iol.bin\"; then echo ${p##*/}; fi; done'"
        pid_out = subprocess.check_output(pid_cmd, shell=True).decode().strip()
        pids = [int(p) for p in pid_out.split('\n') if p.strip()]
        pid = str(min(pids))
        
        fds = subprocess.check_output(f"sudo docker exec {container} sh -c 'ls -l /proc/{pid}/fd'", shell=True).decode()
        pts_match = re.search(r'/dev/pts/(\d+)', fds)
        pts_dev = f'/dev/pts/{pts_match.group(1)}' if pts_match else '/dev/pts/1'
    except Exception as e:
        print(f"Error getting pts dev for config: {e}")
        continue
        
    cmds = configs[node]
    py_inject = f"import fcntl, termios; fd = open('{pts_dev}', 'w'); [fcntl.ioctl(fd, termios.TIOCSTI, c) for c in {repr(cmds)}]; fd.close()"
    
    try:
        subprocess.check_call(f"sudo docker exec -i {container} python3 -c {repr(py_inject)}", shell=True)
        print(f"Successfully configured {node}!")
    except Exception as e:
        print(f"Failed to configure {node}: {e}")

print("\nAll initial configurations have been successfully pushed!")
