import os
import sys
import time
import subprocess
import re

nodes = ['isp-b', 'r2']
project = 'cisco-bgp-route-control'
results = {}

for node in nodes:
    container = f'clab-{project}-{node}'
    
    # PID を取得
    try:
        pid_cmd = f"sudo docker exec {container} sh -c 'for p in /proc/[0-9]*; do if cat $p/cmdline 2>/dev/null | grep -q iol.bin; then echo ${{p##*/}}; fi; done'"
        pid_out = subprocess.check_output(pid_cmd, shell=True).decode().strip()
        pid = pid_out.split('\n')[0].strip()
    except Exception as e:
        print(f"Error getting PID for {node}: {e}")
        continue
        
    # pts を取得
    try:
        fds = subprocess.check_output(f"sudo docker exec {container} sh -c 'ls -l /proc/{pid}/fd'", shell=True).decode()
        pts_match = re.search(r'/dev/pts/(\d+)', fds)
        pts_dev = f'/dev/pts/{pts_match.group(1)}' if pts_match else '/dev/pts/1'
    except Exception as e:
        pts_dev = '/dev/pts/1'
        
    # 実行するコマンド
    if node == 'isp-b':
        cmds = "\r\n\r\nenable\r\nterminal length 0\r\nshow ip bgp\r\nshow ip bgp 3.3.3.3\r\nshow ip route 3.3.3.3\r\n"
    else: # r2
        cmds = "\r\n\r\nenable\r\nterminal length 0\r\nshow run | section route-map\r\nshow run | section router bgp\r\nshow ip bgp neighbor 192.168.22.100 advertised-routes\r\n"
        
    # 注入
    py_inject = f"import fcntl, termios; fd = open('{pts_dev}', 'w'); [fcntl.ioctl(fd, termios.TIOCSTI, c) for c in {repr(cmds)}]; fd.close()"
    try:
        subprocess.check_call(f"sudo docker exec -i {container} python3 -c {repr(py_inject)}", shell=True)
    except Exception as e:
        print(f"Failed to inject to {node}: {e}")
        
time.sleep(4)

# ログを回収
for node in nodes:
    container = f'clab-{project}-{node}'
    try:
        logs = subprocess.check_output(f"sudo docker logs {container}", shell=True).decode(errors='replace')
        # 最新の出力を切り取るため、後ろから100行を取得
        lines = logs.split('\n')
        last_lines = '\n'.join(lines[-150:])
        print(f"\n=================== {node.upper()} LOGS ===================")
        print(last_lines)
    except Exception as e:
        print(f"Failed to get logs for {node}: {e}")
