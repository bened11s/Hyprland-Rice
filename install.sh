#!/usr/bin/env bash
# install.sh — richtet den Dynamic-Island-Rice auf diesem Rechner ein.
#
# Laeuft aus einem frischen Klon heraus:
#
#     git clone https://github.com/Gamecat-HD/Hyprland-Rice.git
#     cd Hyprland-Rice
#     ./install.sh
#
# config/ im Repo spiegelt ~/.config. Das Skript verteilt daraus hypr/,
# quickshell/dynamic-island/ und dynamic-island/ nach ~/.config
# (standardmaessig als Symlinks, damit ein `git pull` im Klon durchschlaegt),
# mit --extras auch die optionalen Configs, und richtet danach alles Weitere ein
# (u. a. kitty-Transparenz: config/kitty/dynamic-island.conf + include-Block).
#
# Idempotent: mehrfach ausfuehren schadet nicht.
#
# ACHTUNG: Dieses Skript wurde mit KI erstellt. Vor dem Ausfuehren durchlesen.
#
#   ./install.sh                 einrichten (fragt vorher nach)
#   ./install.sh --copy          Dateien kopieren statt verlinken
#   ./install.sh --extras        auch hyprlock, nvim, spicetify, spotify-launcher
#   ./install.sh --install-deps  fehlende Pakete gleich mitinstallieren
#   ./install.sh --check         nur pruefen, nichts aendern
#   ./install.sh --monitors      nur ~/.config/hypr/monitors.lua neu erzeugen
#   ./install.sh --dry-run       zeigen was passieren wuerde
#   ./install.sh -y              ohne Rueckfrage durchlaufen
set -uo pipefail

# Das Repo ist der Ordner dieses Skripts – egal wohin geklont wurde
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# config/ spiegelt ~/.config
SRC_DIR="$REPO_DIR/config"
DI_DIR="$SRC_DIR/dynamic-island"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
BIN_DIR="$HOME/.local/bin"
BACKUP_DIR="$HOME/backups/dynamic-island-install-$(date +%Y%m%d-%H%M%S)"

SHELL_NAME="dynamic-island"
# Welche Pfade unter ~/.config per --copy aus diesem Repo kamen (einer je Zeile)
COPY_MARKER="$STATE_DIR/$SHELL_NAME/install-copied"
CHECK_ONLY=0
DRY_RUN=0
INSTALL_DEPS=0
ASSUME_YES=0
COPY=0
EXTRAS=0
MONITORS_ONLY=0
FAILED=0
PATH_HINT=0

# Was aus config/ nach ~/.config gehoert (Pfade relativ zu beiden)
DEPLOY_PATHS=(hypr quickshell/dynamic-island dynamic-island)
# Optional (--extras): eigene Configs, die die Notch nicht braucht. Auf einem
# fremden Rechner ersetzen sie dessen nvim/spicetify, darum nicht standardmaessig.
# caelestia/cli.json gehoert nur zum Profil "caelestia".
EXTRA_PATHS=(hyprlock nvim spicetify spotify-launcher.conf caelestia/cli.json)

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
  ./install.sh --extras        auch hyprlock, nvim, spicetify, spotify-launcher
  ./install.sh --install-deps  fehlende Pakete gleich mitinstallieren
  ./install.sh --check         nur pruefen, nichts aendern
  ./install.sh --monitors      nur ~/.config/hypr/monitors.lua neu erzeugen
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
        --extras) EXTRAS=1 ;;
        --monitors) MONITORS_ONLY=1 ;;
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
    - verlinkt hypr/, quickshell/dynamic-island/ und dynamic-island/ aus
      config/ nach ~/.config (mit --copy stattdessen kopieren); was dort im
      Weg liegt, wandert vorher nach ~/backups/
EOF
    [ "$EXTRAS" = 1 ] && printf '    - dazu (--extras): %s\n' "${EXTRA_PATHS[*]}"
    cat <<EOF
    - Symlinks in ~/.local/bin (dynamic-island, hypr-profile, theme-set)
      und in ~/.config/fish/completions
    - baut die Rust-Helfer und legt sie nach ~/.local/bin (nur mit cargo)
    - legt Verzeichnisse an (~/.local/state/$SHELL_NAME, ~/.cache/$SHELL_NAME,
      ~/Pictures/{Wallpapers,Screenshots})
    - kopiert die Wallpaper aus dem Repo nach ~/Pictures/Wallpapers
      (vorhandene Dateien bleiben)
    - erzeugt ein Farbschema, falls keines da ist — das schreibt auch
      Farben nach Hyprland, GTK, Qt, btop, cava und Discord
    - legt ~/.config/hypr/profile an, falls es fehlt
    - schreibt die angeschlossenen Monitore nach ~/.config/hypr/monitors.lua,
      falls es die Datei nicht gibt (nur wenn Hyprland laeuft)
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

