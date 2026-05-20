# TODO — îmbunătățiri opționale după test fresh

După ce am un script stabil testat pe fresh Debian Testing install, continui cu astea.

## Ce **lipsește** dar e opțional

| Componentă | Ce face | Impact | Risc |
|---|---|---|---|
| **`hid_apple` fn-mode** (F-keys vs media keys) | Schimbă comportamentul F1-F12 (media keys vs F-keys reale) | Preferință pură | Zero, e parametru kernel |

## Implementate

- **Touchpad UX** — tap-to-click + natural scroll + disable-while-typing (ETAPA 7/8 in script)
- **Thermal management** — thermald 2.5.10 (apt) + lm-sensors + RAPL PL1=22W/PL2=30W Apple-like via systemd-tmpfiles (ETAPA 8/8 in script)

## Ce NU recomand să adăugăm
- **`mbpfan`** — vechi, instabil, fan control built-in pe MBP 2017 merge OK
- **GNOME extensions / Dash-to-Dock** — preferință pură, nu hardware fix
- **Microphone gain custom** — codec-ul Cirrus se descurcă singur

## Onest

Pentru testul tău de stabilitate fresh — **scriptul e complet pentru hardware**. Adăugările de mai sus sunt nice-to-have, nu blocante. Recomand:

1. **Întâi:** testează fresh ce avem acum (asta era planul tău)
2. **Dacă vrei mai mult control la F-keys vs media keys:** `hid_apple` fn-mode (5 minute)
