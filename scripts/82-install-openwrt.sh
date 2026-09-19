#!/bin/sh
# Install OpenWrt on the XGS 107w NPU (eMMC slot p1) and switch U-Boot to it,
# with the stock Sophos slot p3 as automatic fallback.
#
# Preconditions: SFOS advanced shell open on the x86 console (/dev/ttyUSB0),
# NPU running stock, XGS Port2 on the same LAN as this PC (PC_IP below),
# ~/src/xgs-build/stage holds xgs107w-p1.img + 81-uboot-env-openwrt.txt.
# Procedure and undo: docs/openwrt-install.md.
set -eu
cd "$(dirname "$0")/.."

PC_IP=${PC_IP:-192.168.88.254}
STAGE=${STAGE:-$HOME/src/xgs-build/stage}
IMG_SHA=74f621117b25a24192baa011d074763715a8cc969510ef33fe43cbb3621fd6f6

send() {	# send one line to the SFOS shell, print the reply
	printf '%s\n' "$1" | sg dialout -c "python3 scripts/40-console-send.py --name sfos-install --idle ${2:-5}"
}
die() { echo "ABORT: $*" >&2; kill $SRV 2>/dev/null; exit 1; }

[ "$(sha256sum "$STAGE/xgs107w-p1.img" | cut -d' ' -f1)" = "$IMG_SHA" ] || die "slot image hash mismatch"

(cd "$STAGE" && exec python3 -m http.server 8001 >/dev/null 2>&1) &
SRV=$!
sleep 1

echo "== 1/5 checking NPU is stock and p1 is free"
out=$(send 'timeout 20 xgs-ssh.sh "uname -r; mount | grep -c mmcblk0p1"' 22)
echo "$out" | grep -q '^4\.14' || die "NPU is not on stock firmware"
echo "$out" | grep -qx '0' || die "p1 is mounted on the NPU"

echo "== 2/5 writing OpenWrt to mmcblk0p1 (about 1 minute)"
send "curl -sS http://$PC_IP:8001/xgs107w-p1.img | xgs-ssh.sh \"dd of=/dev/mmcblk0p1 bs=1M conv=fsync 2>/dev/null; sync\"; echo WRITE_DONE" 90 | grep -q WRITE_DONE || die "write did not finish"

echo "== 3/5 verifying on the NPU"
send 'timeout 60 xgs-ssh.sh "sha256sum /dev/mmcblk0p1"' 60 | grep -q "^$IMG_SHA" || die "p1 hash mismatch after write (stock boot is untouched)"
echo "   p1 verified: $IMG_SHA"

echo "== 4/5 U-Boot env (OpenWrt first, stock p3 as fallback)"
send "curl -sS http://$PC_IP:8001/81-uboot-env-openwrt.txt | xgs-ssh.sh \"cat > /tmp/env.txt; fw_setenv -s /tmp/env.txt; fw_printenv bootcmd bootcmd_owrt bootcmd_stock\"" 15
send 'timeout 20 xgs-ssh.sh "fw_printenv -n bootcmd"' 20 | grep -q 'run bootcmd_owrt; run bootcmd_stock' || die "env not applied"

echo "== 5/5 rebooting the NPU into OpenWrt (SFOS on the x86 will crash and reboot)"
# the stock NPU userland has no reboot binary: use SysRq
send 'xgs-ssh.sh "sync; echo s > /proc/sysrq-trigger; sleep 1; echo b > /proc/sysrq-trigger" </dev/null >/dev/null 2>&1 &' 3 >/dev/null
kill $SRV 2>/dev/null

# SFOS answers on this same MAC (and its own DHCP lease) until the NPU goes
# down, so first wait for that address to disappear.
old=$(ip neigh | awk 'tolower($5)=="c8:4f:86:c6:2c:63" && $1 !~ /:/ {print $1; exit}')
while [ -n "$old" ] && ping -c1 -W1 "$old" >/dev/null 2>&1; do sleep 3; done
ip neigh flush dev "$(ip route get "$PC_IP" 2>/dev/null | awk '{print $3; exit}')" >/dev/null 2>&1 || true
echo "   waiting for OpenWrt WAN (Port2, MAC c8:4f:86:c6:2c:63) on the LAN..."
for i in $(seq 1 60); do
	for h in $(seq 1 254); do ping -c1 -W1 "${PC_IP%.*}.$h" >/dev/null 2>&1 & done; wait
	ip=$(ip neigh | awk 'tolower($5)=="c8:4f:86:c6:2c:63" && $1 !~ /:/ {print $1; exit}')
	if [ -n "$ip" ] && ping -c1 -W1 "$ip" >/dev/null 2>&1; then
		echo "DONE: OpenWrt is up, WAN $ip. LAN/LuCI: plug a PC into port 1 -> http://192.168.1.1"
		exit 0
	fi
	sleep 10
done
echo "OpenWrt WAN not seen within ~15 min; check the NPU console (x86 /dev/ttyS2)."
exit 1