backup_copy() {  # backup_copy <pfad> — Stand sichern, das Original bleibt liegen
    local target="$1" rel
    rel="${target#$HOME/}"
    run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    run cp -a "$target" "$BACKUP_DIR/$rel"
    warn "Stand von ~${target#$HOME} gesichert nach ~${BACKUP_DIR#$HOME}/$rel"
}

backup() {  # backup <datei> — echte Datei (kein Symlink) wegsichern
    local target="$1"
    [ -e "$target" ] && [ ! -L "$target" ] || return 0
    run mkdir -p "$BACKUP_DIR"
    run cp -a "$target" "$BACKUP_DIR/"
    warn "$(basename "$target") gesichert nach ~${BACKUP_DIR#$HOME}"
}

copy_tracked() {  # copy_tracked <rel> <ziel> — config/<rel> nach <ziel> kopieren
    # Nur was Git versioniert: Im Klon koennen gitignorte Dateien liegen
    # (eigene shell.json, Build-Ordner rust/target), die sonst die des Ziels
    # ueberschreiben oder es aufblaehen. Ohne Git (z. B. Zip) alles kopieren.
    local rel="$1" dst="$2" f n=0
    if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        run cp -a "$SRC_DIR/$rel/." "$dst/"
        return
    fi
    while IFS= read -r -d '' f; do
        f="${f#config/$rel/}"
        n=$((n + 1))
        [ "$DRY_RUN" = 1 ] && continue
        mkdir -p "$dst/$(dirname "$f")"
        cp -a "$SRC_DIR/$rel/$f" "$dst/$f"
    done < <(git -C "$REPO_DIR" ls-files -z -- "config/$rel")
    [ "$DRY_RUN" = 1 ] && printf '  %s[dry-run]%s %s Dateien aus config/%s nach %s\n' \
        "$c_dim" "$c_reset" "$n" "$rel" "$(short "$dst")"
    return 0
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

    local paths=("${DEPLOY_PATHS[@]}")
    [ "$EXTRAS" = 1 ] && paths+=("${EXTRA_PATHS[@]}")

    local rel src dst
    for rel in "${paths[@]}"; do
        src="$SRC_DIR/$rel"
        dst="$CONFIG_DIR/$rel"

        if [ ! -e "$src" ]; then
            fail "$rel fehlt im Repo ($src)"
            continue
        fi
        if same_path "$dst" "$src"; then
            skip "~${dst#$HOME} zeigt schon auf das Repo"
            continue
        fi

        # Erneuter Lauf mit --copy (z. B. nach einem `git pull`): die fruehere
        # Kopie NICHT wegraeumen, sonst landen die gitignorten Dateien, die erst
        # hier entstanden sind (shell.json, keybinds.json, scenes.json,
        # hypr/profile, hypr/scheme/*), im Backup und die Einstellungen sind
        # scheinbar weg. Stattdessen nur die Repo-Dateien drueberlegen.
        if [ "$COPY" = 1 ] && [ -d "$src" ] && [ -d "$dst" ] && [ ! -L "$dst" ] \
           && grep -qxF "$rel" "$COPY_MARKER" 2>/dev/null; then
            backup_copy "$dst"
            copy_tracked "$rel" "$dst"
            ok "$(short "$dst") aktualisiert (eigene Dateien bleiben)"
            continue
        fi

        # Auch kaputte Symlinks muessen weg, deshalb -L dazu
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            backup_move "$dst"
        fi

        run mkdir -p "$(dirname "$dst")"
        if [ "$COPY" = 1 ]; then
            if [ -d "$src" ]; then
                run mkdir -p "$dst"
                copy_tracked "$rel" "$dst"
            else
                run cp -a "$src" "$dst"
            fi
            ok "$(short "$dst") kopiert"
            # Merken, dass diese Kopie von uns stammt: Nur dann darf ein
            # spaeterer Lauf sie zusammenfuehren statt sie wegzuraeumen. Eine
            # fremde Config wuerde sonst mit dem Repo vermischt.
            if [ "$DRY_RUN" = 0 ] && ! grep -qxF "$rel" "$COPY_MARKER" 2>/dev/null; then
                mkdir -p "$(dirname "$COPY_MARKER")"
                printf '%s\n' "$rel" >> "$COPY_MARKER"
            fi
        else
            run ln -sfn "$src" "$dst"
            ok "$(short "$dst") -> $(short "$src")"
        fi
    done
}

