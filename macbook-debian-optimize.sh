#!/bin/bash
# =============================================================================
#  MacBook Pro 13" 2017 (A1708) — Debian Testing — Optimizare RAM + boot
# =============================================================================
#
#  Companion pentru macbook-debian-setup.sh — dezactiveaza serviciile care nu
#  aduc nimic pe acest hardware/utilizare, pentru RAM liber si boot rapid in GDM.
#  Analiza completa (masuratori pe sistem viu, 12 iul 2026): fiecare pas de mai
#  jos a fost verificat individual (simulari apt, dependente de pachete, politici
#  de restart docker, socket-uri) ca sa NU afecteze stabilitatea.
#
#  Castig masurat (13 iul 2026, dupa o zi de rulare): boot 16s -> 9.9s;
#  servicii sistem (system.slice) 862 -> 223 MB; swap 3.7 GB -> 0;
#  pasii 13-16 mai elibereaza ~280 MB din sesiunea grafica.
#
#  Ce face (si cum se anuleaza fiecare):
#    1. Docker on-demand: disable docker.service, ramane docker.socket ->
#       daemonul + containerele (restart=always/unless-stopped) pornesc automat
#       la PRIMA comanda docker. Orfanul csmbraila_db (web-ul lui e oprit din
#       mai 2026): restart=no + stop.        [revert: systemctl enable docker]
#    2. NetworkManager-wait-online off — 3.6s de pe drumul critic al bootului.
#                    [revert: systemctl enable NetworkManager-wait-online]
#    3. Plymouth sters + 'quiet'/'splash' scoase din GRUB -> vezi serviciile
#       pornind la boot in loc de logo. GDM nu depinde de plymouth (verificat);
#       fara disc criptat/LVM nu e nevoie de el.  [revert: apt install plymouth]
#    4. gnome-software mask (user) — nu mai sta rezident ~30 MB pt. verificari
#       de update in fundal; update-urile se fac cu apt.
#                    [revert: systemctl --user unmask gnome-software]
#    5. localsearch-3 mask (user) — indexarea de fisiere (~55 MB); cautarea din
#       Files devine limitata.  [revert: systemctl --user unmask localsearch-3]
#    6. ModemManager off — nu exista modem WWAN. Pachetul RAMANE instalat
#       (network-manager il are in relatii).   [revert: systemctl enable --now]
#    7. fwupd mask + timer off — LVFS nu are firmware pt. Mac 2017.
#                    [revert: systemctl unmask fwupd; enable fwupd-refresh.timer]
#    8. CUPS on-demand REAL: disable cups.service + cups-browsed + cups.path;
#       ramane DOAR cups.socket -> printarea porneste automat cand chiar
#       printezi. (cups.path pornea cupsd la FIECARE boot: fisierul-semnal
#       /var/cache/cups/org.cups.cupsd persista pe disc intre reporniri —
#       vazut pe viu la boot-ul din 13 iul.)
#                    [revert: systemctl enable --now cups cups-browsed cups.path]
#    9. switcheroo-control off — un singur GPU, n-are ce comuta.
#   10. iio-sensor-proxy mask — singurul consumator (auto-brightness) e oprit
#       de setup (ETAPA 5h).     [revert: unmask + gsettings ambient-enabled]
#   11. networking.service (ifupdown) off — doar 'lo' in interfaces, totul e NM.
#   12. e2scrub timers off — functioneaza doar pe LVM; sistemul nu are LVM.
#   13. Evolution Data Server mask (user) — ~207 MB masurat (alarm-notify 87 +
#       source-registry 62 + addressbook 31 + calendar 27 MB). Fara conturi
#       online (GOA gol) nu serveste nimic. Calendarul din Shell nu mai arata
#       evenimente; GNOME Contacts/Calendar nu functioneaza pana la unmask.
#                    [revert: systemctl --user unmask evolution-source-registry
#                     evolution-calendar-factory evolution-addressbook-factory
#                     + sterge ~/.config/autostart/org.gnome.Evolution-alarm-notify.desktop]
#   14. packagekit mask — ~21 MB; pornea la fiecare boot desi gnome-software
#       (singurul client real) e mascat de pasul 4. apt nu trece prin
#       PackageKit. Hook-ul apt 20packagekit e deviat (dpkg-divert), altfel
#       fiecare apt update ar afisa un "Error: UnitMasked" inofensiv.
#                    [revert: systemctl unmask packagekit && dpkg-divert
#                     --rename --remove /etc/apt/apt.conf.d/20packagekit]
#   15. Remmina fara autostart in tray (~53 MB la login); aplicatia ramane
#       instalata si o deschizi normal cand ai nevoie.
#                    [revert: sterge linia Hidden=true din
#                     ~/.config/autostart/remmina-applet.desktop]
#   16. gvfs afc+goa monitor mask (user) — ~16 MB; afc = montare iPhone (nu
#       exista iPhone), goa = conturi online (nu exista). RAMAN gvfs-mtp si
#       gvfs-gphoto2: telefonul Samsung pe USB apare prin MTP (fisiere) sau
#       PTP (poze).  [revert: systemctl --user unmask gvfs-afc-volume-monitor
#                     gvfs-goa-volume-monitor]
#   17. firmware AutoBoot=%00 (+ auto-boot=false) — MacBook-urile 2016+ pornesc
#       SINGURE la ridicarea capacului / conectarea alimentarii; de aici
#       porniri nedorite la transport. Pe Intel fara T2 comutatorul efectiv e
#       AutoBoot binar (echivalentul 'nvram AutoBoot=%00' din macOS); scriem
#       si varianta ASCII auto-boot=false (T1/T2) pentru acoperire completa.
#       Dupa acest pas laptopul porneste doar de la butonul de pornire.
#                    [revert: comenzile info afisate de pasul 17 — aceleasi
#                     scrieri, cu 'true' respectiv %03]
#
#  NU se ating (folosite activ): bluetooth + mpris-proxy (casti Apple/Sony,
#  mouse Logitech), avahi (SSH/.local catre al doilea PC), gvfs-mtp/gphoto2
#  (telefon Samsung pe USB), bolt/udisks2 (necesare, oricum in paralel la boot).
#
#  Optiuni (schimba in 0 ca sa sari peste pasul respectiv):
#    OPT_DOCKER=1       — pasul 1 (site-urile dev nu mai sunt up imediat la boot)
#    OPT_LOCALSEARCH=1  — pasul 5 (cautarea in Files devine limitata)
#    OPT_EDS=1          — pasul 13 (calendarul din Shell nu mai arata evenimente)
#
#  Utilizare:
#    chmod +x macbook-debian-optimize.sh
#    ./macbook-debian-optimize.sh
#    sudo reboot        (castigul complet se vede dupa reboot)
#
#  Nota: nu rula ca root. Scriptul foloseste sudo intern. Idempotent — safe
#  de rulat de mai multe ori.
# =============================================================================

