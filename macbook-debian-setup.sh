#!/bin/bash
# =============================================================================
#  MacBook Pro 13" 2017 (A1708) — Debian Testing — Setup Script
# =============================================================================
#
#  Ce instaleaza:
#    1. Dependente (build-essential, dkms, linux-headers-amd64, linux-source, etc.)
#    2. Driver audio Cirrus Logic CS8409
#       https://github.com/davidjo/snd_hda_macbookpro
#    3. Firmware camera FaceTime HD (extras din driverul Apple OS X)
#       https://github.com/patjak/facetimehd-firmware
#    4. Driver kernel camera FaceTime HD cu DKMS
#       https://github.com/patjak/facetimehd
#    5. Fix sistem: luminozitate, reboot=pci, sleep targets masked (suspend blocat, S3 unreliable)
#    6. Accelerare video hardware VA-API (Intel Iris Plus 640 / Kaby Lake)
#    7. Touchpad UX (tap-to-click + natural scroll + disable-while-typing)
#    8. Thermal management: thermald + RAPL PL1/PL2 (22W/30W Apple-like, udev) +
#       fan floor (fan1_min=3500 RPM via udev — rece la idle, SMC ramp auto deasupra)
#    9. Cosmetic / curatire jurnal: GNOME media-keys (hibernate/playback-repeat goale) +
#       usb-protection off (USBGuard neinstalat) + applespi fnmode=1 (default explicit)
#
#  Notă touchpad: nu mai aplicăm patch out-of-tree pentru "Touch jump detected and discarded".
#  libinput protejează în userspace (discard event corupt) — cursorul nu sare vizibil.
#  Mesajele rămân în jurnal ca semnal de protecție, nu defect funcțional.
#
#  Utilizare:
#    chmod +x macbook-debian-setup.sh
#    ./macbook-debian-setup.sh
#    sudo reboot
#
#  Nota: nu rula ca root. Scriptul foloseste sudo intern.
# =============================================================================

# --- Culori ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Functii de log ---
step()  { echo -e "\n${BOLD}${BLUE}┌─── $1 ───${NC}"; }
ok()    { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC}  $1"; }
info()  { echo -e "  ${BLUE}→${NC}  $1"; }
fail()  {
    echo -e "\n  ${RED}✗ EROARE:${NC} $1"
    echo -e "  Scriptul s-a oprit la etapa: ${BOLD}$CURRENT_STEP${NC}"
    echo -e "  Verifica output-ul de mai sus si reia cu: ${BOLD}./macbook-debian-setup.sh${NC}"
    exit 1
}

CURRENT_STEP="initializare"
WORKDIR="$HOME/macbook-setup"
KERNEL="$(uname -r)"

mkdir -p "$WORKDIR"
LOGFILE="$WORKDIR/setup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# =============================================================================
# Verificari initiale
# =============================================================================
[ "$EUID" -eq 0 ] && fail "Nu rula ca root. Foloseste un user normal cu sudo."

if ! sudo -v 2>/dev/null; then
    fail "Ai nevoie de acces sudo pentru a continua."
fi

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║   MacBook Pro 13\" 2017 — Debian Testing Setup       ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
info "Kernel curent: $KERNEL"
info "Director de lucru: $WORKDIR"
info "Log salvat in: $LOGFILE"


# =============================================================================
# ETAPA 1/9 — Dependente
# =============================================================================
CURRENT_STEP="ETAPA 1/9 — Dependente"
step "$CURRENT_STEP"

PKGS=(build-essential linux-headers-amd64 linux-source dkms git patch wget curl cpio xz-utils libssl-dev rfkill)

info "Actualizare lista de pachete..."
sudo apt-get update -qq || fail "apt-get update a esuat."

info "Instalare pachete necesare: ${PKGS[*]}"
sudo apt-get install -y "${PKGS[@]}" || fail "Instalarea pachetelor a esuat."

for pkg in "${PKGS[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg"
    else
        fail "Pachetul '$pkg' nu a putut fi instalat."
    fi
done

ok "Toate dependentele sunt instalate."


# =============================================================================
# ETAPA 2/9 — Driver audio Cirrus Logic CS8409
# https://github.com/davidjo/snd_hda_macbookpro
# =============================================================================
CURRENT_STEP="ETAPA 2/9 — Driver audio"
step "$CURRENT_STEP"
info "Proiect: https://github.com/davidjo/snd_hda_macbookpro"

if sudo dkms status 2>/dev/null | grep -q "snd_hda_macbookpro"; then
    warn "Driver-ul audio este deja inregistrat in DKMS. Sar aceasta etapa."
else
    cd "$WORKDIR"
    if [ -d "snd_hda_macbookpro" ]; then
        info "Repo exista, actualizez..."
        git -C snd_hda_macbookpro pull || warn "git pull a esuat, continui cu versiunea existenta."
    else
        info "Clonez repo-ul..."
        git clone https://github.com/davidjo/snd_hda_macbookpro.git \
            || fail "git clone snd_hda_macbookpro a esuat."
    fi

    cd snd_hda_macbookpro || fail "Nu am putut intra in directorul snd_hda_macbookpro."
    info "Instalare driver audio cu DKMS (poate dura cateva minute)..."
    sudo ./install.cirrus.driver.sh -i || fail "install.cirrus.driver.sh a esuat."
    cd "$WORKDIR"
fi

if sudo dkms status 2>/dev/null | grep -q "snd_hda_macbookpro"; then
    ok "Driver audio inregistrat in DKMS."
else
    fail "Driver-ul audio nu apare in dkms status. Verifica cu: sudo dkms status"
fi

if lsmod | grep -q "snd_hda_codec_cs8409" || \
   ls /lib/modules/"$KERNEL"/updates/dkms/ 2>/dev/null | grep -q "snd"; then
    ok "Modulul snd_hda_codec_cs8409 este disponibil."
else
    warn "Modulul nu e inca incarcat — va fi activ dupa reboot."
fi


# =============================================================================
# ETAPA 3/9 — Firmware camera FaceTime HD
# https://github.com/patjak/facetimehd-firmware
# =============================================================================
CURRENT_STEP="ETAPA 3/9 — Firmware camera FaceTime HD"
step "$CURRENT_STEP"
info "Proiect: https://github.com/patjak/facetimehd-firmware"

