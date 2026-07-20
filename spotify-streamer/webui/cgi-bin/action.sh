#!/system/bin/sh
echo "Content-Type: text/plain"
echo ""

case "$QUERY_STRING" in
  do=reboot)
    echo "Rebooting — back in ~1 min, Spotify auto-relaunches."
    ( sleep 2; svc power reboot ) &
    ;;
  do=poweroff)
    # A full power cycle rather than a reboot. Note it does NOT recover a DAC
    # that failed to enumerate -- measured, the Type-C attach still happens with
    # the charger connected, so it loses the same race a reboot does. Only a
    # physical charger replug fixes that.
    # Only safe on a headless unit because magisk-autoboot powers it back on
    # when the charger is connected; without that this is a one-way trip that
    # needs someone to press the button, so refuse rather than strand it.
    AB=/data/adb/modules/magisk-autoboot
    if [ ! -d "$AB" ] || [ -f "$AB/disable" ]; then
      echo "Refused: magisk-autoboot is not active, so the unit would not come back on its own."
    else
      echo "Powering off — magisk-autoboot should bring it back in about 90 s."
      ( sleep 2; svc power shutdown ) &
    fi
    ;;
  do=restart_spotify)
    am force-stop com.spotify.music
    ( sleep 3
      monkey -p com.spotify.music -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
      sleep 8
      input keyevent 223 ) &
    echo "Spotify restarting (screen will blip on briefly)."
    ;;
  do=playpause)
    input keyevent 85
    echo "Toggled play/pause."
    ;;
  do=screen_on)
    input keyevent 224
    # Derive the address from the request rather than hardcoding one, so this
    # tells you the right host whatever the streamer's IP happens to be.
    echo "Screen on. scrcpy: adb connect ${HTTP_HOST%%:*}:5555"
    ;;
  do=screen_off)
    input keyevent 223
    echo "Screen off."
    ;;
  *)
    echo "Unknown action: $QUERY_STRING"
    ;;
esac
