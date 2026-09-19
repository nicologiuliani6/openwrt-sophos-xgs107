#!/usr/bin/env python3
"""Catch the x86's GRUB menu on the serial console and edit a boot entry.

The XGS x86 has no display, but GRUB (2.02, AMI UEFI) is redirected to the
micro-USB console at 38400 8N1. Start this BEFORE powering the box on:

  sg dialout -c 'python3 scripts/90-x86-grub.py --append "rdinit=/bin/sh"'
  python3 scripts/90-x86-grub.py --show          # only display the entry
  python3 scripts/90-x86-grub.py --replay logs/x86-console-20260918-2114.log

It waits for the menu, presses `e` on the highlighted entry, finds the line
that starts with `linux`, appends the given text to it and boots with Ctrl-X.
With --show it leaves the editor with Esc instead and changes nothing.
A tiny terminal emulator rebuilds the screen from GRUB's ANSI output.
"""
import argparse, os, re, select, sys, termios, time

ROWS, COLS = 30, 100
CSI = re.compile(r'\x1b\[([0-9;?]*)([A-Za-z])')


class Screen:
    def __init__(self):
        self.g = [[' '] * COLS for _ in range(ROWS)]
        self.r = self.c = 0

    def feed(self, text):
        i = 0
        while i < len(text):
            m = CSI.match(text, i)
            if m:
                a = [int(x) if x.isdigit() else 0 for x in m.group(1).replace('?', '').split(';')] or [0]
                k = m.group(2)
                if k in 'Hf':
                    self.r = max(0, min(ROWS - 1, (a[0] or 1) - 1))
                    self.c = max(0, min(COLS - 1, ((a[1] if len(a) > 1 else 1) or 1) - 1))
                elif k == 'J':
                    self.g = [[' '] * COLS for _ in range(ROWS)]
                elif k == 'K':
                    for x in range(self.c, COLS):
                        self.g[self.r][x] = ' '
                i = m.end()
                continue
            ch = text[i]
            i += 1
            if ch == '\r':
                self.c = 0
            elif ch == '\n':
                self.r = min(ROWS - 1, self.r + 1)
            elif ch >= ' ' and ch != '\x1b':
                if self.c < COLS:
                    self.g[self.r][self.c] = ch
                    self.c += 1

    def lines(self):
        return [''.join(row).rstrip() for row in self.g]

    def show(self):
        for n, l in enumerate(self.lines()):
            if l.strip():
                print(f'{n:2d}| {l}')


def replay(path):
    s = Screen()
    s.feed(open(path, 'rb').read().decode(errors='replace'))
    s.show()


class Port:
    def __init__(self, dev, baud):
        self.fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        t = termios.tcgetattr(self.fd)
        t[0] = t[1] = t[3] = 0
        t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        t[4] = t[5] = getattr(termios, f'B{baud}')
        termios.tcsetattr(self.fd, termios.TCSANOW, t)
        self.screen = Screen()
        self.raw = ''

    def pump(self, secs):
        end = time.time() + secs
        while time.time() < end:
            if select.select([self.fd], [], [], 0.05)[0]:
                try:
                    d = os.read(self.fd, 4096).decode(errors='replace')
                except BlockingIOError:
                    continue
                self.raw += d
                self.screen.feed(d)

    def send(self, s, gap=0.05):
        for ch in s:
            os.write(self.fd, ch.encode())
            time.sleep(gap)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dev', default='/dev/ttyUSB0')
    ap.add_argument('--baud', type=int, default=38400)
    ap.add_argument('--append', default='')
    ap.add_argument('--show', action='store_true')
    ap.add_argument('--replay')
    ap.add_argument('--wait', type=int, default=900, help='seconds to wait for GRUB')
    ap.add_argument('--log', default=f'logs/x86-grub-{time.strftime("%Y%m%d-%H%M%S")}.log')
    a = ap.parse_args()
    if a.replay:
        return replay(a.replay)
    if not a.append and not a.show:
        ap.error('give --append TEXT or --show')

    p = Port(a.dev, a.baud)
    print('waiting for the GRUB menu (power the XGS on now)...', flush=True)
    t0 = time.time()
    while 'GNU GRUB' not in p.raw:
        p.pump(0.5)
        if time.time() - t0 > a.wait:
            sys.exit('no GRUB menu seen')
    p.send('e')
    p.pump(2)
    lines = p.screen.lines()
    li = next((n for n, l in enumerate(lines) if re.search(r'\blinux\b', l) and 'Minimal' not in l), None)
    print('--- GRUB edit screen'); p.screen.show()
    if li is None:
        open(a.log, 'w').write(p.raw)
        sys.exit('no linux line on the edit screen')
    for _ in range(40):                      # walk the cursor down to it
        if p.screen.r >= li:
            break
        p.send('\x1b[B'); p.pump(0.3)
    if a.show:
        p.send('\x1b'); p.pump(1)
        open(a.log, 'w').write(p.raw)
        print(f'(entry only shown; GRUB resumes the countdown; log {a.log})')
        return
    p.send('\x05'); p.pump(0.3)              # Ctrl-E: end of line
    p.send(' ' + a.append); p.pump(1)
    print('--- after edit'); p.screen.show()
    if a.append not in ''.join(p.screen.lines()[li:li + 3]):
        open(a.log, 'w').write(p.raw)
        sys.exit('appended text not visible on the linux line, not booting')
    p.send('\x18')                            # Ctrl-X: boot
    p.pump(45)
    open(a.log, 'w').write(p.raw)
    tail = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', p.raw).replace('\r', '')
    print('--- console after boot (tail)'); print(tail[-1500:])


if __name__ == '__main__':
    main()
