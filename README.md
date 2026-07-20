# Nord Streamer

Turns a rooted OnePlus Nord (AC2003, Android 16, Magisk, no GAPPS) into a headless
**Spotify Connect streamer** feeding a USB DAC with bit-matched lossless audio
(24-bit/44.1 kHz). The phone lies screen-off next to the amp.

> **This is a janky personal project, not a product.** It is built for exactly
> one phone, one DAC and one flat where it sits on a shelf next to the amp.
> Expect hardcoded assumptions, sharp edges and things that only work because
> of a quirk of this particular kernel. It pokes vendor sysfs nodes, ships an
> overlay of a vendor audio config, and one companion module reflashes the boot
> partition. Nothing here is tested beyond my own device.
>
> The web UI has **no authentication whatsoever** — it can reboot the phone,
> power it off, and tap anywhere on its screen. LAN only. Do not port-forward it.
>
> It also does not fully work: whether the DAC enumerates after a boot is a race
> that is lost maybe a third of the time, and the fix is to physically replug
> the charger. See the hardware notes for why. If you want a reliable Spotify
> Connect endpoint, buy one.

Published in case the hardware notes below save someone else the two days of
poking at `oplus_chg` sysfs that they cost me.

## What the Magisk module does (`spotify-streamer/`)

Everything runs from `service.sh` at boot:

- **Device identity** — overrides all model/name props (`AC2003` → `Nord Streamer`)
- **ADB over Wi-Fi** on port 5555 for headless debugging (`scrcpy` friendly)
- **Keep-alive** — doze whitelist for Spotify + Aurora Store, Wi-Fi low-latency
  mode (fixes slow Spotify Connect/mDNS discovery caused by Wi-Fi power-save)
- **Watchdog loop (every 2 min):**
  - relaunches Spotify if its process died (crash, update, reboot) **or if it
    stopped advertising as a Connect target**, then sleeps the screen. The
    liveness test is the presence of Spotify's UDP 57621 discovery socket, not
    just the pid — an idled Spotify keeps its process but drops the listener,
    which used to leave the device silently undiscoverable until a manual restart
  - restarts the web UI server if it died
  - **charge governor** — charge to 75 %, then hold (battery idles at 0 mA while
    the charger powers the system); resume below 40 %; hard cutoff above 45 °C
- **USB host mode** — 30 s after boot, takes the USB host (DFP) role so the DAC
  enumerates; verified and rolled back if nothing appears, and retried every
  ~30 min in case the DAC is plugged in later (see the Type-C note below)
- **Audio policy overlay** — pins the `deep_buffer` output to 44 100 Hz in
  `/vendor/etc/audio_policy_configuration.xml` so Spotify Lossless reaches the
  DAC without resampling (verify: `/proc/asound/card0/pcm0p/sub0/hw_params`)
- **Keylayout overlay** — neutralizes the DAC's HID buttons
  (`Vendor_0572_Product_1b09.kl`); the DAC fired a phantom PLAY on connect
- **Web UI** — busybox `httpd` + shell CGI on port **8080**, no dependencies:
  live status (battery/hold, playback, actual DAC stream format, temp, uptime),
  transport & system controls, log viewers, and a remote screen with
  click-to-tap and drag-to-swipe. LAN only, **no auth — do not port-forward.**

## Usage

```sh
./install.sh            # build the module zip and install it over ADB, then: adb reboot
./build.sh              # just build spotify-streamer.zip
./debloat.sh disable    # disable the 42 packages in debloat.txt (reversible)
./debloat.sh enable     # re-enable them all
```

Web UI: `http://<device-ip>:8080` · ADB: `adb connect <device-ip>:5555`

Tunables at the top of `spotify-streamer/service.sh`: device name (`NAME`),
charge thresholds (75/40/450), web UI port. Bump `versionCode` in
`module.prop` when editing, then `./install.sh` + reboot.

## Hardware-specific notes (OnePlus Nord, oplus_chg kernel)

Hard-won findings — likely apply to other OnePlus 8-era devices:

- The **only working charge cutoff** is the battery thermal cooling device
  (`/sys/class/thermal/cooling_device*` with `type` = `battery`):
  `cur_state 10` = 0 mA, `0` = normal. The usual switches (`input_suspend`,
  `mmi_charging_enable`, `/proc/charger_cycle`) are silently reset by the driver.
