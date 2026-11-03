pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.launcher
import qs.modules.services.wallpaper

import qs

// Dienst des Plugins: Wallhaven-Suche fuer die Wallpaper-Auswahl – Treffer,
// Seiten, Downloads. (Frueher modules/services/wallpaper/Wallhaven.qml.)
//
// Die Arbeit macht wallhaven.py im Plugin-Ordner (python3 -I, nur Stdlib),
// es liefert NDJSON auf stdout – erst die Trefferliste, dann je fertigem
// Vorschaubild eine Zeile (die Kacheln stehen also sofort mit Platzhaltern
// da). Hier wird nur gesammelt und in ein ListModel geschrieben: ein
// JS-Array als Modell wuerde bei jedem nachgereichten Thumb alle Kacheln neu
// bauen und das Karussell auf Null stellen.
//
// Die Oberflaeche ist Section.qml (Manifest panels.wallpaper) und entsteht
// nur, solange die Sektion aufgeklappt ist – hier liegt, was das Zuklappen
// ueberleben soll: Suchtext, Treffer, ein laufender Download. Keine Timer;
// Prozesse laufen nur waehrend einer Anfrage.
//
// Die API erlaubt 45 Anfragen pro Minute: eine laufende Suche wird beim
// neuen Start abgebrochen, die naechste Seite kommt erst, wenn die vorige
// samt Thumbs durch ist, und mehr als `maxPages` Seiten gibt es je Suche
// nicht. Entprellt wird in der Sektion (Tipp-Pause), nicht hier.
Scope {
    id: root

    required property var plugin

    readonly property string script: root.plugin.url("wallhaven.py")
    // Dieselben Orte wie in wallhaven.py
    readonly property string thumbsDir: root.plugin.cachePath("thumbs")

    // Mehr Seiten als das laedt das Karussell nicht nach (24 Treffer je Seite)
    readonly property int maxPages: 6

    // Die laufende Suche: Suchtext und Sortierung (API-Wert), dazu die Meta-
    // Daten der letzten Antwort. `seed` haelt die Zufallsreihenfolge ueber
    // die Seiten hinweg zusammen.
    property string query: ""
    property int page: 0
    property int lastPage: 0
    property int total: 0
    property string seed: ""
    property string error: ""

    // Phasen eines Aufrufs: `searching` bis die Trefferliste da ist (dann
    // lohnt eine Statusanzeige), `busy` solange der Prozess noch Thumbs
    // nachreicht (dann keine neue Seite anstossen)
    property bool searching: false
    readonly property bool busy: searchProc.alive
    readonly property bool hasMore: root.page > 0 && root.page < Math.min(root.lastPage, root.maxPages)
    // Es gab schon eine Antwort fuer die aktuelle Suche (sonst: nichts
    // gesucht, "keine Treffer" waere falsch)
    property bool answered: false

    // Ob die eigene Sektion gerade offen ist
    readonly property bool shown: LauncherState.open && LauncherState.mode === "wallpaper"
        && LauncherState.wallpaperSection === root.plugin.id

    // Im Launcher unter ">" und per Tastenkuerzel (simple.lua: SUPER+ALT+W ->
    // ipc open): Auswahl mit aufgeklappter Sektion und der Tastatur darin
    readonly property var actions: [
        {
            name: I18n.tr("Wallhaven durchsuchen"),
            desc: "SUPER+ALT+W",
            keepOpen: true,
            run: () => LauncherState.showWallpaperSection(LauncherState.screen, root.plugin.id)
        }
    ]

    // qs -c dynamic-island ipc call plugins call wallhaven open _
    function ipc(cmd: string, arg: string): string {
        if (cmd === "open") {
            // Genau so schon offen -> zu
            LauncherState.toggleWallpaperSection(LauncherState.focusedScreen(), root.plugin.id);
            return "ok";
        }
        if (cmd === "status")
            return JSON.stringify({
                query: root.query, items: root.items.count, page: root.page, lastPage: root.lastPage,
                total: root.total, searching: root.searching, downloading: root.downloading, error: root.error,
                fullPreview: root.cfg.fullPreview, prefetchingId: root.prefetchingId, screenWidth: root.screenWidth,
                hq: (() => { let n = 0; for (let i = 0; i < root.items.count; i++) n += root.items.get(i).hq !== "" ? 1 : 0; return n; })()
            });
        return "unbekannt: open | status";
    }

    // Plugin aus: nichts mehr anfragen, und zeigt der Hintergrund gerade
    // eines unserer Bilder (Thumb oder HQ-Vorschau aus dem Cache), zurueck
    // zum echten Bild
    function onDisable(): void {
        searchProc.stop();
        downloadProc.running = false;
        root.pendingDownload = null;
        root.cancelPrefetch();
        if (Wallpapers.showPreview && Wallpapers.previewPath.startsWith(root.plugin.cachePath("")))
            Wallpapers.stopPreview();
    }

    // ---- Treffer ----
    // Rollen: wid, url, full, thumb, resolution, size, fileType, favorites,
    // views, local (Pfad oder ""), hq (Vorschau in Bildschirmgroesse aus dem
    // Cache oder ""), phase ("" | "downloading" | "error").
    // `wid` statt `id`: das ist in QML reserviert.
    readonly property ListModel items: ListModel {}

    function indexOf(wid: string): int {
        for (let i = 0; i < root.items.count; i++)
            if (root.items.get(i).wid === wid)
                return i;
        return -1;
    }

    function patch(wid: string, values: var): void {
        const at = root.indexOf(wid);
        if (at < 0)
            return;
        for (const key in values)
            root.items.setProperty(at, key, values[key]);
    }

    // ---- Einstellungen -> API ----
    // Die Einstellungen halten deutsche Chip-Werte (wie wallpaper.transition),
    // die API will ihre eigenen Woerter bzw. Bitmasken
    readonly property var sortings: ({
        "relevanz": "relevance",
        "neu": "date_added",
        "zufall": "random",
        "views": "views",
        "favoriten": "favorites",
        "top": "toplist"
    })
    readonly property var topRanges: ({
        "1 Tag": "1d", "3 Tage": "3d", "1 Woche": "1w", "1 Monat": "1M",
        "3 Monate": "3M", "6 Monate": "6M", "1 Jahr": "1y"
    })
    readonly property var purities: ({ "sfw": "100", "sfw+sketchy": "110" })
    readonly property var categoryBits: ({
        "alle": "111", "general": "100", "anime": "010", "people": "001", "general+anime": "110"
    })

    readonly property var cfg: root.plugin.settings
    readonly property string sorting: root.sortings[root.cfg.sorting] ?? "toplist"

    // Sortierung aus der Sektion: in die Einstellungen, Chips dort und im
    // Menue zeigen denselben Wert
    function setSorting(name: string): void {
        if (name in root.sortings)
            root.plugin.set("sorting", name);
    }

    // Alle Filter als ein Schluessel: aendert sich einer (Chip in der
    // Sektion oder im Menue), passt die Trefferliste nicht mehr. Bei offener
    // Sektion gleich neu suchen – zugeklappt nur merken, sonst liefe fuer
    // eine Liste, die niemand sieht, ein Prozess (refresh holt es nach).
    readonly property string filters: [root.sorting, root.cfg.topRange, root.cfg.categories,
        root.cfg.purity, root.cfg.atleast, root.cfg.ratios].join("|")
    property bool stale: false

    onFiltersChanged: {
        if (!root.answered && !root.searching)
            return;
        if (root.shown)
            root.search(root.query, true);
        else
            root.stale = true;
    }

    // Beim Aufklappen der Sektion: ohne Treffer gleich etwas zeigen (Toplist
    // o.ae. laut Einstellungen), veraltete Treffer erneuern
    function refresh(): void {
        if (root.stale || (!root.answered && !root.searching))
            root.search(root.query, true);
    }

    // ---- Suche ----
    // Erste Seite. `force` sucht auch bei gleichem Text nochmal (Filter
    // gewechselt, Fehler wiederholen).
    function search(text: string, force: bool): void {
        const q = text.trim();
        if (!force && q === root.query && (root.answered || root.searching))
            return;
        root.query = q;
        root.seed = "";
        root.page = 0;
        root.lastPage = 0;
        root.total = 0;
        root.answered = false;
        root.stale = false;
        root.fetch(1);
    }

    // Naechste Seite anhaengen – nur wenn gerade nichts laeuft, sonst
    // stapeln sich Anfragen beim schnellen Durchblaettern
    function loadMore(): void {
        if (root.busy || !root.hasMore)
            return;
        root.fetch(root.page + 1);
    }

    function fetch(page: int): void {
        root.error = "";
        root.searching = true;

        const c = root.cfg;
        const cmd = ["python3", "-I", root.script, "search", root.query,
            "-s", root.sorting, "-r", root.topRanges[c.topRange] ?? "1M",
            "-c", root.categoryBits[c.categories] ?? "111",
            "-u", root.purities[c.purity] ?? "100",
            "-p", String(page)];
        if (c.atleast !== "aus")
            cmd.push("-a", c.atleast);
        if (c.ratios !== "alle")
            cmd.push("--ratios", c.ratios);
        if (root.sorting === "random" && root.seed !== "")
            cmd.push("--seed", root.seed);

        searchProc.start(cmd, page);
    }

    Process {
        id: searchProc

        property int page: 1
        // Neustart erst, wenn der alte Prozess wirklich weg ist: Quickshell
        // meldet dessen onExited sonst NACH dem Start des neuen (und `running`
        // steht dann auf false, obwohl der neue laeuft) – `searching` fiele
        // mitten in der neuen Suche ab. Darum eigenes `alive` + Warteschlange.
        property bool alive: false
        property var queued: null

        function start(cmd: var, page: int): void {
            if (searchProc.alive) {
                searchProc.queued = { cmd, page };
                searchProc.running = false;
                return;
            }
            searchProc.page = page;
            searchProc.command = cmd;
            searchProc.alive = true;
            searchProc.running = true;
        }

        function stop(): void {
            searchProc.queued = null;
            searchProc.running = false;
        }

        stdout: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (msg.type === "result")
                    root.receive(msg);
                else if (msg.type === "thumb")
                    root.patch(msg.id, { thumb: msg.thumb });
                else if (msg.type === "error") {
                    root.error = msg.message ?? I18n.tr("Fehler");
                    root.searching = false;
                }
            }
        }

        // Abgebrochen oder abgestuerzt, ohne dass eine Antwort kam – oder
        // fuer die naechste Anfrage beendet, die jetzt startet
        onExited: {
            searchProc.alive = false;
            const next = searchProc.queued;
            searchProc.queued = null;
            if (next)
                searchProc.start(next.cmd, next.page);
            else
                root.searching = false;
        }
    }

    function receive(msg: var): void {
        const meta = msg.meta ?? {};
        if (searchProc.page === 1)
            root.items.clear();
        for (const w of msg.items ?? []) {
            root.items.append({
                wid: w.id,
                url: w.url ?? "",
                full: w.full ?? "",
                thumb: w.thumb ?? "",
                resolution: w.resolution ?? "",
                size: Number(w.size ?? 0),
                fileType: w.fileType ?? "",
                favorites: Number(w.favorites ?? 0),
                views: Number(w.views ?? 0),
                local: w.local ?? "",
                hq: w.hq ?? "",
                phase: ""
            });
        }
        root.page = Number(meta.page ?? searchProc.page);
        root.lastPage = Number(meta.lastPage ?? 1);
        root.total = Number(meta.total ?? root.items.count);
        if (meta.seed)
            root.seed = String(meta.seed);
        root.answered = true;
        root.searching = false;
    }

    // ---- HQ-Vorschau ----
    // Bleibt die Auswahl kurz auf einem Treffer stehen (WallhavenList), holt
    // `prefetch` das Vollbild in den Cache des Plugins (wallhaven.py fetch:
    // Original + auf Bildschirmbreite verkleinertes JPEG) und traegt das
    // JPEG als `hq` ein – der Hintergrund zieht dann vom Thumb darauf hoch.
    // Einer gleichzeitig; Weiterblaettern bricht ab (Prozess beenden reicht,
    // das Skript laesst keine halben Dateien liegen). Ein spaeterer Download
    // nimmt das Original aus dem Cache und ist damit sofort fertig.
    property string prefetchingId: ""
    readonly property bool prefetching: fetchProc.alive
    // So breit wird das Vorschau-JPEG: der Monitor, auf dem die Auswahl
    // offen ist (gleiche Breite = gleicher Cache-Eintrag)
    readonly property int screenWidth: LauncherState.screen?.width ?? 2560

    function prefetch(wid: string): void {
        if (!root.cfg.fullPreview)
            return;
        const at = root.indexOf(wid);
        if (at < 0)
            return;
        const item = root.items.get(at);
        if (item.local !== "" || item.hq !== "" || (fetchProc.alive && root.prefetchingId === wid))
            return;
        // Wartet ein Download auf den laufenden Abruf, den nicht abbrechen
        if (root.pendingDownload)
            return;
        fetchProc.start(wid, ["python3", "-I", root.script, "fetch", wid, "--url", item.full,
            "--width", String(root.screenWidth)]);
    }

    // Laufenden Abruf abbrechen – ausser ein Download wartet auf genau ihn
    // (Enter waehrend des Abrufs, danach weitergeblaettert)
    function cancelPrefetch(): void {
        fetchProc.queued = null;
        if (root.pendingDownload && root.pendingDownload.wid === root.prefetchingId)
            return;
        fetchProc.running = false;
    }

    Process {
        id: fetchProc

        // Wie searchProc: Neustart erst nach dem echten Ende des alten
        property bool alive: false
        property var queued: null

        function start(wid: string, cmd: var): void {
            if (fetchProc.alive) {
                fetchProc.queued = { wid, cmd };
                fetchProc.running = false;
                return;
            }
            root.prefetchingId = wid;
            fetchProc.command = cmd;
            fetchProc.alive = true;
            fetchProc.running = true;
        }

        stdout: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (msg.type === "preview" && msg.path)
                    root.patch(msg.id, { hq: msg.path });
                else if (msg.type === "error")
                    root.plugin.log(`HQ-Vorschau ${root.prefetchingId}: ${msg.message ?? "Fehler"}`);
            }
        }

        onExited: {
            fetchProc.alive = false;
            root.prefetchingId = "";
            // Enter waehrend des Abrufs: jetzt den Download nachholen, der
            // nimmt das Original aus dem Cache
            const p = root.pendingDownload;
            root.pendingDownload = null;
            if (p)
                root.download(p.wid, p.apply);
            const next = fetchProc.queued;
            fetchProc.queued = null;
            if (next && !root.downloading)
                fetchProc.start(next.wid, next.cmd);
        }
    }

    // ---- Download ----
    // Einer nach dem anderen: die Bilder sind 2-6 MB, und ein zweiter Klick
    // waehrend des ersten ist eher ein Versehen als ein Wunsch.
    property string downloadingId: ""
    // Auch ein auf den Abruf wartender Download zaehlt: sonst startet ein
    // zweiter Klick daneben, und der wartende ginge danach verloren
    readonly property bool downloading: downloadProc.running || root.pendingDownload !== null
    // Download, der auf das Ende eines laufenden Abrufs wartet ({ wid, apply })
    property var pendingDownload: null

    // `apply`: danach als Wallpaper setzen (ueber Wallpapers.set, damit die
    // Auswahl sofort das neue Bild kennt). Liegt es schon lokal, geht es
    // ohne Netz direkt weiter.
    function download(wid: string, apply: bool): void {
        const at = root.indexOf(wid);
        if (at < 0 || root.downloading)
            return;
        const item = root.items.get(at);
        if (item.local !== "") {
            root.finish(wid, item.local, apply);
            return;
        }
        // Laeuft gerade der Abruf fuer dieses Bild, zu Ende laden lassen
        // statt es ein zweites Mal zu holen; ein anderer Abruf fliegt raus
        if (fetchProc.alive) {
            if (root.prefetchingId === wid) {
                root.pendingDownload = { wid, apply };
                root.items.setProperty(at, "phase", "downloading");
                return;
            }
            root.cancelPrefetch();
        }
        root.downloadingId = wid;
        root.items.setProperty(at, "phase", "downloading");
        downloadProc.wid = wid;
        downloadProc.apply = apply;
        downloadProc.command = ["python3", "-I", root.script, "download", wid, "--url", item.full];
        downloadProc.running = true;
    }

    function finish(wid: string, path: string, apply: bool): void {
        root.patch(wid, { local: path, phase: "" });
        if (apply) {
            Wallpapers.set(path);
            // Gesetzt: die Auswahl zu, wie beim lokalen Setzen. Beim reinen
            // Download bleibt sie offen – die Kachel traegt dann das Haekchen,
            // und das Bild steht in der lokalen Reihe.
            if (LauncherState.open && LauncherState.mode === "wallpaper")
                LauncherState.close();
        }
        // Ab jetzt steht es auch im lokalen Karussell
        Wallpapers.reload();
    }

    Process {
        id: downloadProc

        property string wid: ""
        property bool apply: false
        property string path: ""

        stdout: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (msg.type === "done")
                    downloadProc.path = msg.path ?? "";
                else if (msg.type === "error")
                    root.error = msg.message ?? I18n.tr("Download fehlgeschlagen");
            }
        }

        onExited: {
            root.downloadingId = "";
            if (downloadProc.path !== "") {
                root.finish(downloadProc.wid, downloadProc.path, downloadProc.apply);
                downloadProc.path = "";
            } else {
                root.patch(downloadProc.wid, { phase: "error" });
                if (root.error === "")
                    root.error = I18n.tr("Download fehlgeschlagen");
            }
        }
    }
}
