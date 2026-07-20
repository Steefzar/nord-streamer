#!/usr/bin/env bash
# Package the Magisk module into a flashable zip.
set -euo pipefail
cd "$(dirname "$0")"

rm -f spotify-streamer.zip

if command -v zip >/dev/null; then
  (cd spotify-streamer && zip -r ../spotify-streamer.zip . -x '.*')
else
  python3 - <<'EOF'
import os, zipfile
root = "spotify-streamer"
with zipfile.ZipFile("spotify-streamer.zip", "w", zipfile.ZIP_DEFLATED) as z:
    for dirpath, _, files in os.walk(root):
        for f in files:
            p = os.path.join(dirpath, f)
            z.write(p, os.path.relpath(p, root))
EOF
fi
echo "Built spotify-streamer.zip"