check_deploy() {
    step "Konfiguration unter ~/.config"

    local rel dst
    for rel in "${DEPLOY_PATHS[@]}"; do
        dst="$CONFIG_DIR/$rel"
        if same_path "$dst" "$SRC_DIR/$rel"; then
            ok "~${dst#$HOME} zeigt auf das Repo"
        elif [ -e "$dst" ]; then
            warn "~${dst#$HOME} existiert, kommt aber nicht aus diesem Repo"
        else
            fail "~${dst#$HOME} fehlt"
        fi
    done

    # Optional: nur melden, nie als Fehler werten
    for rel in "${EXTRA_PATHS[@]}"; do
        dst="$CONFIG_DIR/$rel"
        if same_path "$dst" "$SRC_DIR/$rel"; then
            ok "~${dst#$HOME} zeigt auf das Repo (Extra)"
        else
            skip "~${dst#$HOME} nicht aus dem Repo (Extra, --extras)"
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
    # Medien-Karte und Medientasten
    [playerctl]=playerctl
    # Lautstaerketasten (hypr/hyprland/keybinds.lua, Profile)
    [wpctl]=wireplumber
    # Lockscreen-Screenshot (Lock.qml) und hypr/scripts/session-exit.sh
    [jq]=jq
)

# Ohne die laeuft alles weiter, nur eine Einzelheit fehlt.
declare -A OPTIONAL=(
    # Balken im Medien-Player
    [cava]=cava
    # Helligkeit ueber DDC/CI (Brightness.qml). Am Laptop meist unnoetig,
    # dort regelt brightnessctl die interne Anzeige.
    [ddcutil]=ddcutil
    # Helligkeit des internen Laptop-Panels und die Helligkeitstasten
    [brightnessctl]=brightnessctl
    # Audio-Profile (A2DP/HFP) bei Bluetooth-Kopfhoerern
    [pactl]=libpulse
    # Screenshot -> Text erkennen (OCR), braucht dazu tesseract-data-deu/-eng
    [tesseract]=tesseract
    # Die VPN-Kachel kann zwischen NordVPN und Cloudflare WARP wechseln
    [nordvpn]=nordvpn-bin
    [warp-cli]=cloudflare-warp-bin
    # Baut die Rust-Helfer (dynamic-island/rust), ohne cargo laufen die Python-Fassungen
    [cargo]=rust
    # Papierkorb beim Hyprland-Start aufraeumen (aelter als 30 Tage)
    [trash-empty]=trash-cli
    # Mein Terminal; fehlt es, nimmt SUPER + Q das erste andere (hypr/apps.lua)
    [kitty]=kitty
)

# Nur melden, nie per --install-deps mitinstallieren: fremde Dienste mit
# eigenem Konto, die niemand nebenbei auf dem Rechner haben will.
NO_AUTO_INSTALL=(nordvpn warp-cli)

