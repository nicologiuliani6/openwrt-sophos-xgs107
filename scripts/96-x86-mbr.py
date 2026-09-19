#!/usr/bin/env python3
"""Make the OpenWrt root partition visible to a normal Linux kernel on the XGS x86.

SFOS creates most of its partitions (sda3..sda9) at runtime; the disk's MBR only
lists the /boot and 64 MB partitions, so a stock kernel sees just sda1 and sda2.
This adds a real MBR entry #3 for SFOS's old swap area (sda8, where the OpenWrt
root filesystem was written), backing up sector 0 first, and points the GRUB
entry at it. Runs ON the x86 (SFOS advanced shell, python 3.8):

  python3 96-x86-mbr.py <sda8 start> <sda8 size>     # values from /sys/block/sda/sda8/{start,size}

Every precondition is checked before anything is written.
"""
import os, struct, sys

DEV = '/dev/sda'
start, size = int(sys.argv[1]), int(sys.argv[2])


def die(msg):
    sys.exit('ABORT: ' + msg)


def sysfs(n, what):
    return int(open('/sys/block/sda/sda%d/%s' % (n, what)).read())


with open(DEV, 'rb') as f:
    mbr = f.read(512)
if mbr[510:512] != b'\x55\xaa':
    die('no MBR signature')

ents = [struct.unpack('<B3sB3sII', mbr[446 + 16 * i:462 + 16 * i]) for i in range(4)]
for i, e in enumerate(ents, 1):
    print('MBR entry %d: type=0x%02x start=%d sectors=%d' % (i, e[2], e[4], e[5]))

if (ents[0][4], ents[0][5]) != (sysfs(6, 'start'), sysfs(6, 'size')):
    die('MBR entry 1 does not match sda6 (the boot partition)')
if (ents[1][4], ents[1][5]) != (sysfs(7, 'start'), sysfs(7, 'size')):
    die('MBR entry 2 does not match sda7')
if any(mbr[446 + 32:446 + 64]):
    die('MBR entries 3 and 4 are not empty')
if (sysfs(8, 'start'), sysfs(8, 'size')) != (start, size):
    die('sda8 start/size in sysfs differ from the arguments')
if ents[1][4] + ents[1][5] != start:
    print('note: sda8 does not directly follow MBR entry 2')

with open(DEV, 'rb') as f:               # the OpenWrt ext4 must be really there
    f.seek(start * 512 + 1080)
    if f.read(2) != b'\x53\xef':
        die('no ext4 superblock at the start of sda8')
    f.seek(start * 512 + 1024 + 0x78)
    print('ext4 volume label at sda8:', f.read(16).split(b'\0')[0].decode(errors='replace'))

bak = '/boot/mbr-sda.bak'
if not os.path.exists(bak):
    with open(bak, 'wb') as f:
        f.write(mbr)
        f.flush()
        os.fsync(f.fileno())
print('sector 0 backed up to', bak, '=', mbr.hex()[892:1024], '(entries+signature, hex)')

entry = struct.pack('<B3sB3sII', 0x00, b'\xfe\xff\xff', 0x83, b'\xfe\xff\xff', start, size)
new = mbr[:446 + 32] + entry + mbr[446 + 48:]
assert len(new) == 512 and new[510:512] == b'\x55\xaa'
fd = os.open(DEV, os.O_WRONLY | os.O_SYNC)
os.write(fd, new)
os.fsync(fd)
os.close(fd)
with open(DEV, 'rb') as f:
    back = f.read(512)
if back != new:
    die('read-back of sector 0 differs (restore with: dd if=%s of=%s bs=512 count=1)' % (bak, DEV))
print('MBR entry 3 written: type=0x83 start=%d sectors=%d, verified' % (start, size))
