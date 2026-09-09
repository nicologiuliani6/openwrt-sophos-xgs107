#!/usr/bin/env bash
# Snapshot the appliance's PCI/hardware state. Read-only: loads nothing,
# changes nothing. Safe to run on a stock live USB before any driver work.
# Output lands in logs/hw-<timestamp>/.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT="$REPO/logs/hw-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

[ "$(id -u)" -eq 0 ] || echo "WARN: not root -- lspci -vvv output will be truncated" >&2

run() { echo "### $* ###"; "$@" 2>&1; echo; }

{
	run uname -a
	run lspci -nn
	run lspci -knn -d 11ab:
	run lspci -vvv -d 11ab:
} > "$OUT/pci.txt"

# BAR start/size per Marvell device. prestera_pci.c keys its BAR2-split
# decision off pci_resource_len(pdev, 2) == 0x1000000, so the sizes here
# decide which pp_bar2= value to try first.
{
	for d in $(lspci -D -n -d 11ab: | cut -d' ' -f1); do
		sys="/sys/bus/pci/devices/$d"
		echo "=== $d ==="
		for f in vendor device subsystem_vendor subsystem_device revision; do
			[ -r "$sys/$f" ] && echo "  $f = $(cat "$sys/$f")"
		done
		i=0
		while read -r start end _flags; do
			# bash arithmetic parses the 0x prefixes directly
			if [ $((end)) -gt $((start)) ]; then
				printf '  BAR%d start=%s size=0x%x\n' \
					"$i" "$start" $((end - start + 1))
			fi
			i=$((i + 1))
		done < "$sys/resource"
		echo
	done
} > "$OUT/bars.txt"

# Sanity check: Wi-Fi and USB should work regardless of the switch problem.
{
	run lsusb
	run rfkill list
	run ip -br link
	run lspci -knn -d ::0280
	run lspci -knn -d ::0200
} > "$OUT/other-hw.txt"

dmesg > "$OUT/dmesg.txt" 2>&1

echo "--- summary ---"
if lspci -n -d 11ab:7080 | grep -q .; then
	echo "FOUND 11ab:7080:"
	lspci -knn -d 11ab:7080
	grep -A8 "$(lspci -D -n -d 11ab:7080 | cut -d' ' -f1 | head -1)" "$OUT/bars.txt"
else
	echo "11ab:7080 NOT present. Marvell devices actually seen:"
	lspci -nn -d 11ab: | grep . || echo "  (none)"
	echo "If the ID differs, update PRESTERA_DEV_ID_XGS107W in"
	echo "driver/prestera-v6.14/prestera_pci.c and rebuild."
fi
echo
echo "Logs: $OUT"
