#!/system/bin/sh
# Enable the charger driver's OTG switch as early as Magisk allows.
#
# OnePlus gates USB host mode behind this switch and it defaults to 0. The DAC
# only enumerates while the phone holds the host role, so if the switch is
# still off when the Type-C port finishes attaching, the port settles as
# UFP/device and the DAC stays invisible until the charger is physically
# replugged.
#
# service.sh (late_start) also sets it, but that runs long after the port has
# attached -- which is why the DAC comes up on some boots and not others.
# post-fs-data runs early enough to win that race more often. The node may not
# exist yet this early, so poll briefly rather than give up on the first miss.
OTG_SWITCH=/sys/devices/virtual/oplus_chg/usb/otg_switch

n=0
while [ "$n" -lt 20 ]; do
  if [ -e "$OTG_SWITCH" ]; then
    echo 1 > "$OTG_SWITCH" 2>/dev/null
    break
  fi
  n=$((n + 1))
  sleep 1
done
