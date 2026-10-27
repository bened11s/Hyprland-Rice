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
// Lueckenstuecke: "_:n" haelt n Spalten frei, damit eine Kachel weiter
// rechts stehen kann (Helligkeit | leer | Widget). Sie zaehlen nicht als
// Kachel (nicht in `tiles`/`hidden`), Luecken am Reihenende fallen weg.
//
// Kachel-Arten (nur Vorgaben fuer die Breite):
//   pill    2 Spalten, ab 1 Spalte nur das Symbol
//   circle  1 Spalte  (Standard-Aufbau nutzt 2, wie im Android-Tray)
//   wide    volle Breite, mindestens 2 Spalten (Regler, Aufnahme)
Singleton {
    id: root

    readonly property var builtinTiles: ({
        "wifi":       { label: "Wi-Fi",         icon: "wifi",           kind: "pill" },
        "bluetooth":  { label: "Bluetooth",     icon: "bluetooth",      kind: "pill" },
        "vpn":        { label: "VPN",           icon: "vpn_key",        kind: "pill" },
        "nosleep":    { label: "No Sleep",      icon: "coffee",         kind: "pill" },
        "gamemode":   { label: "Game-Mode",     icon: "sports_esports", kind: "circle" },
        "airplane":   { label: "Flugmodus",     icon: "flight",         kind: "circle" },
        "settings":   { label: "Einstellungen", icon: "tune",           kind: "circle" },
        "record":     { label: "Aufnahme",      icon: "screen_record",  kind: "wide" },
        "volume":     { label: "Lautstärke",    icon: "volume_up",      kind: "wide" },
        "mic":        { label: "Mikrofon",      icon: "mic",            kind: "wide" },
        "power":      { label: "Energie",       icon: "bolt",           kind: "pill" },
        "brightness": { label: "Helligkeit",    icon: "brightness_6",   kind: "wide" }
    })
    // Kacheln aktiver Plugins ("<plugin>.<kachel>" -> { label, icon, kind, url,
    // plugin }), gesetzt von Plugins.qml – die Abhaengigkeit laeuft nur in
    // diese Richtung (plugins importiert config, nicht umgekehrt)
    property var extraTiles: ({})
    readonly property var tiles: Object.assign({}, root.builtinTiles, root.extraTiles)
    readonly property var ids: Object.keys(root.tiles)

    readonly property int columns: Math.max(2, Math.min(6, Config.quick.columns))
    readonly property string gap: "_"

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

    // Plugin-Kacheln kommen nach dem Start (oder beim Ein-/Ausschalten) dazu:
    // neu einlesen, sonst fielen sie beim ersten Parsen als unbekannt raus
    onExtraTilesChanged: root.reparse()

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

    // Belegt von echten Kacheln (Luecken geben ihren Platz her)
    function tileUsed(row: var): int {
        return row.reduce((sum, t) => sum + (t.id === root.gap ? 0 : t.span), 0);
    }

    // Luecken aufraeumen: benachbarte zusammenlegen, am Ende weg, und wenn die
    // Reihe zu voll ist, Luecken von hinten her schrumpfen
    function tidy(row: var): var {
        const out = [];
        for (const t of row) {
            const last = out[out.length - 1];
            if (t.id === root.gap && last && last.id === root.gap)
                last.span += t.span;
            else if (t.span > 0)
                out.push({ id: t.id, span: t.span });
        }
        let over = root.used(out) - root.columns;
        for (let i = out.length - 1; i >= 0 && over > 0; i--) {
            if (out[i].id !== root.gap)
                continue;
            const cut = Math.min(over, out[i].span);
            out[i].span -= cut;
            over -= cut;
        }
        const kept = out.filter(t => t.span > 0);
        while (kept.length && kept[kept.length - 1].id === root.gap)
            kept.pop();
        return kept;
    }

    // Startspalte jedes Eintrags einer Reihe
    function columnsOf(row: var): var {
        let c = 0;
        return row.map(t => {
            const at = c;
            c += t.span;
            return at;
        });
    }

    function parse(list: var): var {
        const seen = new Set();
        const out = [];
        for (const line of list) {
            let row = [];
            for (const raw of String(line).split(",")) {
                const [idRaw, spanRaw] = raw.split(":");
                const id = (idRaw ?? "").trim();
                if (id === root.gap) {
                    const n = parseInt(spanRaw ?? "", 10);
                    const free = root.columns - root.used(row);
                    if (!isNaN(n) && n > 0 && free > 0)
                        row.push({ id, span: Math.min(n, free) });
                    continue;
                }
                if (id === "" || !root.tiles[id] || seen.has(id))
                    continue;
                seen.add(id);
                const parsed = parseInt(spanRaw ?? "", 10);
                const span = root.clampSpan(id, isNaN(parsed) ? root.defaultSpan(id) : parsed);
                // Passt nicht mehr in die Reihe: neue Reihe anfangen
                if (root.used(row) + span > root.columns && row.length > 0) {
                    out.push(root.tidy(row));
                    row = [];
                }
                row.push({ id, span });
            }
            out.push(root.tidy(row));
        }
        return out.filter(r => r.length > 0);
    }

    function serialise(rows: var): var {
        return rows.filter(r => r.length > 0).map(r => r.map(t => `${t.id}:${t.span}`).join(","));
    }

    function save(rows: var): void {
        const clean = rows.map(r => root.tidy(r)).filter(r => r.length > 0);
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
        const free = root.columns - root.tileUsed(others);
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

    // Wie breit passt `id` ab Spalte `column` in Reihe `rowIndex`? Zaehlt
    // freie Zellen (Luecken und Reihenende) bis zur naechsten Kachel; die
    // eigenen Zellen von `id` gelten als frei. 0 = passt nicht.
    function fitAt(id: string, rowIndex: int, column: int): int {
        if (column < 0 || column >= root.columns)
            return 0;
        const row = root.rows[rowIndex] ?? [];
        const cols = root.columnsOf(row);
        let end = root.columns;
        for (let i = 0; i < row.length; i++) {
            const t = row[i];
            if (t.id === root.gap || t.id === id)
                continue;
            if (cols[i] <= column && column < cols[i] + t.span)
                return 0;
            if (cols[i] > column)
                end = Math.min(end, cols[i]);
        }
        const hit = root.find(root.rows, id);
        const want = hit ? hit.tile.span : root.defaultSpan(id);
        const span = Math.min(want, end - column);
        return span >= root.minSpan(id) ? span : 0;
    }

    // `id` in Reihe `rowIndex` ab Spalte `column` legen (auf freie Zellen).
    // Davor bleibt eine Luecke. In derselben Reihe wird der alte Platz zur
    // Luecke (der Rest bleibt stehen), aus einer anderen Reihe rueckt die
    // alte Reihe zusammen. Passt die Kachel nicht (fitAt = 0): nichts.
    function placeAt(id: string, rowIndex: int, column: int): void {
        const span = root.fitAt(id, rowIndex, column);
        if (span === 0)
            return;
        const cur = root.copy();
        const hit = root.find(cur, id);
        if (hit && hit.row === rowIndex)
            cur[hit.row][hit.index] = { id: root.gap, span: hit.tile.span };
        else if (hit)
            cur[hit.row].splice(hit.index, 1);

        // Reihe als Kacheln mit Startspalte, die neue dazu, dann mit
        // Luecken wieder zusammensetzen
        const row = rowIndex < cur.length ? cur[rowIndex] : [];
        const cols = root.columnsOf(row);
        const placed = row.map((t, i) => ({ id: t.id, span: t.span, col: cols[i] }))
                          .filter(t => t.id !== root.gap);
        placed.push({ id, span, col: column });
        placed.sort((a, b) => a.col - b.col);

        const next = [];
        let c = 0;
        for (const t of placed) {
            if (t.col > c)
                next.push({ id: root.gap, span: t.col - c });
            next.push({ id: t.id, span: t.span });
            c = t.col + t.span;
        }
        if (rowIndex < cur.length)
            cur[rowIndex] = next;
        else
            cur.push(next);
        root.save(cur);
    }

    // Ganze Reihe verschieben (Layout-Modus der Steuerung): Reihe `from`
    // landet an Position `to` (Index im Ergebnis)
    function moveRow(from: int, to: int): void {
        const cur = root.copy();
        if (from < 0 || from >= cur.length)
            return;
        const target = Math.max(0, Math.min(to, cur.length - 1));
        if (target === from)
            return;
        const row = cur.splice(from, 1)[0];
        cur.splice(target, 0, row);
        root.save(cur);
    }

    // Breite aendern – hoechstens so weit, wie die Reihe noch Platz hat
    function resize(id: string, span: int): void {
        const cur = root.copy();
        const hit = root.find(cur, id);
        if (!hit)
            return;
        // Luecken in der Reihe darf die Kachel aufbrauchen (tidy schrumpft sie)
        const free = root.columns - root.tileUsed(cur[hit.row]) + hit.tile.span;
        const next = Math.max(root.minSpan(id), Math.min(free, span));
        if (next === hit.tile.span)
            return;
        // Breiter frisst zuerst die Luecke direkt dahinter, damit der Rest
        // der Reihe stehen bleibt (sonst schrumpft tidy Luecken von hinten)
        const after = cur[hit.row][hit.index + 1];
        const delta = next - hit.tile.span;
        if (delta > 0 && after && after.id === root.gap)
            after.span -= Math.min(delta, after.span);
        hit.tile.span = next;
        root.save(cur);
    }

    // Wie breit darf `id` in seiner Reihe hoechstens werden?
    function maxSpan(id: string): int {
        const hit = root.find(root.rows, id);
        if (!hit)
            return root.columns;
        return root.columns - root.tileUsed(root.rows[hit.row]) + hit.tile.span;
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