OPT_DOCKER=1
OPT_LOCALSEARCH=1
OPT_EDS=1

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
    echo -e "  Verifica output-ul de mai sus si reia cu: ${BOLD}./macbook-debian-optimize.sh${NC}"
    exit 1
}

CURRENT_STEP="initializare"
WORKDIR="$HOME/macbook-setup"
mkdir -p "$WORKDIR"
LOGFILE="$WORKDIR/optimize-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

[ "$EUID" -eq 0 ] && fail "Nu rula ca root. Foloseste un user normal cu sudo."
sudo -v 2>/dev/null || fail "Ai nevoie de acces sudo pentru a continua."

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║   MacBook Pro 13\" 2017 — Optimizare RAM + boot      ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
info "Log salvat in: $LOGFILE"

# Helper: dezactiveaza un unit system daca nu e deja dezactivat/mascat
sys_disable() {  # $1=unit  $2=--now optional
    local state
    state=$(systemctl is-enabled "$1" 2>/dev/null)
    case "$state" in
        disabled|masked) warn "$1 deja $state." ;;
        "")              warn "$1 nu exista pe sistem — sar peste." ;;
        *) sudo systemctl disable ${2:+--now} "$1" \
               || fail "Nu am putut dezactiva $1."
           ok "$1 dezactivat." ;;
    esac
}

sys_mask() {  # $1=unit (system)
    if [ "$(systemctl is-enabled "$1" 2>/dev/null)" = "masked" ]; then
        warn "$1 deja mascat."
    else
        sudo systemctl mask --now "$1" || fail "Nu am putut masca $1."
        ok "$1 mascat (nu mai poate fi pornit nici la cerere)."
    fi
}

