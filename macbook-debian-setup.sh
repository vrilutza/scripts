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
#    5. Fix sistem: luminozitate, suspend S3 stabil (nvme.noacpi, i915.enable_dc=0), WiFi dupa sleep
#    6. Fix touchpad Apple SPI — elimina "Touch jump detected and discarded"
#    7. Accelerare video hardware VA-API (Intel Iris Plus 640 / Kaby Lake)
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
# ETAPA 1/7 — Dependente
# =============================================================================
CURRENT_STEP="ETAPA 1/7 — Dependente"
step "$CURRENT_STEP"

PKGS=(build-essential linux-headers-amd64 linux-source dkms git patch wget curl cpio xz-utils libssl-dev)

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
# ETAPA 2/7 — Driver audio Cirrus Logic CS8409
# https://github.com/davidjo/snd_hda_macbookpro
# =============================================================================
CURRENT_STEP="ETAPA 2/7 — Driver audio"
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
# ETAPA 3/7 — Firmware camera FaceTime HD
# https://github.com/patjak/facetimehd-firmware
# =============================================================================
CURRENT_STEP="ETAPA 3/7 — Firmware camera FaceTime HD"
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
# ETAPA 4/7 — Driver kernel camera FaceTime HD cu DKMS
# https://github.com/patjak/facetimehd
# =============================================================================
CURRENT_STEP="ETAPA 4/7 — Driver camera FaceTime HD (DKMS)"
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
# ETAPA 5/7 — Fix sistem: luminozitate ecran + suspend stabil + WiFi dupa sleep
# =============================================================================
CURRENT_STEP="ETAPA 5/7 — Fix luminozitate, suspend si WiFi dupa sleep"
step "$CURRENT_STEP"

# --- 5a: GRUB — luminozitate + suspend stabil pe Apple hardware ---
# mem_sleep_default=deep      — S3 suspend; s2idle crasha pe Apple NVMe (vendor 0x106b)
# nvme.noacpi=1               — dezactiveaza ACPI PM pentru Apple NVMe proprietar
# i915.enable_dc=0            — dezactiveaza Intel Display C-states; previne crash i915/DMC la resume
# nvme_core.default_ps_max_latency_us=0 — tine Apple NVMe in PS0; power states mai inalte nu revin corect
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
             "i915.enable_dc=0" "nvme_core.default_ps_max_latency_us=0"; do
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
             "i915.enable_dc=0" "nvme_core.default_ps_max_latency_us=0"; do
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
# brcmfmac (BCM4350) nu se reinitializeaza corect dupa S3 resume fara reload complet
info "Instalare hook suspend pentru WiFi (brcmfmac)..."

WIFI_HOOK="/usr/lib/systemd/system-sleep/brcmfmac"

if [ -f "$WIFI_HOOK" ]; then
    warn "Hook suspend brcmfmac deja exista la $WIFI_HOOK."
else
    sudo tee "$WIFI_HOOK" > /dev/null << 'HOOKEOF'
