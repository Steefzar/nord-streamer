#!/usr/bin/env bash
# Disable (default) or re-enable the packages in debloat.txt on the streamer.
# Usage: ./debloat.sh [disable|enable]
set -euo pipefail
cd "$(dirname "$0")"

DEV="${DEV:-192.168.1.90:5555}"
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
