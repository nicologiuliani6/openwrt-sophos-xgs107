#!/usr/bin/env python3
"""Catch the x86's GRUB menu on the serial console and edit a boot entry.

The XGS x86 has no display, but GRUB (2.02, AMI UEFI) is redirected to the
micro-USB console at 38400 8N1. Start this BEFORE powering the box on:

  sg dialout -c 'python3 tools/x86-grub.py --append "rdinit=/bin/sh"'
  python3 tools/x86-grub.py --show          # only display the entry
  python3 tools/x86-grub.py --replay logs/x86-console-20260918-2114.log

It waits for the menu, presses `e` on the highlighted entry, finds the line
that starts with `linux`, appends the given text to it and boots with Ctrl-X.
With --show it leaves the editor with Esc instead and changes nothing.
A tiny terminal emulator rebuilds the screen from GRUB's ANSI output.
"""
import argparse, glob, os, re, select, sys, termios, time

ROWS, COLS = 30, 100
CSI = re.compile(r'\x1b\[([0-9;?]*)([A-Za-z])')


class Screen:
    def __init__(self):
        self.g = [[' '] * COLS for _ in range(ROWS)]
        self.r = self.c = 0
        self.carry = ''                  # an escape sequence cut by a read() boundary

    def feed(self, text):
        text = self.carry + text
        self.carry = ''
        m = re.search(r'\x1b(\[[0-9;?]*)?$', text)
        if m:
            self.carry, text = text[m.start():], text[:m.start()]
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


def port_holders(pattern):
    """PIDs (other than us) that have the serial device open."""
    m = sorted(glob.glob(pattern))
    if not m:
        return []
    node, out = os.path.realpath(m[0]), []
    for d in glob.glob('/proc/[0-9]*/fd/*'):
        pid = int(d.split('/')[2])
        if pid == os.getpid():
            continue
        try:
            if os.path.realpath(d) == node:
                out.append(pid)
        except OSError:
            pass
    return out


def replay(path):
    s = Screen()
    s.feed(open(path, 'rb').read().decode(errors='replace'))
    s.show()


