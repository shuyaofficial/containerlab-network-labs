import telnetlib
import sys
import time

try:
    tn = telnetlib.Telnet("172.20.20.2")
    tn.read_until(b"Password:", timeout=5)
    tn.write(b"admin\n")
    time.sleep(1)
    tn.write(b"show etherchannel summary\n")
    time.sleep(1)
    print(tn.read_very_eager().decode('ascii'))
except Exception as e:
    print(f"Error: {e}")
