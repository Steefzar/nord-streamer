#!/system/bin/sh
echo "Content-Type: text/plain; charset=utf-8"
echo ""

case "$QUERY_STRING" in
  src=dmesg)
    dmesg | tail -n 120
    ;;
  src=accd)
    f=$(ls -t /data/adb/vr25/logs/*.log 2>/dev/null | head -1)
    if [ -n "$f" ]; then echo "== $f"; tail -n 120 "$f"; else echo "no ACC log found"; fi
    ;;
  *)
    logcat -d -t 150 2>&1
    ;;
esac
