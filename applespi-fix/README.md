# applespi-fix — Velocity filter patch for Apple SPI touchpad

Kernel-level fix for the `"Apple SPI Touchpad: kernel bug: Touch jump detected and discarded"` error
on MacBook Pro 2017 (A1708) running Linux.

## The problem

The in-kernel `applespi` driver occasionally receives corrupt coordinates from the SPI bus.
These arrive as valid-looking touch events far outside any physically possible position.
libinput catches them and logs:

```
Apple SPI Touchpad: kernel bug: Touch jump detected and discarded (3.2mm -> 183mm, pointer)
```

The cursor snaps to a random corner and back, making the touchpad unusable.

## The fix

A velocity filter added to `report_tp_state()` in `applespi.c`:

- Any touch event where the coordinate delta from the previous frame exceeds **1440 units ≈ 15 mm**
  is silently dropped before it reaches the input subsystem.
- Bound check: coordinates outside the physical touchpad area are also dropped.

`APPLESPI_MAX_DELTA = 1440` was chosen empirically: 96 units/mm × 15mm — fast enough for any real
swipe, tight enough to discard SPI glitches that jump hundreds of millimetres in one frame.

## Files

| File | Purpose |
|---|---|
| `applespi.c` | Patched driver (velocity filter in `report_tp_state()`) |
| `applespi.h` | Unmodified header from kernel 7.0.7 |
| `applespi_trace.h` | Stub trace header — replaces kernel tracepoints for out-of-tree build |
| `Makefile` | Standard out-of-tree kernel module build |
| `dkms.conf` | DKMS registration (`applespi-fix`, version `7.0.7`) |

## Install manually (step by step)

These commands are run automatically by the main setup script. Use them for manual install or reinstall.

### Prerequisites

```bash
sudo apt-get install build-essential linux-headers-amd64 dkms
```

### 1. Copy sources into DKMS tree

```bash
sudo cp -r applespi-fix /usr/src/applespi-fix-7.0.7
```

### 2. Register with DKMS

```bash
sudo dkms add -m applespi-fix -v 7.0.7
```

### 3. Build

```bash
sudo dkms build -m applespi-fix -v 7.0.7
```

### 4. Install

```bash
sudo dkms install -m applespi-fix -v 7.0.7
```

### 5. Load the patched module (no reboot needed)

```bash
sudo modprobe -r applespi && sudo modprobe applespi
```

### 6. Verify

```bash
# Check DKMS status
sudo dkms status

# Confirm patched module is loaded (vermagic should match running kernel)
/usr/sbin/modinfo applespi | grep -E 'filename|version|vermagic'

# Monitor for 2 minutes — should be silent
journalctl -f 2>/dev/null | grep -i 'touch jump'
```

## Uninstall

```bash
sudo dkms remove applespi-fix/7.0.7 --all
sudo rm -rf /usr/src/applespi-fix-7.0.7
# Reload in-kernel module
sudo modprobe -r applespi && sudo modprobe applespi
```

## Tested on

- MacBook Pro 13" 2017 — Model A1708 (no Touch Bar)
- Debian Testing — kernel `7.0.7+deb14-amd64` — May 2026
- Result: 0 "touch jump" errors after module swap (previously 3/min)
