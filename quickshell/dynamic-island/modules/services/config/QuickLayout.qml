pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// Aufbau der Schnelleinstellungen (die Kacheln in der Settings-Karte) – ein
// Raster wie im Android-Tray.
//
// Config.quick.columns sagt, wie viele Spalten das Raster hat. Die Reihen
// stehen in Config.quick.rows als Liste von Strings, je Reihe eine, Kacheln
// als "id:breite" (Breite in Spalten), mit Komma getrennt. Hier steht,
// welche Kacheln es gibt (`tiles`), und die Operationen, die der Drag-and-
// Drop-Editor im Einstellungs-Menue braucht. SettingsTiles.qml rendert
// `rows`.
//
// Kachel-Arten (nur Vorgaben fuer die Breite):
//   pill    2 Spalten, ab 1 Spalte nur das Symbol
//   circle  1 Spalte  (Standard-Aufbau nutzt 2, wie im Android-Tray)
//   wide    volle Breite, mindestens 2 Spalten (Regler, Aufnahme)
Singleton {
    id: root

    readonly property var tiles: ({
        "wifi":       { label: "Wi-Fi",         icon: "wifi",           kind: "pill" },
        "bluetooth":  { label: "Bluetooth",     icon: "bluetooth",      kind: "pill" },
        "vpn":        { label: "VPN",           icon: "vpn_key",        kind: "pill" },
        "nosleep":    { label: "No Sleep",      icon: "coffee",         kind: "pill" },
        "gamemode":   { label: "Game-Mode",     icon: "sports_esports", kind: "circle" },
        "monitors":   { label: "Bildschirm",    icon: "monitor",        kind: "circle" },
        "settings":   { label: "Einstellungen", icon: "tune",           kind: "circle" },
        "record":     { label: "Aufnahme",      icon: "screen_record",  kind: "wide" },
        "volume":     { label: "Lautstärke",    icon: "volume_up",      kind: "wide" },
        "mic":        { label: "Mikrofon",      icon: "mic",            kind: "wide" },
        "power":      { label: "Energie",       icon: "bolt",           kind: "pill" },
        "brightness": { label: "Helligkeit",    icon: "brightness_6",   kind: "wide" },
        "screenshot": { label: "Screenshot",    icon: "screenshot",     kind: "wide" },
        "dnd":        { label: "Nicht stören",  icon: "notifications_off", kind: "pill" },
        "lock":       { label: "Sperren",       icon: "lock",           kind: "circle" }
    })
    readonly property var ids: Object.keys(root.tiles)

    readonly property int columns: Math.max(2, Math.min(6, Config.quick.columns))

    // Reihen als Arrays von { id, span } – bereinigt: Unbekanntes und
    // Doppeltes raus, Breiten auf [minSpan, columns] gedeckelt, Reihen, die
    // nicht mehr passen, aufgeteilt, leere Reihen raus.
    //
    // Eigener Zustand statt Binding auf Config.quick.rows. Grund: nach
    // Config.set() schreibt der FileView asynchron, und der Datei-Watcher
    // meldet dazwischen noch einmal den VORHERIGEN Dateistand (das Signal
    // kommt mit dem alten Wert, kurz danach erst der neue). Ein Binding
    // haette damit kurz den alten Stand – zweimal schnell ziehen rechnete
    // dann auf der falschen Basis. Deshalb: save() setzt `rows` sofort und
    // sperrt externe Aenderungen fuer einen Moment; Aenderungen von aussen
    // (Datei von Hand, Reset, Spaltenzahl) kommen ueber die Connections nach.
    property var rows: root.parse(Config.quick.rows)
    // Alles, was in keiner Reihe steht
    readonly property var hidden: root.ids.filter(id => !root.rows.some(r => r.some(t => t.id === id)))

    Timer {
        id: saveGuard

        interval: 400
    }

    Connections {
        target: Config.quick

        function onRowsChanged(): void {
            if (saveGuard.running)
                return;
            root.reparse();
        }

        // Weniger Spalten: Reihen neu aufteilen (parse macht das)
        function onColumnsChanged(): void {
            root.reparse();
        }
    }

    // Reihen und Spalten aendern sich beim Laden oft zugleich – einmal
    // gesammelt neu aufbauen statt je Signal (jede Zuweisung baut alle
    // Kachel-Repeater neu)
    function reparse(): void {
        Qt.callLater(root.applyParsed);
    }

    function applyParsed(): void {
        root.rows = root.parse(Config.quick.rows);
    }

    function kind(id: string): string {
        return root.tiles[id]?.kind ?? "pill";
    }

    function isWide(id: string): bool {
        return root.kind(id) === "wide";
    }

    function minSpan(id: string): int {
        return root.isWide(id) ? Math.min(2, root.columns) : 1;
    }

    function defaultSpan(id: string): int {
        const k = root.kind(id);
        return k === "wide" ? root.columns : k === "circle" ? 1 : Math.min(2, root.columns);
    }

    function clampSpan(id: string, span: int): int {
        return Math.max(root.minSpan(id), Math.min(root.columns, span));
    }

    function used(row: var): int {
        return row.reduce((sum, t) => sum + t.span, 0);
    }

    function parse(list: var): var {
        const seen = new Set();
        const out = [];
        for (const line of list) {
            let row = [];
            for (const raw of String(line).split(",")) {
                const [idRaw, spanRaw] = raw.split(":");
                const id = (idRaw ?? "").trim();
                if (id === "" || !root.tiles[id] || seen.has(id))
                    continue;
                seen.add(id);
                const parsed = parseInt(spanRaw ?? "", 10);
                const span = root.clampSpan(id, isNaN(parsed) ? root.defaultSpan(id) : parsed);
                // Passt nicht mehr in die Reihe: neue Reihe anfangen
                if (root.used(row) + span > root.columns && row.length > 0) {
                    out.push(row);
                    row = [];
                }
                row.push({ id, span });
            }
            if (row.length)
                out.push(row);
        }
        return out;
    }

    function serialise(rows: var): var {
        return rows.filter(r => r.length > 0).map(r => r.map(t => `${t.id}:${t.span}`).join(","));
    }

    function save(rows: var): void {
        const clean = rows.filter(r => r.length > 0);
        root.rows = clean;
        saveGuard.restart();
        Config.set("quick", "rows", root.serialise(clean));
    }

    function copy(): var {
        return root.rows.map(r => r.map(t => ({ id: t.id, span: t.span })));
    }

    function find(rows: var, id: string): var {
        for (let i = 0; i < rows.length; i++) {
            const k = rows[i].findIndex(t => t.id === id);
            if (k >= 0)
                return ({ row: i, index: k, tile: rows[i][k] });
        }
        return null;
    }

    // `id` nach Reihe `rowIndex` an Position `index` legen. rowIndex ===
    // rows.length haengt eine neue Reihe an, `newRow` legt eine neue Reihe
    // VOR rowIndex an. Passt die Kachel nicht mehr in die Reihe, wird sie so
    // schmal wie der freie Platz; ist nicht einmal ihre Mindestbreite frei,
    // bekommt sie eine eigene Reihe daneben.
    function place(id: string, rowIndex: int, index: int, newRow: bool): void {
        const cur = root.copy();
        let tile = { id, span: root.defaultSpan(id) };

        const hit = root.find(cur, id);
        if (hit) {
            tile = cur[hit.row].splice(hit.index, 1)[0];
            if (hit.row === rowIndex && !newRow && hit.index < index)
                index--;
        }

        const inRange = rowIndex >= 0 && rowIndex < cur.length;
        const others = inRange ? cur[rowIndex] : [];
        const free = root.columns - root.used(others);
        const ownRow = newRow || !inRange || free < root.minSpan(id);

        if (ownRow) {
            const at = newRow ? rowIndex
                     : !inRange ? cur.length
                     : index <= 0 ? rowIndex : rowIndex + 1;
            cur.splice(Math.max(0, Math.min(at, cur.length)), 0, [tile]);
        } else {
            tile.span = Math.min(tile.span, free);
            cur[rowIndex].splice(Math.max(0, Math.min(index, others.length)), 0, tile);
        }
        root.save(cur);
    }

    // Breite aendern – hoechstens so weit, wie die Reihe noch Platz hat
    function resize(id: string, span: int): void {
        const cur = root.copy();
        const hit = root.find(cur, id);
        if (!hit)
            return;
        const free = root.columns - root.used(cur[hit.row]) + hit.tile.span;
        const next = Math.max(root.minSpan(id), Math.min(free, span));
        if (next === hit.tile.span)
            return;
        hit.tile.span = next;
        root.save(cur);
    }

    // Wie breit darf `id` in seiner Reihe hoechstens werden?
    function maxSpan(id: string): int {
        const hit = root.find(root.rows, id);
        if (!hit)
            return root.columns;
        return root.columns - root.used(root.rows[hit.row]) + hit.tile.span;
    }

    function hide(id: string): void {
        root.save(root.rows.map(r => r.filter(t => t.id !== id)));
    }

    // Wieder einblenden: als eigene Reihe hinten dran
    function show(id: string): void {
        const cur = root.copy();
        cur.push([{ id, span: root.defaultSpan(id) }]);
        root.save(cur);
    }

    // Zuruecksetzen laeuft wie ein save(): Stand sofort setzen, Sperre an –
    // sonst holt der verspaetete Watcher-Nachlauf des vorigen Schreibens den
    // alten Aufbau zurueck
    function reset(): void {
        const d = Config.defaults.quick?.rows;
        if (d === undefined)
            return;
        root.rows = root.parse(d);
        saveGuard.restart();
        Config.reset("quick", "rows");
    }
}
