# TODO — îmbunătățiri opționale & teste

Hardware-ul de bază e **complet funcțional și stabil** pe Debian Testing/forky, kernel **7.0.12**
(iunie 2026 — inclusiv audio). Acest fișier ține doar ce **urmează**: testul kernelului 7.1, opțiuni
încă neimplementate (cu trade-off) și referință. Istoricul problemelor deja rezolvate e condensat jos
+ în git history / README.

---

## 🧪 În testare — Kernel 7.1.2 (experimental) — instalat 29 iun 2026

Instalat `linux-image-7.1-amd64 = 7.1.2-1~exp1` din **experimental**, **lângă** 7.0.12 (care rămâne
default de fallback în GRUB). 7.1.1 a mers fără probleme ~1 săptămână (22→29 iun); 7.1.2 e point release
de bugfix peste el — același slot ABI `7.1-amd64`, deci **a suprascris 7.1.1, fără intrare GRUB nouă**.
Îl țin în continuare **în teste cel puțin 1 săptămână** de uz real — fiind din experimental, nu-l bag în script.

> Context: seria 7.0 e EOL upstream; forky (testing) a urcat la `7.0.13`, dar 7.1 e încă doar în
> experimental. Când 7.1.x ajunge în forky, `~exp1` se reconciliază curat (`7.1.x-1` > `7.1.x-1~exp1`).

**Audit live pe `7.1.2` / `7.1-amd64` (29 iun) — TOT verde:**

| Verificare | Rezultat |
|---|---|
| DKMS | `facetimehd` + `snd_hda_macbookpro` recompilate **și semnate** pe 7.1 ("Autoinstall succeeded") |
| Audio | card 0 `Cirrus Logic CS8409/CS42L83`, `pcm0c`+`pcm0p`, `cs8409` încărcat, **0 UBSAN** (pe 1224 linii log real) |
| Cameră | `facetimehd` încărcat, `/dev/video0` prezent |
| WiFi | `wlp2s0` **connected** (IP 192.168.1.2), firmware BCM4350 încărcat OK |
| Drivere | toate cheie încărcate (i915, applespi, applesmc, intel_lpss, nvme, thunderbolt, btbcm…); **0** device PCI fără driver; **0** module eșuate |
| Thermal | RAPL `22W/30W`, `thermald` active, `fan1_min=3500` (`macbook-fan-floor.service` active) |
| Suspend | 4/4 target-uri `masked` |
| Zgomot log | identic cu 7.0.12 (firmware-probe brcmfmac → cade pe generic, BT `BCM.hcd` lipsă, Apple ACPI/SGX/DMAR). **Nicio regresie nouă.** |

> Taint `12352` = out-of-tree (module DKMS) + unsigned (cheia MOK ne-enrolled, Secure Boot off) +
> user → **benign**, la fel ca pe orice kernel pe acest hardware.

**De făcut / de decis după ~1 săptămână de teste:**

- [ ] Uz real: sunet (căști + boxe + mic), cameră, termic sub load, **baterie/idle**, câteva reboot-uri.
- [ ] **NU rula `apt autoremove`** cât testezi — meta `linux-image-amd64` a urcat la `7.1.2-1~exp1`,
      deci 7.0.12 ar putea deveni eligibil de ștergere. Păstrează-l ca fallback până ești convins.
      (Recomandat: `apt-mark manual linux-image-7.0.12+deb14.1-amd64 linux-headers-7.0.12+deb14.1-amd64`.)
- [ ] Dacă stabil → decide dacă 7.1 rămâne standard. Când `7.1.x` ajunge în **forky** (testing), meta
      se reconciliază curat (`7.1.x-1` > `7.1.x-1~exp1`, upgrade normal) și se aliniază cu scriptul.
- [ ] Dacă apare ceva → reboot, alegi `7.0.12` din GRUB (Advanced options); nimic de dezinstalat.

**Scriptul rămâne țintit pe kernelul din forky (acum `7.0.13`)** până 7.1 migrează în forky.

---

## 🟡 De evaluat — opțional, cu trade-off (neimplementate intenționat)

Lucruri care s-ar *putea* face, dar nu se justifică acum. Aici stă „viitorul" real al proiectului.

