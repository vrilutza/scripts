# TODO — îmbunătățiri opționale după test fresh

După ce am un script stabil testat pe fresh Debian Testing install, continui cu astea.

## Ce **lipsește** dar e opțional

| Componentă | Ce face | Impact | Risc |
|---|---|---|---|
| **`hid_apple` fn-mode** (F-keys vs media keys) | Schimbă comportamentul F1-F12 (media keys vs F-keys reale) | Preferință pură | Zero, e parametru kernel |

## Implementate

- **Touchpad UX** — tap-to-click + natural scroll + disable-while-typing (ETAPA 7/8 in script)
- **Thermal management** — thermald 2.5.10 (apt) + lm-sensors + RAPL PL1=22W/PL2=30W Apple-like via systemd service (ETAPA 8/8 in script)

## Ce NU recomand să adăugăm
- **`mbpfan`** — vechi, instabil, fan control built-in pe MBP 2017 merge OK
- **GNOME extensions / Dash-to-Dock** — preferință pură, nu hardware fix
- **Microphone gain custom** — codec-ul Cirrus se descurcă singur

## Onest

Pentru testul tău de stabilitate fresh — **scriptul e complet pentru hardware**. Adăugările de mai sus sunt nice-to-have, nu blocante. Recomand:

1. **Întâi:** testează fresh ce avem acum (asta era planul tău)
2. **Dacă vrei mai mult control la F-keys vs media keys:** `hid_apple` fn-mode (5 minute)

---

# Analiză stabilitate la kernel upgrade — RAPL race condition

Investigare completă mai 28, 2026, după kernel upgrade automat 7.0.7 → 7.0.9 (via `apt dist-upgrade`). Surse: jurnal sistem complet (grup `adm`), 19 boot-uri vizibile în journalctl, sysfs mtimes, /proc/modules.

## 1. Bug confirmat

**Service**: `macbook-rapl.service`

**Comportament observat**: pe boot-urile cu kernel 7.0.9, `ConditionPathExists=/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw` eșuează silent → service skipped → RAPL rămâne nelimitat (100W/125W Apple defaults).

**Statistici empirice** (din `journalctl -u macbook-rapl.service` pe 10 boot-uri):

| Kernel | Success rate |
|---|---|
| 7.0.7 | 3/3 = **100%** |
| 7.0.9 | 5/8 = **62.5%** (37.5% rate de eșec) |

**Cauza root** — race condition de ~110ms între:
- systemd evaluează `ConditionPathExists` la **8.486s** post-boot (pe boot 0 FAILED)
- kernel `intel_rapl_msr` udev probe expune fișierul la **8.596s** (~110ms mai târziu)

Pe boot-urile SUCCESS, alt service blocant (NetworkManager-wait-online @ 3.687s, plymouth-quit-wait @ 4.351s) întârzie systemd suficient cât fișierul să apară primul. Pe boot-urile FAILED, systemd câștigă cursa.

## 2. Impact lateral — thermald

Pe boot-urile FAILED, **și thermald inițializează fără RAPL** ca cooling device:

```
[ 8.408234s] thermald[687]: NO RAPL sysfs present
[ 8.408244s] thermald[687]: 22 CPUID levels; family:model:stepping 0x6:8e:9
```

Polling thermald (4s) **nu rescanează** cooling devices după init — verificat empiric la 40+ min după boot, log-ul thermald conține doar mesajele de la pornire. Asta înseamnă controlul termal RAPL-based e **mort pe întregul boot** pe boot-urile failed.

**Risc real dar nu emergency**: 5 zile fără throttle event în jurnal. `applesmc` (fan) + `intel_pstate` (frequency scaling) compensează. Sub workload sustenut greu (build mare, video encoding lung), CPU poate atinge TJmax 100°C și auto-throttle inconsistent. Fix-ul elimină riscul.

## 3. Fix propus

### F1 — `.path` unit + simplified service

**Fișier nou** `/etc/systemd/system/macbook-rapl.path`:
```ini
[Unit]
Description=Watch for intel-rapl sysfs to apply MacBook RAPL limits
After=thermald.service

[Path]
PathExists=/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw
Unit=macbook-rapl.service

[Install]
WantedBy=multi-user.target
```

**Modificare** `/etc/systemd/system/macbook-rapl.service`: scoate linia `ConditionPathExists=...`.

### F2c — restart thermald după ce RAPL e setat

În `macbook-rapl.service`, adaug:
```ini
ExecStartPost=/bin/systemctl try-restart thermald.service
```

Thermald se reinițializează cu RAPL acum disponibil → vede cooling device → throttling RAPL-based funcțional.

### Modificări în script `ETAPA 8b`

1. Scrie `macbook-rapl.path` + `macbook-rapl.service` (cu ExecStartPost adăugat)
2. `systemctl daemon-reload`
3. `systemctl enable --now macbook-rapl.path` (declanșează service-ul automat)
4. Cleanup idempotent: `systemctl disable macbook-rapl.service 2>/dev/null || true` (pentru sistem unde era enable-d direct via versiunea veche a script-ului)

