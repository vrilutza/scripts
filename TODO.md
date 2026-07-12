# TODO — îmbunătățiri opționale & teste

Hardware-ul de bază e **complet funcțional și stabil** pe Debian Testing/forky, kernel **7.1.3**
(single-kernel, din forky — verificat cap-coadă 11–12 iul 2026). Acest fișier ține doar ce **urmează**:
bug-ul de cameră (de raportat upstream), monitorizarea WiFi, opțiuni neimplementate (cu trade-off)
și referință. Istoricul problemelor deja rezolvate e condensat jos + în git history / README.

---

## 🔧 În lucru — Camera: GNOME Snapshot îngheață la primul cadru (bug upstream PipeWire + Snapshot)

**Diagnosticat complet 11 iul 2026** (NU e kernel, NU e driver, NU e regresie pipewire 1.6.8 —
diff-ul upstream 1.6.7→1.6.8 n-are schimbări de buffere): deadlock de buffer-starvation pe 3 straturi:

1. **facetimehd** limita V4L2 la 4 buffere (`FTHD_BUFFERS`) — **REPARAT local 11 iul**: patch 4→8 în
   `/usr/src/facetimehd-0.7.0.1` (`fthd_drv.h` + `fthd_v4l2.c`), DKMS rebuilt; ISP streamează 8
   buffere in-flight la 30.0 fps, 0 erori kernel. Driverul acordă acum 8 la cerere (re-verificat 12 iul).
2. **PipeWire** (spa v4l2) negociază oricum default **4** buffere (hardcodat în `v4l2-source.c`,
   indiferent cât suportă driverul), iar `pipewiresrc` aruncă **definitiv** frame-urile ne-reciclate
   („buffer was not recycled", fără copy-fallback) — de-aia patch-ul de driver singur nu deblochează Snapshot.
3. **Snapshot** ține ocupate simultan toate cele 4 buffere din pool (lanțul de afișare GL) →
   viewfinder blocat permanent pe primul cadru, înregistrări goale.

Empiric: client care ține 3 buffere = 30 fps la nesfârșit; ține 4 = fix 4 cadre apoi îngheț;
`min-buffers=8` pe driverul patch-uit = merge chiar ținând 7 (146 cadre/6s).
**Workaround până răspund upstream:** `guvcview` sau camera din Chrome (amândouă V4L2 direct, ocolesc PipeWire).

- [x] **Bug-urile upstream TRIMISE 12 iul 2026** (texte păstrate în repo):
      1) PipeWire — <https://gitlab.freedesktop.org/pipewire/pipewire/-/work_items/5363>
      ([ISSUE_camera_pipewire.md](ISSUE_camera_pipewire.md));
      2) Snapshot — <https://gitlab.gnome.org/GNOME/snapshot/-/work_items/367>
      ([ISSUE_camera_snapshot.md](ISSUE_camera_snapshot.md)). De urmărit răspunsurile dezvoltatorilor.
- [ ] **Înlocuiește placeholder-ele `LINK-...` în issue-urile live** (Edit description pe GitLab):
      în #367 (Snapshot) pune link-ul PipeWire de mai sus în locul `LINK-PIPEWIRE-ISSUE` (verificat
      12 iul: placeholder-ul e încă acolo); în #5363 (PipeWire) pune link-ul Snapshot în locul
      `LINK-SNAPSHOT-ISSUE`. Fișierele din repo au deja link-urile reale.
- [ ] **Adaugă patch-ul `FTHD_BUFFERS` 4→8 în script (ETAPA 4)** — acum trăiește doar în `/usr/src`
      și **se pierde la reinstalare** (scriptul re-clonează patjak/facetimehd). Două `sed`-uri + verificare.
- [ ] Opțional: **PR upstream patjak/facetimehd** (4→8; testat stabil, bugetul propriu de 16 MB al
      driverului ține 9 buffere la 720p) — de trimis după ce răspunde PipeWire.
