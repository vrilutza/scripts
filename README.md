# scripts

Setup scripts for **MacBook Pro 13" 2017 (A1708)** running **Debian Testing**.

## Prerequisites — fresh Debian Testing install

Before running this script:

1. **Install Debian Testing with non-free firmware enabled** — the Debian installer must include
   `firmware-iwlwifi`, `firmware-brcm80211` and friends. The graphical installer offers
   "non-free-firmware" as a checkbox; the netinst ISO from `cdimage.debian.org/cdimage/unofficial/non-free/firmware/`
   has them bundled. Without these, WiFi/Bluetooth will not work even after this script runs.
2. **Boot into GNOME, open a terminal**, then install `git`:
   ```bash
   sudo apt update
   sudo apt install -y git
   ```
3. **(Optional) If migrating from macOS:** perform an SMC Reset once (see Bluetooth section below)
   — otherwise Bluetooth will stay broken even after the script runs.

## Usage

```bash
git clone https://github.com/vrilutza/scripts.git
cd scripts
chmod +x macbook-debian-setup.sh
./macbook-debian-setup.sh
sudo reboot
```

## After reboot — quick stability check

| What to test | How |
|---|---|
| Audio (speakers + headphones jack) | Play any sound; toggle output in GNOME Settings → Sound |
| Camera | `cheese` or any video-call app — `/dev/video0` should exist |
| Backlight | `Fn+F1` / `Fn+F2` — slider should respond smoothly |
| WiFi | Connect to your network from GNOME |
| Bluetooth | Pair a device from GNOME Settings → Bluetooth (SMC reset first if needed) |
| Touchpad | Tap, swipe, two-finger scroll — cursor should be smooth |
| VA-API (video accel) | `vainfo` should print supported profiles |
| Suspend | Auto-suspend is **disabled by design**. Closing the lid only locks the screen. |
| DKMS rebuild | `sudo dkms status` — `snd_hda_macbookpro` and `facetimehd` should show `installed` |

## Diagnostics & monitoring per subsystem

Commands you can come back to without remembering anything — open this section, copy what you need. All read-only unless noted. Some commands need extra tools; the `apt install` hint is shown where relevant.

### Audio (Cirrus CS8409)

```bash
sudo dkms status snd_hda_macbookpro      # DKMS module installed + built for current kernel?
lsmod | grep cs8409                      # Codec module loaded right now?
cat /proc/asound/cards                   # ALSA sees the card?
aplay -l                                 # Playback devices visible to ALSA?
```

Quick live test: from GNOME Settings → Sound, toggle output between Speakers and Headphones; both should respond. If audio dies after a kernel upgrade, run `sudo dkms status` first — DKMS rebuilds the module automatically against the new headers and a missing rebuild is the usual culprit.

### Camera (FaceTime HD)

```bash
ls -la /dev/video*                                   # Device node present after boot?
lsmod | grep facetimehd                              # Driver loaded right now?
sudo dkms status facetimehd                          # DKMS state (installed against current kernel)?
ls -la /usr/lib/firmware/facetimehd/firmware.bin     # ~1.4 MB firmware in place?
sudo modinfo facetimehd | head -10                   # Driver metadata (version, deps)
```

Quick live test: `sudo apt install cheese && cheese` — webcam preview should appear in 1-2 seconds. If `/dev/video0` is missing right after boot, try `sudo modprobe facetimehd` manually.

### System fixes (backlight, suspend, lid behavior)

```bash
cat /proc/cmdline                                                                # Kernel boot params currently active
ls -la /usr/lib/systemd/system-sleep/                                            # Sleep hooks (facetimehd, brcmfmac) present?
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type     # Should be 'nothing'
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type # Should be 'nothing'
cat /etc/systemd/logind.conf.d/macbook-no-suspend.conf                           # Lid switch override
systemctl show systemd-logind | grep -i lid                                      # Effective lid behavior (Lock = correct)
```

To test the backlight keys: `Fn+F1` / `Fn+F2` — slider in GNOME panel should slide smoothly without jumps.

### Video acceleration (VA-API)

```bash
LIBVA_DRIVER_NAME=iHD vainfo 2>&1 | head -10    # iHD driver (Kaby Lake native) profiles
vainfo 2>&1 | grep VAProfile                    # All profiles available (any driver)
dpkg -l intel-media-va-driver i965-va-driver    # Both VA-API packages installed?
```

Browser-side check: open `chrome://gpu` in Chrome/Chromium and look for **Video Decode: Hardware accelerated**. In Firefox, `about:support` → search "Decoder" → should show VAAPI for H.264/HEVC.

### Touchpad UX

