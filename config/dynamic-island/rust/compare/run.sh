#!/usr/bin/env bash
# Vergleicht die Python- und die Rust-Fassung in einer Sandbox ohne Zugriff auf
# Hyprland, Shell, echte D-Bus-Busse, Terminals, fremde Prozesse und Netz.
#
#   compare/run.sh baseline   Python zweimal: Sind die Protokolle stabil?
#   compare/run.sh            Python gegen Rust (vorher: cargo build --release)
#   compare/run.sh fallback   Die echten QML-Befehle, mit und ohne Binary im PATH
#   compare/run.sh plugin     `dynamic-island plugin`, Python gegen Rust
#   compare/run.sh looks      Terminal-Looks, Python gegen Rust
#   compare/run.sh colours    scheme und wallpaper, Python gegen Rust
set -euo pipefail

RUST_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# config/ im Repo (Spiegel von ~/.config): dort liegen quickshell/ und
# dynamic-island/ so, wie die Szenarien sie unter /tmp/work erwarten
REPO="$(cd "$RUST_DIR/../.." && pwd)"
OUT="${COMPARE_OUT:-$RUST_DIR/target/compare}"
mkdir -p "$OUT"

sandbox() {
    bwrap --ro-bind / / --dev /dev --proc /proc --tmpfs /tmp --tmpfs /run --tmpfs "$HOME" \
        --dir "/run/user/$(id -u)" --ro-bind "$REPO" /tmp/work --bind "$OUT" /tmp/out \
        --unshare-all --die-with-parent --new-session \
        --setenv HOME "$HOME" --setenv XDG_RUNTIME_DIR "/run/user/$(id -u)" \
        --unsetenv WAYLAND_DISPLAY --unsetenv DISPLAY --unsetenv DBUS_SESSION_BUS_ADDRESS \
        --unsetenv HYPRLAND_INSTANCE_SIGNATURE --unsetenv XDG_SESSION_ID \
        --setenv COMPARE_STDERR /tmp/out/stderr.log \
        --ro-bind-try "$HOME/.config/fastfetch" /tmp/ff-echt \
        --ro-bind-try "$HOME/Pictures/Wallpapers" /tmp/wall-echt \
        "$@"
}

C=/tmp/work/dynamic-island/rust/compare
IDLE_PY=(python3 -I /tmp/work/quickshell/dynamic-island/modules/services/idle/idlehelper.py)
AGENT_PY=(python3 -I /tmp/work/quickshell/dynamic-island/modules/services/bluetooth/agent.py)
IDLE_RS=(/tmp/work/dynamic-island/rust/target/release/dynamic-island-idle)
AGENT_RS=(/tmp/work/dynamic-island/rust/target/release/dynamic-island-bluetooth-agent)

compare() { # name a b
    if diff -u "$2" "$3" > "$OUT/$1.diff"; then
        echo "GLEICH  $1 ($(wc -l < "$2") Protokollzeilen)"
    else
        echo "ANDERS  $1, siehe $OUT/$1.diff"
        STATUS=1
    fi
}

# Befehl so, wie ihn die QML-Datei startet: sh -c '<skript>' sh <python-skript>
qml_command() { # qml-datei python-skript
    local script
    script="$(python3 -I "$RUST_DIR/compare/qml_script.py" "$1")"
    printf '%s\0' sh -c "$script" sh "$2"
}

CLI_PY=/tmp/work/dynamic-island/bin/dynamic-island
CLI_RS=/tmp/work/dynamic-island/rust/target/release/dynamic-island-rs

LOOKS_PY=(python3 -I /tmp/work/quickshell/dynamic-island/plugins/terminal/looks.py)
LOOKS_RS=(/tmp/work/dynamic-island/rust/target/release/dynamic-island-looks)

STATUS=0
if [ "${1:-}" = colours ]; then
    # Die Kopie in /tmp/cli enthaelt zusaetzlich Test-Schemata
    sandbox python3 -I "$C/colours_scenarios.py" /tmp/out/colours.py /tmp/cli/bin/dynamic-island &
    sandbox python3 -I "$C/colours_scenarios.py" /tmp/out/colours.py2 /tmp/cli/bin/dynamic-island &
    sandbox python3 -I "$C/colours_scenarios.py" /tmp/out/colours.rs "$CLI_RS" &
    wait
    compare colours-baseline "$OUT/colours.py" "$OUT/colours.py2"
    compare colours "$OUT/colours.py" "$OUT/colours.rs"
elif [ "${1:-}" = looks ]; then
    sandbox python3 -I "$C/looks_scenarios.py" /tmp/out/looks.py "${LOOKS_PY[@]}" &
    sandbox python3 -I "$C/looks_scenarios.py" /tmp/out/looks.py2 "${LOOKS_PY[@]}" &
    sandbox python3 -I "$C/looks_scenarios.py" /tmp/out/looks.rs "${LOOKS_RS[@]}" &
    wait
    compare looks-baseline "$OUT/looks.py" "$OUT/looks.py2"
    compare looks "$OUT/looks.py" "$OUT/looks.rs"