sorted_keys() {  # sorted_keys <name des assoziativen Arrays> — stabile Ausgabe
    local -n _arr="$1"
    printf '%s\n' "${!_arr[@]}" | sort
}

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
    local bin
    for bin in $(sorted_keys NEEDED); do
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
    for bin in $(sorted_keys OPTIONAL); do
        if command -v "$bin" >/dev/null 2>&1; then
            ok "$bin"
        elif [[ " ${NO_AUTO_INSTALL[*]} " == *" $bin "* ]]; then
            skip "$bin fehlt (${OPTIONAL[$bin]}, nur fuer die VPN-Kachel, wird nie automatisch installiert)"
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
    # Voreingestellte Schrift der Shell; fehlt sie, nimmt Qt die Systemschrift.
    if fc-list : family 2>/dev/null | grep -i "Rubik" >/dev/null; then  # kein -q: pipefail + SIGPIPE
        ok "Schrift: Rubik"
    else
        warn "Rubik nicht gefunden — die Shell nimmt sonst die Systemschrift"
        missing+=(ttf-rubik-vf)
    fi

    if [ ${#missing[@]} -gt 0 ] && [ "$INSTALL_DEPS" = 1 ] && [ "$CHECK_ONLY" = 0 ]; then
        local helper=""
        for h in paru yay; do command -v "$h" >/dev/null 2>&1 && { helper="$h"; break; }; done
        if [ -n "$helper" ]; then
            step "Installiere: ${missing[*]}"
            # Nur bei Erfolg gilt das Fehlende als erledigt – ein abgebrochenes
            # paru darf nicht zu "Alles eingerichtet" fuehren
            if run "$helper" -S --needed "${missing[@]}"; then
                FAILED=0
            else
                fail "Paketinstallation gescheitert oder abgebrochen"
            fi
        else
            warn "Kein paru/yay gefunden — bitte von Hand:"
            manual_install_hint "${missing[@]}"
        fi
    elif [ ${#missing[@]} -gt 0 ]; then
        warn "Nachinstallieren mit: ./install.sh --install-deps   (braucht paru/yay), oder:"
        manual_install_hint "${missing[@]}"
    fi
}

# Was pacman selbst kennt, geht per pacman; der Rest (AUR) braucht paru/yay.
# pacman -Si liest nur die lokale Paketdatenbank, das geht auch offline.
manual_install_hint() {
    local repo=() aur=() p
    for p in "$@"; do
        if pacman -Si "$p" >/dev/null 2>&1; then repo+=("$p"); else aur+=("$p"); fi
    done
    [ ${#repo[@]} -gt 0 ] && warn "   sudo pacman -S --needed ${repo[*]}"
    [ ${#aur[@]} -gt 0 ] && warn "   aus dem AUR (paru/yay): ${aur[*]}"
    return 0
}

# ---------------------------------------------------------- 1b. Dienste ---
# Akku, Energieprofile, Bluetooth und WLAN holt sich die Shell ueber DBus.
# Laeuft der jeweilige Daemon nicht, bleibt die Anzeige einfach leer – das
# sieht man der Shell nicht an, deshalb hier nachsehen.
check_services() {
    step "Systemdienste"

    # is-active allein reicht nicht: fuer eine Unit, die es gar nicht gibt,
    # meldet es ebenfalls "inactive". Ob sie installiert ist, sagt LoadState.
    local unit load state
    for unit in "${!SERVICES[@]}"; do
        load="$(systemctl show -p LoadState --value "$unit" 2>/dev/null)"
        state="$(systemctl is-active "$unit" 2>/dev/null)"
        case "$load" in
            loaded) ;;
            masked)
                warn "$unit ist maskiert — ${SERVICES[$unit]} bleibt leer"
                warn "   sudo systemctl unmask $unit && sudo systemctl enable --now $unit"
                continue ;;
            *)
                warn "$unit nicht installiert (Paket: ${SERVICE_PKG[$unit]}) — ${SERVICES[$unit]} entfaellt"
                continue ;;
        esac
        case "$state" in
            active)
                ok "$unit (${SERVICES[$unit]})" ;;
            activating|reloading)
                ok "$unit startet gerade (${SERVICES[$unit]})" ;;
            *)
                warn "$unit laeuft nicht — ${SERVICES[$unit]} bleibt leer"
                warn "   sudo systemctl enable --now $unit" ;;
        esac
    done
}

# ------------------------------------------- 1c. Benachrichtigungen ---
# Die Shell IST der Notification-Daemon (Quickshell.Services.Notifications).
# Laeuft schon ein anderer, bekommt der den DBus-Namen und die Glocke in der
# Leiste bleibt stumm.
check_notifications() {
    step "Benachrichtigungen"

    local other="" d owner=""
    for d in mako dunst swaync fnott; do
        pgrep -x "$d" >/dev/null 2>&1 && other="$d"
    done

    # Entscheidend ist, wer den DBus-Namen haelt – ein nebenher laufender
    # Daemon stoert nicht, solange die Shell den Namen schon hat.
    if command -v busctl >/dev/null 2>&1; then
        owner="$(busctl --user status org.freedesktop.Notifications 2>/dev/null \
                 | sed -n 's/^Comm=//p')"
    fi

    if [ "$owner" = qs ] || [ "$owner" = quickshell ]; then
        ok "die Shell haelt org.freedesktop.Notifications"
        [ -n "$other" ] && skip "$other laeuft nebenher, wird aber nicht gebraucht"
    elif [ -n "$owner" ]; then
        warn "$owner belegt org.freedesktop.Notifications"
        warn "   Die Shell bringt einen eigenen Daemon mit – $owner beenden oder abschalten."
    elif [ -n "$other" ]; then
        warn "$other laeuft und belegt org.freedesktop.Notifications"
        warn "   Die Shell bringt einen eigenen Daemon mit – $other beenden oder abschalten."
    else
        ok "kein zweiter Daemon im Weg (die Shell bringt einen mit)"
    fi
}

# ------------------------------------------------------------- 2. Links ---
link_files() {
    step "Befehle und Completions verlinken"
    # Der Symlink bleibt: Themes.qml findet ueber ihn die Farbschemata (bin/../src)
    if [ -x "$DI_DIR/bin/dynamic-island-rs" ]; then
        link "$DI_DIR/bin/dynamic-island-rs" "$BIN_DIR/dynamic-island"
    else
        link "$DI_DIR/bin/dynamic-island" "$BIN_DIR/dynamic-island"
    fi
    link "$DI_DIR/scripts/hypr-profile" "$BIN_DIR/hypr-profile"
    link "$DI_DIR/scripts/theme-set" "$BIN_DIR/theme-set"
    if command -v fish >/dev/null 2>&1; then
        link "$DI_DIR/completions/dynamic-island.fish" "$CONFIG_DIR/fish/completions/dynamic-island.fish"
    else
        skip "kein fish installiert, keine Completions"
    fi
}

# --------------------------------------------------------- 2b. PATH ---
# Die Befehle liegen in ~/.local/bin. Arch und EndeavourOS nehmen den Ordner
# nicht von selbst in den PATH (CachyOS' fish-Config schon) – ohne das gibt
# es nach der Installation "dynamic-island: command not found". Darum einen
# markierten Block in die rc-Datei jeder vorhandenen Shell; Hyprland selbst
# ergaenzt den PATH in hyprland.lua.
PATH_MARK="# >>> dynamic-island PATH >>>"

path_block() {  # path_block <shell>
    printf '\n%s\n' "$PATH_MARK"
    if [ "$1" = fish ]; then
        printf 'fish_add_path -g ~/.local/bin\n'
    else
        cat <<'EOF'
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
EOF
    fi
    printf '# <<< dynamic-island PATH <<<\n'
}

setup_path() {
    step "PATH"

    # Ziel-Dateien: bash/zsh-rc, wenn es sie gibt oder die Shell die
    # Login-Shell ist (eine neue ~/.zshrc wuerde sonst zsh's Ersteinrichtung
    # unterdruecken); fish ueber conf.d, damit config.fish unangetastet bleibt
    local login="${SHELL##*/}" zshrc="${ZDOTDIR:-$HOME}/.zshrc"
    local -a targets=()
    { [ -f "$HOME/.bashrc" ] || [ "$login" = bash ]; } && targets+=("bash:$HOME/.bashrc")
    { [ -f "$zshrc" ] || [ "$login" = zsh ]; } && targets+=("zsh:$zshrc")
    command -v fish >/dev/null 2>&1 && targets+=("fish:$CONFIG_DIR/fish/conf.d/dynamic-island-path.fish")

    local entry sh rc handled=0
    for entry in "${targets[@]}"; do
        sh="${entry%%:*}"; rc="${entry#*:}"
        if [ -f "$rc" ] && grep -qF "$PATH_MARK" "$rc"; then
            skip "$(short "$rc") setzt den PATH schon"
            handled=1
            continue
        fi
        # Steht ~/.local/bin schon in der rc (eigene Zeile), nichts doppeln
        if [ -f "$rc" ] && grep -qE '(\$HOME|~|'"$HOME"')/\.local/bin' "$rc"; then
            skip "$(short "$rc") nennt ~/.local/bin schon"
            handled=1
            continue
        fi
        if [ "$CHECK_ONLY" = 1 ]; then
            case ":$PATH:" in
                *":$BIN_DIR:"*) ;;
                *) warn "$(short "$rc") nimmt ~/.local/bin nicht in den PATH" ;;
            esac
            continue
        fi
        if [ "$DRY_RUN" = 1 ]; then
            printf '  %s[dry-run]%s ~/.local/bin in %s eintragen\n' "$c_dim" "$c_reset" "$(short "$rc")"
            continue
        fi
        mkdir -p "$(dirname "$rc")"
        path_block "$sh" >> "$rc"
        ok "~/.local/bin in $(short "$rc") eingetragen ($sh)"
        handled=1
    done

    case ":$PATH:" in
        *":$BIN_DIR:"*) ok "~/.local/bin liegt im PATH" ;;
        *) if [ "$handled" = 1 ]; then
               PATH_HINT=1
           elif [ "$DRY_RUN" = 0 ]; then
               warn "~/.local/bin fehlt im PATH, und keine Shell-Config gefunden:"
               warn "   export PATH=\"\$HOME/.local/bin:\$PATH\"  in die rc deiner Shell"
           fi ;;
    esac
}