```bash
# Current GNOME settings — should all return 'true'
gsettings get org.gnome.desktop.peripherals.touchpad tap-to-click
gsettings get org.gnome.desktop.peripherals.touchpad natural-scroll
gsettings get org.gnome.desktop.peripherals.touchpad disable-while-typing

# Touchpad device known to libinput  (apt install libinput-tools if missing)
sudo libinput list-devices | grep -A 6 -i touchpad
```

To live-debug events (e.g., "did my tap register as click?"): `sudo libinput debug-events` then touch the trackpad; Ctrl+C to stop. To check libinput discarding bad touchpad events (the "Touch jump detected" messages): `journalctl -k --since "1 hour ago" | grep -i "touch jump"`.

### Thermal management

```bash
# Live temps + fan speed (Ctrl+C to exit)
watch -n 1 'sensors | grep -E "Core|fan"'

# One-shot read of all sensors (CPU, battery, ambient)
sensors

# RAPL limits currently active (constraint_0 = PL1, constraint_1 = PL2)
grep . /sys/class/powercap/intel-rapl:0/constraint_*_power_limit_uw

# Recent thermal throttle events
journalctl --since "1 hour ago" | grep -iE "throttle|thermal"

# Is thermald running + did the udev rule fire its reinit service?
systemctl is-active thermald macbook-rapl-thermald.service

# The udev rule that sets RAPL on device appearance
cat /etc/udev/rules.d/99-macbook-rapl.rules

# How thermald picks up RAPL each boot: the first thermald instance starts
# before the powercap device and logs "NO RAPL sysfs present" (2 lines, expected),
# then the udev rule sets RAPL and restarts thermald. Confirm the restart happened
# *after* RAPL was set — the running thermald instance is the one that sees RAPL:
journalctl -u thermald -u macbook-rapl-thermald.service -b 0 | tail -8
# Expected tail: "...reinit... Finished", immediately followed by thermald "Started".
```

**Expected ranges on i5-7360U with PL1=22W / PL2=30W:**

| Scenario | Temperature |
|---|---|
| Idle / light browsing | 40-60°C |
| YouTube / Netflix HD (VA-API active) | 60-75°C |
| Sustained heavy load (build, video encode) | 80-92°C — PL1 22W cap engages |
| Brief burst (app launch, short compile) | up to ~95°C — PL2 30W, transient |

**Red flags worth investigating:**

- **Idle persistent over 70°C** — RAPL may not be applied (`grep .` command above) or thermald is down (`systemctl is-active thermald`).
- **Sustained over 95°C with fan maxed** — PL1 is too aggressive for this thermal solution. To lower it, edit the two `ATTR{constraint_*_power_limit_uw}` values in `/etc/udev/rules.d/99-macbook-rapl.rules` (change `22000000` to e.g. `18000000`), then `sudo udevadm control --reload && sudo udevadm trigger --action=add /sys/class/powercap/intel-rapl:0`. No reboot needed.

**Why a udev rule (not tmpfiles / `.service` / `.path`)?** This repo went through four iterations:

1. **v1 — `tmpfiles.d`**: wrote RAPL limits at early boot. Failed because `intel_rapl_msr` loads via udev later in boot and overwrote our values with Apple EFI defaults (100W / 125W).
2. **v2 — `.service` with `ConditionPathExists`**: worked on kernel 7.0.7 (100% of boots) but **failed on ~37.5% of boots on kernel 7.0.9** due to a ~110 ms race condition: systemd evaluated the condition *just before* the kernel's udev probe exposed the sysfs file. Worse, `thermald` itself initialised without RAPL on the same failed boots (logged `NO RAPL sysfs present`) — and its 4-second polling does *not* rediscover cooling devices.
3. **v3 — `.path` unit + `.service`**: also failed. `.path` units use **inotify**, and sysfs does *not* reliably emit inotify creation events — so the trigger only fired when the file already existed at `.path` start time (still a race). Plus `After=thermald.service` on a `.path` unit created an ordering cycle (paths.target is ordered *before* basic.target, thermald *after*).
4. **v4 (current) — udev rule**: `ACTION=="add", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:0"` writes the limits directly via `ATTR{constraint_*_power_limit_uw}=`. udev fires on the kernel's *real* device-add uevent (reliable, unlike inotify on sysfs), so the values are set deterministically the moment the device appears — on any kernel. `TAG+="systemd"` + `ENV{SYSTEMD_WANTS}+="macbook-rapl-thermald.service"` pulls in a tiny oneshot that `try-restart`s thermald so it reinitialises and discovers RAPL. Verified empirically: `udevadm trigger --action=add` re-applies 100W→22W, and thermald restarted after RAPL is set no longer logs `NO RAPL sysfs present`.

### WiFi & Bluetooth

