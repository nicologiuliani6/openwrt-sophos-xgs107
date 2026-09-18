#!/bin/sh
# Live view of the NPU COM header (ARM switch-side console). Read-only:
# prints everything the board sends, non-printable bytes shown as ^@ / M-x,
# and saves the raw bytes to logs/.
# Usage: scripts/30-npu-console.sh [baud] [device]   (Ctrl-C to stop)
set -u

BAUD=${1:-115200}
DEV=${2:-/dev/ttyACM0}
REPO=$(cd "$(dirname "$0")/.." && pwd)
LOG="$REPO/logs/npu-com-$(date +%Y%m%d-%H%M%S)-$BAUD.log"

stty -F "$DEV" "$BAUD" cs8 -cstopb -parenb raw -echo clocal || exit 1
echo "listening on $DEV @ $BAUD -> $LOG  (Ctrl-C to stop)"
cat "$DEV" | tee "$LOG" | cat -v
