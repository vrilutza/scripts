# TODO — plan tehnic & stare reală

Fișier unic: **ce e rezolvat**, **ce e deschis și se poate repara**, **ce e won't-fix** și **ce s-a respins tehnic**
(cu dovada, ca să nu fie repropus). Înlocuiește și absoarbe fostele `ANALIZA_TEHNICA_UNIFICATA.md`,
`hard_issues_deep_analysis.md`, `todo_full_technical_breakdown.md`, `unresolved_todo_technical_plan.md`.

| | |
|---|---|
| **Hardware** | MacBookPro14,1 (A1708), i5-7360U 2C/4T, Iris 640, 8 GB RAM, Apple S3X NVMe, BCM4350C0 (WiFi PCIe + BT UART), FaceTime HD, CS8409/CS42L83 |
| **Software** | Debian testing/forky, kernel `7.1.6+deb14-amd64` (+ `7.1.3` păstrat ca rezervă, DKMS construit pe ambele), pipewire 1.6.8-1, wireplumber 0.5.15-1, Chrome 151.0.7922.108, GNOME/Wayland |
| **Verificat pe viu** | **8 august 2026** — reverificare completă a cifrelor de mai jos pe **196 de boot-uri** (19 mai → 8 aug). Verificarea anterioară: 27 iulie, 173 de boot-uri. Ce nu s-a putut reverifica e marcat explicit `⏳ neconfirmat`. |
| **Stare de bază** | Hardware-ul e funcțional. Margini: 2 probleme cronice (BT, WiFi), 1 **nediagnosticată** (opriri spontane), 1 la upstream (cameră — 9 rapoarte trimise, 2 acceptate), 1 fizică (termic). |

**Legendă:**

| Simbol | Sens |
|---|---|
| ✅ | Rezolvat și verificat — rămâne doar ca referință |
| 🟢 | Deschis, fixabil local, plan clar, risc mic |
| 🟡 | Deschis, are nevoie de un experiment/măsurătoare înainte de decizie |
| 🔵 | Deschis, depinde de upstream — local nu există fix curat |
| 🔴 | Won't-fix (limitare hardware/firmware reală) |
| ❌ | Propunere **respinsă** (greșită tehnic sau periculoasă) — vezi Anexa C |

---

## 0. Tabloul complet

