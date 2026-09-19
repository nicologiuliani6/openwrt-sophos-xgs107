#!/bin/sh
# Install OpenWrt on the NPU (CN9130) eMMC slot p1 and point the NPU's U-Boot
# at it, with the stock Sophos slot p3 as automatic fallback.
#
# Runs ON THE x86, in the SFOS advanced shell (busybox sh), while the stock NPU
# is running, fetching everything from the PC:
#
#   curl -fsS http://<pc>:8000/install-npu.sh -o /dev/shm/n.sh && PC=<pc> sh /dev/shm/n.sh
#
# Needs in the PC's dist/ (served over HTTP): npu-p1.img.gz, npu-p1.md5,
# npu-p1.sha256, uboot-env.txt.
#
# Written: eMMC mmcblk0p1 and four U-Boot environment variables (SPI mtd1).
# Never written: the SPI U-Boot (mtd0), the stock slots p2/p3.
# Nothing is rebooted: power-cycle the appliance afterwards (docs/install.md).
set -eu

PORT=${PORT:-8000}
say() { echo "[install-npu] $*"; }
die() { echo "[install-npu] ABORT: $*" >&2; exit 1; }
npu() { xgs-ssh.sh "$@"; }
: "${PC:?set PC=<ip of the PC that serves dist/>}"
URL=http://$PC:$PORT

cd /dev/shm
say "downloading"
curl -fsS "$URL/npu-p1.md5" -o p1.md5
curl -fsS "$URL/npu-p1.sha256" -o p1.sha256
curl -fsS "$URL/uboot-env.txt" -o env.txt
curl -fsS "$URL/npu-p1.img.gz" -o p1.img.gz
say "verifying the download (md5 of the decompressed image)"
[ "$(zcat p1.img.gz | md5sum | cut -d' ' -f1)" = "$(cat p1.md5)" ] || die "image md5 mismatch"

say "checking the NPU"
[ "$(npu 'uname -r' | cut -c1-4)" = 4.14 ] || die "the NPU is not running the stock Linux 4.14"
npu 'grep -q root=/dev/mmcblk0p3 /proc/cmdline' || die "the NPU did not boot from stock slot p3"
[ "$(npu 'mount | grep -c mmcblk0p1')" = 0 ] || die "mmcblk0p1 is mounted on the NPU"
npu 'which fw_setenv fw_printenv sha256sum >/dev/null' || die "fw_setenv / sha256sum missing on the NPU"

say "writing mmcblk0p1 (about a minute)"
zcat p1.img.gz | npu 'dd of=/dev/mmcblk0p1 bs=1M conv=fsync 2>/dev/null; sync'
say "verifying what the NPU wrote"
[ "$(npu 'sha256sum /dev/mmcblk0p1' | cut -d' ' -f1)" = "$(cat p1.sha256)" ] ||
	die "mmcblk0p1 differs from the image (the stock slots and U-Boot are untouched: safe to retry)"

say "U-Boot environment: OpenWrt first, stock as fallback"
npu 'cat > /tmp/owrt-env.txt; fw_setenv -s /tmp/owrt-env.txt' < env.txt
npu 'fw_printenv -n bootcmd' | grep -q 'run bootcmd_owrt; run bootcmd_stock' || die "bootcmd was not updated"

say "DONE. The NPU boots OpenWrt at the next power-up; if its kernel cannot be loaded U-Boot falls back to stock."
rm -f p1.img.gz
