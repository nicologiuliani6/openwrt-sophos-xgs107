#!/usr/bin/env bash
# Load the patched driver and report how far the firmware handshake got.
# Run as root, after 10-build-module.sh. Re-runnable.
#
#   ./20-load-test.sh              # driver defaults (BAR4 for pp regs)
#   PP_BAR2=1 ./20-load-test.sh    # pp regs in second half of BAR2
#   FW_ARM64=1 ./20-load-test.sh   # request the arm64 firmware image
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$REPO/driver/prestera-v6.14"
PP_BAR2="${PP_BAR2:--1}"
FW_ARM64="${FW_ARM64:--1}"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root" >&2; exit 1; }
[ -f "$SRC/prestera_pci.ko" ] || { echo "ERROR: build first: scripts/10-build-module.sh" >&2; exit 1; }

if command -v mokutil >/dev/null && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
	echo "WARN: Secure Boot is on; insmod of an unsigned module will fail." >&2
	echo "      Disable it in BIOS or enroll a MOK key." >&2
fi

# The driver requests firmware from /lib/firmware; ship our staged copies.
if [ ! -e /lib/firmware/mrvl/prestera/mvsw_prestera_fw-v4.1.img ] &&
   [ ! -e /lib/firmware/mrvl/prestera/mvsw_prestera_fw-v4.1.img.zst ]; then
	# firmware-refs/ is gitignored (72M, re-stageable), so it may be absent
	# on a fresh clone. Restage it from the linux-firmware package:
	#   scripts/05-stage-firmware.sh
	if ! compgen -G "$REPO/firmware-refs/mrvl/prestera/*.img" >/dev/null; then
		echo "ERROR: no firmware in /lib/firmware and none staged in firmware-refs/." >&2
		echo "       Run: scripts/05-stage-firmware.sh  (needs linux-firmware installed)" >&2
		exit 1
	fi
	echo "Installing firmware into /lib/firmware/mrvl/prestera/"
	mkdir -p /lib/firmware/mrvl/prestera
	cp -n "$REPO"/firmware-refs/mrvl/prestera/*.img /lib/firmware/mrvl/prestera/
fi

# Drop any distro-provided prestera first, then load ours by explicit path.
rmmod prestera_pci 2>/dev/null
rmmod prestera 2>/dev/null

before=$(dmesg | wc -l)

insmod "$SRC/prestera.ko" || { echo "insmod prestera.ko failed" >&2; exit 1; }
if ! insmod "$SRC/prestera_pci.ko" pp_bar2="$PP_BAR2" fw_arm64="$FW_ARM64"; then
	echo "insmod prestera_pci.ko failed" >&2
	rmmod prestera 2>/dev/null
	exit 1
fi

# Firmware download has a 50s timeout in the driver; give it room.
echo "loaded with pp_bar2=$PP_BAR2 fw_arm64=$FW_ARM64, watching dmesg..."
for _ in $(seq 60); do
	sleep 1
	dmesg | tail -n +$((before + 1)) | grep -qE 'Prestera FW is ready|timed out|failed|invalid|bad CRC|no enough mem' && break
done

new=$(dmesg | tail -n +$((before + 1)))
printf '%s\n' "$new" > "$REPO/logs/load-$(date +%Y%m%d-%H%M%S)-bar2_${PP_BAR2}-arm64_${FW_ARM64}.txt"

echo "--- kernel output ---"
printf '%s\n' "$new"
echo "--- verdict ---"
case "$new" in
	*"Prestera FW is ready"*)
		echo "SUCCESS: firmware loaded and the FW ready magic (0xcafebabe) came back."
		echo "Check for new interfaces:  ip -br link" ;;
	*"waiting for FW loader is timed out"*)
		echo "Loader magic (0xf00dfeed) never appeared at the expected offset."
		echo "The driver bound but found no Prestera loader there."
		echo "Next: retry with the other BAR layout -- PP_BAR2=$([ "$PP_BAR2" = 1 ] && echo 0 || echo 1) $0" ;;
	*"FW failed to start"*|*"Timeout to load FW img"*|*"bad CRC"*)
		echo "Loader responded but the image did not start."
		echo "Protocol matches; wrong firmware flavour or version. Try FW_ARM64=1." ;;
	*"failed to request previous firmware"*)
		echo "Firmware file missing from /lib/firmware/mrvl/prestera/." ;;
	*prestera*)
		echo "Driver bound but produced an unexpected result -- read the output above." ;;
	*)
		echo "No prestera output at all. The device likely did not match the ID table."
		echo "Confirm the real ID with scripts/00-collect-hw.sh." ;;
esac
