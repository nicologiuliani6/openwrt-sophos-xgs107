#!/bin/sh
# Build an ext4 image for one NPU eMMC slot (p1: 500 MiB) from an OpenWrt
# build: the OpenWrt ext4 rootfs, grown to the slot size, with the kernel
# and DTB added under /boot so the stock U-Boot can ext4load them.
#
#   scripts/80-mk-emmc-slot.sh <openwrt-tree> <out.img>
#
# Only e2fsprogs is used (resize2fs, debugfs), so no root and no loop mounts.
set -eu

TREE=$1
OUT=$2
SLOT_BYTES=$((1024000 * 512))	# mmcblk0p1, from the stock MBR

KDIR=$(ls -d "$TREE"/build_dir/target-*/linux-mvebu_cortexa72 | head -1)
ROOTFS=$KDIR/root.ext4
KERNEL=$KDIR/sophos_xgs107w-kernel.bin
DTB=$KDIR/image-cn9130-sophos-xgs107w.dtb
for f in "$ROOTFS" "$KERNEL" "$DTB"; do
	[ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
done

case $ROOTFS in
*.gz) gzip -dc "$ROOTFS" > "$OUT" ;;
*) cp "$ROOTFS" "$OUT" ;;
esac

e2fsck -fy "$OUT" >/dev/null || true
truncate -s $SLOT_BYTES "$OUT"
resize2fs "$OUT" >/dev/null
# make_ext4fs images leave the resize inode size stale after growing
e2fsck -fy "$OUT" >/dev/null 2>&1 || true

debugfs -w "$OUT" >/dev/null <<EOF
mkdir /boot
write $KERNEL /boot/Image
write $DTB /boot/cn9130-sophos-xgs107w.dtb
EOF

e2fsck -fy "$OUT" >/dev/null 2>&1 || true
e2fsck -fn "$OUT" >/dev/null
debugfs -R "ls -l /boot" "$OUT" 2>/dev/null
sha256sum "$OUT"