- [ ] Opțional, secundar (descoperit pe parcurs): **wireplumber 0.5.15** crash Lua
      (`common-utils.lua:54`, `media.type` nil → „target not found") pt. stream-uri fără proprietatea
      `media.type` — lovește doar clienți sintetici, nu aplicații reale. Raportare doar dacă e chef.

---

## 🔧 Monitorizare — Stabilitate WiFi BCM4350 (kernel panic 7 iul 2026)

**Incident:** 7 iul 2026, 06:08 (pe 7.1.2, dar **nu** e regresie 7.1.x — apărea pe toate kernelele):
kernel panic `Fatal exception in interrupt`, capturat complet în **pstore EFI**. Lanțul:

1. `DMAR: [DMA Write] ... PTE Write access is not set` — chipul WiFi a încercat o scriere DMA
   interzisă; IOMMU (VT-d) a blocat-o;
2. `brcmf_msgbuf_get_pktid: Invalid packet id` — ring-ul firmware↔driver desincronizat;
3. skb corupt scăpat în stiva de rețea (125 fragmente / max 17, 2× UBSAN `skbuff.h:2543`);
4. GPF în `memcpy` în softirq → panic. Colateral: applespi mort imediat (-110).

**Cauza-rădăcină:** firmware-ul generic Broadcom (nov 2015), fără NVRAM/CLM Apple, se desincronizează
cronic de driver — înainte de mitigare: `Invalid packet id` de ~23 de ori între 20 mai și 8 iul
(~o dată la 1–3 zile). De obicei recuperare silențioasă; pe 7 iul corupția a ajuns în network stack.

**Mitigare aplicată (8 iul, live + ETAPA 5g în script):**

- [x] WiFi **power-save off** (persistent, `wifi.powersave = 2` în NetworkManager) — mai puține
      tranziții de stare în firmware; laptop mereu pe AC, cost zero.
- [x] **`kernel.panic = 10`** — reboot automat la 10s după panic în loc de freeze permanent.
- [x] IOMMU rămâne **pornit** — el a blocat scrierile DMA ilegale; `intel_iommu=off` le-ar transforma
      în corupere silențioasă de memorie.
- [x] ~~Fix definitiv = firmware Apple BCM4350 („faza 2")~~ — **investigat 8 iul, verdict: fișierele
      NU există nicăieri** (nici în macOS: pe Mac-urile non-T2 calibrarea stă în OTP-ul cipului, pe
      care brcmfmac îl citește deja, iar datele regulatorii sunt în firmware-ul Apple „bmac" —
      split-MAC, incompatibil brcmfmac). Impact real ~zero: toate canalele 5 GHz active (36–165),
      limitarea la 2,4 GHz vine de la router (SSID „vik" emite doar pe canalul 1). Mutat la won't-fix.

**Monitorizare (pasiv):**

- [ ] `journalctl -g 'Invalid packet id'` — **status 12 iul: ultimul eveniment 8 iul 06:50 (cu ~1h
      înainte de aplicarea mitigării); 0 evenimente în cele 4 zile de după**, față de ~1 la 1–3 zile
      înainte → mitigarea pare eficace. De re-verificat periodic; dacă vreodată redevine frecvent +
      panici: adaptor USB WiFi (~15 €).

---

## 🧹 De făcut — curățenie repo experimental (rămas de la testarea 7.1.x)

Kernelul vine acum din forky, dar fișierele repo-ului experimental **încă există** (verificat 12 iul).
Inofensive (pin scăzut), dar nu mai au rost:

```bash
sudo rm /etc/apt/sources.list.d/experimental.sources /etc/apt/sources.list.d/experimental.list.bak /etc/apt/preferences.d/experimental
sudo apt update
```

---

## 🟡 De evaluat — opțional, cu trade-off (neimplementate intenționat)

| Item | Ce ar rezolva | De ce nu (încă) |
|---|---|---|
| **DMAR I2C messages** | `DMAR: Failed to find handle ... I2C0/I2C2/UA00` (3×/boot) | fix = `intel_iommu=off`, dar dezactivează IOMMU (trade-off de securitate) — nu merită doar pt log |
| **BCM4350 BT baudrate + `.hcd`** | `failed to write update baudrate (-16)` + `BCM.hcd` lipsă la boot | cauza = ACPI Apple incomplet + firmware Apple ne-redistribuibil; BT merge oricum (vezi detaliu jos) |

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
| **Firmware Apple BCM4350 (WiFi/BT)** | Fișierele nu există public și nici în macOS pt. Mac-urile non-T2: calibrarea stă în OTP-ul cipului (citit deja de brcmfmac), datele regulatorii în firmware-ul Apple „bmac" (split-MAC, incompatibil brcmfmac). Investigat 8 iul 2026 — mesajele „failed to load ...MacBookPro14,1.*" rămân cosmetice. |
| **facetimehd PLL lock** | `Failed to lock S2 PLL` — bug upstream patjak/facetimehd; camera merge pe PLL alternativ. |
| **ASPM PCIe** | `can't disable ASPM` — Apple BIOS restricționează; `pcie_aspm=off` ar strica bateria. |
| **Apple ACPI / SGX noise** | `AE_ALREADY_EXISTS`, `_OSC/_PDC AE_NOT_FOUND`, SSDT duplicate, SGX disabled — Apple nu implementează metode ACPI standard / dezactivează SGX. Pur cosmetic. |

---

## ✅ Implementate în script (referință — 9 etape)

| # | Ce | Detaliu |
|---|---|---|
| 1-6 | Hardware base | deps (+rfkill, iw), audio CS8409, cameră FaceTime HD, GRUB/suspend fixes, **Bluetooth unblock+AutoEnable (5f)**, **WiFi stabilitate: power-save off + kernel.panic=10 (5g)**, **luminozitate fixă: auto-brightness ALS + idle-dim off (5h)**, VA-API |
| 7 | Touchpad UX | tap-to-click + natural scroll + disable-while-typing |
| 8 | Thermal | thermald + lm-sensors + RAPL PL1=22W/PL2=30W + fan floor 3500 RPM (oneshot service, race-safe) |
| 9 | Cosmetic / jurnal | GNOME media-keys (hibernate/playback-repeat) + usb-protection off + applespi fnmode=1 |

---

## 📒 Istoric rezolvat (arhivă scurtă — detalii în git history + README)

Probleme deja închise, păstrate doar ca rezumat (nu mai sunt de făcut):

- **Kernel 7.1.3 (forky) — upgrade complet, single-kernel** — 7.1.1/7.1.2 testate din experimental
  (22 iun → 11 iul, audit complet verde, zero regresii); `7.1.3-1` a intrat în forky și meta
  `linux-image-amd64` s-a reconciliat curat (`7.1.3-1` > `7.1.2-1~exp1`); kernelurile vechi (7.0.13,
  7.1.2~exp1) purjate complet (dpkg + /boot + /lib/modules + /usr/src). Verificat cap-coadă 11–12 iul:
  DKMS recompilate + semnate, 0 UBSAN/oops/DMAR-fault, toate driverele încărcate, accelerare 3D (GBM
  pe i915) + VA-API (iHD) funcționale. De-acum kernelul vine prin `apt dist-upgrade` normal.
- **Luminozitate „fantomă"** (12 iul) — ecranul se închidea/deschidea singur deși era setat la maxim:
  senzor ALS (`acpi-als`) + iio-sensor-proxy + GNOME „Automatic Screen Brightness"; percepția de
  culori calde/reci era tot backlight-ul (2017 n-are True Tone). Fix: **ETAPA 5h** (ambient-enabled
  + idle-dim off). Comenzi de toggle manual în README.
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
- **BT „nu merge deloc" (soft-block persistat)** — `systemd-rfkill` restaura la fiecare boot un rfkill
  soft-block salvat (de la un disable/enable din GUI). Dovedit **A/B** că `AutoEnable=true` singur NU-l
  învinge (restaurarea vine înaintea power-on-ului). Fix: oneshot `bluetooth-rfkill-unblock.service`
  (unblock ordonat între `systemd-rfkill` și `bluetooth`) + `AutoEnable=true`. **ETAPA 5f** + `rfkill` în deps.

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
| B | `brcmfmac: failed to load ...MacBookPro14,1.bin/.txt/.clm_blob` | ~8×/boot | caută variante Apple, cade pe generic (WiFi OK; fișierele nu există — vezi won't-fix) |
| C | `nvme0n2: partition table beyond EOD, truncated` | 1×/boot | al 2-lea namespace al NVMe-ului Apple (proprietar/gol); prezent pe toate kernelurile |
| C | `facetimehd: Failed to lock S2 PLL` | 1×/boot | bug upstream driver; camera merge pe PLL alt |
| C | `facetimehd: can't disable ASPM` | 1×/boot | Apple BIOS restricționează ASPM |
| C | `facetimehd: module verification failed - tainting kernel` | 1×/boot | DKMS nesemnat în keyring; benign fără Secure Boot |
| C | `hci_uart_bcm: Unexpected ACPI gpio_int_idx / No reset resource` | 3×/boot | Apple ACPI lipsuri; fallback OK |
| A | `gsd-media-keys: Failed to grab ... hibernate/playback-repeat` | 1×/login | rezolvat ETAPA 9 (keybinding golit) |
| A | `gsd-usb-protection: Failed to fetch USBGuard` | 2×/boot | rezolvat ETAPA 9 (usb-protection off) |
| C | `x86/cpu: SGX disabled or unsupported by BIOS` | 1×/boot | Apple BIOS dezactivează SGX |

**Concluzie**: zero crash/oops/UBSAN la un boot normal. Categoria A e deja curățată (ETAPA 9); restul
sunt Apple ACPI/firmware quirks inevitabile (C) sau cu trade-off nejustificat (B). Excepția rară (nu
per-boot): desincronizarea brcmfmac `Invalid packet id` — sub mitigare din 8 iul, vezi „Monitorizare" sus.
