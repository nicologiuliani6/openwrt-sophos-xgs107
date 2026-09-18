#!/usr/bin/env python3
"""Send lines to a serial console and print what comes back.

Each argument is sent as one line (CR-terminated); after each, output is
read until the line goes quiet for --idle seconds. Raw bytes are appended to
logs/<name>-<date>.log so every session stays on record.

  sg dialout -c "python3 scripts/40-console-send.py 'lspci -nn' 'lsmod'"
  python3 scripts/40-console-send.py --idle 8 'dmesg'     # slow command
  python3 scripts/40-console-send.py ''                   # just press Enter
  sg dialout -c 'python3 scripts/40-console-send.py' < cmds.txt   # one per line
"""
import argparse, os, re, select, sys, termios, time

p = argparse.ArgumentParser()
p.add_argument('lines', nargs='*')
p.add_argument('--dev', default='/dev/ttyUSB0')
p.add_argument('--baud', type=int, default=38400)
p.add_argument('--idle', type=float, default=2.0)
p.add_argument('--name', default='x86-console')
a = p.parse_args()
if not a.lines and not sys.stdin.isatty():
    a.lines = sys.stdin.read().splitlines()

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
log = open(os.path.join(repo, 'logs', f'{a.name}-{time.strftime("%Y%m%d")}.log'), 'ab')

fd = os.open(a.dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
t = termios.tcgetattr(fd)
speed = getattr(termios, f'B{a.baud}')
t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
t[4] = t[5] = speed
termios.tcsetattr(fd, termios.TCSANOW, t)

def drain(idle):
    out, last = b'', time.time()
    while time.time() - last < idle:
        if select.select([fd], [], [], 0.1)[0]:
            try:
                chunk = os.read(fd, 4096)
            except BlockingIOError:
                continue
            out += chunk
            last = time.time()
    return out

drain(0.3)  # discard anything stale
for line in a.lines or ['']:
    os.write(fd, line.encode() + b'\r')
    out = drain(a.idle)
    log.write(out)
    log.flush()
    text = re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', out).replace(b'\r', b'')
    print(text.decode(errors='replace'), end='' if text.endswith(b'\n') else '\n')
os.close(fd)
