# TODO — îmbunătățiri opționale

Hardware-ul de bază e **complet funcțional și stabil** (testat pe Debian Testing, kernel 7.0.9,
mai 2026). Ce urmează aici sunt opționale, organizate pe categorii ca să poți decide ce merită.

---

## ✅ Implementate (în script)

| # | Ce | Detaliu |
|---|---|---|
| 1-6 | Hardware base | deps, audio CS8409, camera FaceTime HD, GRUB/suspend fixes, VA-API |
| 7 | Touchpad UX | tap-to-click + natural scroll + disable-while-typing |
| 8 | Thermal management | thermald + lm-sensors + RAPL PL1=22W/PL2=30W |

**RAPL race condition — REZOLVAT.** A trecut prin 4 iterații (tmpfiles → ConditionPathExists →
.path unit → **udev rule**). Versiunea finală (regula udev + thermald reinit) validată **8/8
boot-uri** la 22M/30M. Detaliile tehnice complete sunt în istoricul git (commits `2870454`,
`3f0419e`, `af0b850`) și în README secțiunea "Why a udev rule".

---

## ⚠️ REGRESIE ACTIVĂ — Audio rupt pe kernel 7.0.10 (din 4 iunie 2026)

**Simptom**: pe kernel `7.0.10+deb14-amd64`, niciun sound card (`/proc/asound/cards` = "no soundcards",
`/dev/snd/` doar seq+timer). Pe `7.0.9` audio funcționează perfect.

**Cauză exactă (debugging complet pe sistem real, 4 iunie):**

Stack trace pe boot 7.0.10:
```
cs8409.c:32  snd_hda_gen_parse_auto_config(codec, &spec->gen.autocfg)
  → hda_get_autocfg_input_label (auto_parser.c:579,582,583,588,589)
  → snd_hda_gen_parse_auto_config (generic.c:3294,3304,3305,3311,3312)
  → UBSAN array-index-out-of-bounds → probe FAILED → niciun card
```

UBSAN raportează indici **garbage** pe array-uri fixe:
- `index 18, 40, 41, 42` pe `auto_pin_cfg_item inputs[18]` (AUTO_CFG_MAX_INS=18 în kernel 7.0.10)
- `index 40, 41, 223` pe `char *[36]` (input labels) și `int [36]`

**Root cause** — confirmat din sursa driverului (`patch_cirrus/cirrus_apple.h:1860`):
```
// as of 5.13 the definition of AUTO_CFG_MAX_INS has been increased to handle the 8409
// so we need to hack this code because we have more adcs than AUTO_CFG_MAX_INS
// adcs (8) - actual number is 18
```
Driverul CS8409 are **mai multe ADC-uri/input pins decât AUTO_CFG_MAX_INS (18)** și setează
intenționat `cfg->num_inputs` peste limita array-ului `inputs[18]`. Parser-ul HDA **in-tree**
iterează `for (i=0; i < cfg->num_inputs; i++) cfg->inputs[i]` → accesează `inputs[18..42]` și
calculează indici de label garbage (223) din memorie de după array. Acest "hack" a fost tolerat
până la 7.0.10, când **UBSAN array-bounds checking** (nou activat în config-ul Debian) îl prinde
ȘI accesul out-of-bounds rupe înregistrarea cardului.

**Clasificare reală**: bug în **driver** (hack-ul care depășește AUTO_CFG_MAX_INS), latent ani de
zile, expus de UBSAN-ul mai strict din kernel 7.0.10. NU e config-ul nostru, NU e bug script.

**Fix posibil din 2 direcții**:
1. **Driver** (davidjo/snd_hda_macbookpro): să nu mai depășească `cfg->num_inputs > AUTO_CFG_MAX_INS`
   — fix-ul corect. Upstream ultimul commit 2026-05-05, fără el încă.
2. **Kernel**: AUTO_CFG_MAX_INS crescut peste 18, SAU UBSAN bounds dezactivat (improbabil/nedorit).

**Workaround imediat**: boot 7.0.9 din GRUB → Advanced options (audio OK, 0 UBSAN).

**Testare kerneluri noi (răspuns la întrebarea: merită 7.0.11 / experimental?)**:
- Multi-kernel în paralel e SIGUR — Debian păstrează mai multe `linux-image-*`, GRUB le listează pe toate. Zero risc să ai 7.0.9 + 7.0.10 + 7.0.11 simultan.
- DAR: fix-ul e **driver-side**. Un kernel mai nou repară audio DOAR dacă întâmplător crește
  AUTO_CFG_MAX_INS sau relaxează bounds — nu garantat. 7.0.11 cu același AUTO_CFG_MAX_INS=18 +
  UBSAN va rupe audio la fel. Merită testat, dar nu te baza pe el ca soluție.
