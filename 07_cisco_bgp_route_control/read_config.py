import fcntl, termios, time, os

pts = "/dev/pts/1"

# Read current NVRAM config
try:
    with open("/iol/config.txt", "r") as f:
        content = f.read()
        print("=== NVRAM CONFIG (config.txt) ===")
        print(content)
        print("=== END NVRAM CONFIG ===")
except Exception as e:
    print(f"Cannot read NVRAM config: {e}")

# Also check startup-config
try:
    with open("/iol/startup-config", "r") as f:
        content = f.read()
        print("=== STARTUP CONFIG ===")
        print(content)
        print("=== END STARTUP CONFIG ===")
except Exception as e:
    print(f"Cannot read startup config: {e}")
