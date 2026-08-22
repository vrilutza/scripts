# TODO — plan tehnic & stare reală

Fișier unic: **ce e rezolvat**, **ce e deschis și se poate repara**, **ce e won't-fix** și **ce s-a respins tehnic**
(cu dovada, ca să nu fie repropus). Înlocuiește și absoarbe fostele `ANALIZA_TEHNICA_UNIFICATA.md`,
`hard_issues_deep_analysis.md`, `todo_full_technical_breakdown.md`, `unresolved_todo_technical_plan.md`.

| | |
|---|---|
| **Hardware** | MacBookPro14,1 (A1708), i5-7360U 2C/4T, Iris 640, 8 GB RAM, Apple S3X NVMe, BCM4350C0 (WiFi PCIe + BT UART), FaceTime HD, CS8409/CS42L83 |
| **Software** | Debian testing/forky, kernel `7.1.6+deb14-amd64` (+ `7.1.3` păstrat ca rezervă, DKMS construit pe ambele), pipewire 1.6.8-1, wireplumber 0.5.15-1, Chrome 151.0.7922.108, GNOME/Wayland |
| **Verificat pe viu** | **8 august 2026** — reverificare completă a cifrelor de mai jos pe **196 de boot-uri** (19 mai → 8 aug). Verificarea anterioară: 27 iulie, 173 de boot-uri. Ce nu s-a putut reverifica e marcat explicit `⏳ neconfirmat`. |
| **Stare de bază** | Hardware-ul e funcțional. Margini: 2 probleme cronice (BT, WiFi), 1 **nediagnosticată** (opriri spontane), 1 la upstream (cameră — 18 rapoarte trimise, 3 patch-uri acceptate în master, 2 laptopuri de test), 1 fizică (termic). Tabloul complet al rapoartelor: [secțiunea 0.1](#01-rapoarte-trimise-upstream--tablou). |

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
| 3 | Cameră — partajare de buffere fără `SPA_META_Busy` (aplicațiile îngheață) | 🔵 upstream | **3 patch-uri acceptate în master**; !2935 e gata de review din 15 aug | [3](#3--camera-facetime-hd--partajare-de-buffere-nesigură) |
| 4 | Sacadare cu 2 browsere + saturație termică | 🟢 | curățare fizică + tab-ul Chrome; abia apoi eventual daemon de ventilator | [4](#4--termic--sacadare) |
| 5 | Suspend / s2idle | 🟡 opțional | experiment reversibil, dacă chiar vrei suspend | [5](#5--suspend--s2idle) |
| 6 | Zgomot de log (DMAR / ACPI / SGX / nvme0n2) | 🔴 | nimic — vezi de ce „fix-ul fără dezactivarea IOMMU" nu funcționează | [6](#6--zgomot-de-log) |
| 7 | Tot ce e deja închis (NVRAM, audio, RAPL, rfkill, kernel…) | ✅ | nimic | [7](#7--rezolvate-arhivă-tehnică) |
| **8** | **Opriri spontane, fără urmă în jurnal** | 🟡 **activ** | netconsole către al doilea PC, ca următoarea să lase o urmă | [8](#8--opriri-spontane--cauză-nedeterminată) |

**Ordinea recomandată:**

| Prioritate | Acțiune | Efort | Risc | Câștig |
|---|---|---|---|---|
| **P1** | Curățare fizică ventilator + radiator (+ eventual PTM7950) | 1-2 h | mediu (demontare) | marja termică — măsura principală anti-sacadare |
| **P1** | **Netconsole către al doilea PC** ([secțiunea 8](#8--opriri-spontane--cauză-nedeterminată)) | 30 min | zero | singura cale de a prinde următoarea oprire spontană |
| **P2** | Identificat tab-ul Chrome de 10-13% (`Shift+Esc`) | 5 min | zero | ~10% CPU permanent |
| **P2** | Hook de shutdown care logează verbul (`reboot`/`poweroff`) | 15 min | mic | răspunde la întrebarea BT `-110` **și** la [secțiunea 8](#8--opriri-spontane--cauză-nedeterminată) |
| **P3** | Raport upstream `brcmfmac` cu dovezile din pstore | 1-2 h | zero | poate scoate riscul de panică definitiv |
| **P4** | Experiment s2idle (doar dacă vrei suspend) | 30 min | mediu, reversibil | lid-close real |
| **P5** | Daemon de ventilator pe `fan1_min` dinamic | 2 h | mic (dacă se face corect) | mic — doar cazul „rafală după liniște" |

*(Scos din listă pe 8 august: „persistența patch-ului `FTHD_BUFFERS=8`". Patch-ul nu mai există —
vezi [secțiunea 3](#3--camera-facetime-hd--partajare-de-buffere-nesigură).)*

**Nu e în tabelul de mai sus, dar e deschis:** [secțiunea 7.9](#79-️-capcana-de-la-fiecare-upgrade-de-kernel--linux-source-întâi) — capcana `linux-source` de la fiecare upgrade
de kernel. Stă în [secțiunea 7](#7--rezolvate-arhivă-tehnică) fiindcă acolo o cauți, la upgrade, nu în lista de probleme active.

---

## 0.1 Rapoarte trimise upstream — tablou

Toate raportate de aici. Ține-le într-un singur loc: patru s-au și rezolvat, iar despre restul e ușor
să uiți că există. Stare verificată prin API pe **16 august 2026**.

⚠️ **Niciunul dintre cele trei patch-uri acceptate nu e într-o versiune lansată.** Verificat cu
`git merge-base --is-ancestor` pe ramura `1.6`: !2933, !2934 și !2941 sunt toate doar în master. De
reținut înainte de a-i spune cuiva că „are deja" vreuna dintre reparații.

| Unde | Ce | Stare |
|---|---|---|
| [wireplumber #972](https://gitlab.freedesktop.org/pipewire/wireplumber/-/work_items/972) | hook-urile de linking crăpau pentru stream-uri fără `media.type` | ✅ **rezolvat upstream** (MR 861, în master) — [secțiunea 7.4](#74-wireplumber-972--rezolvat-upstream-confirmat-19-iul) |
| [pipewire !2933](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2933) | `module-client-node` ignora flag-ul `READ` la enumerarea parametrilor | ✅ **acceptat în master** `c81badc1b`, în aceeași zi în care a fost trimis (30 iul) |
| [pipewire !2941](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2941) | reciclare de buffer sub încuietoarea buclei + scurgere `buf_to_release` | ✅ **acceptat în master** `30ff8da17`, neatins, fast-forward |
| [pipewire !2934](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2934) | gardă de depășire în `spa_v4l2_use_buffers()` | ✅ **acceptat în master** `7a8e49384` (14 aug), rebazat de `wtaymans`, autor păstrat; recenzat de `pobrn`, singura lui cerere (`got`→`provided`) inclusă |
| [pipewire !2935](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2935) | copiere când pool-ul se golește | 🔵 gata de review din 15 aug, acum `6fe4eaca2`, CI verde. Descriere rescrisă 16 aug; pe **17 aug** mesajul de commit corectat — citatul lui `wtaymans` era greșit (`starting` în loc de `stating`), referința `#5190` scoasă ca nesusținută, corp 63 → 43 rânduri. Codul neatins |
| [pipewire !2950](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2950) | o sursă cu interval de dimensiuni era deschisă la **cea mai mică**; plus pasul raportat greșit | 🔵 **cod schimbat pe 16 aug**: `908a66c05` → `14619fffa`, default-ul vine acum din `CROP_BOUNDS` (nativ), nu din maxim. CI verde. `pobrn` a pus două întrebări; la a doua **avea dreptate**, iar răspunsul meu a fost editat ca s-o spună |
| [pipewire !2951](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2951) | `pipewiresrc` repornea fluxul la renegocieri care nu cereau nimic | 🔵 trimis 15 aug, acum `1da2d9604`. Descriere rescrisă 16 aug; pe **17 aug** mesajul de commit corectat — spunea că defectul cere „*any source that advertises a range*", ceea ce infirmasem deja: intervalele pot veni din aval. Codul neatins. **Zero comentarii de la cineva din afară** |
| [pipewire !2954](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2954) | enumerarea `SPA_PARAM_Props` cădea din cauza unui singur control | 🔵 trimis 19 aug cu **două** comituri; **decuplat pe 21 aug** la unul singur, `23f742e59` (forma lui `pobrn`, cu `Suggested-by:`). Al doilea comit — citirea non-fatală — a plecat pe ramura locală `v4l2-nonfatal-read`, fiindcă era **nemăsurat**. Între timp a fost măsurat pe un driver scris anume ([secțiunea 3.2p](#32p--21-august--2954-decuplat-și-comitul-al-doilea-măsurat-pe-un-driver-scris-anume)) și s-a dovedit că are cauză proprie. `mergeable`, CI verde, 👍 de la `rmader`, zero comentarii |
| [facetimehd #334](https://github.com/patjak/facetimehd/pull/334) | AE se așează în 200 ms, nu într-o secundă, la fiecare STREAMON | 🔵 trimis 15 aug, peste [#328](https://github.com/patjak/facetimehd/pull/328) |
| [wireplumber #986](https://gitlab.freedesktop.org/pipewire/wireplumber/-/work_items/986) | un nod de cameră `vivid` nu primește niciodată session item, deci clientul pică cu `target not found` | 🔵 **trimis 17 aug**, **primul răspuns de întreținător** în aceeași zi: `julian` a cerut testare cu !876. Testat — presupunerea lui (activare eșuată) e **falsă**; **cauza reală e în PipeWire**: `spa_v4l2_enum_controls()` înregistrează un control cu payload, `VIDIOC_G_CTRL` dă EINVAL și toată enumerarea `Props` cade. Patch de 7 linii, A/B alternat, plus trei probe de infirmare, toate trecute. ✅ **Răspuns postat 18 aug** (nota `3619570`) și **descrierea corectată în patru locuri** — rândul `1.0.5 → works` retras, secțiunea „Where I stopped" înlocuită cu „Cause". Verificat după: comentarii 1 → 2. Defectul e în **PipeWire**, se reproduce de la **1.3.81** încolo ([3.2h](#32h--17-august-seara--986-cauza-găsită-și-în-alt-loc-decât-credeau-toți)–[3.2m](#32m--18-august--postat-si-o-corectie-proprie-105-nu-arata-defectul)). Patch încă **local**, MR abia după ce răspunde |
| [pipewire #5363](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/5363) | raportul de bază | 🔵 deschis, fără răspuns de mentenanț din 11 iulie; !2935 îl **închide automat la merge** (`Closes #5363`, verificat prin API) |
| [snapshot #367](https://gitlab.gnome.org/GNOME/snapshot/-/work_items/367) | viewfinder înghețat pe primul cadru | 🔵 deschis, **1 upvote** — altcineva a confirmat bug-ul (8 aug). Mentenantul a propus [!464](https://gitlab.gnome.org/GNOME/snapshot/-/merge_requests/464) (`min-buffers=8`); infirmat cu măsurători pe 10 aug — pe camera asta dă **0 cadre**, nu e un fix. !464 e încă deschis, nemerged |
| [facetimehd #328…#334](https://github.com/patjak/facetimehd/pulls) | șapte PR-uri de driver (vezi [secțiunea 3.3](#33--driver--șapte-pr-uri-la-patjakfacetimehd)) | 🟡 toate deschise, zero review-uri — dar **`patjak` a răspuns pe 15 aug**, primul semn de la întreținător: nu primise notificări, se uită peste ele. **Toate verificate prin măsurătoare pe 17 aug**, master curat față de master+PR ([3.3a](#33a--17-august--fiecare-patch-verificat-prin-măsurătoare)); doar #332 rămâne netestabil. Menționează că cineva ar fi trimis driverul în kernelul upstream; **n-am putut confirma** (lore și patchwork blochează accesul automat, iar căutările dau doar Apple ISP pentru M-series, alt hardware) — întrebat direct pe #328 |
| [snd_hda_macbookpro #187](https://github.com/davidjo/snd_hda_macbookpro/issues/187) | `install.cirrus.driver.sh` pică pe Debian (`.tar.xz`) și pe kerneluri `-rc` (404 la kernel.org) | 🔵 deschis, 7 comentarii |
| [snd_hda_macbookpro #189](https://github.com/davidjo/snd_hda_macbookpro/pull/189) | fix: folosește sursa de kernel instalată local | 🔵 deschis, 1 comentariu |

**Patru bug-uri deschise ale altora**, la care am contribuit fără să le revendicăm.

| Unde | Ce | Ce am adus |
|---|---|---|
| [pipewire #4797](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/4797) | `buffer was not recycled` cu `x264enc`, două webcam-uri USB, pool ~16 | `@arun` descrie exact mecanismul și numește fix-ul ca nescris încă. **Reprodus pe 16 aug** cu un encoder adevărat, pe a doua mașină |
| [pipewire #2489](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/2489) | deschis din 2022, același tip de pipeline | workaround-ul confirmat acolo e `always-copy=true` — adică fix ce automatizează !2935 |
| [pipewire #4174](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/4174) | producătorul suprascrie un buffer pe care consumatorul încă îl ține | deschis din **august 2024**, un singur răspuns, argumentat exclusiv din citit cod. **Comentat pe 16 aug** (nota `3617445`) cu primul reproducător: bugetul din „*consumers are supposed to use them before they are reused*" e `pool / rată de cadre`, adică ~0,7 s la pool 4 |
| [pipewire #4863](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/4863) | același defect, ridicat de `pobrn` în august 2025 pentru noduri async | **Comentat pe 16 aug** (nota `3617448`): mai multe buffere nu elimină cursa, doar lungesc fereastra — ceea ce susține punctul lui `pobrn` rămas fără răspuns |

**Doar #5363 e revendicat** (`Closes`). Restul sunt doar menționate sau comentate: a închide automat
bugul altcuiva pe baza unei deduceri, fără să-l fi testat pe hardware-ul lui, e exact felul de
afirmație care strică încrederea într-un patch bun.

⚠️ **Ultimele două nu erau consemnate nicăieri în acest repo** până pe 8 august, deși
`#187` descrie exact capcana de la **fiecare** upgrade de kernel pe mașina asta: dacă
`linux-source-<X.Y>` nu e instalat **înainte**, build-ul DKMS al audio-ului pică. Vezi [secțiunea 7.9](#79-️-capcana-de-la-fiecare-upgrade-de-kernel--linux-source-întâi).

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
      mereu pe AC). **Efect real: nul** — vezi [secțiunea 2.2](#22-datele-reale--mitigarea-din-8-iulie-nu-a-oprit-desincronizarea). Se păstrează, nu strică nimic.
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
| **B. Raport upstream** (linux-wireless/netdev) cu dump-ul pstore din 7 iul | 1-2 h | zero | **Recomandat (P3), `⏳ nefăcut`.** Ai ceva ce raportorii obișnuiți n-au: panică completă capturată în pstore + **93** de evenimente datate. Aceeași strategie a funcționat deja de patru ori: wireplumber #972 (rezolvat) și pipewire !2933, !2941, !2934 (toate în master) — vezi [secțiunea 0.1](#01-rapoarte-trimise-upstream--tablou) |
| **C. Hardening local prin DKMS** ([secțiunea 2.6](#26-patch-defensiv--versiunea-corectă-dacă-se-merge-pe-b-sau-c)) | mare | mediu | **Doar ca ultimă soluție.** `brcmfmac` e in-tree; un fork DKMS cere blacklist pe modulul din kernel, rebuild la fiecare update, taint suplimentar |
| **D. Adaptor USB WiFi (~15 €)** | 15 € | zero | Ocolire completă a cipului Broadcom. Plan B dacă redevine frecvent + panici |
| ❌ **`intel_iommu=off`** | — | — | **Interzis** ([secțiunea 2.4](#24-mitigări-deja-aplicate-8-iul-live--etapa-5g-în-script)) |

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

### 3.2 🔵 PipeWire — trei patch-uri acceptate, trei în review

Vezi tabloul complet din [secțiunea 0.1](#01-rapoarte-trimise-upstream--tablou). Pe scurt:

| MR | ce | stare |
|---|---|---|
| **!2933** | `module-client-node` nu verifica flag-ul `READ` la enumerarea parametrilor | ✅ **în master** (`c81badc1b`), luat în ziua în care a fost trimis |
| **!2941** | ordinea încuietorilor în `buffer_recycle()` + repararea scurgerii `buf_to_release` | ✅ **în master** (`30ff8da17`), luat neatins, fast-forward |
| **!2934** | gardă de depășire în `spa_v4l2_use_buffers()` | ✅ **în master** (`7a8e49384`, 14 aug), rebazat la merge, autor păstrat |
| !2935 | copierea când pool-ul se golește | 🔵 **gata de review** (15 aug), `9a118621e` pe `adfb948ec`, CI verde |
| !2950 | dimensiunea implicită a unei surse cu interval | 🔵 `14619fffa` — **cod schimbat pe 16 aug**, vezi [3.2d](#32d--16-august--campania-de-validare-și-un-patch-de-al-nostru-infirmat) |
| !2951 | repornirea fluxului la renegocieri inutile | 🔵 `c72c54f15`, CI verde, **zero comentarii din afară** |

!2933 a fost acceptat în aceeași zi, !2941 la ~2 ore după ce a fost pus. Asta răspunde la întrebarea
veche „de ce nu ne răspunde nimeni": **răspund**, dacă patch-ul e mic, izolat și măsurat. !2934 a
avut singurul review propriu-zis — `pobrn`, două runde de întrebări tehnice, apoi o singură cerere
de formulare (`got` → `provided` în mesajul de log); aplicată, și a intrat trei zile mai târziu.

**!2935 a ieșit din Draft pe 15 august.** Draft-ul era auto-impus, cu un motiv scris în MR: decizia
de politică — *când* anume ar trebui `pipewiresrc` să înceteze să partajeze — nu părea a fi a
noastră. Se hrănea singur: pe GitLab, un MR în Draft e filtrat din cozile de review, deci așteptai o
părere de la exact cine nu-l vedea. Descrierea propune acum un răspuns (`PRODUCER_HEADROOM 3`, cu
raționamentul și măsurătorile), în loc să lase întrebarea deschisă. Zero postări noi în fir: nota
veche a fost editată, iar restul sunt note de sistem.

⚠️ **Atenție dacă reiei proba lui !2934: „daemonul moare 3/3" nu se mai reproduce.** Descrierea
MR-ului, din 31 iulie, spune că daemonul nepatchat cade la fiecare rulare. Pe master-ul din 15
august, cu același build injectat și aceeași negociere, **supraviețuiește 3 din 3**. Nu e o
contrazicere: e o *citire* în afara tabloului, iar dacă pagina de după e mapată nu pică nimic —
depinde de aranjarea heap-ului, nu de patch. Defectul e real și reparația e în master; ce nu mai e
valabil e criteriul. Proba din banc folosește acum unul determinist, verificat pe ambele variante la
`spa.v4l2:5`: amândouă scriu `got 4 buffers` pentru o negociere de 2 buffere, dar numai build-ul cu
patch scrie `provided 4 buffers, using 2`.

Evidența completă — bancul de test, măsurătorile, ce s-a retras și de ce — stă în
`pipewire-5363/`, **numai local pe laptop** (nu e publicată: e material de lucru, nu documentație
de proiect). De curățat după ce upstream se pronunță, mai puțin `camera-fix/`, care aparține
proiectului ăstuia. Ce contează pentru cineva din afară e deja în MR-urile și PR-urile linkate
mai sus.

### 3.2b 🔵 Pornirea lentă a camerei — și de ce era vina noastră

**Simptom:** dai click pe cameră și stă câteva secunde până apare imaginea. Investigat pe 15 august,
după ce a fost descris ca senzație, nu ca bug.

Descompunerea pornirii lui GNOME Snapshot, din jurnalul `pipewiresrc`:

| t | ce se întâmplă |
|---|---|
| 0,00–0,35 s | pornirea aplicației + portalul xdg |
| 0,35 s | conectare #1, format fixat `320x240` |
| **1,55 s** | primul cadru — 1,19 s de la conectare |
| 1,54 s | `reconfigure` din aval → deconectare → conectare #2 |
| 2,84 s | al doilea cadru, alt `reconfigure` → conectare #3 |
| ~4,1 s | abia acum fluxul devine continuu |

Trei cauze, măsurate separat, **niciuna cauza celeilalte** (plan factorial complet, 2×2):

1. **Driverul doarme o secundă la fiecare `STREAMON`** — `fthd_isp.c`, `msleep(1000)` „Needed to
   settle AE", din commit-ul de bring-up din 2015. Măsurat cu parametru de modul: la 100 ms primul
   cadru e deja corect, la 50 ms vine negru. Trimis ca [#334](https://github.com/patjak/facetimehd/pull/334) cu 200 ms.
2. **`pipewiresrc` repornea fluxul degeaba.** Scurtătura care exista deja upstream compara caps-uri
   fixate cu caps-uri care încă au intervale, deci nu se declanșa niciodată. Trimis ca
   [!2951](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2951).
3. **Vizorul rula la 320x240** — implicitul unei surse cu interval era minimul, iar preferința se
   pierdea la conversia în caps GStreamer. Trimis ca
   [!2950](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2950).

⚠️ **Simptomul l-a adus PR-ul nostru [#331](https://github.com/patjak/facetimehd/pull/331).** Izolat
prin revocarea acelei singure comiteri peste restul seriei, cu Snapshot pe stiva din `/usr`:

| | cu #331 | fără #331 |
|---|---|---|
| format | 320x240 | **1296x736** |
| conectări la pornire | 3 | **1** |
| continuu de la | ~4100 ms | **~1500 ms** |
| `Skipping renegotiation` în jurnal | 0 | **2** |

Ultimul rând e dovada: scurtătura upstream **funcționează** când caps-urile sunt fixate. #331 e
corect — driverul chiar acceptă intervalul — dar a expus două defecte vechi din PipeWire
(`853a46120` din 2024 și zona atinsă de `b8d533446` din 2025, plus scurtătura scrisă de `e2e8cf794`
în 2024). Niciunul nu e al nostru.

De-asta reparația nu a fost retragerea lui #331: aia ar fi ascuns simptomul și ar fi lăsat două
bug-uri care lovesc orice cameră care raportează un interval. #331 are acum o notă care spune exact
asta, cu cifrele de mai sus.

### 3.2c 🔵 Al doilea laptop — ce a schimbat

Pe 15 august am pus bancul și pe Lenovo IdeaPad Z580 (Ubuntu 24.04, webcam **UVC**, driver
`uvcvideo`, dimensiuni **discrete**, `REQBUFS` dă până la **32** de buffere). Detalii de mediu în
memoria proiectului; ce a produs, pe scurt:

**#5363 nu e al camerei noastre și nu e recent.** Se reproduce acolo pe **PipeWire 1.0.5** din
distribuție: pool de 16, merge până la 14 ținute, moare la 16. `always-copy=true` îl repară — adică
exact confirmarea cerută raportorului din [#4797](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues/4797),
obținută acum pe hardware propriu.

**!2935 verificat pe pool de 16**, cazul pe care descrierea MR-ului îl declara netestabil: se
declanșează la 13 ținute, cum e proiectat, și **nu costă nimic** acolo (64 de cadre în ambele
variante); la 16 și 20 salvează fluxul (38 și 37 de cadre față de 16-și-apoi-tăcere).

**De ce a devenit ușor de atins.** `DEFAULT_MIN_BUFFERS` din `pipewiresrc` era 8 și o cameră v4l2
negocia **16** buffere. `e81fb7732` (mai 2025) l-a coborât la 1 — corect, fiindcă 8 rupea negocierea
cu libcamera. Aceeași cameră negociază acum **4**. Măsurat pe Lenovo, aceeași cameră, același build:
`min-buffers` nesetat → 4, `=8` → 16.

⚠️ **Corectat pe 16 august, era greșit și aici și în descrierea MR-ului:** formularea „până în 1.4"
lasă impresia că seria 1.4 e nevinovată. Valorile reale, citite din arbore: 8 până la **1.4.3**
inclusiv (13 mai 2025), 1 din **1.4.4** (29 mai 2025, retroportare `eda42ef2f`, la patru zile după
commit-ul din master) și din **1.6.0** (27 ian 2026). Deci **1.4.4–1.4.11 sunt și ele afectate**.

Deci blocajul se atinge acum când consumatorul ține **patru** cadre, nu șaisprezece. Nu s-a stricat
nimic — s-a micșorat marja. Și întoarcerea nu e disponibilă: 8 rupe libcamera, iar pe o cameră
plafonată la 4 dă zero cadre, exact cum am arătat la snapshot!464.

**Neregresie pentru !2950 și !2951** pe cameră cu dimensiuni discrete: tot identic, în afară de un
rând care s-a **îmbunătățit** — proba cu `reconfigure`, 30 → 54 de cadre. Ceea ce a infirmat propria
mea explicație din !2951: defectul nu cere o sursă care anunță un interval, intervalele pot veni din
aval (`videoconvert` e de ajuns). Descrierea MR-ului a fost corectată.

### 3.2d 🔵 16 august — campania de validare, și un patch de-al nostru infirmat

Nouă puncte plănuite, opt făcute. Ce contează:

**`vivid` a infirmat politica din !2950.** Driverul virtual de test din kernel (`modprobe vivid`) dă
o a doua sursă cu interval, independentă de `facetimehd`. A confirmat ambele defecte — și a arătat
că alegerea noastră de default era greșită. `ENUM_FRAMESIZES` pe un dispozitiv cu scaler raportează
ce poate **întinde scaler-ul**, nu ce livrează sursa: `vivid` oferă 16x16 – 16384x8640 dintr-o sursă
de 720x576. A cere maximul acolo nu e „rezoluție mai mare", e 720x576 mărit până la 283 MB pe cadru,
măsurat: 20,5 fps față de 25,6.

V4L2 răspunde separat la întrebarea corectă — `VIDIOC_G_SELECTION` cu `CROP_BOUNDS` dă dreptunghiul
sursei, și distinge cele trei intrări `vivid` (720x576, 720x576, 1280x720) acolo unde
`ENUM_FRAMESIZES` raportează același interval pentru toate. Commit rescris: default = nativ, cu
revenire la maxim pentru dispozitivele fără API-ul de selecție. `facetimehd` nu-l implementează, deci
dă tot 1296x736 — **toate măsurătorile de pe MacBook rămân valabile**.

Două rute eliminate prin măsurătoare, ca să nu se mai reia: intervalele de cadru nu pot mărgini nimic
(`vivid` pretinde 25 fps la orice dimensiune, inclusiv la maxim), iar `VIDIOC_G_FMT` e definitiv mort
— formatul e stare globală pe dispozitiv care supraviețuiește lui close/open, deci orice proces
anterior o otrăvește.

**#4797 reprodus cu un encoder adevărat**, după două modele greșite pe care le-am măsurat și
aruncat — amândouă merită știute de oricine încearcă să reproducă:

* un element care **convertește** între sursă și consumator face defectul **imposibil**
  (`videoconvert` eliberează bufferul din pool imediat, nici măcar partajarea forțată nu blochează);
* un consumator **doar lent** nu ajunge — sursa se auto-reglează la ritmul lui.

Mecanismul e „are nevoie de N cadre înainte să elibereze primul, cu N > pool", adică `rc-lookahead`.
Pe camera reală cu pool de 16: stock se oprește **fix la 16 cadre**, patch-ul duce pipeline-ul de la
**0 la 38 de cadre codate**.

**!2935 curat sub sanitizer.** ASAN + UBSAN, zero rapoarte, cu control pozitiv verificat. Fără
scurgeri (528 de octeți diferență față de nepatchat, toate în contexte eliberate la ieșire). Soak de
10 minute: 2617 cadre copiate, RSS plat la 49 kB.

**Blocajul lovește 1.6.8**, seria lansată curentă, **cu configurația implicită** — pool 4, consumator
care ține 4, mort în 0,79 s; 50 de cadre cu patch-ul. `!2941` și `!2935` se aplică prin cherry-pick
curat pe 1.6, în ordinea aia. Până acum descrierea spunea doar că patch-ul *se aplică* pe 1.6.8.

**Totul rula deja pe DMA-BUF** — `uvcvideo` suportă `EXPBUF` și alocatorul văzut de client e
`dmabufallocator0`. Ramura „DMA-BUF necopiabil" nu se poate obține de la o cameră v4l2 (plugin-ul
pune întotdeauna `MAPPABLE`), deci a fost verificată prin injecție de defect: patch-ul refuză să
copieze și cade înapoi pe comportamentul de bază, fără crăpătură.

**#4174/#4863 au acum un reproducător.** Ții **un** buffer și îi recalculezi amprenta: conținutul se
schimbă sub tine, cu control pozitiv (copiere → niciodată) și cu aritmetica `pool / rată de cadre`
care se potrivește. Ambele fire erau argumentate exclusiv din citit cod, de doi ani respectiv unul.

**Publicat prin editare, nu prin postări noi** — la cererea explicită: descrierile celor trei MR-uri
rescrise în loc (!2935 s-a și **scurtat**, 9681 → 7688 caractere), titlul lui !2950 aliniat la
commit, și răspunsul meu către `pobrn` **editat** ca să spună că măsurătoarea i-a dat lui dreptate.
Verificat după: numărul de comentarii neschimbat peste tot.

### 3.2e 🔵 17 august — cele trei defecte „ale altora", triate

Din cele trei observate pe 16 august, **unul s-a dovedit al meu**:

* **`pipewiresrc` cu caps ANY nu negociază** — **RETRAS**, nu e defect. Caps ANY merge pe master pe
  ambele camere reale (UVC pe Lenovo, `facetimehd` pe MacBook). Eșua doar împotriva unui nod
  `vivid` declarat de mine prin `context.objects`, care n-are proprietățile unuia creat de monitor.
  O notă veche din `repro.py` susținea că pe master e stricat; era nesusținută și am corectat-o la
  sursă.
* **WirePlumber nu leagă `vivid`** — **al lor**, izolat prin schimbarea fiecărei variabile separat
  și raportat ca [wireplumber #986](https://gitlab.freedesktop.org/pipewire/wireplumber/-/work_items/986).
* **`update_controls` → `-EINVAL` pe `vivid`** — ~~rămâne neraportat, e zgomot în log, cu efect
  practic aproape nul~~. **Greșit, corectat pe 17 aug seara:** este exact cauza lui #986. Vezi
  [3.2h](#32h--17-august-seara--986-cauza-gasita-si-in-alta-parte-decat-credeau-toti). Lecția:
  „zgomot în log" a fost o presupunere, nu o măsurătoare — n-am urmărit niciodată unde ajunge
  acel `-EINVAL`.

Recitirea raportului înainte de postare a prins ceva ce merită reținut: reproducerea scrisă inițial
**nu reproducea** — rulată exact așa cum era scrisă, clientul reușea, fiindcă orice altă cameră
funcțională maschează complet defectul. Condiția lipsă („`vivid` să fie singura cameră") e acum
îngroșată în raport.

Rămas nefăcut din plan: nimic — kernelul de debug cu KASAN/lockdep e făcut (secțiunea 3.2f).
`netconsole` (secțiunea 2) e pe jumătate: receptorul merge, emițătorul pornește, dar rămâne de
verificat dacă transmisia rară trece.

### 3.2g 🔵 17 august — verificare pe stivă curată, și curățenie în ce am trimis

Întrebare pusă direct: *defectele chiar se reproduc, sau le-am dedus din banc — care ar putea fi el
problema?* Întemeiată, fiindcă exact în ziua precedentă „caps ANY" se dovedise a fi tocmai așa ceva.

**Regula impusă: niciun cod construit local, niciun daemon privat, nicio variabilă de mediu.** Doar
pachete de distribuție, în sesiunea reală, cu mediul curățat explicit și cu plugin-ul GStreamer
verificat de fiecare dată că vine din `/usr`. Două stive independente: Debian + PipeWire 1.6.8 +
WirePlumber 0.5.15, și Ubuntu + PipeWire 1.0.5 + WirePlumber 0.4.17.

| MR | ce susține | ce a ieșit pe stivă curată |
|---|---|---|
| !2935 | fluxul moare când consumatorul ține tot pool-ul | 1/2/3 ținute → 145 cadre; **4 ținute → 4 cadre, mort la t=1,29 s** |
| !2950 | clientul fără preferință primește minimul | `facetimehd` 320x240–1296x736 → **320x240**; `vivid` 16x16–16384x8640 → **16x16** |
| !2951 | renegociere inutilă care demontează fluxul | 3 pauze × ~1,30 s pe 1.6.8, 3 × ~0,73 s pe 1.0.5, caps-urile sursei neschimbate |

Pentru !2951 și **mecanismul**, nu doar simptomul: `GST_DEBUG=pipewiresrc:4` pe binarul din
distribuție arată `gst_pipewire_src_negotiate: set format` de trei ori în plus, de fiecare dată cu
exact același format, iar „Skipping renegotiation" nu apare niciodată.

**Toate trei se reproduc fără niciun cod de-al nostru. Niciunul nu poate fi pus pe seama bancului.**
Detaliile în `pipewire-5363/results/VERIFICARE-STIVA-CURATA.md`.

⚠️ **Capcană găsită tot aici.** Prima rulare a lui !2951 pe 1.0.5 a fost cu `vivid` și a arătat
**zero pauze** — era gata să raportez „nu se reproduce pe 1.0.5". Schimbasem însă două variabile
deodată, versiunea și camera. Reluat pe aceeași stivă cu camera reală: trei pauze. `vivid` e driver
virtual, `STREAMON` la el e instantaneu, deci remontarea fluxului nu costă nimic măsurabil.
**Defectul e prezent, costul nu se vede** — cine încearcă să reproducă pe un dispozitiv virtual va
zice „nu reproduc", și va avea dreptate despre simptom, greșit despre defect.

**Curățenie în cele trei MR-uri**, toată prin editarea primului post, zero postări noi:

* scoase liniile de tipul „*Two commits, +66/−5, on …*" din toate trei — se văd în GitLab deasupra
  descrierii, iar repetate în text nu fac decât să rămână în urmă. Chiar rămăseseră: `+36/−4` era
  vechi după rescrierea patch-ului.
* corectate **mesajele de commit**, care intră permanent în istoric: citatul greșit al lui
  `wtaymans` și referința nesusținută `#5190` din !2935, plus formularea din !2951 care sugera că
  defectul cere o sursă cu intervale.

### 3.2f 🔵 Kernel de depanare pe Lenovo — KASAN, lockdep, KFENCE

Compilat mainline **7.1.8** (aceeași versiune cu MacBook-ul, deci relevant direct) cu `KASAN`,
`PROVE_LOCKING`, `DEBUG_VM`, `DEBUG_LIST`, `DEBUG_ATOMIC_SLEEP` și `KFENCE_NUM_OBJECTS=16383`.
Instalat ca `7.1.8-kasan`, **nu** implicit — `GRUB_DEFAULT` e fixat explicit pe `7.0.0-28-generic`,
fiindcă intrarea „Ubuntu" din GRUB alege mereu cel mai recent kernel, adică ar fi ales tăcut pe cel
de 2–5× mai lent și ar fi falsificat orice măsurătoare ulterioară.

**Rezultat pe căile noastre: zero rapoarte.** Stres v4l2 pe camera reală, pe `vivid` inclusiv
alocări de 3840x2160, plus sarcina PipeWire completă. Ambele detectoare au control pozitiv verificat:
o depășire de redzone (`slub_debug`) și o **citire** în afara limitelor (`KASAN`), amândouă
raportate corect.

Singurul lucru găsit e un impas potențial AB-BA în `nouveau`, la suspendarea automată a GPU-ului —
dar e [cunoscut din 2021](https://gitlab.freedesktop.org/drm/nouveau/-/issues/101), aceeași pereche
de mutex-uri, și n-are legătură cu camera.

⚠️ **Kernelul Ubuntu are deja `KFENCE` compilat, dar e inutil fără rebuild:** pool-ul de 255 de
obiecte se umple la boot cu alocări de lungă durată, și de atunci refuză tăcut orice eșantion — în
prima fază a arătat `skipped allocations (capacity): 121648` și **zero** eșantioane reale. Verifică
întotdeauna acel contor înainte să crezi un „zero bug-uri".

### 3.3 🔵 Driver — șapte PR-uri la `patjak/facetimehd`

Toate deschise, `MERGEABLE`, bazate direct pe `364b1c6`, și verificate că se aplică și **toate
împreună**, fără conflict. `patjak` a răspuns pe 15 august — primul semn de la întreținător — și
spune că se uită peste ele; vezi [3.3a](#33a--17-august--fiecare-patch-verificat-prin-măsurătoare).

| PR | Ce repară |
|---|---|
| [#328](https://github.com/patjak/facetimehd/pull/328) | `break` lipsă la AWB, `FTHD_BUFFERS` în loc de literalul 4, `mdelay`→`msleep` (o secundă de CPU ars la fiecare STREAMON) |
| [#329](https://github.com/patjak/facetimehd/pull/329) | controalele erau aruncate la fiecare STREAMON; `ALIGN(width, 7)` — nu e putere a lui doi, deci era pur și simplu stricat |
| [#330](https://github.com/patjak/facetimehd/pull/330) | decupare **centrată**: orice rezoluție sub senzor întorcea colțul din stânga-sus |
| [#331](https://github.com/patjak/facetimehd/pull/331) | `ENUM_FRAMESIZES` raportează intervalul real, nu o singură dimensiune |
| [#332](https://github.com/patjak/facetimehd/pull/332) | un singur timeout de firmware lăsa camera fără buffere până la reîncărcarea modulului |
| [#333](https://github.com/patjak/facetimehd/pull/333) | **coruperea de memorie**: până la 4095 de octeți scriși *înaintea* bufferului, când acesta nu începe pe graniță de pagină |

| [#334](https://github.com/patjak/facetimehd/pull/334) | așteptarea AE de la fiecare STREAMON: 1000 ms → 200 ms *(stivuit peste #328, îl conține)* |

Driverul instalat pe mașină e **exact** suma lor *(verificat prin `diff -rq` pe 8 aug)*, construit
pentru ambele kerneluri. Scriptul de instalare/revenire e local, în
`pipewire-5363/camera-fix/install-pr333.sh` (nu e publicat — vezi nota din [secțiunea 3.2](#32--pipewire--trei-patch-uri-acceptate-al-patrulea-în-review)).

### 3.3a 🔵 17 august — fiecare patch verificat prin măsurătoare

Aceeași întrebare ca la PipeWire: patch-urile chiar repară ce pretind, sau am dedus pe alocuri?

**Metoda:** șapte module compilate din git, fiecare din HEAD-ul exact al PR-ului său, peste un master
**verificat că e chiar `364b1c6`** și că nu conține patch-urile noastre. Md5-uri distincte, tipărite
înainte de fiecare măsurătoare, `insmod` cu cale explicită, variantele alternate.

| PR | master | cu patch-ul |
|---|---|---|
| #328 | 1198 ms, **1130 ms CPU ars (94% dintr-un nucleu)** | 1231 ms, **50 ms CPU (4%)** |
| #329 `TRY_FMT(321)` | **321** — nealiniat, trece neatins | **328** |
| #329 luminozitate 128→255 | 14,4 → **14,0** (niciun efect) | 14,5 → **141,0** |
| #330 | colț **0,996** / centrat −0,028 | colț −0,070 / centrat **0,996** |
| #331 | `Discrete 1296x736`, Scaling **FAIL** | `Stepwise 320x240–1296x736 step 8/1`, Scaling **OK** |
| #333 | **8176** linii „scris înaintea bufferului" | **0** |
| #334 | 1198 / 1231 ms | **463 / 461 ms** |

Fiecare repetare confirmă; la #330 corelațiile se inversează complet. Detalii în
`pipewire-5363/results/VERIFICARE-FACETIMEHD.md`.

**#332 nu se poate testa** — cere un timeout de firmware, care nu se declanșează la comandă. Rămâne
verificat doar prin recitire de cod.

**Ce am corectat:** #328 avea în corpul PR-ului o justificare greșită pentru `break` — spunea că
devine capcană „*as soon as anything calls `s_ctrl` for every control*". Fals: cazul cade în
`default: break;`, identic cu un `break;`, indiferent câte apeluri se fac. Mesajul commit-ului
spunea de la început formularea corectă, deci istoricul era curat; corectat doar corpul, prin
editare.

⚠️ **Două capcane, ambele ale mele.** Arborele `fthd-master-src` din cache **avea deja patch-urile
noastre**, deci orice verificare pe el ar fi fost fără valoare. Și prima serie de compilări a
etichetat drept „master" un arbore aflat de fapt la `a9c99dd` — master cu toate PR-urile — fiindcă
`checkout` eșuase tăcut peste un index murdar. Prinsă doar pentru că tipăream hash-ul fiecărui build;
altfel aș fi comparat master cu master și aș fi raportat că patch-urile n-au niciun efect.

**Precizie de spus:** proba mea măsoară `STREAMON` plus un cadru plus pornirea procesului, nu
`STREAMON` singur ca tabelul din #334 — aceeași direcție și mărime, dar nu aceeași măsurătoare.

### 3.3b 🔵 Cele șapte împreună — și o declarație lipsă găsită astfel

Fiecare patch fusese verificat separat; asta verifică ce ar lua efectiv un întreținător.

| | master curat | toate cele șapte |
|---|---|---|
| `framesizes` | `Discrete 1296x736` | `Stepwise 320x240–1296x736 step 8/1` |
| `TRY_FMT(321)` | **321** | **328** |
| STREAMON | 1222 ms, **1040 ms CPU (85%)** | **496 ms**, 20 ms CPU (4%) |
| luminozitate 128→255 | 53,1 → **51,8** (niciun efect) | 53,7 → **180,6** |
| decupare | **COLȚ STÂNGA-SUS** | **CENTRAT** |
| scrieri înaintea bufferului | **8176** | **0** |
| `v4l2-compliance` | 51 reușite, **6 eșecuri** | 52 reușite, **5 eșecuri** |
| captură 1296x736 | 30/30 cadre | 30/30 cadre |

Toate efectele apar simultan, niciun patch nu-l anulează pe altul, iar `v4l2-compliance` **scade** de
la 6 eșecuri la 5 — deci setul nu introduce regresii, ci repară un test în plus.

⚠️ **Ce a scos la iveală runda asta, și e cel mai important lucru din ea:** prima coloană arată că
`facetimehd` de pe `patjak/master` raportează **o singură dimensiune discretă**. Intervalul vine din
**#331, un patch de-al nostru încă în review acolo**. Adică toate cifrele despre `facetimehd` din
descrierea lui **!2950** depindeau de un driver modificat local, iar un recenzent PipeWire cu un
MacBook și driverul publicat **n-ar fi reprodus nimic** — și ar fi închis MR-ul ca nereproductibil.

!2951 declara deja asta („*by reverting one commit in its driver*"); !2950 nu. Corectat prin editarea
descrierii, cu trimitere la #331 și cu precizarea că `vivid` nu cere nimic, fiind în arborele
kernelului. **Piciorul solid al lui !2950 rămâne `vivid`**, nu `facetimehd`.

**Trei defecte în scriptul de test**, toate de aceeași formă — verificate într-un mod care nu putea
găsi defectul: variabilă neinițializată sub `set -u`, funcție care returna starea lui `tee` în loc de
a lui `insmod`, și `fs.protected_regular=2` care împiedică root-ul să scrie fișiere din `/tmp` lăsate
de o rulare anterioară ca utilizator. `bash -n` nu execută nimic, iar o rulare ca utilizator nu poate
găsi o problemă care apare doar sub root.

### 3.3c 🔵 Auditul de declarare pe cele trei MR-uri PipeWire

Întrebarea care l-a declanșat: dacă !2950 se sprijinea nedeclarat pe un driver modificat local, are
și !2935 aceeași problemă?

| MR | depinde de driver modificat? | era declarat? |
|---|---|---|
| **!2950** | **da** — intervalul de dimensiuni vine din #331, încă în review | **nu** → corectat, cu trimitere la #331 și cu precizarea că `vivid` nu cere nimic |
| **!2951** | da | **da**, deja: „*by reverting one commit in its driver*" |
| **!2935** | **nu** | acum spune explicit că nu cere nimic out-of-tree |

La !2935 am procedat invers decât la !2950: în loc să adaug o precauție, am **eliminat îndoiala prin
măsurătoare**. Driverul publicat încărcat direct (identitate verificată: `Discrete 1296x736`,
`TRY_FMT(321) → 321`), pragul cade în același loc:

| cadre ținute | driver publicat | driver cu patch-urile noastre |
|---|---|---|
| 1 / 2 / 3 | 146 / 145 / 146 | 145 / 144 / 145 |
| **4** | **4 cadre, mort la t=1,26 s** | 4 cadre, mort la t=1,29 s |
| 6 / 12 | 4 / 4 | 4 / 4 |

Pool-ul de patru e `FTHD_BUFFERS` al driverului, adică upstream. Precizat în descriere, fiindcă
preîntâmpină exact întrebarea pe care un recenzent și-o va pune după ce citește precauția din !2950.

Precizat tot acolo și că sursa I420 din proba cu `x264enc` era un `v4l2loopback`, nu o cameră, iar
pool-ul de acolo e 2–3, **sub pragul patch-ului** — altfel „2 frames, then dead" se putea citi ca
„patch-ul nu rezolvă cazul din #4797".

### 3.2h 🔵 17 august seara — #986: cauza găsită, și în alt loc decât credeau toți

**Primul răspuns de la un întreținător de WirePlumber.** `julian` a presupus în #986 că nodul
`vivid` *nu reușește să se activeze* și a cerut să testăm cu
[!876](https://gitlab.freedesktop.org/pipewire/wireplumber/-/merge_requests/876) — între timp
în master ca `35d5d199` — care face hook-ul `monitor/v4l2/create-node` asincron și raportează
eroarea activării.

Testat pe **Lenovo**, cu `35d5d199` luat prin cherry-pick **exact peste `bf2a473d`**, comitul pe
care fusese raportat bug-ul, ca să nu se schimbe decât o singură variabilă.

**Presupunerea lui e falsă.** Cu !876 aplicat nu apare niciun mesaj: activarea nodului reușește,
iar nodul chiar există în graf (`44 Video/Source v4l2_input.platform-vivid.0`). Eșecul e mai
târziu, în object manager:

```
wp-proxy  <WpNode:44> error res:-22 enum params id:2 (Spa:Enum:ParamId:Props) failed
wp-object-manager  on_proxy_ready: proxy activation failed: Object activation aborted
```

Lanțul complet, urmărit până la `ioctl`:

1. `spa_v4l2_enum_controls()` comută **doar pe `queryctrl.type`**, iar `VIDIOC_QUERY_EXT_CTRL`
   raportează un **array de întregi** ca `V4L2_CTRL_TYPE_INTEGER`. Măsurat pe controlul vinovat:
   `"S32 2 Element Array" type=1 elems=2 nr_of_dims=1 flags=0x1100 (HAS_PAYLOAD|…)`.
2. E înregistrat deci ca proprietate `Int` scalară.
3. `spa_v4l2_update_controls()` îl citește cu `VIDIOC_G_CTRL` → **EINVAL** (nucleul nu permite
   `G_CTRL` pe controale cu payload). Doar `EACCES` e tratat ca netatal.
4. `SPA_PARAM_Props` întoarce `-EINVAL` **în întregime**.
5. WirePlumber cere `WP_OBJECT_FEATURES_ALL` pe fiecare nod, deci activarea obiectului e
   abandonată → `node-added` nu se emite → `create-item.lua` nu vede nodul → `target not found`.

Deci **defectul e în PipeWire, nu în WirePlumber**, deși simptomul apare la WirePlumber.

Sondă scrisă ca să refacă exact selecția făcută de spa: din **53** de controale înregistrate pe
`vivid`, **exact unul** pică la `VIDIOC_G_CTRL`; pe camera UVC reală, **0 din 9**. De aceea numai
`vivid` e afectat — și de aceea am crezut o zi întreagă că e „zgomot în log".

**Reparație**, `~/pw-test/wt-ctrl` branch `v4l2-payload`, comit `216c897f5`, +7 linii: se sare
peste controalele cu `V4L2_CTRL_FLAG_HAS_PAYLOAD`. Flag-ul e păstrat și pe calea de rezervă
`VIDIOC_QUERYCTRL`, deci merge și pe drivere fără `QUERY_EXT_CTRL`.

A/B alternat, ambele variante din același comit și aceeași configurare meson, cu md5-ul
plugin-ului **chiar încărcat de daemon** citit din `/proc/PID/maps` la fiecare rulare:

| rulare | plugin | `enum_params` eșuat | session item | client |
|---|---|---|---|---|
| 1, 3 | master | 2 | 0 | `target not found` |
| 2, 4 | +patch | 0 | 1 | OK, 10 cadre |

Non-regresie pe camera reală: `pw-cli enum-params PropInfo` + `Props` pe UVC, master vs patch —
**ieșire identică**, 150 de linii. Pe `vivid`, singura diferență e dispariția intrării
`"S32 2 Element Array"`, adică exact controlul care nu putea fi citit oricum.

**A doua observație, pentru WirePlumber:** eșecul e complet mut la nivelul implicit de log —
`on_proxy_ready()` (`lib/wp/object-manager.c:780`) folosește `wp_debug_object`. !876 nu acoperă
cazul, fiindcă activarea din monitor reușește; nodul e aruncat după aceea. Un `wp_warning_object`
acolo ar fi făcut diagnosticul imediat — exact ce voia `julian` de la !876.

### 3.2i 🔵 17 august, târziu — auditul bancului cerut înainte de a crede rezultatul

Întrebarea pusă: *„verifică bancul a 11-a oară — ce te face așa sigur că defectul e cel
diagnosticat și că patch-ul e corect?"* Șase probleme găsite, una dintre ele gravă.

* **`git stash` întoarce 0 și când n-are ce pune deoparte.** Rețeta de construire a variantelor
  era `git stash && ninja && cp`. După ce patch-ul a fost **comis**, `git stash` n-a mai avut ce
  lua, `&&` a mers mai departe, și a copiat varianta patch-uită peste `/tmp/v4l2-master.so`.
  **Ambele „variante" erau același fișier.** Prins doar fiindcă tipăream md5-urile. Înlocuit cu
  `fa-variante.py`: fiecare variantă se face prin `git checkout <comit> -- <fișier>`, cu
  verificare **în sursă** înainte de compilare și cu asertarea că toate au md5-uri distincte.
* **Trei directoare de build erau învechite** — dar doar ca mtime: după rebuild complet,
  md5-ul fiecărui artefact e neschimbat. Măsurătorile anterioare n-au fost afectate, și în plus
  se vede că build-urile sunt reproductibile.
* **Sonda mea ocolea verificarea bancului** (`whichplugin.py`), fiindcă rula `gst-launch`
  direct. Reintrodusă.
* **`wt-ctrl` era configurat altfel** decât build-ul principal (`libcamera` pornit). Aliniat —
  și după aliniere, varianta „master" are `.text` și `.rodata` **identice la bit** cu plugin-ul
  build-ului principal, compilat separat din același comit. Deci brațul de control chiar e
  master-ul upstream.
* **`pkill -f` s-a potrivit iar cu propria mea linie de comandă** — a șasea oară în sesiune, de
  data asta omorându-mi sesiunea SSH în mijlocul unei probe.
* **`gst-launch` nu iese după `stream error`** — rămâne blocat; vechea sondă ascundea asta în
  spatele lui `timeout`.

**Probe construite ca să răstoarne diagnosticul**, cu predicțiile scrise înainte, două treceri, a
doua în ordine inversă:

| variantă | ce schimbă | rezultat |
|---|---|---|
| `log` | master + sondă în `update_controls` | pică, și spune **care** control: `ctrl_id=0098f90f errno=22`, unul singur |
| `tolerant` | master + `EINVAL` tratat ca `EACCES` — alt cod, controlul **rămâne** în `PropInfo` | **repară** → legătura e „enumerarea `Props` eșuează", nu „controlul a dispărut" |
| `sabotat` | fix + eșec forțat al enumerării | **strică la loc** → simptomul urmărește eșecul, nu vreun efect secundar al patch-ului |

Verificat și pe **WirePlumber master de azi** (`35d5d199`): master pică, fix merge, de două ori.

### 3.2j ⚠️ 17 august — o eroare în ce **postasem deja** pe #986

Auditul a scos la iveală că randul din raportul trimis —

> | 1.0.5 (Ubuntu) | 0.4.17 (Ubuntu) | implicit | **works** — links and streams, YUY2 320x180 |

— **nu se reproduce**. Cu reproducerea scrisă în același raport (`media.role=Camera`), `vivid`
pică la fel și pe stiva distribuției. Ce merge acolo e `pipewiresrc` **simplu**, fără proprietăți
de flux; aproape sigur asta măsurasem, fără să notez că schimbasem comanda.

Controlul care exclude explicația comodă („0.4.17 n-ar ști de rolul de cameră"): pe aceeași
stivă, **camera UVC reală merge cu exact aceeași comandă**.

Și atunci, o singură variabilă schimbată — daemon master + **WirePlumber 0.4.17 al
distribuției**, alternat de patru ori: cu plugin-ul master clientul pică, cu patch-ul merge.

**Concluzia corectă: defectul e în PipeWire și se vede pe fiecare versiune de WirePlumber
încercată.** Diferă doar cât de departe ajunge simptomul. Fraza din raportul postat, *„it is
neither the profile nor the PipeWire version"*, a fost dedusă dintr-un rând măsurat greșit și
trebuie corectată când răspundem. Corectarea e deja în draft.

### 3.2k 🔵 Câte drivere reale au defectul: **niciunul**

Căutat în `linux-source-7.1`, `drivers/media` + `drivers/staging/media`. Forma periculoasă e
precisă: un control **array** al cărui **tip de bază** e `INTEGER`, `BOOLEAN` sau `MENU` —
singurele trei pe care `spa_v4l2_enum_controls()` le înregistrează. Toate celelalte (`U8`, `U16`,
`U32`, `INTEGER64`, `STRING`, tipurile compuse) cad deja pe `default: goto next`.

Toate cele 14 fișiere cu `.dims`: `go7007` (U8), `tw5864` și `solo6x10` (U16), `si4713` (U32),
`vsp1` lut/clu (U32) și hgt (U8), `dw100` (U32), `hantro`/`rkvdec`/`visl`/`cedrus`/`mtk-vcodec`
(structuri compuse) — **niciunul atins**. Singurul din tot arborele e `vivid`, cu
`"S32 2 Element Array"` (`V4L2_CTRL_TYPE_INTEGER`, `.dims = { 2 }`). Chiar și celălalt array al
lui `vivid`, `"S64 5 Element Array"`, e `INTEGER64` și e deja sărit.

Din afara arborelui: `facetimehd` folosește numai `v4l2_ctrl_new_std` cu controale scalare;
`v4l2loopback` nu e instalat pe niciuna dintre mașini.

Confirmat și în nucleu de ce pică exact acolo: `ctrl->is_int = !ctrl->is_ptr && type !=
INTEGER64` (`v4l2-ctrls-core.c:2173`), iar `v4l2_g_ctrl()` întoarce `-EINVAL` dacă `!is_int`
(`v4l2-ctrls-api.c:797`). `WRITE_ONLY` dă `EACCES` — singurul caz pe care codul spa îl tratează.

**Deci severitatea pentru utilizatorul cu cameră reală e zero azi.** Ce rămâne: `vivid` e
driverul de test standard, folosit tocmai ca să se probeze stivele de cameră; codul e greșit
oricum, fiindcă un singur control necitibil dărâmă enumerarea `Props` a întregului nod; și
aceeași cădere apare fără niciun array — pentru un control `VOLATILE`, eroarea întoarsă de
`g_volatile_ctrl` al driverului se propagă până la `VIDIOC_G_CTRL` (`v4l2-ctrls-api.c:788`), deci
un driver USB care întoarce `-EIO` ar dărâma la fel toată enumerarea. De aceea varianta
`tolerant` merită propusă **pe lângă** sărirea controalelor cu payload, nu în locul ei.

### 3.2m 🔵 18 august — postat, și o corecție proprie: 1.0.5 **nu** arată defectul

Verificând reproducătorul **înainte** de postare, am dat peste ceva ce infirma o frază scrisă de
mine cu o zi înainte: *„codul fatal e în toate versiunile, în 1.0.5 e chiar mai rău"*. Codul chiar
e acolo, dar **defectul nu se manifestă pe 1.0.5**: enumerarea controalelor folosea un buffer de
pod **static**, care dă peste margine (`can't create Control 'Test Pattern' overflow 1080`) și se
oprește înainte să ajungă la controlul vinovat. Builder-ul dinamic a intrat cu `2c1ec7fa4`
(9 iulie 2024), prima versiune care îl conține fiind **1.3.81**.

Ce rămâne și ce cade:

* **Rămâne valid** experimentul decisiv — același daemon master, schimbat doar plugin-ul v4l2,
  rezultatul se răstoarnă și cu WirePlumber master, și cu 0.4.17.
* **Nu mai atribui nouă** eșecul clientului măsurat ieri pe stiva 1.0.5 + 0.4.17: acolo `Props`
  nu eșuează deloc, deci acel eșec are altă cauză, **neidentificată**. Nu l-am pus în ce am
  postat. Dacă îl scriam, trimiteam dezvoltatorii pe pistă greșită — exact ce voiai evitat.

Reproducătorul final e de două comenzi, **fără WirePlumber și fără client media**, și nu cere ca
`vivid` să fie singura cameră: `pw-cli enum-params <nod> PropInfo` arată `"S32 2 Element Array"`,
iar `pw-cli enum-params <nod> Props` întoarce `res:-22 (Invalid argument)`.

Postat ca **un** comentariu (nota `3619570`, 04:17 UTC) plus **o** editare a descrierii în patru
locuri: nota de sus, rândul retras, concluzia trasă din el, secțiunea „Where I stopped" (cu
tabelul de proprietăți, care era o pistă falsă) înlocuită cu „Cause", și rândul din „Versions".
Verificat după: comentarii **1 → 2**, toate cele trei afirmații vechi dispărute.

Textul postat: `results/NOTA-986-POSTAT.md`. **Patch-ul rămâne local**; MR-ul la PipeWire, cu două
comituri, abia după ce răspunde.

### 3.2n 🔵 18 august — toate patch-urile deschise, retestate pe master-ul de azi

Cerut: *„testează PipeWire master la zi cu patch-ul tău și ia și patch-urile trimise de noi care
așteaptă review, să vedem dacă mai sunt valabile și dacă fixează ce spun că fixează."*

Punctul de plecare, verificat înainte de orice măsurătoare: `origin/master` = `adfb948ec`, **n-a
mișcat**; cele trei MR-uri aduse prin `refs/merge-requests/N/head` (deci **exact ce văd
recenzenții**, nu ramurile mele locale); toate trei se aplică curat, **CI verde**, `mergeable`,
fără conflicte; iar cele cinci comituri se combină într-un singur arbore fără conflict.

| MR | ce pretinde | stock | cu patch | verdict |
|---|---|---|---|---|
| **!2935** | nu blochează fluxul când consumatorul ține bufferele | 4 cadre, mort la t=0,78 s (×2) | 53 și 65 cadre, ultimul la t≈5,9 s | **valid** |
| **!2951** | nu repornește fluxul la renegocieri inofensive | 3 pauze de ~715 ms (×2) | **0 pauze**, 119 cadre vs ~90 | **valid** |
| **!2950** SPA | implicit = nativul, pasul e pasul | `16x16`, pas `16384x8640` | `1280x720`, pas `2x2` | **valid** |
| **!2950** GStreamer | clientul fără preferință primește implicitul | `16x16` | `720x576` / `1280x720` | **valid** |
| **v4l2-payload** | `vivid` devine utilizabil | `Props` EROARE, `target not found` | `Props` DATE, 74 cadre | **valid** |

Fiecare rând alternat, cu identitatea verificată la fiecare rulare (daemonul din
`/proc/PID/maps`, plugin-ul GStreamer prin `whichplugin.py`). Punct de funcționare de control la
!2935 (`hold=1`, care trebuie să meargă peste tot): 78 / 45 / 78 cadre. !2951 **nu** repară
blocajul și !2935 **nu** repară repornirile — fiecare face exact ce spune, nici mai mult.

Partea GStreamer a lui !2950 măsurată pe **două** configurații native diferite ale lui `vivid`
(HDMI 1280x720 și TV 720x576): valoarea urmărește `CROP_BOUNDS` în ambele. Iar în arborele
combinat, `vivid` devine utilizabil **și** primește dimensiunea nativă în aceeași rulare — deci
patch-urile nu se încurcă.

**Ce a prins bancul de data asta:** stare de plecare greșită (rămăsese `vivid` singura cameră, de
la verificarea reproducătorului, deci prima calibrare a dat `target not found` peste tot);
un filtru pentru `EnumFormat` care nu se potrivea cu nimic în **ambele** brațe; și `spa-ctrl`
rămas cu varianta de probă. Toate trei prinse înainte să producă un număr fals. La final,
`verifica-bancul.sh` iese 0 pe toate cele opt verificări, cu zece directoare de build la zi.

**Două capcane noi de la `vivid`**, salvate și în memorie: intrarea 3 (HDMI) livrează **un singur
cadru** prin PipeWire, fiindcă cere DV timings pe care sursa v4l2 nu le tratează (driverul direct
dă 30 de cadre repede) — pentru numărat cadre se folosește intrarea 1 (TV), unde ies 99 în 4 s;
iar intrarea 0 (webcam) merge sub 1 fps chiar la nivel de driver.

Măsurători complete: `results/MATRICE-18aug.md`. **Nimic nu s-a trimis**: patch-ul v4l2 rămâne pe
`wt-ctrl:v4l2-payload`, MR-ul abia după ce răspunde `julian`.

### 3.2o 🔵 19 august — tichetul mutat în PipeWire (#5431), și un fix propus de upstream identic cu al nostru

`wireplumber#986` a fost **închis și mutat** de `julian` în `pipewire#5431` pe 18 aug 12:43 UTC
(`moved_to_id=155435`), cu descrierea și nota noastră intacte. Două lucruri noi acolo:

- **`julian`** confirmă diagnosticul și explică de ce mesajul din object manager stă la `debug`:
  a fost coborât intenționat (`3fa4165513`), fiindcă apare normal când clienții creează și distrug
  noduri repede. Propune, în schimb, un semnal `"object-error"` în object manager, ca monitorul V4L2
  să avertizeze doar pentru nodurile video — cc `gkiagia`. E design pe partea lor; punctul nostru
  („e tăcut la nivelul implicit") a fost preluat, nu respins.
- **`pobrn`** propune, într-un comentariu, exact schimbarea pe care o măsurasem:
  `if (queryctrl.flags & (V4L2_CTRL_FLAG_DISABLED | V4L2_CTRL_FLAG_HAS_PAYLOAD))`. Aceeași funcție,
  același loc, același predicat — noi îl pusesem ca `if` separat, el l-a împăturit în cel existent.
  **Nu e alt fix, e același fix.** Confirmare independentă, nu divergență. Antetul lui de hunk
  (`@@ -1439,7 +1443,7 @@`) nu se potrivește cu master, deci e o sugestie scrisă din arborele lui,
  nu un patch trimis: **nimeni nu a deschis MR** (verificat prin API — niciun MR legat de #5431 în
  afară de `wireplumber!876`, deja merged).

**Ramura pregătită:** `wt-ctrl:v4l2-payload-v2`, peste `adfb948ec` (master n-a mișcat nici azi),
două comituri: `23f742e59` *do not expose compound controls as props* (forma lui `pobrn`, cu
`Suggested-by:`) și `c940697ce` *keep reading the other controls when one cannot be read*.
Patch-uri exportate în `pipewire-5363/patches/5431/`, descrierea MR-ului în
`results/MR-5431-DESCRIERE.md`.

**Trimis pe 19 august ca [!2954](https://gitlab.freedesktop.org/pipewire/pipewire/-/merge_requests/2954)**
— ramura `v4l2-compound-controls` pe fork, țintă `master`, `mergeable`, fără conflicte, `+15 -11`
într-un singur fișier. Referința a apărut automat pe #5431 (`mentioned in merge request !2954`),
numărul de comentarii a rămas 4 — nicio postare stivuită. Push-ul s-a făcut prin HTTPS cu un
credential helper care ia jetonul **din mediu** (`/tmp/cred.sh`), fiindcă portul 22 către
`gitlab.freedesktop.org` e blocat din rețeaua asta și Lenovo-ul n-are cheie SSH; jetonul n-a atins
nici linia de comandă, nici vreun fișier.

**CI verde pe MR:** pipeline-ul `1729503`, 62/62 joburi trecute.

**Întărirea comitului 2, 19 august — cerută fiindcă e plauzibil ca upstream să ia cauza dar nu și
efectul.** Argumentul „orice control VOLATILE poate pica" suna a speculație; l-am transformat în
dovadă, din sursa nucleului 7.1:

- `get_ctrl()` are **patru** căi de eșec, dintre care doar două se văd **înainte** de citire:
  compound (comitul 1) și `WRITE_ONLY` (scutit din 2017). Celelalte două — controlul dispărut și
  `VOLATILE` — se văd doar la citire, deci nu există filtru posibil.
- Din **40** de handlere `g_volatile_ctrl` înregistrate în `drivers/media`, **11** au cale reală de
  eroare (nu `default: return -EINVAL` de neatins): `ov5648`, `ov7740`, `ov965x`, `mt9m114`,
  `vd55g1`, `vd56g3` propagă eroarea de citire I2C; `pwc` una USB; **`s5c73m3` întoarce `-EBUSY`
  cât timp senzorul nu e alimentat** — stare perfect normală.
- **`uvcvideo` nu înregistrează niciun `ctrl_handler`.** Lanțul verificat în sursă:
  `VIDIOC_G_CTRL` → `v4l_g_ctrl()` → (ambele `ctrl_handler` NULL) → `ops->vidioc_g_ext_ctrls` =
  `uvc_ioctl_g_ext_ctrls` → `uvc_ctrl_get` → `uvc_query_ctrl(UVC_GET_CUR)` → `usb_control_msg()`.
  Deci pe **orice webcam USB** citirea unui control e un transfer USB, iar un stall/timeout face azi
  să pice toată enumerarea `Props` și, prin ea, activarea nodului.

Descrierea MR-ului **editată** cu asta (nu comentariu nou — numărul de comentarii 0 înainte și după).
Ce rămâne declarat nemăsurat: n-am reușit să fac un dispozitiv de aici să pice așa, și scriu asta
explicit în MR. Dacă upstream ia doar comitul 1, #5431 se închide oricum, iar comitul 2 se
repropune separat — acum cu driverele numite, nu cu un raționament.

Pipeline-ul de pe ramura fork-ului (`1729499`) **eșuează la etapa `container`** — nu din cauza
codului: *„Looks like you don't have enough privileges"*, [fd.o#540](https://gitlab.freedesktop.org/freedesktop/freedesktop/-/issues/540),
fork-ul n-are voie să construiască imagini. Pipeline-ul MR-ului (`1729503`) rulează în contextul
oficial și acolo etapa `container` a trecut.

**Măsurat pe Lenovo, kernel 7.0.0-29, `vivid n_devs=1 node_types=0x1` singura cameră**, fiecare
comit separat și amândouă, secvența rulată și în ordine inversă — rezultat identic de ambele dăți:

| plugin | enum `Props` | session item | client cameră |
|---|---|---|---|
| master `adfb948ec` | eșuează, -EINVAL | 0 | `target not found` |
| numai comitul 1 | ok | 1 | 10 cadre |
| numai comitul 2 | ok | 1 | 10 cadre |
| amândouă | ok | 1 | 10 cadre |

**De ce e nevoie de amândouă, deși oricare singur ascunde simptomul.** Diferența se vede în ce
rămâne expus, nu în dacă merge camera:

| | `PropInfo` pe vivid | `Props` pe vivid |
|---|---|---|
| master | 1001 linii (include `"S32 2 Element Array"`) | **eroare** |
| comitul 1 | 990 linii — controlul dispare | 111 linii |
| comitul 2 | 1001 linii — controlul **rămâne** | 113 linii, controlul raportează `Int 0` |

Comitul 2 singur repară efectul și lasă în graf o proprietate care minte: un `Int` scalar cu min/max
din array, care citit dă mereu 0 și scris nu face nimic. Comitul 1 e cauza; comitul 2 e raza de
explozie — orice control VOLATILE al cărui `g_volatile_ctrl` întoarce eroare (orice `errno`, e la
latitudinea driverului) omoară la fel toată enumerarea.

**Neregresie pe cameră reală:** pe UVC, `PropInfo` și `Props` sunt **identice octet cu octet** cu și
fără cele două comituri, măsurat intercalat (master / patch / master / patch). UVC-ul nu are niciun
control cu payload, deci comitul 1 nu are ce scoate.

**Review propriu pe patch, cerut înainte de trimitere — un defect găsit în el.** Comitul 2 punea
`c->value = 0` când citirea eșua. Dar `spa_v4l2_enum_controls()` inițializează fiecare control cu
`queryctrl.default_value` (l. 1456), deci zeroizarea **arunca valoarea implicită** și raporta 0 —
care nu e neapărat în intervalul anunțat de control. Corectat: se lasă valoarea în pace, deci
rămâne ultima citită cu succes, sau implicita. Măsurat direct pe vivid, controlul cu payload citit
fără comitul 1: `Int 0` înainte, **`Int 2`** (implicita lui) după. Comitul 2 e acum `c940697ce`;
binarul reconstruit are md5-ul măsurat `b25de7404f9b`. Pe UVC, tot identic octet cu octet — camera
aia n-are niciun control write-only sau volatile, deci comitul 2 n-are ce schimba acolo.

Restul review-ului, verificat în sursa nucleului 7.1 (`linux-source-7.1`), nu presupus:
`v4l2_query_ext_ctrl_to_v4l2_queryctrl()` copiază `to->flags = from->flags` **verbatim**, deci
`HAS_PAYLOAD` se vede și prin `VIDIOC_QUERYCTRL`-ul vechi — și fără verificarea noastră un control
compound ar fi ajuns înregistrat cu min=max=step=0, fiindcă acolo conversia le pune pe 0 pentru
tipurile compound. `get_ctrl()` confirmă cele trei căi: `!is_int` → `-EINVAL`, `WRITE_ONLY` →
`-EACCES`, iar pentru `VOLATILE` întoarce **exact** ce întoarce `g_volatile_ctrl` al driverului.
`V4L2_CTRL_FLAG_NEXT_COMPOUND` e în cod din 2017 (`e5e360d5d`, Wim), nu adăugat intenționat pentru
suport compound — deci alternativa „scoate NEXT_COMPOUND" ar merge și ea, dar e mai fragilă:
verificarea pe flag prinde și calea `QUERYCTRL`. Singurul apelant al lui
`spa_v4l2_update_controls()` e `v4l2-source.c:322`; după comitul 2 funcția mai poate eșua doar dacă
`spa_v4l2_open()` eșuează — adică exact cazul în care eșecul chiar înseamnă ceva.

Verificări de banc, făcute explicit: cele patru variante generate prin `git checkout <comit> --`, cu
aserțiuni în sursă (numărul de `HAS_PAYLOAD` și prezența căii fatale) și md5-uri distincte; md5-ul
chiar încărcat de daemon **și** de wireplumber citit din `/proc/PID/maps`; după corectarea mesajelor
de comit, binarele reconstruite din SHA-urile finale au **exact md5-urile măsurate** — deci ce se
trimite e ce s-a măsurat. `verifica-bancul.sh`: verde, înainte și după.

### 3.2p 🔵 21 august — !2954 decuplat, și comitul al doilea măsurat pe un driver scris anume

**De unde a pornit.** Întrebarea pusă direct: din cele două comituri ale lui !2954, al doilea
repară cauza sau efectul, și mai e nevoie de el aici? Răspunsul scurt e că **pentru #5431 e efect**,
dar **are cauză proprie**, iar la momentul acela cauza aia era **nemăsurată** — scria chiar în
descrierea MR-ului: *„that part is not measured"*. Cu regula „nu trimitem nimic copt pe jumătate",
asta îl scotea din MR.

**Decuplarea.** `fork/v4l2-compound-controls` forțat de la `c940697ce` la `23f742e59`; comitul 2
păstrat pe ramura locală `v4l2-nonfatal-read`. Cele două hunk-uri sunt în funcții diferite, la 117
linii distanță (`spa_v4l2_enum_controls()` l. 1439 vs `spa_v4l2_update_controls()` l. 1556) — un
`cherry-pick` al comitului 2 pe `adfb948ec` a intrat curat, `1 file changed, 10 insertions(+),
10 deletions(-)`, ceea ce **dovedește** independența, nu doar o sugerează. Descrierea MR-ului
rescrisă (editată, nu postată peste); numărul de comentarii a rămas 0.

**Bancul, actualizat — și !883 chiar schimbă ce se măsoară.** WirePlumber `35d5d199` → `8cf44a43`,
care conține !883 și !861. Din !883, monitorul activează `Features.ALL` și **nu mai stochează nodul**
când activarea eșuează: pe un plugin nereparat camera nu mai apare deloc în graf, în loc să apară
inutilizabilă, iar eșecul se scrie la nivel **N**:

```
N wp-event-dispatche <WpAsyncEventHook> failed: Failed to activate V4L2 node
  v4l2_input.platform-vivid.0: Object activation aborted: enum params id:2 failed
```

Adică exact ce lipsea când raportasem #986 — atunci era mut. Poarta veche din `banc.sh`
(„camera prezentă") expira; acum acceptă și a doua stare terminală. Copie: `banc.sh.pre883`.

**Un defect de măsurare, prins înainte să conteze.** Coloana nouă „nod Video/Source" dădea **0
pentru toate** variantele, inclusiv cele care mergeau. Cauza: `pw-dump` are nevoie de
`SPA_PLUGIN_DIR` ca să găsească `support.system`; fără el eșuează tăcut, `json.loads` arunca, iar
`except` întorcea listă goală. Aceeași familie cu „un grep care nu găsește nimic nu e o măsurătoare".
Reparat: primește mediul bancului, iar o ieșire goală oprește proba.

**!2954 retestat pe `vivid`**, patru variante distincte prin md5, fiecare verificată în sursă pe doi
markeri independenți înainte de compilare, și verificată la rulare că e chiar cea încărcată de
**ambele** procese:

| plugin | enum Props | nod | eroare N | item | props | prop falsă | client |
|---|---|---|---|---|---|---|---|
| master | eșuează, -EINVAL | 0 | 1 | 0 | — | — | `target not found` |
| cauza `23f742e59` | ok | 1 | 0 | 1 | **257** | nu | 10 cadre |
| efect `b7aabe7ac` | ok | 1 | 0 | 1 | **258** | **`S32 2 Element Array`** | 10 cadre |
| ambele `c940697ce` | ok | 1 | 0 | 1 | **257** | nu | 10 cadre |

**257 vs 258** e dovada numerică că efectul singur doar maschează: proprietatea falsă rămâne expusă.
Non-regresie pe camera UVC reală, alternat master/cauza ×4: `PropInfo` `fc73087f1273` și `Props`
`6ae844c01873` identice în toate patru rulările.

**Driverul care eșuează la `G_CTRL`.** Cazul comitului 2 nu poate fi produs de nimic din casă:
singurul `g_volatile_ctrl` din `vivid` (`vivid-ctrls.c:426`) se termină în `return 0;`
necondiționat, iar o cameră UVC sănătoasă nu-ți blochează un transfer de control la comandă.
Sursele `vivid` nu există pentru kernelul de pe Lenovo (în `linux-headers` sunt doar `Kconfig` și
`Makefile`). Deci **`failctrl`** (`pipewire-5363/failctrl/`): dispozitiv V4L2 de captură minimal cu
trei controale, dintre care `V4L2_CID_GAIN` e VOLATILE și al cărui `g_volatile_ctrl` întoarce
`-EIO`. Drumul e cel real din kernel — `get_ctrl()` face `ret = call_op(master, g_volatile_ctrl);`
și duce errno-ul driverului direct în userspace. Verificat înainte de orice măsurătoare:
`--get-ctrl=gain` → `Input/output error`, `--get-ctrl=brightness` → `128`. Defectul se stinge la
cald prin `/sys/module/failctrl/parameters/fail`, deci există **control negativ pe același
dispozitiv**, iar fiecare rulare verifică întâi că injecția chiar se comportă cum s-a cerut.

| # | plugin | fail | enum Props | nod | item | client |
|---|---|---|---|---|---|---|
| 1 | master | 1 | eșuează | 0 | 0 | `target not found` |
| 2 | efect | 1 | ok | 1 | 1 | 10 cadre |
| 3 | **cauza** | 1 | **eșuează** | 0 | 0 | **`target not found`** |
| 4 | ambele | 1 | ok | 1 | 1 | 10 cadre |
| 5 | master | **0** | ok | 1 | 1 | 10 cadre |
| 6 | master | 1 | eșuează | 0 | 0 | `target not found` |
| 7 | efect | 1 | ok | 1 | 1 | 10 cadre |

Brațele alternate, nu în loturi. Rândurile 6–7 repetă 1–2 identic; rândul 5 e controlul negativ —
același plugin, același dispozitiv, defectul stins, merge.

**Rândul 3 e concluzia:** comitul 1 nu ajută deloc acolo. Cu un control volatil care eșuează, camera
e la fel de moartă ca pe master. Deci comitul 2 **nu e efectul comitului 1** — are cauză proprie, iar
acum e măsurată, nu citită din sursă. S-a verificat și afirmația din mesajul lui despre valoarea
păstrată: `gain` rămâne în `Props` cu **42**, implicitul stocat de `spa_v4l2_enum_controls()`, nu 0.

**Ce s-a greșit la origine, ca să nu se repete:** comitul 2 a fost scris și trimis pe baza unui
raționament citit din sursa kernelului, fără niciun dispozitiv pe care să eșueze. Raționamentul s-a
dovedit corect — dar asta se știe abia acum, iar între timp ținea ostatic un fix de o linie care are
`Suggested-by:` de la recenzent. Argumentul din sursă justifică o **investigație**, nu o trimitere.

**Reverificat pe kernelul nou.** Lenovo-ul a fost trecut pe `7.0.0-30-generic` — GRUB era **fixat**
pe `7.0.0-28-generic` prin `GRUB_DEFAULT`, deci upgrade-ul nu se lua singur; schimbat (copie:
`/etc/default/grub.bak-21aug`), `update-grub`, restart. Kernelul vechi purjat, `7.1.8-kasan`
(cel compilat de noi, [secțiunea 3.2f](#32f--kernel-de-depanare-pe-lenovo--kasan-lockdep-kfence))
păstrat și verificat că e încă în meniul GRUB. Șterse și cinci directoare rămase în `/lib/modules`
de la kerneluri demult scoase (`6.17.0-22/23/29/35`, `7.0.0-29`) — fiecare cu **zero** module și
fără `vmlinuz`, verificat înainte de ștergere.

`failctrl` recompilat pentru `7.0.0-30-generic`, cele patru variante de plugin reconstruite cu
**exact aceleași md5-uri** ca înainte, iar ambele probe rulate din nou: rezultatele de mai sus se
reproduc identic, rând cu rând. La fel și non-regresia pe camera UVC — `PropInfo` `fc73087f1273`,
`Props` `6ae844c01873` în toate cele patru rulări alternate.

Artefacte: `pipewire-5363/failctrl/failctrl.c`, probele în `pipewire-5363/scripts/`
(`fa-variante2.py`, `proba986b.py`, `probauvc.py`, `probafail.py`), raportul complet în
`pipewire-5363/results/PLAN-UPSTREAM-20aug.md` secțiunea 10. Comitul 2 **nu s-a trimis**.

### 3.2q 🔵 22 august — cele șapte PR-uri de facetimehd, măsurate pe camera reală

**De unde a pornit.** Modulul instalat prin DKMS se numește `facetimehd-0.7.0.1`, iar upstream
are tag-ul `0.7.0.3`. Întrebarea firească: am trimis patch-uri peste cod vechi, și poate unele
buguri au fost reparate între timp?

**Nu.** Numele e o etichetă, nu codul. Comparat octet cu octet, `/usr/src/facetimehd-0.7.0.1/`
are 13 din 17 fișiere identice cu tag-ul `0.7.0.3` și doar 11 cu `0.7.0.1`; `fthd_drv.c` și
`fthd_drv.h` sunt identice bit cu bit cu `0.7.0.3`. Cele 4 fișiere care diferă de `0.7.0.3`
diferă **pentru că sunt patch-urile noastre în ele** (#328…#333, nu și #334). Șirul `0.7.0.1`
vine dintr-o singură linie din `dkms.conf`; modulul compilat nu are câmp `version:` deloc,
pentru că driverul upstream nu apelează niciodată `MODULE_VERSION()`.

Iar `0.7.0.3` = `364b1c66` = HEAD-ul de pe master. Verificat prin API: **toate cele șapte PR-uri
au baza `364b1c6`**. Nimic nu s-a trimis peste cod vechi.

Între `0.7.0.1` și `0.7.0.3` sunt 6 comituri. Singurul care ne atinge zona e `98b55fd3` (Thomas
Shirley, citește rezoluția reală a senzorului). Nu repară nimic din ce reparăm noi — dimpotrivă,
patch-urile noastre **se sprijină pe** câmpurile `sensor_width`/`sensor_height` introduse de el.

**Ce s-a măsurat.** Trei module compilate din același depozit peste `364b1c66`, fiecare cu un
marcaj `MODULE_VERSION` adăugat după copierea surselor (singura linie adăugată, nu atinge cod
executat), verificabil din `/sys/module/facetimehd/version`. Rulătorul refuză să măsoare dacă
marcajul nu e cel cerut. Ordinea intercalată: master → tot → 328 → master.

| observabil | `v-master` (0.7.0.3 curat) | `v-tot` (cu patch-uri) |
|---|---|---|
| `S_FMT` cu lățime impară | **acceptă impare**: 321→321, 323→329, 641→641 | toate → multiplu de 8 |
| contradicție cu `ENUM_FRAMEINTERVALS` | 4 cazuri | 0 |
| `ENUM_FRAMESIZES` | `Discrete 1296x736` | `Stepwise 320x240–1296x736, pas 8/1` |
| control pus înainte de `STREAMON` | **pierdut** (A=90.77 ≈ implicit D=91.06) | **păstrat** (A=16.04 ≈ C=15.78) |
| cerere de 640x360 | **colțul stânga-sus** (corel. 0.931) | câmpul întreg micșorat (corel. 0.944) |
| `REQBUFS` cu `USERPTR` | acceptat | `EINVAL` |
| octeți distruși în fața bufferului | **până la 3999 din 4000** | nu se ajunge acolo |
| `WARN_ON` în jurnal | 8 pe rulare, fără efect | 0 |
| CPU de sistem ars la `STREAMON` | **991 ms** | 1 ms |
| durata `STREAMON` | 1077 ms | 289 ms |

Reproductibil: a doua rulare pe master, intercalată, dă aceleași concluzii.

**Cel mai important rezultat.** Scrierea din fața bufferului (#333) e acum măsurată direct, nu
dedusă din cod. Buffer `USERPTR` așezat intenționat la un decalaj cunoscut după marginea unei
pagini, santinelă `0xA5` în fața lui, în propria alocare a procesului:

| decalaj | santinelă | **distruși** | primul | ultimul | după capătul bufferului |
|---:|---:|---:|---:|---:|---:|
| 100 | 100 | **100** | 0 | 99 | 0 |
| 1000 | 1000 | **1000** | 0 | 999 | 0 |
| 2048 | 2048 | **2048** | 0 | 2047 | 0 |
| 4000 | 4000 | **3999** | 0 | 3999 | 0 |

Camera scrie de la marginea paginii, adică exact `offset` octeți în fața bufferului primit.
Ambele `WARN_ON` existente (`fthd_buffer.c:76` și `:78`) trag — și driverul continuă oricum.

**#328c izolat de #334.** Varianta `v-328` are `mdelay`→`msleep` dar nu și scurtarea: peretele
rămâne 1092 ms, dar CPU-ul de sistem scade de la 991 ms la **1 ms**. Deci `msleep` nu scurtează
nimic, doar dă secunda înapoi sistemului; #334 e cel care scurtează.

**Ce NU s-a putut măsura:** #332 (cere un firmware care nu răspunde — injecția ar măsura
injecția, nu defectul), #328a și #328b (nu au observabil azi, `FTHD_BUFFERS` *este* 4),
#330a separat de #330c.

**Restructurarea propusă**, pregătită local și verificată (fiecare ramură compilează singură,
0 avertismente):

| PR | acum | după |
|---|---|---|
| #329 | controale + `ALIGN` | doar controalele (1 comit) |
| #331 | doar `framesizes` | `ALIGN` + `framesizes` — același contract |
| #330 | y1 + redenumire + decupaj centrat | doar `cmd.y1` (**1 linie**) |
| nou | — | redenumire + decupaj centrat, peste #330 |
| #334 | 4 comituri (trage și #328) | 2 comituri: `msleep` + 200 ms |
| #333 | neschimbat | descriere rescrisă cu tabelul santinelei |

**Ce mi-am schimbat.** Spusesem că scoaterea lui `VB2_USERPTR` din #333 e „retragerea unei
capabilități anunțate" și că ar trebui discutată separat. Măsurătoarea o infirmă: modul nu
funcționează deloc pe hardware-ul ăsta — fiecare decalaj testat a distrus memorie. Nu e
retragerea unei capabilități, e încetarea unei reclame pe care hardware-ul nu o poate onora.
Cele două comituri rămân împreună.

**Aplicat pe 22 august, cu acordul explicit al lui vik pentru punctele 1 și 2** (punctul 3, PR-ul
nou pentru decupajul centrat, a rămas nedecis):

| PR | acțiune | rezultat |
|---|---|---|
| #329 | `--force-with-lease` + titlu + descriere | 1 comit, 2 fișiere, +11/-6, `clean` |
| #330 | `--force-with-lease` + titlu + descriere | 1 comit, **1 fișier, +1/-1** |
| #331 | `--force-with-lease` + titlu + descriere | 2 comituri, 1 fișier, +8/-4 |
| #334 | `--force-with-lease` + descriere | 2 comituri (a scăpat de #328) |
| #333 | doar descrierea | neatins codul; tabelul santinelei adăugat |

Verificat după: numărul de comentarii **nu a crescut** la niciunul (#331 rămâne la 1, restul 0) —
s-au editat descrierile, nu s-au adăugat postări. Toate șapte `mergeable=true`, `clean`, pe
`364b1c66`. Descrierile dinainte și de după: `fthd-masuratori/descrieri/{inainte,dupa}-22aug/`.

**Verificare live, imediat după — au ieșit patru lucruri pe care prima trecere le ratase:**

1. **`(cherry picked from commit …)`** pe toate cele 6 comituri rescrise. `cherry-pick -x` le pusese;
   trimit către SHA-uri care există doar în fork-ul nostru, deci zgomot pur upstream. Scoase.
2. **Mesajul comitului `framesizes` din #331** zicea încă *„Depends on … (#329)"* și *„should not go
   in ahead of 'isp: crop a centred window' (#330)"* — ambele false după mutare. Rescrise fără
   numere de PR, care oricum se pot schimba.
3. **Titlul lui #331** zicea `(merge after #330)`. #330 nu mai conține decupajul, deci motivul
   ordonării dispăruse din el. Titlul curățat, iar în descriere argumentul e acum legat de
   comportament, nu de un număr de PR, cu tabelul de corelații în el.
4. **Comitul de 200 ms din #334 n-avea `Signed-off-by`** — defect vechi, de la deschiderea PR-ului,
   nu de azi. Adăugat.

Bonus: #330 a putut fi pus **exact pe comitul original `27132649`** (părintele lui era deja master),
deci acolo nu s-a rescris nimic. Verificat înainte de a împinge că arborele fiecărei ramuri e
**identic** cu ce era live — s-au schimbat doar mesajele.

După corectură, verificat live: toate șapte `mergeable=true`, `clean`, pe `364b1c66`; `Signed-off-by`
pe 12 din 12 comituri; zero trailere `cherry picked from`; zero referințe încrucișate moarte;
descrierile live identice cu fișierele locale. Numărul de comentarii tot neschimbat (#328 la 3,
#331 la 1, restul 0).

**A doua trecere de verificare, tot pe 22 august.** Prima verificare live se uitase doar la PR-urile
pe care le atinsesem. A doua le-a luat pe toate șapte, plus comentariile, identitățile de autor,
diff-urile de pe GitHub față de cele locale, și fiecare referință încrucișată din fiecare descriere.

Ce e **confirmat corect**:

* capul fiecărui PR = ramura din fork, la toate șapte;
* diff-ul de pe GitHub identic, linie cu linie, cu cel local, la toate patru cele rescrise;
* `Signed-off-by` pe 12 din 12 comituri, zero trailere `cherry picked from`;
* autor și comiter `Viorel Cernateanu <vrilutza@gmail.com>` peste tot, niciun `Co-Authored-By`;
* **zero comentarii create pe 22 august** — niciun fișier de comentarii nu conține data de azi;
* master-ul lui patjak tot la `364b1c66`, din 30 iunie; toate șapte `mergeable=true`, `clean`.

Ce **nu** e corect, și e vina restructurării de azi — trei descrieri **din PR-uri pe care nu le-am
atins** au rămas cu text fals:

1. **#328** își descria seria: *„#329 (control values discarded …, **and `ALIGN(width, 7)` aligning
   nothing**)"* — `ALIGN` e la #331 acum; și *„#330 (the camera returns the top left corner …)"* —
   #330 e acum doar `cmd.y1`. Ambele false. Zicea și „the first of five", când sunt șapte.
2. **#332**: *„measured … with the whole series … this patch together with #328, #329, #330 and
   #331"* — reuniunea acelor patru nu mai conține rescrierea decupajului, care era instalată la
   momentul măsurătorii. Devenită inexactă.
3. **#333**: *„the measurements above were taken with those five applied"* — aceeași problemă. Și e
   păcat, pentru că măsurătoarea santinelei a fost făcută pe **master curat**, ceea ce e mai tare
   decât spune textul.

Un al patrulea, mai mic: comentariul nostru de pe #331 din 15 august zice *„the numbers below are
for this commit alone"*. Când l-am scris, #331 avea un singur comit; acum are două, deci „this
commit" a devenit ambiguu.

**Aplicate, cu acordul lui vik pentru toate patru.** Doar descrieri și un comentariu editat, niciun
cod atins:

* **#328** — lista seriei rescrisă pe conținutul de azi, toate șase celelalte enumerate corect, plus
  nota că `msleep` apare și în #334 și că oricare ar intra prima, git îl ia pe celălalt deasupra.
* **#332** — nota de testare spune acum că build-ul măsurat conținea și rescrierea decupajului, care
  a ieșit din #330 și n-a fost retrimisă, deci setul exact nu mai e reproductibil din PR-urile
  deschise.
* **#333** — aceeași corectură, plus întărirea care lipsea: **măsurătoarea santinelei a fost făcută
  pe master curat**, deci nu depinde de restul seriei.
* **comentariul de pe #331** — *editat, nu adăugat*: „this commit" → „the enumeration commit alone",
  cu o paranteză care spune că ramura poartă între timp și fixul `ALIGN`, venit din #329 după ce
  comentariul fusese scris.

Verificat după: descrierile live identice cu fișierele locale la toate șapte; numărul de comentarii
**neschimbat** (#328 la 3, #331 la 1, restul 0); toate șapte `mergeable=true`, `clean`. Baleiaj
final peste **fiecare** referință `#3xx` din descrieri, comentarii și mesaje de comit — 17 în total,
toate adevărate acum.

Copiile: `descrieri/dupa-22aug-b/` (inclusiv `331-comentariu.md`).

**Runda a treia, 22 august: descrierile scurtate.** Pornit de la o observație a lui vik — vicamo a
deschis #335 pe 20 august și descrierea lui e scurtă. Verificat, și avea dreptate: proza din #335 e
de **două propoziții**, restul celor 104 linii e o ieșire `v4l2-compliance` lipită.

Două măsurători care au decis:

* **stilul depozitului**: mesajele de comit ale lui patjak au **mediana 14 cuvinte**, media 30,
  maximul 134 pe ultimele 30 de comituri. Ale noastre: mediana **259**, maximul **610**;
* **firul de pe #328**: patjak scrisese pe 15 august *„sorry for not looking at this earlier …
  I'll have a look during next week"*. Săptămâna trecuse.

Descrierile lungi nu conving, ridică prețul lui „mă uit puțin".

| PR | înainte | după |
|---|---:|---:|
| #329 | 379 cuv. | **128** |
| #330 | 235 | **89** |
| #331 | 901 | **248** |
| #332 | 448 | **140** |
| #333 | 1152 | **247** |
| #334 | 958 | **196** |
| comentariul de pe #331 | 405 | **278** (editat, nu dublat) |

**#328 lăsat neatins**, la cererea lui vik — e singurul unde a comentat patjak, iar firul de acolo
are valoare: acolo a dat linkul către trimiterea în linux-media.

Substanța n-a fost aruncată: în descriere au rămas mecanismul defectului și cifra decisivă, restul
e în mesajele de comit și în raportul de măsurători. Verificat live după: descrierile identice cu
fișierele locale la toate șase, comentariile **neschimbate ca număr**, toate șapte `mergeable`,
`clean`, pe `364b1c66`.

**Runda a patra: mesajele de comit — și o descoperire care schimbă #331.**

Măsurat corect de data asta, doar comiturile reale de cod ale depozitului (fără merge, fără
`dkms.conf`): **mediana 21 de cuvinte, maximul 134**. Ale noastre: mediana 259, maximul 610.
Rescrise la 139–225. Comitul `msleep` din #334 lăsat **neatins**, ca să rămână identic cu cel din
#328 — altfel nu mai sunt același patch (verificat: md5 identic al mesajului).

**Descoperirea.** Căutând stilul depozitului am dat peste `545cb18` (22 mai 2020):

> *Revert to discrete frame sizes and frame intervals. Skype and other applications don't support
> stepwise frame sizes and frame intervals … It seems they will never fix this so instead we reduce
> our functionality to just support the discrete type.*

**patjak a făcut exact ce propune #331 și a revenit deliberat asupra ei**, cu valori identice:
`step_width = 8`, `step_height = 1`. Cronologia:

```
2015-11-28  4758d7a  stepwise introdus
2016-01-24  #52 deschis: „Low resolution with Skype"
2020-05-22  545cb18  patjak REVINE la discrete
2026-06-28  patjak inchide #52
2026-07-30  noi deschidem #331 -- citand #52 ca argument PENTRU
```

Iar #52 și #36 sunt din era stepwise: **nu ne susțin, sunt parte din motivul revenirii**. Doar #243
(2021) și #323 (2026) sunt de după revenire și chiar ne susțin. Descrierea noastră cita toate patru.

Și mai important: măsurătoarea noastră de pe #331, făcută pe 15 august, spune că problema din 2020
**nu a dispărut, s-a mutat** — pe un PipeWire lansat, o gamă stepwise face GNOME Snapshot să
negocieze 320x240 în loc de 1296x736 și să pornească în ~4100 ms în loc de ~1500. Aceeași clasă de
defect ca Skype, altă aplicație. Descoperisem asta independent, fără să știm de `545cb18`.

**#331 rescris pornind de la asta:** comitul 1 (`ALIGN`) e o greșeală curată, se poate lua oricând;
comitul 2 (enumerarea) **scrie acum explicit că nu ar trebui luat acum**, cu scuze pentru citarea
greșită a lui #52 și cu oferta de a le despărți în două PR-uri. Descrierea a crescut de la 248 la
350 de cuvinte — singura care a crescut, și își merită lungimea.

**Autoverificare live după tot:** toate șapte `true`/`clean` pe `364b1c66`; diff-urile live identice
linie cu linie cu cele locale; mesajele de comit identice cu fișierele din `mesaje/`; descrierile
identice cu `descrieri/scurte/`; `Signed-off-by` pe 12 din 12; zero trailere `cherry picked from`;
**zero comentarii create pe 22 august** pe oricare din cele șapte; #328 neatins, cap tot `849cbf79`.
Cele 11 referințe încrucișate rămase, verificate una câte una — inclusiv cele două către #52 și #329
din #331, care sunt intenționate.

**A cincea trecere, 22 august — citit integral, live.** Nicio activitate nouă de la patjak: ultimul
lui comentariu e din 19 august (pe tichetul #178), iar pe #328 din 17 august. Promisiunea *„I'll
have a look during next week"* e din **15 august**. Tot ce s-a întâmplat azi pe cele șapte suntem
noi. Zero review-uri, pe oricare.

Patru lucruri găsite citind textul integral:

1. **Titlul lui #331 cerea exact ce descrierea zicea să nu ia.** Era *„make the advertised frame
   sizes match what the driver accepts"* — adică fix comitul 2, pus în așteptare. Schimbat în
   *„fix ALIGN(pix->width, 7); second commit re-does 545cb18 and should wait"*.
2. **#329 trimitea la ceva care nu mai exista:** *„a second interleaved run are in the commit
   message"* — tăiat la scurtare. Cifrele puse direct în descriere.
3. **#333 la fel:** *„v4l2-compliance numbers … are in the commit messages"* — tăiate. Puse înapoi
   compact în descriere: 6132 → 0 scrieri în afara bufferului, testele USERPTR de la `OK` la `FAIL`
   la `not supported`.
4. **Tabelul din #334 amesteca valori dintr-o repetare cu medii.** Publicase `1077 / 991`,
   `1092 / 1`, `289 / 1`. Mediile reale peste cinci repetări sunt `1077 / 990`, `1102 / 1`,
   `291 / 1`. Toate cele publicate erau în interval, dar nu erau medii și nu spuneam că sunt valori
   individuale. Rescris cu media plus min–max explicit.

Verificate și cinci SHA-uri citate în mesajele de comit — `6bbe3712`, `230e57ae`, `f3067f2`,
`98b55fd`, `545cb18` — toate există și fac exact ce spunem: `6bbe3712` (28 nov 2015) chiar adaugă
`if (interval->width & 7`, `230e57ae` (30 nov 2015) chiar adaugă `ALIGN(pix->width, 7)`, deci
„două zile apart" e corect, iar `f3067f2` chiar introduce `#define FTHD_BUFFERS 4`.

**Verificarea care lipsea din trecerile anterioare:** fiecare cifră publicată, confrontată cu
`rezultate/*.json`. După corectura de la punctul 4, toate se potrivesc — cele 6 valori de luma din
#329, cei patru octeți-santinelă din #333, cele 18 valori de cronometrare din #334, dimensiunile din
#331.

**Stare finală:** toate șapte `true`/`clean` pe `364b1c66`; diff-urile live identice cu cele locale
la **toate șapte** (inclusiv #328 și #330, neatinse azi la cod); mesajele identice cu `mesaje/`;
descrierile identice cu `descrieri/scurte/`; `Signed-off-by` 12/12; zero trailere `cherry picked`;
**zero comentarii create azi** pe oricare.

**A șasea trecere — de data asta enumerat mecanic, nu citit.** Trecerile 1–5 au fost citiri, iar o
citire găsește ce observi. Aici am enumerat categoriile de afirmații verificabile și le-am verificat
pe fiecare cu un script, inclusiv trei pe care nu le atinsesem niciodată:

* **fiecare simbol din driver citat** în descrieri, comentarii și mesaje de comit (`fthd_*`,
  `iommu_*`, `FTHD_*`, `CISP_*`), căutat în surse — **niciunul lipsă**, la toate șapte;
* **fiecare linie de cod citată**, căutată literal în surse după normalizarea spațiilor — 14 linii,
  **toate prezente**;
* **afirmațiile externe**: `!2950` și `!2951` încă deschise și cu titlurile pe care le descriem;
  `v4l2-compliance 1.32.0` confirmat local; blocurile markdown toate închise;
* **definiția lui `ALIGN`** citită din headerele instalate:
  `ALIGN(x,a)` → `__ALIGN_KERNEL_MASK(x, a-1)` → `((x) + (a-1)) & ~(a-1)`. Afirmația din #331 e
  exactă;
* **afirmații repetate în mai multe PR-uri** (1296x736, MacBookPro14,1, versiuni de kernel,
  `FTHD_BUFFERS`, 4095) — fără contradicții;
* niciun PR în stare `draft`, toate pe `master@364b1c66`.

**Un singur lucru găsit, și e exact genul pe care doar un script îl prinde.** #333 spunea că adresa
dată firmware-ului de `fthd_buffer_prepare()` este `(obj->offset << 12)`. În funcția aia variabila
nu se numește `obj` — expresia reală, la `fthd_v4l2.c:219`, este `(ctx->plane[0]->offset << 12)`.
`obj` e numele local din `iommu_allocate_sgtable()`, altă funcție. Cine dădea grep nu găsea nimic.
Corectat în descriere și în mesajul de comit, plus adăugat numărul de linie.

**Stare finală, verificată live după corectură:** toate șapte `true`/`clean`, `draft=false`, pe
`master@364b1c66`; diff-urile live identice cu cele locale la **toate șapte**; cele 7 mesaje de comit
identice cu `mesaje/`; cele 6 descrieri identice cu `descrieri/scurte/`; `Signed-off-by` 12/12; zero
trailere `cherry picked`; zero comentarii create azi; zero apariții rămase de `obj->offset`.

**Rescriere completă, nu peticire.** După șase treceri de corecturi incrementale, vik a cerut pe
bună dreptate să nu mai peticesc: rescrise **toate șapte descrierile de la zero**, ca un set coerent,
cu aceeași hartă a seriei în fiecare — tabel cu cele șapte, rândul propriu marcat `(this one)`, și
cele două note de ordonare (`msleep` comun între #328 și #334; comitul 2 din #331 în așteptare), plus
mențiunea patch-ului cu decupajul care nu e trimis.

**#328 inclus de data asta**, cu acordul explicit al lui vik. Conversația cu patjak rămâne intactă —
se editează doar corpul. Am corectat și afirmația de deschidere: zicea *„None of them changes
behaviour at the current values"*, dar comitul `msleep` schimbă exact ceva măsurabil. Acum spune
*„two change nothing at the current values; the third stops burning a CPU"*, cu tabelul.

**Scriptul de confruntare a cifrelor a prins încă una, înainte de trimitere.** În tabelul lui #329,
rândul `210` avea în coloana „run 2" valoarea **163.69** — care e de la `v-tot`, nu de la master
run 2. Corectă: **184.52**. Exact genul de greșeală pe care șase citiri n-au prins-o și un script o
prinde din prima.

**Uneltele de verificare sunt acum în repo**, ca să nu depindă de atenția mea:
`unelte/verifica-simboluri.py` (fiecare simbol din driver citat există în surse),
`unelte/verifica-citate-cod.py` (fiecare linie de cod citată există literal),
`unelte/verifica-cifre.py` (fiecare cifră publicată se potrivește cu `rezultate/*.json`).

**Verificat live după rescriere:** cele 7 descrieri identice cu `descrieri/final/`; **fiecare PR
trimite la celelalte șase, 6/6, la toate șapte**; rândul propriu marcat corect la toate; toate
`true`/`clean`, `draft=false`, pe `master@364b1c66`; diff-urile identice cu cele locale la toate
șapte; cele 7 mesaje de comit identice cu `mesaje/`; `Signed-off-by` 12/12; zero trailere
`cherry picked`; blocurile markdown închise la toate; **zero comentarii create azi** — #328 rămâne
la 3, #331 la 1, restul la 0.

**Verificarea patch-urilor, 22 august — o afirmație falsă în toate șapte.** Vik a cerut să verific
patch-urile și comiturile citind, fără să modific. Luate **de pe GitHub**, aplicate pe master curat
și compilate: toate șapte se aplică curat și compilează cu 0 avertismente, iar fiecare diff face
exact ce spune mesajul lui.

Dar aplicându-le **toate una peste alta**, prima șase intră și a șaptea pică pe `fthd_isp.c:1241`.
Harta seriei, prezentă în toate șapte descrierile, spunea:

> #334 carries the same `msleep` commit as #328. Whichever lands first, the other applies on top.

**Fals.** Testat în ambele direcții, pe o clonă nouă, simulând exact butonul „Merge pull request":

| | `git am` | `git merge` | `git rebase` |
|---|---|---|---|
| #334 peste #328 | eșuează | **CONFLICT** în `fthd_isp.c` | merge, păstrează 1 din 2 |
| #328 peste #334 | eșuează | **CONFLICT** | merge, păstrează 2 din 3 |

Merge doar cu `rebase`. Butonul de pe GitHub face merge, deci patjak ar fi primit exact conflictul
pe care descrierea îi promitea că nu-l are. Cauza e simplă și inevitabilă: ambele ramuri schimbă
aceeași linie, `mdelay(1000)` → `msleep(1000)` → `msleep(200)`.

Corectat în toate șapte, spunând ce se întâmplă de fapt și oferind rebazarea.

**Și scriptul de cifre a prins o a doua greșeală, la regenerare.** Corectasem `163.69` → `184.52`
direct în `329.md`, nu în `329-corp.md`; regenerarea a luat corpul vechi și a readus valoarea
greșită. Reparată la sursă. Fără script ar fi ajuns pe GitHub a doua oară.

**Verificat live după:** cele 7 descrieri identice cu fișierele; afirmația veche dispărută din toate
7, cea nouă prezentă în toate 7; toate `true`/`clean`; comentariile neschimbate (#328 la 3, #331 la
1, restul 0); cele trei scripturi trec — simboluri 7/7, citate 14/14, cifre 42/42.

**Decizia despre decupajul centrat (`n-330b`): se ține gata, NU se trimite acum.** Luată de vik pe
22 august, după ce am pus cifrele pe masă.

Ce le-a decis:

* depozitul lui patjak are **10 PR-uri deschise în total, dintre care 7 sunt ale noastre** (celelalte
  trei: unul din 2018, unul din 2020, unul de la vicamo din 20 august);
* ritmul lui de acceptare în 2026: **trei** — #320 în martie, #327 și #324 în iunie. Plus unul în
  septembrie 2025 și unul în martie 2025. E un driver de hobby, un singur om, fără firmă în spate,
  și e prietenos când răspunde (#328, 15 aug: *„sorry for not looking at this earlier"*);
* decupajul centrat e cea mai mare cerere de **decizie** din tot lotul, nu de **greșeală** — și
  categoria decizie e cea care stă blocată peste tot, pentru că cine aprobă își asumă regresia
  altcuiva iar cine nu decide nu plătește nimic;
* am scris chiar azi în #330 și #331 că niciunul n-ar trebui să intre înaintea unui fix de decupaj,
  deci al optulea ar face un lanț de trei la un întreținător cu trei acceptări pe an;
* așteptarea nu costă nimic: master-ul e nemișcat din 30 iunie.

**Ce ar schimba decizia:** orice mișcare pe vreunul din cele șapte — o acceptare, sau chiar și numai
un comentariu de la patjak. Atunci al optulea are unde să se așeze.

**Salvat ca să nu se piardă:** ramura trăia doar în clona temporară din `/tmp`. Exportată în
`fthd-masuratori/patches/n-330b/` (3 patch-uri, md5-uri în `patches/CITESTE.md`), verificat la export
că se aplică curat pe master, dau +47/-20 și compilează cu 0 avertismente. Comitul 0001 e identic cu
ce e deschis ca #330, deci ordinea nu creează conflict. Descrierea pregătită: `descrieri/330b.md`.
Tot acolo, în `patches/pr-live/`, sunt exportate și cele 7 PR-uri deschise în starea de azi — 15
patch-uri, o copie care nu depinde de GitHub.

Datele brute, uneltele și raportul: `pipewire-5363/fthd-masuratori/` (ignorat de git, ca tot
bancul). Raportul: `rezultate/MASURATORI-CAMERA-22aug.md`.

### 3.2r 🔵 22 august, seara — cele patru MR-uri rebazate, și două remăsurate

Masterul PipeWire a avansat cu **11 comituri** pe 21 august (14:30–17:10), de la `adfb948ec` la
`f03a55d7f`. Toate patru MR-urile noastre au trecut din `mergeable` în `need_rebase`. Printre cele
11 e **!2955** (`31b556d6`, sangchul), care atinge `dequeue_buffer` — exact funcția modificată de
!2935.

**Rebazate local, fără un singur conflict:** `rb2935` → `83cdc11f5`, `rb2950` → `11756ee0f`,
`rb2951` → `a39b6f20e`, `rb2954` → `f5589a4ed`, `rbnonfatal` → `43cf22e03`.

**Cine e de fapt expus.** Intersectând fișierele atinse de cele 11 comituri cu ce atinge fiecare MR:
!2935 și !2951 se suprapun pe `src/gst/gstpipewiresrc.c`; **!2950 și !2954 nu se suprapun deloc**.
Deci doar două aveau ce verifica — și amândouă au fost verificate pe hardware, nu deduse.

**!2935, `masoara.sh`, pool 16, două repetări:**

| hold | 15 aug (`adfb948e`) | 22 aug (`f03a55d7`) |
|---|---|---|
| 1–15 | 64 / 64 | 64 64 / 64 64 |
| **16** | **16** / **38** | **16 16** / **38 38** |
| **20** | **16** / **37** | **16 16** / **37 37** |

**!2951, `matrice.py A` / `rescale.py`:**

| | cadre | pauze > 200 ms |
|---|---|---|
| 18 aug, stock | 92 | 3 — 716, 714, 712 ms |
| 18 aug, + !2951 | **119** | **0** |
| 22 aug, stock | 92 | 3 — 715, 714, 719 ms |
| 22 aug, + !2951 | **119** | **0** |

Identice cifră cu cifră la ambele. Rândurile de control din aceeași rulare (hold=1 → 78 cadre,
hold=4 → 4 cadre) nu diferă între variante, deci !2951 nu atinge ce măsoară !2935.

**Un defect al bancului, prins de propria lui gardă.** Prima rulare a lui `masoara.sh` s-a oprit
singură: *„incarcat md5=493fd8dfa1d3, asteptam f85878faff8e"*. `493fd8dfa1d3` e plugin-ul GStreamer
**de sistem**, nu al nostru. Cauza: `gst-plugin-scanner` crapă cu o aserțiune în driverul Intel
VA-API (`i965_drv_video.c:4653`) și, când crapă la momentul nepotrivit, plugin-ul nostru nu ajunge
în registru. Verificat că e intermitent — 8 rulări cu registru proaspăt au dat **8/8 corect** — și
că niciun pachet GStreamer sau VA-API nu s-a schimbat de la ultima rulare. Reluată după ștergerea
registrelor, a trecut. Fără gardă, prima rulare ar fi comparat plugin-ul de sistem cu el însuși și
ar fi „dovedit" că patch-ul nu schimbă nimic.

**Împinse**, cu acordul lui vik — exact ramurile măsurate, aduse de pe Lenovo prin ssh, nu
reconstruite pe MacBook. Verificat înainte, pentru fiecare, că diff-ul rebazat e **identic octet cu
octet** cu ce era în MR și că stă exact pe `f03a55d`:

| MR | vechi → nou | diff |
|---|---|---|
| !2935 | `6fe4eaca2` → `83cdc11f5` | neschimbat |
| !2950 | `14619fffa` → `11756ee0f` | neschimbat |
| !2951 | `1da2d9604` → `a39b6f20e` | neschimbat |
| !2954 | `23f742e59` → `f5589a4ed` | neschimbat |

Jetonul a rămas în keyring — push pe HTTPS prin `git-credential-forge`, nicăieri într-un fișier sau
într-o linie de comandă. După push: `has_conflicts=false` la toate patru, CI pornit, comentariile
**neschimbate** ca număr, 👍-ul lui rmader păstrat pe !2954.

Raportul complet: `pipewire-5363/results/REBAZARE-22aug.md`.

### 3.2s 🔵 22 august, seara — CI verde pe toate patru, și comitul non-fatal remăsurat

**CI: toate patru verzi.** !2935 a picat prima dată, dar nu din cauza noastră — jobul
`build_on_debian: [armhf]` a murit cu *„Job failed (system failure): container … does not exist in
database"*, `step_script` a durat 2 secunde și n-a existat niciun `meson-logs` de încărcat.
Containerul Docker a dispărut de sub runner. Repornit jobul, a trecut. `!2935 success`,
`!2950 success`, `!2951 success`, `!2954 success`.

**11.1 pregătit, nimic trimis.** Tabelul de pe `failctrl` era din 21 august, pe master-ul vechi. Un
MR nou pleacă cu cifre de azi, deci l-am refăcut pe `f03a55d7f`.

Comitul non-fatal se aplică **singur pe master**, fără cel din !2954: `133c5b933`, 1 fișier, +10/-10.

Cele patru variante de plugin, reconstruite — toate cu md5 diferit de setul din 21 august, ceea ce e
dovada că baza chiar s-a schimbat:

| variantă | md5 21 aug | md5 22 aug |
|---|---|---|
| master | `61aafafce9a9` | `053a3ec68e65` |
| cauza | `161c3867909f` | `1fd9fd7afa80` |
| efect | `88b06ef903b8` | `0ea90e581cab` |
| ambele | `b25de7404f9b` | `ce0d67028b69` |

Tabelul cu șapte brațe se reproduce **rând cu rând** identic: rândul 3 (`cauza` singur, fail=1) dă
tot `TARGET NOT FOUND`, deci comitul non-fatal are cauză proprie; rândul 5 e controlul negativ pe
același dispozitiv; rândurile 6 și 7 repetă 1 și 2.

**A doua capcană a bancului, din aceeași familie ca prima.** Prima construcție a variantelor a ieșit
cu md5-uri **identice cu cele din 21 august** — imposibil dacă baza s-a mutat cu 11 comituri.
`fa-variante2.py` face `git checkout <sha> -- v4l2-utils.c`, ceea ce **pune fișierul și în index**,
iar următorul `git checkout --detach origin/master` eșuează tăcut cu *„Your local changes would be
overwritten"*; scriptul rebuild-uiește apoi din arborele vechi. `git checkout -- .` nu repară,
`git reset --hard` da. Notat în memorie lângă cealaltă.

Mașina pusă la loc: `failctrl` descărcat, `uvcvideo` înapoi pe `/dev/video0`, niciun daemon rămas,
`wt-ctrl` curat.

**Trimis ca !2963**, cu acordul lui vik: `spa: v4l2: keep reading the other controls when one
cannot be read`, un comit `133c5b933`, `mergeable`, fără conflicte, pe ramura din fork
`v4l2-nonfatal-control-read`.

**Înainte de a-l deschide am închis golul din argument.** Îl măsurasem doar pe `failctrl`, un driver
scris de mine, iar `vivid` nu poate produce cazul — deci întrebarea corectă era: se întâmplă pe o
cameră reală? Citit `uvc_query_ctrl()` din `drivers/media/usb/uvc/uvc_video.c`: traduce codul de
eroare al camerei în errno, iar **opt din cele nouă coduri din specificația UVC nimeresc drumul
fatal**:

| eroare UVC | errno | fatal azi |
|---|---|---|
| 1 Not ready | `-EBUSY` | da |
| 2 Wrong state | `-EACCES` | **nu** — singura scutită |
| 3 Power | `-EREMOTE` | da |
| 4 Out of range | `-ERANGE` | da |
| 5/6/7 Invalid unit/control/request | `-EIO` | da |
| 8 Invalid value in range | `-EINVAL` | da |
| STALL, timeout, deconectare | `-EPIPE`, `-ETIMEDOUT`, `-ENODEV` | da |

Comentariul din kernel la 5/6/7: *„firmware-ul nu a implementat corect controlul, sau a fost o
eroare hardware"* — adică exact `-EIO`, errno-ul pe care îl întoarce `failctrl`. Deci o cameră USB
obișnuită care răspunde „nu sunt gata" la un singur control face să dispară **tot nodul** din graf.
Argumentul a intrat în descriere; MR-ul nu mai stă pe un driver de laborator.

Raport: `pipewire-5363/results/NONFATAL-22aug.md`. Descrierea: `results/descrieri/MR-nonfatal.md`,
verificat că e identică cu cea live.

### 3.2t ⚠️ 22 august, seara — B generalizat, măsurat, și infirmat de propria măsurătoare

**Mecanismul propus ține.** În loc de „structura fixă pusă în față" (ce face patch-ul de azi, și ce
nu se poate generaliza), o **listă cu preferatul primul**: `width = { 1296, [320,1296] }`. Testat pe
caps pure: fixarea fără preferință dă 1296x736, un consumator cu preferință proprie primește ce
cere, iar costul e **1 structură** față de **4 la două proprietăți** și 16 la patru. Pe fracții,
lista `{30/1,[1/1,30/1]}` fixează la 30/1 iar intervalul singur la **1/1** — confirmă ce i-am scris
lui pobrn, defectul nu e specific dimensiunii.

**Patch-ul generalizat, scris și compilat:** `gstpipewireformat.c`, +56/-9 peste `f03a55d7f`, două
ajutoare comune folosite în toate cele trei locuri (`handle_int_prop`, `handle_rect_prop`,
`handle_fraction_prop`), fără special-cazare pe `SPA_FORMAT_VIDEO_size`.

**Și apoi măsurătoarea l-a infirmat.** `vivid` intrarea 1 (stepwise 16x16–16384x8640, `CROP_BOUNDS`
720x576), bază cu !2954 fără de care vivid nu e utilizabil, client `pipewiresrc → appsink`:

| daemon | client | dimensiune |
|---|---|---|
| fără C | fără B | 16x16 |
| fără C | **B nou** | 16x16 |
| **cu C** | fără B | **720x576** |
| **cu C** | B vechi | **720x576** |
| **cu C** | **B nou** | **720x576** |
| fără C, repetare | fără B | 16x16 |

**B nu schimbă nimic.** Nici vechiul, nici noul. C singur face toată treaba.

**Cauza, din cod:** `gst_pipewire_src_negotiate()` **nu fixează niciodată** — trimite caps-urile ca
filtru cu `gst_caps_to_format_all()` și **serverul** alege, luând `values[0]`, exact valoarea pe care
o schimbă C. Fixarea pe care B e proiectat s-o influențeze nu are loc pe acest drum.

**Ce înseamnă.** Mesajul comitului `11756ee0` spune *„Two changes, both needed … Verified separately:
with only the first change the application still got the smallest size"*. **Nu se reproduce.** Ori
observația originală venea din pipeline-ul lui Snapshot (`capsfilter + parsebin + multiqueue`), ori
era greșită. Nu s-a stabilit care — e următorul lucru de verificat, cu `masoara-snapshot.sh`, care
cere sesiune grafică.

**Nemăsurat:** `framerate` pe hardware — nici vivid intrarea 1, nici camera UVC nu anunță intervale
de cadre, doar valori discrete. Generalizarea la fracții e dovedită doar la nivel de caps.

**Lămurit în aceeași seară — B contează, dar în altă parte.** `gst_caps_from_format()` are **trei**
apelanți, nu unul: pe drumul de negociere (unde nu contează, tocmai s-a arătat) și de două ori în
`gstpipewiredeviceprovider.c` — **caps-urile pe care le vede o aplicație care enumeră camerele**.

Măsurat cu `devcaps.py`, daemon cu C, variante intercalate (`bnou` primul și ultimul):

| variantă | structuri | dacă aplicația le fixează |
|---|---|---|
| fără B | 82 | **16x16** |
| B vechi (din !2950) | **164** | 720x576 |
| **B nou (listă)** | **82** | **720x576** |

Trei lucruri deodată: B repară un defect real; varianta veche îl repară **dublând** numărul de
structuri (82 → 164, adică 82 × 16 la patru proprietăți); varianta nouă îl repară **fără nicio
creștere**.

Verificat și pe pipeline-ul **real** al lui GNOME Snapshot (`capsfilter + parsebin + multiqueue`),
două repetări: cu C → 720x576 indiferent de B; fără C → 16x16 indiferent de B. Deci pentru
negociere C singur ajunge, iar B repară enumerarea.

**Concluzia:** cele două jumătăți repară **simptome diferite**, cu cauze diferite, și niciuna n-o
acoperă pe cealaltă:

| | ce repară |
|---|---|
| **C** | clientul care nu cere nimic primește cel mai mic cadru |
| **B** | aplicația care enumeră camerele vede doar intervale |

Spargerea lui !2950 nu mai e doar igienă — e corectă pe fond.

**Verificat și pe audio, și NU se confirmă.** ALSA chiar pune o valoare cu sens în `values[0]` al
unui `Range` — `pw-cli enum-params` pe nodul audio arată `Range: 48000, 44100, 192000`, adică rata
preferată a plăcii urmată de limite. Dacă acel `values[0]` ar ajunge în caps, B ar repara un defect
audio de sine stătător. Măsurat pe toate trei variantele, intercalat: **nicio diferență**, toate dau
`rate → 1`. Cauza: caps-urile dispozitivelor audio vin din **șablonul elementului**
(`audio/x-alaw, rate=[1, 384000]`), nu din `EnumFormat`-ul nodului. Deci domeniul dovedit al lui B
rămâne doar furnizorul de dispozitive **video**. Bine că am verificat înainte să scriu altceva în MR.

**Ce trebuie rescris în mesajul comitului `11756ee0`:** propoziția *„the caps conversion keeps that
default as a fixed structure in front of the range so fixation lands on it"* descrie mecanismul care
**nu** funcționează la negociere, iar *„Verified separately: with only the first change the
application still got the smallest size"* e **falsă** așa cum e scrisă. Ambele se înlocuiesc cu
simptomul real: enumerarea dispozitivelor.

**Cele trei texte, scrise și gata** (`results/descrieri/`):

* `MR-A-step.md` — 129 de cuvinte. Valoarea greșită, diff-ul, ce descria de fapt pasul de 1296x736,
  și că nimic n-o impune azi.
* `MR-B-caps.md` — 471. Spune **explicit** că nu e vorba de negociere, ci de
  `gstpipewiredeviceprovider.c`, cu cifrele 82/16x16 vs 82/720x576 și cu 164 pentru varianta veche.
  Explică de ce lista în loc de structura duplicată, și declară două lucruri nemăsurate: calea
  fracțiilor (niciun dispozitiv de aici nu anunță interval de cadre) și că **B singur nu schimbă
  nimic pentru o sursă v4l2 azi**, pentru că acolo `values[0]` e chiar minimul.
* `NOTA-C-2950.md` — 284. Un comentariu nou, scurt, care spune ce a plecat din MR și pune **o
  singură întrebare** în loc să repete argumentul: e cel mai mic cadru un implicit pe care l-ar
  apăra până există o regulă centrală, iar dacă nu, ce ar pune în loc între timp.

**Nimic trimis.** Toate trei presupun `--force-with-lease` pe !2950, deci rămâne condiția: după ce
revine pobrn la fir.

Raport: `pipewire-5363/results/B-GENERALIZAT-22aug.md`. Patch-ul și uneltele:
`pipewire-5363/patches/B-generalizat/`.

### 3.2u 🟢 22 august — cele șapte MR-uri verificate pe MacBookPro14,1, de la zero

Patch-urile luate **direct din capetele MR-urilor de pe server**, nu din copii locale. PipeWire
master `f03a55d7f` și WirePlumber master `8cf44a43`, clonate proaspăt. Banc propriu pe socketul
`pw-verif`; sesiunea reală neatinsă.

**Trei dispozitive, fiecare pentru altceva:** facetimehd (`/dev/video0`, stepwise 320x240–1296x736
pas 8/1, `VIDIOC_G_SELECTION` **eșuează**), vivid (`/dev/video1`, 4 intrări, singurul driver cu
control-tablou), failctrl (`/dev/video5`, construit pentru kernelul de aici, injecția verificată).

**Compilare** cu ALSA, libcamera, v4l2 și GStreamer pornite — 1208 ținte, master în 3m06. Toate
șapte separat: **0 avertismente**. Toate șapte împreună: 4 fișiere, +166/-28, niciun conflict,
**0 avertismente**.

**!2950 și !2964 — ortogonale.** Alegerea de dimensiune din `EnumFormat`:

| | implicit | pas |
|---|---|---|
| master | 320x240 | **1296x736** |
| doar !2950 | **1296x736** | 1296x736 |
| doar !2964 | 320x240 | **8x1** |
| ambele | **1296x736** | **8x1** |

**!2965** — `GstDeviceMonitor` pe camera reală, cu !2950 prezent: fixarea trece de la **320x240** la
**1296x736**, cu **4 structuri în ambele cazuri**. Al doilea dispozitiv pe care se confirmă.

**!2954 și !2963 — cauza și efectul, separate pe hardware.** Pe master, vivid și failctrl **nu apar
deloc în graf**:

| | facetimehd | vivid | failctrl |
|---|---|---|---|
| master | 8 | absent | absent |
| doar !2954 | 8 | **55** | **absent** |
| doar !2963 | 8 | **56** | **6** |
| !2954 + !2963 | 8 | **55** | **6** |

!2954 singur nu ajută failctrl — rândul 3 din tabelul de pe 21 august, reprodus pe alt calculator.
Iar diferența de exact o proprietate pe vivid e chiar `String "S32 2 Element Array"`: cu !2963
singur e expus ca scalar fals, cu !2954 e corect absent.

**!2935** — `repro.py` pe camera reală, pool de 4, două repetări: la hold 1 și 3 identice (85), la
hold 4/5/6 master dă **exact 4 cadre** apoi tace, iar cu patch-ul 71/72/74 — ~84% din debitul liber.
*„Capture stops at exactly the pool size every time"*, confirmat literal.

**!2951** — `rescale.py`, trei redimensionări: master 90–91 cadre cu **3 pauze de ~1,3 s**, cu
patch-ul **205 cadre, 0 pauze**, sursa rămânând `640x480` tot timpul.

**Concluzia: toate șapte compilează și toate șapte fac exact ce spun**, fiecare cu observabilul lui
și cu control negativ unde există. Niciunul nu are efect în afara a ce declară.

**Cele două goluri, reluate cu `v4l2loopback` instalat.**

*Brațul cu I420 din !2935 — închis.* `v4l2loopback` cu `exclusive_caps=0`, alimentat de
`videotestsrc` cu I420, consumat de `pipewiresrc → x264enc(rc-lookahead=40) → fakesink`: **0 cadre
codate pe master, 0 cu patch-ul, 0 la repetarea pe master**. Patch-ul nu schimbă nimic acolo, exact
cum spune descrierea. Și motivul invocat se verifică direct: cu `GST_DEBUG=pipewiresrc:5`,
loopback-ul negociază **3 buffere**, iar pragul e `n_buffers > PRODUCER_HEADROOM` cu
`PRODUCER_HEADROOM = 3` — condiția e falsă, calea de copiere nu se activează. (În descriere scrie
„2 frames, then dead", aici ies 0; setări diferite de encoder, afirmația verificată nu depinde de
număr.)

*Calea fracțiilor din !2965 — rămâne deschisă, dar știm de ce.* `v4l2loopback` fără producător chiar
anunță `Continuous 0.001s - 4294967295.000s`, iar pluginul construiește `framerate: Range
implicit=25/1 min=1/4294967295 max=1000/1` — exact forma căutată. **Dar GStreamer respinge gama
întreagă** cu `range start is not smaller than end for GstFractionRange`, **77 de avertismente
identice în ambele brațe**, deci nu e cauzat de !2965: numitorul `4294967295` nu încape în `gint`.
`framerate` dispare din caps la ambele variante.

**Defect nou, găsit pe drum, pe master — investigat separat.** Pluginul v4l2 pasează o gamă de
fracții pe care GStreamer o refuză, iar `framerate` se pierde tăcut din caps-urile dispozitivului.

*Mecanismul, izolat:* fracțiile SPA au numărător și numitor `uint32`;
`gst_caps_set_simple(..., GST_TYPE_FRACTION_RANGE, ...)` le colectează ca `gint`. `4294967295` devine
**-1**, semnul se inversează, `gst_util_fraction_compare(1, -1, 1000, 1)` întoarce `1` în loc de `-1`,
GStreamer conchide *„range start is not smaller than end"* și aruncă gama cu un CRITICAL. 77 de
avertismente, câte unul pe structură. Locul: `handle_fraction_prop()`, cod din **2017**
(`7a66af71c`); partea din pluginul v4l2 care inversează intervalul e din 2024 (`669f53946`).

*Și nu e doar `v4l2loopback`.* Căutat în `drivers/media` din `linux-source-7.1`:
**`pci/mgb4/mgb4_vin.c`** — Digiteq Automotive MGB4, driver de **captură din kernel** — declară
`ival->stepwise.max.numerator = 0xFFFFFFFF`, exact aceeași valoare. Și acolo intervalul nici măcar
nu e absurd: `0xFFFFFFFF / 125000000` = **34,4 s** între cadre, adică „cel mai lent cadru admis";
numitorul e cel care nu încape, nu valoarea. Restul driverelor cu interval continuu declară valori
mici și nu sunt afectate.

*Unde ar sta reparația:* în `handle_fraction_prop()`, adică în stratul de conversie — pod-ul e corect
și consumatorii din afara GStreamer n-au nicio problemă. Simpla simplificare a fracției ar repara
`mgb4` (`gcd = 5`, deci `25000000/858993459`, care încape) dar **nu** și `v4l2loopback`, unde
`1/4294967295` e ireductibilă. Trebuie o limitare, nu doar o reducere.

*Nestabilit:* impactul practic (dacă un client chiar poate transmite de la o astfel de sursă),
dacă versiunea din distribuție e afectată la fel, și dacă vreo cameră UVC reală ajunge acolo.

**A doua trecere prin analiză, cerută de vik**, a confirmat tot — dar prin măsurare, nu deducție:
tipul `uint32_t`, liniile exacte, că `handle_fraction_prop` e singurul loc care construiește gama,
și că respingerea se produce **și pentru `mgb4`**, rulat cu cifrele lui. **O corectură la mine:**
prima dată scrisesem că valoarea lui `mgb4` e „absurdă". Nu e — 34,4 s între cadre e un „cel mai
lent cadru admis" rezonabil; numitorul e cel care nu încape, nu valoarea.

**Dovada directă**, structura `[0]` a caps-urilor pe master: `width=[2,8192], height=[1,8192],
colorimetry=...` — **niciun `framerate`**, față de facetimehd care în aceeași rulare are
`framerate=(fraction)30/1`.

**Patch scris și măsurat** (`patches/fractii/`, 49 de inserări): reduce fracția întâi — exact, și
suficient pentru `mgb4` — și scalează doar dacă tot nu încape, cazul lui `v4l2loopback`.

| | `range start is not smaller` | `dma_drm` | `framerate` în caps |
|---|---|---|---|
| master | **77** | 15 | **absent** |
| cu patch | **0** | 15 | `[ 1/2147483647, 1000/1 ]` |
| master, repetare | **77** | 15 | absent |

Prima versiune scotea `[ 0/1, ... ]`, dar `0/1` înseamnă „framerate variabil" în GStreamer, deci a
doua ridică numărătorul la 1.

**Impactul, măsurat — și mai mic decât părea.** Transmisia **nu** e afectată: 120 de cadre pe
master, 120 cu patch-ul, caps identice — negocierea nu trece prin caps-urile dispozitivului. Sub
`G_DEBUG=fatal-criticals` aplicația moare (cod 134) și pe master abortul e chiar la defectul nostru,
primul critical din drum — dar **patch-ul n-o salvează**: dispare acela și abortează imediat pe
`gst_video_dma_drm_format_from_gst_format`, un al doilea critical preexistent, fără legătură.

Ce rămâne ca impact real: **77 de CRITICAL-uri la fiecare enumerare** și `framerate` lipsă din
caps-urile pe care le vede orice aplicație care întreabă ce poate camera.

**Nemăsurat:** dacă 1.6.8 din distribuție e afectat la fel; cazul `mgb4` e din citirea codului, nu
din rulare (nu am placa); al doilea critical n-a fost investigat.

**Trimis ca !2966**, `gst: clamp a fraction that does not fit a GstFraction` — `877416f36`, un
comit, 1 fișier, +55/-5, `mergeable`.

**Unde trebuia trimis, verificat înainte:** fișierul e `src/gst/gstpipewireformat.c` din depozitul
**PipeWire**, livrat ca `gstreamer1.0-pipewire`. Kernelul e în regulă — `struct v4l2_fract` chiar are
câmpuri `__u32`, deci `0xFFFFFFFF` e o valoare legală; `GstFraction` e `gint` prin proiectare și nu
se schimbă. PipeWire e cel care convertește perechea fără să verifice, deci acolo stă reparația.

**Și, verificând, am găsit ceva despre propriul nostru !2965.** Ajutorul pe care îl introduce,
`set_pref_fraction_range()`, pasează `min->num, min->denom, max->num, max->denom` — toate `uint32` —
direct către `gst_caps_set_simple(GST_TYPE_FRACTION_RANGE, ...)`. **Duce defectul mai departe**, la
fel. Cele două se și ciocnesc textual, în ambele direcții (testat). Deci !2966 trebuie luat primul,
iar !2965 rebazat peste el. Scris în descrierile **amândurora** — la !2965 prin editarea descrierii,
fără postare nouă (`note=0` și după).

Descrierea lui !2966 spune deschis și ce **nu** face: transmisia nu e afectată, iar sub
`fatal-criticals` nu salvează aplicația, pentru că imediat în spate e alt critical. Și că lucrurile
despre `mgb4` vin din citirea driverului, nu din rularea lui.

**Și apoi vik a spus stop, pe bună dreptate: „deja simt ca ne invartim… hotaraste tu, fixezi cauza
nu efectul?"** Avea dreptate. Spusesem în aceeași descriere și că se ciocnesc textual, și că unul
trebuie rebazat pe celălalt — adică descrisesem o problemă fără s-o rezolv.

**Decizia: le-am unit.** !2965 și !2966 nu sunt cauză și efect — sunt **două defecte ale aceleiași
funcții**, conversia unei alegeri SPA în caps GStreamer. Unul pierde valoarea preferată, celălalt
trunchiază o valoare care nu încape. Rescriu aceleași linii, iar ajutorul din !2965 poartă defectul
lui !2966. Separate se blochează reciproc.

Greșeala mea a fost că am aplicat „sparge lucrurile" ca obicei, nu ca judecată. Regula pe care o
urmasem toată ziua — separă reparațiile de deciziile de politică — nu se aplica aici: amândouă sunt
reparații, în aceeași funcție.

**!2965 rescris**, două comituri în ordinea care funcționează: limitarea întâi, valoarea preferată
peste ea, cu ajutorul folosind conversia limitată. `acea30afa`, 1 fișier, +111/-11, fiecare comit
compilează separat cu 0 avertismente. Titlu nou: *„gst: two defects in the conversion from a SPA
choice to GstCaps"*. **!2966 închis**, cu o notă care spune de ce.

Măsurat, structura `[0]` a caps-urilor, integral:

```
master        facetimehd    width=(int)[ 320, 1296 ]      framerate=(fraction)30/1
              v4l2loopback  width=(int)[ 2, 8192 ]        <- niciun framerate
cu amandoua   facetimehd    width=(int){ 1296, [ 320, 1296 ] }
              v4l2loopback  width=(int){ 8192, [ 2, 8192 ] },
                            framerate=(fraction){ 25/1, [ 1/2147483647, 1000/1 ] }
```

77 de CRITICAL-uri → **0**, structuri neschimbate, iar valoarea preferată apare prima peste tot.

**La a doua întrebare a lui vik — e nevoie de Lenovo?** Nu. MacBook-ul are tot: facetimehd, vivid,
v4l2loopback, failctrl. Lenovo-ul adaugă doar o cameră UVC cu dimensiuni discrete, care e un control
de neregresie, nu ceva ce lipsește pentru identificare.

Raport: `pipewire-5363/results/DEFECT-FRACTII-22aug.md`. Patch și probe: `patches/fractii/`.

**Prima reacție din afară:** rmader a dat 👍 pe **!2950 și !2964** la 16:45–16:46, adică la douăzeci
de minute după restructurare și după nota postată. Are deja 👍 și pe !2954 din 19 august.

Raport: `pipewire-5363/results/VERIFICARE-MACBOOK-22aug.md`.

### 3.2v 🟢 22 august, noaptea — autoreview la toate cele șapte MR-uri, luate live

Cerut de vik: „le iei direct LIVE unde le vad toti si pe urma te apuci sa testezi toate". Patch-urile
aduse **din capetele MR-urilor de pe server**, nu din copii locale.

**O confuzie de-a mea, lămurită:** scrisesem „toate șapte | 8 comituri" și se citea ca opt PR-uri.
Sunt **7 MR-uri și 8 comituri**, pentru că !2965 are două. !2966 e închis.

**Patru dispozitive**, fiecare pentru altceva: facetimehd (camera reală), `v4l2loopback` (singura
sursă cu interval de cadre), `vivid` (singurul driver cu control-tablou), `failctrl` (scris pentru
controlul volatil care eșuează).

**Compilare:** toate șapte separat, 0 avertismente. Toate opt comiturile împreună: 4 fișiere,
+221/-30, niciun conflict, 0 avertismente.

**Fac ce spun — toate șapte:**

* **!2950 / !2964** ortogonale: implicit `320x240 → 1296x736` doar cu primul, pas
  `1296x736 → 8x1` doar cu al doilea, ambele cu amândouă.
* **!2965**: 77 criticals → 0, framerate revine în caps, valoarea preferată apare prima. **Și
  confirmă avertismentul din propria descriere** — singur nu schimbă dimensiunea facetimehd, fiindcă
  pe master `values[0]` chiar e minimul.
* **!2954 / !2963**: pe master vivid și failctrl **nu apar deloc** în graf. !2954 singur aduce vivid
  (55 prop.) dar **nu** failctrl; !2963 singur le aduce pe amândouă (56 / 6); împreună 55 / 6. Cele
  două proprietăți diferență e chiar `String "S32 2 Element Array"`.
* **!2935**: hold 1 și 3 identice (85), la hold 4 și 5 master dă **exact 4 cadre** apoi tace, cu
  patch-ul 71 și 73.
* **!2951**: 90 de cadre cu **3 pauze de ~1,3 s** → 205 cadre, **0 pauze**, sursa rămânând 640x480.

**Nemăsurat:** calea fracțiilor cu o preferință venită de la driver (nu există aici); cazul `mgb4`
din !2965 (din citirea codului, n-am placa); brațul I420 din !2935 (verificat separat mai devreme).

Raport: `pipewire-5363/results/AUTOREVIEW-7MR-22aug.md`.

### 3.2l 🟢 `verifica-bancul.sh` — răspunsul la „e bancul ok?", măsurat

Întrebarea a venit a 11-a oară, deci am făcut din ea un script: `~/pw-test/verifica-bancul.sh`,
opt verificări, ieșire 0/1. Verifică build-urile la zi (`ninja -n`), arborii git curați, ramurile
care există **doar local** (criteriul e comitul, nu numele — altfel rândul reclamă mereu și nu-l
mai citește nimeni), daemonii de banc rămași în urmă (căutați după executabil, **niciodată** cu
`pgrep -f`, care s-a potrivit de șase ori cu propria mea linie de comandă), modulele de test
încărcate, camerele prezente, dacă directorul suprascris `spa-ctrl` conține plugin-ul curat sau o
variantă de probă, și amprentele artefactelor principale.

La prima rulare a prins imediat capcana rămasă: `spa-ctrl` avea încă varianta **patch-uită**, deci
orice rulare ulterioară cu `PWSPA` ar fi folosit-o în tăcere. Repus cel curat, sonda depășită
(`vivid-ab.sh`, cea fără verificare de identitate) ștearsă. A doua rulare: totul verde.

Pe MacBook: `facetimehd` din DKMS (0.7.0.1, instalat pentru 7.1.7 și 7.1.8), cameră normală,
niciun proces de test rămas, 113 MB de capturi brute șterse din `~/.cache/facetimehd-fix/tmp`.
Tot aici, încă o sondă care nu putea reuși: verificarea provenienței modulului dădea „n/a" fiindcă
`modinfo` nu e în `PATH`-ul unei sesiuni neinteractive — nu fiindcă ar fi fost ceva în neregulă.

Raport complet: `pipewire-5363/results/VIVID-CAUZA-17aug.md`. Draft de răspuns, **nepostat**:
`results/NOTA-986-raspuns.md`. Patch-ul rămâne **local**, pe `wt-ctrl:v4l2-payload`.

### 3.4 ✅ Ce s-a închis din versiunea veche a acestei secțiuni

- ~~patch local `FTHD_BUFFERS` 4→8~~ — **retras**, trata simptomul ([secțiunea 3.1](#31-cauza-rădăcină-așa-cum-e-ea))
- ~~*fosta* secțiune 3.3, persistența patch-ului 4→8 în scriptul de setup~~ — **fără obiect**, patch-ul nu
  mai există *(numerele se refereau la structura veche a secțiunii; azi [secțiunea 3.3](#33--driver--șapte-pr-uri-la-patjakfacetimehd) e altceva)*
- ~~*fosta* secțiune 3.4, PR upstream `patjak/facetimehd` cu 4→8~~ — **nu s-a trimis și nu se mai trimite**;
  în locul lui au plecat cele șase de mai sus
- ~~„fix-ul propus e de o linie (`SPA_MIN(8u, …)`)"~~ — **infirmat** de analiza de cauză rădăcină

### 3.5 Ce înseamnă asta practic — încă nimic, pe mașina asta

**Atenție la o confuzie ușor de făcut:** !2933, !2941 și !2934 sunt în **master**-ul PipeWire, iar
Debian testing are `1.6.8-1`. Până când Debian livrează o versiune care le conține, pe mașina asta
nu s-a schimbat nimic. La fel pentru cele șase PR-uri de driver — sunt instalate local, dar nu sunt
încă upstream.

Workaround-ul rămâne valabil: `guvcview` sau camera din Chrome, ambele merg V4L2 direct și ocolesc
PipeWire.

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
pentru sacadare. Fix-ul real rămâne identificarea tab-ului ([secțiunea 4.2](#42-de-făcut)).

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
o problemă de sincronizare documentată ([secțiunea 2](#2--wifi-bcm4350--desincronizare-ring-msgbuf)). Probabilitate de succes: rezonabilă, nu garantată.
Beneficiul practic e mic (laptopul e mereu pe AC; lid-close ține sistemul pornit cu ecranul blocat; iar
pornirea nedorită la capac e deja rezolvată — [secțiunea 7](#7--rezolvate-arhivă-tehnică)). De aceea **P4, nu P1**.

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
- ❌ `intel_iommu=off` — interzis ([secțiunea 2.4](#24-mitigări-deja-aplicate-8-iul-live--etapa-5g-în-script)).
- ❌ Override de tabelă DMAR din initramfs (`CONFIG_ACPI_TABLE_UPGRADE`) — teoretic posibil, dar DMAR e
  consumată foarte devreme la boot; o tabelă greșit reconstruită poate dezactiva IOMMU sau împiedica
  boot-ul. **Risc real pentru 3 linii cosmetice.**

**Verdict: won't-fix.**

### 6.2 Restul limitărilor hardware — won't-fix (referință)

| Item | De ce nu se poate |
|---|---|
| **Suspend S3 / hibernare** | S3 nu se trezește fiabil pe NVMe+EFI Apple → blocat via `systemctl mask` (ETAPA 5e). Hibernarea ar moșteni aceleași probleme de resume. Pentru s2idle vezi [secțiunea 5](#5--suspend--s2idle) |
| **Broadcom WiFi/BT la repornire** | `reboot` nu power-cycle-ază cipul → poate rămâne mut (`Reset failed -110`). **Dar e doar un factor agravant, nu cauza unică** — vezi [secțiunea 1.3](#13-teoria-warm-reboot--măsurată-nu-presupusă-27-iul) (14% din boot-uri, jumătate după opriri lungi) |
| **Firmware Apple BCM4350 (WiFi/BT)** | Fișierele nu există public și nici în macOS pt. Mac-urile non-T2: calibrarea stă în OTP-ul cipului (citit deja de `brcmfmac`), datele regulatorii în firmware-ul Apple „bmac" (split-MAC, incompatibil). Investigat 8 iul 2026 — mesajele „failed to load …MacBookPro14,1.*" rămân cosmetice |
| **facetimehd PLL lock** | `Failed to lock S2 PLL` — bug upstream `patjak/facetimehd`; camera merge pe PLL alternativ |
| **ASPM PCIe** | `can't disable ASPM` — Apple BIOS restricționează; `pcie_aspm=off` ar avea alte efecte |
| **Apple ACPI / SGX noise** | `AE_ALREADY_EXISTS`, `_OSC/_PDC AE_NOT_FOUND`, SSDT duplicate, SGX disabled — Apple nu implementează metode ACPI standard / dezactivează SGX. Pur cosmetic |

---

## 7. ✅ Rezolvate (arhivă tehnică)

Probleme închise. Păstrate cu detaliul tehnic care contează, ca să nu fie re-deschise sau re-diagnosticate.

⚠️ **Excepție: [secțiunea 7.9](#79-️-capcana-de-la-fiecare-upgrade-de-kernel--linux-source-întâi) nu e o problemă închisă.** E o capcană recurentă, care se manifestă doar la
upgrade de kernel; stă aici pentru că acolo o cauți, nu în lista de probleme active.

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
audio-ului pică. Vezi [secțiunea 7.9](#79-️-capcana-de-la-fiecare-upgrade-de-kernel--linux-source-întâi).

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
**Alta** e problema din [secțiunea 1](#1--bluetooth-bcm4350c0--init-eșuat-la-14-din-boot-uri) (`-110` la init) — nu confunda cele două.

### 7.8 Restul

- **Fan floor `fan1_min=3500`** — udev scria ATTR înainte ca `applesmc` să expună atributul (race) →
  înlocuit cu oneshot `macbook-fan-floor.service` care așteaptă atributul. Verificat la reboot.
- **RAPL 22 W / 30 W** — Apple lasă PL1 la 100 W. Race rezolvat după **4 iterații** (`.path` cu inotify
  nu e fiabil pe sysfs; final: regulă udev + reinit thermald, ordonat față de thermald), validat 8/8
  boot-uri. Azi: `constraint_0_name=long_term` = 22 W, `constraint_1_name=short_term` = 30 W.
- **Reboot hang** — `reboot=pci` în GRUB (ETAPA 5a), testat.
- **Suspend hang S3** — toate sleep target-urile `masked` (ETAPA 5e), 4/4 confirmat.
- **`udevadm settle` hang pe 7.0.10** — bound `--timeout=5` (ETAPA 8b); era efect al bug-ului audio.
- **BT „down" după upgrade 7.0.10** — era stare Broadcom după repornire, **nu** kernel (vezi [secțiunea 1](#1--bluetooth-bcm4350c0--init-eșuat-la-14-din-boot-uri)).

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

**Eliminate, cu dovada:** termic (66 °C sub încărcare, prag 100 °C, zero throttling în boot-urile
care au murit), suspendare (ținte `masked`, zero `PM: suspend` în tot istoricul — reverificat 8 aug),
**kernel panic** (`kernel.panic=10` ar fi repornit în 10 s; pauzele reale până la boot-ul următor au
fost **92 s** și **98 s** — deci nu a intrat în panic), disc (zero erori NVMe/EXT4), DMA/IOMMU,
MCE/RAM, și WiFi ca declanșator direct (ultimele evenimente sunt cu ore înainte de fiecare cădere).

**De ce nu se prinde nimic:** `iTCO_wdt: device disabled by hardware/BIOS` — firmware-ul Apple
dezactivează watchdog-ul hardware. `/sys/fs/pstore` e gol, netconsole nu e configurat. Mașina nu are
în acest moment **niciun** mecanism prin care să lase o urmă când moare.

**Cele două ipoteze rămase**, pe care jurnalele nu le pot separa:

1. **blocaj complet al kernelului** — nimic nu mai rulează, deci nimic nu mai scrie; ar fi urmat de
   apăsarea butonului după ~90 s, ceea ce se potrivește cu pauzele măsurate;
2. **întrerupere de alimentare la nivel SMC/firmware** — la fel de tăcută pentru sistemul de operare.

⚠️ Alimentarea **nu e eliminată** — e eliminată doar *pe intervalul măsurat* (tensiunea bateriei
perfect plată, 12,399–12,401 V, până cu 7 minute înainte). Indiciu slab pentru (2): după o cădere,
bateria pierduse ~1,3 Wh și se încărca la 12,2 W, deci sistemul trăgea din baterie sub încărcare —
alimentatorul de 61 W poate să nu acopere vârful. Bateria e la **62% sănătate, 1436 de cicluri**.

Kernelul e `tainted` de două module out-of-tree (`facetimehd`, `snd_hda_codec_cs8409`). Un blocaj de
driver e plauzibil pentru două dintre căderi, dar **nu explică** cele trei nocturne, cu mașina inactivă.

### 8.1 🟢 De făcut, în ordinea raportului cost/informație — `⏳ NIMIC APLICAT`

- [ ] **1. netconsole către al doilea PC.** Trimite mesajele de kernel prin UDP pe măsură ce apar,
      deci prinde un oops *înainte* ca mașina să moară. Singurul lucru care transformă „nimic în
      jurnal" în „avem urma". Risc zero, reversibil.
- [ ] **2. Panic pe blocaj** — `panic_on_oops=1`, `softlockup_panic=1`, `hardlockup_panic=1`.
      **Doar împreună cu (1)**, altfel se pierde și informația care există azi.
- [ ] **3. Separare pe încărcare** — o noapte cu `facetimehd` pe blacklist. Dacă opririle nocturne
      continuă, driverul e exclus definitiv; dacă se opresc, e primul suspect.
- [ ] **4. Alimentare**, dacă (3) nu lămurește: consumul măsurat la priză sub încărcare, sau alt
      alimentator.

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
| `intel_iommu=off` | Transformă DMA blocat în corupere silențioasă de memorie | [secțiunea 2.4](#24-mitigări-deja-aplicate-8-iul-live--etapa-5g-în-script) |
| `intel_iommu=on,igfx_off` pentru mesajele DMAR | `igfx_off` afectează doar iGPU; mesajele vin din ANDD | E9 |
| Override de tabelă DMAR din initramfs | Risc de boot/IOMMU pentru 3 linii de log | [secțiunea 6.1](#61-dmar--și-de-ce-fix-ul-care-păstrează-iommu-nu-există) |
| Extragerea `.hcd` din macOS | Nu rezolvă `-110`; ne-redistribuibil; transportul citat e greșit (USB vs UART) | E11 |
| Plafonare turbo / zswap / modificări thermald | Respinse pe datele de 3 h din 19 iul | [secțiunea 4.5](#45--ce-nu-se-face-respins-pe-datele-de-3-h) |
| DKMS fork pentru `brcmfmac` (ca primă opțiune) | Cost de întreținere mare; upstream e calea corectă | [secțiunea 2.5](#25-opțiuni-deschise) |
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

`macbook-debian-optimize.sh`: 17 pași, dintre care **pasul 17** = NVRAM `AutoBoot` ([secțiunea 7.1](#71-nvram-autoboot--pornire-nedorită-la-ridicarea-capacului-pasul-17-din-optimize)).

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
| B | `DMAR: Failed to find handle … I2C0/I2C2/UA00` | 3×/boot | intrări ANDD Apple nerezolvabile ([secțiunea 6.1](#61-dmar--și-de-ce-fix-ul-care-păstrează-iommu-nu-există)) |
| B | `Bluetooth: hci0: BCM: failed to write update baudrate (-16)` | 168/195 boot-uri | BCM4350 refuză upgrade baud; rămâne 115200, BT OK ([secțiunea 1](#1--bluetooth-bcm4350c0--init-eșuat-la-14-din-boot-uri)) |
| **A!** | `Bluetooth: hci0: BCM: failed to write update baudrate (-110)` + `Reset failed (-110)` | **27/195 boot-uri** | **NU e benign: BT mort tot boot-ul** ([secțiunea 1](#1--bluetooth-bcm4350c0--init-eșuat-la-14-din-boot-uri)) |
| B | `Bluetooth: hci0: BCM: firmware Patch file not found 'brcm/BCM.hcd'` | 168/195 | firmware patch opțional, nu există în Debian |
| B | `brcmfmac: failed to load …MacBookPro14,1.bin/.txt/.clm_blob` | ~8×/boot | caută variante Apple, cade pe generic (WiFi OK; fișierele nu există — [secțiunea 6.2](#62-restul-limitărilor-hardware--wont-fix-referință)) |
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
**Două excepții care NU sunt zgomot:** `-110` la Bluetooth ([secțiunea 1](#1--bluetooth-bcm4350c0--init-eșuat-la-14-din-boot-uri)) și `Invalid packet id` la WiFi ([secțiunea 2](#2--wifi-bcm4350--desincronizare-ring-msgbuf)).

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

# --- Bluetooth: corelația eșec vs. durata opririi (secțiunea 1.3) ---
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
   linie `Rebooting.`/`Powering off.` în tot jurnalul. De aici nevoia hook-ului din [secțiunea 1.4](#14--de-făcut).
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
| **E3** | Daemon de ventilator care citește `thermal_zone0` ca temperatură CPU și scrie `fan1_manual=1` | **Două erori.** (a) `thermal_zone0` = **BAT0** (bateria, 36,3°C); CPU-ul e `thermal_zone1 = x86_pkg_temp` (62°C) — praguri de 75°C nu s-ar atinge niciodată, daemonul n-ar face nimic. (b) `fan1_manual=1` **scoate SMC-ul din buclă** (`README.md` avertizează explicit) — dacă daemonul moare, ventilatorul rămâne fixat, fără rampă de siguranță. Plus plafon propus 6200 < `fan1_max` real 7200. Design corect: [secțiunea 4.3](#43--p5--daemon-de-ventilator-designul-corect) |

### C.2 Ar face fix-ul inoperant

| # | Propunerea | Realitatea verificată |
|---|---|---|
| **E4** | Patch `brcmfmac` în `brcmf_msgbuf_rx_process()`, apel `brcmf_msgbuf_pktid_find()` | Niciuna dintre funcții nu există în kernel 7.1 (`grep -c` = 0 în `msgbuf.c`). Numele reale: **`brcmf_msgbuf_process_rx_complete()`** (l. 1147) și **`brcmf_msgbuf_get_pktid()`** (l. 367). Patch-ul nu s-ar aplica. Versiunea corectată: [secțiunea 2.6](#26-patch-defensiv--versiunea-corectă-dacă-se-merge-pe-b-sau-c) |
| **E5** | `dev_kfree_skb_any(skb)` pe un skb cu `nr_frags` corupt | Chiar asta e calea care crapă: `skb_release_data()` iterează `shinfo->nr_frags` și dereferențează fiecare fragment. Eliberarea unui skb cu `nr_frags = 125` **re-declanșează** GPF-ul pe care patch-ul vrea să-l prevină. Trebuie sanitizat **înainte** de eliberare |
| **E6** | Shim `LD_PRELOAD` pe `VIDIOC_REQBUFS` care „forțează PipeWire să aloce 8 buffere" | Atacă stratul greșit. `REQBUFS` e apelat de SPA **cu numărul deja negociat** cu clientul (tot 4). Un shim care umflă `req.count` în kernel nu spune nimănui de deasupra: SPA tot își dimensionează array-ul la 4, Snapshot tot le ține pe toate 4. **Dovadă:** driver nepatch-uit + `min-buffers=5` → **0 cadre** (`mmap_init -ENOMEM`) — numărul curge de sus în jos. În plus **driverul e deja la 8**. Pârghia reală e `min-buffers` pe client |
| **E7** | `systemctl unmask s2idle.target` | `s2idle.target` nu există în systemd. Țintele reale: `sleep`, `suspend`, `hibernate`, `hybrid-sleep`, `suspend-then-hibernate`. Selecția s2idle se face din `mem_sleep_default=s2idle` sau `/sys/power/mem_sleep` |
| **E8** | Politică Chrome cu `TabFreezingEnabled` + `BackgroundTracingAllowed` | Ambele **ABSENTE** din binarul Chrome 150 — ar fi ignorate în tăcere. JSON valid: [secțiunea 4.4](#44--politica-chrome--json-valid-pe-chrome-150) |
| **E9** | `intel_iommu=on,igfx_off` elimină `DMAR: Failed to find handle` păstrând IOMMU | `igfx_off` scoate din translație **doar iGPU-ul**. Mesajele vin din intrările **ANDD** (I2C0/I2C2/UA00) — nicio legătură cu grafica. Ar rămâne identice. [Secțiunea 6.1](#61-dmar--și-de-ce-fix-ul-care-păstrează-iommu-nu-există) |
| **E10** | `PATCH[0]` în `dkms.conf` face patch-ul camerei să supraviețuiască reinstalării | Rezolvă doar jumătate: scriptul recreează **tot** `/usr/src/facetimehd-$VER` prin `cp -r` din clona proaspătă, deci și `dkms.conf` editat și `patches/` dispar. (`PATCH[0]`/`PATCH_MATCH[0]` **sunt** directive DKMS reale — problema e alta.) **Devenit fără obiect 8 aug:** patch-ul pe care trebuia să-l persiste a fost retras, vezi [secțiunea 3.4](#34--ce-s-a-închis-din-versiunea-veche-a-acestei-secțiuni) |
| **E11** | `.hcd`-ul extras din macOS ar rezolva „inclusiv upgrade-ul de baudrate" | **Trei probleme.** (a) Calea citată e `IOBluetoothHostControllerUSBTransport.kext`, dar cipul e pe **UART**, nu USB. (b) `.hcd` e un patch aplicat **după** reset-ul reușit; pe boot-urile cu `-110` secvența moare înainte — nu apare nici `chip id 92`, nici căutarea `.hcd` ([secțiunea 1.2](#12-statistica--reverificată-pe-196-de-boot-uri-19-mai--8-aug)). (c) Eroarea `-16` are cauza în ACPI (`No reset resource`), nu în lipsa patch-ului |

### C.3 Afirmații nesusținute (nu greșite dovedit, dar nici verificabile)

| Afirmație | Observație |
|---|---|
| senzorul ALS e „Intersil ISL29023" | Din Linux se vede doar `ACPI0008` / driverul generic `acpi-als`. Neverificabil — de nu prezentat ca fapt |
| fișierul de stare rfkill = `platform-applespi:bluetooth` | Calea reală: `…/rfkill/pci-0000:00:1e.0-platform-dw-apb-uart.2:bluetooth`. Mecanismul descris e corect, numele nu ([secțiunea 7.7](#77-bluetooth-nu-merge-deloc--soft-block-rfkill-persistat)) |
| „Apple lasă PL1=100 W, **PL2=125 W**" | PL1=100 W e confirmat. PL2=125 W nu apare în nicio măsurătoare proprie |
| plafonul de 16 MB al driverului = `FTHD_MAX_BUFFER_SIZE` | Constanta **nu există** în sursă. Observația rămâne validă ca notă istorică; PR-ul cu 8 buffere pentru care conta nu s-a mai trimis ([secțiunea 3.4](#34--ce-s-a-închis-din-versiunea-veche-a-acestei-secțiuni)) |
| „SMC așteaptă 6-10 s peste 85°C"; „PROCHOT → 1,4 GHz" | Ordinul de mărime al lag-ului e confirmat de README (~20-30 s la sarcină bruscă), dar cifrele exacte nu vin din nicio măsurătoare. Monitorizarea de 3 h a măsurat altceva: ventilator ≥7000 RPM ~85% din timp și **un singur** episod de throttling |
| „100% solvabil" ×5 | Niciuna dintre cele 5 nu e demonstrat 100% solvabilă; 2 din 5 aveau propuneri care nu funcționează (E6) sau nu se aplică (E4) |

### C.4 Ce era corect în acele documente și s-a păstrat aici

NVRAM `AutoBoot` binar vs `auto-boot` ASCII, inclusiv masca `07 00 00 00` vs `07 00 00 80` și respingerea
cu `-EINVAL` ([secțiunea 7.1](#71-nvram-autoboot--pornire-nedorită-la-ridicarea-capacului-pasul-17-din-optimize)) · istoricul RAPL în 4 iterații ([secțiunea 7.8](#78-restul)) · mecanismul race-ului rfkill ([secțiunea 7.7](#77-bluetooth-nu-merge-deloc--soft-block-rfkill-persistat)) ·
aritmetica bufferelor camerei, 1280×720 NV12 ≈ 1,38 MB × 8 ≈ 11 MB (azi fără obiect, [secțiunea 3.4](#34--ce-s-a-închis-din-versiunea-veche-a-acestei-secțiuni)) · regresia audio 7.0.10
([secțiunea 7.6](#76-audio-rupt-pe-7010)) · `PATCH[0]`/`PATCH_MATCH[0]` ca directive DKMS reale (E10) · ghidul de demontare A1708 —
pentalobe P5, T5 înăuntru, bateria deconectată prima, PTM7950 pentru die expus ([secțiunea 4.2](#42-de-făcut)).
