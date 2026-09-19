#!/usr/bin/env python3
"""Copy a small file to a shell on a serial console that has no network and no
base64/stty (busybox ash on the x86 OpenWrt). Sends it as `echo -ne '\\xHH..'`
chunks into per-chunk files, checks every chunk with md5sum, resends the bad
ones, then concatenates. About 1.5 KB/s at 38400 baud.

  sg dialout -c "python3 tools/console-put.py LOCAL /tmp/REMOTE [--dev DEV]"
"""
import argparse, glob, hashlib, os, re, select, sys, termios, time

p = argparse.ArgumentParser()
p.add_argument('local')
p.add_argument('remote')
p.add_argument('--dev', default='/dev/serial/by-id/usb-Prolific*-port0')
p.add_argument('--chunk', type=int, default=48)
a = p.parse_args()

dev = glob.glob(a.dev)[0]
fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
t = termios.tcgetattr(fd)
t[0] = t[1] = t[3] = 0
t[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
t[4] = t[5] = termios.B38400
termios.tcsetattr(fd, termios.TCSANOW, t)


def run(cmd, wait=8.0, quiet=0.35):
    """send one line, return the output once the prompt is back and the console has been quiet for `quiet` s"""
    os.write(fd, cmd.encode() + b'\r')
    buf, end, last = b'', time.time() + wait, time.time()
    while time.time() < end:
        if select.select([fd], [], [], 0.05)[0]:
            buf += os.read(fd, 4096)
            last = time.time()
        elif buf.rstrip().endswith(b'#') and time.time() - last > quiet:
            break
    return buf.decode(errors='replace')


data = open(a.local, 'rb').read()
chunks = [data[i:i + a.chunk] for i in range(0, len(data), a.chunk)]
d = '/tmp/put.d'
run('')
run('rm -rf %s; mkdir %s' % (d, d))


def send(i):
    esc = ''.join('\\x%02x' % b for b in chunks[i])
    run("echo -ne '%s' > %s/%05d" % (esc, d, i))


for i in range(len(chunks)):
    send(i)
    if i % 50 == 0:
        print('%d/%d' % (i, len(chunks)), flush=True)

for attempt in range(6):
    out = run('cd %s && md5sum *' % d, 30)
    have = dict(m.group(2, 1) for m in re.finditer(r'([0-9a-f]{32})  (\d{5})', out))
    bad = [i for i in range(len(chunks))
           if have.get('%05d' % i) != hashlib.md5(chunks[i]).hexdigest()]
    print('bad chunks:', len(bad), flush=True)
    if not bad:
        break
    for i in bad:
        send(i)
else:
    sys.exit('giving up')
run('cat %s/* > %s; rm -rf %s' % (d, a.remote, d))
out = run('md5sum ' + a.remote)
ok = hashlib.md5(data).hexdigest() in out
print('remote', a.remote, 'OK' if ok else 'MISMATCH: ' + out)
sys.exit(0 if ok else 1)
