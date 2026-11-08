pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs

// Verwaltung der Wallpaper-Bibliothek fuer das Einstellungs-Fenster
// (modules/settings/WallpaperManager.qml): Ordner, Verschieben, Papierkorb
// und der Terminal-Look (fastfetch) je Bild oder Ordner.
//
// Die Liste der Bilder selbst bleibt bei Wallpapers (list, thumbFor, set,
// setVariant); hier steht nur, was dazukommt. Alles, was Dateien anfasst,
// macht wallmgr.py – es zieht beim Verschieben auch Szenen, Stil je Bild,
// Looks, Vorschaubilder und das aktuelle Wallpaper mit.
//
// Terminal-Looks: ~/.config/dynamic-island/terminal-looks.tsv, je Zeile
// "<Schluessel>\t<Look>", Schluessel wie in scenes.json ("Ordner/bild.jpg",
// "Ordner/"). Gelesen von fish (functions/__terminal_look.fish); lookFor()
// rechnet hier genauso, damit die Seite zeigt, was das Terminal zeigen wird.
//
// Benutzung:  import qs.modules.services.wallpaper
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("modules/services/wallpaper/wallmgr.py")
    readonly property string looksPath: Quickshell.env("DYNAMIC_ISLAND_LOOKS_FILE")
        || (Quickshell.env("HOME") + "/.config/dynamic-island/terminal-looks.tsv")
    readonly property string wallsDir: Wallpapers.wallsDir

    // [{ id, title, desc, card, cards }] – card = Pfad einer Logo-Karte (leer bei "scheme")
    property var looks: []
    // Unterordner relativ zum Wallpaper-Ordner, auch leere
    property var folders: []
    // { "<Schluessel>": "<Look>" }
    property var assignments: ({})

    // Laeuft gerade eine Operation (oder wartet eine)
    readonly property bool busy: root.queue.length > 0 || root.running
    // Letzte Fehlermeldung, leer nach Erfolg
    property string lastError: ""

    // Nach jeder Operation: op = "move" | "trash" | ..., result = JSON von wallmgr.py
    signal finished(string op, var result)

    // ---- Laden ----
    // Beim Oeffnen der Seite: Bilder (Wallpapers), Ordner, Looks
    function ensureLoaded(): void {
        Wallpapers.ensureLoaded();
        root.run("folders", []);
        root.run("looks", []);
    }

    // ---- Pfade ----
    // "Ordner/bild.jpg" (relativ), leer ausserhalb des Wallpaper-Ordners
    function keyFor(path: string): string {
        const prefix = root.wallsDir + "/";
        return path.startsWith(prefix) ? path.slice(prefix.length) : "";
    }

    // Ordner eines Bilds relativ, "" = oberste Ebene
    function folderOf(path: string): string {
        const key = root.keyFor(path);
        const i = key.lastIndexOf("/");
        return i < 0 ? "" : key.slice(0, i);
    }

    // Schluessel eines Ordners fuer setLook ("Ordner/")
    function folderKey(folder: string): string {
        return folder === "" ? "" : folder + "/";
    }

    // Bilder eines Ordners ("" = alle) aus Wallpapers.list
    function imagesIn(folder: string): var {
        if (folder === "")
            return Wallpapers.list;
        const prefix = folder + "/";
        return Wallpapers.list.filter(w => w.name.startsWith(prefix) && !w.name.slice(prefix.length).includes("/"));
    }

    // ---- Terminal-Looks ----
    function lookInfo(id: string): var {
        return root.looks.find(l => l.id === id) ?? null;
    }

    function exists(look: string): bool {
        return look === "scheme" || look === "miku" || root.looks.some(l => l.id === look);
    }

    // Look nach Ordnernamen (fastfetch/<ordner in klein>), leer = keiner
    function conventionLook(folder: string): string {
        const name = folder.split("/").pop().toLowerCase();
        return name !== "" && root.exists(name) && name !== "scheme" ? name : "";
    }

    // Welcher Look fuer ein Bild gilt und warum – wie __terminal_look.fish
    // im Modus "wallpaper":
    //   source "bild"    feste Zuordnung des Bilds
    //          "ordner"  feste Zuordnung des Ordners
    //          "name"    Ordner heisst wie ein Look
    //          "schema"  nichts davon -> Farbschema
    function lookFor(path: string): var {
        const key = root.keyFor(path);
        const folder = root.folderOf(path);
        const byImage = root.assignments[key];
        if (key !== "" && byImage && root.exists(byImage))
            return { id: byImage, source: "bild" };
        const byFolder = root.assignments[root.folderKey(folder)];
        if (folder !== "" && byFolder && root.exists(byFolder))
            return { id: byFolder, source: "ordner" };
        const named = root.conventionLook(folder);
        if (named !== "")
            return { id: named, source: "name" };
        return { id: "scheme", source: "schema" };
    }

    // Was ein Ordner ohne eigene Zuordnung bekaeme (fuer "Automatisch (…)")
    function folderLookFor(folder: string): var {
        const own = root.assignments[root.folderKey(folder)];
        if (folder !== "" && own && root.exists(own))
            return { id: own, source: "ordner" };
        const named = root.conventionLook(folder);
        return named !== "" ? { id: named, source: "name" } : { id: "scheme", source: "schema" };
    }

    // Feste Zuordnung setzen; look "" nimmt sie zurueck (dann gilt wieder
    // Ordner bzw. Ordnername)
    function setLook(key: string, look: string): void {
        if (key === "")
            return;
        const next = Object.assign({}, root.assignments);
        if (look === "")
            delete next[key];
        else
            next[key] = look;
        root.assignments = next;        // sofort, die Datei zieht gleich nach
        root.run("look", [key, look]);
    }

    // ---- Dateien ----
    function move(path: string, folder: string): void {
        root.run("move", [path, folder]);
    }

    function trash(path: string): void {
        root.run("trash", [path]);
    }

    function makeFolder(name: string): void {
        root.run("mkdir", [name]);
    }

    function renameFolder(from: string, to: string): void {
        root.run("rename-folder", [from, to]);
    }

    // ---- Warteschlange ----
    // Immer nur ein wallmgr.py zur Zeit, der naechste startet erst nach
    // onExited (Process-Neustart im laufenden Lauf meldet sein Ende falsch).
    property var queue: []
    property bool running: false

    function run(op: string, args: var): void {
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

    function handle(op: string, text: string): void {
        let result;
        try {
            result = JSON.parse(text.trim().split("\n").pop());
        } catch (e) {
            result = { ok: false, error: text.trim() || I18n.tr("wallmgr.py ohne Antwort") };
        }

        if (!result.ok) {
            root.lastError = result.error ?? I18n.tr("Fehler");
            // Optimistisch gesetzte Zuordnung zuruecknehmen
            if (op === "look")
                assignFile.reload();
        } else {
            root.lastError = "";
            if (op === "looks")
                root.looks = result.looks ?? [];
            else if (op === "folders")
                root.folders = result.folders ?? [];
            else if (op !== "look") {
                // Etwas hat sich auf der Platte bewegt
                Wallpapers.reload();
                root.run("folders", []);
            }
        }
        root.finished(op, result);
    }

    // Fertig ist ein Lauf erst, wenn stdout zu ist UND der Prozess beendet –
    // in welcher Reihenfolge die beiden Signale kommen, ist nicht fest
    Process {
        id: proc

        property string op: ""
        property string output: ""
        property bool streamDone: false
        property bool exitDone: false

        function complete(): void {
            if (!proc.streamDone || !proc.exitDone)
                return;
            const op = proc.op;
            const text = proc.output;
            proc.output = "";
            proc.streamDone = false;
            proc.exitDone = false;
            root.running = false;
            root.handle(op, text);
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

    // ---- Zuordnungen ----
    function parse(text: string): var {
        const map = {};
        for (const line of text.split("\n")) {
            if (line.startsWith("#"))
                continue;
            const tab = line.indexOf("\t");
            if (tab <= 0)
                continue;
            const look = line.slice(tab + 1).trim();
            if (look !== "")
                map[line.slice(0, tab)] = look;
        }
        return map;
    }

    FileView {
        id: assignFile

        path: root.looksPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.assignments = root.parse(text())
        onLoadFailed: root.assignments = {}
    }
}