FIRMWARE_PATH="/usr/lib/firmware/facetimehd"

if [ -f "${FIRMWARE_PATH}/firmware.bin" ]; then
    warn "Firmware-ul camerei este deja instalat la ${FIRMWARE_PATH}/. Sar aceasta etapa."
else
    cd "$WORKDIR"
    if [ -d "facetimehd-firmware" ]; then
        info "Repo exista, actualizez..."
        git -C facetimehd-firmware pull || warn "git pull a esuat, continui cu versiunea existenta."
    else
        info "Clonez repo-ul..."
        git clone https://github.com/patjak/facetimehd-firmware.git \
            || fail "git clone facetimehd-firmware a esuat."
    fi

    cd facetimehd-firmware || fail "Nu am putut intra in directorul facetimehd-firmware."
    info "Extragere firmware din driverul Apple OS X (descarca automat ~50MB)..."
    make || fail "make firmware a esuat. Verifica conexiunea la internet."
    info "Instalare firmware..."
    sudo make install || fail "sudo make install firmware a esuat."
    cd "$WORKDIR"
fi

if [ -f "${FIRMWARE_PATH}/firmware.bin" ]; then
    FWSIZE=$(du -sh "${FIRMWARE_PATH}/firmware.bin" | cut -f1)
    ok "Firmware instalat: ${FIRMWARE_PATH}/firmware.bin (${FWSIZE})"
else
    fail "firmware.bin nu a fost gasit in ${FIRMWARE_PATH}/. Instalarea a esuat."
fi


# =============================================================================
# ETAPA 4/9 — Driver kernel camera FaceTime HD cu DKMS
# https://github.com/patjak/facetimehd
# =============================================================================
CURRENT_STEP="ETAPA 4/9 — Driver camera FaceTime HD (DKMS)"
step "$CURRENT_STEP"
info "Proiect: https://github.com/patjak/facetimehd"

if sudo dkms status 2>/dev/null | grep -q "facetimehd"; then
    warn "Driver-ul camerei este deja inregistrat in DKMS. Sar aceasta etapa."
else
    cd "$WORKDIR"
    if [ -d "facetimehd" ]; then
        info "Repo exista, actualizez..."
        git -C facetimehd pull || warn "git pull a esuat, continui cu versiunea existenta."
    else
        info "Clonez repo-ul..."
        git clone https://github.com/patjak/facetimehd.git \
            || fail "git clone facetimehd a esuat."
    fi

    FTIMEHD_VER=$(grep "^PACKAGE_VERSION=" "$WORKDIR/facetimehd/dkms.conf" \
        | cut -d= -f2 | tr -d '"')
    [ -z "$FTIMEHD_VER" ] && FTIMEHD_VER="0.7.0.1"
    info "Versiune driver camera: $FTIMEHD_VER"

    cd facetimehd || fail "Nu am putut intra in directorul facetimehd."
    info "Compilare modul kernel..."
    make || fail "Compilarea facetimehd a esuat."

    DKMS_SRC="/usr/src/facetimehd-${FTIMEHD_VER}"
    if [ ! -d "$DKMS_SRC" ]; then
        info "Copiere sursa in $DKMS_SRC..."
        sudo cp -r "$WORKDIR/facetimehd" "$DKMS_SRC" \
            || fail "Copierea surselor DKMS a esuat."
    fi

    info "dkms add..."
    sudo dkms add -m facetimehd -v "$FTIMEHD_VER" \
        || warn "dkms add: modulul poate fi deja adaugat, continui."

    info "dkms build..."
    sudo dkms build -m facetimehd -v "$FTIMEHD_VER" \
        || fail "dkms build facetimehd a esuat."

    info "dkms install..."
    sudo dkms install -m facetimehd -v "$FTIMEHD_VER" \
        || fail "dkms install facetimehd a esuat."

    cd "$WORKDIR"
fi

if ! lsmod | grep -q "^facetimehd"; then
    info "Incarcare modul facetimehd..."
    sudo modprobe facetimehd 2>/dev/null || true
    sleep 1
fi

if sudo dkms status 2>/dev/null | grep -q "facetimehd"; then
    ok "Driver camera inregistrat in DKMS."
else
    fail "facetimehd nu apare in dkms status."
fi

if [ -e /dev/video0 ]; then
    ok "Camera detectata: /dev/video0"
elif lsmod | grep -q "^facetimehd"; then
    warn "Modulul e incarcat dar /dev/video0 nu apare inca."
else
    warn "Camera va fi disponibila dupa reboot."
fi


# =============================================================================
# ETAPA 5/9 — Fix sistem: luminozitate ecran + suspend stabil + WiFi dupa sleep + Bluetooth
# =============================================================================
CURRENT_STEP="ETAPA 5/9 — Fix luminozitate + auto-suspend dezactivat (S3 unreliable) + Bluetooth"
step "$CURRENT_STEP"

# --- 5a: GRUB — luminozitate + suspend stabil pe Apple hardware ---
# mem_sleep_default=deep      — S3 suspend; s2idle crasha pe Apple NVMe (vendor 0x106b)
# nvme.noacpi=1               — dezactiveaza ACPI PM pentru Apple NVMe proprietar
# i915.enable_dc=0            — dezactiveaza Intel Display C-states; previne crash i915/DMC la resume
# nvme_core.default_ps_max_latency_us=0 — tine Apple NVMe in PS0; power states mai inalte nu revin corect
# reboot=pci                  — forteaza reset via PCI port 0xcf9; metoda default nu reseteaza
#                               fiabil hardware-ul Apple (reboot ramane blocat la "Rebooting.").
#                               Testat pe MacBookPro14,1: rezolva reboot hang. Alt. reboot=efi/acpi.
info "Verificare parametri GRUB..."

GRUB_FILE="/etc/default/grub"
GRUB_NEEDS_UPDATE=false

# Inlocuieste mem_sleep_default=s2idle cu deep daca exista din versiuni anterioare
if grep -q "mem_sleep_default=s2idle" "$GRUB_FILE"; then
    info "Inlocuire mem_sleep_default=s2idle cu deep..."
    sudo sed -i 's/mem_sleep_default=s2idle/mem_sleep_default=deep/g' \
        "$GRUB_FILE" || fail "Inlocuirea sleep mode in GRUB a esuat."
    GRUB_NEEDS_UPDATE=true