- `battery/current_now` is broken (always ~0). Real charge current is the 5th
  field of the `GAUGE[...]` line in dmesg (`OPLUS_CHG` log). The battery status
  enum keeps saying "Charging" even when paused — read the cooling device instead.
- **ACC does not work** on this kernel for the reasons above.
- **The DAC only enumerates while the phone holds the USB host role.** With the
  charger feeding the dongle's PD passthrough, the phone attaches as
  UFP/device (`typec_mode` = `Source attached (high current)`, `data_role` =
  `device`) and the DAC is invisible — no entry under `/sys/bus/usb/devices`,
  one card in `/proc/asound/cards`, audio silently on the speaker. Once host
  mode holds, charging and audio work together fine — the port supports
  `sink + host`, confirmed at 24-bit/44.1 kHz while charging.
- **Host mode is gated by `/sys/devices/virtual/oplus_chg/usb/otg_switch`,
  which defaults to 0.** While it is off nothing enumerates no matter what else
  is driven — the port will report the host role over an empty bus, which makes
  this easy to misdiagnose. The module sets it from `post-fs-data.sh` (early)
  and re-asserts it from `service.sh`.
- **Whether the DAC appears is a boot race, and it is only partly winnable.**
  The dongle decides its own role when it attaches: if the phone is UFP at that
  moment it latches into charger-passthrough and never presents a USB device.
  Nothing on the phone undoes that afterwards — not the HAL role swap, not
  `data_role`, not `port_type`, not restarting xHCI via `ssusb/mode`. You can
  get the port to host with root hubs up and still have an empty bus. Cycling
  `otg_switch` around a `port_type` transition sometimes recovers it (the
  module tries this at boot and every ~10 min), but measured success is roughly
  **4 boots in 6**. When it fails, **physically replugging the charger is the
  only reliable fix** — the web UI's `dac_present` field flags when that is
  needed.
- Useful tell: `data_role`/`power_role` show the **current** role in brackets,
  e.g. `host [device]` means it is currently a device. `dumpsys usb` gives the
  same in `port_manager`, plus `num_connects` (0 = nothing ever enumerated).
- USB audio does **not** stream through the USB card's own PCM. The ADSP drives
  the endpoint, so `/proc/asound/card0/...` (the DAC) reads `closed` while
  playing and the live stream shows up on the platform card's PCM instead.
  Confirm routing with `dumpsys media.audio_flinger` — look for an output
  thread with `Output devices: 0x4000000 (AUDIO_DEVICE_OUT_USB_HEADSET)` and
  `Standby: no`.
- Spotify Connect's display name is pinned server-side at registration
  ("OnePlus Nord"); prop overrides only take effect after a Spotify re-login.

## Companion Magisk modules

- **[magisk-autoboot](https://github.com/Magisk-Modules-Alt-Repo/magisk-autoboot)** —
  boots the phone automatically when power is connected, so a flat battery or a
  crash does not leave the streamer dark until someone presses the button.
  Verified here: power off with the charger attached and it is back up in ~75 s.
  **It patches and reflashes the boot partition** (adds an `on charger` init
  trigger that sets `sys.powerctl reboot` above 5 % battery) — it is not an
  ordinary systemless module. It resolves the right target on this device
  (`boot_a`; there is no `init_boot`, and Magisk lives in boot, not recovery).
  Keep a boot image backup before installing: the installer leaves one at
  `/data/adb/modules/magisk-autoboot/AutoBoot-Backup/backup_boot.img`, and an
  independent copy is in `../nord-streamer-backups/`.

## Companion device setup (not in the module)

- Spotify via **Aurora Store**: auto-updates on, installer = Root (Aurora granted
  su via Magisk policy DB), doze-whitelisted → fully unattended updates
- The DAC dongle (Synaptics `0572:1b09`, descriptor "Synaptics Hi-Res Audio",
  full speed, S16_LE / S24_3LE at up to 96 kHz) has its own **PD passthrough
  port**, so the charger plugs into the dongle rather than the phone — which is
  what puts the phone in UFP/device mode and makes the host-mode step necessary
- Static IP via router DHCP reservation (mind Android's per-network random MAC)
