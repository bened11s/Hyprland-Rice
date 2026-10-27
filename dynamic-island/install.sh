#!/usr/bin/env bash
# install.sh — richtet den Dynamic-Island-Rice auf diesem Rechner ein.
#
# Laeuft aus einem frischen Klon heraus:
#
#     git clone https://github.com/Gamecat-HD/Hyprland-Rice.git
#     cd Hyprland-Rice
#     ./dynamic-island/install.sh
#
# Es verteilt hypr/, quickshell/dynamic-island/ und dynamic-island/ nach
# ~/.config (standardmaessig als Symlinks, damit ein `git pull` im Klon
# durchschlaegt) und richtet danach alles Weitere ein. Liegt das Repo selbst
# unter ~/.config, faellt das Verteilen weg.
#
# Idempotent: mehrfach ausfuehren schadet nicht.
#
# ACHTUNG: Dieses Skript wurde mit KI erstellt. Vor dem Ausfuehren durchlesen.
#
#   ./install.sh                 einrichten (fragt vorher nach)
#   ./install.sh --copy          Dateien kopieren statt verlinken
#   ./install.sh --install-deps  fehlende Pakete gleich mitinstallieren
#   ./install.sh --check         nur pruefen, nichts aendern
#   ./install.sh --dry-run       zeigen was passieren wuerde
#   ./install.sh -y              ohne Rueckfrage durchlaufen
set -uo pipefail

DI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Das Repo ist der Ordner darueber – egal wohin geklont wurde
REPO_DIR="$(cd "$DI_DIR/.." && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
BIN_DIR="$HOME/.local/bin"
BACKUP_DIR="$HOME/backups/dynamic-island-install-$(date +%Y%m%d-%H%M%S)"

SHELL_NAME="dynamic-island"
CHECK_ONLY=0
DRY_RUN=0
INSTALL_DEPS=0
ASSUME_YES=0
COPY=0
FAILED=0

# Was aus dem Repo nach ~/.config gehoert
DEPLOY_PATHS=(hypr quickshell/dynamic-island dynamic-island)