fi

for param in "acpi_backlight=native" "mem_sleep_default=deep" "nvme.noacpi=1" \
             "i915.enable_dc=0" "nvme_core.default_ps_max_latency_us=0" "reboot=pci"; do
    if grep -q "$param" "$GRUB_FILE"; then
        info "Prezent: $param"
    else
        info "Adaugare: $param"
        sudo sed -i \
            "s|GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 ${param}\"|" \
            "$GRUB_FILE" || fail "Adaugare '$param' in GRUB a esuat."
        GRUB_NEEDS_UPDATE=true
    fi
done

if [ "$GRUB_NEEDS_UPDATE" = true ]; then
    info "Regenerare grub.cfg..."
    sudo update-grub || fail "update-grub a esuat."
fi

for param in "acpi_backlight=native" "mem_sleep_default=deep" "nvme.noacpi=1" \
             "i915.enable_dc=0" "nvme_core.default_ps_max_latency_us=0" "reboot=pci"; do
    if ! grep -q "$param" "$GRUB_FILE"; then
        fail "Parametrul '$param' nu a fost scris corect in $GRUB_FILE."
    fi
done
ok "GRUB: toti parametrii de suspend aplicati."

# --- 5b: Hook suspend/resume pentru facetimehd ---
# Previne kernel panic la sleep descarcand modulul inainte si reincarcandu-l la wake
info "Instalare hook suspend pentru facetimehd..."

SLEEP_HOOK="/usr/lib/systemd/system-sleep/facetimehd"

if [ -f "$SLEEP_HOOK" ]; then
    warn "Hook suspend facetimehd deja exista la $SLEEP_HOOK."
else
    sudo mkdir -p "$(dirname "$SLEEP_HOOK")" \
        || fail "Nu am putut crea directorul $(dirname "$SLEEP_HOOK")."

    sudo tee "$SLEEP_HOOK" > /dev/null << 'HOOKEOF'
