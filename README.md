# scripts

Setup scripts for **MacBook Pro 13" 2017 (A1708)** running **Debian Testing**.

## Usage

```bash
git clone https://github.com/vrilutza/scripts.git
cd scripts
chmod +x macbook-debian-setup.sh
./macbook-debian-setup.sh
sudo reboot
```

## Scripts

### `macbook-debian-setup.sh`

Full setup for MacBook Pro 13" 2017 on a fresh Debian Testing install. Runs in 5 stages, each with auto-verification before proceeding.

| Stage | What it does |
|---|---|
| 1 — Dependencies | `build-essential`, `linux-headers-amd64`, `linux-source`, `dkms`, `git`, `patch`, `wget`, `curl`, `cpio`, `xz-utils`, `libssl-dev` |
| 2 — Audio driver | [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) — Cirrus CS8409 patched driver via DKMS |
| 3 — Camera firmware | [patjak/facetimehd-firmware](https://github.com/patjak/facetimehd-firmware) — extracted from Apple OS X driver |
| 4 — Camera driver | [patjak/facetimehd](https://github.com/patjak/facetimehd) — kernel module via DKMS |
| 5 — System fixes | Backlight (`acpi_backlight=native`) + stable suspend (`mem_sleep_default=s2idle` + facetimehd sleep hook) |

Both DKMS modules auto-rebuild on kernel updates. The script is idempotent — safe to re-run, skips already completed stages.

## Hardware

- MacBook Pro 13" 2017 — Model A1708 (no Touch Bar)
- CPU: Intel Core i5-7360U (Kaby Lake)
- GPU: Intel Iris Plus Graphics 640
- Audio: Cirrus Logic CS8409 / CS42L83
- Camera: Broadcom 720p FaceTime HD [14e4:1570]
- WiFi: Broadcom BCM4350

## Tested on

Debian Testing — kernel 7.0.7+deb14-amd64 — May 2026.
