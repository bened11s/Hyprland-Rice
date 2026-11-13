#!/bin/sh
# shellupdate.sh <repo> <log> — die Shell (dieses Repo) aktualisieren
#
# Schritte: `git pull --ff-only`, danach – nur wenn der Pull die Dateien
# beruehrt hat – Rust-Helfer bauen (wie install.sh build_helpers) und
# `hyprctl reload`, zum Schluss die Shell so neu starten, wie es die CLI
# tut (`dynamic-island shell -k`, kurz warten, `dynamic-island shell -d`).
#
# Laeuft abgekoppelt von der Shell (Quickshell.execDetached, ShellUpdate.qml):
# der Pull aendert QML-Dateien, Quickshell laedt daraufhin neu und beendet
# dabei seine Kindprozesse – ein Process im QML stuerbe mitten im Pull.
# Fortschritt und Fehler landen deshalb in der Logdatei, die die Shell
# beobachtet. ShellUpdate.qml liest dieses Skript vorher komplett in den
# Speicher, weil der Pull auch diese Datei ueberschreiben kann.
#
# Kein autostash, kein reset (eigene Commits: Rebase, bei Konflikt
# abgebrochen). Wer uncommittete Aenderungen hat, bekommt den
# Fehlertext von git zu sehen (E-Zeilen) und sichert sie selbst (README,
# "Updating").
#
# Zeilen im Log, je eine pro Ereignis:
#   START <epoch>            Beginn
#   STEP pull|build|hypr|restart
#   E <text>                 Ausgabe von git/cargo (mehrzeilig, eine E-Zeile je Zeile)
#   WARN build               Helfer-Build gescheitert, die alten bleiben
#   FAIL pull                Pull abgebrochen, Grund in den E-Zeilen
#   PULLED <alt> <neu> <n>   n Commits uebernommen
#   DONE <neu>               fertig, die Shell startet gleich neu

repo="$1"
log="$2"
if [ -z "$repo" ] || [ -z "$log" ]; then
    echo "usage: shellupdate.sh <repo> <log>" >&2
    exit 64
fi

mkdir -p "$(dirname "$log")"
: > "$log"

say() { printf '%s\n' "$*" >> "$log"; }
dump() { printf '%s\n' "$1" | sed 's/^/E /' >> "$log"; }

# git darf nie nach einem Passwort fragen – es gibt kein Terminal
export GIT_TERMINAL_PROMPT=0

say "START $(date +%s)"

if ! cd "$repo" 2>/dev/null; then
    say "E $repo: Verzeichnis nicht gefunden"
    say "FAIL pull"
    exit 1
fi

# ---- 1. Pull -------------------------------------------------------------
say "STEP pull"
old=$(git rev-parse HEAD 2>/dev/null)
# Eigene Commits vor dem Upstream: ff-only ginge nie mehr, also die eigenen
# Commits per Rebase obendrauf legen. Geht das schief (Konflikt), wird der
# Rebase abgebrochen – der Stand ist danach wie vorher.
ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
if [ "$ahead" -gt 0 ]; then
    if ! out=$(git pull --rebase --no-autostash 2>&1); then
        git rebase --abort >/dev/null 2>&1
        dump "$out"
        say "FAIL pull"
        exit 1
    fi
elif ! out=$(git pull --ff-only 2>&1); then
    dump "$out"
    say "FAIL pull"
    exit 1
fi
new=$(git rev-parse HEAD)
n=$(git rev-list --count "$old..$new" 2>/dev/null || echo 0)
say "PULLED $old $new $n"

changed=$(git diff --name-only "$old" "$new")

# ---- 2. Rust-Helfer, falls ihre Quellen dabei waren --------------------
# Wie install.sh (build_helpers): Binaries nach ~/.local/bin, die CLI
# nach config/dynamic-island/bin. Ohne cargo bleibt alles beim Alten –
# die Shell nimmt dann die Python-Fassungen.
if printf '%s\n' "$changed" | grep -q '^config/dynamic-island/rust/'; then
    say "STEP build"
    di="$repo/config/dynamic-island"
    bin="$HOME/.local/bin"
    if ! command -v cargo >/dev/null 2>&1; then
        say "E cargo fehlt – ./install.sh baut die Helfer, sobald es da ist"
        say "WARN build"
    elif out=$(cargo build --release --quiet --manifest-path "$di/rust/Cargo.toml" --target-dir "$di/rust/target" 2>&1); then
        built="$di/rust/target/release"
        for h in dynamic-island-idle dynamic-island-bluetooth-agent dynamic-island-looks; do
            [ -x "$built/$h" ] && install -Dm755 "$built/$h" "$bin/$h"
        done
        [ -x "$built/dynamic-island-rs" ] && install -Dm755 "$built/dynamic-island-rs" "$di/bin/dynamic-island-rs"
    else
        dump "$(printf '%s\n' "$out" | tail -n 15)"
        say "WARN build"
    fi
fi

# ---- 3. Hyprland, falls seine Config dabei war --------------------------
if printf '%s\n' "$changed" | grep -q '^config/hypr/'; then
    say "STEP hypr"
    hyprctl reload >/dev/null 2>&1 || say "E hyprctl reload fehlgeschlagen"
fi

# ---- 4. Shell neu starten ------------------------------------------------
say "STEP restart"
cli="$HOME/.local/bin/dynamic-island"
[ -x "$cli" ] || cli=dynamic-island
# DONE vor dem Neustart: die neue Shell liest das Protokoll beim Start
say "DONE $new"
sleep 1
"$cli" shell -k >/dev/null 2>&1
sleep 1.5
exec "$cli" shell -d