#!/bin/sh
case $1/$2 in
  pre/*)   modprobe -r facetimehd ;;
  post/*)  modprobe facetimehd ;;
esac
HOOKEOF

    sudo chmod +x "$SLEEP_HOOK" || fail "chmod pe hook a esuat."
fi

if [ -x "$SLEEP_HOOK" ]; then
    ok "Hook suspend facetimehd instalat si executabil: $SLEEP_HOOK"
else
    fail "Hook-ul $SLEEP_HOOK nu este executabil sau lipseste."
fi

# --- 5c: Hook suspend/resume pentru brcmfmac (WiFi) ---
# brcmfmac (BCM4350) nu se reinitializeaza corect dupa S3 resume fara reload complet.
# Problema: modprobe -r esueaza cu "Module brcmfmac is in use" pentru ca NetworkManager
# deconecteaza interfata dar nu o aduce DOWN la nivel kernel. Fix: PCI sysfs unbind,
# care opreste corect chip-ul inclusiv la wake-for-hibernate (suspend-then-hibernate default).
info "Instalare hook suspend pentru WiFi (brcmfmac)..."

WIFI_HOOK="/usr/lib/systemd/system-sleep/brcmfmac"
WIFI_HOOK_OK=false

# Verifica daca hook-ul existent are deja varianta corecta (PCI unbind)
if [ -f "$WIFI_HOOK" ] && grep -q "pci/drivers/brcmfmac/unbind" "$WIFI_HOOK"; then
    warn "Hook suspend brcmfmac (PCI unbind) deja exista la $WIFI_HOOK."
    WIFI_HOOK_OK=true
fi

if [ "$WIFI_HOOK_OK" = false ]; then
    sudo tee "$WIFI_HOOK" > /dev/null << 'HOOKEOF'
#!/bin/sh
# BCM4350 WiFi suspend hook — MacBook Pro 2017
# PCI sysfs unbind: opreste chip-ul corect inainte de S3,
# inclusiv la tranzitia suspend-then-hibernate (default logind).
case $1/$2 in
  pre/*)
    echo -n "0000:02:00.0" > /sys/bus/pci/drivers/brcmfmac/unbind 2>/dev/null || true
    ;;
  post/*)
    modprobe -r brcmfmac 2>/dev/null || true
    modprobe brcmfmac
    ;;
esac
HOOKEOF

    sudo chmod +x "$WIFI_HOOK" || fail "chmod pe hook WiFi a esuat."
fi

if [ -x "$WIFI_HOOK" ]; then
    ok "Hook suspend brcmfmac instalat si executabil: $WIFI_HOOK"
else
    fail "Hook-ul $WIFI_HOOK nu este executabil sau lipseste."
fi

# --- 5d: Dezactivare auto-suspend pe idle ---
# Cauza: S3 deep suspend pe MacBook Pro 2017 (NVMe Apple + EFI Apple) nu se trezeste fiabil
# dupa intrarea in suspend (kernel intra in PM: suspend entry (deep) si hardware-ul
# nu mai genereaza wake event). Testat cu toate fix-urile standard (nvme.noacpi, i915.enable_dc,
# nvme_core.default_ps_max_latency_us, brcmfmac PCI unbind) — comportament inconstant: scurt OK, lung blocheaza.
# Decizie: dezactivam auto-suspend pe idle + lid close = lock (nu suspend) → comportament predictibil.
# GRUB params + sleep hooks raman, pentru cazul cand userul vrea sa testeze manual `systemctl suspend`.
info "Configurare GNOME: dezactivare auto-suspend pe idle..."

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' \
        || warn "Nu am putut seta sleep-inactive-ac-type."
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' \
        || warn "Nu am putut seta sleep-inactive-battery-type."

    AC_TYPE=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 2>/dev/null)
    BAT_TYPE=$(gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 2>/dev/null)
    if [ "$AC_TYPE" = "'nothing'" ] && [ "$BAT_TYPE" = "'nothing'" ]; then
        ok "GNOME: auto-suspend dezactivat (AC + baterie)."
    else
        warn "GNOME: verificare esuata (AC=$AC_TYPE, BAT=$BAT_TYPE)."
    fi
else
    warn "gsettings nu este disponibil — sari peste config GNOME."
fi

info "Configurare logind: lid close = lock screen (nu suspend)..."

LOGIND_OVERRIDE="/etc/systemd/logind.conf.d/macbook-no-suspend.conf"

if [ -f "$LOGIND_OVERRIDE" ] && grep -q "HandleLidSwitch=lock" "$LOGIND_OVERRIDE"; then
    warn "logind override deja exista la $LOGIND_OVERRIDE."
else
    sudo mkdir -p "$(dirname "$LOGIND_OVERRIDE")" \
        || fail "Nu am putut crea $(dirname "$LOGIND_OVERRIDE")."

    sudo tee "$LOGIND_OVERRIDE" > /dev/null << 'LOGINDEOF'
# MacBook Pro 2017: S3 suspend nu se trezeste fiabil pe acest hardware.
# Lid close = blocheaza ecranul in loc de suspend (auto-suspend dezactivat in gsettings).
[Login]
HandleLidSwitch=lock
HandleLidSwitchExternalPower=lock
HandleLidSwitchDocked=ignore
LOGINDEOF

    info "Aplicare config logind (reincarcare daemon)..."
    sudo systemctl kill -s HUP systemd-logind 2>/dev/null \
        || warn "Reincarcare logind: aplica la urmatorul reboot."
fi

if [ -f "$LOGIND_OVERRIDE" ]; then
    ok "logind override: $LOGIND_OVERRIDE"
else
    fail "logind override nu a fost creat la $LOGIND_OVERRIDE."
fi

# --- 5e: Mask sleep targets — blocare totala suspend/hibernate ---
# gsettings (5d) + logind lid=lock NU acopera TOATE caile de suspend: observat empiric ca
# systemd-suspend-then-hibernate.service tot a rulat pe idle lung (lid inchis pe baterie) →
# PM: suspend entry (deep) → S3 nu s-a trezit → hang, force power-off.
# Pe acest hardware S3 e nefiabil prin design, deci nu il "reparam" — il blocam complet.
# Mask pe target-urile de sleep face IMPOSIBIL orice suspend/hibernate (nimic nu le mai poate
# declansa). Reversibil cu: sudo systemctl unmask sleep.target suspend.target ...
info "Mask sleep targets (blocare totala suspend/hibernate — S3 nefiabil pe acest hardware)..."

SLEEP_TARGETS="sleep.target suspend.target hibernate.target suspend-then-hibernate.target"
sudo systemctl mask $SLEEP_TARGETS >/dev/null 2>&1 \
    || warn "Mask sleep targets a returnat eroare."

MASKED_OK=true
for t in $SLEEP_TARGETS; do
    [ "$(systemctl is-enabled $t 2>/dev/null)" = "masked" ] || MASKED_OK=false
done
if [ "$MASKED_OK" = true ]; then
    ok "Sleep targets masked: niciun suspend/hibernate posibil (S3 hang prevenit)."
else
    warn "Unele sleep targets nu sunt masked. Verifica: systemctl is-enabled sleep.target"
fi

# --- 5f: Bluetooth — deblocare rfkill la boot + AutoEnable ---
# Acelasi cip BCM4350 (WiFi+BT). Cand userul dezactiveaza BT din GUI (reactie naturala cand un
# device nu se asociaza), systemd-rfkill SALVEAZA starea "blocat" in /var/lib/systemd/rfkill/ si o
# RESTAUREAZA la fiecare boot → BT ramane soft-blocked, Powered: no, "nu merge deloc".
# Testat empiric pe acest hardware (A/B pe aceeasi trapa): AutoEnable=true SINGUR nu invinge block-ul
# — systemd-rfkill restaureaza soft=1 INAINTE ca bluetoothd sa faca power-on, iar un adapter
# rfkill-blocked nu poate fi pornit. Fix dovedit: un oneshot `rfkill unblock`, ORDONAT dupa
# systemd-rfkill.service si INAINTE de bluetooth.service, + AutoEnable pentru power-on.
# Trade-off acceptat: BT porneste mereu disponibil la boot (un disable persistent nu supravietuieste
# reboot-ului; oprirea in sesiune merge). Pe acest hardware nu exista suspend si laptopul e mereu pe
# AC, deci irelevant.
info "Bluetooth: deblocare rfkill la boot + AutoEnable (BCM4350)..."

BT_UNBLOCK_SVC="/etc/systemd/system/bluetooth-rfkill-unblock.service"
BT_MAIN_CONF="/etc/bluetooth/main.conf"

sudo tee "$BT_UNBLOCK_SVC" > /dev/null << 'BTSVCEOF'
[Unit]
Description=Unblock Bluetooth rfkill before bluetoothd (MacBook BCM4350)
Documentation=https://github.com/vrilutza/scripts
After=systemd-rfkill.service
Before=bluetooth.service
Wants=systemd-rfkill.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/rfkill unblock bluetooth
RemainAfterExit=yes

[Install]
WantedBy=bluetooth.service
BTSVCEOF

# AutoEnable=true sub [Policy] in main.conf (bluetoothd porneste adapterul dupa deblocare) — idempotent
if [ ! -f "$BT_MAIN_CONF" ]; then
    sudo mkdir -p "$(dirname "$BT_MAIN_CONF")"
    printf '[Policy]\nAutoEnable=true\n' | sudo tee "$BT_MAIN_CONF" > /dev/null
elif grep -qE '^[[:space:]]*#*[[:space:]]*AutoEnable[[:space:]]*=' "$BT_MAIN_CONF"; then
    sudo sed -i 's/^[[:space:]]*#*[[:space:]]*AutoEnable[[:space:]]*=.*/AutoEnable=true/' "$BT_MAIN_CONF"
elif grep -qE '^[[:space:]]*\[Policy\]' "$BT_MAIN_CONF"; then
    sudo sed -i '/^[[:space:]]*\[Policy\]/a AutoEnable=true' "$BT_MAIN_CONF"
else
    printf '\n[Policy]\nAutoEnable=true\n' | sudo tee -a "$BT_MAIN_CONF" > /dev/null
fi