# --------------------------------------------------------- 2c. kitty ---
# Die Transparenz des Terminals steckt in kitty (background_opacity), nicht in
# Hyprland. Ohne das ist kitty auf einem frischen Rechner voll deckend. Die
# Einstellungen liegen in config/kitty/dynamic-island.conf; kitty.conf selbst
# bleibt die des Rechners und bekommt nur einen markierten include-Block.
KITTY_MARK="# >>> dynamic-island kitty >>>"

kitty_setup() {
    step "kitty (Transparenz)"
    local src="$SRC_DIR/kitty/dynamic-island.conf"
    local dst="$CONFIG_DIR/kitty/dynamic-island.conf"
    local kc="$CONFIG_DIR/kitty/kitty.conf"

    if ! command -v kitty >/dev/null 2>&1 && [ ! -d "$CONFIG_DIR/kitty" ]; then
        skip "kitty nicht installiert"
        return 0
    fi

    local included=0
    [ -f "$kc" ] && grep -qE "^[[:space:]]*include[[:space:]]+(\\./)?dynamic-island\\.conf[[:space:]]*\$" "$kc" \
        && included=1

    if [ "$CHECK_ONLY" = 1 ]; then
        if same_path "$dst" "$src"; then ok "$(short "$dst") zeigt auf das Repo"
        elif [ -f "$dst" ]; then ok "$(short "$dst") (Kopie)"
        else warn "$(short "$dst") fehlt (./install.sh legt sie an)"
        fi
        if [ "$included" = 1 ]; then ok "$(short "$kc") bindet dynamic-island.conf ein"
        else warn "$(short "$kc") bindet dynamic-island.conf nicht ein"
        fi
        return 0
    fi

    if [ "$COPY" = 1 ]; then
        # Ein frueherer Symlink zeigt auf die Quelle selbst – cp wuerde scheitern
        [ -L "$dst" ] && run rm -f "$dst"
        run mkdir -p "$(dirname "$dst")"
        run cp "$src" "$dst"
        ok "$(short "$dst") kopiert"
    else
        link "$src" "$dst"
    fi

    if [ "$included" = 1 ]; then
        skip "$(short "$kc") bindet dynamic-island.conf schon ein"
    elif [ "$DRY_RUN" = 1 ]; then
        printf '  %s[dry-run]%s include dynamic-island.conf an %s anhaengen\n' "$c_dim" "$c_reset" "$(short "$kc")"
    else
        mkdir -p "$(dirname "$kc")"
        printf '\n%s\n# Transparenz der Dynamic-Island-Rice; eigene Werte darunter gewinnen\ninclude dynamic-island.conf\n# <<< dynamic-island kitty <<<\n' \
            "$KITTY_MARK" >> "$kc"
        ok "include dynamic-island.conf in $(short "$kc") eingetragen"
        warn "Offene kitty-Fenster laden das erst nach Strg+Shift+F5 (oder neu starten)"
    fi
}

