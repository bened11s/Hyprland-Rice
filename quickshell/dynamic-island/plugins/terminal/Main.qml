pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs

// Welchen Look das Terminal zeigt: Starship-Prompt und fastfetch.
// (Frueher modules/services/system/TerminalTheme.qml, jetzt ein Plugin.)
//
// Einstellungen (plugin.json, im Menue unter "Terminal-Looks"):
//   theme         an = Farben des aktuellen Schemas, aus = immer Vocaloid-Look
//   folderLooks   an = Wallpaper-Ordner mit eigenem Look (~/.config/fastfetch/<ordner>/,
//                 Miku direkt in ~/.config/fastfetch) zeigt diesen statt des Schemas;
//                 feste Looks je Bild/Ordner (terminal-looks.tsv) setzt die
//                 Wallpaper-Bibliothek in den Einstellungen (WallManager.qml)
//
// Entschieden wird in fish (functions/__terminal_look.fish, genutzt von
// fastfetch.fish und conf.d/terminal-theme.fish), bei jedem Aufruf bzw.
// Prompt. fish liest kein JSON, darum schreibt das Plugin den Stand als ein
// Wort in eine Modus-Datei (Plugin aus = "miku", siehe onDisable):
//   "wallpaper"  Ordner-Look des Wallpapers, sonst Schema (Standard, auch ohne Datei)
//   "theme"      immer Schema
//   "miku"       immer Vocaloid-Look
//
// Dazu der Dienst fuer den Looks-Editor (LooksPage.qml, erreichbar ueber
// `plugin.main`): call(op, args, cb) startet looks.py (Operationen siehe
// dort) und ruft cb(result) mit dessen JSON-Zeile ({ok, error, ...}).
// Ein Prozess zur Zeit; eine wartende Vorschau wird durch eine neuere ersetzt.
QtObject {
    id: root

    required property var plugin

    readonly property string modePath: Quickshell.env("HOME") + "/.local/state/dynamic-island/terminal-mode"
    readonly property string mode: !root.plugin.settings.theme ? "miku"
                                   : root.plugin.settings.folderLooks ? "wallpaper" : "theme"

    readonly property var labels: ({ wallpaper: I18n.tr("Wallpaper-Ordner"), theme: I18n.tr("Farbschema"), miku: "Vocaloid" })

    // Im Launcher unter ">" – schaltet zwischen den drei Modi durch
    readonly property var actions: [
        {
            name: I18n.tr("Terminal-Look wechseln"),
            desc: I18n.tr("Jetzt: %1").arg(root.labels[root.mode]),
            keepOpen: true,
            run: () => root.cycle()
        }
    ]

    function cycle(): void {
        // wallpaper -> theme -> miku -> wallpaper
        if (root.mode === "wallpaper")
            root.plugin.set("folderLooks", false);
        else if (root.mode === "theme")
            root.plugin.set("theme", false);
        else {
            root.plugin.set("theme", true);
            root.plugin.set("folderLooks", true);
        }
    }

    // qs -c dynamic-island ipc call plugins call terminal mode|cycle|looks ""
    function ipc(cmd: string, arg: string): string {
        if (cmd === "mode")
            return root.mode;
        if (cmd === "cycle") {
            root.cycle();
            return "ok";
        }
        // Stand der Look-Liste (laedt neu; zweiter Aufruf zeigt das Ergebnis)
        if (cmd === "looks") {
            root.refresh();
            return root.looks.map(l => `${l.id}${l.managed ? "" : " (ohne look.json)"}`).join("\n") || "(noch leer)";
        }
        return "unbekannt: mode | cycle | looks";
    }

    function write(): void {
        if (modeFile.text().trim() !== root.mode)
            modeFile.setText(root.mode + "\n");
    }

    onModeChanged: write()

    // Plugin aus = Funktion aus: fester Vocaloid-Look statt Wechsel je
    // Wallpaper. Ohne das bliebe die Datei auf dem letzten Stand stehen und
    // fish wechselte weiter. Per sh, weil das Objekt gleich danach zerstoert
    // wird (ein FileView-Schreiben koennte dabei verloren gehen).
    function onDisable(): void {
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" > "$2"', "sh", "miku", root.modePath]);
    }

    property FileView modeFile: FileView {
        path: root.modePath
        printErrors: false
        blockLoading: true
        // Fehlt die Datei (erster Start), trotzdem schreiben
        onLoaded: root.write()
        onLoadFailed: root.write()
    }

    // ---- Looks-Editor ----------------------------------------------------------

    readonly property string script: root.plugin.dir + "/looks.py"
    // Liste aus `looks.py list` (id, title, palette, cards, card, raw, managed)
    property var looks: []
    property bool busy: false
    property string lastError: ""
    // Ein Look wurde gespeichert/angelegt/geloescht (fuer Listen, die mitziehen)
    signal changed(string id)

    property var queue: []

    // Die Liste holt erst der Editor (refresh()), danach jede Aenderung
    function refresh(): void {
        root.call("list", [], r => {
            if (r.ok)
                root.looks = r.looks ?? [];
        });
    }

    function call(op: string, args: var, cb: var): void {
        const job = { op: op, args: args ?? [], cb: cb ?? null };
        // Vorschau: nur die neueste zaehlt
        if (op === "preview")
            root.queue = root.queue.filter(j => j.op !== "preview" || j.args[0] !== job.args[0]);
        root.queue = root.queue.concat([job]);
        if (!root.busy)
            root.next();
    }

    // Bequeme Huellen (look = Objekt aus `get`, wird als JSON uebergeben)
    function get(id: string, cb: var): void {
        root.call("get", [id], cb);
    }
    function save(id: string, look: var, force: bool, cb: var): void {
        root.call("save", [id, "--json", JSON.stringify(look)].concat(force ? ["--force"] : []), cb);
    }
    function preview(look: var, size: string, cb: var): void {
        root.call("preview", [size, "--json", JSON.stringify(look)], cb);
    }

    function next(): void {
        // busy: ein call() aus einem Rueckruf hat schon den naechsten
        // gestartet, bevor das callLater aus complete() hier ankommt
        if (root.busy || root.queue.length === 0)
            return;
        const job = root.queue[0];
        root.queue = root.queue.slice(1);
        proc.job = job;
        proc.command = ["python3", "-I", root.script, job.op].concat(job.args);
        root.busy = true;
        proc.running = true;
    }

    function handle(job: var, text: string): void {
        let result;
        try {
            result = JSON.parse(text.trim().split("\n").pop());
        } catch (e) {
            result = { ok: false, error: text.trim() || I18n.tr("looks.py ohne Antwort") };
        }
        if (job.op !== "preview")
            root.lastError = result.ok ? "" : (result.error ?? I18n.tr("Fehler"));
        if (job.cb) {
            try {
                job.cb(result);
            } catch (e) {
                console.warn(`[terminal] ${job.op}: ${e}`);
            }
        }
        const writes = ["save", "import", "new", "delete", "card-make", "card-remove", "raw-set", "raw-off"];
        if (result.ok && writes.includes(job.op)) {
            root.changed(job.args[0] ?? "");
            root.refresh();
        }
    }

    // Fertig erst, wenn stdout zu ist UND der Prozess beendet (Reihenfolge
    // der beiden Signale ist nicht fest, wie in WallManager.qml)
    property Process proc: Process {
        id: proc

        property var job: null
        property string output: ""
        property bool streamDone: false
        property bool exitDone: false

        function complete(): void {
            if (!proc.streamDone || !proc.exitDone)
                return;
            const job = proc.job;
            const text = proc.output;
            proc.output = "";
            proc.streamDone = false;
            proc.exitDone = false;
            root.busy = false;
            root.handle(job, text);
            Qt.callLater(root.next);
        }

        stdout: StdioCollector {
            onStreamFinished: {
                proc.output = text;
                proc.streamDone = true;
                proc.complete();
            }
        }

        onExited: {
            proc.exitDone = true;
            proc.complete();
        }
    }
}