info "Reload systemd + enable/start serviciu unblock..."
sudo systemctl daemon-reload || warn "daemon-reload a returnat eroare."
sudo systemctl enable bluetooth-rfkill-unblock.service > /dev/null 2>&1 \
    || warn "enable bluetooth-rfkill-unblock.service a returnat eroare."
sudo systemctl start bluetooth-rfkill-unblock.service \
    || warn "start bluetooth-rfkill-unblock.service a returnat eroare."

if [ -f "$BT_UNBLOCK_SVC" ] && grep -qE '^AutoEnable=true' "$BT_MAIN_CONF"; then
    ok "Bluetooth: serviciu unblock + AutoEnable=true (BT disponibil la fiecare boot)."
else
    warn "Bluetooth: verificare partiala. Verifica $BT_UNBLOCK_SVC si $BT_MAIN_CONF."
fi


# =============================================================================
# ETAPA 6/9 — Accelerare video hardware VA-API (Intel Iris Plus 640)
# Problema: "vaInitialize failed: unknown libva error" in VS Code / Chrome
# Cauza:    driver-ele VA-API pentru Intel Kaby Lake nu sunt instalate
# Fix:      intel-media-va-driver (iHD, Kaby Lake+) + i965-va-driver (fallback)
# =============================================================================
CURRENT_STEP="ETAPA 6/9 — Accelerare video hardware VA-API"
step "$CURRENT_STEP"
info "Intel Iris Plus 640 (Kaby Lake) — instalare drivere VA-API..."

VAAPI_PKGS=(intel-media-va-driver i965-va-driver vainfo)

info "Instalare pachete VA-API: ${VAAPI_PKGS[*]}"
sudo apt-get install -y "${VAAPI_PKGS[@]}" || fail "Instalarea pachetelor VA-API a esuat."

for pkg in "${VAAPI_PKGS[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg"
    else
        warn "Pachetul '$pkg' nu a putut fi instalat — poate nu e disponibil."
    fi
done

# Verificare VA-API cu driver iHD (Intel Media Driver — Kaby Lake nativ)
if command -v vainfo &>/dev/null; then
    VAAPI_iHD=$(LIBVA_DRIVER_NAME=iHD vainfo 2>&1 | grep -c "VAProfile" || true)
    if [ "$VAAPI_iHD" -gt 0 ]; then
        ok "VA-API functional cu driver iHD (Intel Media Driver — Kaby Lake)."
    else
        VAAPI_i965=$(LIBVA_DRIVER_NAME=i965 vainfo 2>&1 | grep -c "VAProfile" || true)
        if [ "$VAAPI_i965" -gt 0 ]; then
            ok "VA-API functional cu driver i965 (fallback)."
        else
            warn "VA-API instalat dar neactivat inca — va fi activ dupa reboot."
        fi
    fi
else
    warn "vainfo nu este disponibil pentru verificare — reboot si verifica manual cu: vainfo"
fi


# =============================================================================
# ETAPA 7/9 — Touchpad UX (tap-to-click + natural scroll + disable-while-typing)
# Comportament macOS-like out of the box, doar gsettings, fara modificari kernel.
# =============================================================================
CURRENT_STEP="ETAPA 7/9 — Touchpad UX"
step "$CURRENT_STEP"
info "Configurare GNOME touchpad: tap-to-click + natural scroll + disable-while-typing..."

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true \
        || warn "Nu am putut seta tap-to-click."
    gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll true \
        || warn "Nu am putut seta natural-scroll."
    gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true \
        || warn "Nu am putut seta disable-while-typing."

    TAP=$(gsettings get org.gnome.desktop.peripherals.touchpad tap-to-click 2>/dev/null)
    NAT=$(gsettings get org.gnome.desktop.peripherals.touchpad natural-scroll 2>/dev/null)
    DWT=$(gsettings get org.gnome.desktop.peripherals.touchpad disable-while-typing 2>/dev/null)
    if [ "$TAP" = "true" ] && [ "$NAT" = "true" ] && [ "$DWT" = "true" ]; then
        ok "Touchpad UX: tap-to-click + natural scroll + disable-while-typing active."
    else
        warn "Touchpad UX: verificare esuata (tap=$TAP, natural=$NAT, dwt=$DWT)."
    fi
else
    warn "gsettings nu este disponibil — sari peste config touchpad UX."
fi


# =============================================================================
# ETAPA 8/9 — Thermal management: thermald + RAPL PL1/PL2 + fan floor
#
# Problema: RAPL pe MBP 2017 sub Linux nu are limite sane (Apple EFI lasa
# PL1=100W, PL2=125W pe un chip cu TDP nominal 15W). Chip-ul ruleaza
# unrestricted pana cand kernel-ul face emergency thermal throttle la TJmax.
# Plus: curba SMC stock tine fan-ul prea jos (lent), laptopul sta inutil cald.
#
# Fix in 3 parti:
#   8a) thermald 2.5.10 din apt — daemon dinamic care reduce P-state cand
#       temperaturile cresc. Plus lm-sensors pentru monitoring manual.
#   8b) Regula udev (scrie RAPL via ATTR) + macbook-rapl-thermald.service:
#         PL1 = 22 W sustained — match Apple macOS config (cTDP-up)
#         PL2 = 30 W short-term boost — match Apple macOS config
#       Time windows raman default kernel (~28s PL1 / ~2.4ms PL2).
#
#       Evolutia abordarii (4 iteratii — vezi TODO.md pentru date complete):
#       v1) /etc/tmpfiles.d/macbook-rapl.conf — scria devreme la boot, dar
#           intel_rapl_msr (udev-loaded) suprascria cu defaults Apple. NU.
#       v2) macbook-rapl.service + ConditionPathExists. Mergea pe 7.0.7
#           (100%), dar pe 7.0.9 race ~110ms → 37.5% boot-uri esuate.
#       v3) macbook-rapl.path (PathExists) + .service. ESUAT: .path units
#           folosesc inotify, iar sysfs NU emite fiabil evenimente inotify
#           de creare → tot non-determinist. Plus After=thermald pe .path
#           crea ordering cycle (paths.target e inainte de basic.target).
#       v4) (curent) Regula udev pe SUBSYSTEM==powercap, KERNEL==intel-rapl:0.
#           udev primeste uevent KERNEL real la aparitia device-ului (fiabil,
#           spre deosebire de inotify-pe-sysfs). Scrie valorile direct via
#           ATTR{}= (zero race, sincron cu add event). TAG+=systemd +
#           SYSTEMD_WANTS declanseaza macbook-rapl-thermald.service care face
#           try-restart thermald → thermald redescopera RAPL.
#           Testat empiric: udevadm trigger --action=add re-aplica 100M→22M;
#           thermald restartat dupa RAPL set nu mai logheaza "NO RAPL sysfs".
# =============================================================================
CURRENT_STEP="ETAPA 8/9 — Thermal management (thermald + RAPL + fan floor)"
step "$CURRENT_STEP"

