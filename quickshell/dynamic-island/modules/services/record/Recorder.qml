pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

// Bildschirmaufnahme. Die Arbeit macht die CLI (`dynamic-island record`):
// sie startet gpu-screen-recorder auf dem fokussierten Monitor und schiebt
// den fertigen Clip beim Stoppen nach ~/Videos/Recordings.
//
// Ob gerade aufgenommen wird, steht hier nicht als selbst gesetztes Flag,
// sondern wird am laufenden Recorder-Prozess abgelesen. So taucht auch eine
// Aufnahme in der Leiste auf, die per Tastenkürzel oder Terminal gestartet
// wurde – und ein abgestürzter Recorder lässt den Punkt nicht ewig leuchten.
//
// Benutzung:  import qs.modules.services.record
Singleton {
    id: root

    // Absolut statt nur "dynamic-island" – dieselbe Begründung wie in
    // Wallpapers.qml: execDetached erbt die PATH der Session, und die ist
    // beim Start der Shell nicht garantiert dieselbe wie im Terminal.
    readonly property string cli: Quickshell.env("HOME") + "/.local/bin/dynamic-island"
    readonly property string recorder: "gpu-screen-recorder"

    // Ton der Standard-Ausgabe mitschneiden. Der Schalter sitzt auf der
    // Kachel und gilt ab der nächsten Aufnahme (laufende ändert er nicht).
    property bool sound: true

    // Nur einen Ausschnitt aufnehmen statt des ganzen Monitors. Den Rahmen
    // zieht slurp auf, sobald die Aufnahme startet – zwei Modi (Vollbild /
    // Bereich, je mit und ohne Ton). Gilt wie `sound` erst ab der nächsten Aufnahme.
    property bool region: false

    property bool active: false
    // Laufzeit für die Kachel. Startpunkt ist der Moment, in dem die Shell
    // den Recorder sieht – nach einem Shell-Neustart mitten in der Aufnahme
    // zählt sie also ab da, nicht ab dem echten Start.
    property double startedAt: 0
    property int elapsed: 0

    readonly property string elapsedLabel: {
        const total = Math.max(0, root.elapsed);
        const m = Math.floor(total / 60);
        const s = total % 60;
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }

    // Ein Aufruf für beides: die CLI stoppt selbst, wenn schon eine Aufnahme
    // läuft. Die Schalter dürfen nur beim Start mit – beim Stoppen versteht
    // die CLI sie falsch.
    function toggle(): void {
        const args = [root.cli, "record"];
        if (!root.active) {
            // `--region` ohne Wert heißt in der CLI: Rahmen mit slurp ziehen
            if (root.region)
                args.push("--region");
            if (root.sound)
                args.push("--sound");
        }
        Quickshell.execDetached(args);
        settle.restart();
    }

    // Aufnahme eines fertigen Ausschnitts (aus dem Screenshot-Overlay),
    // geometry = "BxH+X+Y" in globalen logischen Koordinaten
    function startRegion(geometry: string): void {
        if (root.active)
            return;
        const args = [root.cli, "record", "--region", geometry];
        if (root.sound)
            args.push("--sound");
        Quickshell.execDetached(args);
        settle.restart();
    }

    function refresh(): void {
        if (!pidProc.running)
            pidProc.running = true;
    }

    onActiveChanged: {
        root.startedAt = active ? Date.now() : 0;
        root.elapsed = 0;
    }

    Process {
        id: pidProc

        command: ["pidof", root.recorder]
        onExited: code => root.active = code === 0
    }

    // Die CLI schreibt während der Aufnahme nach record/recording.mp4 und
    // schiebt die Datei beim Stoppen weg. Jede Änderung im Ordner (inotify,
    // kein Polling) stößt das engmaschige Nachsehen an – so springt der
    // Punkt auch bei Starts per Tastenkürzel oder Terminal sofort um.
    FolderListModel {
        folder: "file://" + Quickshell.env("HOME") + "/.local/state/dynamic-island/record"
        nameFilters: ["recording.mp4"]
        showDirs: false
        onCountChanged: settle.restart()
    }

    // Ruhiger Grundtakt – nur noch Rückfallebene für Recorder, die ganz an
    // der CLI vorbei gestartet wurden, und für einen abgestürzten Recorder.
    // Vorher alle 2 s: ~30 pidof-Starts pro Minute, dauerhaft; dann 10 s.
    // Starts ueber die CLI meldet ohnehin der FolderListModel oben.
    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Nach einem Klick ein paar Sekunden engmaschig nachsehen: Start und
    // Stopp brauchen jeweils einen Moment (der Stopp wartet sogar auf das
    // saubere Ende der Datei), der Punkt an der Uhr soll trotzdem zügig
    // umspringen statt erst beim nächsten Grundtakt.
    Timer {
        id: settle

        interval: 200
        repeat: true
        triggeredOnStart: true

        property int ticks: 0

        onRunningChanged: if (running) ticks = 0
        onTriggered: {
            root.refresh();
            if (++ticks >= 30)   // ~6 s
                settle.stop();
        }
    }

    // Laufzeit-Zähler
    Timer {
        interval: 1000
        running: root.active
        repeat: true
        onTriggered: root.elapsed = Math.floor((Date.now() - root.startedAt) / 1000)
    }
}
