#!/system/bin/sh
echo "Content-Type: text/plain"
echo ""

get() { echo "$QUERY_STRING" | sed -n "s/.*$1=\([^&]*\).*/\1/p"; }

act=$(get act)
case "$act" in
  tap)
    x=$(get x); y=$(get y)
    case "$x$y" in *[!0-9]*|"") echo "bad coords"; exit 0;; esac
    input tap "$x" "$y"
    echo "tap $x $y"
    ;;
  key)
    code=$(get code)
    case "$code" in *[!0-9]*|"") echo "bad keycode"; exit 0;; esac
    input keyevent "$code"
    echo "key $code"
    ;;
  swipe)
    x1=$(get x1); y1=$(get y1); x2=$(get x2); y2=$(get y2); dur=$(get dur)
    case "$x1$y1$x2$y2$dur" in *[!0-9]*|"") echo "bad swipe args"; exit 0;; esac
    [ "$dur" -lt 80 ] && dur=80
    [ "$dur" -gt 2000 ] && dur=2000
    input swipe "$x1" "$y1" "$x2" "$y2" "$dur"
    echo "swipe $x1,$y1 -> $x2,$y2 (${dur}ms)"
    ;;
  swipe_up)
    input swipe 540 1600 540 700 250
    echo "swipe up"
    ;;
  swipe_down)
    input swipe 540 700 540 1600 250
    echo "swipe down"
    ;;
  *)
    echo "unknown action"
    ;;
esac