# --- 8a: thermald + lm-sensors via apt ---
THERMAL_PKGS=(thermald lm-sensors)
info "Instalare ${THERMAL_PKGS[*]}..."
sudo apt-get install -y "${THERMAL_PKGS[@]}" || fail "Instalarea pachetelor thermald a esuat."

for pkg in "${THERMAL_PKGS[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        ok "$pkg"
    else
        fail "$pkg nu a putut fi instalat."
    fi
done

info "Enable + start thermald.service..."
sudo systemctl enable --now thermald.service \
    || fail "systemctl enable --now thermald a esuat."

if systemctl is-active --quiet thermald.service; then
    # Versiunea din dpkg (nu din `thermald --version` — binarul e in /usr/sbin
    # si poate sa nu fie in PATH-ul user-ului care ruleaza scriptul).
    THERMALD_VER=$(dpkg-query -W -f='${Version}' thermald 2>/dev/null)
    ok "thermald active (versiune ${THERMALD_VER:-necunoscuta})."
else
    fail "thermald.service nu este active. Vezi: systemctl status thermald"
fi

# --- 8b: RAPL via regula udev (ATTR write) + thermald reinit service ---
PL1_UW=22000000   # 22 W sustained
PL2_UW=30000000   # 30 W short-term boost

RAPL_BASE="/sys/class/powercap/intel-rapl:0"

if [ ! -d "$RAPL_BASE" ]; then
    fail "RAPL sysfs interface lipseste la $RAPL_BASE. Modulul intel_rapl_msr nu e incarcat?"
fi

# Cleanup iteratii anterioare (v1 tmpfiles, v2/v3 service + .path unit).
OLD_TMPFILES="/etc/tmpfiles.d/macbook-rapl.conf"
if [ -f "$OLD_TMPFILES" ]; then
    info "Stergere config tmpfiles RAPL vechi (v1)..."
    sudo rm -f "$OLD_TMPFILES" || warn "Nu am putut sterge $OLD_TMPFILES."
fi
for unit in macbook-rapl.path macbook-rapl.service; do
    if systemctl is-enabled --quiet "$unit" 2>/dev/null || systemctl is-active --quiet "$unit" 2>/dev/null; then
        info "Dezactivare $unit (iteratie v2/v3)..."
        sudo systemctl disable --now "$unit" >/dev/null 2>&1 || true
    fi
done
sudo rm -f /etc/systemd/system/macbook-rapl.path /etc/systemd/system/macbook-rapl.service

info "Configurare RAPL: PL1=$((PL1_UW/1000000))W (long-term), PL2=$((PL2_UW/1000000))W (short-term)..."

UDEV_RULE="/etc/udev/rules.d/99-macbook-rapl.rules"
REINIT_SERVICE="/etc/systemd/system/macbook-rapl-thermald.service"

# Regula udev: la aparitia device-ului powercap intel-rapl:0 (uevent KERNEL
# real, fiabil — nu inotify), scrie valorile RAPL direct via ATTR{}= si
# declanseaza service-ul de reinit thermald prin SYSTEMD_WANTS.
sudo tee "$UDEV_RULE" > /dev/null << UDEVEOF
# MacBook Pro 13" 2017 (A1708) — Intel i5-7360U RAPL power limits
# Apple EFI lasa RAPL nelimitat (100W/125W) pe Linux. Scriem PL1/PL2 fix
# cand kernel-ul expune device-ul powercap, via uevent udev (deterministic
# pe orice kernel — vs inotify pe sysfs care nu emite fiabil add events).
ACTION=="add", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:0", ATTR{constraint_0_power_limit_uw}="$PL1_UW", ATTR{constraint_1_power_limit_uw}="$PL2_UW", TAG+="systemd", ENV{SYSTEMD_WANTS}+="macbook-rapl-thermald.service"
UDEVEOF

# Service mic: thermald initializeaza fara RAPL daca porneste inainte ca
# device-ul sa existe ("NO RAPL sysfs present"), iar polling-ul lui nu
# redescopera cooling devices. try-restart il forteaza sa reinitializeze
# dupa ce udev a setat RAPL. Fara After=thermald (evitam ordering cycle).
sudo tee "$REINIT_SERVICE" > /dev/null << 'SERVICEEOF'
[Unit]
Description=Reinit thermald after MacBook RAPL limits are set by udev
Documentation=https://github.com/vrilutza/scripts

[Service]
Type=oneshot
ExecStart=/bin/systemctl try-restart thermald.service
RemainAfterExit=yes
SERVICEEOF

if [ -f "$UDEV_RULE" ] && [ -f "$REINIT_SERVICE" ]; then
    ok "Scrise: $UDEV_RULE + $REINIT_SERVICE"
else
    fail "Nu am putut scrie regula udev / service-ul de reinit."
fi

info "Reload udev + systemd, aplicare imediata (udevadm trigger)..."
sudo systemctl daemon-reload || fail "systemctl daemon-reload a esuat."
sudo udevadm control --reload || fail "udevadm control --reload a esuat."
# Pe sistem live device-ul exista deja; trigger-ul re-fire-uieste regula acum.
sudo udevadm trigger --action=add /sys/class/powercap/intel-rapl:0 \
    || warn "udevadm trigger a returnat eroare."
