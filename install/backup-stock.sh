#!/bin/sh
# Back up everything the install touches, and the parts you would need to go
# back to stock, BEFORE installing. Streams to the PC, nothing is stored on the
# appliance.
#
# PC:   python3 tools/dump-receiver.py 8001         (writes into dumps/, never overwrites)
# x86 (SFOS advanced shell, stock NPU running):
#       curl -fsS http://<pc>:8000/backup-stock.sh -o /dev/shm/b.sh && PC=<pc> PORT=8001 sh /dev/shm/b.sh
#
# Every stream is hashed on the PC by the receiver; the NPU's own sha256 is
# printed next to it: compare them (docs/backup.md). The whole eMMC is 7.3 GB
# and takes about 25 minutes; SKIP_EMMC=1 leaves it out (then keep at least
# p3, the stock slot, and the SPI U-Boot).
set -eu

: "${PC:?set PC=<ip of the PC running tools/dump-receiver.py>}"
PORT=${PORT:-8001}
URL=http://$PC:$PORT
npu() { xgs-ssh.sh "$@"; }
put() { curl -fsS -T - "$URL/$1"; }		# stdin -> dumps/<name>

echo "== NPU: SPI U-Boot and its environment"
npu 'cat /dev/mtd0' | put npu/mtd0-uboot.bin
npu 'cat /dev/mtd1' | put npu/mtd1-uboot-env.bin
echo "== NPU: device tree in use, boot partitions"
npu 'cat /sys/firmware/fdt' | put npu/running.dtb
npu 'cat /dev/mmcblk0boot0' | put npu/mmcblk0boot0.bin
npu 'cat /dev/mmcblk0boot1' | put npu/mmcblk0boot1.bin
echo "== NPU: partition table and hashes computed on the NPU"
npu 'fdisk -l /dev/mmcblk0; fw_printenv' | put npu/partitions-and-env.txt
npu 'sha256sum /dev/mtd0 /dev/mtd1 /dev/mmcblk0boot0 /dev/mmcblk0boot1'

if [ -z "${SKIP_EMMC:-}" ]; then
	echo "== NPU: the whole eMMC (slow)"
	npu 'cat /dev/mmcblk0' | put npu/mmcblk0-full.img
	echo "NPU-side hash of the eMMC (compare with the receiver's line above):"
	npu 'sha256sum /dev/mmcblk0'
fi

echo "== x86: first MiB of the disk (MBR + gap) and the /boot partition"
dd if=/dev/sda bs=1M count=1 2>/dev/null | put x86/sda-first-1M.bin
dd if=/dev/boot bs=1M 2>/dev/null | put x86/boot-partition.img
echo "x86-side md5 (compare with sha256 of the same data if needed):"
dd if=/dev/sda bs=1M count=1 2>/dev/null | md5sum
echo "== done"
