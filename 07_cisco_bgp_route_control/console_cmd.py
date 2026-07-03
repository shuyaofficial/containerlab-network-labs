#!/usr/bin/env python3
"""Verify router configs by injecting show commands and reading output from pts."""
import fcntl
import termios
import time
import os
import sys
import select

def send_and_read(pts_dev, command, wait=2):
    """Send a command via TIOCSTI and read output from the pts."""
    # Send the command
    fd_write = open(pts_dev, 'w')
    for c in f"\r{command}\r":
        fcntl.ioctl(fd_write, termios.TIOCSTI, c.encode())
    fd_write.close()
    
    time.sleep(wait)
    
    # Try to read from pts
    fd_read = os.open(pts_dev, os.O_RDONLY | os.O_NONBLOCK)
    output = b""
    try:
        while True:
            r, _, _ = select.select([fd_read], [], [], 0.1)
            if r:
                chunk = os.read(fd_read, 4096)
                if not chunk:
                    break
                output += chunk
            else:
                break
    except:
        pass
    finally:
        os.close(fd_read)
    
    return output.decode('utf-8', errors='replace')

if __name__ == '__main__':
    pts_dev = sys.argv[1] if len(sys.argv) > 1 else '/dev/pts/1'
    command = sys.argv[2] if len(sys.argv) > 2 else 'show running-config'
    
    result = send_and_read(pts_dev, command)
    print(result)