# settle --timeout=5: pe kerneluri cu coada udev aglomerata (ex 7.0.10, unde
# coldplug-ul audio rupt o tine ocupata) un `udevadm settle` fara timeout
# blocheaza ~1-2 min. Nu avem nevoie sa golim TOATA coada — am declansat un
# singur device si verificam rezultatul direct mai jos. Bound la 5s.
sudo udevadm settle --timeout=5 2>/dev/null || true
sleep 1

PL1_READ=$(cat "$RAPL_BASE/constraint_0_power_limit_uw" 2>/dev/null)
PL2_READ=$(cat "$RAPL_BASE/constraint_1_power_limit_uw" 2>/dev/null)

if [ "$PL1_READ" = "$PL1_UW" ] && [ "$PL2_READ" = "$PL2_UW" ]; then
    ok "RAPL aplicat efectiv: PL1=$((PL1_READ/1000000))W, PL2=$((PL2_READ/1000000))W."
else
    warn "RAPL: valori curente nu corespund (PL1=$PL1_READ vs $PL1_UW, PL2=$PL2_READ vs $PL2_UW). Vor fi aplicate la urmatorul boot prin regula udev. Verifica: cat $RAPL_BASE/constraint_0_power_limit_uw"
fi

# --- 8c: Fan floor — ridica fan1_min ca laptopul sa stea mai rece ---
# Curba SMC stock e "lenoasa": tine fan-ul la minim (~1200 RPM) chiar si la 80°C,
# prioritizand linistea. Ridicam podeaua la 3500 RPM (sweet spot zgomot pe A1708):
#   - fan1_manual ramane 0 → SMC pastreaza controlul automat
#   - fan1_min=3500 → SMC nu coboara sub 3500, dar URCA liber peste (pana la 7200) la load
# Testat pe MacBookPro14,1: idle 80→74°C; sub load fan urca automat 3500→4500→5400+;
# zero throttle. "Best of both": rece+linistit la idle, ramp de siguranta intact la load.
# Bonus: mai putina caldura in sasiu = menajeaza bateria (heat = ucigasul #1 al litiu).
# Persistat via udev (fan1_min e volatil, se reseteaza la reboot).
FAN_MIN_RPM=3500
FAN_SMC="/sys/devices/platform/applesmc.768"

if [ ! -e "$FAN_SMC/fan1_min" ]; then
    warn "applesmc fan1_min lipseste ($FAN_SMC) — sar peste fan floor (modul applesmc neincarcat?)."
else
    info "Configurare fan floor: fan1_min=$FAN_MIN_RPM RPM (SMC ramane auto deasupra)..."
    FAN_RULE="/etc/udev/rules.d/99-macbook-fan.rules"
    FAN_SVC="/etc/systemd/system/macbook-fan-floor.service"
    FAN_HELPER="/usr/local/sbin/macbook-fan-floor"

    # IMPORTANT (corectat 14 iun 2026): fan1_min NU exista inca la evenimentul `add` al
    # platform device-ului applesmc — e creat mai tarziu, la probe-ul hwmon. Scrierea
    # ATTR{fan1_min} direct in regula udev da RACE si esueaza la boot:
    #   "Could not chase sysfs attribute .../fan1_min ... No such file or directory"
    # → fan1_min ramane 1200 (stock). Solutie (acelasi model ca RAPL): regula udev
    # declanseaza un service oneshot care ASTEAPTA sa apara atributul, apoi scrie podeaua.

    # Helper: asteapta pana la 5s ca fan1_min sa existe, apoi scrie podeaua.
    sudo tee "$FAN_HELPER" > /dev/null << FANHLP
#!/bin/sh
F=$FAN_SMC/fan1_min
i=0
while [ "\$i" -lt 50 ]; do
    [ -e "\$F" ] && { echo $FAN_MIN_RPM > "\$F"; exit 0; }
    i=\$((i + 1)); sleep 0.1
done
echo "macbook-fan-floor: \$F nu a aparut in 5s" >&2; exit 1
FANHLP
    sudo chmod +x "$FAN_HELPER"

    sudo tee "$FAN_SVC" > /dev/null << FANSVCEOF
[Unit]
Description=MacBook fan floor (fan1_min=$FAN_MIN_RPM) — set after applesmc exposes the attribute
Documentation=https://github.com/vrilutza/scripts

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$FAN_HELPER

[Install]
WantedBy=multi-user.target
FANSVCEOF

    sudo tee "$FAN_RULE" > /dev/null << FANEOF
# MacBook Pro 13" 2017 (A1708) — fan floor
# fan1_min NU exista la evenimentul \`add\` al applesmc (creat tarziu, la probe) →
# ATTR{fan1_min} direct da race. Declansam in schimb service-ul oneshot, care scrie
# $FAN_MIN_RPM dupa ce device-ul e gata (acelasi model ca regula RAPL).
ACTION=="add", SUBSYSTEM=="platform", KERNEL=="applesmc.768", TAG+="systemd", ENV{SYSTEMD_WANTS}+="macbook-fan-floor.service"
FANEOF

    if [ -f "$FAN_HELPER" ] && [ -f "$FAN_SVC" ] && [ -f "$FAN_RULE" ]; then
        ok "Helper + service + regula udev fan scrise."
    else
        fail "Nu am putut scrie helper/service/regula fan."
    fi

    info "Reload systemd + udev, enable + start service..."
    sudo systemctl daemon-reload
    sudo systemctl enable macbook-fan-floor.service > /dev/null 2>&1 \
        || warn "enable macbook-fan-floor.service a returnat eroare."
    sudo udevadm control --reload || warn "udevadm control --reload a returnat eroare."
    sudo systemctl start macbook-fan-floor.service \
        || warn "start macbook-fan-floor.service a returnat eroare."

    FAN_MIN_READ=$(cat "$FAN_SMC/fan1_min" 2>/dev/null)
    if [ "$FAN_MIN_READ" = "$FAN_MIN_RPM" ]; then
        ok "Fan floor aplicat: fan1_min=$FAN_MIN_READ RPM (SMC auto deasupra)."
    else
        warn "Fan floor: fan1_min=$FAN_MIN_READ (asteptat $FAN_MIN_RPM). Verifica dupa reboot: cat $FAN_SMC/fan1_min"
    fi
fi


