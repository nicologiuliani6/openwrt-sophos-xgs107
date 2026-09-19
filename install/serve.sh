#!/bin/sh
# Serve dist/ to the appliance over HTTP (the x86 fetches the installers and
# images from here).   install/serve.sh [port]     default port 8000
# Without a dist/ (nothing built yet) it serves install/, which is enough for
# the backup (backup-stock.sh), the first thing to do.
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
PORT=${1:-8000}
DIR=$REPO/dist
[ -f "$DIR/install-x86.sh" ] || { DIR=$REPO/install; echo "no dist/ yet: serving install/ (enough for the backup, not for the install)"; }
echo "PC address(es): $(hostname -I 2>/dev/null)"
echo "serving $DIR on port $PORT (Ctrl-C to stop)"
cd "$DIR" && exec python3 -m http.server "$PORT"
