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

## Scripts

### `macbook-debian-setup.sh`

Full setup for MacBook Pro 13" 2017 on a fresh Debian Testing install. Runs in 6 stages, each with auto-verification before proceeding.

| Stage | What it does |
|---|---|
| 1 — Dependencies | `build-essential`, `linux-headers-amd64`, `linux-source`, `dkms`, `git`, `patch`, `wget`, `curl`, `cpio`, `xz-utils`, `libssl-dev` |
| 2 — Audio driver | [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) — Cirrus CS8409 patched driver via DKMS |
| 3 — Camera firmware | [patjak/facetimehd-firmware](https://github.com/patjak/facetimehd-firmware) — extracted from Apple OS X driver |
| 4 — Camera driver | [patjak/facetimehd](https://github.com/patjak/facetimehd) — kernel module via DKMS |
| 5 — System fixes | Backlight (`acpi_backlight=native`) + sleep hooks (defensive) + auto-suspend disabled (see below) |
| 6 — VA-API | `intel-media-va-driver` + `i965-va-driver` — hardware video acceleration for Intel Iris Plus 640 |

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

If you previously installed `applespi-fix` via this repo and want to remove it cleanly:

```bash
sudo dkms remove applespi-fix/7.0.7 --all
sudo rm -rf /usr/src/applespi-fix-7.0.7
sudo modprobe -r applespi && sudo modprobe applespi
```

## Hardware

- MacBook Pro 13" 2017 — Model A1708 (no Touch Bar)
- CPU: Intel Core i5-7360U (Kaby Lake)
- GPU: Intel Iris Plus Graphics 640
- Audio: Cirrus Logic CS8409 / CS42L83
- Camera: Broadcom 720p FaceTime HD [14e4:1570]
- WiFi/Bluetooth: Broadcom BCM4350 (WiFi) / BCM4350C0 (Bluetooth, UART on serial0/ttyS4)

## Suspend / sleep

**Auto-suspend on idle is disabled.** S3 deep suspend does not wake reliably on this hardware
(Apple proprietary NVMe + Apple EFI). Tested with all the usual fixes (`nvme.noacpi=1`,
`i915.enable_dc=0`, `nvme_core.default_ps_max_latency_us=0`, brcmfmac PCI unbind hook):
short suspends sometimes wake, longer ones (>20 min) leave the system frozen, only power
button recovers — which causes data loss risk.

Stage 5 configures:

- GNOME `sleep-inactive-ac-type` / `sleep-inactive-battery-type` → `nothing` (no auto-suspend)
- logind override at `/etc/systemd/logind.conf.d/macbook-no-suspend.conf`:
  - `HandleLidSwitch=lock` — closing the lid locks the screen, does not suspend
  - `HandleLidSwitchExternalPower=lock`
  - `HandleLidSwitchDocked=ignore`
- Screen still blanks/locks after idle (GNOME `idle-delay=300`); the laptop stays running.

The GRUB suspend params and sleep hooks (facetimehd, brcmfmac) remain installed — they are
defensive, in case you want to test manual `systemctl suspend`.

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

## Tested on

Debian Testing — kernel `7.0.7+deb14-amd64` — May 2026.
