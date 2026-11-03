pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

import qs

// Zustand des Sperrbildschirms – einer fuer alle Monitore, damit es egal
// ist, auf welchem man tippt: Puffer, Phase, Meldung.
//
// Phasen:
//   idle      gesperrt, nichts getippt
//   typing    Puffer nicht leer
//   checking  PAM prueft gerade
//   failed    falsch – Notch schuettelt sich, nach ein paar Sekunden idle
//   success   richtig – die Oberflaeche spielt ihren Abgang, dann `unlocked`
//
// PAM laeuft ueber /etc/pam.d/hyprlock (-> login -> system-auth): dieselbe
// Pruefung wie hyprlock, inklusive faillock.
Scope {
    id: root

    property string buffer: ""
    property string phase: "idle"
    // Text unter den Punkten: Fehler, faillock-Sperre, PAM-Rueckfragen
    property string message: ""
    property bool capsLock: false
    // Fehlversuche seit dem Sperren (nur Anzeige, die Grenze zieht faillock)
    property int failures: 0
    // Zaehlt hoch bei jedem Fehlschlag – die Notch schuettelt sich daran
    property int shakes: 0

    readonly property bool busy: root.phase === "checking" || root.phase === "success"

    // Die Oberflaeche hat ihren Abgang gespielt -> Lock.qml gibt frei
    signal unlocked

    function reset(): void {
        pam.abort();
        root.buffer = "";
        root.phase = "idle";
        root.message = "";
        root.failures = 0;
        failReset.stop();
        root.refreshCapsLock();
    }

    function handleKey(event: var): void {
        if (root.busy)
            return;

        const key = event.key;
        if (key === Qt.Key_CapsLock) {
            capsDelay.restart();
            return;
        }
        if (key === Qt.Key_Enter || key === Qt.Key_Return) {
            root.submit();
            return;
        }
        if (key === Qt.Key_Escape) {
            root.clear();
            return;
        }
        if (key === Qt.Key_Backspace) {
            root.buffer = event.modifiers & Qt.ControlModifier ? "" : root.buffer.slice(0, -1);
        } else if (event.text && /^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            root.buffer += event.text;
        } else {
            return;
        }
        failReset.stop();
        root.message = "";
        root.phase = root.buffer.length > 0 ? "typing" : "idle";
    }

    function clear(): void {
        if (root.busy)
            return;
        root.buffer = "";
        root.message = "";
        root.phase = "idle";
    }

    function submit(): void {
        if (root.busy || root.buffer.length === 0)
            return;
        root.phase = "checking";
        root.message = "";
        if (!pam.start()) {
            root.fail(I18n.tr("Anmeldung nicht möglich"));
        }
    }

    function fail(text: string): void {
        root.buffer = "";
        root.phase = "failed";
        root.message = text;
        root.failures++;
        root.shakes++;
        failReset.restart();
    }

    function refreshCapsLock(): void {
        capsProc.running = false;
        capsProc.running = true;
    }

    PamContext {
        id: pam

        config: "hyprlock"

        onResponseRequiredChanged: {
            if (!responseRequired)
                return;
            respond(root.buffer);
            root.buffer = "";
        }

        // faillock meldet sich mit "The account is locked due to N failed
        // logins" (bzw. lokalisiert) – das soll stehen, statt "Falsches
        // Passwort". Die Rueckfrage selbst ("Passwort: ") ist keine Meldung.
        property string lastMessage: ""
        onMessageChanged: lastMessage = message

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.phase = "success";
                root.message = "";
                successDelay.restart();
                return;
            }
            const locked = /locked|gesperrt/i.test(pam.lastMessage);
            root.fail(locked ? I18n.tr("Zu viele Fehlversuche – kurz warten")
                    : result === PamResult.MaxTries ? I18n.tr("Zu viele Versuche")
                    : result === PamResult.Error ? I18n.tr("Anmeldefehler")
                    : I18n.tr("Falsches Passwort"));
            pam.lastMessage = "";
        }

        onError: error => {
            console.warn("lock: PAM-Fehler", PamError.toString(error));
        }
    }

    // Kurz "entsperrt" zeigen (Schloss offen, Akzentfarbe), dann abgehen
    Timer {
        id: successDelay

        interval: 260
        onTriggered: root.unlocked()
    }

    Timer {
        id: failReset

        interval: 3200
        onTriggered: if (root.phase === "failed") {
            root.phase = "idle";
            root.message = "";
        }
    }

    // ---- Feststelltaste ----
    // Quickshell kennt den Zustand der Tastatur-LEDs nicht, Hyprland schon:
    // die Haupttastatur in `hyprctl devices -j`. Gefragt wird nur beim
    // Sperren und nach einem Druck auf die Feststelltaste selbst.
    Timer {
        id: capsDelay

        interval: 60
        onTriggered: root.refreshCapsLock()
    }

    Process {
        id: capsProc

        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const boards = JSON.parse(text).keyboards ?? [];
                    const main = boards.find(k => k.main) ?? boards[0];
                    root.capsLock = !!main?.capsLock;
                } catch (e) {
                    root.capsLock = false;
                }
            }
        }
    }
}