| Item | Ce ar rezolva | De ce nu (încă) |
|---|---|---|
| **DMAR I2C messages** | `DMAR: Failed to find handle ... I2C0/I2C2/UA00` (3×/boot) | fix = `intel_iommu=off`, dar dezactivează IOMMU (trade-off de securitate) — nu merită doar pt log |
| **BCM4350 BT baudrate + `.hcd`** | `failed to write update baudrate (-16)` + `BCM.hcd` lipsă la boot | cauza = ACPI Apple incomplet + firmware Apple ne-redistribuibil; BT merge oricum (vezi detaliu jos) |
| **Apple WiFi/BT firmware** | mesajele `brcmfmac: failed to load ...MacBookPro14,1.bin/.txt/.clm_blob` | nvram/CLM trebuie extras din macOS → risc legal de redistribuire; firmware generic merge OK |

**Detaliu — Bluetooth BCM4350 (cele 2 mesaje err de la fiecare boot, ambele benigne):**

Cip combo WiFi+BT Broadcom **BCM4350C0**; partea BT e atașată pe **UART** (serial, nu USB), driver
`hci_uart` + `btbcm`. Live: controllerul e `Powered: yes`, stack-ul BNEP/MGMT/RFCOMM urcă normal.

- `BCM: failed to write update baudrate (-16)` → `Failed to set baudrate`. La init, `btbcm` încearcă să
  urce viteza UART de la default (115200) la una mai mare, printr-o comandă HCI vendor Broadcom, apoi
  reconfigurează UART-ul gazdă să se potrivească. Pe Apple, ACPI nu descrie complet device-ul
  (`hci_uart_bcm: Unexpected ACPI gpio_int_idx: -1` / `No reset resource, using default baud rate`),
  deci reconfigurarea nu se poate aplica → `-16` = **`-EBUSY`** → **rămâne pe 115200**. BT funcționează;
  115200 e destul pt mouse/tastatură/căști (A2DP ok). Doar throughput-ul maxim teoretic ar fi limitat —
  imperceptibil în uz.
