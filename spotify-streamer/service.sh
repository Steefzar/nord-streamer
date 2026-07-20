#!/system/bin/sh
# Magisk late_start service script for the spotify-streamer module.
# Makes the phone a headless Spotify Connect target.

# Wait for full boot, then give Wi-Fi a moment to associate
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 20

# --- Friendly device name: Spotify Connect shows the device identity,
# which lives in several props ("AC2003" / "OnePlus Nord" on this hardware).
# All must be overridden before Spotify starts.
NAME="Nord Streamer"
for p in ro.product.model ro.product.odm.model ro.product.product.model \
         ro.product.system.model ro.product.system_ext.model \
         ro.product.vendor.model ro.product.vendor_dlkm.model \
         bluetooth.device.default_name vendor.usb.product_string; do
  resetprop "$p" "$NAME"
done
settings put global device_name "$NAME"
settings put secure bluetooth_name "$NAME"

# --- ADB over Wi-Fi (debug without touching the device) ---
setprop service.adb.tcp.port 5555
stop adbd
start adbd

# --- Keep-alive settings (idempotent, cheap to re-apply every boot) ---
settings put global wifi_sleep_policy 2
dumpsys deviceidle whitelist +com.spotify.music
dumpsys deviceidle whitelist +com.aurora.store
# Disable Wi-Fi power-save napping; without this, mDNS responses are delayed
# and the device is slow to appear as a Connect target
cmd wifi force-low-latency-mode enabled

# --- Debug web UI (busybox httpd + CGI), LAN only, port 8080 ---
BB=/data/adb/magisk/busybox
WEBROOT=/data/adb/modules/spotify-streamer/webui
chmod 755 "$WEBROOT"/cgi-bin/*.sh 2>/dev/null

# --- Charge governor setup: this kernel's oplus driver ignores the usual
# charge-enable switches but respects the battery thermal cooling device
# (cur_state 10 = 0 mA into the battery, verified against the fuel gauge).
# Resolve it by type since cooling_device numbering can shift across boots.
CDEV=""
for d in /sys/class/thermal/cooling_device*; do
  [ "$(cat "$d/type" 2>/dev/null)" = "battery" ] && CDEV="$d/cur_state" && break
done

# --- USB host mode for the DAC ---
# The DAC only enumerates while the phone holds the USB host (DFP) role. With
# the charger feeding the dongle's passthrough port the phone attaches as
# UFP/device, the DAC never appears, and audio falls back to the speaker.
#
# OnePlus gates host mode behind the charger driver's own OTG switch, which
# defaults to 0 on this ROM. While it is off nothing will enumerate no matter
# what else is driven -- the port will happily report the host role and still
# show an empty bus.
OTG_SWITCH=/sys/devices/virtual/oplus_chg/usb/otg_switch

# Root hubs are usbN plus their N-0:1.0 interface, so a genuine downstream
# device is N-M with M >= 1 -- matching N-0 would report success on an empty bus.
usb_device_attached() {
  ls /sys/bus/usb/devices/ 2>/dev/null | grep -qE '^[0-9]+-[1-9]'
}

usb_otg_enable() {
  [ -e "$OTG_SWITCH" ] || return 1
  echo 1 > "$OTG_SWITCH" 2>/dev/null
}

# Enabling OTG is necessary but not sufficient: whether the port settles as
# host depends on whether the switch won the race against the Type-C attach at
# boot, so some boots come up with the DAC and some do not.
#
# Nothing that only drives the role recovers it -- not the HAL role swap, not
# writing data_role, not port_type on its own, not cycling the dwc3 controller.
# What does work is cycling the OTG switch *around* a port_type transition:
# that makes the stack re-run detection, and it comes up as host with the DAC
# enumerated. Charging is not interrupted. The sleeps matter; the transitions
# are not instant and skipping the settle time makes it fail.
TYPEC_PORT=/sys/class/typec/port0
usb_host_recover() {
  [ -e "$OTG_SWITCH" ] && [ -e "$TYPEC_PORT/port_type" ] || return 1
  echo 0 > "$OTG_SWITCH" 2>/dev/null
  sleep 2
  echo sink > "$TYPEC_PORT/port_type" 2>/dev/null
  sleep 3
  echo 1 > "$OTG_SWITCH" 2>/dev/null
  sleep 2
  echo dual > "$TYPEC_PORT/port_type" 2>/dev/null
  sleep 8
  usb_device_attached
}

usb_otg_enable

# Bring the DAC up after boot when the port lost the race.
(
  sleep 30
  n=0
  while [ "$n" -lt 3 ]; do
    usb_device_attached && break
    usb_host_recover && break
    n=$((n + 1))
    sleep 15
  done
) &

# --- Spotify Connect liveness ---
# A pidof test is not enough: when Spotify is idled into the background it
# tears down its Connect/zeroconf listeners but the process stays alive, so
# pidof keeps succeeding while the device has silently stopped being
# discoverable (the symptom is having to restart Spotify by hand before it
# shows up). UDP 57621 -- E115 in /proc/net's hex notation -- is Spotify's
# local-discovery socket and is bound only while it is really announcing
# itself as a Connect target. Re-launching rebinds it without waking the
# screen. The uid is resolved every call because it changes on reinstall.
spotify_connectable() {
  pidof com.spotify.music >/dev/null 2>&1 || return 1
  uid=$(stat -c %u /data/data/com.spotify.music 2>/dev/null)
  [ -n "$uid" ] || return 0
  awk -v u="$uid" '$8==u && $2 ~ /:E115$/ {f=1} END{exit !f}' \
      /proc/net/udp /proc/net/udp6
}

# --- Watchdog: relaunch Spotify or the web UI whenever they die or, in
# Spotify's case, go undiscoverable ---
(
  cyc=0
  while true; do
    cyc=$((cyc + 1))
    if ! spotify_connectable; then
      # monkey resolves the launcher activity itself; survives Spotify updates
      monkey -p com.spotify.music -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
      sleep 8
      # Only sleep the screen if the launch actually worked, so a missing
      # Spotify install doesn't blank the screen every cycle
      if pidof com.spotify.music >/dev/null 2>&1; then
        input keyevent 223
      fi
    fi
    if ! $BB pgrep -f "httpd -p 8080" >/dev/null 2>&1; then
      $BB httpd -p 8080 -h "$WEBROOT"
    fi
    # Charge governor: charge up to 75%, then hold (battery idles at 0 mA
    # while the charger powers the system); resume only if it drains to 40%.
    # Also cut charging above 45.0 C. Reasserted every cycle since thermal
    # services may reset cur_state.
    if [ -n "$CDEV" ]; then
      cap=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
      temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
      if [ "${cap:-0}" -ge 75 ] || [ "${temp:-0}" -ge 450 ]; then
        echo 10 > "$CDEV"
      elif [ "${cap:-100}" -le 40 ]; then
        echo 0 > "$CDEV"
      fi
    fi
    # Recover the DAC if it is missing. Rate-limited to ~10 min: the sequence
    # cycles the Type-C port, and when the DAC is genuinely unplugged there is
    # nothing to find, so there is no point retrying every cycle.
    if ! usb_device_attached; then
      usb_otg_enable
      [ $((cyc % 5)) -eq 0 ] && usb_host_recover
    fi
    sleep 120
  done
) &
