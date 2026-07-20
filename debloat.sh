#!/usr/bin/env bash
# Disable (default) or re-enable the packages in debloat.txt on the streamer.
# Usage: ./debloat.sh [disable|enable]
set -euo pipefail
cd "$(dirname "$0")"

# Target device. Defaults to the only attached device; set DEV to an
# ip:port when the streamer is reachable over Wi-Fi, e.g.
#   DEV=192.168.1.50:5555 ./debloat.sh disable
DEV="${DEV:-}"
if [ -z "$DEV" ]; then
  DEV=$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | head -1)
  [ -n "$DEV" ] || { echo "no adb device found; set DEV=<ip:port>" >&2; exit 1; }
fi

MODE="${1:-disable}"
case "$MODE" in
  disable) CMD="pm disable-user --user 0" ;;
  enable)  CMD="pm enable --user 0" ;;
  *) echo "usage: $0 [disable|enable]" >&2; exit 1 ;;
esac

grep -v '^#' debloat.txt | while read -r pkg; do
  [ -z "$pkg" ] && continue
  printf '%-45s ' "$pkg"
  adb -s "$DEV" shell "$CMD $pkg" </dev/null | tr -d '\r'
done
