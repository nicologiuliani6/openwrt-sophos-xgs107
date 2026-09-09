#!/usr/bin/env bash
# Decompress the Prestera firmware images out of the installed
# linux-firmware package into firmware-refs/, so 20-load-test.sh can
# install them on a machine whose /lib/firmware lacks them.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DST="$REPO/firmware-refs/mrvl/prestera"
SRC=/lib/firmware/mrvl/prestera

if ! compgen -G "$SRC/*.img*" >/dev/null; then
	echo "ERROR: no images in $SRC" >&2
	echo "       apt install firmware-marvell-prestera   (Debian/Ubuntu)" >&2
	echo "       dnf install mrvlprestera-firmware       (Fedora)" >&2
	exit 1
fi

mkdir -p "$DST"
for f in "$SRC"/*.img.zst; do
	[ -e "$f" ] || continue
	zstd -dqf "$f" -o "$DST/$(basename "$f" .zst)"
done
for f in "$SRC"/*.img; do
	[ -e "$f" ] || continue
	cp -n "$f" "$DST/"
done

# The driver rejects any image whose header magic is not 0x351D9D06.
for f in "$DST"/*.img; do
	magic=$(xxd -p -l4 "$f")
	printf '%-40s %s %s\n' "$(basename "$f")" "$magic" \
		"$([ "$magic" = 351d9d06 ] && echo OK || echo 'BAD MAGIC')"
done
