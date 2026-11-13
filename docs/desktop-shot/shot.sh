#!/bin/bash
# Rendert die Bearbeitungs-Oberflaeche der Desktop-Widgets (EditBar,
# WidgetOptions, WidgetPicker – siehe harness.qml) offscreen, ohne den Desktop
# zu beruehren: bwrap-Sandbox mit eigenem PID-Namespace, $HOME als
# Wegwerf-Overlay, kein Wayland/Hyprland/D-Bus, Software-Renderer.
# Gleiches Muster wie docs/settings-shot/shot.sh.
#
#   shot.sh <ausgabe.png> [breite hoehe]
#   Umgebung: SRC  Shell-Ordner (Vorgabe: der aus diesem Repo)
#             CONFIRM=1 zeigt die Loesch-Rueckfragen
#             DELAY ms bis zum Bild (Vorgabe 6000), LOG Zeilen Log (Vorgabe 0)
#
# Grenzen: Popups (Dropdown/⋮) fehlen im Bild (Overlay-Ebene). Der Lauf
# scheitert ab und zu ohne Bild – dann einfach wiederholen.
# NIE die qs-Zeile ausserhalb der Sandbox starten: der Harness beendet sich
# per `pkill -x qs` und wuerde sonst die laufende Shell mitnehmen.
set -u
[ $# -ge 1 ] || { echo "shot.sh <ausgabe.png> [breite hoehe]" >&2; exit 2; }
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${SRC:-$HERE/../../config/quickshell/dynamic-island}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/desktop-shot.XXXXXX") || exit 1
mkdir -p "$WORK/bin" "$(dirname "$1")"
trap 'rm -rf "$WORK"' EXIT

rsync -a --exclude .qmlls.ini "$SRC/" "$WORK/copy/"
cp "$HERE/harness.qml" "$WORK/copy/shell.qml"
# Offscreen gibt es kein PanelWindow: ohne die Ebene laedt das Plugin `desktop`
# trotzdem und meldet seine Widget-Typen (Uhr, Visualiser, Songtext)
sed -i '/^    Desktop {}$/d' "$WORK/copy/plugins/desktop/Main.qml"
# hyprctl-Attrappe mit echten Monitordaten (nur lesend geholt)
hyprctl monitors all -j > "$WORK/bin/monitors.json" 2>/dev/null || echo '[]' > "$WORK/bin/monitors.json"
cat > "$WORK/bin/hyprctl" <<EOF
#!/bin/sh
case "\$*" in *monitors*) cat "$WORK/bin/monitors.json" ;; *-j*) echo '[]' ;; *) echo ok ;; esac
EOF
chmod +x "$WORK/bin/hyprctl"

for try in 1 2 3; do
    bwrap --ro-bind / / --dev-bind /dev /dev --proc /proc --tmpfs /tmp \
        --overlay-src "$HOME" --tmp-overlay "$HOME" --bind "$WORK" "$WORK" \
        --tmpfs /run --dir /run/user/"$(id -u)" --unshare-pid --unshare-net --die-with-parent \
        --setenv XDG_RUNTIME_DIR /run/user/"$(id -u)" --unsetenv WAYLAND_DISPLAY --unsetenv DISPLAY \
        --unsetenv DBUS_SESSION_BUS_ADDRESS --unsetenv HYPRLAND_INSTANCE_SIGNATURE \
        --setenv PATH "$WORK/bin:/usr/bin" --setenv QT_QPA_PLATFORM offscreen --setenv QT_QUICK_BACKEND software \
        --setenv OUT "$WORK/out.png" --setenv DELAY "${DELAY:-6000}" --setenv CONFIRM "${CONFIRM:-0}" \
        --setenv W "${2:-1500}" --setenv H "${3:-900}" \
        bash -c "timeout 25 qs -p '$WORK/copy' --no-color 2>&1 | grep -v i18n | tail -${LOG:-0}"
    [ -f "$WORK/out.png" ] && { mv "$WORK/out.png" "$1"; echo "$1"; exit 0; }
done
echo "kein Bild: $1" >&2
exit 1
