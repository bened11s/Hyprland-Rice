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

    // Haelt den Schlaf wach: solange dieser Prozess laeuft, haelt er einen
    // logind-Inhibitor gegen idle/suspend
    Process {
        id: inhibitProc

        command: ["systemd-inhibit", "--what=idle:sleep", "--who=dynamic-island",
                  "--mode=block", "sleep", "infinity"]
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
