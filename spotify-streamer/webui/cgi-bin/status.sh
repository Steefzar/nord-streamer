#!/system/bin/sh
echo "Content-Type: application/json"
echo ""

batt=$(dumpsys battery)
level=$(echo "$batt" | awk '/^  level:/{print $2; exit}')
bstat=$(echo "$batt" | awk '/^  status:/{print $2; exit}')
btemp=$(echo "$batt" | awk '/temperature:/{print $2; exit}')
sppid=$(pidof com.spotify.music)
play=$(dumpsys media_session 2>/dev/null | grep -m1 -oE "state=(PLAYING|PAUSED|STOPPED)" | cut -d= -f2)
uptime=$(cut -d. -f1 /proc/uptime)

# Charge hold: the status enum always says "Charging", so read the switch
hold=0
for d in /sys/class/thermal/cooling_device*; do
  if [ "$(cat "$d/type" 2>/dev/null)" = "battery" ]; then
    [ "$(cat "$d/cur_state" 2>/dev/null)" -ge 1 ] 2>/dev/null && hold=1
    break
  fi
done

# Is the DAC actually enumerated? After a reboot the port sometimes comes up as
# UFP and the DAC is absent until the charger is unplugged and replugged once.
dac_present=0
grep -q "USB-Audio" /proc/asound/cards 2>/dev/null && dac_present=1

# DAC stream: report rate/format of whichever playback PCM is open, but only
# when the DAC is really there -- card indices are not stable and on this
# platform the ADSP drives the USB endpoint, so the live stream shows up on the
# platform card's PCM. Without the guard the built-in speaker's stream would be
# reported as the DAC, which is exactly the case worth spotting.
dac=""
if [ "$dac_present" = 1 ]; then
  for f in /proc/asound/card*/pcm*p/sub*/hw_params; do
    hw=$(cat "$f" 2>/dev/null)
    [ -n "$hw" ] && [ "$hw" != "closed" ] || continue
    rate=$(echo "$hw" | awk '/^rate:/{print $2}')
    fmt=$(echo "$hw" | awk '/^format:/{print $2}')
    dac="$fmt @ ${rate}Hz"
    break
  done
fi

printf '{"batt_level":%s,"batt_status":%s,"batt_temp":%s,"hold":%s,"spotify_pid":"%s","playback":"%s","dac":"%s","dac_present":%s,"uptime":%s}\n' \
  "${level:-0}" "${bstat:-1}" "${btemp:-0}" "$hold" "$sppid" "$play" "$dac" "$dac_present" "${uptime:-0}"