class Port:
    """The USB-serial bridge vanishes while the XGS is unpowered and comes
    back on a new ttyUSBn: (re)open it whenever it is missing or fails."""

    def __init__(self, dev, baud):
        self.dev, self.baud, self.fd, self.node = dev, baud, None, None
        self.screen = Screen()
        self.raw = ''
        self.reopen()

    def path(self):
        m = sorted(glob.glob(self.dev))
        return m[0] if m else None

    def reopen(self):
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None
        try:
            path = self.path()                       # look it up once: it can vanish any time
            if path is None:
                return False
            fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
            node = os.path.realpath(path)
            t = termios.tcgetattr(fd)
            t[0] = t[1] = t[3] = 0
            t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
            t[4] = t[5] = getattr(termios, f'B{self.baud}')
            termios.tcsetattr(fd, termios.TCSANOW, t)
        except (OSError, termios.error):
            return False
        self.fd, self.node = fd, node
        print(f'  console open: {self.node}', flush=True)
        return True

    def pump(self, secs):
        end = time.time() + secs
        while time.time() < end:
            cur = self.path()
            if self.fd is None or cur is None or os.path.realpath(cur) != self.node:
                if not self.reopen():
                    time.sleep(0.5)
                    continue
            try:
                if select.select([self.fd], [], [], 0.05)[0]:
                    d = os.read(self.fd, 4096).decode(errors='replace')
                    self.raw += d
                    self.screen.feed(d)
            except BlockingIOError:
                continue
            except OSError:            # unplugged under us
                self.fd = None

    def send(self, s, gap=0.05):
        for ch in s:
            try:
                os.write(self.fd, ch.encode())
            except OSError:
                self.fd = None
                return
            time.sleep(gap)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dev', default='/dev/serial/by-id/usb-Prolific*-port0',
                    help='by-id path survives the ttyUSBn renumbering after a power cycle')
    ap.add_argument('--baud', type=int, default=38400)
    ap.add_argument('--append', default='')
    ap.add_argument('--show', action='store_true')
    ap.add_argument('--replay')
    ap.add_argument('--cmdline', metavar='EXTRA',
                    help="use GRUB's command line instead of the editor: types the stock linux line "
                         "(without 'quiet') plus EXTRA, verifies it on screen, then boot")
    ap.add_argument('--sysrq-reboot', action='store_true',
                    help='first send BREAK + "b" (SysRq reboot) to the running x86, then catch its GRUB')
    ap.add_argument('--at-menu', action='store_true',
                    help='GRUB is already showing its menu (countdown stopped): do not wait for it, '
                         'select the last entry and edit it. Waits until no other process (picocom) holds the port.')
    ap.add_argument('--wait', type=int, default=900, help='seconds to wait for GRUB')
    ap.add_argument('--log', default=f'logs/x86-grub-{time.strftime("%Y%m%d-%H%M%S")}.log')
    a = ap.parse_args()
    if a.replay:
        return replay(a.replay)
    if not a.append and not a.show and a.cmdline is None:
        ap.error('give --append TEXT, --cmdline EXTRA or --show')

    if a.at_menu:
        print('waiting for the console to be free (close picocom: Ctrl-A then Ctrl-X)...', flush=True)
        while port_holders(a.dev):
            time.sleep(0.5)
    p = Port(a.dev, a.baud)
    if a.at_menu:
        def last_entry_selected():
            return any(re.search(r'\*\s*19_5_4_718', l) for l in p.screen.lines())
        for attempt in range(4):
            p.send('\x1b'); p.pump(2.5)      # leave the editor if open; GRUB waits ~1s to tell Esc from a sequence
            for _ in range(4):                # Down: the last entry is 19_5_4_718 (SFOS 19.5.4)
                p.send('\x1b[B'); p.pump(0.7)
            if last_entry_selected():
                break
        if not last_entry_selected():
            p.screen.show()
            sys.exit('cannot select the 19_5_4_718 entry, not editing')
        p.raw += 'GNU GRUB'
    else:
        if a.sysrq_reboot:
            print('sending SysRq-b (BREAK then b) to the x86...', flush=True)
            termios.tcsendbreak(p.fd, 0); time.sleep(0.4); p.send('b')
            p.raw = ''
        print('waiting for the GRUB menu (power the XGS on now)...', flush=True)
        t0 = time.time()
        while 'GNU GRUB' not in p.raw:
            p.pump(0.5)
            if time.time() - t0 > a.wait:
                sys.exit('no GRUB menu seen')
    if a.cmdline is not None:
        base = ('linux /19_5_4_718 console=tty0 console=ttyS0,38400n8 pcie_aspm.policy=performance '
                'amd_iommu=on iommu=pt libata.force=noncq acpi_enforce_resources=lax '
                'crashkernel=3800M-6G:80M,6G-16G:128M,16G-:192M')
        line = (base + ' ' + a.cmdline).strip()
        def prompt_open():
            return any(l.lstrip().startswith('grub>') for l in p.screen.lines())
        def typed_ok():
            rows = [l for l in p.screen.lines() if l.strip()]
            i = next((n for n in range(len(rows) - 1, -1, -1) if rows[n].lstrip().startswith('grub>')), None)
            # GRUB echoes each character twice, which leaves an extra one at the edges of the
            # line: require the whole expected line inside, allowing only edge leftovers.
            return i is not None and line.replace(' ', '') in ''.join(rows[i:]).replace('grub>', '', 1).replace(' ', '')
        for _ in range(4):
            p.send('c')
            t1 = time.time()
            while time.time() - t1 < 9 and not prompt_open():
                p.pump(0.5)
            if prompt_open():
                break
        if not prompt_open():
            p.screen.show(); sys.exit('no grub> prompt')
        print('grub> prompt open; typing the linux line', flush=True)
        for ch in line:
            p.send(ch, gap=0); p.pump(0.06)
        p.pump(1.5)
        p.screen.show()
        if not typed_ok():
            open(a.log, 'w').write(p.raw)
            sys.exit('the typed line does not match, NOT pressing Enter (clear it with Ctrl-U)')
        p.send('\r'); p.pump(3)
        print('--- after linux'); p.screen.show()
        if any('error' in l.lower() for l in p.screen.lines()):
            open(a.log, 'w').write(p.raw)
            sys.exit('GRUB reported an error for the linux command, not booting')
        p.raw = ''
        for ch in 'boot':
            p.send(ch, gap=0); p.pump(0.1)
        p.send('\r'); p.pump(70)
        open(a.log, 'w').write(p.raw)
        tail = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', p.raw).replace('\r', '')
        print('--- console after boot (tail)'); print(tail[-3500:])
        return
    def editor_open():
        return any("setparams" in l for l in p.screen.lines())
    for _ in range(4):                        # a lost 'e' is retried, but only after a long wait:
        p.send('e')                           # a second 'e' inside an open editor would be typed into it
        t1 = time.time()
        while time.time() - t1 < 9 and not editor_open():
            p.pump(0.5)
        if editor_open():
            break
    p.pump(2)
    lines = p.screen.lines()
    li = next((n for n, l in enumerate(lines) if re.search(r'\blinux\b', l) and 'Minimal' not in l), None)
    print('--- GRUB edit screen'); p.screen.show()
    if li is None:
        open(a.log, 'w').write(p.raw)
        sys.exit('no linux line on the edit screen')
    # The editor starts on the first line. Wrapped lines end with a backslash before the
    # border, so count LOGICAL lines from the first box row down to the linux row.
    L = p.screen.lines()
    top = next(n for n, l in enumerate(L) if l.lstrip().startswith('/---'))
    def wraps(n):
        return L[n].rstrip().endswith('\\|')
    downs = sum(1 for n in range(top + 1, li + 1) if n == top + 1 or not wraps(n - 1)) - 1
    print(f'linux is logical line {downs} of the entry: pressing Down {downs} times')
    for _ in range(downs):
        p.send('\x1b[B'); p.pump(0.5)
    if a.show:
        p.send('\x1b'); p.pump(1)
        open(a.log, 'w').write(p.raw)
        print(f'(entry only shown; GRUB resumes the countdown; log {a.log})')
        return
    p.send('\x05'); p.pump(0.5)              # Ctrl-E: end of line
    for ch in ' ' + a.append:                 # GRUB drops characters typed faster than it redraws
        p.send(ch, gap=0); p.pump(0.35)
    p.pump(1)
    print('--- after edit'); p.screen.show()
    def content(row):                         # text inside the box, without the wrap marker
        r = p.screen.lines()[row]
        r = r[r.find('|') + 1:r.rfind('|')] if r.count('|') >= 2 else r
        return r[:-1] if r.endswith('\\') else r
    if not content(top + 1).startswith('setparams') or a.append not in ''.join(content(n) for n in range(li, li + 5)):
        open(a.log, 'w').write(p.raw)
        sys.exit('appended text not visible on the linux line, not booting')
    p.send('\x18')                            # Ctrl-X: boot
    p.pump(45)
    open(a.log, 'w').write(p.raw)
    tail = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', p.raw).replace('\r', '')
    print('--- console after boot (tail)'); print(tail[-1500:])


if __name__ == '__main__':
    main()