user_mask() {  # $1=unit (user)
    if [ "$(systemctl --user is-enabled "$1" 2>/dev/null)" = "masked" ]; then
        warn "$1 (user) deja mascat."
    else
        systemctl --user mask --now "$1" || fail "Nu am putut masca $1 (user)."
        ok "$1 (user) mascat + oprit."
    fi
}

# =============================================================================
# PASUL 1 — Docker on-demand (cel mai mare castig: ~700 MB + 2.8s la boot)
# =============================================================================
if [ "$OPT_DOCKER" = "1" ]; then
    CURRENT_STEP="PASUL 1 — Docker on-demand"
    step "$CURRENT_STEP"

    # docker.socket trebuie sa ramana enabled — el porneste daemonul la prima
    # comanda docker; containerele cu restart=always/unless-stopped urca atunci.
    if [ "$(systemctl is-enabled docker.socket 2>/dev/null)" != "enabled" ]; then
        sudo systemctl enable docker.socket || fail "Nu am putut activa docker.socket."
        ok "docker.socket activat (pornire on-demand)."
    else
        ok "docker.socket ramane enabled (pornire on-demand la prima comanda docker)."
    fi
    sys_disable docker.service

    # containerd e enabled separat si porneste la boot (69 MB + ~440ms) desi
    # dockerd (ExecStart --containerd=...) il foloseste doar cand ruleaza.
    # docker.service are doar After=containerd (ordonare), NU Wants/Requires ->
    # ii adaugam un drop-in Wants= ca la activarea prin socket sa porneasca si
    # containerd automat, apoi il dezactivam la boot.
    DROPIN_DIR="/etc/systemd/system/docker.service.d"
    DROPIN="$DROPIN_DIR/containerd-ondemand.conf"
    if [ -f "$DROPIN" ]; then
        warn "Drop-in containerd-ondemand deja exista."
    else
        sudo mkdir -p "$DROPIN_DIR" || fail "Nu am putut crea $DROPIN_DIR."
        printf '# docker e pornit on-demand prin docker.socket; fara acest Wants,\n# containerd (doar After= in unitatea originala) nu ar mai porni deloc.\n[Unit]\nWants=containerd.service\n' \
            | sudo tee "$DROPIN" > /dev/null || fail "Nu am putut scrie $DROPIN."
        sudo systemctl daemon-reload
        ok "Drop-in creat: docker porneste containerd automat (Wants=)."
    fi
    sys_disable containerd.service --now

    # Orfanul csmbraila_db: containerele web/phpmyadmin ale stack-ului sunt
    # oprite din mai 2026, doar DB-ul mai porneste (restart=always) degeaba.
    # Atentie: orice comanda docker trezeste daemonul prin socket — deci
    # verificam orfanul DOAR daca daemonul e deja pornit (idempotenta fara
    # efecte secundare la re-rulari).
    if systemctl is-active --quiet docker.service \
        && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx csmbraila_db; then
        RESTART_POLICY=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' csmbraila_db 2>/dev/null)
        if [ "$RESTART_POLICY" != "no" ]; then
            docker update --restart=no csmbraila_db > /dev/null \
                || warn "Nu am putut schimba politica de restart la csmbraila_db."
            ok "csmbraila_db: restart=always -> no (nu mai porneste la boot)."
        else
            warn "csmbraila_db are deja restart=no."
        fi
        if [ "$(docker inspect --format '{{.State.Running}}' csmbraila_db 2>/dev/null)" = "true" ]; then
            docker stop csmbraila_db > /dev/null \
                || warn "Nu am putut opri csmbraila_db."
            ok "csmbraila_db oprit (repornesti cu: docker start csmbraila_db)."
        fi
    else
        warn "Docker inactiv sau containerul csmbraila_db inexistent — sar peste (orfanul e tratat la prima rulare)."
    fi
    info "Stack-urile alberto_caccia si pancronex urca automat la prima comanda docker."
else
    step "PASUL 1 — Docker: SARIT (OPT_DOCKER=0)"
fi