# ------------------------------------------------------- Rust-Helfer ---
# Fehlt ein Binary, nimmt die Shell die Python-Fassung. Darum ist ein
# gescheiterter Build hier nur eine Warnung.
RUST_HELPERS=(dynamic-island-idle dynamic-island-bluetooth-agent dynamic-island-looks)

build_helpers() {
    step "Rust-Helfer bauen"
    if ! command -v cargo >/dev/null 2>&1; then
        warn "cargo fehlt, die Shell nimmt die Python-Helfer"
        return 0
    fi
    local built="$DI_DIR/rust/target/release"
    if ! run cargo build --release --quiet --manifest-path "$DI_DIR/rust/Cargo.toml" --target-dir "$DI_DIR/rust/target"; then
        warn "Build gescheitert, die Shell nimmt die Python-Helfer"
        return 0
    fi
    local helper
    for helper in "${RUST_HELPERS[@]}"; do
        if run install -Dm755 "$built/$helper" "$BIN_DIR/$helper"; then
            ok "$(short "$BIN_DIR/$helper")"
        else
            warn "$helper nicht installiert, die Shell nimmt die Python-Fassung"
        fi
    done
    # Neben dem Python-Skript: Es uebernimmt alles, was Rust nicht selbst kann. Der
    # Symlink zieht erst um, wenn das Binary wirklich dort liegt.
    if run install -Dm755 "$built/dynamic-island-rs" "$DI_DIR/bin/dynamic-island-rs"; then
        link "$DI_DIR/bin/dynamic-island-rs" "$BIN_DIR/dynamic-island"
    else
        warn "dynamic-island-rs nicht installiert, die CLI bleibt bei Python"
    fi
}