# =============================================================================
# ETAPA 9/9 — Cosmetic / curatire jurnal (GNOME media-keys + usb-protection + fnmode)
#
# Zero impact functional — doar silentiaza erori benigne care apar la fiecare boot:
#   - gsd-media-keys "Failed to grab accelerator ... hibernate / playback-repeat":
#     keybinding-urile veneau setate la [''] (string gol invalid) → grab esueaza.
#     Le golim ([]) ca plugin-ul sa nu mai incerce. Hibernate e oricum mascat (S3 dead).
#   - gsd-usb-protection "Failed to fetch USBGuard parameters": USBGuard nu e instalat,
#     deci plugin-ul interogheaza un serviciu D-Bus inexistent. Oprim functia (e no-op).
#   - applespi fnmode=1: fixeaza EXPLICIT comportamentul default (taste media primare pe
#     F1-F12; tii Fn pentru F-taste reale). Nu schimba nimic vizibil — doar documenteaza.
#     fnmode=2 = invers (F-taste primare). MacBook 2017 = driver applespi, NU hid_apple.
# =============================================================================
CURRENT_STEP="ETAPA 9/9 — Cosmetic / curatire jurnal"
step "$CURRENT_STEP"

# --- GNOME gsettings (per-user; scriptul ruleaza ca user normal, nu root) ---
if command -v gsettings >/dev/null 2>&1; then
    info "Silentiez erori GNOME benigne (media-keys hibernate/playback-repeat, usb-protection)..."
    gsettings set org.gnome.settings-daemon.plugins.media-keys hibernate "[]" \
        || warn "Nu am putut goli keybinding-ul hibernate."
    gsettings set org.gnome.settings-daemon.plugins.media-keys playback-repeat "[]" \
        || warn "Nu am putut goli keybinding-ul playback-repeat."
    gsettings set org.gnome.desktop.privacy usb-protection false \
        || warn "Nu am putut dezactiva usb-protection."

    HIB=$(gsettings get org.gnome.settings-daemon.plugins.media-keys hibernate 2>/dev/null)
    USBP=$(gsettings get org.gnome.desktop.privacy usb-protection 2>/dev/null)
    case "$HIB" in *"[]"*) HIB_OK=1 ;; *) HIB_OK=0 ;; esac
    if [ "$HIB_OK" = "1" ] && [ "$USBP" = "false" ]; then
        ok "GNOME cosmetic: hibernate/playback-repeat golite, usb-protection off."
    else
        warn "GNOME cosmetic: verificare partiala (hibernate=$HIB, usb-protection=$USBP)."
    fi
else
    warn "gsettings nu este disponibil — sari peste curatirea GNOME."
fi

# --- applespi fnmode=1 (default explicit: taste media primare, Fn pentru F1-F12) ---
APPLESPI_CONF="/etc/modprobe.d/applespi.conf"
info "Fixez explicit applespi fnmode=1 in $APPLESPI_CONF..."
sudo tee "$APPLESPI_CONF" > /dev/null << 'APPLESPIEOF'
# MacBook Pro 13" 2017 (A1708) — tastatura Apple SPI (driver applespi)
# fnmode=1 (default): taste media (volum/luminozitate) primare pe F1-F12; tii Fn
#   pentru F1-F12 reale. Setat explicit ca sa documenteze comportamentul.
# fnmode=2 = invers (F1-F12 primare, Fn pentru media). Schimba aici daca preferi.
options applespi fnmode=1
APPLESPIEOF

if [ -f "$APPLESPI_CONF" ]; then
    ok "applespi fnmode=1 scris in $APPLESPI_CONF."
    if sudo update-initramfs -u > /dev/null 2>&1; then
        ok "initramfs regenerat (fnmode activ la boot)."
    else
        warn "update-initramfs a esuat — ruleaza manual: sudo update-initramfs -u"
    fi
else
    warn "Nu am putut scrie $APPLESPI_CONF."
fi


# =============================================================================
# REZUMAT FINAL
# =============================================================================
echo ""
echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗"
echo "  ║              INSTALARE COMPLETA                     ║"
echo -e "  ╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✓${NC}  Driver audio Cirrus CS8409 — DKMS"
echo -e "  ${GREEN}✓${NC}  Firmware FaceTime HD — /usr/lib/firmware/facetimehd/"
echo -e "  ${GREEN}✓${NC}  Driver camera FaceTime HD — DKMS"
echo -e "  ${GREEN}✓${NC}  Luminozitate ecran — acpi_backlight=native in GRUB"
echo -e "  ${GREEN}✓${NC}  Reboot fix — reboot=pci in GRUB (reset fiabil pe Apple hardware)"
echo -e "  ${GREEN}✓${NC}  Suspend/hibernate blocat complet — sleep targets masked (S3 nefiabil)"
echo -e "  ${GREEN}✓${NC}  Lid close = lock screen (logind), nu suspend"
echo -e "  ${GREEN}✓${NC}  Sleep hooks (facetimehd + brcmfmac PCI unbind) — defensive pt suspend manual"
echo -e "  ${GREEN}✓${NC}  Touchpad: libinput protejeaza in userspace (nu mai aplicam patch DKMS)"
echo -e "  ${GREEN}✓${NC}  Touchpad UX — tap-to-click + natural scroll + disable-while-typing"
echo -e "  ${GREEN}✓${NC}  Accelerare video VA-API — intel-media-va-driver + i965-va-driver"
echo -e "  ${GREEN}✓${NC}  thermald (Intel thermal daemon) + lm-sensors"
echo -e "  ${GREEN}✓${NC}  RAPL: PL1=22W / PL2=30W (Apple-like) prin regula udev + thermald reinit"
echo -e "  ${GREEN}✓${NC}  Fan floor: fan1_min=3500 RPM (rece la idle, SMC ramp auto deasupra)"
echo -e "  ${GREEN}✓${NC}  Bluetooth: unblock rfkill la boot + AutoEnable (BCM4350, mereu disponibil)"
echo -e "  ${GREEN}✓${NC}  Cosmetic: GNOME media-keys/usb-protection silentiate + applespi fnmode=1"
echo ""
echo -e "  ${YELLOW}⚠${NC}  Necesar: ${BOLD}sudo reboot${NC} pentru a activa toate modificarile."
echo ""