| # | Subiect | Status | Ce mai e de făcut | Secț. |
|---|---|---|---|---|
| 1 | Bluetooth mort la ~14% din boot-uri (`-110`) | 🟡 activ | experiment de 3 linii care separă „warm vs cold"; SMC reset ca remediu | [1](#1--bluetooth-bcm4350c0--init-eșuat-la-14-din-boot-uri) |
| 2 | WiFi BCM4350 — desincronizare ring, risc de panică | 🟡 activ | raport upstream cu dovezile din pstore; monitorizare cu prag | [2](#2--wifi-bcm4350--desincronizare-ring-msgbuf) |
| 3 | Cameră — partajare de buffere fără `SPA_META_Busy` (aplicațiile îngheață) | 🔵 upstream | **1 patch acceptat în master**; restul așteaptă review | [3](#3--camera-facetime-hd--partajare-de-buffere-nesigură) |
| 4 | Sacadare cu 2 browsere + saturație termică | 🟢 | curățare fizică + tab-ul Chrome; abia apoi eventual daemon de ventilator | [4](#4--termic--sacadare) |
| 5 | Suspend / s2idle | 🟡 opțional | experiment reversibil, dacă chiar vrei suspend | [5](#5--suspend--s2idle) |
| 6 | Zgomot de log (DMAR / ACPI / SGX / nvme0n2) | 🔴 | nimic — vezi de ce „fix-ul fără dezactivarea IOMMU" nu funcționează | [6](#6--zgomot-de-log) |
| 7 | Tot ce e deja închis (NVRAM, audio, RAPL, rfkill, kernel…) | ✅ | nimic | [7](#7--rezolvate-arhivă-tehnică) |
| **8** | **Opriri spontane, fără urmă în jurnal** | 🟡 **activ** | netconsole către al doilea PC, ca următoarea să lase o urmă | [8](#8--opriri-spontane--cauză-nedeterminată) |

**Ordinea recomandată:**

| Prioritate | Acțiune | Efort | Risc | Câștig |
|---|---|---|---|---|
| **P1** | Curățare fizică ventilator + radiator (+ eventual PTM7950) | 1-2 h | mediu (demontare) | marja termică — măsura principală anti-sacadare |
| **P1** | **Netconsole către al doilea PC** (§8) | 30 min | zero | singura cale de a prinde următoarea oprire spontană |
| **P2** | Identificat tab-ul Chrome de 10-13% (`Shift+Esc`) | 5 min | zero | ~10% CPU permanent |
| **P2** | Hook de shutdown care logează verbul (`reboot`/`poweroff`) | 15 min | mic | răspunde la întrebarea BT `-110` **și** la §8 |
| **P3** | Raport upstream `brcmfmac` cu dovezile din pstore | 1-2 h | zero | poate scoate riscul de panică definitiv |
| **P4** | Experiment s2idle (doar dacă vrei suspend) | 30 min | mediu, reversibil | lid-close real |
| **P5** | Daemon de ventilator pe `fan1_min` dinamic | 2 h | mic (dacă se face corect) | mic — doar cazul „rafală după liniște" |

*(Scos din listă pe 8 august: „persistența patch-ului `FTHD_BUFFERS=8`". Patch-ul nu mai există —
vezi §3.)*

---

## 0.1 Rapoarte trimise upstream — tablou

Toate raportate de aici. Ține-le într-un singur loc: două s-au și rezolvat, iar despre restul e ușor
să uiți că există. Stare verificată prin API pe **8 august 2026**.

| Unde | Ce | Stare |
|---|---|---|
| [wireplumber #972](https://gitlab.freedesktop.org/pipewire/wireplumber/-/work_items/972) | hook-urile de linking crăpau pentru stream-uri fără `media.type` | ✅ **rezolvat upstream** (MR 861, în master) — §7.4 |
| [pipewire !2941](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2941) | reciclare de buffer sub încuietoarea buclei + scurgere `buf_to_release` | ✅ **acceptat în master** `30ff8da17`, neatins, fast-forward |
| [pipewire !2934](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2934) | gardă de depășire în `spa_v4l2_use_buffers()` | 🔵 deschis, `mergeable`, CI verde; recenzat de `pobrn`, răspuns dat |
| [pipewire !2935](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2935) | copiere când pool-ul se golește | 🔵 **Draft intenționat** — ce a rămas e o decizie de politică |
| [pipewire #5363](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/5363) | raportul de bază | 🔵 deschis, fără răspuns de mentenanț din 11 iulie |
| [snapshot #367](https://gitlab.gnome.org/GNOME/snapshot/-/work_items/367) | viewfinder înghețat pe primul cadru | 🔵 deschis, **1 upvote** — altcineva a confirmat bug-ul (8 aug) |
| [facetimehd #328…#333](https://github.com/patjak/facetimehd/pulls) | șase PR-uri de driver (vezi §3.3) | 🔵 toate deschise, `MERGEABLE`, **zero review-uri**; upstream nu s-a mișcat din 30 iunie |
| [snd_hda_macbookpro #187](https://github.com/davidjo/snd_hda_macbookpro/issues/187) | `install.cirrus.driver.sh` pică pe Debian (`.tar.xz`) și pe kerneluri `-rc` (404 la kernel.org) | 🔵 deschis, 7 comentarii |
| [snd_hda_macbookpro #189](https://github.com/davidjo/snd_hda_macbookpro/pull/189) | fix: folosește sursa de kernel instalată local | 🔵 deschis, 1 comentariu |

⚠️ **Ultimele două nu erau consemnate nicăieri în acest repo** până pe 8 august, deși
`#187` descrie exact capcana de la **fiecare** upgrade de kernel pe mașina asta: dacă
`linux-source-<X.Y>` nu e instalat **înainte**, build-ul DKMS al audio-ului pică. Vezi §7.9.

---

## 1. 🟡 Bluetooth BCM4350C0 — init eșuat la 14% din boot-uri

Cip combo WiFi+BT Broadcom **BCM4350C0**; partea BT e atașată pe **UART** (serial, nu USB — verificat:
`/sys/class/bluetooth/hci0` → `…/dw-apb-uart.2/…`), driver `hci_uart` + `btbcm`.

### 1.1 Cele două rezultate posibile la boot

La init, `btbcm` trimite o comandă HCI vendor Broadcom (`0xfc18`) ca să urce viteza UART de la 115200,
apoi reconfigurează UART-ul gazdă. Pe Apple, ACPI nu descrie complet device-ul
(`hci_uart_bcm: Unexpected ACPI gpio_int_idx: -1`, `No reset resource, using default baud rate`),
deci reconfigurarea nu se poate aplica. Eroarea apare **la fiecare boot**, dar cu două coduri diferite:

```
BENIGN (149 boot-uri)                        FATAL (24 boot-uri)
  BCM: failed to write update baudrate (-16)   hci0: command 0xfc18 tx timeout
  Failed to set baudrate                       BCM: failed to write update baudrate (-110)
  BCM: chip id 92                              Failed to set baudrate
  BCM4350C0 UART 37.4 MHz Gamay USI UHE        hci0: command 0xfc18 tx timeout   ← reîncercare
  BCM: firmware Patch file not found           BCM: Reset failed (-110)
  → hci0 UP RUNNING, BT funcțional             → hci0 DOWN, BD Address 00:00:00:00:00:00
                                               → „No default controller available"
```

Pe boot-urile fatale controllerul rămâne mut și la **a doua** trimitere a lui `0xfc18` — nu e un
timeout izolat, ci lipsă totală de răspuns pe UART.

- `-16` = **`-EBUSY`**: comanda e refuzată, dar controllerul răspunde. Rămâne pe 115200 și **merge** —
  suficient pentru mouse/tastatură/căști (A2DP ok). Doar throughput-ul maxim teoretic e limitat.
- `-110` = **`-ETIMEDOUT`**: controllerul **nu răspunde deloc** (`tx timeout`), reset-ul eșuează,
  BT e mort tot boot-ul.

### 1.2 Statistica — reverificată pe 196 de boot-uri (19 mai → 8 aug)

| Observație | 27 iulie | **8 august** | Interpretare |
|---|---|---|---|
| `failed to write update baudrate` | 173 | **195** | apare la *fiecare* boot cu init BT |
| … cu `-16` (`-EBUSY`) | 149 | **168** | benign: BT urcă, rămâne la 115200 |
| … cu `-110` (`-ETIMEDOUT`) | 24 | **27** | fatal: `BCM: Reset failed (-110)` → BT mort tot boot-ul |

**Rata de eșec: 27/195 = 13,8%** — față de 13,9% în urmă cu 12 zile și 23 de boot-uri.
Practic neschimbată; e o proprietate stabilă a hardware-ului, nu o derivă.

*(Boot-ul curent, 8 aug 08:09: `-16`, `chip id 92`, `hci0 UP RUNNING`, `BD Address 8C:85:90:52:15:6F`
— deci BT funcțional azi.)*

Corelația cu `.hcd` e decisivă: pe boot-urile cu `-110` **nu apare nici `chip id 92`, nici căutarea
`.hcd`** — secvența moare la reset, înainte de orice încărcare de firmware. Asta închide definitiv
ideea „extragem `.hcd`-ul din macOS și se repară" (vezi **E11**, Anexa C).

### 1.3 Teoria „warm reboot" — măsurată, nu presupusă (27 iul)

`README`-ul și versiunile vechi ale acestui fișier spuneau: *„`reboot` nu power-cycle-ază cipul → poate
rămâne mut"*. Verbul de shutdown **nu e persistat în jurnal** (`journald` se oprește înainte ca
`systemd-shutdown` să scrie `Rebooting.`/`Powering off.` — zero astfel de linii în tot jurnalul), deci
teoria nu se poate testa direct. **Proxy folosit:** timpul mort dintre ultima intrare a unui boot și
prima intrare a următorului. O repornire rapidă (<45 s) e aproape sigur `reboot`; o pauză lungă
înseamnă alimentare întreruptă.

```
                        repornire rapidă (<45 s)   pauză ≥45 s
BT mort (-110)                    12                   12
BT ok   (-16)                     45                  103

P(BT mort | repornire rapidă) = 12/57  = 21%
P(BT mort | pauză lungă)      = 12/115 = 10%     → risc relativ 2,0×
Fisher exact, o coadă:  p = 0,055
```

**Concluzie nuanțată — teoria e parțial adevărată și insuficientă:**

- repornirea rapidă **dublează** riscul (21% vs 10%), ceea ce susține mecanismul „cipul nu e
  power-cycle-at"… dar la `p = 0,055` e **sugestiv, nu dovedit** (sub pragul de semnificație);
- **jumătate din eșecuri (12/24) apar după pauze lungi** — 11 dintre ele după ≥10 minute de oprire,
  unul după **23,9 h**. O oprire de 24 h power-cycle-ază cipul cu certitudine, deci warm reboot-ul
  **nu poate fi singura cauză**. Rămâne o componentă de cursă (race) în secvența de init UART.
- Exemplu concret din ultimele zile: boot-ul de **27 iul 00:00** a avut BT mort după o pauză de
  **25 min**; boot-ul curent (27 iul 17:08, după 9 h de oprire) are BT **funcțional** (`-16`, `chip id 92`).
- Ipoteza alternativă „shutdown murdar" a fost **infirmată**: pe boot-urile cu BT mort, boot-ul
  precedent s-a încheiat curat în 22 din 24 de cazuri; în grupul de control — 23 din 25. Nicio diferență.

### 1.4 🟢 De făcut

- [ ] **P2 — experimentul care răspunde definitiv. `⏳ NEFĂCUT`** (verificat 8 aug:
      `/usr/lib/systemd/system-shutdown/` conține doar `fwupd.shutdown`.) `systemd` execută scripturile din
      `/usr/lib/systemd/system-shutdown/` cu **verbul ca `$1`** (`reboot`, `poweroff`, `halt`, `kexec`).
      Directorul există deja (conține `fwupd.shutdown`). Prima versiune trebuie doar să **măsoare**,
      nu să repare:

      /usr/lib/systemd/system-shutdown/00-log-verb   →  adaugă „<data> <verb>" într-un fișier persistent
                                                        (obligatoriu: shebang + chmod +x, altfel
                                                         systemd îl ignoră în tăcere)

      După 2-3 săptămâni, corelezi fișierul cu boot-urile care au avut `Reset failed (-110)`. Abia atunci
      știi dacă warm reboot-ul e cauza dominantă — și, dacă e, poți testa varianta activă
      (`btmgmt power off` sau `hciconfig hci0 down` înainte de reboot; ambele binare există).
- [ ] **Experiment ieftin de încercat la următorul `-110`** (5 secunde, complet reversibil):
      `sudo modprobe -r hci_uart && sudo modprobe hci_uart` — reîncarcă transportul și re-rulează init-ul
      fără shutdown. **Poate să nu ajute** (nu face power-cycle cipului). Dar rezultatul e informativ în
      ambele sensuri: dacă *funcționează*, starea proastă e în driver/UART, nu în cip — ceea ce schimbă
      complet diagnosticul și face fix-ul mult mai ieftin.
- **Remediu când se întâmplă (documentat în `README.md`, „SMC Reset"):** `sudo systemctl poweroff -i`,
  apoi **Shift stânga + Control stânga + Option stânga + Power** ~10 s, apoi pornire normală.
  SMC Reset-ul face power-cycle cipului. *(Notă: uneori e suficient un simplu poweroff lung —
  vezi boot-ul de azi.)*

### 1.5 🔴 Cele două mesaje de log — verdict neschimbat

| Mesaj | Cauză | Verdict |
|---|---|---|
| `failed to write update baudrate (-16)` (149 boot-uri) | ACPI Apple nu descrie GPIO-ul de reset → UART-ul nu poate fi reconfigurat → rămâne 115200 | 🔴 Won't-fix. 115200 e suficient pentru mouse/tastatură/căști A2DP |
| `firmware: failed to load brcm/BCM.hcd (-2)` → `Patch file not found` (149 boot-uri) | `.hcd` = patch RAM **opțional** peste ROM-ul controllerului; Debian (`firmware-brcm80211`) nu livrează blob-ul Apple (ne-redistribuibil legal, ca nvram/clm_blob de pe WiFi). `-2` = `-ENOENT`; `btbcm` continuă pe ROM-ul built-in | 🔴 Won't-fix. Vezi **E11** — nu rezolvă `-110` |

Ambele au aceeași rădăcină ca `brcmfmac: failed to load ...MacBookPro14,1.*`: Apple ține
firmware/calibrare custom în macOS, Linux cade pe generic/ROM și merge.

---

## 2. 🟡 WiFi BCM4350 — desincronizare ring msgbuf

### 2.1 Incidentul de referință (7 iul 2026, 06:08)

Kernel panic `Fatal exception in interrupt`, capturat complet în **pstore EFI**. Lanțul cauzal:

1. `DMAR: [DMA Write] … PTE Write access is not set` — chipul WiFi a încercat o scriere DMA interzisă;
   IOMMU (VT-d) a blocat-o;
2. `brcmf_msgbuf_get_pktid: Invalid packet id` — ring-ul firmware↔driver desincronizat;
3. skb corupt scăpat în stiva de rețea (**125 fragmente / max 17**, 2× UBSAN `skbuff.h:2543`);
4. GPF în `memcpy` în softirq → panic. Colateral: `applespi` mort imediat (`-110`).

**Cauza-rădăcină:** firmware-ul generic Broadcom (nov 2015), fără NVRAM/CLM Apple, se desincronizează
cronic de driver. Nu e regresie de kernel — apărea pe toate kernelele testate.

**Mecanismul corupției (important pentru orice fix):** `skb_shared_info` stă **imediat după** zona de
date a bufferului. O scriere DMA care depășește bufferul suprascrie `nr_frags` — de-aici valoarea
absurdă de 125.

### 2.2 Datele reale — mitigarea din 8 iulie **nu** a oprit desincronizarea

```
brcmf_msgbuf_get_pktid: Invalid packet id   — 93 evenimente, 19 mai → 8 aug   (erau 62 la 27 iul)
  • până la 8 iul 08:00 (pre-mitigare):     23 evenimente / ~50 zile = 0,46/zi
  • după 8 iul 08:00 (post-mitigare):       70 evenimente / ~31 zile = 2,26/zi   ← ×4,9
  • vârfuri:  12 iul = 14 · 27 iul = 15 · 18 iul = 8 · 19 iul = 7
  • din 27 iul incoace: 27 iul=15 · 28 iul=5 · 1 aug=5 · 2 aug=2 · 3 aug=2 · 4 aug=1 · 5 aug=1
  • ultimul:  5 august
Panici / oops / UBSAN după 8 iul:           0    (reverificat 8 aug)
```

**Reverificat 8 august:** rata post-mitigare a rămas ~2/zi, exact cum arăta acum 12 zile. Nimic nu
s-a înrăutățit, nimic nu s-a reparat. De notat, fără să se tragă concluzii: **niciun eveniment din
5 august încoace** — trei zile. Prea puțin ca să însemne ceva la o rată de 2/zi, dar merită urmărit.

⚠️ **Corecție față de nota veche din acest fișier.** Scria: *„ultimul eveniment 8 iul 06:50; 0 evenimente
în cele 4 zile de după → mitigarea pare eficace"*. Afirmația era corectă **pe 12 iulie dimineața** — în
aceeași zi au apărut 14. Concluzia se inversează: **`wifi.powersave=2` nu a oprit desincronizarea.**

*(Capcană metodologică care a produs nota greșită: `journalctl -k` implică `-b`, adică **doar boot-ul
curent**. Orice statistică istorică trebuie făcută cu `_TRANSPORT=kernel --since …` — vezi Anexa B.)*

### 2.3 Ce înseamnă și ce nu înseamnă

- Desincronizarea e **cronică și în creștere** ca frecvență.
- Totuși, în cele 39 de evenimente post-mitigare **niciunul n-a mai ajuns la panică**. Asta confirmă
  analiza originală: de obicei driverul se recuperează silențios; pe 7 iulie corupția a scăpat în stiva
  de rețea, ceea ce e evenimentul rar.
- `kernel.panic=10` **nu previne** panica — doar transformă freeze-ul permanent în reboot la 10 s. Util.
- **IOMMU e singura barieră reală** și rămâne pornit: el a blocat scrierea DMA ilegală din 7 iulie.

**Recalibrare de risc:** ~2 desincronizări/zi × probabilitate mică de scăpare în stivă = un eveniment de
tip 7 iulie la fiecare câteva luni. Nu e urgent, dar nici „rezolvat".

### 2.4 Mitigări deja aplicate (8 iul, live + ETAPA 5g în script)

- [x] WiFi **power-save off** (persistent, `wifi.powersave = 2` în NetworkManager). Cost zero (laptop
      mereu pe AC). **Efect real: nul** — vezi §2.2. Se păstrează, nu strică nimic.
- [x] **`kernel.panic = 10`** — reboot automat la 10 s după panic în loc de freeze permanent.
- [x] **IOMMU rămâne pornit.** `intel_iommu=off` ar transforma scrierile DMA blocate în corupere
      silențioasă de memorie. ❌ Interzis, definitiv.
- [x] ~~Fix definitiv = firmware Apple BCM4350 („faza 2")~~ — **investigat 8 iul, verdict: fișierele NU
      există nicăieri.** Nici în macOS: pe Mac-urile non-T2 calibrarea stă în OTP-ul cipului (pe care
      `brcmfmac` îl citește deja), iar datele regulatorii sunt în firmware-ul Apple „bmac" (split-MAC,
      incompatibil `brcmfmac`). Impact real ~zero: toate canalele 5 GHz sunt active (36–165); limitarea
      la 2,4 GHz vine de la router (SSID „vik" emite doar pe canalul 1). → won't-fix.

### 2.5 Opțiuni deschise

| Opțiune | Efort | Risc | Verdict |
|---|---|---|---|
| **A. Status quo** (IOMMU + `panic=10`) + monitorizare | zero | acceptat | **Baza.** Rămâne valabilă indiferent ce se alege mai jos |
| **B. Raport upstream** (linux-wireless/netdev) cu dump-ul pstore din 7 iul | 1-2 h | zero | **Recomandat (P3), `⏳ nefăcut`.** Ai ceva ce raportorii obișnuiți n-au: panică completă capturată în pstore + **93** de evenimente datate. Aceeași strategie a funcționat deja de două ori: wireplumber #972 (rezolvat) și pipewire !2941 (acceptat în master) — vezi §0.1 |
| **C. Hardening local prin DKMS** (§2.6) | mare | mediu | **Doar ca ultimă soluție.** `brcmfmac` e in-tree; un fork DKMS cere blacklist pe modulul din kernel, rebuild la fiecare update, taint suplimentar |
| **D. Adaptor USB WiFi (~15 €)** | 15 € | zero | Ocolire completă a cipului Broadcom. Plan B dacă redevine frecvent + panici |
| ❌ **`intel_iommu=off`** | — | — | **Interzis** (§2.4) |

### 2.6 Patch defensiv — versiunea corectă (dacă se merge pe B sau C)

Punct de inserție verificat în sursa kernel 7.1 (`msgbuf.c`, `brcmf_msgbuf_process_rx_complete()` —
definită la linia **1147**, **nu** `brcmf_msgbuf_rx_process()`, care nu există; vezi **E4**).

⚠️ **Poziția contează:** verificarea trebuie să stea între `if (!skb) return;` și primul `skb_pull()`
care urmează imediat. `skb_pull()` pe un skb cu `skb_shared_info` corupt e la fel de nesigur ca
eliberarea lui — orice inserție mai jos ratează scopul.

```c
/* drivers/net/wireless/broadcom/brcm80211/brcmfmac/msgbuf.c
 * în brcmf_msgbuf_process_rx_complete(), imediat după: */
	skb = brcmf_msgbuf_get_pktid(msgbuf->drvr->bus_if->dev,
				     msgbuf->rx_pktids, idx);
	if (!skb)
		return;
+
+	/* Un buffer RX proaspăt postat e mereu liniar: nr_frags == 0.
+	 * skb_shared_info stă imediat după zona de date, deci o scriere DMA
+	 * care depășește bufferul o corupe (incident 7 iul 2026: nr_frags=125,
+	 * max 17 -> GPF in memcpy in softirq).
+	 */
+	if (unlikely(skb_shinfo(skb)->nr_frags || skb_shinfo(skb)->frag_list)) {
+		bphy_err(drvr, "corrupted rx skb (nr_frags=%u), dropping\n",
+			 skb_shinfo(skb)->nr_frags);
+		/* ESENȚIAL: se sanitizează ÎNAINTE de free — altfel
+		 * skb_release_data() parcurge chiar array-ul corupt.
+		 */
+		skb_shinfo(skb)->nr_frags = 0;
+		skb_shinfo(skb)->frag_list = NULL;
+		brcmu_pkt_buf_free_skb(skb);
+		return;
+	}
```

**Ce face și ce nu face:** transformă o panică într-un pachet aruncat + o linie de log. **Nu** repară
desincronizarea firmware-ului — aia rămâne.

### 2.7 🟢 Monitorizare automată — `⏳ NEFĂCUT`

*(Verificat 8 aug: nu există niciun timer propriu în `/etc/systemd/system/`.)*

- [ ] Timer systemd zilnic care numără evenimentele din ultimele 24 h și alertează peste prag.
      Detalii de implementare care contează:
      - filtrul explicit e **obligatoriu**: `journalctl _TRANSPORT=kernel --since "24 hours ago"
        -g "Invalid packet id" | grep -c "Invalid packet id"` — fără al doilea `grep`, se numără și
        liniile de separator dintre boot-uri;
      - notificarea din context root: `systemd-run --machine=vik@ --user …` sau `busctl`, **nu**
        `sudo -u vik notify-send` cu `DBUS_SESSION_BUS_ADDRESS` ghicit;
      - prag rezonabil pe datele reale: **> 5/zi** (media actuală ~2/zi, vârful a fost 14).

---

## 3. 🔵 Camera FaceTime HD — partajare de buffere nesigură

> **Rescrisă integral 8 august 2026.** Versiunea de dinainte descria un diagnostic (limita de 4
> buffere din driver) și un fix (patch local `FTHD_BUFFERS` 4→8) care **nu mai sunt starea reală**.
> Ce s-a schimbat, pe scurt: patch-ul 4→8 a fost **abandonat deliberat** pe 30 iulie, iar cauza
> rădăcină s-a dovedit a fi alta. Textul vechi rămâne în istoricul git (commit `ed5e846`).

### 3.1 Cauza rădăcină, așa cum e ea

`pipewiresrc` predă în aval `GstMemory` **partajat** cu un buffer pe care producătorul îl reia în
același ciclu de graf. Pentru o sursă SPA cum e v4l2 asta e nesigur din două motive: cadrele încă în
zbor sunt suprascrise, iar când clientul ține tot pool-ul fluxul se blochează. Mecanismul care ar
face partajarea legală e **`SPA_META_Busy`** — și **niciun plugin SPA nu-l implementează**.

Cu cele patru buffere pe care le negociază o sursă v4l2, un client care ține patru e suficient ca să
oprească fluxul. Snapshot (lanț de afișare GL) ține exact atâtea.

**De ce nu mai e „driverul limitează la 4":** limita e reală, dar nu e cauza. Un driver cu 8 buffere
mută pragul, nu îl elimină — clientul care ține 8 blochează la fel. De-asta patch-ul 4→8 a fost
retras: trata simptomul, iar ca patch upstream ar fi fost respins pe bună dreptate.

`FTHD_BUFFERS` e azi **4**, valoarea upstream *(verificat 8 aug: `fthd_drv.h:30`)*.

### 3.2 🔵 PipeWire — un patch acceptat, două în așteptare

Vezi tabloul complet din §0.1. Pe scurt:

| MR | ce | stare |
|---|---|---|
| **!2941** | ordinea încuietorilor în `buffer_recycle()` + repararea scurgerii `buf_to_release` | ✅ **în master** (`30ff8da17`), luat neatins, fast-forward |
| !2934 | gardă de depășire în `spa_v4l2_use_buffers()` | 🔵 `mergeable`, CI verde, așteaptă review |
| !2935 | copierea când pool-ul se golește | 🔵 **Draft intenționat** — decizie de politică |

!2941 a fost acceptat la ~2 ore după ce a fost pus. Asta răspunde la întrebarea veche „de ce nu ne
răspunde nimeni": **răspund**, dacă patch-ul e mic, izolat și măsurat.

Evidența completă — bancul de test, măsurătorile, ce s-a retras și de ce — stă în
`pipewire-5363/`, **numai local pe laptop** (nu e publicată: e material de lucru, nu documentație
de proiect). De curățat după ce upstream se pronunță, mai puțin `camera-fix/`, care aparține
proiectului ăstuia. Ce contează pentru cineva din afară e deja în MR-urile și PR-urile linkate
mai sus.

### 3.3 🔵 Driver — șase PR-uri la `patjak/facetimehd`

Toate deschise, `MERGEABLE`, bazate direct pe `364b1c6`. **Zero review-uri** — upstream-ul ăsta e
lent, e de așteptat, nu e un semnal.

| PR | Ce repară |
|---|---|
| [#328](https://github.com/patjak/facetimehd/pull/328) | `break` lipsă la AWB, `FTHD_BUFFERS` în loc de literalul 4, `mdelay`→`msleep` (o secundă de CPU ars la fiecare STREAMON) |
| [#329](https://github.com/patjak/facetimehd/pull/329) | controalele erau aruncate la fiecare STREAMON; `ALIGN(width, 7)` — nu e putere a lui doi, deci era pur și simplu stricat |
| [#330](https://github.com/patjak/facetimehd/pull/330) | decupare **centrată**: orice rezoluție sub senzor întorcea colțul din stânga-sus |
| [#331](https://github.com/patjak/facetimehd/pull/331) | `ENUM_FRAMESIZES` raportează intervalul real, nu o singură dimensiune |
| [#332](https://github.com/patjak/facetimehd/pull/332) | un singur timeout de firmware lăsa camera fără buffere până la reîncărcarea modulului |
| [#333](https://github.com/patjak/facetimehd/pull/333) | **coruperea de memorie**: până la 4095 de octeți scriși *înaintea* bufferului, când acesta nu începe pe graniță de pagină |

Driverul instalat pe mașină e **exact** suma lor *(verificat prin `diff -rq` pe 8 aug)*, construit
pentru ambele kerneluri. Instalare/revenire: `camera-fix/install-pr333.sh`.

### 3.4 ✅ Ce s-a închis din versiunea veche a acestei secțiuni

- ~~patch local `FTHD_BUFFERS` 4→8~~ — **retras**, trata simptomul (§3.1)
- ~~§3.3 persistența patch-ului 4→8 în scriptul de setup~~ — **fără obiect**, patch-ul nu mai există
- ~~§3.4 PR upstream `patjak/facetimehd` cu 4→8~~ — **nu s-a trimis și nu se mai trimite**; în locul
  lui au plecat cele șase de mai sus
- ~~„fix-ul propus e de o linie (`SPA_MIN(8u, …)`)"~~ — **infirmat** de analiza de cauză rădăcină

### 3.5 Workaround, cât timp !2934/!2935 așteaptă

`guvcview` sau camera din Chrome — ambele merg V4L2 direct și ocolesc PipeWire. Neschimbat.

## 4. 🟢 Termic & sacadare

**Simptom:** micro-înțepeniri când sunt deschise Chrome și Firefox simultan; nu apărea în mai (vreme răcoroasă).

### 4.1 Diagnostic pe date live (19 iul: 45 min @5 s + 3 h @10 s, PSI/termice/frecvențe/ventilator)

1. **Cauza principală: saturarea CPU-ului (2C/4T) în rafale.** PSI-CPU ≥10% în **8,4% din timp**, vârfuri
   36-54% (procesele stau la coadă după CPU = exact senzația de înțepenit), load până la 6,5; GPU-ul
   (Iris 640) țintuit la 1000 MHz în aceleași momente. **Chrome = primul consumator în ~80% din
   eșantioane, constant ~10-13% CPU și în idle** — un tab lucrează permanent în fundal.
2. **Agravant termic (legătura cu vremea):** ventilator la ≥7000 RPM ~85% din timp chiar la 60°C
   pachet = **evacuare proastă a căldurii** (praf/pastă uscată), nu control prost. Singurul episod real
   de throttling (+115 evenimente, 89-95°C, 11:47-11:49) a început cu ventilatorul prins jos
   (~3900 RPM) după o perioadă liniștită — lag-ul SMC documentat în README. Pe vreme rece marja acoperă
   rafalele — de-aia „nu se întâmpla acum 2 luni".
3. **Exonerate pe date:** memoria (PSI-mem ~0 permanent, max 4%; swap 2,7 GB dar NVMe absoarbe fără
   stall-uri; avail min 694 MB), thermald (corect, powerclamp 0 intervenții), turbo (3,6 GHz susținut).

**Stare instantanee 27 iul 17:30** (idle, 22 min uptime): pachet **62°C**, ventilator 3497 RPM,
`fan1_min=3500`, `fan1_max=7200`, `fan1_manual=0`, throttle counters **0**, PSI-cpu avg300 = 0,71%,
PSI-mem = 0. Consistent: fără sarcină nu e nicio problemă.

### 4.2 De făcut

- [ ] **P1 — curățare fizică ventilator + radiator** (eventual repastare). **Măsura principală.** Note:
      - capacul A1708 = șuruburi **pentalobe P5**; înăuntru **T5**;
      - deconectezi flexul bateriei **înainte** de a atinge radiatorul;
      - **PTM7950** e alegerea corectă pentru un die expus (fără pump-out), superioară pastelor clasice;
      - ⚠️ A1708 are **bateria lipită**; la manipularea heatsink-ului e ușor să atingi cablul antenei;
      - repastarea unui die expus cere aplicare uniformă, fără presiune pe colțuri;
      - estimarea „idle 60 → 48-52°C" e plauzibilă dar e o promisiune, nu o măsurătoare.

      **Măsurarea efectului** (contoarele se resetează la fiecare boot → compară pe interval egal, în
      aceleași condiții: aceleași tab-uri, aceeași oră):
      ```
      /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count
      /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_total_time_ms
      ```
      plus temperatura de idle din `hwmon` (`Package id 0`) și RPM-ul mediu.
- [ ] **P2 — identificat tab-ul Chrome permanent activ**: `Shift+Esc` în Chrome → Task Manager →
      sortare după CPU. Ținta: procesul de ~10-13% constant în idle. ± uBlock Origin.

### 4.3 🟡 P5 — daemon de ventilator: designul corect

Ideea de anticipare pe *dT/dt* e legitimă. Implementarea propusă în documentele de analiză era
**nefuncțională și periculoasă** (E3). Design corect:

| Aspect | Varianta greșită | Corect |
|---|---|---|
| sursa de temperatură | `thermal_zone0` = **BAT0** (bateria, 36,3°C) | `hwmon` cu `name == coretemp`, eticheta `Package id 0`, **rezolvat după nume** (numerotarea `hwmonN` nu e stabilă între boot-uri) — sau `thermal_zone1` (`x86_pkg_temp`) |
| mecanism | `fan1_manual=1` + `fan1_output` | **`fan1_min` dinamic**, cu `fan1_manual=0` — ridici *podeaua*, SMC-ul păstrează rampa automată și siguranța |
| plafon | 6200 RPM | `fan1_max` = **7200** (valoarea reală citită din applesmc) |
| perioadă | 500 ms | ≥2 s (citirile applesmc sunt lente și serializate; polling agresiv costă CPU exact când n-ai) |
| eșec | ventilator blocat pe ultima valoare | `ExecStopPost=` care restaurează `fan1_min=3500`; `Restart=on-failure` |
| histerezis | absent (oscilează în jurul pragului) | prag de urcare ≠ prag de coborâre + temporizare de revenire |

**Așteptări realiste:** datele de 3 h arată ventilatorul deja la maxim ~85% din timp — deci daemonul
**nu poate câștiga nimic** în acele 85%. Ajută exclusiv scenariul „rafală care prinde ventilatorul jos
după o perioadă liniștită" (fix episodul de la 11:47). Câștig mic; de făcut **după** curățare, când
podeaua termică scade și scenariul devine relativ mai frecvent.

### 4.4 🟡 Politica Chrome — JSON valid pe Chrome 150

Revalidat pe binarul instalat **8 august**, versiunea **151.0.7922.108** (era 150.0.7871.186 —
verdictul e neschimbat pe versiunea nouă):
`HighEfficiencyModeEnabled` ✅, `MemorySaverModeSavings` ✅, `TabDiscardingExceptions` ✅,
`BackgroundModeEnabled` ✅ — dar `TabFreezingEnabled` ❌ **ABSENT** și `BackgroundTracingAllowed` ❌
**ABSENT** (ar fi ignorate în tăcere — vezi E8).

În `/etc/opt/chrome/policies/managed/`:

```json
{
  "HighEfficiencyModeEnabled": true,
  "MemorySaverModeSavings": 2,
  "TabDiscardingExceptions": ["domeniu-de-pastrat-activ.ro"]
}
```

⚠️ **Politica nu e aplicată** *(verificat 8 aug: `/etc/opt/chrome/policies/managed/` nu există)* —
deci ce urmează e o propunere, nu o stare a sistemului.

Am validat **numele** cheilor, nu și **valoarea** enum-ului `MemorySaverModeSavings` (0/1/2) — se
confirmă imediat în `chrome://policy` după aplicare (acolo se vede dacă o cheie a fost acceptată sau ignorată).

⚠️ **Limitare:** Memory Saver descarcă tab-uri **inactive**. Vinovatul măsurat e un tab **activ în
fundal** (10-13% CPU permanent), pe care politica nu-l atinge. Util ca igienă generală, **nu** ca fix
pentru sacadare. Fix-ul real rămâne identificarea tab-ului (§4.2).

### 4.5 ❌ Ce nu se face (respins pe datele de 3 h)

Plafonare turbo (throttling ~1% din timp), zswap (zero presiune de memorie), modificări thermald
(powerclamp: 0 intervenții).

---

## 5. 🟡 Suspend & s2idle

### 5.1 Context

S3 e blocat intenționat (toate sleep target-urile `masked`, ETAPA 5e) pentru că nu se trezea fiabil pe
NVMe+EFI Apple. Dar există o cerere reală de utilizare:

```
26 iul 23:30:46  systemd-logind: Suspend key pressed short.
26 iul 23:30:46  systemd-logind: suspend requested from client PID 1884 ('gsd-media-keys')
26 iul 23:30:46  systemd-logind: The system will suspend now!
26 iul 23:30:46  systemd-logind: Unit suspend.target is masked, refusing operation.
```

Won't-fix-ul rămâne tehnic corect pentru **S3**, dar **s2idle** e altceva și merită un experiment controlat.

### 5.2 Stare verificată (27 iul)

```
/sys/power/mem_sleep   →  s2idle [deep]      ← s2idle e disponibil, deep e selectat
/sys/power/state       →  freeze mem disk
masked: sleep.target, suspend.target, hibernate.target, suspend-then-hibernate.target
cmdline: … acpi_backlight=native mem_sleep_default=deep nvme.noacpi=1 i915.enable_dc=0
          nvme_core.default_ps_max_latency_us=0 reboot=pci
```

Doi dintre parametrii „de adăugat" propuși în analize (`i915.enable_dc=0`,
`nvme_core.default_ps_max_latency_us=0`) **sunt deja în cmdline**. `s2idle.target` **nu există** (E7) —
selecția s2idle se face din `mem_sleep_default=s2idle` sau scriind în `/sys/power/mem_sleep`.

### 5.3 🟡 Protocol de experiment (dacă vrei să încerci — P4)

- [ ] 1. **Cel mai ieftin test, fără GRUB, fără unmask:** `echo s2idle | sudo tee /sys/power/mem_sleep`,
         apoi — pentru că `systemctl suspend` ar fi refuzat (target masked) — testul real e
         `sudo sh -c 'echo freeze > /sys/power/state'` **din consolă**, cu nimic important deschis și cu
         jurnal persistent activ.
- [ ] 2. Dacă revine curat de 3-4 ori la rând (inclusiv după **10+ minute** în freeze, nu doar 5 secunde)
         → atunci merită `mem_sleep_default=s2idle` în GRUB + `unmask sleep.target suspend.target`.
- [ ] 3. **Rollback notat ÎNAINTE de test:** re-`systemctl mask …` + scoaterea parametrului din GRUB.
- [ ] 4. **De verificat la fiecare trezire:** ecran, tastatură (`applespi`), touchpad, WiFi (`brcmfmac` —
         cel mai probabil să nu revină), sunet, cameră. Și `journalctl -b -p err` după.

**Așteptare onestă:** s2idle e mai puțin dependent de firmware decât S3, deci are șanse reale. Dar pe
hardware Apple `brcmfmac` + `applespi` sunt exact componentele fragile la resume, iar cipul WiFi are deja
o problemă de sincronizare documentată (§2). Probabilitate de succes: rezonabilă, nu garantată.
Beneficiul practic e mic (laptopul e mereu pe AC; lid-close ține sistemul pornit cu ecranul blocat; iar
pornirea nedorită la capac e deja rezolvată — §7). De aceea **P4, nu P1**.

Elementele respinse din planurile de suspend (reset PCI pe discul de sistem, scriere 0 în RAPL,
`unmask s2idle.target`): vezi **E1, E2, E7** în Anexa C.

---

## 6. 🔴 Zgomot de log

### 6.1 DMAR — și de ce „fix-ul care păstrează IOMMU" nu există

Pe boot-ul curent: exact 3 mesaje `DMAR: Failed to find handle for ACPI object …`. Sursa lor sunt
intrările **ANDD** din tabela DMAR livrată de Apple:

```
DMAR: ANDD device: 1 name: \_SB.PCI0.I2C0     ← nu se rezolvă
DMAR: ANDD device: 3 name: \_SB.PCI0.I2C2     ← nu se rezolvă
DMAR: ANDD device: 8 name: \_SB.PCI0.SPI1     ← SE rezolvă (de-asta sunt 3 erori, nu 4)
DMAR: ANDD device: 9 name: \_SB.PCI0.UA00     ← nu se rezolvă
```

- ❌ `intel_iommu=on,igfx_off` **nu ajută** (E9): `igfx_off` scoate din translație **doar iGPU-ul** —
  n-are nicio legătură cu I2C/UART. Mesajele ar rămâne identice.
- ❌ `intel_iommu=off` — interzis (§2.4).
- ❌ Override de tabelă DMAR din initramfs (`CONFIG_ACPI_TABLE_UPGRADE`) — teoretic posibil, dar DMAR e
  consumată foarte devreme la boot; o tabelă greșit reconstruită poate dezactiva IOMMU sau împiedica
  boot-ul. **Risc real pentru 3 linii cosmetice.**

**Verdict: won't-fix.**

### 6.2 Restul limitărilor hardware — won't-fix (referință)

| Item | De ce nu se poate |
|---|---|
| **Suspend S3 / hibernare** | S3 nu se trezește fiabil pe NVMe+EFI Apple → blocat via `systemctl mask` (ETAPA 5e). Hibernarea ar moșteni aceleași probleme de resume. Pentru s2idle vezi §5 |
| **Broadcom WiFi/BT la repornire** | `reboot` nu power-cycle-ază cipul → poate rămâne mut (`Reset failed -110`). **Dar e doar un factor agravant, nu cauza unică** — vezi §1.3 (14% din boot-uri, jumătate după opriri lungi) |
| **Firmware Apple BCM4350 (WiFi/BT)** | Fișierele nu există public și nici în macOS pt. Mac-urile non-T2: calibrarea stă în OTP-ul cipului (citit deja de `brcmfmac`), datele regulatorii în firmware-ul Apple „bmac" (split-MAC, incompatibil). Investigat 8 iul 2026 — mesajele „failed to load …MacBookPro14,1.*" rămân cosmetice |
| **facetimehd PLL lock** | `Failed to lock S2 PLL` — bug upstream `patjak/facetimehd`; camera merge pe PLL alternativ |
| **ASPM PCIe** | `can't disable ASPM` — Apple BIOS restricționează; `pcie_aspm=off` ar avea alte efecte |
| **Apple ACPI / SGX noise** | `AE_ALREADY_EXISTS`, `_OSC/_PDC AE_NOT_FOUND`, SSDT duplicate, SGX disabled — Apple nu implementează metode ACPI standard / dezactivează SGX. Pur cosmetic |

---

## 7. ✅ Rezolvate (arhivă tehnică)

Probleme închise. Păstrate cu detaliul tehnic care contează, ca să nu fie re-deschise sau re-diagnosticate.

### 7.1 NVRAM `AutoBoot` — pornire nedorită la ridicarea capacului (PASUL 17 din optimize)

**Test fizic TRECUT** (19 iul, boot 16:39): cu `AutoBoot=%00` laptopul rămâne oprit la ridicarea
capacului; pornește doar din buton; valoarea supraviețuiește power-cycle-ului (`07 00 00 80 00` la
recitire după shutdown).

Mecanismul, integral verificat:
- pe Intel **fără T2**, comutatorul citit de SMC e variabila **binară** `AutoBoot` (`%00` = oprit,
  `%03` = pornit) — echivalentul `nvram AutoBoot=%00` din macOS;
- `auto-boot` **ASCII** (`false`/`true`) e varianta **T1/T2**: pe A1708 persistă în NVRAM dar e
  **inertă**. Prima încercare a eșuat exact din cauza asta, deși valoarea persista;
- `efivarfs` acceptă la scriere doar biții standard UEFI — masca `07 00 00 00`. Firmware-ul Apple
  raportează la **citire** `07 00 00 80` (bitul lui propriu), iar `efivarfs_file_write()` respinge cu
  `-EINVAL` orice bit din afara `EFI_VARIABLE_MASK`;
- variabilele sunt imutabile → `chattr -i` înainte de scriere.

Pasul 17 le scrie acum pe amândouă (binară + ASCII).

### 7.2 Kernel — de la 7.0.x la 7.1.6, prin `apt` normal

7.1.1/7.1.2 testate din experimental (22 iun → 11 iul, audit complet verde, zero regresii); `7.1.3-1` a
intrat în forky și meta `linux-image-amd64` s-a reconciliat curat (`7.1.3-1` > `7.1.2-1~exp1`);
kernelurile vechi (7.0.13, 7.1.2~exp1) purjate complet (dpkg + `/boot` + `/lib/modules` + `/usr/src`).
Verificat cap-coadă 11–12 iul: DKMS recompilate + semnate, 0 UBSAN/oops/DMAR-fault, toate driverele
încărcate, accelerare 3D (GBM pe i915) + VA-API (iHD) funcționale. De-acum kernelul vine prin
`apt dist-upgrade` normal.

**Actualizat 8 august: sistemul e pe `7.1.6+deb14-amd64`.** Nu mai e „single-kernel" — `7.1.3` a fost
păstrat deliberat ca rezervă, cu DKMS construit pentru amândouă (`facetimehd` și
`snd_hda_macbookpro`, verificat 8 aug). Upgrade-ul 7.1.3 → 7.1.6 a fost verificat cap-coadă pe
cameră: toate variantele de driver compilează fără warning, `v4l2-compliance` dă **exact** aceleași
50/7 ca pe 7.1.3, captura merge de la 320x240 la 1296x736.

⚠️ **Înainte de orice upgrade de kernel: `apt install linux-source-<X.Y>`** — altfel build-ul DKMS al
audio-ului pică. Vezi §7.9.

### 7.3 Curățenie repo experimental — **deja făcută** (reverificat 8 aug)

`/etc/apt/sources.list.d/` = `debian.sources`, `github-cli.list`, `google-chrome.sources`,
`vscode.sources`; `/etc/apt/preferences.d/` = **gol**. Niciun fișier `experimental*`. Nimic de făcut.

### 7.4 wireplumber #972 — rezolvat upstream (confirmat 19 iul)

Raportat 12 iul (<https://gitlab.freedesktop.org/pipewire/wireplumber/-/work_items/972>): **ambele**
hook-uri de linking crăpau cu erori Lua pentru stream-uri fără `media.type`. Fix: **MR 861** (Julian
Bouzas, „Fixes #972" — `cutils.getMediaType()` cu fallback „Unknown"), analizat și confirmat corect,
acum în master. Ajunge la noi odată cu un wireplumber **> 0.5.15** în Debian testing (azi: 0.5.15-1,
Installed = Candidate). Nimic de făcut local.
*(Textele `ISSUE_wireplumber_media_type.md` și `REPLY_wireplumber_972_mr861.md` au fost scoase din repo
după rezolvare — rămân în git history, commit `10e6c1d`.)*

### 7.5 Luminozitate „fantomă" (12 iul)

Ecranul se închidea/deschidea singur deși era setat la maxim: senzor ALS (`acpi-als`) +
iio-sensor-proxy + GNOME „Automatic Screen Brightness". Percepția de culori calde/reci era tot
backlight-ul (A1708 n-are True Tone). Fix: **ETAPA 5h** (ambient-enabled off + idle-dim off). Comenzi de
toggle manual în README.
*(Notă: senzorul apare în Linux doar ca `ACPI0008` / driver generic `acpi-als` — identificarea lui ca
„Intersil ISL29023" circulă prin documentații, dar **nu e verificabilă** de aici.)*

### 7.6 Audio rupt pe 7.0.10

Regresie **in-tree** în parser-ul HDA (UBSAN array-index-out-of-bounds → card nereg.), **exclusiv** pe
7.0.10. Reparat upstream în **7.0.12** (0 UBSAN); 7.0.10 dezinstalat. Driverul davidjo n-a avut nevoie
de patch (bug 100% in-tree). Codec confirmat live: `Cirrus Logic CS8409/CS42L83`. Analiza completă +
stack trace: git history.

### 7.7 Bluetooth „nu merge deloc" — soft-block rfkill persistat

`systemd-rfkill` restaura la fiecare boot un rfkill soft-block salvat (de la un disable/enable din GUI).
Dovedit **A/B** că `AutoEnable=true` singur **NU**-l învinge — restaurarea vine înaintea power-on-ului.
Fix: oneshot `bluetooth-rfkill-unblock.service` (unblock ordonat între `systemd-rfkill` și `bluetooth`)
+ `AutoEnable=true`. **ETAPA 5f** + `rfkill` în deps.
*(Fișierul de stare real: `/var/lib/systemd/rfkill/pci-0000:00:1e.0-platform-dw-apb-uart.2:bluetooth` —
nu `platform-applespi:bluetooth`, cum apare prin unele documentații.)*
**Alta** e problema din §1 (`-110` la init) — nu confunda cele două.

### 7.8 Restul

- **Fan floor `fan1_min=3500`** — udev scria ATTR înainte ca `applesmc` să expună atributul (race) →
  înlocuit cu oneshot `macbook-fan-floor.service` care așteaptă atributul. Verificat la reboot.
- **RAPL 22 W / 30 W** — Apple lasă PL1 la 100 W. Race rezolvat după **4 iterații** (`.path` cu inotify
  nu e fiabil pe sysfs; final: regulă udev + reinit thermald, ordonat față de thermald), validat 8/8
  boot-uri. Azi: `constraint_0_name=long_term` = 22 W, `constraint_1_name=short_term` = 30 W.
- **Reboot hang** — `reboot=pci` în GRUB (ETAPA 5a), testat.
- **Suspend hang S3** — toate sleep target-urile `masked` (ETAPA 5e), 4/4 confirmat.
- **`udevadm settle` hang pe 7.0.10** — bound `--timeout=5` (ETAPA 8b); era efect al bug-ului audio.
- **BT „down" după upgrade 7.0.10** — era stare Broadcom după repornire, **nu** kernel (vezi §1).

### 7.9 ⚠️ Capcana de la fiecare upgrade de kernel — `linux-source` întâi

**Nu e rezolvată, dar nici nu era scrisă nicăieri până pe 8 august.** Se pune aici pentru că se
manifestă doar la upgrade și e ușor de uitat exact atunci.

`install.cirrus.driver.sh` din `snd_hda_macbookpro` are nevoie de sursele `sound/hda` ale kernelului.
Preferă `/usr/src/linux-source-<X.Y>.tar.xz` (pachetul Debian `linux-source-<X.Y>`) și, dacă lipsește,
încearcă să descarce `linux-<X.Y>.tar.xz` de pe kernel.org — care **dă 404 și pentru `-rc`, și pentru
seriile EOL**. S-a întâmplat pe 4 iulie 2026 cu 7.0.13, când seria 7.0 a ieșit din suport.

```
# ÎNAINTE de orice upgrade de kernel:
sudo apt install linux-source-<X.Y>

# dacă build-ul a picat deja (pachete blocate în starea iF):
sudo apt install linux-source-<X.Y> && sudo dpkg --configure -a
```

`facetimehd` nu e afectat (nu descarcă nimic).

Raportat upstream, ambele scrise de aici, **ambele încă deschise** *(verificat 8 aug)*:
[issue #187](https://github.com/davidjo/snd_hda_macbookpro/issues/187) (7 comentarii) și
[PR #189](https://github.com/davidjo/snd_hda_macbookpro/pull/189), care face scriptul să prefere
sursa distribuției. Până se acceptă, pasul manual de mai sus rămâne obligatoriu.

- [ ] `⏳` De adăugat `linux-source-$(uname -r | cut -d. -f1,2)` în etapa 1 din
      `macbook-debian-setup.sh`, ca să nu depindă de memoria nimănui.

---

## 8. 🟡 Opriri spontane — cauză nedeterminată

> **Secțiune nouă, 8 august 2026.** Problema exista din 26 iulie și **nu figura în acest fișier**,
> deși e singura de aici fără niciun diagnostic. Investigația completă, cu jurnale și cronologie,
> e în `ISSUE_opriri_spontane.md` — **numai local pe laptop**, fiindcă e specifică acestei mașini
> și conține extrase brute de jurnal.

**Cinci opriri abrupte între 26 iulie și 5 august**, fără ca laptopul să fie oprit de utilizator și
**fără nicio urmă în jurnal** — journald se oprește odată cu mașina, deci ultimul lucru scris e o
intrare normală.

**Eliminate, cu dovezi:** termic (fără throttling în preajma opririlor), suspend (toate țintele
`masked`, verificat din nou 8 aug), panic (zero `Oops`/UBSAN din 8 iulie, verificat 8 aug), stocare
(NVMe fără erori), baterie/alimentare (laptopul e permanent pe USB-C), WiFi și DMAR.

**De ce nu se poate prinde acum:** watchdog-ul hardware e dezactivat de firmware-ul Apple, iar
pstore EFI nu conține nimic — deci oprirea nu e o panică. Rămâne o cădere de alimentare sau ceva
sub nivelul kernelului.

### 8.1 🟢 De făcut — netconsole (P1) `⏳ NEFĂCUT`

Singura cale de a obține o urmă: trimiterea jurnalului de kernel prin UDP către **al doilea PC din
LAN**, în timp real. Ce se scrie acolo nu se pierde odată cu mașina.

Nimic din asta nu e configurat încă *(verificat 8 aug)*.

### 8.2 Stare de fapt

**Nicio recidivă din 5 august.** Ultimele trei opriri (7 aug 08:17, 7 aug 19:39, 8 aug 08:09) au
toate `systemd-shutdown` în jurnal — **ordonate** *(verificat 8 aug)*. Trei zile nu înseamnă
rezolvat: intervalul dintre incidente a fost și de patru zile.

---

## 9. ❌ Ce NU se face — listă consolidată

| Propunere | Motiv | Detaliu |
|---|---|---|
| Reset PCI pe `0000:01:00.0` la resume | **E discul de sistem** — corupere de filesystem | E1 |
| Scriere 0 în `constraint_0_power_limit_uw` | N-are legătură cu NVMe; ar șterge limita de 22 W | E2 |
| `fan1_manual=1` | Scoate SMC-ul din buclă; fără rampă de siguranță dacă daemonul moare | E3 |
| Shim `LD_PRELOAD` pe `VIDIOC_REQBUFS` | Atacă stratul greșit — numărul de buffere curge de sus în jos | E6 |
| `intel_iommu=off` | Transformă DMA blocat în corupere silențioasă de memorie | §2.4 |
| `intel_iommu=on,igfx_off` pentru mesajele DMAR | `igfx_off` afectează doar iGPU; mesajele vin din ANDD | E9 |
| Override de tabelă DMAR din initramfs | Risc de boot/IOMMU pentru 3 linii de log | §6.1 |
| Extragerea `.hcd` din macOS | Nu rezolvă `-110`; ne-redistribuibil; transportul citat e greșit (USB vs UART) | E11 |
| Plafonare turbo / zswap / modificări thermald | Respinse pe datele de 3 h din 19 iul | §4.5 |
| DKMS fork pentru `brcmfmac` (ca primă opțiune) | Cost de întreținere mare; upstream e calea corectă | §2.5 |
| `systemctl unmask s2idle.target` | Ținta nu există în systemd | E7 |
| Politici Chrome `TabFreezingEnabled` / `BackgroundTracingAllowed` | Absente și din Chrome 150, și din **151** (reverificat 8 aug) — ignorate în tăcere | E8 |

---

## 10. Implementate în script (referință — 9 etape)

| # | Ce | Detaliu |
|---|---|---|
| 1-6 | Hardware base | deps (+`rfkill`, `iw`), audio CS8409, cameră FaceTime HD, GRUB/suspend fixes, **Bluetooth unblock+AutoEnable (5f)**, **WiFi: power-save off + `kernel.panic=10` (5g)**, **luminozitate fixă: auto-brightness ALS + idle-dim off (5h)**, VA-API |
| 7 | Touchpad UX | tap-to-click + natural scroll + disable-while-typing |
| 8 | Thermal | thermald + lm-sensors + RAPL PL1=22 W/PL2=30 W + fan floor 3500 RPM (oneshot service, race-safe) |
| 9 | Cosmetic / jurnal | GNOME media-keys (hibernate/playback-repeat) + usb-protection off + `applespi fnmode=1` |

`macbook-debian-optimize.sh`: 17 pași, dintre care **pasul 17** = NVRAM `AutoBoot` (§7.1).

---

## Anexa A — catalog „log noise" per boot

Pentru fiecare boot apar ~40 mesaje „error/warning". Toate sunt clasificate mai jos — **benigne cu o
singură excepție**, rândul marcat `A!` (Bluetooth `-110`), care apare pe **27 din 195** de boot-uri și
**nu** e zgomot. *(Cifre reverificate 8 august, 196 de boot-uri în jurnal.)*

| Cat | Mesaj jurnal | Frecvență | Cauza reală |
|---|---|---|---|
| C | `ACPI Error: AE_ALREADY_EXISTS, SSDT already loaded` | 19×/boot | Apple SSDT-uri duplicate; kernel ignoră al doilea |
| C | `ACPI Error: Aborting method \_PR.CPU*._OSC/PDC/GCAP/APPT` | ~10×/boot | Apple nu implementează metode ACPI standard |
| C | `ACPI BIOS Error: Could not resolve symbol [\_SB.OSCP]` | 2×/boot | Apple nu expune `_OSC` global |
| B | `DMAR: Failed to find handle … I2C0/I2C2/UA00` | 3×/boot | intrări ANDD Apple nerezolvabile (§6.1) |
| B | `Bluetooth: hci0: BCM: failed to write update baudrate (-16)` | 168/195 boot-uri | BCM4350 refuză upgrade baud; rămâne 115200, BT OK (§1) |
| **A!** | `Bluetooth: hci0: BCM: failed to write update baudrate (-110)` + `Reset failed (-110)` | **27/195 boot-uri** | **NU e benign: BT mort tot boot-ul** (§1) |
| B | `Bluetooth: hci0: BCM: firmware Patch file not found 'brcm/BCM.hcd'` | 168/195 | firmware patch opțional, nu există în Debian |
| B | `brcmfmac: failed to load …MacBookPro14,1.bin/.txt/.clm_blob` | ~8×/boot | caută variante Apple, cade pe generic (WiFi OK; fișierele nu există — §6.2) |
| C | `nvme0n2: partition table beyond EOD, truncated` | 1×/boot | al 2-lea namespace al NVMe-ului Apple (proprietar/gol); pe toate kernelele |
| C | `facetimehd: Failed to lock S2 PLL` | 1×/boot | bug upstream driver; camera merge pe PLL alternativ |
| C | `facetimehd: can't disable ASPM` | 1×/boot | Apple BIOS restricționează ASPM |
| C | `facetimehd: module verification failed - tainting kernel` | 1×/boot | DKMS nesemnat în keyring; benign fără Secure Boot. *(Azi modulul **e** semnat cu cheia DKMS — mesajul poate să nu mai apară.)* |
| C | `hci_uart_bcm: Unexpected ACPI gpio_int_idx / No reset resource` | 3×/boot | Apple ACPI lipsuri; fallback OK |
| A | `gsd-media-keys: Failed to grab … hibernate/playback-repeat` | 1×/login | rezolvat ETAPA 9 (keybinding golit) |
| A | `gsd-usb-protection: Failed to fetch USBGuard` | 2×/boot | rezolvat ETAPA 9 (usb-protection off) |
| C | `x86/cpu: SGX disabled or unsupported by BIOS` | 1×/boot | Apple BIOS dezactivează SGX |

**Concluzie:** zero crash/oops/UBSAN la un boot normal (0 din 8 iul încoace). Categoria A e curățată
(ETAPA 9); restul sunt Apple ACPI/firmware quirks inevitabile (C) sau cu trade-off nejustificat (B).
**Două excepții care NU sunt zgomot:** `-110` la Bluetooth (§1) și `Invalid packet id` la WiFi (§2).

---

## Anexa B — comenzi de verificare (read-only) + capcane

Toate cifrele marcate „verificat" vin de aici, rulate **27 iulie 2026**. Nimic nu modifică sistemul.

```bash
# --- termic / ventilator ---
for f in fan1_min fan1_max fan1_output fan1_input fan1_manual; do
  echo "$f = $(cat /sys/devices/platform/applesmc.768/$f)"; done
for z in /sys/class/thermal/thermal_zone*; do echo "$z: $(cat $z/type) = $(cat $z/temp)"; done
grep -H . /sys/class/hwmon/hwmon*/name          # numerotarea NU e stabilă între boot-uri
grep -H . /sys/devices/system/cpu/cpu0/thermal_throttle/*
head -1 /proc/pressure/{cpu,memory,io}

# --- RAPL ---
grep -H . /sys/class/powercap/intel-rapl:0/constraint_*_{name,power_limit_uw}

# --- WiFi: frecvența desincronizării ---
journalctl _TRANSPORT=kernel --since "2026-05-19" -g "Invalid packet id" | grep -c "Invalid packet id"
journalctl _TRANSPORT=kernel --since "2026-07-08 08:00" -g "Invalid packet id" | grep -c "Invalid packet id"
journalctl _TRANSPORT=kernel --since "2026-05-19" -g "Invalid packet id" -o short-iso \
  | grep "Invalid packet" | awk '{print substr($1,1,10)}' | sort | uniq -c

# --- Bluetooth: distribuția eșecurilor pe boot-uri ---
journalctl _TRANSPORT=kernel --since "2026-05-19" -g "update baudrate" | grep -oE '\(-[0-9]+\)' | sort | uniq -c
journalctl _TRANSPORT=kernel --since "2026-05-19" -g "BCM: Reset failed" | grep -c "Reset failed"
journalctl _TRANSPORT=kernel --since "2026-05-19" -g "BCM: chip id"     | grep -c "chip id"
hciconfig -a; bluetoothctl show
readlink -f /sys/class/bluetooth/hci0        # -> …/dw-apb-uart.2/… (transport UART, nu USB)

# --- Bluetooth: corelația eșec vs. durata opririi (§1.3) ---
# boot-urile ca JSON (index, boot_id, first_entry, last_entry în µs):
journalctl --list-boots -o json > boots.json
# boot_id-urile cu BT mort:
journalctl _TRANSPORT=kernel --since "2026-05-19" -g "BCM: Reset failed" -o json \
  | python3 -c "import sys,json; print('\n'.join(sorted({json.loads(l)['_BOOT_ID'] for l in sys.stdin})))"
# apoi: gap[i] = (first_entry[i] - last_entry[i-1]) / 1e6  → tabel de contingență la pragul de 45 s

# --- cameră ---
grep -n "FTHD_BUFFERS" /usr/src/facetimehd-0.7.0.1/fthd_drv.h
grep -rn "MAX_BUFFER" /usr/src/facetimehd-0.7.0.1/    # gol -> FTHD_MAX_BUFFER_SIZE nu există
apt-cache policy pipewire wireplumber

# --- suspend ---
cat /sys/power/mem_sleep /sys/power/state /proc/cmdline
systemctl list-unit-files | grep -E "sleep|suspend|hibernate"

# --- DMAR ---
journalctl -k -g "ANDD device"; journalctl -k -g "Failed to find handle"

# --- sursa kernel (verificarea punctului de inserție brcmfmac) ---
tar -tf /usr/src/linux-source-7.1.tar.xz | grep brcmfmac/msgbuf.c    # întâi calea exactă
tar -xf /usr/src/linux-source-7.1.tar.xz linux-source-7.1/drivers/net/wireless/broadcom/brcm80211/brcmfmac/msgbuf.c
grep -c "brcmf_msgbuf_rx_process"        …/msgbuf.c   # 0    -> funcția propusă nu există
grep -n  "brcmf_msgbuf_process_rx_complete" …/msgbuf.c   # 1147 -> numele real

# --- politici Chrome (validare nume pe binarul instalat) ---
for p in HighEfficiencyModeEnabled MemorySaverModeSavings TabDiscardingExceptions \
         TabFreezingEnabled BackgroundTracingAllowed; do
  strings -a /opt/google/chrome/chrome | grep -qx "$p" && echo "PRESENT $p" || echo "ABSENT  $p"; done

# --- igienă apt ---
ls /etc/apt/sources.list.d/ /etc/apt/preferences.d/
```

**Capcane de reținut:**

1. **`journalctl -k` implică `-b`** — doar boot-ul curent. Orice statistică istorică trebuie făcută cu
   `_TRANSPORT=kernel --since …`. Nota greșită „0 evenimente WiFi din 1 iulie" din versiunile vechi ale
   acestui fișier vine exact de aici.
2. **`journalctl … | grep -c`** numără și liniile de separator dintre boot-uri (`-- Boot … --`) — de aici
   al doilea `grep` cu textul explicit.
3. **`journalctl --list-boots | wc -l`** include linia de antet: N linii = **N−1 boot-uri**
   (la 8 august: 197 linii = 196 de boot-uri).
4. **Verbul de shutdown nu e persistat** — `journald` se oprește înainte de `systemd-shutdown`. Nicio
   linie `Rebooting.`/`Powering off.` în tot jurnalul. De aici nevoia hook-ului din §1.4.
5. **`dkms` nu e în `$PATH`-ul userului** — e la `/usr/sbin/dkms`.
6. **Numerotarea `hwmonN` nu e stabilă între boot-uri** — se rezolvă întotdeauna după `name`.

---

## Anexa C — propuneri respinse, cu dovada (ca să nu fie repropuse)

Analize externe generate pe 26 iul 2026 (fostele `hard_issues_deep_analysis.md`,
`todo_full_technical_breakdown.md`, `unresolved_todo_technical_plan.md`) au propus 11 lucruri greșite,
dintre care **3 ar strica sistemul** dacă s-ar executa. Concluzia lor globală („5 din 5 probleme sunt
100% solvabile") nu se susține pe datele reale.

### C.1 Ar strica sistemul

| # | Propunerea | De ce e greșită (dovadă) |
|---|---|---|
| **E1** | `echo 1 > /sys/bus/pci/devices/0000:01:00.0/reset` la wake — „resetează controllerul PCI NVMe" | `01:00.0` **este** controllerul NVMe pe care stă rootfs-ul: `Apple Inc. S3X NVMe Controller`. Un FLR pe discul de sistem, dintr-un script care rulează *de pe* acel disc = I/O eșuat în mijlocul resume-ului → în cel mai bun caz remount read-only, în cel mai rău corupere de filesystem. **De nu executat niciodată.** |
| **E2** | `echo 0 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw`, comentat „forțează NVMe în PS0" | N-are nicio legătură cu NVMe. E limita RAPL **long_term a CPU-ului**: `constraint_0_name = long_term`, `= 22000000`. Ar șterge exact setarea de 22 W pusă de ETAPA 8 și ar cere o limită de 0 W |
| **E3** | Daemon de ventilator care citește `thermal_zone0` ca temperatură CPU și scrie `fan1_manual=1` | **Două erori.** (a) `thermal_zone0` = **BAT0** (bateria, 36,3°C); CPU-ul e `thermal_zone1 = x86_pkg_temp` (62°C) — praguri de 75°C nu s-ar atinge niciodată, daemonul n-ar face nimic. (b) `fan1_manual=1` **scoate SMC-ul din buclă** (`README.md` avertizează explicit) — dacă daemonul moare, ventilatorul rămâne fixat, fără rampă de siguranță. Plus plafon propus 6200 < `fan1_max` real 7200. Design corect: §4.3 |

### C.2 Ar face fix-ul inoperant

| # | Propunerea | Realitatea verificată |
|---|---|---|
| **E4** | Patch `brcmfmac` în `brcmf_msgbuf_rx_process()`, apel `brcmf_msgbuf_pktid_find()` | Niciuna dintre funcții nu există în kernel 7.1 (`grep -c` = 0 în `msgbuf.c`). Numele reale: **`brcmf_msgbuf_process_rx_complete()`** (l. 1147) și **`brcmf_msgbuf_get_pktid()`** (l. 367). Patch-ul nu s-ar aplica. Versiunea corectată: §2.6 |
| **E5** | `dev_kfree_skb_any(skb)` pe un skb cu `nr_frags` corupt | Chiar asta e calea care crapă: `skb_release_data()` iterează `shinfo->nr_frags` și dereferențează fiecare fragment. Eliberarea unui skb cu `nr_frags = 125` **re-declanșează** GPF-ul pe care patch-ul vrea să-l prevină. Trebuie sanitizat **înainte** de eliberare |
| **E6** | Shim `LD_PRELOAD` pe `VIDIOC_REQBUFS` care „forțează PipeWire să aloce 8 buffere" | Atacă stratul greșit. `REQBUFS` e apelat de SPA **cu numărul deja negociat** cu clientul (tot 4). Un shim care umflă `req.count` în kernel nu spune nimănui de deasupra: SPA tot își dimensionează array-ul la 4, Snapshot tot le ține pe toate 4. **Dovadă:** driver nepatch-uit + `min-buffers=5` → **0 cadre** (`mmap_init -ENOMEM`) — numărul curge de sus în jos. În plus **driverul e deja la 8**. Pârghia reală e `min-buffers` pe client |
| **E7** | `systemctl unmask s2idle.target` | `s2idle.target` nu există în systemd. Țintele reale: `sleep`, `suspend`, `hibernate`, `hybrid-sleep`, `suspend-then-hibernate`. Selecția s2idle se face din `mem_sleep_default=s2idle` sau `/sys/power/mem_sleep` |
| **E8** | Politică Chrome cu `TabFreezingEnabled` + `BackgroundTracingAllowed` | Ambele **ABSENTE** din binarul Chrome 150 — ar fi ignorate în tăcere. JSON valid: §4.4 |
| **E9** | `intel_iommu=on,igfx_off` elimină `DMAR: Failed to find handle` păstrând IOMMU | `igfx_off` scoate din translație **doar iGPU-ul**. Mesajele vin din intrările **ANDD** (I2C0/I2C2/UA00) — nicio legătură cu grafica. Ar rămâne identice. §6.1 |
| **E10** | `PATCH[0]` în `dkms.conf` face patch-ul camerei să supraviețuiască reinstalării | Rezolvă doar jumătate: scriptul recreează **tot** `/usr/src/facetimehd-$VER` prin `cp -r` din clona proaspătă, deci și `dkms.conf` editat și `patches/` dispar. (`PATCH[0]`/`PATCH_MATCH[0]` **sunt** directive DKMS reale — problema e alta.) **Devenit fără obiect 8 aug:** patch-ul pe care trebuia să-l persiste a fost retras, vezi §3.4 |
| **E11** | `.hcd`-ul extras din macOS ar rezolva „inclusiv upgrade-ul de baudrate" | **Trei probleme.** (a) Calea citată e `IOBluetoothHostControllerUSBTransport.kext`, dar cipul e pe **UART**, nu USB. (b) `.hcd` e un patch aplicat **după** reset-ul reușit; pe boot-urile cu `-110` secvența moare înainte — nu apare nici `chip id 92`, nici căutarea `.hcd` (§1.2). (c) Eroarea `-16` are cauza în ACPI (`No reset resource`), nu în lipsa patch-ului |

### C.3 Afirmații nesusținute (nu greșite dovedit, dar nici verificabile)

| Afirmație | Observație |
|---|---|
| senzorul ALS e „Intersil ISL29023" | Din Linux se vede doar `ACPI0008` / driverul generic `acpi-als`. Neverificabil — de nu prezentat ca fapt |
| fișierul de stare rfkill = `platform-applespi:bluetooth` | Calea reală: `…/rfkill/pci-0000:00:1e.0-platform-dw-apb-uart.2:bluetooth`. Mecanismul descris e corect, numele nu (§7.7) |
| „Apple lasă PL1=100 W, **PL2=125 W**" | PL1=100 W e confirmat. PL2=125 W nu apare în nicio măsurătoare proprie |
| plafonul de 16 MB al driverului = `FTHD_MAX_BUFFER_SIZE` | Constanta **nu există** în sursă. Observația rămâne validă ca notă istorică; PR-ul cu 8 buffere pentru care conta nu s-a mai trimis (§3.4) |
| „SMC așteaptă 6-10 s peste 85°C"; „PROCHOT → 1,4 GHz" | Ordinul de mărime al lag-ului e confirmat de README (~20-30 s la sarcină bruscă), dar cifrele exacte nu vin din nicio măsurătoare. Monitorizarea de 3 h a măsurat altceva: ventilator ≥7000 RPM ~85% din timp și **un singur** episod de throttling |
| „100% solvabil" ×5 | Niciuna dintre cele 5 nu e demonstrat 100% solvabilă; 2 din 5 aveau propuneri care nu funcționează (E6) sau nu se aplică (E4) |

### C.4 Ce era corect în acele documente și s-a păstrat aici

NVRAM `AutoBoot` binar vs `auto-boot` ASCII, inclusiv masca `07 00 00 00` vs `07 00 00 80` și respingerea
cu `-EINVAL` (§7.1) · istoricul RAPL în 4 iterații (§7.8) · mecanismul race-ului rfkill (§7.7) ·
aritmetica bufferelor camerei, 1280×720 NV12 ≈ 1,38 MB × 8 ≈ 11 MB (azi fără obiect, §3.4) · regresia audio 7.0.10
(§7.6) · `PATCH[0]`/`PATCH_MATCH[0]` ca directive DKMS reale (E10) · ghidul de demontare A1708 —
pentalobe P5, T5 înăuntru, bateria deconectată prima, PTM7950 pentru die expus (§4.2).
