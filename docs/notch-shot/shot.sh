#!/bin/bash
# Rendert die Notch offscreen (bwrap wie settings-shot/shot.sh).
#   shot.sh <zustand> <ausgabe.png> [breite hoehe]
#   Zustaende: collapsed, overview, media, control, notifications, system,
#              power, apps, clipboard, keys
#              plugin:<id> (Notch-Ansicht), wallpaper:<id> (Sektion der Wallpaper-Auswahl)
#   Umgebung: SRC, OUT, DELAY, LOG wie bei settings-shot; PRE = Befehl vor
#             dem Start in der Sandbox (z. B. shell.json im Wegwerf-HOME ändern).
# Grenzen: wie settings-shot; ohne D-Bus/MPRIS/Hyprland fehlen Musik, Akkus,
# Workspaces und Benachrichtigungen.
# Masken/Schatten zeichnet der Software-Renderer nicht (Bildvorschauen leer),
# Git-Status der Shell meldet "Kein Git-Repo"/kein Netz. Der Lauf scheitert
# ab und zu ohne Bild – dann einfach wiederholen.
# NIE die qs-Zeile ausserhalb der Sandbox starten: der Harness beendet sich
# per `pkill -x qs` und wuerde sonst die laufende Shell mitnehmen.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${SRC:-$HERE/../../config/quickshell/dynamic-island}
OUT=${OUT:-$PWD/shots}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/notch-shot.XXXXXX")
mkdir -p "$OUT" "$WORK/bin"
trap 'rm -rf "$WORK"' EXIT

rsync -a --exclude .qmlls.ini "$SRC/" "$WORK/copy/"
cp "$HERE/harness.qml" "$WORK/copy/shell.qml"
# hyprctl-Attrappe mit echten Monitordaten (nur lesend geholt)
hyprctl monitors all -j > "$WORK/bin/monitors.json" 2>/dev/null || echo '[]' > "$WORK/bin/monitors.json"
cat > "$WORK/bin/hyprctl" <<EOF
#!/bin/sh
case "\$*" in *monitors*) cat "$WORK/bin/monitors.json" ;; *-j*) echo '[]' ;; *) echo ok ;; esac
EOF
chmod +x "$WORK/bin/hyprctl"

for try in 1 2 3; do
    rm -f "$OUT/$2"
    bwrap --ro-bind / / --dev-bind /dev /dev --proc /proc --tmpfs /tmp \
        --overlay-src "$HOME" --tmp-overlay "$HOME" --bind "$WORK" "$WORK" --bind "$OUT" "$OUT" \
        --tmpfs /run --dir /run/user/"$(id -u)" --unshare-pid --unshare-net --die-with-parent \
        --setenv XDG_RUNTIME_DIR /run/user/"$(id -u)" --unsetenv WAYLAND_DISPLAY --unsetenv DISPLAY \
        --unsetenv DBUS_SESSION_BUS_ADDRESS --unsetenv HYPRLAND_INSTANCE_SIGNATURE \
        --setenv PATH "$WORK/bin:/usr/bin" --setenv QT_QPA_PLATFORM offscreen --setenv QT_QUICK_BACKEND software \
        --setenv STATE "$1" --setenv OUT "$OUT/$2" --setenv DELAY "${DELAY:-6000}" \
        --setenv W "${3:-900}" --setenv H "${4:-520}" \
        bash -c "${PRE:-true}; timeout 25 qs -p '$WORK/copy' --no-color 2>&1 | grep -v i18n | tail -${LOG:-0}"
    [ -f "$OUT/$2" ] && { echo "$OUT/$2"; exit 0; }
done
echo "kein Bild: $2" >&2
exit 1