# =============================================================================
# PASUL 2 — NetworkManager-wait-online (3.6s pe drumul critic al bootului)
# =============================================================================
CURRENT_STEP="PASUL 2 — NetworkManager-wait-online"
step "$CURRENT_STEP"
# Dupa pasii 1/4/8 nimic nu mai cere network-online.target la boot, deci
# oricum nu ar mai rula — disable = plasa de siguranta.
sys_disable NetworkManager-wait-online.service

# =============================================================================
# PASUL 3 — Plymouth sters + boot verbose (vezi serviciile, nu logo)
# =============================================================================
CURRENT_STEP="PASUL 3 — Plymouth + GRUB verbose"
step "$CURRENT_STEP"

if dpkg -s plymouth > /dev/null 2>&1; then
    # Verificat: se sterg DOAR plymouth + plymouth-label (simulare apt);
    # gdm3 nu depinde de plymouth; nu exista disc criptat (fara prompt LUKS).
    sudo apt-get purge -y plymouth plymouth-label \
        || fail "Stergerea plymouth a esuat."
    ok "plymouth + plymouth-label sterse."
else
    warn "plymouth nu este instalat."
fi

GRUB_FILE="/etc/default/grub"
if grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" | grep -qE '\b(quiet|splash)\b'; then
    sudo sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/{s/\bquiet\b *//g; s/\bsplash\b *//g; s/" /"/}' \
        "$GRUB_FILE" || fail "Nu am putut edita $GRUB_FILE."
    sudo update-grub || fail "update-grub a esuat."
    ok "'quiet' scos din GRUB — la boot vezi mesajele serviciilor."
else
    warn "GRUB nu contine quiet/splash — nimic de facut."
fi
grep -E '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE" | grep -qE '\bquiet\b' \
    && fail "'quiet' este inca in $GRUB_FILE."

# =============================================================================
# PASUL 4 — gnome-software: nu mai sta rezident (~30 MB + activari packagekit)
# =============================================================================
CURRENT_STEP="PASUL 4 — gnome-software mask"
step "$CURRENT_STEP"
# NU se sterge pachetul: apt remove gnome-software ar trage dupa el metapachetele
# gnome/gnome-core/task-gnome-desktop (verificat prin simulare) si ar strica
# upgrade-urile viitoare de GNOME pe testing. Mask = ramane instalat, nu ruleaza.
user_mask gnome-software.service
info "Update-urile se fac cu apt (cum faci deja). Revert: systemctl --user unmask gnome-software && systemctl --user start gnome-software"

# =============================================================================
# PASUL 5 — localsearch-3 (indexare fisiere, ~55 MB)
# =============================================================================
if [ "$OPT_LOCALSEARCH" = "1" ]; then
    CURRENT_STEP="PASUL 5 — localsearch-3 mask"
    step "$CURRENT_STEP"
    user_mask localsearch-3.service
    # exista si un .desktop de autostart — il ascundem, altfel gnome-session
    # poate porni binarul direct, ocolind unitatea mascata
    AUTOSTART_OVERRIDE="$HOME/.config/autostart/localsearch-3.desktop"
    if [ -f /etc/xdg/autostart/localsearch-3.desktop ] && [ ! -f "$AUTOSTART_OVERRIDE" ]; then
        mkdir -p "$HOME/.config/autostart"
        printf '[Desktop Entry]\nType=Application\nName=LocalSearch\nHidden=true\n' \
            > "$AUTOSTART_OVERRIDE" || fail "Nu am putut scrie $AUTOSTART_OVERRIDE."
        ok "Autostart localsearch-3 ascuns (override Hidden=true)."
    else
        warn "Autostart localsearch-3: deja tratat sau inexistent."
    fi
    info "Cautarea din Files devine limitata. Revert: unmask + sterge $AUTOSTART_OVERRIDE"
else
    step "PASUL 5 — localsearch-3: SARIT (OPT_LOCALSEARCH=0)"
fi

# =============================================================================
# PASUL 6 — ModemManager (nu exista modem WWAN pe acest hardware)
# =============================================================================
CURRENT_STEP="PASUL 6 — ModemManager"
step "$CURRENT_STEP"
sys_disable ModemManager.service --now

# =============================================================================
# PASUL 7 — fwupd (LVFS nu livreaza firmware pentru Mac-uri 2017)
# =============================================================================
CURRENT_STEP="PASUL 7 — fwupd"
step "$CURRENT_STEP"
sys_disable fwupd-refresh.timer --now
sys_mask fwupd.service

# =============================================================================
# PASUL 8 — CUPS on-demand (socket-ul ramane: printarea porneste la nevoie)
# =============================================================================
CURRENT_STEP="PASUL 8 — CUPS on-demand"
step "$CURRENT_STEP"
sys_disable cups-browsed.service --now
sys_disable cups.service --now
# cups.path (PathExists=/var/cache/cups/org.cups.cupsd) pornea cupsd la FIECARE
# boot: fisierul-semnal persista pe disc intre reporniri. Socket-ul singur
# acopera complet printarea la cerere.
sys_disable cups.path --now
if [ "$(systemctl is-enabled cups.socket 2>/dev/null)" != "enabled" ]; then
    sudo systemctl enable cups.socket || warn "Nu am putut activa cups.socket."
fi
# daca cupsd a fost pornit de cups.path la boot-ul curent, il oprim acum.
# Atentie: cups.socket are PartOf=cups.service, deci stop-ul serviciului
# opreste si socket-ul — il repornim imediat ca printarea on-demand sa
# functioneze si in sesiunea curenta, nu doar dupa reboot.
if systemctl is-active --quiet cups.service; then
    sudo systemctl stop cups.service || warn "Nu am putut opri cups.service."
    ok "cups.service oprit (porneste la nevoie prin socket)."
fi
if ! systemctl is-active --quiet cups.socket; then
    sudo systemctl start cups.socket || warn "Nu am putut porni cups.socket."
    ok "cups.socket repornit (asculta pentru printare on-demand)."
fi
ok "doar cups.socket ramane activ (printare on-demand reala, zero pierdere)."

# =============================================================================
# PASUL 9-12 — marunte, toate cu risc zero verificat
# =============================================================================
CURRENT_STEP="PASUL 9 — switcheroo-control (un singur GPU)"
step "$CURRENT_STEP"
sys_disable switcheroo-control.service --now

CURRENT_STEP="PASUL 10 — iio-sensor-proxy (consumatorul e oprit de ETAPA 5h)"
step "$CURRENT_STEP"
sys_mask iio-sensor-proxy.service

CURRENT_STEP="PASUL 11 — networking.service (ifupdown legacy, doar lo)"
step "$CURRENT_STEP"
sys_disable networking.service

CURRENT_STEP="PASUL 12 — e2scrub (doar pentru LVM, sistemul nu are LVM)"
step "$CURRENT_STEP"
sys_disable e2scrub_all.timer --now
sys_disable e2scrub_reap.service

# =============================================================================
# PASUL 13 — Evolution Data Server (~207 MB; fara conturi online nu face nimic)
# =============================================================================
if [ "$OPT_EDS" = "1" ]; then
    CURRENT_STEP="PASUL 13 — Evolution Data Server mask"
    step "$CURRENT_STEP"
    # Masurat pe sistem viu (13 iul 2026), cu zero conturi configurate (GOA gol).
    # Pachetele RAMAN instalate — gnome-shell depinde de evolution-data-server;
    # doar unitatile user sunt mascate, deci activarea D-Bus esueaza curat
    # (o linie in jurnal cand deschizi calendarul din bara, atat).
    user_mask evolution-source-registry.service
    user_mask evolution-calendar-factory.service
    user_mask evolution-addressbook-factory.service
    # alarm-notify nu e serviciu, e autostart .desktop — il ascundem ca la
    # localsearch (pasul 5) si oprim instanta care ruleaza acum.
    EDS_OVERRIDE="$HOME/.config/autostart/org.gnome.Evolution-alarm-notify.desktop"
    if [ -f /etc/xdg/autostart/org.gnome.Evolution-alarm-notify.desktop ] && [ ! -f "$EDS_OVERRIDE" ]; then
        mkdir -p "$HOME/.config/autostart"
        printf '[Desktop Entry]\nType=Application\nName=Evolution Alarm Notify\nHidden=true\n' \
            > "$EDS_OVERRIDE" || fail "Nu am putut scrie $EDS_OVERRIDE."
        ok "Autostart evolution-alarm-notify ascuns (override Hidden=true)."
    else
        warn "Autostart evolution-alarm-notify: deja tratat sau inexistent."
    fi
    pkill -u "$USER" -f evolution-alarm-notify 2>/dev/null \
        && ok "evolution-alarm-notify oprit."
    info "Calendarul din Shell nu mai arata evenimente. Revert: unmask cele 3 unitati + sterge override-ul autostart."
else
    step "PASUL 13 — Evolution Data Server: SARIT (OPT_EDS=0)"
fi

# =============================================================================
# PASUL 14 — packagekit (update-urile se fac cu apt, nu prin PackageKit)
# =============================================================================
CURRENT_STEP="PASUL 14 — packagekit mask"
step "$CURRENT_STEP"
# Pornit la fiecare boot de un job de mentenanta (gdbus call ca root) si nu
# mai iesea din idle (~21 MB), desi gnome-software — singurul lui client
# real — e mascat de pasul 4. apt nu trece prin PackageKit.
sys_mask packagekit.service
# Sursa acelui gdbus call: hook-ul apt 20packagekit, care anunta daemonul
# dupa fiecare apt update / operatie dpkg (inclusiv apt-daily la boot). Cu
# serviciul mascat, apelul afiseaza "Error: ... UnitMasked" — inofensiv
# (apt isi termina treaba normal), dar il deviem ca sa dispara si eroarea,
# si activarea la boot. Divert-ul supravietuieste upgrade-urilor pachetului.
# Numele de deviere trebuie sa se termine in .disabled: e in lista implicita
# apt Dir::Ignore-Files-Silently, deci apt il ignora FARA sa afiseze un
# "Notice: Ignoring file..." la fiecare rulare (cum ar face cu .distrib,
# numele implicit dpkg-divert).
PK_HOOK="/etc/apt/apt.conf.d/20packagekit"
PK_DIVERT="$PK_HOOK.disabled"
if dpkg-divert --list "$PK_HOOK" 2>/dev/null | grep -q "to $PK_DIVERT"; then
    warn "Hook-ul apt 20packagekit deja deviat in .disabled."
else
    if dpkg-divert --list "$PK_HOOK" 2>/dev/null | grep -q .; then
        # deviat cu numele implicit .distrib (versiunea veche a pasului) —
        # il readucem si il deviem din nou, curat
        sudo dpkg-divert --rename --remove "$PK_HOOK" \
            || fail "Nu am putut anula devierea veche a $PK_HOOK."
        info "Devierea veche (.distrib) anulata — refac cu .disabled."
    fi
    if [ -e "$PK_HOOK" ]; then
        sudo dpkg-divert --rename --divert "$PK_DIVERT" --add "$PK_HOOK" \
            || fail "Nu am putut devia $PK_HOOK."
        ok "Hook-ul apt 20packagekit deviat in .disabled (apt il ignora silentios)."
        info "Revert: sudo dpkg-divert --rename --remove $PK_HOOK"
    else
        warn "Hook-ul apt 20packagekit inexistent — nimic de deviat."
    fi
fi

# =============================================================================
# PASUL 15 — Remmina fara autostart in tray (~53 MB la fiecare login)
# =============================================================================
CURRENT_STEP="PASUL 15 — Remmina fara autostart"
step "$CURRENT_STEP"
REMMINA_AUTOSTART="$HOME/.config/autostart/remmina-applet.desktop"
if [ -f "$REMMINA_AUTOSTART" ]; then
    if grep -q '^Hidden=true' "$REMMINA_AUTOSTART"; then
        warn "Remmina autostart deja ascuns."
    elif grep -q '^Hidden=' "$REMMINA_AUTOSTART"; then
        # fisierul generat de Remmina contine deja Hidden=false — il inlocuim,
        # nu adaugam a doua cheie (duplicatele deruteaza parserul GKeyFile)
        sed -i 's/^Hidden=.*/Hidden=true/' "$REMMINA_AUTOSTART" \
            || fail "Nu am putut edita $REMMINA_AUTOSTART."
        ok "Remmina nu mai porneste in tray la login (aplicatia ramane instalata)."
    else
        printf 'Hidden=true\n' >> "$REMMINA_AUTOSTART" \
            || fail "Nu am putut edita $REMMINA_AUTOSTART."
        ok "Remmina nu mai porneste in tray la login (aplicatia ramane instalata)."
    fi
else
    warn "Remmina autostart inexistent — nimic de facut."
fi

# =============================================================================
# PASUL 16 — gvfs: monitor iPhone (afc) + conturi online (goa)
# =============================================================================
CURRENT_STEP="PASUL 16 — gvfs afc+goa monitor mask"
step "$CURRENT_STEP"
# afc = Apple File Conduit (montare iPhone — nu exista iPhone); goa = GNOME
# Online Accounts (niciun cont configurat). RAMAN gvfs-mtp si gvfs-gphoto2:
# telefonul Samsung pe USB apare prin MTP (fisiere) sau PTP (poze).
user_mask gvfs-afc-volume-monitor.service
user_mask gvfs-goa-volume-monitor.service

# =============================================================================
# PASUL 17 — firmware auto-boot=false (nu mai porneste singur la capac)
# =============================================================================
CURRENT_STEP="PASUL 17 — firmware auto-boot=false"
step "$CURRENT_STEP"
# MacBook-urile 2016+ pornesc automat la ridicarea capacului si la conectarea
# alimentarii (variabila NVRAM Apple 'auto-boot', din fabrica 'true') — de
# aici pornirile nedorite cand e carat cu capacul inchis. Scriem 'false' in
# ACEEASI variabila — exact ce face 'nvram auto-boot=false' din macOS; nu
# atingem nicio alta variabila EFI. Formatul efivarfs: 4 octeti de atribute
# + valoarea ASCII. Firmware-ul Apple raporteaza la CITIRE atributele cu un
# bit propriu (07 00 00 80), dar kernelul respinge cu EINVAL orice bit din
# afara celor standard UEFI la scriere (efivarfs_file_write: attributes &
# ~EFI_VARIABLE_MASK — verificat in sursa 7.1) — deci scriem NV+BS+RT
# (07 00 00 00), forma acceptata si de kernel si de firmware.
AB_VAR="/sys/firmware/efi/efivars/auto-boot-7c436110-ab2a-4bbb-a880-fe41995c9f82"
if [ ! -e "$AB_VAR" ]; then
    warn "Variabila auto-boot nu exista in NVRAM (resetat?) — sar peste."
elif [ "$(tail -c +5 "$AB_VAR" 2>/dev/null)" = "false" ]; then
    warn "auto-boot deja false."
else
    # efivarfs marcheaza variabilele immutable — ridicam flag-ul inainte de scriere
    sudo chattr -i "$AB_VAR" 2>/dev/null
    printf '\x07\x00\x00\x00false' | sudo tee "$AB_VAR" > /dev/null \
        || fail "Nu am putut scrie auto-boot=false."
    [ "$(tail -c +5 "$AB_VAR" 2>/dev/null)" = "false" ] \
        || fail "auto-boot nu s-a schimbat (recitirea nu arata 'false')."
    ok "auto-boot=false scris (varianta ASCII, citita de firmware-urile T1/T2)."
    # backslash-urile sunt dublate pentru echo -e din info(); se afiseaza \x07 etc.
    info "Revert: sudo chattr -i \$VAR && printf '\\\\x07\\\\x00\\\\x00\\\\x00true' | sudo tee \$VAR  (VAR=$AB_VAR)"
fi
# Pe Mac-urile Intel FARA T2 (cazul A1708) comutatorul citit efectiv de SMC e
# variabila clasica AutoBoot, BINARA (%00=oprit, %03=pornit) — cea creata de
# 'nvram AutoBoot=%00' din macOS pentru modelele 2016-2017. Verificat pe viu
# 19 iul 2026: doar cu auto-boot=false (ASCII) laptopul tot pornea singur la
# ridicarea capacului; variabila AutoBoot nu exista si trebuie CREATA.
# Le setam pe amandoua — dublura e inofensiva si acopera ambele familii.
AB2_VAR="/sys/firmware/efi/efivars/AutoBoot-7c436110-ab2a-4bbb-a880-fe41995c9f82"
ab2_val() { od -An -tx1 -j4 "$AB2_VAR" 2>/dev/null | tr -d ' \n'; }
if [ "$(ab2_val)" = "00" ]; then
    warn "AutoBoot deja %00."
else
    [ -e "$AB2_VAR" ] && sudo chattr -i "$AB2_VAR" 2>/dev/null
    printf '\x07\x00\x00\x00\x00' | sudo tee "$AB2_VAR" > /dev/null \
        || fail "Nu am putut scrie AutoBoot=%00."
    [ "$(ab2_val)" = "00" ] \
        || fail "AutoBoot nu s-a schimbat (recitirea nu arata %00)."
    ok "AutoBoot=%00 — laptopul porneste doar de la butonul de pornire."
    info "Revert: sudo chattr -i \$VAR && printf '\\\\x07\\\\x00\\\\x00\\\\x00\\\\x03' | sudo tee \$VAR  (VAR=$AB2_VAR)"
fi

# =============================================================================
# VERIFICARE FINALA
# =============================================================================
CURRENT_STEP="verificare finala"
step "VERIFICARE FINALA"

check() {  # $1=unit $2=stare asteptata $3=scope (system|user)
    local got
    if [ "$3" = "user" ]; then
        got=$(systemctl --user is-enabled "$1" 2>/dev/null)
    else
        got=$(systemctl is-enabled "$1" 2>/dev/null)
    fi
    if [ "$got" = "$2" ]; then
        ok "$1 = $got"
    else
        warn "$1 = ${got:-inexistent} (asteptat: $2)"
    fi
}

[ "$OPT_DOCKER" = "1" ] && { check docker.service disabled system; check docker.socket enabled system; check containerd.service disabled system; }
check NetworkManager-wait-online.service disabled system
check ModemManager.service disabled system
check fwupd-refresh.timer disabled system
check fwupd.service masked system
check cups.service disabled system
check cups-browsed.service disabled system
check cups.path disabled system
check cups.socket enabled system
check switcheroo-control.service disabled system
check iio-sensor-proxy.service masked system
check networking.service disabled system
check e2scrub_all.timer disabled system
check packagekit.service masked system
dpkg-divert --list /etc/apt/apt.conf.d/20packagekit 2>/dev/null | grep -q '\.disabled' \
    && ok "hook apt packagekit deviat (.disabled)" \
    || warn "hook apt packagekit nedeviat sau cu nume vechi (apt va afisa Error/Notice)"
check gnome-software.service masked user
[ "$OPT_LOCALSEARCH" = "1" ] && check localsearch-3.service masked user
if [ "$OPT_EDS" = "1" ]; then
    check evolution-source-registry.service masked user
    check evolution-calendar-factory.service masked user
    check evolution-addressbook-factory.service masked user
fi
check gvfs-afc-volume-monitor.service masked user
check gvfs-goa-volume-monitor.service masked user
[ "$(tail -c +5 "$AB_VAR" 2>/dev/null)" = "false" ] && [ "$(ab2_val)" = "00" ] \
    && ok "firmware auto-boot=false + AutoBoot=%00 (nu porneste singur la capac/alimentare)" \
    || warn "auto-boot/AutoBoot incomplete (poate porni singur la ridicarea capacului)"
grep -q '^Hidden=true' "$HOME/.config/autostart/remmina-applet.desktop" 2>/dev/null \
    && ok "remmina autostart ascuns" \
    || warn "remmina autostart activ (fisier lipsa sau fara Hidden=true)"
dpkg -s plymouth > /dev/null 2>&1 && warn "plymouth inca instalat" || ok "plymouth sters"

echo ""
echo -e "${BOLD}${GREEN}  ╔══════════════════════════════════════════════════════╗"
echo "  ║              OPTIMIZARE APLICATA                    ║"
echo -e "  ╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✓${NC}  Castig masurat: boot 16s -> ~10s; servicii sistem 862 -> ~220 MB; sesiune -~280 MB"
echo -e "  ${YELLOW}⚠${NC}  Necesar: ${BOLD}sudo reboot${NC} pentru efectul complet."
echo -e "  ${BLUE}→${NC}  Dupa reboot, masoara cu: systemd-analyze && free -h"
echo -e "  ${BLUE}→${NC}  Docker: stack-urile dev pornesc la prima comanda docker (ex: docker ps)."
echo ""
