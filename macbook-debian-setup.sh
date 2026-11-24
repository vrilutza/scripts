#!/bin/bash
# =============================================================================
#  MacBook Pro 13" 2017 (A1708) — Debian trixie / forky / sid — Setup Script
# =============================================================================
#
#  Ce instaleaza:
#    1. Dependente (build-essential, dkms, linux-headers-amd64, etc.)
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

# O singura rulare a scriptului odata, pe masina: flock pe /run/lock/macbook-setup.lock, tinut pana iese scriptul.
# Se ia inainte de etapa 1: instalarea headerelor de acolo poate porni `dkms autoinstall`, care ar instala sau ar scoate
# module in timp ce alta rulare e in etapele 2-4. Un `apt` pornit in afara scriptului nu e oprit de ea. Intoarce 1
# daca blocarea e ocupata sau nu se poate deschide.
setup_lock() {
    local lock=/run/lock/macbook-setup.lock
    # Redirectarea lui stderr e pe grup: pe `exec` insusi ar ramane pentru tot scriptul.
    { exec {SETUP_LOCK_FD}<>"$lock"; } 2>/dev/null || { exec {SETUP_LOCK_FD}<"$lock"; } 2>/dev/null \
        || { warn "Nu pot deschide blocarea $lock."; return 1; }
    flock -n "$SETUP_LOCK_FD" \
        || { warn "O alta rulare a scriptului e in curs (blocare: $lock); reia dupa ce se termina."; return 1; }
}

# Pachetul $1 e instalat, inclusiv cand e pus pe hold: `dpkg -l | grep "^ii"` rateaza starea "hi".
pkg_installed() { [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = installed ]; }

