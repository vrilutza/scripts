#!/bin/bash
# =============================================================================
#  MacBook Pro 13" 2017 (A1708) — Debian Testing — Setup Script
# =============================================================================
#
#  Ce instaleaza:
#    1. Dependente (build-essential, dkms, linux-headers, linux-source, etc.)
#    2. Driver audio Cirrus Logic CS8409
#       https://github.com/davidjo/snd_hda_macbookpro
#    3. Firmware camera FaceTime HD (extras din driverul Apple OS X)
#       https://github.com/patjak/facetimehd-firmware
#    4. Driver kernel camera FaceTime HD cu DKMS
#       https://github.com/patjak/facetimehd
#    5. Fix sistem: luminozitate ecran + suspend stabil (sleep hook facetimehd)
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
mkdir -p "$WORKDIR"


# =============================================================================
# ETAPA 1/5 — Dependente
# =============================================================================
CURRENT_STEP="ETAPA 1/5 — Dependente"
step "$CURRENT_STEP"

PKGS=(build-essential linux-headers-amd64 linux-source dkms git patch wget)

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
# ETAPA 2/5 — Driver audio Cirrus Logic CS8409
# https://github.com/davidjo/snd_hda_macbookpro
# =============================================================================
CURRENT_STEP="ETAPA 2/5 — Driver audio"
step "$CURRENT_STEP"
info "Proiect: https://github.com/davidjo/snd_hda_macbookpro"

if sudo dkms status 2>/dev/null | grep -q "snd_hda_macbookpro"; then
    warn "Driver-ul audio este deja inregistrat in DKMS. Sar clonarea."
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

    cd snd_hda_macbookpro
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
# ETAPA 3/5 — Firmware camera FaceTime HD
# https://github.com/patjak/facetimehd-firmware
# =============================================================================
CURRENT_STEP="ETAPA 3/5 — Firmware camera FaceTime HD"
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

    cd facetimehd-firmware
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
# ETAPA 4/5 — Driver kernel camera FaceTime HD cu DKMS
# https://github.com/patjak/facetimehd
# =============================================================================
CURRENT_STEP="ETAPA 4/5 — Driver camera FaceTime HD (DKMS)"
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

    cd facetimehd
    info "Compilare modul kernel..."
    make || fail "Compilarea facetimehd a esuat."

    DKMS_SRC="/usr/src/facetimehd-${FTIMEHD_VER}"
    if [ ! -d "$DKMS_SRC" ]; then
        info "Copiere sursa in $DKMS_SRC..."
        sudo cp -r "$WORKDIR/facetimehd" "$DKMS_SRC" \
            || fail "Copierea surselor DKMS a esuat."
    fi

    info "dkms add..."
    sudo dkms add -m facetimehd -v "$FTIMEHD_VER" 2>/dev/null \
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
# ETAPA 5/5 — Fix sistem: luminozitate ecran + suspend stabil
# =============================================================================
CURRENT_STEP="ETAPA 5/5 — Fix luminozitate si suspend"
step "$CURRENT_STEP"

# --- 5a: GRUB — luminozitate (acpi_backlight=native) + sleep mode (s2idle) ---
info "Verificare parametri GRUB..."

GRUB_FILE="/etc/default/grub"
GRUB_NEEDS_UPDATE=false

if grep -q "acpi_backlight=native" "$GRUB_FILE"; then
    warn "acpi_backlight=native deja prezent in GRUB."
else
    info "Adaugare acpi_backlight=native si mem_sleep_default=s2idle in GRUB..."
    sudo sed -i \
        's|GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"|GRUB_CMDLINE_LINUX_DEFAULT="\1 acpi_backlight=native mem_sleep_default=s2idle"|' \
        "$GRUB_FILE" || fail "Modificarea GRUB a esuat."
    GRUB_NEEDS_UPDATE=true
fi

if [ "$GRUB_NEEDS_UPDATE" = true ]; then
    info "Regenerare grub.cfg..."
    sudo update-grub || fail "update-grub a esuat."
fi

if grep -q "acpi_backlight=native" "$GRUB_FILE"; then
    ok "GRUB: acpi_backlight=native + mem_sleep_default=s2idle aplicate."
else
    fail "Parametrii GRUB nu au fost scrisi corect in $GRUB_FILE."
fi

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
echo -e "  ${GREEN}✓${NC}  Suspend stabil — s2idle + hook facetimehd"
echo ""
echo -e "  ${YELLOW}⚠${NC}  Necesar: ${BOLD}sudo reboot${NC} pentru a activa toate modificarile."
echo ""