# ---------------------------------------------------------------- Ausgabe ---
c_reset=$'\033[0m'; c_blue=$'\033[1;34m'; c_green=$'\033[1;32m'
c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'; c_dim=$'\033[2m'

short() {  # short <pfad> — ~ nur, wenn der Pfad auch im HOME liegt
    case "$1" in
        "$HOME"/*) printf '~%s' "${1#$HOME}" ;;
        *) printf '%s' "$1" ;;
    esac
}

step() { printf '\n%s==>%s %s\n' "$c_blue" "$c_reset" "$1"; }
ok()   { printf '  %s✓%s %s\n' "$c_green" "$c_reset" "$1"; }
skip() { printf '  %s·%s %s\n' "$c_dim" "$c_reset" "$1"; }
warn() { printf '  %s!%s %s\n' "$c_yellow" "$c_reset" "$1"; }
fail() { printf '  %s✗%s %s\n' "$c_red" "$c_reset" "$1"; FAILED=1; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  %s[dry-run]%s %s\n' "$c_dim" "$c_reset" "$*"; else "$@"; fi; }

usage() {
    cat <<'EOF'
install.sh — richtet den Dynamic-Island-Rice auf diesem Rechner ein.

  ./install.sh                 einrichten (fragt vorher nach)
  ./install.sh --copy          Dateien kopieren statt verlinken
  ./install.sh --install-deps  fehlende Pakete gleich mitinstallieren
  ./install.sh --check         nur pruefen, nichts aendern
  ./install.sh --dry-run       zeigen was passieren wuerde
  ./install.sh -y              ohne Rueckfrage durchlaufen
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check) CHECK_ONLY=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --install-deps) INSTALL_DEPS=1 ;;
        --copy) COPY=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unbekannte Option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done
[ "$CHECK_ONLY" = 1 ] && DRY_RUN=1

# --------------------------------------------------------------- Warnung ---
ki_warnung() {
    printf '\n'
    printf '%s┌────────────────────────────────────────────────────────────────┐%s\n' "$c_yellow" "$c_reset"
    printf '%s│  ACHTUNG: Dieses Skript wurde mit KI erstellt.                 │%s\n' "$c_yellow" "$c_reset"
    printf '%s│  Lies es durch, bevor du es laufen laesst.                     │%s\n' "$c_yellow" "$c_reset"
    printf '%s│  Es fasst dein System an.                                      │%s\n' "$c_yellow" "$c_reset"
    printf '%s└────────────────────────────────────────────────────────────────┘%s\n' "$c_yellow" "$c_reset"
    cat <<EOF

  Was es aendert:
    - verlinkt hypr/, quickshell/dynamic-island/ und dynamic-island/ nach
      ~/.config (mit --copy stattdessen kopieren); was dort im Weg liegt,
      wandert vorher nach ~/backups/
    - Symlinks in ~/.local/bin (dynamic-island, hypr-profile, theme-set)
      und in ~/.config/fish/completions
    - legt Verzeichnisse an (~/.local/state/$SHELL_NAME, ~/.cache/$SHELL_NAME,
      ~/Pictures/{Wallpapers,Screenshots})
    - kopiert die Wallpaper aus dem Repo nach ~/Pictures/Wallpapers
      (vorhandene Dateien bleiben)
    - erzeugt ein Farbschema, falls keines da ist — das schreibt auch
      Farben nach Hyprland, GTK, Qt, btop, cava und Discord
    - legt ~/.config/hypr/profile an, falls es fehlt
EOF
    [ "$INSTALL_DEPS" = 1 ] && printf '    - installiert fehlende Pakete per paru/yay (fragt selbst nochmal)\n'
    printf '\n  Echte Dateien werden vorher nach ~/backups/ gesichert.\n'

    if [ "$DRY_RUN" = 1 ]; then
        printf '\n  %sNur Pruefung — es wird nichts geaendert.%s\n' "$c_dim" "$c_reset"
        return 0
    fi
    if [ "$ASSUME_YES" = 1 ]; then
        printf '\n  %s-y angegeben — laeuft ohne Rueckfrage durch.%s\n' "$c_dim" "$c_reset"
        return 0
    fi
    printf '\n  Fortfahren? [j/N] '
    local answer=""
    # Kein Eingabekanal (Cron, Pipe ohne Inhalt) -> leere Antwort -> Abbruch
    read -r answer || answer=""
    case "$answer" in
        [jJyY]|[jJ][aA]|[yY][eE][sS]) printf '\n' ;;
        *) printf '\n  Abgebrochen.\n'; exit 0 ;;
    esac
}

same_path() {  # same_path <a> <b> — zeigen beide auf dasselbe?
    [ "$(readlink -f "$1" 2>/dev/null)" = "$(readlink -f "$2" 2>/dev/null)" ]
}

backup_move() {  # backup_move <pfad> — aus dem Weg raeumen, nicht loeschen
    local target="$1" rel
    rel="${target#$HOME/}"
    run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    run mv "$target" "$BACKUP_DIR/$rel"
    warn "~${target#$HOME} liegt jetzt unter ~${BACKUP_DIR#$HOME}/$rel"
}

backup() {  # backup <datei> — echte Datei (kein Symlink) wegsichern
    local target="$1"
    [ -e "$target" ] && [ ! -L "$target" ] || return 0
    run mkdir -p "$BACKUP_DIR"
    run cp -a "$target" "$BACKUP_DIR/"
    warn "$(basename "$target") gesichert nach ~${BACKUP_DIR#$HOME}"
}

link() {  # link <ziel> <linkname>
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        skip "~${dst#$HOME} zeigt schon richtig"
        return 0
    fi
    backup "$dst"
    run mkdir -p "$(dirname "$dst")"
    run ln -sfn "$src" "$dst"
    ok "$(short "$dst") -> $(short "$src")"
}

# ----------------------------------------------------- 0. Verteilen ---
# Aus einem Klon irgendwo im Dateisystem die drei Teile nach ~/.config
# bringen. Symlinks, damit ein `git pull` im Klon sofort gilt; mit --copy
# stattdessen Kopien (dann muss man nach einem Pull erneut installieren).
deploy() {
    step "Konfiguration nach ~/.config bringen"

    if same_path "$REPO_DIR" "$CONFIG_DIR"; then
        skip "Das Repo IST ~/.config — nichts zu verteilen"
        return 0
    fi

    local rel src dst
    for rel in "${DEPLOY_PATHS[@]}"; do
        src="$REPO_DIR/$rel"
        dst="$CONFIG_DIR/$rel"

        if [ ! -e "$src" ]; then
            fail "$rel fehlt im Repo ($src)"
            continue
        fi
        if same_path "$dst" "$src"; then
            skip "~${dst#$HOME} zeigt schon auf das Repo"
            continue
        fi

        # Auch kaputte Symlinks muessen weg, deshalb -L dazu
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            backup_move "$dst"
        fi

        run mkdir -p "$(dirname "$dst")"
        if [ "$COPY" = 1 ]; then
            run cp -a "$src" "$dst"
            ok "$(short "$dst") kopiert"
        else
            run ln -sfn "$src" "$dst"
            ok "$(short "$dst") -> $(short "$src")"
        fi
    done
}

check_deploy() {
    step "Konfiguration unter ~/.config"

    if same_path "$REPO_DIR" "$CONFIG_DIR"; then
        skip "Das Repo IST ~/.config"
        return 0
    fi

    local rel dst
    for rel in "${DEPLOY_PATHS[@]}"; do
        dst="$CONFIG_DIR/$rel"
        if same_path "$dst" "$REPO_DIR/$rel"; then
            ok "~${dst#$HOME} zeigt auf das Repo"
        elif [ -e "$dst" ]; then
            warn "~${dst#$HOME} existiert, kommt aber nicht aus diesem Repo"
        else
            fail "~${dst#$HOME} fehlt"
        fi
    done
}

# ------------------------------------------------------------ 1. Pakete ---
# Binary -> Paket. Ohne diese laeuft die Shell nicht oder es fehlen Teile,
# die man sofort merkt (Leiste, Farben, Screenshots).
declare -A NEEDED=(
    [qs]=quickshell [python]=python [grim]=grim [slurp]=slurp [swappy]=swappy
    [hyprpicker]=hyprpicker [wl-copy]=wl-clipboard [cliphist]=cliphist
    [fuzzel]=fuzzel [gpu-screen-recorder]=gpu-screen-recorder [sass]=dart-sass
    [dconf]=dconf [notify-send]=libnotify [hyprctl]=hyprland
    # Sperrbildschirm: Super+L und der Sperren-Knopf der Settings-Karte.
    # Layout in hypr/hyprlock.conf, Farben in hypr/scheme/hyprlock.conf
    [hyprlock]=hyprlock
    # WLAN-Kachel, Netzliste und der Wifi-Ring in der Settings-Pille
    [nmcli]=networkmanager
    # Bluetooth-Kachel und Kopplung (der Dienst selbst redet ueber DBus,
    # bluetoothctl wird nur als Pairing-Agent gestartet)
    [bluetoothctl]=bluez-utils
    # Akku und Energieprofile holt Quickshell ueber DBus – dafuer muessen die
    # Daemons da sein; die CLIs dienen hier als Anwesenheitsprobe
    [upower]=upower
    [powerprofilesctl]=power-profiles-daemon
    # Cover-Bilder der Medien-Karte: laden und die Grundfarbe ziehen
    [curl]=curl
    [magick]=imagemagick
)

# Ohne die laeuft alles weiter, nur eine Einzelheit fehlt.
declare -A OPTIONAL=(
    # Balken im Medien-Player
    [cava]=cava
    # Helligkeit ueber DDC/CI (Brightness.qml). Am Laptop meist unnoetig,
    # dort regelt brightnessctl die interne Anzeige.
    [ddcutil]=ddcutil
    # Die VPN-Kachel kann zwischen NordVPN und Cloudflare WARP wechseln
    [nordvpn]=nordvpn-bin
    [warp-cli]=cloudflare-warp-bin
)

# Systemdienste, an denen die Shell ueber DBus haengt
declare -A SERVICES=(
    [NetworkManager]="WLAN-Liste und Kacheln"
    [bluetooth]="Bluetooth-Kachel"
    [upower]="Akkustand (Ring um die Uhr, Statuszeile)"
    [power-profiles-daemon]="Energieprofile"
)
declare -A SERVICE_PKG=(
    [NetworkManager]=networkmanager [bluetooth]=bluez
    [upower]=upower [power-profiles-daemon]=power-profiles-daemon
)

check_deps() {
    step "Abhaengigkeiten"
    local missing=()
    for bin in "${!NEEDED[@]}"; do
        if command -v "$bin" >/dev/null 2>&1; then
            ok "$bin"
        else
            fail "$bin fehlt (Paket: ${NEEDED[$bin]})"
            missing+=("${NEEDED[$bin]}")
        fi
    done

    for mod in PIL materialyoucolor; do
        if python -c "import $mod" >/dev/null 2>&1; then
            ok "python: $mod"
        else
            fail "python-Modul $mod fehlt"
            [ "$mod" = PIL ] && missing+=(python-pillow) || missing+=(python-materialyoucolor)
        fi
    done

    # Kuerbare Extras: melden, aber nicht als Fehler zaehlen
    for bin in "${!OPTIONAL[@]}"; do
        if command -v "$bin" >/dev/null 2>&1; then
            ok "$bin"
        else
            warn "$bin fehlt (Paket: ${OPTIONAL[$bin]}) — nur diese Einzelheit faellt aus"
            [ "$INSTALL_DEPS" = 1 ] && missing+=("${OPTIONAL[$bin]}")
        fi
    done

    if [ -n "$(fc-list 2>/dev/null | grep -i "material symbols")" ]; then
        ok "Schrift: Material Symbols"
    else
        warn "Material Symbols nicht gefunden — die Bar zeigt sonst leere Kaestchen"
        missing+=(ttf-material-symbols-variable-git)
    fi

    if [ ${#missing[@]} -gt 0 ] && [ "$INSTALL_DEPS" = 1 ] && [ "$CHECK_ONLY" = 0 ]; then
        local helper=""
        for h in paru yay; do command -v "$h" >/dev/null 2>&1 && { helper="$h"; break; }; done
        if [ -n "$helper" ]; then
            step "Installiere: ${missing[*]}"
            run "$helper" -S --needed "${missing[@]}"
            FAILED=0
        else
            warn "Kein paru/yay gefunden — bitte von Hand: sudo pacman -S ${missing[*]}"
        fi
    elif [ ${#missing[@]} -gt 0 ]; then
        warn "Nachinstallieren mit: ./install.sh --install-deps   (oder pacman -S ${missing[*]})"
    fi
}

# ---------------------------------------------------------- 1b. Dienste ---
# Akku, Energieprofile, Bluetooth und WLAN holt sich die Shell ueber DBus.
# Laeuft der jeweilige Daemon nicht, bleibt die Anzeige einfach leer – das
# sieht man der Shell nicht an, deshalb hier nachsehen.
check_services() {
    step "Systemdienste"

    local unit state
    for unit in "${!SERVICES[@]}"; do
        state="$(systemctl is-active "$unit" 2>/dev/null)"
        case "$state" in
            active)
                ok "$unit (${SERVICES[$unit]})" ;;
            inactive|failed)
                warn "$unit laeuft nicht — ${SERVICES[$unit]} bleibt leer"
                warn "   sudo systemctl enable --now $unit" ;;
            *)
                warn "$unit nicht installiert (Paket: ${SERVICE_PKG[$unit]}) — ${SERVICES[$unit]} entfaellt" ;;
        esac
    done
}

# ------------------------------------------- 1c. Benachrichtigungen ---
# Die Shell IST der Notification-Daemon (Quickshell.Services.Notifications).
# Laeuft schon ein anderer, bekommt der den DBus-Namen und die Glocke in der
# Leiste bleibt stumm.
check_notifications() {
    step "Benachrichtigungen"

    local other=""
    for d in mako dunst swaync fnott; do
        pgrep -x "$d" >/dev/null 2>&1 && other="$d"
    done

    if [ -n "$other" ]; then
        warn "$other laeuft und belegt org.freedesktop.Notifications"
        warn "   Die Shell bringt einen eigenen Daemon mit – $other beenden oder abschalten."
    else
        ok "kein zweiter Daemon im Weg (die Shell bringt einen mit)"
    fi
}

# ------------------------------------------------------------- 2. Links ---
link_files() {
    step "Befehle und Completions verlinken"
    link "$DI_DIR/bin/dynamic-island" "$BIN_DIR/dynamic-island"
    link "$DI_DIR/scripts/hypr-profile" "$BIN_DIR/hypr-profile"
    link "$DI_DIR/scripts/theme-set" "$BIN_DIR/theme-set"
    link "$DI_DIR/completions/dynamic-island.fish" "$CONFIG_DIR/fish/completions/dynamic-island.fish"

    case ":$PATH:" in
        *":$BIN_DIR:"*) ok "~/.local/bin liegt im PATH" ;;
        *) warn "~/.local/bin fehlt im PATH — fish: fish_add_path ~/.local/bin"
           warn "                                bash/zsh: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
}

# ----------------------------------------------------- 3. Verzeichnisse ---
make_dirs() {
    step "Verzeichnisse"
    for d in "$STATE_DIR/$SHELL_NAME/wallpaper" "$STATE_DIR/$SHELL_NAME/record" \
             "$CACHE_DIR/$SHELL_NAME" "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Screenshots"; do
        if [ -d "$d" ]; then
            skip "~${d#$HOME}"
        else
            run mkdir -p "$d"
            [ "$DRY_RUN" = 1 ] || ok "~${d#$HOME} angelegt"
        fi
    done
}

# ---------------------------------------------------- 4b. Wallpaper ---
# Die Bilder aus dem Repo nach ~/Pictures/Wallpapers legen. Kopiert statt
# verlinkt: der Ordner ist eine Sammlung, in die man weitere Bilder wirft –
# ein Symlink auf ein Git-Verzeichnis waere da im Weg. Vorhandenes bleibt
# unangetastet, das Skript ueberschreibt nichts.
seed_wallpapers() {
    step "Wallpaper"

    local src="$REPO_DIR/wallpapers"
    if [ ! -d "$src" ]; then
        skip "keine Bilder im Repo"
        return 0
    fi

    local target="$HOME/Pictures/Wallpapers"
    local copied=0 kept=0 rel
    while IFS= read -r rel; do
        if [ -e "$target/$rel" ]; then
            kept=$((kept + 1))
            continue
        fi
        run mkdir -p "$target/$(dirname "$rel")"
        run cp "$src/$rel" "$target/$rel"
        copied=$((copied + 1))
    done < <(cd "$src" && find . -type f -printf '%P\n' | sort)

    [ "$copied" -gt 0 ] && ok "$copied Bilder nach ~/Pictures/Wallpapers kopiert"
    [ "$kept" -gt 0 ] && skip "$kept schon vorhanden"
    [ "$copied" = 0 ] && [ "$kept" = 0 ] && skip "nichts zu kopieren"
    return 0
}

# ------------------------------------------------- 5. Farbschema setzen ---
seed_scheme() {
    step "Farbschema"

    # Aus dem Schema erzeugte Dateien. Sie liegen bewusst nicht im Repo, weil
    # sie sich bei jedem Theme- und Wallpaperwechsel aendern und sonst dauernd
    # als geaendert im `git status` haengen. Nach einem frischen Clone muessen
    # sie aber da sein: hyprlock bricht mit "source= globbing error: found no
    # match" ab, wenn hypr/scheme/hyprlock.conf fehlt.
    local derived f missing=0
    for f in "$CONFIG_DIR/hypr/scheme/hyprlock.conf" \
             "$CONFIG_DIR/hypr/scheme/current.lua"; do
        [ -s "$f" ] || missing=1
    done

    if [ -s "$STATE_DIR/$SHELL_NAME/scheme.json" ]; then
        if [ "$missing" = 0 ]; then
            skip "scheme.json vorhanden ($("$BIN_DIR/dynamic-island" scheme get -n 2>/dev/null || echo '?'))"
            return 0
        fi
        # Schema ist gesetzt, aber die daraus erzeugten Dateien fehlen.
        # Einmal dasselbe Schema neu anwenden schreibt sie zurueck.
        [ "$DRY_RUN" = 1 ] && { warn "wuerde die erzeugten Farbdateien neu schreiben"; return 0; }
        local name
        name="$("$BIN_DIR/dynamic-island" scheme get -n 2>/dev/null)"
        if [ -n "$name" ] && "$BIN_DIR/dynamic-island" scheme set -n "$name"; then
            ok "Erzeugte Farbdateien neu geschrieben (Schema '$name')"
        else
            warn "Farbdateien fehlen und liessen sich nicht erzeugen"
            warn "  spaeter von Hand: dynamic-island scheme set -n island"
        fi
        return 0
    fi
    [ "$DRY_RUN" = 1 ] && { warn "wuerde ein Schema erzeugen"; return 0; }

    local wp
    # Auch in Unterordnern suchen: die mitgelieferten Bilder liegen in
    # Miku/ und Rimuru/, frueher fand das hier deshalb nichts.
    wp="$(find "$HOME/Pictures/Wallpapers" -type f \
         \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
         2>/dev/null | sort | head -1)"
    if [ -n "$wp" ]; then
        "$BIN_DIR/dynamic-island" wallpaper -f "$wp" && ok "Schema aus $(basename "$wp") erzeugt"
    else
        "$BIN_DIR/dynamic-island" scheme set -n island -m dark && ok "Statisches Schema 'island' gesetzt"
        warn "Keine Wallpaper in ~/Pictures/Wallpapers — spaeter: dynamic-island wallpaper -f BILD"
    fi
}

# ------------------------------------------------------- 6. Hypr-Profil ---
hypr_profile() {
    step "Hyprland-Profil"
    local pf="$CONFIG_DIR/hypr/profile"
    if [ ! -d "$CONFIG_DIR/hypr" ]; then
        fail "~/.config/hypr fehlt — liegt das Repo wirklich unter ~/.config?"
        return 0
    fi
    if [ -f "$pf" ]; then
        skip "aktives Profil: $(cat "$pf")"
    else
        run sh -c "printf simple > '$pf'"
        ok "Profil auf 'simple' gesetzt (= Dynamic Island)"
    fi
    [ -d "$CONFIG_DIR/quickshell/$SHELL_NAME" ] \
        && ok "Shell-Config ~/.config/quickshell/$SHELL_NAME gefunden" \
        || fail "Shell-Config ~/.config/quickshell/$SHELL_NAME fehlt"
}

# --------------------------------------------------- 7. Fish-Sequenzen ---
fish_hook() {
    local cf="$CONFIG_DIR/fish/config.fish"
    step "Terminalfarben (fish)"
    [ -f "$cf" ] || { skip "keine fish-Config"; return 0; }
    if grep -q "state/$SHELL_NAME/sequences.txt" "$cf"; then
        skip "sequences.txt wird schon eingelesen"
    else
        warn "In $cf ergaenzen:  cat ~/.local/state/$SHELL_NAME/sequences.txt 2> /dev/null"
    fi
}

# ------------------------------------------------------------- Abschluss ---
summary() {
    step "Ergebnis"
    if [ "$FAILED" = 1 ]; then
        printf '  %sEs fehlt noch etwas (siehe oben).%s\n' "$c_yellow" "$c_reset"
    else
        printf '  %sAlles eingerichtet.%s\n' "$c_green" "$c_reset"
    fi
    [ "$CHECK_ONLY" = 1 ] && return 0
    cat <<EOF

  Weiter geht es mit:
    hyprctl reload                 Hyprland-Config neu laden
    dynamic-island shell -d        Shell starten
    hypr-profile status            Profil und Shell pruefen
    dynamic-island wallpaper -r    zufaelliges Wallpaper + Farbschema

  In der Shell:
    Einstellungen                  Kreis rechts der Uhr aufklappen -> Regler-Symbol
                                   (oder ">einstellungen" im Launcher)
                                   Legt ~/.config/dynamic-island/shell.json an;
                                   dort laesst sich jedes Leisten-Teil abschalten.
    Wallpaper / Theme              ">wallpaper" bzw. ">theme" im Launcher
    WLAN                           Pfeil auf der Wi-Fi-Kachel

  Profile wechseln:  CTRL + SUPER + SHIFT + P   (oder hypr-profile toggle)

  Wenn die Helligkeit nicht reagiert: sie laeuft ueber DDC/CI, und die
  Bus-Nummern stehen fest in modules/services/brightness/Brightness.qml.
  Welche dieser Rechner hat, sagt "ddcutil detect".
EOF
    if [ "$COPY" = 1 ] && ! same_path "$REPO_DIR" "$CONFIG_DIR"; then
        printf '\n  %sKopiert statt verlinkt: nach einem `git pull` dieses Skript erneut laufen lassen.%s\n' \
            "$c_yellow" "$c_reset"
    fi
}

check_links() {
    step "Befehle und Completions"
    local f short
    for f in "$BIN_DIR/dynamic-island" "$BIN_DIR/hypr-profile" "$BIN_DIR/theme-set" \
             "$CONFIG_DIR/fish/completions/dynamic-island.fish"; do
        short="~${f#$HOME}"
        if [ -e "$f" ]; then ok "$short"; else fail "$short fehlt"; fi
    done
}

ki_warnung

check_deps
check_services
check_notifications
if [ "$CHECK_ONLY" = 1 ]; then check_deploy; else deploy; fi
if [ "$CHECK_ONLY" = 1 ]; then check_links; else link_files; fi
make_dirs
seed_wallpapers
seed_scheme
hypr_profile
fish_hook
summary
exit $FAILED