# --- DKMS: un modul instalat din git (etapele 2 si 4) ---
# Kernelurile cu headere instalate. Modulele se construiesc pentru toate, nu doar pentru cel pornit:
# altfel kernelul de rezerva ramane fara driver.
kernels_with_headers() {
    for b in /lib/modules/*/build; do
        [ -e "$b/Makefile" ] && basename "$(dirname "$b")"
    done
}

# `dkms status` cu argumentele date. Intoarce 1, cu un avertisment, doar daca interogarea insasi esueaza;
# o versiune neinregistrata da un raspuns gol si rc 0. Se foloseste unde un raspuns "neinregistrat" sau
# "neinstalat" duce la o stergere, ca o eroare sa nu fie citita drept un astfel de raspuns.
dkms_st() {
    local out
    out=$(sudo dkms status "$@" 2>/dev/null) \
        || { warn "dkms status $* a esuat; nu sterg si nu inlocuiesc nimic pe baza ei." >&2; return 1; }
    [ -z "$out" ] || printf '%s\n' "$out"
}

# Versiunea modulului $1 activa ("installed") pe kernelul $2; nimic daca nu e niciuna. DKMS tine o singura
# versiune activa pe kernel. Intoarce 1 daca interogarea esueaza: fara raspuns nu se poate nota versiunea la
# care se revine, iar `dkms install` ar inlocui-o oricum.
dkms_active() {
    local st
    st=$(dkms_st -m "$1" -k "$2") || return 1
    sed -n "s#^$1/\([^,]*\), $2, [^:]*: installed.*#\1#p" <<< "$st" | head -n 1
}

# Versiunile modulului $1 inregistrate in DKMS. Se iau doar liniile modulului:
# "<modul>/<v>, <kernel>, ..." si "<modul>/<v>: added".
dkms_versions() {
    local st
    st=$(dkms_st -m "$1") || return 1
    sed -n "s#^$1/\([^,:]*\).*#\1#p" <<< "$st" | sort -u
}

# Calea $1 lipseste, constatat din continutul unui director: directorul ei, sau primul director parinte care
# se poate lista, nu contine numele urmator din cale. `test -e` nu ajunge: intoarce fals la orice eroare a
# lui stat (de exemplu EIO), iar atunci fisierul poate exista. Se listeaza "$d/.", nu "$d": `find` nu
# urmeaza un link simbolic dat ca punct de pornire, iar lista ar iesi goala.
path_absent() {
    local p=$1 d names
    while [ "$p" != / ]; do
        d=$(dirname "$p")
        if names=$(sudo find "$d/." -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null); then
            ! grep -qxF -- "$(basename "$p")" <<< "$names"
            return
        fi
        p=$d
    done
    return 1
}

# Modulele construite de DKMS pentru modulul $1, versiunea $2, kernelul $3 (fisiere regulate .ko, .ko.gz, .ko.xz
# sau .ko.zst din directorul module/ al arhitecturii), cate unul pe linie. Intoarce 1 daca `find` esueaza.
dkms_built_files() {
    sudo find "/var/lib/dkms/$1/$2/$3/$(uname -m)/module" -maxdepth 1 -type f \
        \( -name '*.ko' -o -name '*.ko.gz' -o -name '*.ko.xz' -o -name '*.ko.zst' \) 2>/dev/null
}

# DKMS are copia construita pe care `dkms install` o poate folosi pentru modulul $1, versiunea $2, pe kernelul $3.
# Doua verificari, ambele dupa regulile DKMS 3.2.2:
#   - `dkms status` cauta fiecare modul din dkms.conf in arborele construit, dupa nume si extensie, si adauga
#     "(Built modules are missing ...)" cand nu il gaseste;
#   - status verifica doar ca fisierul exista, iar install cere un fisier regulat. DKMS alege <nume>.ko daca exista
#     (`-e`), altfel <nume>.ko<compresie>, apoi cere `-f`. In module/ se verifica deci, cu aceleasi teste: orice
#     *.ko existent, si orice *.ko.gz|xz|zst fara *.ko-ul lui, trebuie sa fie fisier regulat. Numele modulelor nu
#     se citesc din dkms.conf, asa ca un *.ko nefolosit care nu e fisier regulat opreste si el.
# Intoarce 0 daca versiunea apare "built" sau "installed" pe $3, fara mesaj si fara intrari nepotrivite, 1 altfel
# si 2 daca o verificare nu se poate face.
dkms_built_ok() {
    local st bad
    st=$(dkms_st -m "$1" -v "$2" -k "$3") || return 2
    grep -q ': \(built\|installed\)' <<< "$st" || return 1
    grep -q 'Built modules are missing' <<< "$st" && return 1
    # shellcheck disable=SC2016 # variabilele sunt ale lui sh -c
    bad=$(sudo sh -c 'cd "$1" || exit 1
        for e in *.ko *.ko.gz *.ko.xz *.ko.zst; do
            [ -e "$e" ] || continue
            case $e in *.ko) ;; *) [ -e "${e%.*}" ] && continue ;; esac
            [ -f "$e" ] || echo "$e"
        done
        echo sfarsit' sh "/var/lib/dkms/$1/$2/$3/$(uname -m)/module" 2>/dev/null)
    [ "${bad##*$'\n'}" = sfarsit ] || return 2
    [ "$bad" = sfarsit ]
}

# Fisierele modulului $1, versiunea $2, din /lib/modules/$3 sunt chiar cele construite de DKMS. Intoarce 0
# daca toate se potrivesc, 1 daca unul difera sau lipseste (constatat cu path_absent) si 2 daca verificarea
# nu s-a putut face: find, cmp sau sudo au esuat, ori nu exista niciun modul construit cu care sa compar.
# La 2 nu se inlocuieste nimic. Un sudo esuat intoarce 1, ca un `cmp` care gaseste o diferenta, de aceea
# comparatia ruleaza intr-o singura comanda sudo, care tipareste codul lui `cmp`.
dkms_files_ok() {
    local files f t r
    files=$(dkms_built_files "$1" "$2" "$3") \
        || { warn "Nu pot lista modulele construite din /var/lib/dkms/$1/$2/$3." >&2; return 2; }
    if [ -z "$files" ]; then
        warn "Nu gasesc modulele construite in /var/lib/dkms/$1/$2/$3; nu am cu ce compara fisierele instalate." >&2
        return 2
    fi
    for f in $files; do
        t="/lib/modules/$3/updates/dkms/$(basename "$f")"
        # shellcheck disable=SC2016 # $1 si $2 sunt ale lui sh -c
        r=$(sudo sh -c 'cmp -s "$1" "$2"; echo "$?"' sh "$f" "$t" 2>/dev/null)
        case $r in
            0) ;;
            1) return 1 ;;
            2) path_absent "$t" && return 1
               warn "Nu pot compara $t cu $f." >&2; return 2 ;;
            *) warn "Nu pot compara $t cu $f." >&2; return 2 ;;
        esac
    done
    return 0
}

# Modulul $1, versiunea $2, e versiunea activa pe kernelul $3 si fisierele ei sunt verificate. `dkms status`
# poate spune "installed" si cand un .ko lipseste. Intoarce 0, 1 sau 2 ca dkms_files_ok; 2 si daca
# interogarea `dkms status` esueaza.
dkms_installed_ok() {
    local act
    act=$(dkms_active "$1" "$3") || return 2
    [ "$act" = "$2" ] || return 1
    dkms_files_ok "$1" "$2" "$3"
}

# Kernelurile din lista $3 pe care modulul $1, versiunea $2, nu e instalat si verificat. Intoarce 2 daca pe
# vreunul verificarea nu s-a putut face.
dkms_missing() {
    local k r rc=0
    for k in $3; do
        dkms_installed_ok "$1" "$2" "$k"; r=$?
        [ "$r" -eq 0 ] && continue
        echo "$k"
        [ "$r" -eq 2 ] && rc=2
    done
    return "$rc"
}

# Ce versiune a modulului $1 e instalata si verificata pe fiecare kernel din lista $2.
dkms_report() {
    local k v found
    for k in $2; do
        found=""
        for v in $(dkms_versions "$1"); do
            dkms_installed_ok "$1" "$v" "$k" && { found=$v; break; }
        done
        if [ -n "$found" ]; then
            info "  $k: $1 $found"
        else
            warn "  $k: niciun $1 instalat cu fisierele verificate"
        fi
    done
}

# Starea DKMS pastrata intre rulari, in $WORKDIR/dkms-stare, ca o rulare intrerupta sa poata fi reluata.
# Fiecare nota se scrie inainte de pasul pe care il protejeaza; daca scrierea esueaza, pasul nu se face.
#   <modul>.activ      "<kernel> <versiunea de dinainte> <versiunea tinta>": scrisa inainte ca versiunea de
#                      dinainte sa fie dezinstalata de pe kernel. Se inchide cand tinta (sau, dupa o
#                      revenire, versiunea de dinainte) e instalata si verificata pe acel kernel.
#   <modul>.candidati  versiunile pe care acest script le exporta si le inregistreaza in DKMS, notate inainte
#                      de export. Un candidat ramas neinstalat ar putea fi ales de `dkms autoinstall` la
#                      urmatorul kernel, asa ca se scoate; versiunile inregistrate de mana (rezervele) nu
#                      sunt aici si nu se ating.
#   <modul>.inlocuite  versiunile de dinainte ale inlocuirilor terminate, notate inainte ca nota din .activ
#                      sa se inchida. Raman aici pana sunt scoase din DKMS, si peste o rulare intrerupta.
dkms_state() { echo "$WORKDIR/dkms-stare/$1"; }
activ_kernels() { awk '{ print $1 }' "$(dkms_state "$1.activ")" 2>/dev/null; }
activ_get() { awk -v k="$2" '$1 == k { print $2; exit }' "$(dkms_state "$1.activ")" 2>/dev/null; }
activ_target() { awk -v k="$2" '$1 == k { print $3; exit }' "$(dkms_state "$1.activ")" 2>/dev/null; }
activ_versions() { awk '{ print $2 }' "$(dkms_state "$1.activ")" 2>/dev/null | sort -u; }
activ_clear() {
    local f; f=$(dkms_state "$1.activ")
    [ -f "$f" ] || return 0
    awk -v k="$2" '$1 != k' "$f" > "$f.nou" && mv "$f.nou" "$f"
}
# Noteaza (sau corecteaza) pentru kernelul $2: versiunea activa $3 si tinta $4. Intoarce 1 daca nu poate scrie.
activ_set() {
    local f; f=$(dkms_state "$1.activ")
    mkdir -p "$WORKDIR/dkms-stare" || return 1
    { awk -v k="$2" '$1 != k' "$f" 2>/dev/null; echo "$2 $3 $4"; } > "$f.nou" && mv "$f.nou" "$f" \
        && [ "$(activ_get "$1" "$2")" = "$3" ]
}
# Listele <modul>.candidati si <modul>.inlocuite ($2), cu o versiune pe linie. lista_add reciteste lista
# si intoarce 1 daca versiunea nu a ajuns in ea.
lista_get() { cat "$(dkms_state "$1.$2")" 2>/dev/null; }
lista_add() {
    local f; f=$(dkms_state "$1.$2")
    mkdir -p "$WORKDIR/dkms-stare" || return 1
    lista_get "$1" "$2" | grep -qxF -- "$3" && return 0
    echo "$3" >> "$f" && lista_get "$1" "$2" | grep -qxF -- "$3"
}
lista_del() {
    local f; f=$(dkms_state "$1.$2")
    [ -f "$f" ] || return 0
    grep -vxF -- "$3" "$f" > "$f.nou"; mv "$f.nou" "$f"
}

# Scoate versiunea $2 a modulului $1 din DKMS. Sursa se sterge doar daca `dkms remove` a reusit, iar un link
# (0.1 de la install.cirrus.driver.sh -i duce in clona) se sterge doar ca link.
dkms_remove_version() {
    info "Scot versiunea DKMS $1 $2..."
    if sudo dkms remove -m "$1" -v "$2" --all; then
        if [ -L "/usr/src/$1-$2" ]; then
            sudo rm -f "/usr/src/$1-$2"
        else
            sudo rm -rf "/usr/src/$1-$2"
        fi
    else
        warn "dkms remove $1 $2 a esuat; sursa /usr/src/$1-$2 ramane."
        return 1
    fi
}

# Un candidat creat de script care n-a ajuns instalat nicaieri se scoate, ca DKMS sa nu-l aleaga singur
# la urmatorul kernel. Daca rularea s-a oprit inainte de `dkms add`, ramane doar sursa exportata. Daca
# `dkms status` esueaza, nu se sterge nimic si candidatul ramane notat.
dkms_drop_candidate() {
    local st
    lista_get "$1" candidati | grep -qxF -- "$2" || return 0
    activ_versions "$1" | grep -qxF -- "$2" && return 0
    st=$(dkms_st -m "$1" -v "$2") || return 1
    grep -q ': installed' <<< "$st" && return 0
    if [ -n "$st" ]; then
        dkms_remove_version "$1" "$2" || return 1
    elif [ -d "/usr/src/$1-$2" ] && [ ! -L "/usr/src/$1-$2" ]; then
        info "Sterg sursa exportata, neinregistrata, /usr/src/$1-$2..."
        sudo rm -rf "/usr/src/$1-$2" || return 1
    fi
    lista_del "$1" candidati "$2"
}

# Scoate din DKMS versiunile din <modul>.inlocuite care nu mai sunt instalate nicaieri si nu sunt cerute de
# o nota din <modul>.activ; $2, tinta instalata acum peste tot, doar iese din lista. O versiune inca
# instalata (pe un kernel fara headere) ramane in lista, la fel una pentru care `dkms status` sau
# `dkms remove` esueaza: se reincearca la urmatoarea rulare.
dkms_drop_replaced() {
    local v st
    for v in $(lista_get "$1" inlocuite); do
        if [ "$v" = "$2" ]; then
            lista_del "$1" inlocuite "$v"
            continue
        fi
        activ_versions "$1" | grep -qxF -- "$v" && continue
        st=$(dkms_st -m "$1" -v "$v") || continue
        if grep -q ': installed' <<< "$st"; then
            info "Pastrez $1 $v: e inca instalat pe $(sed -n 's#^[^,]*, \([^,]*\),.*: installed.*#\1#p' <<< "$st" | paste -sd ' ' -), kernel fara headere."
            continue
        fi
        if [ -n "$st" ]; then
            dkms_remove_version "$1" "$v" || continue
        fi
        lista_del "$1" inlocuite "$v"
    done
}

# Pune la loc pe kernelul $2 versiunea $3 a modulului $1, cea notata in <modul>.activ, dupa ce scoate de pe
# kernel versiunea $4 (lipsa sau stricata, constatat), daca DKMS o arata activa acolo. Daca interogarea
# esueaza sau e activa alta versiune, nu schimba nimic. Nota se inchide doar daca $3 se verifica.
dkms_restore() {
    local act r
    act=$(dkms_active "$1" "$2") || return 1
    if [ -n "$3" ]; then
        dkms_built_ok "$1" "$3" "$2"; r=$?
        if [ "$r" -eq 2 ]; then
            warn "Nu pot afla daca DKMS are copia construita a lui $1 $3 pe $2; nu dezinstalez nimic, nota ramane."
            return 1
        fi
        if [ "$r" -ne 0 ]; then
            warn "Nu pot pune la loc $1 $3 pe $2: DKMS nu are o copie construita utilizabila a lui; nu dezinstalez nimic."
            warn "Se reconstruieste cu: sudo dkms build -m $1 -v $3 -k $2 --force; nota ramane in $(dkms_state "$1.activ")."
            return 1
        fi
    fi
    if [ -n "$act" ]; then
        if [ "$act" != "$4" ]; then
            warn "Pe $2 e activ acum $1 $act, pe care nu l-am verificat; nu il inlocuiesc."
            return 1
        fi
        sudo dkms uninstall -m "$1" -v "$4" -k "$2" || warn "Nu am putut dezinstala $1 $4 de pe $2."
    fi
    if [ -z "$3" ]; then
        warn "Pe $2 nu era instalata alta versiune inainte."
        return 1
    fi
    warn "Reinstalez pe $2 versiunea de dinainte, $3."
    if sudo dkms install -m "$1" -v "$3" -k "$2"; then
        dkms_installed_ok "$1" "$3" "$2"; r=$?
    else
        r=1
    fi
    if [ "$r" -eq 0 ]; then
        activ_clear "$1" "$2" || warn "Nu pot inchide nota pentru $2; se inchide la urmatoarea rulare."
        return 0
    fi
    if [ "$r" -eq 2 ]; then
        warn "Nu pot verifica $1 $3 pe $2; ramane notat in $(dkms_state "$1.activ") pentru reluare."
    else
        warn "Nici $3 nu s-a putut verifica pe $2; ramane notat in $(dkms_state "$1.activ") pentru reluare."
    fi
    return 1
}

# Inchide notele din <modul>.activ lasate de o rulare intrerupta, dupa versiunea activa acum pe kernelul
# notei (intoarce 1 daca nu se poate afla):
#   - versiunea de dinainte, verificata: revenirea s-a terminat;
#   - tinta sau o alta versiune (instalata intre timp, de exemplu de `dkms autoinstall`), verificata:
#     inlocuirea s-a terminat, iar versiunea de dinainte trece in <modul>.inlocuite;
#   - o versiune ale carei fisiere nu se pot verifica: intoarce 1, fara sa o inlocuiasca, iar nota ramane;
#   - niciuna, sau una cu un fisier lipsa sau diferit: versiunea de dinainte se pune la loc inainte de orice
#     build. Daca nu se poate, intoarce 1 si nota ramane, ca rularea sa nu continue cu un kernel fara driver.
activ_reconcile() {
    local k p t act r
    for k in $(activ_kernels "$1"); do
        p=$(activ_get "$1" "$k")
        t=$(activ_target "$1" "$k")
        act=$(dkms_active "$1" "$k") || return 1
        r=1
        if [ -n "$act" ]; then
            dkms_files_ok "$1" "$act" "$k"; r=$?
        fi
        if [ "$r" -eq 2 ]; then
            warn "Ma opresc: pe $k e activ $1 $act, dar nu ii pot verifica fisierele; nu il inlocuiesc."
            warn "Nota din $(dkms_state "$1.activ") ramane; reia scriptul cand verificarea merge."
            return 1
        fi
        if [ "$r" -eq 0 ]; then
            if [ "$act" = "$p" ]; then
                activ_clear "$1" "$k"
            else
                [ "$act" = "$t" ] \
                    || info "Pe $k e activ acum $1 $act, instalat dupa rularea intrerupta; nu pun la loc $p."
                lista_add "$1" inlocuite "$p" && activ_clear "$1" "$k"
            fi
            continue
        fi
        warn "O rulare anterioara s-a oprit cu $k fara $1 verificat."
        if ! dkms_restore "$1" "$k" "$p" "$act"; then
            warn "Ma opresc: $k a ramas fara $1 verificat. Pune la loc o versiune (sudo dkms install -m $1 -v $p -k $k)"
            warn "sau, daca nu mai folosesti $k, sterge linia lui din $(dkms_state "$1.activ"); apoi reia scriptul."
            return 1
        fi
    done
}

# Ruleaza comanda $2... cat timp tine blocarea modulului $1, ca doua rulari care schimba starea DKMS a aceluiasi
# modul sa nu se suprapuna. Arborele DKMS e al masinii, deci si blocarea: flock pe
# /run/lock/macbook-setup-dkms-<modul>.lock, oricare ar fi $WORKDIR. Fisierul se deschide fara trunchiere (`<>`),
# sau doar pentru citire daca e al altui utilizator; flock merge pe ambele. Blocarea tine cat ruleaza comanda: un
# `sudo dkms ...` pornit din ea tine descriptorul deschis cat lucreaza (comanda lui nu-l primeste, sudo inchide
# descriptorii de la 3 in sus), si dupa ce scriptul e omorat. Se asteapta pana la 10 s: un proces pornit fara sudo
# (de exemplu `sleep 3`-ul ramas din bucla de progres a DKMS, cand dkms ruleaza fara sudo) poate tine descriptorul
# cateva secunde. Daca blocarea nu se elibereaza, intoarce 1 fara sa ruleze comanda.
dkms_with_lock() {
    local fd rc lock="/run/lock/macbook-setup-dkms-$1.lock"
    # Redirectarea lui stderr e pe grup: pe `exec` insusi ar ramane pentru tot scriptul.
    { exec {fd}<>"$lock"; } 2>/dev/null || { exec {fd}<"$lock"; } 2>/dev/null \
        || { warn "Nu pot deschide blocarea $lock; ma opresc fara sa schimb nimic."; return 1; }
    if ! flock -w 10 "$fd"; then
        warn "O alta rulare schimba deja $1 in DKMS (blocare: $lock); ma opresc fara sa schimb nimic."
        exec {fd}>&-
        return 1
    fi
    "${@:2}"; rc=$?
    exec {fd}>&-
    return "$rc"
}

# Instaleaza modulul $1, versiunea $2, din commitul HEAD al clonei $3, pentru kernelurile din lista $4,
# fara sa lase un kernel fara driver daca ceva esueaza:
#   0. Notele din <modul>.activ lasate de o rulare intrerupta se inchid, iar un kernel ramas fara modulul
#      verificat primeste inapoi versiunea notata; daca nu se poate, functia se opreste. Candidatii lasati
#      de o rulare anterioara, neinstalati nicaieri, se scot.
#   1. Candidatul se noteaza, apoi sursa se exporta din commit (git archive), deci modificarile locale si
#      fisierele neversionate ale clonei nu intra, iar versiunea numeste exact codul compilat. O sursa
#      deja inregistrata pentru aceeasi versiune (de la o rulare intrerupta) nu se rescrie.
#   2. Se construieste pentru toate kernelurile. La un esec se opreste fara sa schimbe ceva pe kerneluri,
#      iar candidatul se scoate.
#   3. Daca pe vreun kernel verificarea nu se poate face, sau lipseste copia construita a versiunii noi ori
#      a celei active (necesara revenirii), functia se opreste inainte sa schimbe vreun kernel, iar
#      candidatul se scoate. Altfel, pe fiecare kernel fara versiunea noua instalata si
#      verificata: versiunea activa e aflata (daca
#      interogarea esueaza, functia se opreste). Daca e alta decat cea noua, e notata in <modul>.activ
#      (fara nota scrisa, nu se dezinstaleaza nimic); daca e chiar cea noua, se merge mai departe doar
#      daca un fisier al ei lipseste sau difera. Versiunea activa e dezinstalata, cea noua e instalata si
#      verificata, iar versiunea de dinainte trece in <modul>.inlocuite. Daca instalarea esueaza sau un
#      fisier lipseste ori difera, candidatul e dezinstalat de pe acel kernel, iar versiunea notata e
#      reinstalata si verificata; apoi functia se opreste. Daca verificarea nu se poate face (aici sau
#      inainte de dezinstalare), functia se opreste fara sa inlocuiasca ceva, iar nota ramane.
#   4. Abia cand versiunea noua e instalata si verificata pe toate kernelurile se scot versiunile din
#      <modul>.inlocuite care nu mai sunt instalate nicaieri (un kernel fara headere o poate folosi
#      inca). Celelalte versiuni inregistrate (o rezerva pastrata de mana) raman neatinse si sunt listate.
# Intoarce 0 daca versiunea noua e instalata si verificata pe toate kernelurile. La 1, apelantul
# tipareste ce versiune are fiecare kernel (dkms_report). Doua rulari pentru acelasi modul nu se suprapun
# (dkms_with_lock): a doua se opreste fara sa schimbe ceva.
dkms_install_from_git() { dkms_with_lock "$1" dkms_install_from_git_locked "$@"; }
dkms_install_from_git_locked() {
    local mod=$1 ver=$2 clone=$3 kernels=$4
    local src="/usr/src/$1-$2" k v act prev st r missing

    activ_reconcile "$mod" || return 1
    for v in $(lista_get "$mod" candidati); do
        [ "$v" = "$ver" ] || dkms_drop_candidate "$mod" "$v"
    done

    st=$(dkms_st -m "$mod" -v "$ver") || return 1
    if [ -n "$st" ]; then
        info "$mod $ver e deja inregistrat in DKMS; sursa din $src ramane cum e."
    else
        lista_add "$mod" candidati "$ver" \
            || { warn "Nu pot scrie in $(dkms_state "$mod.candidati"); nu inregistrez $ver."; return 1; }
        info "Export sursa $mod $ver din git in $src..."
        { sudo rm -rf "$src" && sudo mkdir -p "$src"; } || return 1
        git -C "$clone" archive HEAD | sudo tar -x -C "$src" || return 1
        sudo sed -i "s/^PACKAGE_VERSION=.*/PACKAGE_VERSION=\"$ver\"/" "$src/dkms.conf" || return 1
        sudo dkms add -m "$mod" -v "$ver" || { dkms_drop_candidate "$mod" "$ver"; return 1; }
    fi

    for k in $kernels; do
        sudo dkms status -m "$mod" -v "$ver" -k "$k" 2>/dev/null | grep -qE ': (built|installed)' && continue
        info "dkms build $mod $ver pentru $k..."
        if ! sudo dkms build -m "$mod" -v "$ver" -k "$k"; then
            warn "Build-ul $mod $ver pentru $k a esuat; nu schimb nimic pe kerneluri."
            dkms_drop_candidate "$mod" "$ver"
            return 1
        fi
    done

    # Verificarea de pe toate kernelurile se face inainte de primul `uninstall`: o eroare cunoscuta pe un
    # kernel nu trebuie sa apara abia dupa ce altul a fost schimbat.
    missing=$(dkms_missing "$mod" "$ver" "$kernels") || {
        warn "Ma opresc inainte sa schimb vreun kernel: $mod $ver nu se poate verifica pe toate kernelurile."
        dkms_drop_candidate "$mod" "$ver"
        return 1
    }
    # Tot inainte de primul `uninstall`: pe fiecare kernel de schimbat, DKMS are copia construita a versiunii noi
    # (poate spune "built" si cand modulul lipseste) si, daca alta versiune e activa, copia construita a ei, din
    # care o reinstaleaza la revenire (dkms_built_ok).
    for k in $missing; do
        act=$(dkms_active "$mod" "$k") || return 1
        dkms_built_ok "$mod" "$ver" "$k"; r=$?
        if [ "$r" -eq 2 ]; then
            warn "Ma opresc inainte sa schimb vreun kernel: nu pot afla daca DKMS are $mod $ver construit pentru $k."
            dkms_drop_candidate "$mod" "$ver"
            return 1
        fi
        if [ "$r" -ne 0 ]; then
            warn "Ma opresc inainte sa schimb vreun kernel: DKMS nu are o copie construita utilizabila a lui $mod $ver pentru $k."
            dkms_drop_candidate "$mod" "$ver"
            # Indicatia depinde de ce a facut curatarea: un candidat scos nu se mai poate reconstrui cu `dkms build`.
            if st=$(dkms_st -m "$mod" -v "$ver"); then
                if [ -n "$st" ]; then
                    warn "Se reconstruieste cu: sudo dkms build -m $mod -v $ver -k $k --force"
                else
                    warn "Am scos candidatul $mod $ver; reia scriptul, care il exporta si il construieste din nou."
                fi
            fi
            return 1
        fi
        [ -n "$act" ] && [ "$act" != "$ver" ] || continue
        dkms_built_ok "$mod" "$act" "$k"; r=$?
        if [ "$r" -eq 2 ]; then
            warn "Ma opresc inainte sa schimb vreun kernel: nu pot afla daca DKMS are copia construita a lui $mod $act pentru $k, necesara revenirii."
            dkms_drop_candidate "$mod" "$ver"
            return 1
        fi
        if [ "$r" -ne 0 ]; then
            warn "Ma opresc inainte sa schimb vreun kernel: DKMS nu are o copie construita utilizabila a lui $mod $act pentru $k, deci n-as putea reveni la ea."
            warn "Se reconstruieste cu: sudo dkms build -m $mod -v $act -k $k --force"
            dkms_drop_candidate "$mod" "$ver"
            return 1
        fi
    done
    for k in $missing; do
        act=$(dkms_active "$mod" "$k") || return 1
        prev=$(activ_get "$mod" "$k")
        if [ "$act" = "$ver" ]; then
            # Versiunea noua e deja activa: se reinstaleaza, fara nota, doar daca un fisier al ei lipseste sau difera.
            dkms_files_ok "$mod" "$ver" "$k"; r=$?
            [ "$r" -eq 0 ] && continue
            if [ "$r" -eq 2 ]; then
                warn "Ma opresc: nu pot verifica fisierele $mod $ver pe $k; nu il reinstalez."
                return 1
            fi
        elif [ -n "$act" ]; then
            # Versiunea activa reala are prioritate fata de o nota mai veche pentru acelasi kernel.
            if ! activ_set "$mod" "$k" "$act" "$ver"; then
                warn "Nu pot nota versiunea activa $act pentru $k in $(dkms_state "$mod.activ"); nu dezinstalez nimic."
                dkms_drop_candidate "$mod" "$ver"
                return 1
            fi
            prev=$act
        fi
        if [ -n "$act" ]; then
            sudo dkms uninstall -m "$mod" -v "$act" -k "$k" || return 1
        fi
        info "dkms install $mod $ver pentru $k..."
        if sudo dkms install -m "$mod" -v "$ver" -k "$k"; then
            dkms_installed_ok "$mod" "$ver" "$k"; r=$?
        else
            r=1
        fi
        if [ "$r" -eq 0 ]; then
            if [ -n "$prev" ] && ! lista_add "$mod" inlocuite "$prev"; then
                warn "Nu pot nota $prev in $(dkms_state "$mod.inlocuite"); nota pentru $k se inchide la urmatoarea rulare."
            else
                activ_clear "$mod" "$k" || warn "Nu pot inchide nota pentru $k; se inchide la urmatoarea rulare."
            fi
            continue
        fi
        if [ "$r" -eq 2 ]; then
            warn "Ma opresc: nu pot verifica $mod $ver pe $k dupa instalare; nu inlocuiesc nimic."
            [ -n "$prev" ] && warn "Nota din $(dkms_state "$mod.activ") ramane; reia scriptul cand verificarea merge."
            return 1
        fi
        warn "Instalarea $mod $ver pentru $k nu s-a putut verifica."
        dkms_restore "$mod" "$k" "$prev" "$ver"
        dkms_drop_candidate "$mod" "$ver"
        return 1
    done

    lista_del "$mod" candidati "$ver"
    dkms_drop_replaced "$mod" "$ver"
    v=$(dkms_versions "$mod" | grep -vxF -- "$ver" | paste -sd ' ' -)
    [ -n "$v" ] && info "Alte versiuni $mod inregistrate, lasate neatinse: $v"
    [ -z "$(dkms_missing "$mod" "$ver" "$kernels")" ]
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
setup_lock || fail "Nu pornesc: scriptul ruleaza o singura data odata."

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║   MacBook Pro 13\" 2017 — Debian Setup               ║"
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

PKGS=(build-essential linux-headers-amd64 dkms git patch wget curl cpio xz-utils libssl-dev rfkill iw)

info "Actualizare lista de pachete..."
sudo apt-get update -qq || fail "apt-get update a esuat."

info "Instalare pachete necesare: ${PKGS[*]}"
sudo apt-get install -y "${PKGS[@]}" || fail "Instalarea pachetelor a esuat."

for pkg in "${PKGS[@]}"; do
    if pkg_installed "$pkg"; then
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

cd "$WORKDIR"
if [ -d "snd_hda_macbookpro" ]; then
    info "Repo exista, actualizez..."
    # Modificarile locale din clona nu se ating si nici nu intra in modulul construit: sursa DKMS se
    # exporta din commit. Versiunile vechi ale install.cirrus.driver.sh editau dkms.conf pe loc
    # (sed -i.orig), iar o asemenea editare blocheaza `git pull`.
    SND_HDA_DIRTY=$(git -C snd_hda_macbookpro status --porcelain --untracked-files=no 2>/dev/null \
        | awk '{print $2}' | paste -sd ' ' -)
    if [ -n "$SND_HDA_DIRTY" ]; then
        warn "Clona are modificari locale, pe care nu le ating: $SND_HDA_DIRTY"
        warn "Daca e doar dkms.conf editat de vechiul install.cirrus.driver.sh, il refaci cu: git -C $WORKDIR/snd_hda_macbookpro checkout -- dkms.conf"
    fi
    git -C snd_hda_macbookpro pull --quiet || warn "git pull a esuat, continui cu commitul existent."
else
    info "Clonez repo-ul..."
    git clone https://github.com/davidjo/snd_hda_macbookpro.git \
        || fail "git clone snd_hda_macbookpro a esuat."
fi

# Ca la camera (etapa 4): dkms.conf spune 0.1 pentru orice revizie, iar install.cirrus.driver.sh -i
# inregistreaza in DKMS un link spre clona, deci un `git pull` ar schimba codul compilat la urmatorul
# kernel fara sa se vada nicaieri. Versiunea se ia din git, iar sursa se exporta din commit.
SND_HDA_REV=$(git -C "$WORKDIR/snd_hda_macbookpro" rev-parse --short=10 HEAD 2>/dev/null)
[ -z "$SND_HDA_REV" ] && fail "Nu am putut citi revizia git din $WORKDIR/snd_hda_macbookpro."
SND_HDA_VER="0.1-$SND_HDA_REV"
info "Versiune driver audio: $SND_HDA_VER"

SND_HDA_KERNELS=$(kernels_with_headers)
[ -z "$SND_HDA_KERNELS" ] && fail "Nu am gasit headere de kernel in /lib/modules/*/build."

if [ -z "$(dkms_missing snd_hda_macbookpro "$SND_HDA_VER" "$SND_HDA_KERNELS")" ]; then
    info "Driver-ul audio $SND_HDA_VER e deja instalat pentru toate kernelurile."
fi
# Pentru fiecare kernel, PRE_BUILD (install.cirrus.driver.sh --dkms) descarca sursele sound/hda
# ale kernelului de pe kernel.org (poate dura cateva minute).
if ! dkms_install_from_git snd_hda_macbookpro "$SND_HDA_VER" "$WORKDIR/snd_hda_macbookpro" "$SND_HDA_KERNELS"; then
    warn "Starea pe kerneluri:"
    dkms_report snd_hda_macbookpro "$SND_HDA_KERNELS"
    fail "Driver-ul audio $SND_HDA_VER nu e instalat pentru toate kernelurile. Verifica cu: sudo dkms status"
fi
ok "Driver audio $SND_HDA_VER instalat prin DKMS pentru: $(echo "$SND_HDA_KERNELS" | paste -sd ' ' -)."

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

cd "$WORKDIR"
if [ -d "facetimehd" ]; then
    info "Repo exista, actualizez..."
    git -C facetimehd fetch --tags --quiet || warn "git fetch a esuat, continui cu versiunea existenta."
    git -C facetimehd pull --quiet || warn "git pull a esuat, continui cu versiunea existenta."
else
    info "Clonez repo-ul..."
    git clone https://github.com/patjak/facetimehd.git \
        || fail "git clone facetimehd a esuat."
fi

# Versiunea din dkms.conf e nemodificata in upstream de ani (0.7.0.1), asa ca nu
# spune nimic despre ce cod e de fapt instalat: doua instalari facute la luni
# distanta ar purta acelasi nume. Se ia din git, unde se vede si tag-ul, si cate
# comituri sunt peste el, si care comit anume.
FTIMEHD_VER=$(git -C "$WORKDIR/facetimehd" describe --tags --always 2>/dev/null)
[ -z "$FTIMEHD_VER" ] && FTIMEHD_VER=$(grep "^PACKAGE_VERSION=" \
    "$WORKDIR/facetimehd/dkms.conf" | cut -d= -f2 | tr -d '"')
[ -z "$FTIMEHD_VER" ] && FTIMEHD_VER="necunoscut"
info "Versiune driver camera: $FTIMEHD_VER"

FTIMEHD_KERNELS=$(kernels_with_headers)
[ -z "$FTIMEHD_KERNELS" ] && fail "Nu am gasit headere de kernel in /lib/modules/*/build."

if [ -z "$(dkms_missing facetimehd "$FTIMEHD_VER" "$FTIMEHD_KERNELS")" ]; then
    info "Driver-ul camerei $FTIMEHD_VER e deja instalat pentru toate kernelurile."
fi
# Sursa DKMS se exporta din commit la fiecare versiune noua: altfel `git pull` aduce cod nou, dar
# DKMS continua sa compileze copia veche din /usr/src.
if ! dkms_install_from_git facetimehd "$FTIMEHD_VER" "$WORKDIR/facetimehd" "$FTIMEHD_KERNELS"; then
    warn "Starea pe kerneluri:"
    dkms_report facetimehd "$FTIMEHD_KERNELS"
    fail "Driver-ul camerei $FTIMEHD_VER nu e instalat pentru toate kernelurile. Verifica cu: sudo dkms status"
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
# ETAPA 5/9 — Fix sistem: luminozitate ecran + suspend stabil + WiFi dupa sleep + Bluetooth + stabilitate WiFi + luminozitate fixa (ALS off)
# =============================================================================
CURRENT_STEP="ETAPA 5/9 — Fix luminozitate + auto-suspend dezactivat (S3 unreliable) + Bluetooth + stabilitate WiFi"
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

# --- 5g: WiFi BCM4350 — stabilitate: power-save off + panic auto-reboot ---
# Firmware-ul generic Broadcom (2015, fara NVRAM/CLM Apple) se desincronizeaza cronic de driver:
# DMAR fault (scriere DMA ilegala a chipului, blocata de IOMMU) + "brcmf_msgbuf_get_pktid:
# Invalid packet id" — observat de 23 de ori in ~7 saptamani pe acest hardware. Pe 2026-07-07
# desincronizarea a produs un skb corupt (125 fragmente, max 17) → GPF in memcpy in softirq →
# kernel panic "Fatal exception in interrupt" (dovada completa in pstore EFI; vezi TODO.md).
# Mitigare pana la firmware-ul Apple (fix definitiv, in TODO):
#  1. WiFi power-save OFF — reduce tranzitiile de stare ale firmware-ului; laptop mereu pe AC.
#  2. kernel.panic=10 — la panica, reboot automat dupa 10s in loc de freeze permanent (masina always-on).
# NU dezactiva IOMMU (intel_iommu=off) ca sa "dispara" erorile DMAR: el blocheaza scrierile DMA
# ilegale ale chipului; fara el aceleasi scrieri devin corupere silentioasa de memorie.
info "WiFi BCM4350: power-save off (NetworkManager) + kernel.panic auto-reboot..."

WIFI_PS_CONF="/etc/NetworkManager/conf.d/wifi-powersave-off.conf"
PANIC_CONF="/etc/sysctl.d/99-panic-reboot.conf"

if [ -f "$WIFI_PS_CONF" ] && grep -q 'wifi.powersave = 2' "$WIFI_PS_CONF"; then
    warn "NetworkManager wifi.powersave=2 (off) deja configurat la $WIFI_PS_CONF."
else
    sudo mkdir -p "$(dirname "$WIFI_PS_CONF")" || fail "Nu am putut crea $(dirname "$WIFI_PS_CONF")."
    sudo tee "$WIFI_PS_CONF" > /dev/null << 'WIFIPSEOF'
# BCM4350: firmware-ul se desincronizeaza sub power-save (vezi TODO.md) — 2 = dezactivat
[connection]
wifi.powersave = 2
WIFIPSEOF
    sudo systemctl restart NetworkManager 2>/dev/null \
        || warn "Restart NetworkManager a esuat — powersave off se aplica la urmatorul boot."
fi

# Aplica si pe interfata activa (efect imediat, fara sa astepte reconectarea NM)
WIFI_IF=$(sudo iw dev 2>/dev/null | awk '$1=="Interface"{print $2; exit}')
if [ -n "$WIFI_IF" ]; then
    sudo iw dev "$WIFI_IF" set power_save off 2>/dev/null || true
    PS_STATE=$(sudo iw dev "$WIFI_IF" get power_save 2>/dev/null)
    if echo "$PS_STATE" | grep -q 'off'; then
        ok "WiFi power-save: off pe $WIFI_IF (persistent via $WIFI_PS_CONF)."
    else
        warn "WiFi power-save: stare neconfirmata pe $WIFI_IF ($PS_STATE)."
    fi
else
    warn "Nu am gasit interfata WiFi — powersave off se aplica la urmatorul boot via NetworkManager."
fi

if [ -f "$PANIC_CONF" ] && grep -q 'kernel.panic = 10' "$PANIC_CONF"; then
    warn "kernel.panic=10 deja configurat la $PANIC_CONF."
else
    printf 'kernel.panic = 10\n' | sudo tee "$PANIC_CONF" > /dev/null
    sudo sysctl -p "$PANIC_CONF" > /dev/null || warn "sysctl -p a returnat eroare."
fi

if [ "$(cat /proc/sys/kernel/panic 2>/dev/null)" = "10" ]; then
    ok "kernel.panic=10 activ (reboot automat la 10s dupa panica)."
else
    warn "kernel.panic nu este 10 — verifica $PANIC_CONF."
fi

# --- 5h: Luminozitate fixa — dezactivare auto-brightness (senzor ALS) + idle-dim ---
# Cauza: MacBook-ul are senzor de lumina ambientala (acpi-als, langa camera) citit de
# iio-sensor-proxy. GNOME cu "Automatic Screen Brightness" activ regleaza singur
# backlight-ul dupa lumina din camera — ecranul se face ba mai inchis, ba mai deschis
# chiar daca userul a setat luminozitatea la maxim. Perceptia de culori mai calde/reci
# vine tot din variatiile de backlight (panoul 2017 NU are True Tone — doar 2018+).
# Fix: dezactivam auto-brightness + idle-dim (estomparea dupa inactivitate), ca
# luminozitatea sa ramana exact unde o seteaza userul. Diagnosticat 2026-07-12.
# Reversibil oricand: aceleasi chei cu 'true' (sau GNOME Settings -> Power).
info "Configurare GNOME: luminozitate fixa (auto-brightness + idle-dim off)..."

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.settings-daemon.plugins.power ambient-enabled false \
        || warn "Nu am putut dezactiva ambient-enabled (auto-brightness)."
    gsettings set org.gnome.settings-daemon.plugins.power idle-dim false \
        || warn "Nu am putut dezactiva idle-dim."

    AMBIENT=$(gsettings get org.gnome.settings-daemon.plugins.power ambient-enabled 2>/dev/null)
    IDLEDIM=$(gsettings get org.gnome.settings-daemon.plugins.power idle-dim 2>/dev/null)
    if [ "$AMBIENT" = "false" ] && [ "$IDLEDIM" = "false" ]; then
        ok "Luminozitate fixa: auto-brightness + idle-dim dezactivate."
    else
        warn "Luminozitate fixa: verificare esuata (ambient=$AMBIENT, idle-dim=$IDLEDIM)."
    fi
else
    warn "gsettings nu este disponibil — sari peste config luminozitate fixa."
fi


# =============================================================================
# ETAPA 6/9 — Accelerare video hardware VA-API (Intel Iris Plus 640)
# Problema: "vaInitialize failed: unknown libva error" in VS Code / Chrome
# Cauza:    driver-ele VA-API pentru Intel Kaby Lake nu sunt instalate
# Fix:      intel-media-va-driver (iHD, Kaby Lake+); intel-media-va-driver-non-free ramane, daca e deja instalat
# =============================================================================
CURRENT_STEP="ETAPA 6/9 — Accelerare video hardware VA-API"
step "$CURRENT_STEP"
info "Intel Iris Plus 640 (Kaby Lake) — instalare drivere VA-API..."

# intel-media-va-driver-non-free (din non-free) adauga codare si procesare video; e o alternativa la
# intel-media-va-driver (Conflicts), deci instalarea variantei din main ar scoate-o.
if pkg_installed intel-media-va-driver-non-free; then
    info "intel-media-va-driver-non-free e deja instalat; il pastrez."
    VAAPI_DRIVER=intel-media-va-driver-non-free
    VAAPI_PKGS=(vainfo)
else
    VAAPI_DRIVER=intel-media-va-driver
    VAAPI_PKGS=(intel-media-va-driver vainfo)
fi

info "Instalare pachete VA-API: ${VAAPI_PKGS[*]}"
sudo apt-get install -y "${VAAPI_PKGS[@]}" || fail "Instalarea pachetelor VA-API a esuat."

for pkg in "$VAAPI_DRIVER" vainfo; do
    if pkg_installed "$pkg"; then
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
        warn "VA-API instalat dar neactivat inca — va fi activ dupa reboot."
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
#   8a) thermald din apt — daemon dinamic care reduce P-state cand
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
    if pkg_installed "$pkg"; then
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
# fan1_min sta pe platform device pe 7.2.15 si pe device-ul hwmon al applesmc pe 7.3.5
# (applesmc.768/hwmon/hwmonN/fan1_min, dupa trecerea la hwmon_device_register_with_info).
fan_min_path() {
    for f in "$FAN_SMC/fan1_min" "$FAN_SMC"/hwmon/hwmon*/fan1_min; do
        [ -e "$f" ] && { echo "$f"; return 0; }
    done
    return 1
}

if ! fan_min_path > /dev/null; then
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

    # Helper: asteapta pana la 5s ca fan1_min sa existe (pe oricare din cele doua cai),
    # apoi scrie podeaua.
    sudo tee "$FAN_HELPER" > /dev/null << FANHLP
#!/bin/sh
i=0
while [ "\$i" -lt 50 ]; do
    for F in $FAN_SMC/fan1_min $FAN_SMC/hwmon/hwmon*/fan1_min; do
        [ -e "\$F" ] && { echo $FAN_MIN_RPM > "\$F"; exit 0; }
    done
    i=\$((i + 1)); sleep 0.1
done
echo "macbook-fan-floor: fan1_min nu a aparut in 5s sub $FAN_SMC" >&2; exit 1
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

    FAN_MIN_FILE=$(fan_min_path)
    FAN_MIN_READ=$(cat "$FAN_MIN_FILE" 2>/dev/null)
    if [ "$FAN_MIN_READ" = "$FAN_MIN_RPM" ]; then
        ok "Fan floor aplicat: fan1_min=$FAN_MIN_READ RPM (SMC auto deasupra)."
    else
        warn "Fan floor: fan1_min=$FAN_MIN_READ (asteptat $FAN_MIN_RPM). Verifica dupa reboot: cat $FAN_MIN_FILE"
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
echo -e "  ${GREEN}✓${NC}  Luminozitate fixa — auto-brightness (senzor ALS) + idle-dim dezactivate"
echo -e "  ${GREEN}✓${NC}  Reboot fix — reboot=pci in GRUB (reset fiabil pe Apple hardware)"
echo -e "  ${GREEN}✓${NC}  Suspend/hibernate blocat complet — sleep targets masked (S3 nefiabil)"
echo -e "  ${GREEN}✓${NC}  Lid close = lock screen (logind), nu suspend"
echo -e "  ${GREEN}✓${NC}  Sleep hooks (facetimehd + brcmfmac PCI unbind) — defensive pt suspend manual"
echo -e "  ${GREEN}✓${NC}  Touchpad: libinput protejeaza in userspace (nu mai aplicam patch DKMS)"
echo -e "  ${GREEN}✓${NC}  Touchpad UX — tap-to-click + natural scroll + disable-while-typing"
echo -e "  ${GREEN}✓${NC}  Accelerare video VA-API — ${VAAPI_DRIVER}"
echo -e "  ${GREEN}✓${NC}  thermald (Intel thermal daemon) + lm-sensors"
echo -e "  ${GREEN}✓${NC}  RAPL: PL1=22W / PL2=30W (Apple-like) prin regula udev + thermald reinit"
echo -e "  ${GREEN}✓${NC}  Fan floor: fan1_min=3500 RPM (rece la idle, SMC ramp auto deasupra)"
echo -e "  ${GREEN}✓${NC}  Bluetooth: unblock rfkill la boot + AutoEnable (BCM4350, mereu disponibil)"
echo -e "  ${GREEN}✓${NC}  WiFi stabilitate: power-save off + kernel.panic=10 (mitigare firmware BCM4350)"
echo -e "  ${GREEN}✓${NC}  Cosmetic: GNOME media-keys/usb-protection silentiate + applespi fnmode=1"
echo ""
echo -e "  ${YELLOW}⚠${NC}  Necesar: ${BOLD}sudo reboot${NC} pentru a activa toate modificarile."
echo ""
