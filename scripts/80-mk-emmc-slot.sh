#!/bin/sh
# Build an ext4 image for one NPU eMMC slot (p1: 500 MiB) from an OpenWrt
# build: the OpenWrt ext4 rootfs, grown to the slot size, with the kernel
# and DTB added under /boot so the stock U-Boot can ext4load them.
#
#   scripts/80-mk-emmc-slot.sh <openwrt-bin-dir> <out.img>
#
# Only e2fsprogs is used (resize2fs, debugfs), so no root and no loop mounts.
set -eu

BIN=$1
OUT=$2
SLOT_BYTES=$((1024000 * 512))	# mmcblk0p1, from the stock MBR

ROOTFS=$(ls "$BIN"/*sophos_xgs107w*-ext4-rootfs.img* 2>/dev/null | head -1)
KERNEL=$(ls "$BIN"/*sophos_xgs107w*-kernel.bin 2>/dev/null | head -1)
DTB=$(ls "$BIN"/../../../../build_dir/target-*/linux-mvebu_cortexa72/image-cn9130-sophos-xgs107w.dtb 2>/dev/null | head -1)
[ -n "$ROOTFS" ] && [ -n "$KERNEL" ] && [ -n "$DTB" ] || {
	echo "missing rootfs/kernel/dtb in $BIN" >&2; exit 1; }

case $ROOTFS in
*.gz) gzip -dc "$ROOTFS" > "$OUT" ;;
*) cp "$ROOTFS" "$OUT" ;;
esac

e2fsck -fy "$OUT" >/dev/null || true
truncate -s $SLOT_BYTES "$OUT"
resize2fs "$OUT" >/dev/null

debugfs -w "$OUT" >/dev/null <<EOF
mkdir /boot
write $KERNEL /boot/Image
write $DTB /boot/cn9130-sophos-xgs107w.dtb
EOF

e2fsck -fn "$OUT" >/dev/null
debugfs -R "ls -l /boot" "$OUT" 2>/dev/null
sha256sum "$OUT"
