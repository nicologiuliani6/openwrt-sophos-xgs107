#!/bin/sh
# Build the installable images.
#
#   build/build.sh [npu|x86|all]        (default: all)
#
# Environment (all optional):
#   OPENWRT_DIR   OpenWrt checkout            (default: build/openwrt)
#   OPENWRT_URL   where to clone it from      (default: github.com/openwrt/openwrt)
#   JOBS          make -j                     (default: number of CPUs)
#   DL_DIR        shared download cache
#   DIST_DIR      output directory            (default: dist)
#
# Output in $DIST_DIR: everything install/ needs, and SHA256SUMS.
# A cold build takes about an hour per target (the toolchain dominates).
set -eu

REPO=$(cd "$(dirname "$0")/.." && pwd)
# The OpenWrt commit the patches were made and tested against.
OPENWRT_COMMIT=b6ba4e9142b7e926dd3822beffdae26de34da98e

WHAT=${1:-all}
OPENWRT_DIR=${OPENWRT_DIR:-$REPO/build/openwrt}
OPENWRT_URL=${OPENWRT_URL:-https://github.com/openwrt/openwrt.git}
JOBS=${JOBS:-$(nproc)}
DIST_DIR=${DIST_DIR:-$REPO/dist}

case $WHAT in npu|x86|all) ;; *) echo "usage: $0 [npu|x86|all]" >&2; exit 2 ;; esac
[ "$(id -u)" -ne 0 ] || { echo "do not build as root (OpenWrt refuses to)" >&2; exit 1; }
command -v git >/dev/null && command -v make >/dev/null && command -v python3 >/dev/null ||
	{ echo "need git, make, gcc, python3 (see docs/build.md for the full list)" >&2; exit 1; }

if [ ! -d "$OPENWRT_DIR/.git" ]; then
	git clone "$OPENWRT_URL" "$OPENWRT_DIR"
fi
git -C "$OPENWRT_DIR" checkout -q "$OPENWRT_COMMIT" 2>/dev/null || {
	git -C "$OPENWRT_DIR" fetch -q origin
	git -C "$OPENWRT_DIR" checkout -q "$OPENWRT_COMMIT"
}
mkdir -p "$DIST_DIR"

build() {
	target=$1
	echo "==== $target ===="
	"$REPO/openwrt/apply.sh" "$OPENWRT_DIR" "$target"
	cd "$OPENWRT_DIR"
	if [ -n "${DL_DIR:-}" ] && { [ -L dl ] || [ ! -e dl ]; }; then ln -sfn "$DL_DIR" dl; fi
	cp "$REPO/build/feeds.conf" feeds.conf	# the feed commits the images were built with
	./scripts/feeds update -a >/dev/null
	./scripts/feeds install -a >/dev/null
	cp "$REPO/build/config/$target.config" .config
	make defconfig >/dev/null
	make -j"$JOBS"
	cd "$REPO"
}

collect_npu() {
	B=$OPENWRT_DIR/bin/targets/mvebu/cortexa72
	"$REPO/build/mk-emmc-slot.sh" "$OPENWRT_DIR" "$DIST_DIR/npu-p1.img"
	sha256sum "$DIST_DIR/npu-p1.img" | cut -d' ' -f1 > "$DIST_DIR/npu-p1.sha256"
	md5sum "$DIST_DIR/npu-p1.img" | cut -d' ' -f1 > "$DIST_DIR/npu-p1.md5"
	gzip -9f "$DIST_DIR/npu-p1.img"
	cp "$B"/*sophos_xgs107w-initramfs-kernel.bin "$DIST_DIR/npu-initramfs-kernel.bin"
}

collect_x86() {
	B=$OPENWRT_DIR/bin/targets/x86/64
	# The ext4 root comes from build_dir, not from bin/: the *-ext4-rootfs.img in bin/ is
	# padded with dd bs=<partition size>, which for more than 2 GiB doubles it and shifts
	# the data behind the first 2 GiB.
	R=$(ls -d "$OPENWRT_DIR"/build_dir/target-x86_64_*/linux-x86_64 | head -1)/root.ext4
	[ -f "$R" ] || { echo "missing $R" >&2; exit 1; }
	cp "$B/openwrt-x86-64-generic-kernel.bin" "$DIST_DIR/x86-vmlinuz"
	gzip -9c "$R" > "$DIST_DIR/x86-rootfs.img.gz"
	{
		echo "KMD5=$(md5sum "$DIST_DIR/x86-vmlinuz" | cut -d' ' -f1)"
		echo "RMD5=$(md5sum "$R" | cut -d' ' -f1)"
		echo "RHEAD_MD5=$(head -c 536870912 "$R" | md5sum | cut -d' ' -f1)"
		echo "RSIZE=$(stat -c %s "$R")"
	} > "$DIST_DIR/x86-env.sh"
}

case $WHAT in npu|all) build npu; collect_npu ;; esac
case $WHAT in x86|all) build x86; collect_x86 ;; esac

cp "$REPO"/install/install-npu.sh "$REPO"/install/install-x86.sh "$REPO"/install/x86-mbr.py \
	"$REPO"/install/backup-stock.sh \
	"$REPO"/install/uboot-env.txt "$DIST_DIR/"
(cd "$DIST_DIR" && find . -maxdepth 1 -type f ! -name 'SHA256SUMS*' -printf '%P\n' | sort | xargs sha256sum > SHA256SUMS.new && mv SHA256SUMS.new SHA256SUMS)
echo "done: $DIST_DIR"
ls -l "$DIST_DIR"
