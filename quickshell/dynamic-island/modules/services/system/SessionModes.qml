pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// No-Sleep und Game-Mode – ein Zustand fuer die ganze Shell.
//
// Lagen frueher in jeder Kachel-Instanz (SettingsTiles): die gibt es je
// Monitor und Einbauort, Pille und Steuerungs-Untermenue zeigten also
// verschiedene Zustaende und konnten mehrere Inhibitoren starten.
//
//   - No-Sleep: ein systemd-inhibit-Prozess (logind-Lock), der waehrend der
//     Aktivitaet am Leben gehalten wird
//   - Game-Mode: hyprctl eval 'hl.config{...}' (keyword ist im Lua-Parser
//     tot), Rueckweg ueber hyprctl reload
Singleton {
    id: root

    property bool gameMode: false
    property bool noSleep: false

    // Gewaehlte Dauer in Sekunden; -1 = nichts gewaehlt (Standard),
    // 0 = unbegrenzt. sleepRemaining ist die Restlaufzeit in Sekunden.
    property int sleepDurationSec: -1
    property int sleepRemaining: 0

    function toggleNoSleep(): void {
        root.noSleep = !root.noSleep;
        if (root.noSleep) {
            root.sleepRemaining = Math.max(0, root.sleepDurationSec);
            inhibitProc.running = true;
        } else {
            root.sleepRemaining = 0;
            inhibitProc.running = false;
        }
        root.saveState();
    }

    function pickDuration(sec: int): void {
        root.sleepDurationSec = sec;
        if (!root.noSleep) {
            root.noSleep = true;   // Auswahl aktiviert direkt mit
            root.sleepRemaining = Math.max(0, sec);
            inhibitProc.running = true;
        } else if (sec > 0) {
            root.sleepRemaining = sec;   // laufende Session umstellen
        }
        root.saveState();
    }

    function toggleGameMode(): void {
        root.gameMode = !root.gameMode;
        if (root.gameMode) {
            // Je ein eigener Aufruf: ein einzelner Process liess die zweite
            // und dritte Zeile fallen, solange die erste noch lief
            root.hyprEval('hl.config({ animations = { enabled = false } })');
            root.hyprEval('hl.config({ decoration = { shadow = { enabled = false } } })');
            root.hyprEval('hl.config({ decoration = { blur = { enabled = false } } })');
        } else {
            // Reload setzt alles aus dem Profil zurueck
            Quickshell.execDetached(["hyprctl", "reload"]);
        }
    }

    function hyprEval(code: string): void {
        Quickshell.execDetached(["hyprctl", "eval", code]);
    }

    // Altinhibitoren beseitigen, bevor der Zustand wiederhergestellt wird
    Component.onCompleted: cleanupProc.running = true

    // Haelt den Schlaf wach: solange dieser Prozess laeuft, haelt er einen
    // logind-Inhibitor gegen idle/suspend
    Process {
        id: inhibitProc

        command: ["systemd-inhibit", "--what=idle:sleep", "--who=dynamic-island",
                  "--mode=block", "sleep", "infinity"]
    }

    // ---- Zustand merken ----
    //
    // Die Shell laedt bei jeder Aenderung an einer QML-Datei neu. Ohne diese
    // Datei waere No Sleep danach wieder aus - und mit ihm der Inhibitor, der
    // den Bildschirm wach haelt. Der Bildschirm sperrt also genau dann, wenn
    // man die Shell angefasst hat. Deshalb liegt der Zustand daneben:
    //
    //     ~/.local/state/dynamic-island/session.json
    readonly property string statePath: Quickshell.env("HOME")
        + "/.local/state/dynamic-island/session.json"

    FileView {
        id: stateFile

        path: root.statePath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: {
            root.stateLoaded = true;
            root.applyState();
        }
        // Beim ersten Start gibt es die Datei noch nicht -> anlegen
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                stateFile.writeAdapter();
        }

        adapter: JsonAdapter {
            id: stateAdapter

            property bool noSleep: false
            // -1 = nichts gewaehlt, 0 = unendlich, sonst Sekunden
            property int duration: -1
        }
    }

    // Beim Start hängen alte Inhibitoren noch herum: der Prozess stirbt mit
    // der Shell nicht (er wird nicht beendet, nur die Shell). Die haetten
    // den Bildschirm weiter wach gehalten, obwohl No Sleep aus ist.
    Process {
        id: cleanupProc

        command: ["sh", "-c", "pkill -f 'systemd-inhibit .*--who=dynamic-island' 2>/dev/null; true"]
        onExited: {
            root.cleanupDone = true;
            root.applyState();
        }
    }

    property bool stateLoaded: false
    property bool cleanupDone: false

    function saveState(): void {
        stateAdapter.noSleep = root.noSleep;
        stateAdapter.duration = root.sleepDurationSec;
        stateFile.writeAdapter();
    }

    // Zustand anwenden – erst wenn Datei gelesen und Altinhibitoren
    // beseitigt sind, sonst gaenge der gemerkte Zustand verloren.
    function applyState(): void {
        if (!root.stateLoaded || !root.cleanupDone)
            return;
        root.sleepDurationSec = stateAdapter.duration;
        root.noSleep = stateAdapter.noSleep;
        root.sleepRemaining = Math.max(0, root.sleepDurationSec);
        if (root.noSleep)
            inhibitProc.running = true;
        else
            inhibitProc.running = false;
    }

    // Zustand von aussen pruefen und schalten (IPC):
    //     qs -c dynamic-island ipc call nosleep state
    //     qs -c dynamic-island ipc call nosleep toggle
    IpcHandler {
        target: "nosleep"

        function toggle(): void {
            root.toggleNoSleep();
        }

        function state(): string {
            return JSON.stringify({ noSleep: root.noSleep, duration: root.sleepDurationSec,
                remaining: root.sleepRemaining, procRunning: inhibitProc.running });
        }
    }

    // Countdown: bei Ablauf No-Sleep sauber abschalten (ohne Dauer keiner)
    Timer {
        interval: 1000
        running: root.noSleep && root.sleepDurationSec > 0
        repeat: true
        onTriggered: {
            root.sleepRemaining = root.sleepRemaining - 1;
            if (root.sleepRemaining <= 0) {
                root.noSleep = false;
                inhibitProc.running = false;
            }
        }
    }
}
