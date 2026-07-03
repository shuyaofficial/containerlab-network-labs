#!/usr/bin/env python3
"""
Run show commands on IOL routers via TIOCSTI and capture output to files.
Works by redirecting output to flash: and then reading the file.
"""
import subprocess
import time
import sys

PROJECT = 'cisco-bgp-route-control'

def inject_command(node, command):
    """Inject a command via TIOCSTI to the router console."""
    container = f'clab-{PROJECT}-{node}'
    
    # Get PTS
    pid_cmd = f"docker exec {container} sh -c 'for p in /proc/[0-9]*; do if cat $p/cmdline 2>/dev/null | grep -q /iol/iol.bin; then echo ${{p##*/}}; fi; done' | sort -n | head -1"
    pid = subprocess.check_output(pid_cmd, shell=True).decode().strip()
    
    pts_cmd = f'docker exec {container} sh -c "ls -l /proc/{pid}/fd" | grep -o "/dev/pts/[0-9]*" | head -1'
    pts = subprocess.check_output(pts_cmd, shell=True).decode().strip() or '/dev/pts/1'
    
    # Inject the command
    py_code = f'''
import fcntl, termios
fd = open("{pts}", "w")
for c in chr(13) + "{command}" + chr(13):
    fcntl.ioctl(fd, termios.TIOCSTI, c.encode())
fd.close()
'''
    subprocess.run(f'docker exec {container} python3 -c \'{py_code}\'', shell=True, capture_output=True)


def show_and_capture(node, show_command, output_file='verify.txt'):
    """Run a show command by injecting it via TIOCSTI and capturing output from docker logs."""
    container = f'clab-{PROJECT}-{node}'
    
    # 1. Get current logs to find the "before" snapshot line count
    res_before = subprocess.run(f'docker logs {container}', shell=True, capture_output=True, text=True)
    before_count = len(res_before.stdout.splitlines())
    
    # 2. Wake up and ensure enable mode
    inject_command(node, '')
    time.sleep(0.5)
    inject_command(node, 'enable')
    time.sleep(0.5)
    
    # 3. Set terminal length 0 (to avoid --More-- prompts)
    inject_command(node, 'terminal length 0')
    time.sleep(0.5)
    
    # 4. Inject the show command
    inject_command(node, show_command)
    
    # 5. Wait for command output to generate in logs
    time.sleep(3)
    
    # 6. Get new logs
    res_after = subprocess.run(f'docker logs {container}', shell=True, capture_output=True, text=True)
    after_lines = res_after.stdout.splitlines()
    
    # 7. Extract only the new lines
    new_lines = after_lines[before_count:]
    
    return '\n'.join(new_lines)


if __name__ == '__main__':
    nodes = ['r1', 'r2', 'r3', 'isp-a', 'isp-b']
    
    for node in nodes:
        print(f'\n{"="*60}')
        print(f'  {node.upper()}')
        print(f'{"="*60}')
        
        # show ip interface brief
        output = show_and_capture(node, 'show ip interface brief')
        if output.strip():
            print(output)
        else:
            print('  (no output captured - router may still be booting)')
        
        time.sleep(2)
    
    # Special checks
    print(f'\n{"="*60}')
    print(f'  R1: BGP Summary')
    print(f'{"="*60}')
    output = show_and_capture('r1', 'show ip bgp summary')
    print(output if output.strip() else '  (no output)')
    
    print(f'\n{"="*60}')
    print(f'  R1: Track Status')
    print(f'{"="*60}')
    output = show_and_capture('r1', 'show track 1')
    print(output if output.strip() else '  (no output)')
    
    print(f'\n{"="*60}')
    print(f'  R1: BFD Neighbors')
    print(f'{"="*60}')
    output = show_and_capture('r1', 'show bfd neighbors')
    print(output if output.strip() else '  (no output)')
    
    print(f'\n{"="*60}')
    print(f'  ISP-B: BGP Table (AS Path check)')
    print(f'{"="*60}')
    output = show_and_capture('isp-b', 'show ip bgp')
    print(output if output.strip() else '  (no output)')
    
    print(f'\n{"="*60}')
    print(f'  R3: Routing Table')
    print(f'{"="*60}')
    output = show_and_capture('r3', 'show ip route')
    print(output if output.strip() else '  (no output)')