### Modificări README

- **Diagnostics → Thermal management**: înlocui `systemctl is-active macbook-rapl` cu `systemctl is-active macbook-rapl.path macbook-rapl.service` (ambele trebuie active)
- **Red flag fix instruction**: editezi `.service`, apoi `daemon-reload` + `systemctl restart macbook-rapl.path`
- **Nou paragraf "Why .path unit?"**: explicație race condition + de ce `ConditionPathExists` nu e suficient pe kernels noi

### Alternative evaluate și respinse pentru F1

| Alternativă | De ce respinsă |
|---|---|
| `Restart=on-failure` + retry burst | Hacky pentru un oneshot; risipă de invocări failed |
| `ExecStartPre` cu while-loop wait | Busy-wait, sleeps arbitrare, fragil |
| Udev rule `ACTION=="add" SUBSYSTEM=="powercap"` | Nu poate exprima `After=thermald.service` → race cu thermald |
| Force `intel_rapl_msr` în initramfs | Overkill, schimbă initramfs, fragil la upgrade kernel |

`.path` unit confirmat ca pattern idiomatic — folosit chiar de systemd însăși (`/lib/systemd/system/cups.path`, `tpm-udev.path`).

## 4. Reziliență la kernel upgrade — verificat empiric

| Componentă | Supraviețuiește kernel upgrade? | Verificare |
|---|---|---|
| DKMS audio (`snd_hda_macbookpro`) | ✅ Rebuild automat | `/var/lib/dkms/snd_hda_macbookpro/0.1/7.0.9+deb14-amd64/` creat 26 mai 06:51 |
| DKMS camera (`facetimehd`) | ✅ Rebuild automat | `/var/lib/dkms/facetimehd/0.7.0.1/7.0.9+deb14-amd64/` idem |
| Firmware camera | ✅ Kernel-agnostic | `/usr/lib/firmware/facetimehd/firmware.bin` neatins |
| GRUB params | ✅ Persistent | `/etc/default/grub` neatins de apt |
| Sleep hooks | ✅ Persistent | `/usr/lib/systemd/system-sleep/*` neatins |
| logind override | ✅ Persistent | `/etc/systemd/logind.conf.d/` neatins |
| GNOME gsettings | ✅ Per-user, kernel-independent | gsettings store |
| VA-API + thermald + lm-sensors | ✅ apt-managed | persistent prin apt |
| `macbook-rapl.service` (codul actual) | ❌ NU | 37.5% rate de eșec observată pe 7.0.9 |
| `macbook-rapl.path` (după fix) | ✅ | `PathExists` așteaptă indefinit, elimină race-ul |

**Răspuns final**: NU trebuie rerulat scriptul la kernel upgrade. **Singurul rerun** = O DATĂ după fix, pentru migrarea `.service` → `.path` + `.service`.

## 5. Confirmare hardware sănătos

În ciuda log noise (40+ mesaje "error/warning" per boot), toate subsistemele funcționează:

| Subsistem | Stare | Verificat prin |
|---|---|---|
| WiFi | ✅ `connected:full`, vik connection pe wlp2s0 | `nmcli general` |
| Bluetooth | ✅ `Powered: yes`, `UP RUNNING` cu `errors:0` | `bluetoothctl show`, `hciconfig` |
| Audio | ✅ `/dev/snd/{controlC0,pcmC0D0c/p,pcmC0D3p,hwC0D0/D2}` toate prezente | `ls /dev/snd/` |
| Camera | ✅ `/dev/video0` prezent | `ls /dev/video*` |
| Memory | ✅ ZERO OOM events în 5 zile | journal grep |
| Throttle events | ✅ ZERO în 5 zile | journal grep |

## 6. Catalog "pare bug, dar e benign" pentru investigare viitoare

Pentru fiecare boot apar ~40 mesaje "error/warning". Catalog clasificat:

**Legendă**:
- 🟢 **B** = improvement opțional în script (low risk, win marginal)
- 🟡 **C** = future investigation (complex, risc legal, sau win incert)
- 🔴 **D** = ignore (Apple ACPI/firmware noise inevitabil)