- Sursă kernel mai nou: Debian `experimental`/`unstable`, sau build din kernel.org.

**Pentru issue upstream** — include: kernel 7.0.10 cu UBSAN bounds, driver commit cb27cc4,
hardware MacBookPro14,1, stack trace de mai sus, și citatul din cirrus_apple.h:1860 (hack-ul
AUTO_CFG_MAX_INS). Întrebare cheie pt mainaineri: cum să gestioneze >18 ADC pins fără overflow
acum că UBSAN prinde accesul.

**De urmărit**:
- [ ] Issue/PR pe davidjo/snd_hda_macbookpro cu root cause-ul de mai sus
- [ ] Kernel 7.0.11 când intră în Debian — testează dacă UBSAN dispare (probabil NU)
- [ ] Decizie: GRUB default pe 7.0.9 până apare fix driver? (reversibil, recomandabil)

---

## 🔵 Bluetooth DOWN după upgrade 7.0.10 — clarificare (NU e 7.0.10)

User a observat BT mort după reboot-ul de upgrade la 7.0.10, deși mergea înainte. Comparație jurnal:

| Boot | Kernel | BT init | Rezultat |
|---|---|---|---|
| -2 (2 iun) | 7.0.9 | `baudrate (-16)` EBUSY, dar apoi `BCM4350C0 build 1532` | ✅ BT OK |
| 0 (4 iun) | 7.0.10 | `0xfc18 tx timeout`, `baudrate (-110)`, `Reset failed (-110)` | ❌ BT DOWN |

Diferența `-16` (busy, cip răspunde) vs `-110` (timeout, cip mut) = **starea cip-ului Broadcom după
warm reboot**, NU kernelul. Upgrade-ul a necesitat un reboot → exact ce declanșează starea proastă
Broadcom (vezi secțiunea Broadcom warm-reboot din Categoria C). **NU e regresie 7.0.10.**

**Test de confirmare** (pentru a fi 100% siguri): `shutdown -h now` complet → pornire → boot 7.0.10.
Dacă BT revine `UP RUNNING` pe 7.0.10 după power-off → confirmat warm-reboot, nu kernel. (Dacă
rămâne mort și după power-off curat pe 7.0.10 → atunci ar fi regresie kernel, investigăm separat.)

---

## 🟢 Categoria A — Cosmetic / curățire log (risc zero, win mic)

Toate sunt gsettings sau parametri kernel. Zero risc, dar și impact mic. Bune de făcut împreună
într-un commit dacă vrei jurnal curat.

| Item | Ce face | Fix |
|---|---|---|
| **applespi fnmode** | F1-F12 ca media keys (curent) vs F-keys reale | `options applespi fnmode=2` în `/etc/modprobe.d/` + update-initramfs (MacBook 2017 = driver `applespi`, NU `hid_apple`) |
| **GNOME hibernate keybinding** | scoate eroarea `gsd-media-keys: Failed to grab ... hibernate` din log | `gsettings set org.gnome.settings-daemon.plugins.media-keys hibernate "[]"` |
| **GNOME usb-protection** | scoate eroarea `gsd-usb-protection: Failed to fetch USBGuard` | `gsettings set org.gnome.desktop.privacy usb-protection false` |

## 🟡 Categoria B — Posibil util, dar complex sau cu trade-off (de evaluat caz cu caz)

| Item | Ce ar rezolva | De ce e dificil |
|---|---|---|
| **DMAR I2C messages** | `DMAR: Failed to find handle ... I2C0/I2C2/UA00` (3×/boot) | fix = `intel_iommu=off` în GRUB, dar **dezactivează IOMMU** (security trade-off) — nu merită doar pt log |
| **BCM4350 BT baudrate** | `failed to write update baudrate (-16)` la boot | workaround custom complex; BT funcționează oricum la 115200 |
| **Apple WiFi/BT firmware** | `brcmfmac: failed to load ...Apple Inc.-MacBookPro14,1.bin` (extragere nvram/CLM din macOS) | **risc legal** de redistribuire; generic firmware merge OK |

## 🔴 Categoria C — Limitări hardware MacBook (FĂRĂ fix software posibil)

Acestea **nu pot fi reparate** — sunt limitări fizice ale hardware-ului Apple sau bug-uri upstream.
Documentate ca să nu pierdem timp încercând.

