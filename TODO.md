# TODO — îmbunătățiri opționale

Hardware-ul de bază e **complet funcțional și stabil** (testat pe Debian Testing/forky, kernel
**7.0.12**, iunie 2026 — inclusiv audio, după ce regresia din 7.0.10 a fost reparată upstream).
Ce urmează aici sunt opționale, organizate pe categorii ca să poți decide ce merită.

---

## 🔎 Audit jurnal — 19 iunie 2026 (upgrade 7.0.12, audio REPARAT)

Re-analiză completă a logurilor pe sistemul real, acum pe **`7.0.12+deb14.1-amd64`** (forky). Sumar:

- **AUDIO REPARAT ✅** — regresia in-tree din 7.0.10 a dispărut în 7.0.12. Verificat live: card 0 =
  `Cirrus Logic CS8409/CS42L83`, `pcmC0D0c/p` prezent, **0 erori UBSAN**. Dovadă decisivă din scanarea
  **tuturor** boot-urilor păstrate: fiecare boot pe 7.0.10 = 30 linii UBSAN (10 rapoarte → card rupt),
  fiecare boot pe 7.0.9 = 0, fiecare pe 7.0.7 = 0, boot-ul pe 7.0.12 = 0. Bug-ul a fost **exclusiv**
  7.0.10 și e reparat upstream. Driverul davidjo n-a avut nevoie de modificare (cum am documentat).
- **Kernel 7.0.10 dezinstalat** — devenise „automatically installed, no longer required" după ce meta
  `linux-image-amd64` a trecut la 7.0.12 → `autoremove` l-a scos. A rămas `7.0.9` (instalat **manual**,
  rezervă) + `7.0.12` (curent). DKMS a recompilat curat `snd_hda_macbookpro` + `facetimehd` pe 7.0.12.
- **Restul fix-urilor — toate active pe 7.0.12** (verificat live): fan floor `fan1_min=3500` (service
  `active SUCCESS`), RAPL `22W/30W`, suspend mask (4/4 `masked`), `reboot=pci`.
- **Zgomot rămas**: doar Categoria A (GNOME `hibernate`/`playback-repeat`, `usb-protection/USBGuard`) +
  catalogul Apple ACPI/firmware din Anexă. Zero crash/oops/UBSAN.

---

## 🔎 Audit jurnal — 13 iunie 2026 (ce s-a schimbat din 7 iun)

Re-analiză completă a logurilor (kernel + userspace) pe sistemul real, rulând pe **7.0.9** (kernelul
audio-OK). Sumar:

