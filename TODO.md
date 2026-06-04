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

**Cauză** (stack trace din jurnal pe boot 7.0.10):
```
cs8409_probe → snd_hda_gen_parse_auto_config → UBSAN array-index-out-of-bounds
  sound/hda/codecs/generic.c:3294   (index 18 pe auto_pin_cfg_item[18])
  sound/hda/common/auto_parser.c:579 (index 41 pe char*[36])
→ probe FAILED → cardul nu se înregistrează
```
Driverul CS8409 (DKMS davidjo/snd_hda_macbookpro) trimite o config de pini care depășește
limitele array-urilor din parser-ul HDA **in-tree**. Codul HDA in-tree s-a schimbat în 7.0.10
(sau UBSAN nou activat) → out-of-bounds-ul rupe înregistrarea cardului. **NU e bug în script.**

**Status fix**:
- Driver upstream: ultimul commit 2026-05-05 (cb27cc4) — **fără fix** pentru 7.0.10. Rerun script NU ajută.
- Diferit de regresia RAPL: aici e cod **in-tree kernel** + driver OOT, nu config-ul nostru.

**Workaround imediat**: boot kernel 7.0.9 din GRUB → Advanced options (încă instalat, audio OK).

**De urmărit**:
- [ ] Kernel 7.0.11 — posibil fix in-tree HDA (verifică UBSAN dispare)
- [ ] Commit nou pe davidjo/snd_hda_macbookpro care patch-uiește pin config pt 7.0.10
- [ ] Eventual: raportează issue upstream cu stack trace-ul de mai sus
- [ ] Decizie: `apt-mark hold linux-image-amd64` la 7.0.9 până apare fix? (sau GRUB default pe 7.0.9)

Clasificare: regresie kernel↔driver, **temporară**, workaround = boot 7.0.9. Nu necesită schimbare în script.

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
