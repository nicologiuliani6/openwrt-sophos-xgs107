#!/usr/bin/env python3
"""Send lines to a serial console and print what comes back.

Each argument is sent as one line (CR-terminated); after each, output is
read until the line goes quiet for --idle seconds. Raw bytes are appended to
logs/<name>-<date>.log so every session stays on record.

  sg dialout -c "python3 tools/console-send.py 'lspci -nn' 'lsmod'"
  python3 tools/console-send.py --idle 8 'dmesg'     # slow command
  python3 tools/console-send.py --live --idle 300 --until 'DONE|ABORT' 'sh long-job.sh'
  python3 tools/console-send.py ''                   # just press Enter
  sg dialout -c 'python3 tools/console-send.py' < cmds.txt   # one per line
"""
import argparse, os, re, select, sys, termios, time

p = argparse.ArgumentParser()
p.add_argument('lines', nargs='*')
import glob
default_dev = os.environ.get('XGS_CONSOLE') or (glob.glob('/dev/serial/by-id/usb-Prolific*-port0') or ['/dev/ttyUSB0'])[0]
p.add_argument('--dev', default=default_dev,
               help='x86 console: $XGS_CONSOLE, else the PL2303 by-id node (survives ttyUSBn renumbering), else /dev/ttyUSB0')
p.add_argument('--baud', type=int, default=38400)
p.add_argument('--idle', type=float, default=2.0)
p.add_argument('--name', default='x86-console')
p.add_argument('--live', action='store_true', help='print the output as it arrives, not when the line is over')
p.add_argument('--until', help='regex: stop waiting for a line as soon as its output matches it')
a = p.parse_args()
until = re.compile(a.until.encode()) if a.until else None
if not a.lines and not sys.stdin.isatty():
    a.lines = sys.stdin.read().splitlines()

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.makedirs(os.path.join(repo, 'logs'), exist_ok=True)
log = open(os.path.join(repo, 'logs', f'{a.name}-{time.strftime("%Y%m%d")}.log'), 'ab')

try:
    fd = os.open(a.dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
except OSError as e:
    sys.exit(f'cannot open the console {a.dev}: {e.strerror}. Is the micro-USB cable plugged in, '
             f'and are you in the "dialout" group (sudo usermod -aG dialout $USER, then log in again)?')
t = termios.tcgetattr(fd)
speed = getattr(termios, f'B{a.baud}')
t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
t[4] = t[5] = speed
termios.tcsetattr(fd, termios.TCSANOW, t)

def clean(b):
    return re.sub(rb'\x1b\[[0-9;?]*[A-Za-z]', b'', b).replace(b'\r', b'')


def drain(idle, live=False):
    out, last = b'', time.time()
    while time.time() - last < idle:
        if select.select([fd], [], [], 0.1)[0]:
            try:
                chunk = os.read(fd, 4096)
            except BlockingIOError:
                continue
            out += chunk
            last = time.time()
            if live:
                sys.stdout.write(clean(chunk).decode(errors='replace'))
                sys.stdout.flush()
            if until and until.search(clean(out)):
                break
    return out

drain(0.3)  # discard anything stale
for line in a.lines or ['']:
    os.write(fd, line.encode() + b'\r')
    out = drain(a.idle, a.live)
    log.write(out)
    log.flush()
    if not a.live:
        text = clean(out)
        print(text.decode(errors='replace'), end='' if text.endswith(b'\n') else '\n')
    else:
        print()
os.close(fd)
