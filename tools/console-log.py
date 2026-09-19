#!/usr/bin/env python3
"""Log the x86 console to a file, surviving the ttyUSBn renumbering of a power cycle.

  sg dialout -c 'python3 tools/console-log.py logs/x86-boot.log [max_seconds]'

Stops early once the SFOS login prompt ("Password:") has been seen.
"""
import importlib.util, os, sys, time

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('grub', os.path.join(here, '90-x86-grub.py'))
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)

out = sys.argv[1]
limit = float(sys.argv[2]) if len(sys.argv) > 2 else 1800
p = g.Port('/dev/serial/by-id/usb-Prolific*-port0', 38400)
t0, seen = time.time(), 0
with open(out, 'wb') as f:
    while time.time() - t0 < limit:
        p.pump(1.0)
        new = p.raw[seen:]
        if new:
            f.write(new.encode()); f.flush(); seen = len(p.raw)
        if 'Password:' in p.raw[-400:]:
            print(f'login prompt after {int(time.time() - t0)}s'); break
    else:
        print('no login prompt within the limit')
