#!/usr/bin/env bash
# Build and install the module on the rooted Nord over ADB (USB or Wi-Fi).
# Requires: adb connected, Magisk su granted to the shell user.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

echo "==> Waiting for device..."
adb wait-for-device

echo "==> Installing module via Magisk..."
adb push spotify-streamer.zip /data/local/tmp/spotify-streamer.zip
adb shell su -c "magisk --install-module /data/local/tmp/spotify-streamer.zip \
  && rm /data/local/tmp/spotify-streamer.zip"

echo "==> Installed. Reboot to activate:  adb reboot"
echo "    Afterwards:  adb connect <nord-ip>:5555   (then scrcpy for the screen)"