elif [ "${1:-}" = plugin ]; then
    sandbox python3 -I "$C/plugin_scenarios.py" /tmp/out/plugin.py "$CLI_PY" "$CLI_PY" &
    sandbox python3 -I "$C/plugin_scenarios.py" /tmp/out/plugin.py2 "$CLI_PY" "$CLI_PY" &
    wait
    sandbox python3 -I "$C/plugin_scenarios.py" /tmp/out/plugin.rs "$CLI_RS" "$CLI_PY" &
    sandbox python3 -I "$C/plugin_scenarios.py" /tmp/out/plugin.rs2 "$CLI_PY" "$CLI_RS" &
    wait
    compare plugin-baseline "$OUT/plugin.py" "$OUT/plugin.py2"
    compare plugin "$OUT/plugin.py" "$OUT/plugin.rs"
    compare plugin-rust-pakete "$OUT/plugin.py" "$OUT/plugin.rs2"
elif [ "${1:-}" = fallback ]; then
    Q=quickshell/dynamic-island/modules/services
    mapfile -d '' IDLE_QML < <(qml_command "$REPO/$Q/idle/Idle.qml" "/tmp/work/$Q/idle/idlehelper.py")
    mapfile -d '' AGENT_QML < <(qml_command "$REPO/$Q/bluetooth/BluetoothService.qml" "/tmp/work/$Q/bluetooth/agent.py")
    WITH=(--setenv PATH "/tmp/work/dynamic-island/rust/target/release:/usr/bin")
    WITHOUT=(--setenv PATH /usr/bin)
    echo "mit Binary:  $(sandbox "${WITH[@]}" sh -c 'command -v dynamic-island-idle dynamic-island-bluetooth-agent | wc -l') von 2 gefunden"
    echo "ohne Binary: $(sandbox "${WITHOUT[@]}" sh -c 'command -v dynamic-island-idle dynamic-island-bluetooth-agent | wc -l') von 2 gefunden"
    sandbox "${WITH[@]}" python3 -I "$C/idle_scenarios.py" /tmp/out/idle.with "${IDLE_QML[@]}" &
    sandbox "${WITH[@]}" python3 -I "$C/agent_scenarios.py" /tmp/out/agent.with "${AGENT_QML[@]}" &
    wait
    sandbox "${WITHOUT[@]}" python3 -I "$C/idle_scenarios.py" /tmp/out/idle.without "${IDLE_QML[@]}" &
    sandbox "${WITHOUT[@]}" python3 -I "$C/agent_scenarios.py" /tmp/out/agent.without "${AGENT_QML[@]}" &
    wait
    sandbox python3 -I "$C/idle_scenarios.py" /tmp/out/idle.py "${IDLE_PY[@]}" &
    sandbox python3 -I "$C/agent_scenarios.py" /tmp/out/agent.py "${AGENT_PY[@]}" &
    wait
    T=quickshell/dynamic-island/plugins/terminal
    mapfile -d '' LOOKS_QML < <(qml_command "$REPO/$T/Main.qml" "/tmp/work/$T/looks.py")
    W=(--setenv COMPARE_ONLY get_save)
    sandbox "${W[@]}" "${WITH[@]}" python3 -I "$C/looks_scenarios.py" /tmp/out/looks.with "${LOOKS_QML[@]}" &
    sandbox "${W[@]}" "${WITHOUT[@]}" python3 -I "$C/looks_scenarios.py" /tmp/out/looks.without "${LOOKS_QML[@]}" &
    sandbox "${W[@]}" python3 -I "$C/looks_scenarios.py" /tmp/out/looks.only "${LOOKS_PY[@]}" &
    wait
    compare looks-qml-mit-binary "$OUT/looks.only" "$OUT/looks.with"
    compare looks-qml-ohne-binary "$OUT/looks.only" "$OUT/looks.without"
    compare idle-qml-mit-binary "$OUT/idle.py" "$OUT/idle.with"
    compare agent-qml-mit-binary "$OUT/agent.py" "$OUT/agent.with"
    compare idle-qml-ohne-binary "$OUT/idle.py" "$OUT/idle.without"
    compare agent-qml-ohne-binary "$OUT/agent.py" "$OUT/agent.without"
elif [ "${1:-}" = baseline ]; then
    sandbox python3 -I "$C/idle_scenarios.py" /tmp/out/idle.py.1 "${IDLE_PY[@]}" &
    sandbox python3 -I "$C/agent_scenarios.py" /tmp/out/agent.py.1 "${AGENT_PY[@]}" &
    wait
    sandbox python3 -I "$C/idle_scenarios.py" /tmp/out/idle.py.2 "${IDLE_PY[@]}" &
    sandbox python3 -I "$C/agent_scenarios.py" /tmp/out/agent.py.2 "${AGENT_PY[@]}" &
    wait
    compare idle-baseline "$OUT/idle.py.1" "$OUT/idle.py.2"
    compare agent-baseline "$OUT/agent.py.1" "$OUT/agent.py.2"
else
    sandbox python3 -I "$C/idle_scenarios.py" /tmp/out/idle.py "${IDLE_PY[@]}" &
    sandbox python3 -I "$C/agent_scenarios.py" /tmp/out/agent.py "${AGENT_PY[@]}" &
    wait
    sandbox python3 -I "$C/idle_scenarios.py" /tmp/out/idle.rs "${IDLE_RS[@]}" &
    sandbox python3 -I "$C/agent_scenarios.py" /tmp/out/agent.rs "${AGENT_RS[@]}" &
    wait
    compare idle "$OUT/idle.py" "$OUT/idle.rs"
    compare agent "$OUT/agent.py" "$OUT/agent.rs"
fi
exit "$STATUS"
