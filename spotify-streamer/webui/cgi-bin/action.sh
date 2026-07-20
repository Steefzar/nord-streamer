#!/system/bin/sh
echo "Content-Type: text/plain"
echo ""

case "$QUERY_STRING" in
  do=reboot)
    echo "Rebooting — back in ~1 min, Spotify auto-relaunches."
    ( sleep 2; svc power reboot ) &
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
    echo "Screen on. scrcpy: connect to 192.168.1.90:5555"
    ;;
  do=screen_off)
    input keyevent 223
    echo "Screen off."
    ;;
  *)
    echo "Unknown action: $QUERY_STRING"
    ;;
esac