#!/bin/sh
case $1/$2 in
  pre/*)   modprobe -r brcmfmac ;;
  post/*)  modprobe brcmfmac ;;
esac
HOOKEOF

    sudo chmod +x "$WIFI_HOOK" || fail "chmod pe hook WiFi a esuat."
fi

if [ -x "$WIFI_HOOK" ]; then
    ok "Hook suspend brcmfmac instalat si executabil: $WIFI_HOOK"
else
    fail "Hook-ul $WIFI_HOOK nu este executabil sau lipseste."
fi


# =============================================================================
# ETAPA 6/7 — Fix touchpad Apple SPI (patch kernel via DKMS)
# Problema: "Apple SPI Touchpad: kernel bug: Touch jump detected and discarded"
# Cauza:    driver-ul applespi primeste coordonate corupte de pe SPI bus
# Fix:      velocity filter in report_tp_state() — patch out-of-tree via DKMS
# Sursa:    applespi-fix/ din acest repo
# =============================================================================
CURRENT_STEP="ETAPA 6/7 — Fix touchpad Apple SPI (DKMS)"
step "$CURRENT_STEP"
info "Problema: cursor sare — Touch jump in jurnalul kernel"
info "Fix: velocity filter in driver applespi — DKMS patch"

APPLESPI_SRC="${SCRIPT_DIR}/applespi-fix"
APPLESPI_VER="7.0.7"
APPLESPI_DKMS_SRC="/usr/src/applespi-fix-${APPLESPI_VER}"

if [ ! -d "$APPLESPI_SRC" ]; then
    fail "Directorul applespi-fix lipseste: $APPLESPI_SRC — cloneaza repo-ul complet."
fi

if sudo dkms status 2>/dev/null | grep -q "applespi-fix/${APPLESPI_VER}"; then
    warn "Modulul applespi-fix/${APPLESPI_VER} este deja inregistrat in DKMS. Sar aceasta etapa."
else
    info "Copiere surse in $APPLESPI_DKMS_SRC..."
    sudo rm -rf "$APPLESPI_DKMS_SRC"
    sudo cp -r "$APPLESPI_SRC" "$APPLESPI_DKMS_SRC" \
        || fail "Copierea surselor applespi-fix a esuat."

    info "dkms add applespi-fix/${APPLESPI_VER}..."
    sudo dkms add -m applespi-fix -v "$APPLESPI_VER" \
        || warn "dkms add: modulul poate fi deja adaugat, continui."

    info "dkms build applespi-fix/${APPLESPI_VER} (poate dura ~1 minut)..."
    sudo dkms build -m applespi-fix -v "$APPLESPI_VER" \
        || fail "dkms build applespi-fix a esuat. Verifica: sudo dkms status"

    info "dkms install applespi-fix/${APPLESPI_VER}..."
    sudo dkms install -m applespi-fix -v "$APPLESPI_VER" \
        || fail "dkms install applespi-fix a esuat."
fi

if sudo dkms status 2>/dev/null | grep -q "applespi-fix/${APPLESPI_VER}"; then
    ok "Modulul applespi-fix/${APPLESPI_VER} inregistrat in DKMS."
else
    fail "applespi-fix nu apare in dkms status. Verifica cu: sudo dkms status"
fi

# Inlocuire modul incarcat fara reboot
info "Incarcare modul applespi cu patch aplicat..."
if lsmod | grep -q "^applespi"; then
    sudo modprobe -r applespi 2>/dev/null || true
fi
sudo modprobe applespi || warn "modprobe applespi a esuat — va fi incarcat la reboot."

if lsmod | grep -q "^applespi"; then
    ok "Modulul applespi (patched) este incarcat."
    info "Verifica: journalctl -f 2>/dev/null | grep -i 'touch jump'"
else
    warn "Modulul va fi activ dupa reboot."
fi


# =============================================================================
# ETAPA 7/7 — Accelerare video hardware VA-API (Intel Iris Plus 640)
# Problema: "vaInitialize failed: unknown libva error" in VS Code / Chrome
# Cauza:    driver-ele VA-API pentru Intel Kaby Lake nu sunt instalate
# Fix:      intel-media-va-driver (iHD, Kaby Lake+) + i965-va-driver (fallback)
# =============================================================================
CURRENT_STEP="ETAPA 7/7 — Accelerare video hardware VA-API"
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
echo -e "  ${GREEN}✓${NC}  Suspend stabil — S3 deep + nvme.noacpi=1 + i915.enable_dc=0"
echo -e "  ${GREEN}✓${NC}  WiFi dupa sleep — hook brcmfmac reload la resume"
echo -e "  ${GREEN}✓${NC}  Fix touchpad Apple SPI — applespi velocity filter (DKMS)"
echo -e "  ${GREEN}✓${NC}  Accelerare video VA-API — intel-media-va-driver + i965-va-driver"
echo ""
echo -e "  ${YELLOW}⚠${NC}  Necesar: ${BOLD}sudo reboot${NC} pentru a activa toate modificarile."
echo ""