```bash
lsmod | grep brcmfmac           # WiFi driver loaded?
nmcli device wifi               # Visible networks + current connection
nmcli device status             # All network interfaces state
systemctl status bluetooth      # Bluetooth daemon running?
bluetoothctl show               # Adapter info; expect "Powered: yes"
```

Live BT debug: `journalctl -u bluetooth -f`, then try to pair from GNOME Settings — watch for `BCM: Reset failed` (means you need the SMC Reset described in [Bluetooth section below](#bluetooth)).

### General health — anything failing this boot?

```bash
journalctl -p err -b --no-pager            # All errors since boot
systemctl --failed                          # Any failed unit?
sudo dkms status                            # All DKMS modules state (both snd_hda_macbookpro and facetimehd should show 'installed')
uptime                                      # Boot time + load avg
```

If `systemctl --failed` lists anything, drill in with `systemctl status <unit>` and `journalctl -u <unit>` for that specific unit.

## Scripts

### `macbook-debian-setup.sh`

Full setup for MacBook Pro 13" 2017 on a fresh Debian Testing install. Runs in 8 stages, each with auto-verification before proceeding.

| Stage | What it does |
|---|---|
| 1 — Dependencies | `build-essential`, `linux-headers-amd64`, `linux-source`, `dkms`, `git`, `patch`, `wget`, `curl`, `cpio`, `xz-utils`, `libssl-dev` |
| 2 — Audio driver | [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) — Cirrus CS8409 patched driver via DKMS |
| 3 — Camera firmware | [patjak/facetimehd-firmware](https://github.com/patjak/facetimehd-firmware) — extracted from Apple OS X driver |
| 4 — Camera driver | [patjak/facetimehd](https://github.com/patjak/facetimehd) — kernel module via DKMS |
| 5 — System fixes | Backlight (`acpi_backlight=native`) + `reboot=pci` + sleep targets masked (suspend/hibernate blocked — see below) |
| 6 — VA-API | `intel-media-va-driver` + `i965-va-driver` — hardware video acceleration for Intel Iris Plus 640 |
| 7 — Touchpad UX | `tap-to-click` + `natural-scroll` + `disable-while-typing` via gsettings — macOS-like out of the box |
| 8 — Thermal management | `thermald` + `lm-sensors` + RAPL PL1=22W / PL2=30W (Apple-like) via udev rule + thermald reinit |

The two DKMS modules (audio, camera) auto-rebuild on kernel updates. The script is idempotent — safe
to re-run, skips already completed stages.

## Touchpad — no patch needed

Previous versions of this script shipped an out-of-tree `applespi-fix/` DKMS patch with a velocity
filter to catch SPI-bus coordinate glitches before they reached libinput. Real-world testing showed
the patch reduced touch-jump frequency only marginally (it only caught the case where finger count
stayed constant between frames), and **libinput already discards these events in userspace** —
the cursor does not visibly jump.

The patch has been removed. libinput's own `tp_motion_history` detection handles all glitch cases
cleanly. The `kernel bug: Touch jump detected and discarded` messages still appear in the journal
when libinput discards a bad event, but that is the protection mechanism working as designed, not
a defect.

Root cause is hardware-level SPI bus instability on Apple T1/T2 systems — there is no software-only
cure. libinput's secondary filtering is sufficient.

## Hardware

- MacBook Pro 13" 2017 — Model A1708 (no Touch Bar)
- CPU: Intel Core i5-7360U (Kaby Lake)
- GPU: Intel Iris Plus Graphics 640
- Audio: Cirrus Logic CS8409 / CS42L83
- Camera: Broadcom 720p FaceTime HD [14e4:1570]
- WiFi/Bluetooth: Broadcom BCM4350 (WiFi) / BCM4350C0 (Bluetooth, UART on serial0/ttyS4)

## Suspend / sleep / hibernation — why it's blocked, not fixed

**Short version: S3 sleep and hibernation cannot be made reliable on this MacBook, so the script
blocks all sleep entirely. The laptop is meant to run always-on; closing the lid only locks the
screen.**

### Why S3 (suspend-to-RAM) can't be fixed

S3 "deep" suspend does not wake reliably on MacBookPro14,1 (Apple proprietary NVMe + Apple EFI).
The kernel enters `PM: suspend entry (deep)` fine, but the hardware often never generates a wake
event — the machine stays frozen and only a forced power-off recovers it (data-loss risk). This
was tested with every standard fix and none make it dependable:

- `mem_sleep_default=deep` (S3 instead of the s2idle that crashes Apple NVMe)
- `nvme.noacpi=1`, `nvme_core.default_ps_max_latency_us=0` (Apple NVMe power-state quirks)
- `i915.enable_dc=0` (Intel display C-states crash on resume)
- brcmfmac PCI-unbind sleep hook

Result: short suspends sometimes wake, longer ones (>20 min) freeze. It is a firmware/hardware
limitation of how Apple implements power management — there is no software-only cure.

### Why hibernation (S4, suspend-to-disk) won't save you either

Hibernation is a *different* mechanism (write RAM to swap, power off, restore on next boot), so
it's tempting to think it sidesteps the S3 wake problem. In practice it doesn't, on this hardware:

1. **It inherits the same Apple resume path** — restoring from hibernation still goes through the
   Apple EFI + NVMe bring-up that's unreliable.
2. **It needs swap ≥ RAM** set up as a resume device, plus a `resume=` kernel param — extra config
   that this minimal setup doesn't ship.
3. **The Apple NVMe quirks** (`nvme.noacpi`, PS0 pinning) that we apply for stability also work
   against the clean low-power state hibernation expects.

So chasing hibernation here is a dead end. That's the honest answer: **don't try to "enable
hibernation" on this MacBook — it will cost you hours and still not be dependable.**

### What the script does instead (Stage 5)

Since sleep is unfixable, the script *prevents* it so the machine can never hang trying:

- GNOME `sleep-inactive-ac-type` / `sleep-inactive-battery-type` → `nothing` (no idle auto-suspend)
- logind override `/etc/systemd/logind.conf.d/macbook-no-suspend.conf`: `HandleLidSwitch=lock`
  (+ ExternalPower=lock, Docked=ignore) — lid close locks the screen, does not suspend
- **`systemctl mask sleep.target suspend.target hibernate.target suspend-then-hibernate.target`**
  — the bulletproof layer. gsettings + lid alone proved insufficient: a `suspend-then-hibernate`
  still fired once on long idle (lid closed, on battery) and hung S3. Masking the sleep targets
  makes *any* suspend/hibernate impossible — nothing can trigger it.
- `reboot=pci` in GRUB — the default reset method does not reliably reset Apple hardware (reboot
  hangs at "Rebooting."); `reboot=pci` forces a reset via PCI port 0xcf9. Tested working on
  MacBookPro14,1. (If a future kernel breaks it, alternatives are `reboot=efi` / `reboot=acpi`.)

The screen still blanks/locks after idle; the laptop just stays running. The sleep hooks
(facetimehd, brcmfmac) remain installed but are now moot while sleep is masked — they only matter
if you ever `unmask` the targets to experiment.

**To experiment with suspend anyway** (knowing it may hang):
`sudo systemctl unmask sleep.target suspend.target hibernate.target suspend-then-hibernate.target`

## Bluetooth

The Bluetooth chip (BCM4350C0) communicates over UART, not USB. Linux initializes it at 115200 baud,
but macOS leaves it at 3 Mbaud at shutdown — so after migrating from macOS the chip doesn't respond
and `hci0` fails to initialize:

```
Bluetooth: hci0: command 0xfc18 tx timeout
Bluetooth: hci0: BCM: Reset failed (-110)
```

**Fix — SMC Reset (one time only, after first boot from macOS):**

1. Shut down completely: `sudo shutdown -h now`
2. Hold **Shift left + Control left + Option left + Power** simultaneously for 10 seconds
3. Release all keys, then press **Power** to boot normally

The SMC Reset power-cycles the chip back to 115200 baud. After that Linux initializes it correctly
and resets it to 115200 on every shutdown — so subsequent boots work without SMC Reset.

### Warm reboot can leave WiFi/Bluetooth unresponsive

WiFi (BCM4350 on PCIe) and Bluetooth (BCM4350C0 on UART) are the **same physical Broadcom combo
chip**. A warm reboot (`sudo reboot`) does **not** fully power-cycle this chip, and after several
rapid successive reboots it can land in an unresponsive state:

- **WiFi**: `brcmfmac: brcmf_chip_recognition: MMIO read failed: 0xffffffff` → `brcmf_pcie_probe: failed` (chip returns all-ones on PCIe = not responding)
- **Bluetooth**: `command 0xfc18 tx timeout` → `BCM: Reset failed (-110)` (chip times out on UART), `hci0` stays `DOWN`

This is a **hardware-level limitation, not a software bug** — none of this repo's hooks run on
reboot. Observed empirically: across 8 rapid reboots, WiFi failed once (self-recovered next boot)
and Bluetooth went unresponsive after the burst.

**Recovery: a full power-off, not a warm reboot.**

```bash
sudo shutdown -h now
# wait ~10 seconds, then power on
```

A complete power-off de-powers the Broadcom chip so it comes up clean. Re-running the setup script
does **not** help — there is no software fix for an unresponsive chip. (Tip: the distinction shows in
the log — error `-16` / EBUSY means the chip still answered and BT worked; error `-110` / timeout
means the chip is fully unresponsive and needs the power cycle.)

## Tested on

Debian Testing — kernel `7.0.7+deb14-amd64` — May 2026.
