#!/usr/bin/env python3
"""Run shell commands on the NPU's busybox telnetd (bring-up initramfs).

  python3 scripts/70-npu-telnet.py <ip> 'cmd1' 'cmd2' ...   (or stdin lines)
Each command's output is printed. Telnet option negotiation is refused.
"""
import socket, sys, time, re

host = sys.argv[1]
cmds = sys.argv[2:] or sys.stdin.read().splitlines()
s = socket.create_connection((host, 23), timeout=10)

def read(idle=1.5, total=120):
    buf, last, start = b'', time.time(), time.time()
    s.settimeout(0.2)
    while time.time() - last < idle and time.time() - start < total:
        try:
            d = s.recv(65536)
        except socket.timeout:
            continue
        if not d:
            break
        # refuse all telnet options: DO->WONT, WILL->DONT
        out = bytearray(); i = 0
        while i < len(d):
            if d[i] == 255 and i + 2 < len(d) and d[i+1] in (251, 252, 253, 254):
                s.send(bytes([255, 252 if d[i+1] == 253 else 254, d[i+2]])); i += 3
            else:
                out.append(d[i]); i += 1
        buf += bytes(out); last = time.time()
    return buf.decode(errors='replace')

read()
for c in cmds:
    s.send(c.encode() + b'\n')
    print(re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', read()).replace('\r', ''), end='')
print()
