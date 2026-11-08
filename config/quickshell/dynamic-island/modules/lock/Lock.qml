pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs
import qs.modules.services.sounds

// Sperrbildschirm der Shell (ext-session-lock). Ersetzt hyprlock, das als
// Rueckfall bleibt: ~/.config/hypr/scripts/lock.sh nimmt hyprlock, wenn die
// Shell nicht laeuft, und SUPER+ALT+L holt es auch dann, wenn die Shell bei
// gesperrter Sitzung abstuerzt (Hyprland: allow_session_lock_restore).
//
// Sperren:   qs -c dynamic-island ipc call lock lock
//            hl.dsp.global("dynamic-island:lock")
// Entsperren geht bewusst nur ueber das Passwort – kein IPC-Befehl dafuer.
//
// Unter der Sperrflaeche zeigt Hyprland nur Schwarz, nie den Desktop. Damit
// Sperren und Entsperren trotzdem ohne Kante ineinander uebergehen, macht
// grim vorher ein Foto jedes Monitors: der Lockscreen beginnt deckungsgleich
// damit und endet auch wieder so. Die Fotos liegen im XDG_RUNTIME_DIR (tmpfs,
// nur fuer den Benutzer lesbar) und werden nach dem Entsperren geloescht.
Scope {
    id: root

    readonly property alias locked: sessionLock.locked
    // Die Oberflaeche spielt gerade ihren Abgang (nach richtigem Passwort)
    property bool leaving: false
    // Monitor, der beim Sperren fokussiert war: dort steht die Medien-Karte
    property string primaryName: ""
    // Monitor, auf dem gerade getippt bzw. der Zeiger ist: nur dort klappt
    // die Notch auf. Der Puffer (LockContext) gilt fuer alle Monitore.
    property string activeName: ""
    // Waehrend grim fotografiert – ein zweites lock() wartet nicht noch einmal
    property bool capturing: false

    readonly property int exitDuration: Math.round(Appearance.morphDuration * 1.4)

    readonly property string snapshotDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/dynamic-island-lock"
    // Monitor-Name -> file://-URL (mit Zeitstempel, das Image cacht sonst)
    property var snapshots: ({})

    function snapshotFor(name: string): string {
        return root.snapshots[name] ?? "";
    }

    function lock(): void {
        if (sessionLock.locked || root.capturing)
            return;
        root.primaryName = Hyprland.focusedMonitor?.name ?? "";
        root.activeName = root.primaryName;
        root.leaving = false;
        context.reset();
        root.capturing = true;
        snapshotProc.running = true;
        snapshotTimeout.restart();
    }

    function engage(ok: bool): void {
        if (!root.capturing)
            return;
        root.capturing = false;
        snapshotTimeout.stop();
        const shots = {};
        if (ok) {
            const stamp = Date.now();
            for (const s of Quickshell.screens)
                shots[s.name] = `file://${root.snapshotDir}/${s.name}.ppm?${stamp}`;
        }
        root.snapshots = shots;
        sessionLock.locked = true;
        Sounds.locked(true);
    }

    // PPM statt PNG: grim muss nichts komprimieren, ~40 ms je Monitor
    Process {
        id: snapshotProc

        command: ["sh", "-c", 'mkdir -p -m 700 "$1" && cd "$1" || exit 1; '
                  + 'for m in $(hyprctl monitors -j | jq -r ".[].name"); do grim -t ppm -o "$m" "$m.ppm" & done; wait',
                  "sh", root.snapshotDir]
        onExited: code => root.engage(code === 0)
    }

    // Haengt grim, wird trotzdem gesperrt – dann eben mit dem Wallpaper
    Timer {
        id: snapshotTimeout

        interval: 700
        onTriggered: {
            snapshotProc.running = false;
            root.engage(false);
        }
    }

    Process {
        id: snapshotClean

        command: ["sh", "-c", 'rm -f "$1"/*.ppm', "sh", root.snapshotDir]
    }

    WlSessionLock {
        id: sessionLock

        LockSurface {
            context: context
            lock: root
        }
    }

    LockContext {
        id: context

        onUnlocked: {
            root.leaving = true;
            leaveDelay.restart();
            Sounds.locked(false);
        }
    }

    // Erst freigeben, wenn der Abgang ganz durch ist: dann zeigt die
    // Sperrflaeche genau das Foto, und darunter liegt derselbe Desktop
    Timer {
        id: leaveDelay

        interval: root.exitDuration + 40
        onTriggered: {
            sessionLock.locked = false;
            root.leaving = false;
            root.snapshots = ({});
            snapshotClean.running = true;
            context.reset();
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock();
        }

        function isLocked(): bool {
            return sessionLock.locked || root.capturing;
        }
    }

    GlobalShortcut {
        appid: "dynamic-island"
        name: "lock"
        description: "Sitzung sperren"

        onPressed: root.lock()
    }
}
