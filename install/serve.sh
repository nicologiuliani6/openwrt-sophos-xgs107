#!/bin/sh
# Serve dist/ to the appliance over HTTP (the x86 fetches the installers and
# images from here).   install/serve.sh [port]     default port 8000
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
PORT=${1:-8000}
[ -d "$REPO/dist" ] || { echo "no dist/: run build/build.sh first (or unpack a release there)" >&2; exit 1; }
echo "PC address(es): $(hostname -I 2>/dev/null)"
cd "$REPO/dist" && exec python3 -m http.server "$PORT"
