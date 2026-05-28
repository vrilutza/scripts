# TODO — îmbunătățiri opționale după test fresh

După ce am un script stabil testat pe fresh Debian Testing install, continui cu astea.

## Ce **lipsește** dar e opțional

| Componentă | Ce face | Impact | Risc |
|---|---|---|---|
| **`hid_apple` fn-mode** (F-keys vs media keys) | Schimbă comportamentul F1-F12 (media keys vs F-keys reale) | Preferință pură | Zero, e parametru kernel |

## Implementate

- **Touchpad UX** — tap-to-click + natural scroll + disable-while-typing (ETAPA 7/8 in script)
- **Thermal management** — thermald 2.5.10 (apt) + lm-sensors + RAPL PL1=22W/PL2=30W Apple-like via regula udev + thermald reinit (ETAPA 8/8 in script)

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

## 3. Fix — istoric iterații (v1 → v4)

| Ver | Abordare | Rezultat |
|---|---|---|
| v1 | `/etc/tmpfiles.d/macbook-rapl.conf` | ❌ intel_rapl_msr suprascria valorile cu Apple defaults după boot |
| v2 | `macbook-rapl.service` + `ConditionPathExists` | ❌ race ~110ms, 37.5% eșec pe 7.0.9 |
| v3 | `macbook-rapl.path` (PathExists) + `.service` | ❌ inotify pe sysfs nefiabil + ordering cycle din `After=thermald` pe `.path` |
| **v4** | **regula udev (ATTR write) + thermald reinit service** | ✅ **DOVEDIT empiric, implementat** |

### De ce v3 a eșuat (lecția cheie)

`.path` units folosesc **inotify**. **sysfs NU emite fiabil evenimente inotify de creare fișier** → `PathExists` se declanșa doar când fișierul exista deja la momentul pornirii `.path` (tot race). Plus `After=thermald.service` pe un `.path` unit a creat ordering cycle (`paths.target` e ordonat **înainte** de `basic.target`, iar thermald **după**) — systemd a rupt arbitrar un job:
```
basic.target: Found ordering cycle: thermald.service/stop after macbook-rapl.path/stop
  after paths.target/stop after basic.target/stop - after thermald.service
```

### Fix v4 — implementat

**`/etc/udev/rules.d/99-macbook-rapl.rules`**:
```
ACTION=="add", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:0", \
  ATTR{constraint_0_power_limit_uw}="22000000", \
  ATTR{constraint_1_power_limit_uw}="30000000", \
  TAG+="systemd", ENV{SYSTEMD_WANTS}+="macbook-rapl-thermald.service"
```

**`/etc/systemd/system/macbook-rapl-thermald.service`**:
```ini
[Unit]
Description=Reinit thermald after MacBook RAPL limits are set by udev
[Service]
Type=oneshot
ExecStart=/bin/systemctl try-restart thermald.service
RemainAfterExit=yes
```

De ce funcționează unde v1-v3 au eșuat:
- udev primește **uevent KERNEL real** la apariția device-ului powercap — fiabil, spre deosebire de inotify pe sysfs
- `ATTR{}=` scrie valorile **sincron cu add event**, zero race, pe orice kernel
- Fără `After=thermald` → fără ordering cycle (service-ul e tras de device via SYSTEMD_WANTS)
- `try-restart thermald` după ce RAPL e setat → thermald redescoperă RAPL

### Dovada empirică (test 28 mai 22:27, fără reboot)

```
PAS 5: reset RAPL la 100M/125M (simulez boot spart)
PAS 6: udevadm trigger --action=add /sys/class/powercap/intel-rapl:0
PAS 7: RAPL = 22M/30M  → SUCCESS (udev a re-aplicat automat)
PAS 8: macbook-rapl-thermald.service activated → try-restart thermald OK
       thermald PID nou (9474) NU mai logheaza "NO RAPL sysfs present"
```

### Alternative respinse

| Alternativă | De ce respinsă |
|---|---|
| `.path` unit (v3) | inotify pe sysfs nefiabil + ordering cycle |
| `ConditionPathExists` (v2) | race condition la evaluare |
| `tmpfiles.d` (v1) | suprascris de intel_rapl_msr |
| `Restart=on-failure` retry burst | hacky, risipă invocări failed |
| Force `intel_rapl_msr` în initramfs | overkill, fragil la upgrade kernel |
| udev RUN+= cu restart thermald direct | udev RUN nu trebuie să vorbească cu systemd (deadlock); SYSTEMD_WANTS e corect |

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
| RAPL v2/v3 (service/.path) | ❌ NU | race condition / inotify nefiabil pe sysfs |
| RAPL v4 (regula udev) | ✅ | udev fires pe uevent KERNEL real la fiecare boot, orice kernel |

**Răspuns final**: NU trebuie rerulat scriptul la kernel upgrade. Regula udev din `/etc/udev/rules.d/` persistă și se declanșează la fiecare apariție a device-ului powercap, indiferent de versiunea kernel. **Singurul rerun** a fost O DATĂ pentru migrarea v3 → v4.

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
✓ 1-4. Pass-uri analiza
✓ 5.   Confirmare empirica: thermald NU rescaneaza RAPL
✓ 6.   v3 (.path) implementat + commit — A ESUAT la reboot (race inotify + ordering cycle)
✓ 7.   v4 (udev) testat empiric pe sistem (udevadm trigger: 100M→22M, thermald OK)
✓ 8.   v4 implementat in script + README + TODO → commit + push
✓ 9.   Reboot test real (boot 22:36): RAPL = 22M/30M ✓, thermald restartat
       de reinit service la 22:36:16 → instanta noua (PID 1535) vede RAPL.
       FIX VALIDAT COMPLET la boot real (nu doar simulare udevadm trigger).

Nota verificare: `journalctl -u thermald -b 0 | grep "NO RAPL"` arata MEREU
2 linii (instanta pre-restart), chiar cand totul merge — instanta thermald
de dupa restart e cea care conteaza si aceea vede RAPL. Verificare corecta:
`journalctl -u thermald -u macbook-rapl-thermald.service -b 0 | tail -8`
→ reinit "Finished" urmat imediat de thermald "Started".

## STATUS: REZOLVAT — RAPL race condition fix complet (v4 udev), validat la boot real.
   11. (optional, alt commit) B1+B2 din catalog — GNOME gsettings cleanup
   12. (optional) README section "Boot log triage" — known benign issues
```

**După v4, kernel upgrade-urile viitoare NU mai necesită rerun** — regula udev persistă în `/etc/udev/rules.d/` și se declanșează la fiecare apariție a device-ului powercap, pe orice kernel.
