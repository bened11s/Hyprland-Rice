pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs.modules.services.config
import qs.modules.services.media
import qs.modules.services.system

// Inaktivitaet: abdunkeln -> sperren -> Bildschirme aus -> (optional) Ruhezustand.
// Ersetzt hypridle im simple-Profil (hyprland.lua startet es dort nicht).
//
// Gesperrt wird ueber hypr/scripts/lock.sh (Shell-Lock, sonst hyprlock), auch
// vor dem Ruhezustand und bei `loginctl lock-session`. idlehelper.py haelt den
// D-Bus-Namen org.freedesktop.ScreenSaver (Browser/Player melden dort laufende
// Videos) und die logind-Verzoegerung, damit vor dem Schlafen gesperrt ist.
//
// Nichts passiert, solange
//   - ein Programm per ScreenSaver.Inhibit oder Wayland-Idle-Inhibitor bremst,
//   - Medien laufen (idle.media),
//   - ein Fenster im Vollbild laeuft (idle.fullscreen) – Spiele mit Joystick
//     erzeugen keine Wayland-Aktivitaet und melden selten ein Inhibit,
//   - "No Sleep" in den Schnelleinstellungen an ist.
//
// Die Abdunkel-Flaeche zeigt modules/idle/IdleDim.qml an `dim` (0..1).
//
// Benutzung:  import qs.modules.services.idle
Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("modules/services/idle/idlehelper.py")
    readonly property string lockScript: Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh"

    readonly property bool enabled: Config.idle.enabled
    // [{ app, reason }] von ScreenSaver.Inhibit
    property var inhibitors: []
    // Der Helfer hat den D-Bus-Namen (sonst laeuft noch hypridle)
    property bool owned: false

    readonly property bool mediaBlocks: !!Config.idle.media && Media.playing
    readonly property bool fullscreenBlocks: (Config.idle.fullscreen ?? true)
        && Hyprland.monitors.values.some(m => m.activeWorkspace?.hasFullscreen ?? false)
    readonly property bool blocked: root.inhibitors.length > 0 || root.mediaBlocks || root.fullscreenBlocks
                                    || SessionModes.noSleep
    readonly property bool watching: root.enabled && !root.blocked

    // Warnphase vor dem Sperren
    property bool warning: false
    // 0..1 fuer IdleDim
    readonly property real dim: root.warning ? 1 : 0
    readonly property int warnSeconds: Math.max(0, Config.idle.warnSeconds)
    property bool screensOff: false

    function lock(): void {
        root.warning = false;
        Quickshell.execDetached([root.lockScript]);
    }

    function setScreens(on: bool): void {
        if (root.screensOff === !on)
            return;
        root.screensOff = !on;
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.dpms({action = "${on ? "on" : "off"}"})`]);
    }

    // ---- Stufen ----
    // Warnung: lockMinutes minus warnSeconds, danach sperrt der Timer
    IdleMonitor {
        id: warnMonitor
        enabled: root.watching && Config.idle.lockMinutes > 0
        respectInhibitors: true
        timeout: Math.max(5, Config.idle.lockMinutes * 60 - root.warnSeconds)
        onIsIdleChanged: {
            if (isIdle) {
                root.warning = root.warnSeconds > 0;
                lockTimer.restart();
            } else {
                root.warning = false;
                lockTimer.stop();
            }
        }
    }

    Timer {
        id: lockTimer
        interval: root.warnSeconds * 1000
        onTriggered: root.lock()
    }

    IdleMonitor {
        enabled: root.watching && Config.idle.screenOffMinutes > 0
        respectInhibitors: true
        timeout: Config.idle.screenOffMinutes * 60
        onIsIdleChanged: root.setScreens(!isIdle)
    }

    IdleMonitor {
        enabled: root.watching && Config.idle.suspendMinutes > 0
        respectInhibitors: true
        timeout: Config.idle.suspendMinutes * 60
        onIsIdleChanged: if (isIdle) Quickshell.execDetached(["systemctl", "suspend"])
    }

    // Wird die Ueberwachung abgeschaltet (Video startet), Warnung zuruecknehmen
    onWatchingChanged: if (!root.watching) {
        root.warning = false;
        lockTimer.stop();
        root.setScreens(true);
    }

    // ---- Vor dem Ruhezustand ----
    // Nach dem Sperren nachsehen, ob die Sperre steht, und dann den Schlaf
    // freigeben (der Helfer gibt nach 3 s ohnehin frei)
    property int lockPolls: 0

    function lockForSleep(): void {
        root.lock();
        root.lockPolls = 0;
        lockPoll.restart();
    }

    Timer {
        id: lockPoll
        interval: 150
        onTriggered: lockCheck.running = true
    }

    Process {
        id: lockCheck
        command: ["qs", "-c", "dynamic-island", "ipc", "call", "lock", "isLocked"]
        stdout: StdioCollector { id: lockOut }
        onExited: {
            // Fremde Sperre (hyprlock-Rueckfall): lockCheck sagt false, dann
            // reicht die Wartezeit des Helfers
            if (lockOut.text.trim() === "true" || ++root.lockPolls > 15)
                helperProc.write("locked\n");
            else
                lockPoll.restart();
        }
    }

    // ---- Helfer ----
    Process {
        id: helperProc
        command: ["python3", "-I", root.helper]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                if (line === "ready") {
                    root.owned = true;
                    helperProc.write(Config.idle.lockOnSleep ? "sleep-lock on\n" : "sleep-lock off\n");
                } else if (line === "taken") {
                    root.owned = false;
                } else if (line.startsWith("inhibitors ")) {
                    try {
                        root.inhibitors = JSON.parse(line.slice(11));
                    } catch (e) {
                        root.inhibitors = [];
                    }
                } else if (line === "sleep") {
                    if (Config.idle.lockOnSleep)
                        root.lockForSleep();
                } else if (line === "wake") {
                    root.setScreens(true);
                } else if (line === "lock") {
                    root.lock();
                }
            }
        }
        onExited: {
            root.owned = false;
            root.inhibitors = [];
            if (root.enabled)
                restart.restart();
        }
    }

    Timer {
        id: restart
        interval: 10000
        onTriggered: root.syncHelper()
    }

    // Nicht als Binding: nach einem Absturz setzt der Neustart-Timer running
    function syncHelper(): void {
        helperProc.running = root.enabled;
    }

    onEnabledChanged: root.syncHelper()
    Component.onCompleted: root.syncHelper()

    // `qs -c dynamic-island ipc call idle status` – wer gerade bremst
    IpcHandler {
        target: "idle"

        function status(): string {
            return JSON.stringify({
                enabled: root.enabled,
                owned: root.owned,
                watching: root.watching,
                warning: root.warning,
                media: root.mediaBlocks,
                fullscreen: root.fullscreenBlocks,
                noSleep: SessionModes.noSleep,
                inhibitors: root.inhibitors
            });
        }
    }

    Connections {
        target: Config.idle
        function onLockOnSleepChanged(): void {
            if (helperProc.running)
                helperProc.write(Config.idle.lockOnSleep ? "sleep-lock on\n" : "sleep-lock off\n");
        }
    }
}