check_helpers() {
    step "Rust-Helfer"
    local helper
    for helper in "${RUST_HELPERS[@]}"; do
        if [ -x "$BIN_DIR/$helper" ]; then
            ok "$(short "$BIN_DIR/$helper")"
        else
            skip "$helper fehlt, die Shell nimmt die Python-Fassung"
        fi
    done
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
        if "$BIN_DIR/dynamic-island" wallpaper -f "$wp"; then
            ok "Schema aus $(basename "$wp") erzeugt"
        else
            warn "Schema aus $(basename "$wp") liess sich nicht erzeugen"
            warn "  spaeter von Hand: dynamic-island wallpaper -f BILD"
        fi
    else
        if "$BIN_DIR/dynamic-island" scheme set -n island -m dark; then
            ok "Statisches Schema 'island' gesetzt"
        else
            warn "Schema 'island' liess sich nicht setzen"
        fi
        warn "Keine Wallpaper in ~/Pictures/Wallpapers — spaeter: dynamic-island wallpaper -f BILD"
    fi
}

# ------------------------------------------------------- 6. Hypr-Profil ---
hypr_profile() {
    step "Hyprland-Profil"
    local pf="$CONFIG_DIR/hypr/profile"
    if [ ! -d "$CONFIG_DIR/hypr" ]; then
        # Bei --dry-run hat deploy() nur angekuendigt, nichts angelegt
        if [ "$DRY_RUN" = 1 ] && [ "$CHECK_ONLY" = 0 ]; then
            skip "wuerde nach dem Verteilen das Profil 'simple' setzen"
        else
            fail "~/.config/hypr fehlt — install.sh ohne --check laufen lassen"
        fi
        return 0
    fi
    if [ -f "$pf" ]; then
        skip "aktives Profil: $(cat "$pf")"
    elif [ "$DRY_RUN" = 1 ]; then
        printf '  %s[dry-run]%s Profil simple nach %s\n' "$c_dim" "$c_reset" "$(short "$pf")"
    else
        printf simple > "$pf"
        ok "Profil auf 'simple' gesetzt (= Dynamic Island)"
    fi
    [ -d "$CONFIG_DIR/quickshell/$SHELL_NAME" ] \
        && ok "Shell-Config ~/.config/quickshell/$SHELL_NAME gefunden" \
        || fail "Shell-Config ~/.config/quickshell/$SHELL_NAME fehlt"
}

# ------------------------------------------------------- 6b. Monitore ---
# Welche Bildschirme ein Rechner hat, steht in hypr/monitors.lua (git-ignoriert,
# Vorlage monitors.example.lua). Laeuft Hyprland gerade, wird sie aus den
# angeschlossenen Monitoren erzeugt: Aufloesung, Position und Skalierung wie
# jetzt, Workspace-Gruppen (1-10, 11-20, ...) von links nach rechts. Ohne die
# Datei laeuft Hyprland mit bevorzugter Aufloesung und Auto-Gruppen weiter.
MONITORS_GEN='
import json, sys
mons = [m for m in json.load(sys.stdin) if m.get("mirrorOf", "none") == "none"]
mons.sort(key=lambda m: (m["x"], m["y"]))
def num(v):
    return str(int(v)) if float(v).is_integer() else ("%.2f" % v).rstrip("0").rstrip(".")
out = ["-- monitors.lua - Bildschirme dieses Rechners (git-ignoriert).",
       "-- Erzeugt von install.sh aus hyprctl monitors; neu: ./install.sh --monitors",
       "-- Felder und Erklaerung: monitors.example.lua", "", "return {"]
for i, m in enumerate(mons):
    r = m["refreshRate"]
    rate = str(round(r)) if abs(r - round(r)) < 0.01 else "%.2f" % r
    out += ["    {",
            "        output     = %s," % json.dumps(m["name"]),
            "        mode       = \"%dx%d@%s\"," % (m["width"], m["height"], rate),
            "        position   = \"%dx%d\"," % (m["x"], m["y"]),
            "        scale      = %s," % num(m["scale"])]
    if m.get("transform"):
        out.append("        transform  = %d," % m["transform"])
    if m.get("vrr"):
        out.append("        vrr        = true,")
    out += ["        workspaces = %d,  -- %d-%d" % (i * 10, i * 10 + 1, i * 10 + 10), "    },"]
out.append("}")
print("\n".join(out))
'