- `firmware: failed to load brcm/BCM.hcd (-2)` → `Patch file not found`. Broadcom poate încărca un patch
  firmware **opțional** (`.hcd`, „patch RAM") care aplică fix-uri peste ROM-ul controllerului. Debian
  (`firmware-brcm80211`) **nu** livrează `.hcd`-ul Apple (blob distribuit de Apple, extractibil din macOS,
  **ne-redistribuibil legal** — exact ca nvram/clm_blob de pe partea WiFi). `-2` = `-ENOENT` (fișier lipsă);
  fără el, `btbcm` **continuă pe ROM-ul built-in**, complet funcțional.

Ambele au aceeași rădăcină ca `brcmfmac: failed to load ...MacBookPro14,1.*` de pe WiFi: Apple ține
firmware/calibrare custom în macOS, Linux cade pe generic/ROM și merge. Fix-ul „curat" ar cere extras
blob-urile din macOS (risc legal) pt 2 linii de log — nejustificat. **Altă** poveste (nu asta) e BT mut
după *warm reboot* — cipul nu e power-cycle-at → vezi secțiunea won't-fix.

---

## 🔴 Limitări hardware MacBook — won't-fix (referință, ca să nu pierdem timp)

| Item | De ce nu se poate |
|---|---|
| **Suspend S3 / hibernare** | S3 nu se trezește fiabil pe NVMe+EFI Apple → blocat via `systemctl mask` pe sleep targets (ETAPA 5e). Hibernarea ar moșteni aceleași probleme de resume. Detalii în README. |
| **Broadcom WiFi/BT la warm reboot** | `reboot` nu power-cycle-ază cip-ul → poate rămâne mut (`Reset failed -110`). Recuperare = power-off complet. Hardware. |
| **facetimehd PLL lock** | `Failed to lock S2 PLL` — bug upstream patjak/facetimehd; camera merge pe PLL alternativ. |
| **ASPM PCIe** | `can't disable ASPM` — Apple BIOS restricționează; `pcie_aspm=off` ar strica bateria. |
| **Apple ACPI / SGX noise** | `AE_ALREADY_EXISTS`, `_OSC/_PDC AE_NOT_FOUND`, SSDT duplicate, SGX disabled — Apple nu implementează metode ACPI standard / dezactivează SGX. Pur cosmetic. |

---

## ✅ Implementate în script (referință — 9 etape)

| # | Ce | Detaliu |
|---|---|---|
| 1-6 | Hardware base | deps, audio CS8409, cameră FaceTime HD, GRUB/suspend fixes, VA-API |
| 7 | Touchpad UX | tap-to-click + natural scroll + disable-while-typing |
| 8 | Thermal | thermald + lm-sensors + RAPL PL1=22W/PL2=30W + fan floor 3500 RPM (oneshot service, race-safe) |
| 9 | Cosmetic / jurnal | GNOME media-keys (hibernate/playback-repeat) + usb-protection off + applespi fnmode=1 |

---

## 📒 Istoric rezolvat (arhivă scurtă — detalii în git history + README)

Probleme deja închise, păstrate doar ca rezumat (nu mai sunt de făcut):

- **Audio rupt pe 7.0.10** — regresie in-tree în parser-ul HDA (UBSAN array-index-out-of-bounds →
  card nereg.), **exclusiv** pe 7.0.10. Reparat upstream în **7.0.12** (0 UBSAN); 7.0.10 dezinstalat.
  Driverul davidjo n-a avut nevoie de patch (bug 100% in-tree). Analiza completă + stack trace:
  git history + fostul `ISSUE_audio_kernel_7.0.10.md` (șters după rezolvare).
- **Fan floor `fan1_min=3500`** — udev scria ATTR înainte ca applesmc să expună atributul (race) →
  înlocuit cu oneshot `macbook-fan-floor.service` care așteaptă atributul. Verificat la reboot.
- **RAPL 22W/30W** — race rezolvat după 4 iterații (final: regulă udev + thermald reinit), validat 8/8 boot-uri.
- **Reboot hang** — `reboot=pci` în GRUB (ETAPA 5a), testat.
- **Suspend hang S3** — toate sleep targets `masked` (ETAPA 5e), 4/4 confirmat.
- **`udevadm settle` hang pe 7.0.10** — bound `--timeout=5` (ETAPA 8b); era efect al bug-ului audio.
- **BT „down" după upgrade 7.0.10** — era stare Broadcom după warm-reboot, **nu** kernel (vezi won't-fix).

---

## Anexă — catalog "log noise" per boot (referință)

Pentru fiecare boot apar ~40 mesaje "error/warning", toate benigne și clasificate mai sus:

| Cat | Mesaj jurnal | Frecvență | Cauza reală |
|---|---|---|---|
| C | `ACPI Error: AE_ALREADY_EXISTS, SSDT already loaded` | 19×/boot | Apple SSDT-uri duplicate; kernel ignoră al doilea |
| C | `ACPI Error: Aborting method \_PR.CPU*._OSC/PDC/GCAP/APPT` | ~10×/boot | Apple nu implementează metode ACPI standard |
| C | `ACPI BIOS Error: Could not resolve symbol [\_SB.OSCP]` | 2×/boot | Apple nu expune `_OSC` global |
| B | `DMAR: Failed to find handle ... I2C0/I2C2/UA00` | 3×/boot | Apple I2C ACPI paths non-standard pt VT-d |
| B | `Bluetooth: hci0: BCM: failed to write update baudrate (-16)` | 1×/boot | BCM4350 refuză upgrade baud; rămâne 115200 OK |
| B | `Bluetooth: hci0: BCM: firmware Patch file not found 'brcm/BCM.hcd'` | 1×/boot | firmware patch opțional, nu există în Debian |
| B | `brcmfmac: failed to load ...MacBookPro14,1.bin/.txt/.clm_blob` | ~8×/boot | caută variante Apple, cade pe generic (WiFi OK) |
| C | `facetimehd: Failed to lock S2 PLL` | 1×/boot | bug upstream driver; camera merge pe PLL alt |
| C | `facetimehd: can't disable ASPM` | 1×/boot | Apple BIOS restricționează ASPM |
| C | `facetimehd: module verification failed - tainting kernel` | 1×/boot | DKMS nesemnat în keyring; benign fără Secure Boot |
| C | `hci_uart_bcm: Unexpected ACPI gpio_int_idx / No reset resource` | 3×/boot | Apple ACPI lipsuri; fallback OK |
| A | `gsd-media-keys: Failed to grab ... hibernate/playback-repeat` | 1×/login | rezolvat ETAPA 9 (keybinding golit) |
| A | `gsd-usb-protection: Failed to fetch USBGuard` | 2×/boot | rezolvat ETAPA 9 (usb-protection off) |
| C | `x86/cpu: SGX disabled or unsupported by BIOS` | 1×/boot | Apple BIOS dezactivează SGX |

**Concluzie**: zero crash/oops/UBSAN. Categoria A e deja curățată (ETAPA 9); restul sunt Apple
ACPI/firmware quirks inevitabile (C) sau cu trade-off nejustificat (B).
