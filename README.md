# macbook-linux

Setup scripts for **MacBook Pro 13" 2017 (A1708)** running **Debian Testing**.

Each folder is independent — run only what you need.

## Structure

| Folder | Content |
|---|---|
| [`drivers/`](drivers/) | Audio (Cirrus CS8409), Camera (FaceTime HD) |
| [`optimization/`](optimization/) | Battery, thermal, performance tweaks |
| [`dev-tools/`](dev-tools/) | Development environment (IDE, Docker, languages) |
| [`system/`](system/) | Backlight, touchpad, keyboard, suspend |

## Hardware

- MacBook Pro 13" 2017 — Model A1708 (no Touch Bar)
- CPU: Intel Core i5-7360U (Kaby Lake)
- GPU: Intel Iris Plus Graphics 640
- Audio: Cirrus Logic CS8409 / CS42L83
- Camera: Broadcom 720p FaceTime HD [14e4:1570]
- WiFi: Broadcom BCM4350

## Usage

```bash
git clone https://github.com/vrilutza/macbook-linux.git
cd macbook-linux/drivers
chmod +x macbook-debian-setup.sh
./macbook-debian-setup.sh
```

## Scripts

### `drivers/macbook-debian-setup.sh`

Installs audio and FaceTime HD camera drivers on a fresh Debian Testing install.

- **Audio**: [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) — Cirrus Logic CS8409 patched driver via DKMS
- **Camera firmware**: [patjak/facetimehd-firmware](https://github.com/patjak/facetimehd-firmware) — extracted from Apple OS X driver
- **Camera driver**: [patjak/facetimehd](https://github.com/patjak/facetimehd) — kernel module via DKMS

Both DKMS modules auto-rebuild on kernel updates.

## OS

Tested on **Debian Testing** (kernel 7.0.7+deb14-amd64) — May 2026.
