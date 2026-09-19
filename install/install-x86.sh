#!/bin/sh
# Install OpenWrt on the XGS 107w x86 as a second boot entry next to SFOS.
#
# Runs ON THE x86, in the SFOS advanced shell (busybox sh), with the stock
# NPU running (it is the x86's only network), fetching from the PC:
#
#   curl -fsS http://<pc>:8000/install-x86.sh -o /dev/shm/i.sh && PC=<pc> sh /dev/shm/i.sh
#
# Needs in the PC's dist/ (served over HTTP): x86-vmlinuz, x86-rootfs.img.gz,
# x86-env.sh (KMD5, RMD5, RHEAD_MD5, RSIZE), x86-mbr.py.
#
# What it does (nothing is written before every download is verified):
#   1. sda8 = SFOS's swap partition (3.8 GB): swapoff, write the OpenWrt ext4
#      root there;
#   2. a real MBR entry #3 for that area (x86-mbr.py), because SFOS creates
#      sda3..sda9 at run time and a stock kernel only sees the two MBR
#      partitions. Sector 0 is backed up to /boot/mbr-sda.bak;
#   3. kernel -> /boot/openwrt/vmlinuz (the SFOS boot partition);
#   4. /boot/grub/grub.cfg: back it up, add an "OpenWrt" entry
#      (root=/dev/sda3) and make it the default.
# It does NOT reboot. SFOS must NOT be booted again afterwards: it runs mkswap
# on sda8 at every boot and would destroy the OpenWrt root.
set -eu

say() { echo "[install] $*"; }
die() { echo "[install] ABORT: $*" >&2; exit 1; }

cd /dev/shm
: "${PC:?set PC=<ip of the PC that serves dist/>}"
PORT=${PORT:-8000}
URL=http://$PC:$PORT
curl -fsS "$URL/x86-env.sh" -o env.sh
. ./env.sh
: "${KMD5:?}" "${RMD5:?}" "${RHEAD_MD5:?}" "${RSIZE:?}"

say "downloading"
curl -fsS "$URL/x86-vmlinuz" -o vmlinuz
curl -fsS "$URL/x86-rootfs.img.gz" -o rootfs.img.gz

say "verifying downloads in RAM"
[ "$(md5sum vmlinuz | cut -d' ' -f1)" = "$KMD5" ] || die "kernel md5 mismatch"
[ "$(zcat rootfs.img.gz | md5sum | cut -d' ' -f1)" = "$RMD5" ] || die "rootfs md5 mismatch"

say "sanity checks on the target"
# SFOS names its partition nodes /dev/boot, /dev/swap, /dev/var: there is NO /dev/sda8. Writing to a
# missing node with dd silently creates a regular file in RAM (this happened once), so check hard.
[ -b /dev/swap ] || die "/dev/swap is not a block device"
[ -b /dev/sda ] || die "/dev/sda is not a block device"
[ -f /dev/sda8 ] && rm -f /dev/sda8
grep -q ' sda8$' /proc/partitions || die "no sda8"
[ $(( $(awk '$4=="sda8"{print $3}' /proc/partitions) * 1024 )) -ge "$RSIZE" ] || die "sda8 is smaller than the image ($RSIZE bytes)"
ls -l /dev/swap | grep -q ' 8, *8 ' || die "/dev/swap is not sda8 (8,8)"
# sda8 may already be swapped off (an aborted earlier run); what matters is nothing else uses it
[ "$(grep -c . /proc/swaps)" -le 1 ] || grep -q 'swap\|sda8' /proc/swaps || die "another swap device is active"
! grep -q '^/dev/sda8 ' /proc/mounts || die "sda8 is mounted"
grep -q ' /boot ' /proc/mounts || die "/boot is not mounted"
[ "$(df -k /boot | awk 'NR==2{print $4}')" -gt 20000 ] || die "less than 20 MB free in /boot"
[ -f /boot/grub/grub.cfg ] || die "no grub.cfg"

used=$(awk 'NR>1{u+=$4} END{print u+0}' /proc/swaps)
avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
say "swap in use: ${used} kB, RAM available: ${avail} kB"
[ $((used * 2)) -lt "$avail" ] || die "swap holds too much for the free RAM: swapoff would OOM"

say "writing the OpenWrt rootfs to sda8 (SFOS swap)"
if grep -q 'swap\|sda8' /proc/swaps; then swapoff /dev/swap; fi
! grep -q 'swap\|sda8' /proc/swaps || die "sda8 still swapping"
zcat rootfs.img.gz | dd of=/dev/swap bs=1M conv=fsync 2>&1 | tail -1
sync; echo 3 > /proc/sys/vm/drop_caches
# verify from the WHOLE DISK node at the partition's start LBA, not through the node we wrote to
S8=$(cat /sys/block/sda/sda8/start)
[ $((S8 % 8)) -eq 0 ] || die "sda8 start not 4K aligned"
[ "$(dd if=/dev/sda bs=4096 skip=$((S8 / 8)) count=131072 2>/dev/null | md5sum | cut -d' ' -f1)" = "$RHEAD_MD5" ] || die "raw disk read-back mismatch"
say "sda8 (SFOS /dev/swap) verified on the raw disk at LBA $S8"

say "MBR entry #3 for sda8 (backup of sector 0 in /boot/mbr-sda.bak)"
curl -fsS "$URL/x86-mbr.py" -o mbr.py
python3 mbr.py "$(cat /sys/block/sda/sda8/start)" "$(cat /sys/block/sda/sda8/size)"

say "kernel to /boot/openwrt"
mkdir -p /boot/openwrt
cp vmlinuz /boot/openwrt/vmlinuz
sync
[ "$(md5sum /boot/openwrt/vmlinuz | cut -d' ' -f1)" = "$KMD5" ] || die "kernel copy mismatch"

say "grub.cfg"
[ -f /boot/grub/grub.cfg.sfos ] || cp /boot/grub/grub.cfg /boot/grub/grub.cfg.sfos
if ! grep -q 'menuentry "OpenWrt"' /boot/grub/grub.cfg; then
	cat >> /boot/grub/grub.cfg <<'EOF'
menuentry "OpenWrt" {
linux /openwrt/vmlinuz root=/dev/sda3 rootwait rootfstype=ext4 console=tty0 console=ttyS0,38400n8 noinitrd libata.force=noncq pcie_aspm.policy=performance acpi_enforce_resources=lax
}
EOF
fi
sed -i 's#root=/dev/sda8#root=/dev/sda3#; s/^set default=.*/set default=3/' /boot/grub/grub.cfg
sync
say "grub.cfg now:"
cat /boot/grub/grub.cfg

say "DONE: OpenWrt is GRUB entry 3 (default). SFOS entries 0-2 untouched. Not rebooted: now run install-npu.sh, then power-cycle."