- **Problemă găsită ȘI REZOLVATĂ (14 iun)**: fan floor-ul (ETAPA 8c) nu se aplica la boot (regula udev
  dădea race pe `fan1_min`). Reparat cu un oneshot service care așteaptă atributul — verificat la reboot
  (`fan1_min=3500`, fără „Could not chase"). Detalii în secțiunea "Implementate" de mai jos (marcată ✅).
  Restul thermal e OK: RAPL **22W/30W activ** și verificat, thermald + macbook-rapl-thermald active.
- **GNOME 49 → 50.2** (upgrade 13 iun): sesiune OK, fără regresie funcțională. Cosmetic nou:
  `gsd-media-keys: Failed to grab accelerator ... playback-repeat` (pe lângă `hibernate` deja
  documentat) — același tip de zgomot benign Categoria A.
- **`firmware-brcm80211` 20260410 → 20260519** (upgrade 11 iun): **fără schimbare de comportament** BT —
  `BCM.hcd` tot lipsește, baudrate tot `-16` (EBUSY = chip răspunde = BT OK). Rămâne Categoria B.
- **Audio**: perfect pe 7.0.9 (card 0 CS8409/CS42L83). 7.0.10 rămâne instalat (audio rupt — neschimbat).
- **Suspend mask (ETAPA 5e)**: ✅ acum APLICAT (toate 4 target-urile `masked`).
- **Igienă sistem**: zero pachete half-configured (cleanup 7.1-rc5 complet), zero crash/oops/segfault
  în boot-ul curent. Restul zgomotului de log = identic cu catalogul din Anexă (Apple ACPI/DMAR/SGX).

---

## ✅ Implementate (în script)

| # | Ce | Detaliu |
|---|---|---|
| 1-6 | Hardware base | deps, audio CS8409, camera FaceTime HD, GRUB/suspend fixes, VA-API |
| 7 | Touchpad UX | tap-to-click + natural scroll + disable-while-typing |
| 8 | Thermal management | thermald + lm-sensors + RAPL PL1=22W/PL2=30W + fan floor 3500 RPM |

**✅ Fan floor (`fan1_min=3500`) — REZOLVAT (14 iun). Race-ul udev înlocuit cu un oneshot service.**
Intenție (ETAPA 8c, 7 iun): curba SMC stock ține fan-ul la ~1200 RPM chiar la 80°C (silence-first);
ridicăm podeaua la 3500 via udev (`99-macbook-fan.rules`), `fan1_manual` rămâne 0 → SMC ramp automat
peste podea intact.

**PROBLEMĂ (100% confirmată pe sistemul real, 13 iun)**: regula scrie `ATTR{fan1_min}="3500"` pe
evenimentul `add` al platform device-ului `applesmc.768`, dar atributul `fan1_min` **nu există încă**
în acel moment (applesmc îl creează mai târziu, la înregistrarea hwmon din probe). Jurnal boot:
```
(udev-worker): applesmc.768: /etc/udev/rules.d/99-macbook-fan.rules:5 ATTR{fan1_min}="3500":
  Could not chase sysfs attribute ".../applesmc.768/fan1_min", ignoring: No such file or directory
```
Rezultat: `fan1_min` rămâne **1200** (stock) la fiecare boot — verificat live (`cat fan1_min` = 1200)
+ eroarea apare pe **7/7** boot-uri unde regula e logată; niciodată nu reușește. Exact aceeași clasă
de race ca RAPL v1 (ATTR scris înainte ca device-ul să fie gata) — dar regula RAPL **reușește** pentru
că device-ul `powercap intel-rapl:0` expune atributele sincron la `add`, pe când applesmc nu.

Testul "live" din `fantest.md` (idle 80→74°C, ramp 3500→5400) a fost cu `fan1_min` setat **manual**,
apoi revert — deci dovedește că hardware-ul acceptă floor-ul, NU că udev-ul îl aplică la boot. De aceea
afirmația inițială "activ/testat" era greșită: floor-ul nu a fost niciodată persistent la boot.

**Fix aplicat + VERIFICAT la reboot (14 iun)**: floor-ul se aplică acum printr-un oneshot service
(modelul dovedit de la RAPL). Regula udev `99-macbook-fan.rules` doar **declanșează** serviciul
(`TAG+="systemd", ENV{SYSTEMD_WANTS}+="macbook-fan-floor.service"`); serviciul rulează helper-ul
`/usr/local/sbin/macbook-fan-floor`, care **așteaptă** până apare `fan1_min` (max 5s), apoi scrie 3500.
Pornit și de udev (devreme), și de `multi-user.target` (rezervă). Implementat în ETAPA 8c din script.
Dovadă post-reboot pe sistemul real: `fan1_min=3500` live, `fan1_manual=0` (curba SMC intactă), service
`active (exited) SUCCESS` pornit la boot, **zero** „Could not chase" în jurnal. Reversibil: dezactivează
serviciul + `fan1_min=1200`. Explicație thermal completă în README.

**RAPL race condition — REZOLVAT.** A trecut prin 4 iterații (tmpfiles → ConditionPathExists →
.path unit → **udev rule**). Versiunea finală (regula udev + thermald reinit) validată **8/8
boot-uri** la 22M/30M. Detaliile tehnice complete sunt în istoricul git (commits `2870454`,
`3f0419e`, `af0b850`) și în README secțiunea "Why a udev rule".

---

## ✅ REZOLVAT — Audio rupt pe kernel 7.0.10 (regresie 4 iun → reparat în 7.0.12, 19 iun)

> **STARE 19 iun 2026: REZOLVAT.** Regresia exista **doar** pe 7.0.10. Kernelul **7.0.12** (forky)
> repară parser-ul HDA in-tree: audio funcționează (card 0 CS8409/CS42L83, **0 UBSAN**), iar 7.0.10
> e dezinstalat. Driverul davidjo n-a avut nevoie de patch — bug-ul era 100% in-tree, exact cum a
> arătat analiza. Secțiunea de mai jos e păstrată ca **arhivă tehnică** (debugging-ul complet care a
> dus la diagnostic), nu mai e o problemă activă.

**Simptom (istoric)**: pe kernel `7.0.10+deb14-amd64`, niciun sound card (`/proc/asound/cards` = "no
soundcards", `/dev/snd/` doar seq+timer). Pe `7.0.9` și `7.0.12` audio funcționează perfect.

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

**Clasificare reală — CORECȚIE după debugging profund**: e o **regresie de cod în parser-ul HDA
in-tree între 7.0.9 și 7.0.10**, NU "UBSAN nou activat" (greșeala mea inițială).

Dovadă decisivă:
- `CONFIG_UBSAN_BOUNDS_STRICT=y` în **AMBELE** kerneluri (`/boot/config-7.0.9` și `7.0.10`)
- Boot 7.0.9: **0** erori UBSAN audio, audio merge
- Boot 7.0.10: **10** erori UBSAN audio, audio rupt
- Deci sanitizer-ul era mereu acolo; codul HDA in-tree (`sound/hda/codecs/generic.c` +
  `common/auto_parser.c`) s-a schimbat în 7.0.10 și acum produce `cfg->num_inputs` umflat.

Mecanismul exact (din sursa 7.0.10):
- `cs8409_parse_auto_config` (patch_cs8409.c:22) e un wrapper minimal standard: apelează
  `snd_hda_parse_pin_defcfg` (num_inputs=2, corect — logat "inputs: Internal Mic, Mic")
  apoi `snd_hda_gen_parse_auto_config` (in-tree).
- ÎN INTERIORUL `snd_hda_gen_parse_auto_config` (in-tree 7.0.10), bucla de input labels
  (generic.c:3293 `for i < cfg->num_inputs`) ajunge la index 18, 40, 41, 42 pe `inputs[18]`
  și label index garbage 223 pe `input_labels[36]` → num_inputs se umflă peste limite ÎN
  codul in-tree, nu în driver.
- Driverul doar consumă API-ul standard; bug-ul e in-tree.

**Fix — direcții (corectate)**:
1. **Kernel**: regresia e în codul HDA in-tree 7.0.10. Fix corect = bug report kernel + patch
   in-tree (sau revert al schimbării care umflă num_inputs). Cel mai probabil un kernel viitor
   (7.0.11+) îl repară DACĂ schimbarea e recunoscută ca regresie.
2. **Driver** (davidjo/snd_hda_macbookpro): ar putea adăuga un workaround (ex: clamp defensiv),
   dar bug-ul nu e în logica lui — wrapper-ul e standard.

**Pas decisiv pentru patch exact**: diff `sound/hda/codecs/generic.c` + `common/auto_parser.c`
între sursa 7.0.9 și 7.0.10. Sursa 7.0.9 NU e disponibilă local (pachetul `linux-source-7.0` e
deja 7.0.10; fără deb-src). Ar trebui din snapshot.debian.org sau git kernel. Acel diff arată
exact ce s-a schimbat → patch in-tree precis. Fără el, orice patch driver e ghicit.

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
- [x] Issue gata: `ISSUE_audio_kernel_7.0.10.md` (de postat pe davidjo/snd_hda_macbookpro + Debian)
- [x] Kernel 7.0.11 changelog verificat (4 iun) — NU repară audio (3 commit-uri ASoC irelevante)
- [x] Test 7.1-rc5 (4 iun) — neconcludent (build-script driver fail pe RC; vezi mai jos). 7.1
      scos, sistem curățat. **DECIZIE: așteptăm 7.1 RELEASED stabil** ca să-l testăm corect.
- [x] **7.0.12 (forky, 19 iun) REPARĂ audio** — nu a mai fost nevoie de 7.1. Verificat: 0 UBSAN, card OK.
- [x] Decizie GRUB default — **N/A**: 7.0.12 e default-ul bun (audio merge); 7.0.9 rămâne ca rezervă în GRUB.

**Cleanup experimental (rulat 4 iun)**: 7.1-rc5 scos, meta-pachete readuse la forky 7.0.10.
Repo experimental rămâne configurat (pinned prioritate 1 — nu trage nimic automat). Pentru a-l
scoate complet: `sudo rm /etc/apt/sources.list.d/experimental.list /etc/apt/preferences.d/experimental`.

**Comparație changelog kerneluri (pt audio HDA)**:
- **7.0.11** (kernel.org, 1 iun): 3 commit-uri sunet, TOATE ASoC (`cs-amp-lib`, `cs35l56` —
  drivere SoundWire amp, nu codec HDA CS8409). **Zero** fix în parser-ul HDA generic. NU repară.
  În plus, **nu e în Debian** (forky=7.0.10, experimental=7.1-rc5). Inutil pt cazul nostru.
- **7.1-rc5** (Debian experimental, `7.1~rc5-1~exp1`): TESTAT 4 iun — **neconcludent pentru audio**.
  - facetimehd (camera) DKMS: ✅ build OK pe 7.1
  - snd_hda_macbookpro (audio) DKMS: ❌ **eșec de BUILD-SCRIPT, nu de cod**:
    `install.cirrus.driver.sh:167` caută `/usr/src/linux-source-7.1.tar.bz2` dar Debian livrează
    `.tar.xz` → nu-l găsește → cade pe download kernel.org `linux-7.1.tar.xz` → **404** (7.1 e RC,
    fără tarball stabil) → "kernel could not be downloaded...exiting" → make eșuează ("external
    module directory does not exist"). Driverul NICI n-a atins cod HDA → testul regresiei e nul.
  - Efect secundar: postinst eșuat → **7.1 fără initrd** (`/boot/initrd.img-7.1` lipsă) → NU
    bootabil + 4 pachete dpkg half-configured (iF/iU). Necesită cleanup.
  - **Concluzie**: nu putem testa dacă 7.1 repară HDA până când (a) 7.1 e RELEASED (tarball stabil
    pe kernel.org), SAU (b) patch-uim build-script-ul driverului să accepte `.tar.xz` + sursa
    locală. Bug-ul de build-script (`.bz2` hardcodat) e o problemă separată, raportabilă și ea.
  - **De reținut**: driverul snd_hda_macbookpro nu suportă kerneluri RC (download-ul presupune
    tarball stabil) și presupune sursă `.bz2` (Ubuntu-style), nu `.xz` (Debian).

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

**Test de confirmare** (pentru a fi 100% siguri): `sudo systemctl poweroff -i` complet → pornire → boot 7.0.10.
Dacă BT revine `UP RUNNING` pe 7.0.10 după power-off → confirmat warm-reboot, nu kernel. (Dacă
rămâne mort și după power-off curat pe 7.0.10 → atunci ar fi regresie kernel, investigăm separat.)

---

## 🔴 REGRESIE ACTIVĂ — reboot hang + suspend hang (Apple S3/reset quirks, 7 iun)

Două probleme hardware Apple distincte, ambele = "OS face totul curat, dar hardware-ul nu
execută reset/resume". Pe MacBookPro14,1.

### 3a. Reboot hang la "Rebooting." — ✅ REZOLVAT + în script

`systemctl reboot` oprește OS-ul complet (unmount, sync, "Rebooting.") dar **hardware-ul nu se
resetează** → blocat, necesită power-off manual. Intermitent (uneori reboot-ul merge).
- Cmdline NU avea `reboot=` → metoda default de reset nu e fiabilă pe Apple.
- **Fix `reboot=pci`** (reset via PCI port 0xcf9) — **TESTAT 7 iun, rezolvă reboot hang**. Adăugat
  în script ETAPA 5a (parametrii GRUB). Alternative dacă cedează vreodată: `reboot=efi`/`reboot=acpi`.
- NU era cauzat de pachete — `apt upgrade` din 7 iun a fost doar userspace (LibreOffice etc.).

### 3b. suspend-then-hibernate → S3 nu se trezește (ETAPA 5 incomplet)

7 iun 01:04 lid closed → 05:27 `systemd-suspend-then-hibernate.service` → `PM: suspend entry
(deep)` → jurnal se oprește (S3 no-wake) → force power-off. Config ETAPA 5 e INTACT (logind
lid=lock, gsettings sleep-inactive=nothing) dar **o cale de suspend tot a scăpat** (probabil idle
lung pe baterie). Auto-suspend-ul nostru via gsettings + lid nu acoperă TOATE căile (logind
idle action / battery / suspend-then-hibernate target).
- **Fix bulletproof — ✅ adăugat în script ETAPA 5e**: MASK target-urile de sleep:
  ```
  sudo systemctl mask sleep.target suspend.target hibernate.target suspend-then-hibernate.target
  ```
  Face IMPOSIBIL orice suspend/hibernate — nimic nu mai poate declanșa S3. Reversibil cu
  `systemctl unmask`. Mai robust decât gsettings (care a scăpat această cale).
- Trade-off: blochează și suspend-ul manual (dar S3 oricum nu se trezește → nu pierzi nimic real).
- **NB pe sistemul user**: ✅ APLICAT (confirmat 13 iun) — toate 4 target-urile sunt `masked`
  (symlink-uri `-> /dev/null` în `/etc/systemd/system/`, datate 7 iun 09:34). Documentat în README
  secțiunea "Suspend / sleep / hibernation" cu explicația completă de ce S3+hibernare = dead end.

### 3d. udevadm settle hang în script pe 7.0.10 — ✅ FIXAT (efect al bug-ului audio)

La re-rularea scriptului pe 7.0.10, ETAPA 8b a stat blocată ~1 min la `udevadm settle`
("Timed out while waiting for udev queue to empty"). Cauză (din jurnal 13:04):
```
systemd-udevd: hdaudioC0D0: Worker [390] ... killed.
kernel: BUG: unable to handle page fault ... supervisor write ... RIP: strcmp+0x28
  Modules linked in: ... snd_hda_codec_cs8409(OE+) ...
```
udev face coldplug la device-ul audio → încarcă cs8409 → probe → page fault (bug-ul audio 7.0.10)
→ **omoară worker-ul udev** → coada nu se golește → `udevadm settle` așteaptă până la timeout.
Pe 7.0.9 (audio OK) settle revine instant — diferența confirmă cauza.

**Fix în script (ETAPA 8b)**: `udevadm settle` → `udevadm settle --timeout=5`. Nu avem nevoie să
golim toată coada (declanșăm un singur device + verificăm direct rezultatul); bound la 5s elimină
hang-ul pe orice kernel cu coadă aglomerată. RAPL + fan floor se aplică oricum corect (verificat:
22/30 + fan1_min=3500 active pe 7.0.10). Încă o dovadă (write page fault) adăugată în issue.

### 3c. Confirmare: strcmp GP-fault (4 iun) = bug-ul audio 7.0.10

Poza 4 iun: `Oops: general protection fault ... non-canonical address 0x25002400000002 / RIP:
strcmp+0x28 / modprobe exited with irqs disabled`. Pointer-ul garbage vine din citirea
out-of-bounds `input_labels[223]` (generic.c:3305 `strcmp(input_labels[j], label)`). Deci
regresia audio 7.0.10 nu doar warn-uiește UBSAN — poate **hard-crash kernelul** (GP fault în
modprobe la load cs8409). De adăugat în ISSUE_audio_kernel_7.0.10.md ca dovadă de severitate.

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
| **Suspend S3 / hibernare** | S3 nu se trezește fiabil pe NVMe+EFI Apple. Blocat complet via `systemctl mask` pe sleep targets (ETAPA 5e). Hibernarea (suspend-to-disk) ar necesita swap ≥ RAM + ar moșteni aceleași probleme de resume Apple — nefiabil. Explicație completă în README "Suspend / sleep / hibernation". |
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
