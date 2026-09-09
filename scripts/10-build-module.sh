#!/usr/bin/env bash
# Build the patched prestera modules against the running kernel.
# Needs linux-headers-$(uname -r) installed on the machine doing the build.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$REPO/driver/prestera-v6.14"
KDIR="/lib/modules/$(uname -r)/build"

if [ ! -d "$KDIR" ]; then
	echo "ERROR: no kernel build dir at $KDIR" >&2
	echo "Install headers first:  apt install linux-headers-\$(uname -r)" >&2
	exit 1
fi

make -C "$KDIR" M="$SRC" modules

echo
echo "--- verifying the 0x7080 ID made it into the module ---"
if modinfo "$SRC/prestera_pci.ko" | grep -q 'v000011ABd00007080'; then
	echo "OK: prestera_pci.ko will bind pci:11ab:7080"
else
	echo "FAIL: 0x7080 alias missing from prestera_pci.ko" >&2
	exit 1
fi
modinfo "$SRC/prestera_pci.ko" | grep '^parm:'
