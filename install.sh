#!/bin/sh
# One command to install OpenWrt on a stock Sophos XGS 107w (both modules).
#
#   ./install.sh                 build (or reuse dist/), serve it, show the two
#                                commands to paste into the SFOS advanced shell
#   ./install.sh --serial        the same, and type them into the shell for you
#                                over the x86 console (micro-USB, 38400 8N1)
#
# Options: --pc-ip <ip>   address the appliance can reach this PC at
#          --port <n>     HTTP port (default 8000)
#          --yes          do not ask about the missing backup
# Environment: XGS_CONSOLE=/dev/ttyUSB1   serial device for --serial
#              (default: the Prolific PL2303 in /dev/serial/by-id)
#
# Before: open the SFOS advanced shell on the x86 console (login admin,
# menu 5 Device Management, then 3 Advanced Shell). See docs/install.md.
set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
DIST=${DIST_DIR:-$REPO/dist}
PORT=8000
PC_IP=
SERIAL=
YES=
while [ $# -gt 0 ]; do
	case $1 in
	--serial) SERIAL=1 ;;
	--pc-ip) PC_IP=${2:?--pc-ip needs an address}; shift ;;
	--port) PORT=${2:?--port needs a number}; shift ;;
	--yes) YES=1 ;;
	-h|--help) sed -n '2,16p' "$0"; exit 0 ;;
	*) echo "unknown option $1 (try --help)" >&2; exit 2 ;;
	esac
	shift
done

say() { printf '\n== %s\n' "$*"; }
die() { echo "ABORT: $*" >&2; exit 1; }

for t in python3 curl sha256sum; do command -v $t >/dev/null || die "need $t"; done

say "1/4 installation files"
NEED="npu-p1.img.gz npu-p1.md5 npu-p1.sha256 x86-vmlinuz x86-rootfs.img.gz x86-env.sh install-x86.sh install-npu.sh x86-mbr.py uboot-env.txt"
complete=1
for f in $NEED; do [ -f "$DIST/$f" ] || complete=; done
if [ -n "$complete" ] && [ -f "$DIST/SHA256SUMS" ] && (cd "$DIST" && sha256sum -c --quiet SHA256SUMS 2>/dev/null); then
	echo "using $DIST (checksums OK)"
else
	echo "no complete dist/: building it (an hour or two the first time, see docs/build.md)"
	DIST_DIR=$DIST "$REPO/build/build.sh" all
	(cd "$DIST" && sha256sum -c --quiet SHA256SUMS) || die "dist/ does not verify"
fi

say "2/4 backup"
if [ ! -s "$REPO/dumps/npu/mtd0-uboot.bin" ] && [ -z "$YES" ]; then
	echo "No backup of the SPI U-Boot in dumps/ (docs/backup.md)."
	printf 'Continue without a backup? [y/N] '
	read -r a
	[ "$a" = y ] || [ "$a" = Y ] || die "make the backup first: docs/backup.md"
fi

say "3/4 address"
if [ -z "$PC_IP" ]; then
	PC_IP=$(ip -4 route get 192.168.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n1)
	[ -n "$PC_IP" ] || PC_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
[ -n "$PC_IP" ] || die "cannot tell this PC's address: pass --pc-ip"
echo "the appliance will fetch from http://$PC_IP:$PORT (change with --pc-ip)"

LOG=$(mktemp)
OUT=$(mktemp)
(cd "$DIST" && exec python3 -m http.server "$PORT" > "$LOG" 2>&1) &
SRV=$!
trap 'kill $SRV 2>/dev/null; rm -f "$LOG" "$OUT"' EXIT
trap 'exit 130' INT TERM
sleep 1
kill -0 $SRV 2>/dev/null || { cat "$LOG" >&2; die "cannot serve on port $PORT (in use?)"; }

X86="curl -fsS http://$PC_IP:$PORT/install-x86.sh -o /dev/shm/i.sh && PC=$PC_IP PORT=$PORT sh /dev/shm/i.sh"
NPU="curl -fsS http://$PC_IP:$PORT/install-npu.sh -o /dev/shm/n.sh && PC=$PC_IP PORT=$PORT sh /dev/shm/n.sh"

say "4/4 install (in this order)"
if [ -n "$SERIAL" ]; then
	for step in "$X86" "$NPU"; do
		echo ">> $step"
		printf '%s\n' "$step" |
			python3 "$REPO/tools/console-send.py" --name install --live --idle 600 --until '\[install(-npu)?\] (DONE|ABORT)' |
			tee "$OUT" || die "cannot drive the console (see above)"
		grep -Eq '\[install(-npu)?\] DONE' "$OUT" || die "the step did not report DONE: read the output above, fix, run ./install.sh --serial again"
	done
else
	cat <<EOT
Paste these two lines into the SFOS advanced shell, one after the other, and
wait for the [install] DONE and [install-npu] DONE lines:

  $X86

  $NPU

(waiting here, serving dist/ ... Ctrl-C when both have said DONE)
EOT
	while kill -0 $SRV 2>/dev/null; do sleep 5; done
	exit 0
fi

cat <<'EOT'

Both installers finished. Now POWER-CYCLE the appliance (unplug and re-plug
the power). Do not let SFOS reboot by itself before that.

After about a minute: plug a PC into panel port 1, open http://192.168.1.1
(router) and http://192.168.1.2 (x86, Wi-Fi). User root, no password: set one.
Details: docs/usage.md
EOT