| Cat | Mesaj jurnal | Frecvență | Cauza reală | Fix viitor? |
|---|---|---|---|---|
| 🔴D | `ACPI Error: AE_ALREADY_EXISTS, SSDT Table is already loaded` | 19×/boot, stable | Apple SSDT-uri duplicate; kernel ignoră al doilea | Nu — `acpi_osi=` afectează DSDT global |
| 🔴D | `ACPI Error: Aborting method \_PR.CPU*._OSC/PDC/GCAP/APPT` | ~10×/boot | Apple nu implementează aceste metode standard | Nu — fallback-uri kernel OK |
| 🔴D | `ACPI BIOS Error (bug): Could not resolve symbol [\_SB.OSCP], AE_NOT_FOUND` | 2×/boot | Apple nu expune `_OSC` global | Nu — la fel ca #2 |
| 🟡C3 | `DMAR: Failed to find handle for ACPI object \_SB.PCI0.I2C0/I2C2/UA00` | 3×/boot | Apple I2C ACPI paths non-standard pentru VT-d/IOMMU | Posibil — `intel_iommu=off` în GRUB; risk: dezactivează IOMMU (security trade-off) |
| 🟡C1 | `Bluetooth: hci0: BCM: failed to write update baudrate (-16)` | 1×/boot | BCM4350 refuză upgrade baud (EBUSY), rămâne la 115200 | Posibil — workaround custom complex, BT OK la 115200 |
| 🟡C1 | `Bluetooth: hci0: Failed to set baudrate` | 1×/boot | Continuare a celei de sus | Idem |
| 🟡C2 | `Bluetooth: hci0: BCM: firmware Patch file not found, tried: 'brcm/BCM.hcd'` | 1×/boot | Firmware patch BCM opțional, nu există în Debian | Risc legal de redistribuire din macOS |
| 🟡C2 | `brcmfmac: failed to load brcm/brcmfmac4350c2-pcie.Apple Inc.-MacBookPro14,1.bin (-2)` | 3×/boot | brcmfmac caută variantă Apple-specifică, cade pe generic | Idem — extragere din macOS |
| 🟡C2 | `brcmfmac: failed to load .txt / .clm_blob Apple variants` | 4×/boot | Caută nvram + CLM custom Apple, cade pe defaults | Idem |
| 🟡C3 | `facetimehd: Failed to lock S2 PLL: 0xc902c902` | 1×/boot | PLL primary nu se lock-uiește, fallback safe-settings PLL OK | Nu — upstream driver bug, fără workaround user-side |
| 🔴D | `facetimehd: can't disable ASPM; OS doesn't have ASPM control` | 1×/boot | Apple BIOS restrictionează ASPM control | Nu — `pcie_aspm=off` are trade-off rău (baterie) |
| 🔴D | `facetimehd: module verification failed: signature key missing - tainting kernel` | 1×/boot | DKMS modules nesemnate pe Secure Boot | DKMS auto-creează MOK key; benign fără Secure Boot UEFI |
| 🔴D | `snd_hda_intel: Primary patch_cs8409 NOT FOUND trying APPLE` | 1×/boot | DKMS driver fallback intended la APPLE-specific path | Nu — comportament intended al OOT driver |
| 🔴D | `hci_uart_bcm: Unexpected ACPI gpio_int_idx / GPIOs / No reset resource` | 3×/boot | Apple ACPI lipsuri | Nu — fallback driver OK |
| 🟢B1 | `gsd-media-keys: Failed to grab accelerator for keybinding settings:hibernate` | 1×/login | GNOME încearcă bind hibernate, dar logind dezactivat | Da, în ETAPA 7 — `gsettings set org.gnome.settings-daemon.plugins.media-keys hibernate "[]"` |
| 🟢B2 | `gsd-usb-protection: Failed to fetch USBGuard parameters` | 2×/boot | USBGuard nu instalat; GNOME încearcă oricum | Da — `gsettings set org.gnome.desktop.privacy usb-protection false` |
| 🔴D | `wireplumber: Failed to get percentage from UPower: NameHasNoOwner` | 1×/boot | UPower nu gata la pornire wireplumber | Nu — race normal init |
| 🔴D | `xdg-desktop-portal-gnome / gsd-xsettings: Failed to ...` | 2×/login | GNOME portal/X11 cosmetic | Nu |
| 🔴D | `kernel: x86/cpu: SGX disabled or unsupported by BIOS` | 1×/boot | Apple BIOS dezactivează Intel SGX | Nu — irelevant pe MacBook |

**Concluzia catalogului**: din 23 categorii log noise, **3-4 ar putea avea fix-uri opționale în script** (B1, B2 — GNOME cleanup; posibil C3 DMAR via iommu off). **Restul = Apple ACPI/firmware quirks inevitabil**.

## 7. Plan execuție

```
✓ 1-4. Pass-uri analiza (gata)
✓ 5.   Confirmare empirica: thermald NU rescaneaza RAPL (gata)
 → 6.  Tu aprobi explicit fix-ul (F1 + F2c)
   7.  Eu modific macbook-debian-setup.sh ETAPA 8b + README → commit + push
   8.  Tu: git pull + rulezi scriptul (idempotent migration)
   9.  Tu: sudo reboot
   10. Verificare: RAPL = 22W/30W dupa reboot + thermald log contine RAPL detected
   11. (optional, alt commit) B1+B2 din catalog — GNOME gsettings cleanup
   12. (optional) README section "Boot log triage" — known benign issues
```

**Pasul 8 = singurul moment când rulezi scriptul.** După acest pas, kernel upgrade-urile viitoare nu mai necesită rerun.