setup_monitors() {  # setup_monitors [force]
    step "Monitore"
    local mf="$CONFIG_DIR/hypr/monitors.lua"

    if [ -f "$mf" ] && [ "${1:-}" != force ]; then
        skip "$(short "$mf") vorhanden (neu erzeugen: ./install.sh --monitors)"
        return 0
    fi
    if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || ! command -v hyprctl >/dev/null 2>&1; then
        skip "Hyprland laeuft nicht — bevorzugte Aufloesung, Workspaces je Monitor automatisch"
        skip "   eigene Datei spaeter, in Hyprland: ./install.sh --monitors"
        return 0
    fi

    local gen
    if ! gen="$(hyprctl monitors -j 2>/dev/null | python -c "$MONITORS_GEN" 2>/dev/null)" \
       || [ -z "$gen" ]; then
        warn "Monitore liessen sich nicht auslesen — Vorlage: config/hypr/monitors.example.lua"
        return 0
    fi

    # Kurzuebersicht: "HDMI-A-1 2560x1440@60 -> Workspaces 1-10"
    local summary
    summary="$(printf '%s\n' "$gen" | sed -nE \
        -e 's/.*output += "([^"]+)".*/\1/p' \
        -e 's/.*mode += "([^"]+)".*/\1/p' \
        -e 's/.*-- ([0-9]+-[0-9]+)$/-> Workspaces \1/p' | paste -d' ' - - -)"

    if [ "$DRY_RUN" = 1 ]; then
        printf '  %s[dry-run]%s %s schreiben:\n' "$c_dim" "$c_reset" "$(short "$mf")"
        printf '%s\n' "$summary" | sed 's/^/      /'
        return 0
    fi
    [ -f "$mf" ] && backup_copy "$mf"
    mkdir -p "$(dirname "$mf")"
    printf '%s\n' "$gen" > "$mf.tmp" && mv "$mf.tmp" "$mf"
    local line
    while IFS= read -r line; do ok "$line"; done <<<"$summary"
    ok "$(short "$mf") geschrieben — wirkt nach: hyprctl reload"
}

# --------------------------------------------------- 7. Fish-Sequenzen ---
fish_hook() {
    step "Terminalfarben"
    local cf found=0
    for cf in "$CONFIG_DIR/fish/config.fish" "$HOME/.bashrc" "${ZDOTDIR:-$HOME}/.zshrc"; do
        [ -f "$cf" ] || continue
        found=1
        if grep -q "state/$SHELL_NAME/sequences.txt" "$cf"; then
            skip "$(short "$cf") liest sequences.txt schon ein"
        else
            warn "Fuer Schema-Farben im Terminal in $(short "$cf") ergaenzen:"
            warn "   cat ~/.local/state/$SHELL_NAME/sequences.txt 2> /dev/null"
        fi
    done
    [ "$found" = 1 ] || skip "keine Shell-Config gefunden"
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
    if [ "$PATH_HINT" = 1 ]; then
        printf '\n  %sDer Befehl dynamic-island geht erst in einem NEUEN Terminal%s\n' "$c_yellow" "$c_reset"
        printf '  %s(oder in diesem nach: source ~/.bashrc  bzw.  exec $SHELL).%s\n' "$c_yellow" "$c_reset"
    fi
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

  Wenn die Helligkeit nicht reagiert: am Laptop laeuft sie ueber
  brightnessctl, an externen Monitoren ueber DDC/CI (ddcutil). Ob deine
  Monitore DDC/CI koennen, sagt "ddcutil detect" (ggf. im OSD einschalten
  und das Modul i2c-dev laden).
EOF
    if [ "$COPY" = 1 ]; then
        printf '\n  %sKopiert statt verlinkt: nach einem `git pull` dieses Skript erneut laufen lassen.%s\n' \
            "$c_yellow" "$c_reset"
    fi
}

check_links() {
    step "Befehle und Completions"
    local f short
    local -a files=("$BIN_DIR/dynamic-island" "$BIN_DIR/hypr-profile" "$BIN_DIR/theme-set")
    command -v fish >/dev/null 2>&1 && files+=("$CONFIG_DIR/fish/completions/dynamic-island.fish")
    for f in "${files[@]}"; do
        short="~${f#$HOME}"
        if [ -e "$f" ]; then ok "$short"; else fail "$short fehlt"; fi
    done
}

if [ "$MONITORS_ONLY" = 1 ]; then
    setup_monitors force
    exit $FAILED
fi

ki_warnung

check_deps
check_services
check_notifications
if [ "$CHECK_ONLY" = 1 ]; then check_deploy; else deploy; fi
if [ "$CHECK_ONLY" = 1 ]; then check_links; else link_files; fi
setup_path
kitty_setup
if [ "$CHECK_ONLY" = 1 ]; then check_helpers; else build_helpers; fi
make_dirs
seed_wallpapers
seed_scheme
hypr_profile
setup_monitors
fish_hook
summary
exit $FAILED
