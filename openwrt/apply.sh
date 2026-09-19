#!/bin/sh
# Apply the XGS 107w changes to an OpenWrt checkout.
#
#   openwrt/apply.sh <openwrt-tree> <npu|x86>
#
# 1. the patch series in openwrt/patches (edits to existing files), skipped
#    when already applied;
# 2. new files: the NPU device tree, base-files and kernel patches, the x86
#    kernel patches;
# 3. the x86 root filesystem overlay ("files/"), present only for the x86
#    build so it does not leak into the NPU image.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
TREE=${1:?usage: apply.sh <openwrt-tree> <npu|x86>}
TARGET=${2:?usage: apply.sh <openwrt-tree> <npu|x86>}
TREE=$(cd "$TREE" && pwd)

for p in "$HERE"/patches/*.patch; do
	if git -C "$TREE" apply --reverse --check "$p" >/dev/null 2>&1; then
		echo "already applied: $(basename "$p")"
	else
		git -C "$TREE" apply "$p"
		echo "applied: $(basename "$p")"
	fi
done

M=$TREE/target/linux/mvebu
mkdir -p "$M/files/arch/arm64/boot/dts/marvell" "$M/cortexa72/base-files" "$M/patches-6.18"
cp "$HERE"/npu/dts/*.dts "$M/files/arch/arm64/boot/dts/marvell/"
cp -r "$HERE"/npu/base-files/. "$M/cortexa72/base-files/"
cp "$HERE"/npu/kernel-patches/*.patch "$M/patches-6.18/"
cp "$HERE"/x86/kernel-patches/*.patch "$TREE/target/linux/x86/patches-6.18/"

rm -rf "$TREE/files"
if [ "$TARGET" = x86 ]; then
	cp -r "$HERE/x86/files" "$TREE/files"
fi
echo "tree ready for the $TARGET build"
