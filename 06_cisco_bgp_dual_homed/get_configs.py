import os
import sys
import time
import subprocess
import re

nodes = ['isp-a', 'isp-b', 'r1', 'r2', 'r3']
project = 'cisco-bgp-dual-homed'

for node in nodes:
    container = f'clab-{project}-{node}'
    print(f'Fetching config for {node} ({container})...')
    
    # /proc から iol.bin の PID を取得
    try:
        pid_cmd = "sudo docker exec " + container + " sh -c 'for p in /proc/[0-9]*; do if cat $p/cmdline 2>/dev/null | grep -q iol.bin; then echo ${p##*/}; fi; done'"
        pid_out = subprocess.check_output(pid_cmd, shell=True).decode().strip()
        pid = pid_out.split('\n')[0].strip()
        if not pid:
            raise Exception("PID not found in proc filesystem")
    except Exception as e:
        print(f'Error getting PID for {node}: {e}')
        continue
        
    print(f'Found PID: {pid} for {node}')
    
    # iol.bin が開いている pts を検索
    try:
        fds = subprocess.check_output(f"sudo docker exec {container} sh -c 'ls -l /proc/{pid}/fd'", shell=True).decode()
        pts_match = re.search(r'/dev/pts/(\d+)', fds)
        if pts_match:
            pts_dev = f'/dev/pts/{pts_match.group(1)}'
        else:
            pts_dev = '/dev/pts/1' # デフォルト
    except Exception as e:
        pts_dev = '/dev/pts/1'
        
    print(f'Using {pts_dev} for {node}')
    
    # コマンドを注入 (SyntaxErrorを防ぐため完全にセミコロンで繋いだ1行のワンライナーにする)
    cmds = "\r\n\r\nenable\r\nterminal length 0\r\nshow running-config\r\n"
    py_inject = f"import fcntl, termios; fd = open('{pts_dev}', 'w'); [fcntl.ioctl(fd, termios.TIOCSTI, c) for c in {repr(cmds)}]; fd.close()"
    
    try:
        subprocess.check_call(f"sudo docker exec -i {container} python3 -c {repr(py_inject)}", shell=True)
    except Exception as e:
        print(f'Failed to inject commands to {node}: {e}')
        continue
        
    # 出力を待つ
    time.sleep(4)
    
    # ログを取得してパース
    try:
        logs = subprocess.check_output(f"sudo docker logs {container}", shell=True).decode(errors='replace')
        # show running-config から最後のプロンプト までの部分を抽出
        pattern = r'(Current configuration.*end)'
        match = re.search(pattern, logs, re.DOTALL)
        if match:
            config_content = match.group(1)
        else:
            idx = logs.rfind('show running-config')
            if idx != -1:
                config_content = logs[idx + len('show running-config'):].strip()
            else:
                config_content = logs
                
        # クリーニング: 改行文字の統一と余分な出力をカット
        config_lines = []
        for line in config_content.split('\n'):
            line_clean = line.replace('\r', '').strip()
            if line_clean == 'show running-config':
                continue
            config_lines.append(line_clean)
        
        config_cleaned = '\n'.join(config_lines)
        
        # 保存先パス
        dest_path = f'/Users/shuya/Documents/claude/Mac仮想環境構築/06_cisco_bgp_dual_homed/config/{node}.cfg'
        with open(dest_path, 'w') as f:
            f.write(config_cleaned)
        print(f'Successfully saved config for {node} to {dest_path}')
    except Exception as e:
        print(f'Failed to fetch logs or save config for {node}: {e}')

print('All configs processed!')
