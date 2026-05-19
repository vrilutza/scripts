# TODO — îmbunătățiri opționale după test fresh

După ce am un script stabil testat pe fresh Debian Testing install, continui cu astea.

## Ce **lipsește** dar e opțional

| Componentă | Ce face | Impact | Risc |
|---|---|---|---|
| **`thermald`** (Intel thermal daemon) | Managementul corect al temperaturii CPU — previne throttling agresiv | Mediu (MBP 2017 se încălzește pe Linux) | Mic, e oficial Intel/Debian |
| **`tlp`** (battery/power mgmt) | Optimizări consum baterie pe diverse subsisteme | Mediu (laptop durează mai mult din priză) | Mic, dar poate intra în conflict cu unele setări existente |
| **`hid_apple` fn-mode** (F-keys vs media keys) | Schimbă comportamentul F1-F12 (media keys vs F-keys reale) | Preferință pură | Zero, e parametru kernel |

## Implementate

- **Touchpad UX** — tap-to-click + natural scroll + disable-while-typing (ETAPA 7/7 in script)

## Ce NU recomand să adăugăm
- **`mbpfan`** — vechi, instabil, fan control built-in pe MBP 2017 merge OK
- **GNOME extensions / Dash-to-Dock** — preferință pură, nu hardware fix
- **Microphone gain custom** — codec-ul Cirrus se descurcă singur

## Onest

Pentru testul tău de stabilitate fresh — **scriptul e complet pentru hardware**. Adăugările de mai sus sunt nice-to-have, nu blocante. Recomand:

1. **Întâi:** testează fresh ce avem acum (asta era planul tău)
2. **Dacă observi încălziri:** adăugăm **thermald**
