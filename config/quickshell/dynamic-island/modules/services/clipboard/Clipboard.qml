pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.services.core

// Zwischenablage-Verlauf fuer den Launcher-Modus "clipboard" (SUPER+V).
// Gespeichert wird weiter von cliphist (wl-paste --watch im Autostart),
// hier wird nur gelesen und zurueckkopiert. Alles mit Dateien macht
// cliphelper.py, eine Operation zur Zeit (wie WallManager).
//
// Angeheftetes (pins) ist eine eigene Kopie ausserhalb von cliphist und
// ueberlebt "Verlauf leeren".
//
// Benutzung:  import qs.modules.services.clipboard
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("modules/services/clipboard/cliphelper.py")

    // Solange jemand die Liste zeigt, beobachtet wl-paste die Ablage und
    // laedt bei Aenderungen nach.
    readonly property Demand demand: Demand {}

    // [{ id, kind: "text"|"image", text, pinned, thumb?, fmt?, size?, w?, h? }] neueste zuerst
    property var entries: []
    // [{ key, kind, text, added, path? }] zuletzt angeheftet zuerst
    property var pins: []
    // { "<id>": "<pfad>" } fertige Vorschaubilder
    property var thumbs: ({})
    property bool loaded: false
    property string lastError: ""

    // Nach copy/copyPin, damit die Oberflaeche schliessen kann
    signal copied

    function refresh(): void {
        root.run("list", []);
    }

    // Vorschaubild anfordern; mehrere Aufrufe im selben Frame gehen gesammelt raus
    function requestThumb(id: string): void {
        if (root.thumbs[id] || root.thumbWanted.includes(id))
            return;
        root.thumbWanted = root.thumbWanted.concat([id]);
        thumbBatch.restart();
    }

    function thumbFor(id: string): string {
        return root.thumbs[id] ?? "";
    }

    function copy(id: string): void {
        root.run("copy", [id]);
    }

    function copyPin(key: string): void {
        root.run("copy-pin", [key]);
    }

    function remove(id: string): void {
        root.entries = root.entries.filter(e => e.id !== id);   // sofort, Datei zieht nach
        root.run("delete", [id]);
    }

    function wipe(): void {
        root.entries = [];
        root.thumbs = {};
        root.run("wipe", []);
    }

    function togglePin(id: string): void {
        root.run("pin", [id]);
    }

    function unpin(key: string): void {
        root.pins = root.pins.filter(p => p.key !== key);
        root.run("unpin", [key]);
    }

    // Ganzer Text eines Eintrags (die Liste kennt nur die erste Zeile);
    // callback(text, truncated)
    function fullText(id: string, callback: var): void {
        root.callbacks[id] = callback;
        root.run("full", [id]);
    }

    // ---- intern ----
    property var callbacks: ({})
    property var thumbWanted: []
    property var queue: []
    property bool running: false

    function run(op: string, args: var): void {
        // Doppelte "list" in der Warteschlange zusammenfassen
        if (op === "list" && root.queue.some(j => j.op === "list"))
            return;
        root.queue = root.queue.concat([{ op, args }]);
        if (!root.running)
            root.next();
    }

    function next(): void {
        if (root.queue.length === 0)
            return;
        const job = root.queue[0];
        root.queue = root.queue.slice(1);
        proc.op = job.op;
        proc.command = ["python3", "-I", root.script, job.op].concat(job.args);
        root.running = true;
        proc.running = true;
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text.trim().split("\n").pop());
        } catch (e) {
            return { ok: false, error: text.trim() || "cliphelper.py" };
        }
    }

    function handle(op: string, text: string): void {
        const r = root.parse(text);
        if (!r.ok) {
            root.lastError = r.error ?? "";
            console.warn("clipboard:", op, root.lastError);
            if (op === "delete" || op === "unpin")
                root.refresh();
            return;
        }
        root.lastError = "";
        if (op === "list") {
            root.entries = r.entries ?? [];
            root.pins = r.pins ?? [];
            const known = {};
            for (const e of root.entries)
                if (e.thumb)
                    known[e.id] = e.thumb;
            root.thumbs = Object.assign(known, root.thumbs);
            root.loaded = true;
        } else if (op === "full") {
            const cb = root.callbacks[r.id];
            delete root.callbacks[r.id];
            if (cb)
                cb(r.text, r.truncated);
        } else if (op === "copy" || op === "copy-pin") {
            root.copied();
        } else if (op === "pin") {
            root.refresh();
        }
    }

    Process {
        id: proc
        property string op: ""
        stdout: StdioCollector { id: out }
        onExited: {
            root.handle(proc.op, out.text);
            root.running = false;
            root.next();
        }
    }

    Timer {
        id: thumbBatch
        interval: 30
        onTriggered: {
            if (root.thumbWanted.length === 0 || thumbProc.running)
                return;
            thumbProc.ids = root.thumbWanted.slice(0, 12);
            root.thumbWanted = root.thumbWanted.slice(12);
            thumbProc.command = ["python3", "-I", root.script, "thumbs"].concat(thumbProc.ids);
            thumbProc.running = true;
        }
    }

    // Eigener Prozess, damit das Dekodieren grosser Bilder die Liste nicht aufhaelt
    Process {
        id: thumbProc
        property var ids: []
        stdout: StdioCollector { id: thumbOut }
        onExited: {
            const r = root.parse(thumbOut.text);
            if (r.ok)
                root.thumbs = Object.assign({}, root.thumbs, r.thumbs);
            if (root.thumbWanted.length > 0)
                thumbBatch.restart();
        }
    }

    // Ablage beobachten, solange die Liste offen ist. Jede Aenderung schreibt
    // eine Zeile; kurz sammeln, cliphist speichert parallel.
    Process {
        running: root.demand.active
        command: ["wl-paste", "--watch", "echo", "x"]
        stdout: SplitParser {
            onRead: changed.restart()
        }
    }

    Timer {
        id: changed
        interval: 250
        onTriggered: root.refresh()
    }

    // Beim Oeffnen frisch laden
    Connections {
        target: root.demand
        function onActiveChanged(): void {
            if (root.demand.active)
                root.refresh();
        }
    }
}