| Item | De ce nu se poate |
|---|---|
| **Suspend S3 / hibernare** | S3 nu se trezește fiabil pe NVMe+EFI Apple (deja dezactivat by design în ETAPA 5). Hibernarea (suspend-to-disk) ar necesita swap ≥ RAM + ar moșteni aceleași probleme de resume Apple — nefiabil. |
| **Broadcom WiFi/BT la warm reboot** | `sudo reboot` nu power-cycle-ază cip-ul Broadcom → poate rămâne mut (`MMIO read failed` / `Reset failed -110`). Recuperare = power-off complet, nu reboot. Hardware, nu software. |
| **facetimehd PLL lock** | `Failed to lock S2 PLL` — bug în driverul upstream patjak/facetimehd; camera merge pe PLL alternativ. Fără workaround user-side. |
| **ASPM PCIe** | `can't disable ASPM` — Apple BIOS restricționează; `pcie_aspm=off` ar strica bateria. Trade-off rău. |
| **Apple ACPI noise** | `AE_ALREADY_EXISTS`, `_OSC/_PDC AE_NOT_FOUND`, SSDT duplicate — Apple nu implementează metode ACPI standard. Kernel-ul folosește fallback-uri. Pur cosmetic. |
| **Intel SGX disabled** | dezactivat în Apple BIOS, irelevant pe MacBook |

---

## Anexă — catalog complet "log noise" (referință)

Pentru fiecare boot apar ~40 mesaje "error/warning". Toate sunt clasificate mai sus în categoriile
A/B/C. Tabel complet de referință, cu frecvențe și cauze:

| Cat | Mesaj jurnal | Frecvență | Cauza reală |
|---|---|---|---|
| 🔴C | `ACPI Error: AE_ALREADY_EXISTS, SSDT Table is already loaded` | 19×/boot | Apple SSDT-uri duplicate; kernel ignoră al doilea |
| 🔴C | `ACPI Error: Aborting method \_PR.CPU*._OSC/PDC/GCAP/APPT` | ~10×/boot | Apple nu implementează metode ACPI standard |
| 🔴C | `ACPI BIOS Error: Could not resolve symbol [\_SB.OSCP]` | 2×/boot | Apple nu expune `_OSC` global |
| 🟡B | `DMAR: Failed to find handle ... I2C0/I2C2/UA00` | 3×/boot | Apple I2C ACPI paths non-standard pt VT-d |
| 🟡B | `Bluetooth: hci0: BCM: failed to write update baudrate (-16)` | 1×/boot | BCM4350 refuză upgrade baud; rămâne 115200 OK |
| 🟡B | `Bluetooth: hci0: BCM: firmware Patch file not found 'brcm/BCM.hcd'` | 1×/boot | firmware patch opțional, nu există în Debian |
| 🟡B | `brcmfmac: failed to load ...Apple Inc.-MacBookPro14,1.bin/.txt/.clm_blob` | 7×/boot | caută variante Apple, cade pe generic (OK) |
| 🔴C | `facetimehd: Failed to lock S2 PLL: 0xc902c902` | 1×/boot | bug upstream driver; camera merge pe PLL alt |
| 🔴C | `facetimehd: can't disable ASPM` | 1×/boot | Apple BIOS restricționează ASPM |
| 🔴C | `facetimehd: module verification failed - tainting kernel` | 1×/boot | DKMS nesemnat; benign fără Secure Boot |
| 🔴C | `snd_hda_intel: Primary patch_cs8409 NOT FOUND trying APPLE` | 1×/boot | fallback intended al driver-ului OOT |
| 🔴C | `hci_uart_bcm: Unexpected ACPI gpio_int_idx / No reset resource` | 3×/boot | Apple ACPI lipsuri; fallback OK |
| 🟢A | `gsd-media-keys: Failed to grab ... hibernate` | 1×/login | GNOME bind hibernate, dar logind dezactivat |
| 🟢A | `gsd-usb-protection: Failed to fetch USBGuard` | 2×/boot | USBGuard neinstalat |
| 🔴C | `wireplumber: Failed to get percentage from UPower` | 1×/boot | race normal init, se repară singur |
| 🔴C | `xdg-desktop-portal-gnome / gsd-xsettings: Failed to ...` | 2×/login | GNOME portal/X11 cosmetic |
| 🔴C | `kernel: x86/cpu: SGX disabled or unsupported by BIOS` | 1×/boot | Apple BIOS dezactivează SGX |

**Concluzie**: din ~17 categorii distincte de log noise, doar **2 (categoria A) merită curățate**
fără trade-off (GNOME gsettings). Restul sunt fie Apple ACPI/firmware quirks inevitabile (C), fie
au trade-off care nu se justifică (B).
