pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import qs

// Monitore (Einstellungen > Monitore, settings/MonitorsEditor): liest
// `hyprctl -j monitors all`, wendet Aenderungen live per `hyprctl eval`
// an und schreibt bestaetigte Regeln nach ~/.config/hypr/monitors.lua –
// dieselbe git-ignorierte Datei, die install.sh anlegt und
// hypr/monitor-setup.lua laedt (Format: monitors.example.lua, eine Liste
// von hl.monitor()-Feldern plus `workspaces`).
//
// Die Datei ist die einzige Quelle: beim Laden liest `lua` sie ein und gibt
// sie als JSON aus; beim Speichern wird sie komplett neu geschrieben, mit
// allen Feldern, die die Seite nicht kennt (workspaces, bitdepth, …), und
// vorher nach monitors.lua.bak gesichert. Ohne `lua` oder bei kaputter
// Datei schreibt die Seite nichts (sonst gingen Eintraege verloren).
//
// Schluessel (output) eines Monitors: steht er schon in der Datei – unter
// seinem Port (so schreibt install.sh) oder als desc:<EDID> –, bleibt es
// dabei. Neue externe Monitore bekommen desc:<EDID-Beschreibung> (der Port
// wechselt mit Kabel und Dock), interne Panels (eDP-*, …) den Portnamen.
//
// Uebernehmen wie bei GNOME: anwenden, dann 15 s "Einstellungen behalten?";
// ohne Antwort oder bei Zuruecksetzen kommt der alte Stand zurueck. Erst
// Behalten schreibt die Datei. "Standard wiederherstellen" setzt den Monitor
// auf bevorzugten Modus, automatische Position und Skalierung (eine
// workspaces-Angabe bleibt erhalten) – ebenfalls mit Frage.
Singleton {
    id: root

    readonly property string luaPath: Quickshell.env("DYNAMIC_ISLAND_MONITORS_LUA") || Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
    // Wie Keybinds.qml: nur die installierte Shell schreibt nach Hyprland
    readonly property bool writesHypr: !!Quickshell.env("DYNAMIC_ISLAND_MONITORS_LUA")
                                       || Quickshell.shellPath("shell.qml") === Quickshell.env("HOME") + "/.config/quickshell/dynamic-island/shell.qml"

    // [{ id, name, key, description, make, model, serial, short,
    //    width, height, refresh, x, y, scale, transform, vrr, vrrMode,
    //    disabled, focused, dpms, mirrorOf, format,
    //    modes: [{ w, h, hz, label }],
    //    resolutions: [{ w, h, label, rates: [hz] }],
    //    rule: {…} | null }]
    property var monitors: []
    property bool loaded: false
    readonly property bool busy: readProc.running || applyProc.running
    property string lastError: ""

    // Regeln aus monitors.lua je output (Reihenfolge wie in der Datei)
    property var rules: ({})
    property bool rulesLoaded: false
    // Nur wenn die Datei sauber gelesen wurde (oder fehlt), darf sie neu
    // geschrieben werden
    property bool rulesWritable: false

    // ---- Frage "Einstellungen behalten?" ----
    // Sekunden bis zum automatischen Zuruecksetzen, 0 = keine Frage offen
    property int countdown: 0
    readonly property bool confirming: root.countdown > 0
    readonly property int confirmSeconds: 15
    // Was gerade probeweise gilt und was davor galt
    property var pendingSpecs: []
    property var pendingResets: []
    property var previousSpecs: []
    // Zaehlt jede abgeschlossene Anwendung hoch (Editor verwirft dann seine
    // ausstehenden Aenderungen)
    property int applied: 0

    // ---- Lesen ------------------------------------------------------------

    function refresh(): void {
        if (readProc.running)
            return;
        readProc.running = true;
    }

    function keyOf(name: string, description: string): string {
        if (root.rules[name] !== undefined)
            return name;
        if (description !== "" && root.rules["desc:" + description] !== undefined)
            return "desc:" + description;
        if (/^(eDP|LVDS|DSI)-/.test(name) || description === "")
            return name;
        return "desc:" + description;
    }

    function parseMode(s: string): var {
        const m = /^(\d+)x(\d+)@([\d.]+)/.exec(s);
        if (!m)
            return null;
        const hz = Math.round(parseFloat(m[3]) * 100) / 100;
        return { w: Number(m[1]), h: Number(m[2]), hz, label: root.modeLabel(Number(m[1]), Number(m[2]), hz) };
    }

    function hzLabel(hz: real): string {
        return Number.isInteger(hz) ? String(hz) : hz.toFixed(2).replace(/\.?0+$/, "");
    }

    function modeLabel(w: int, h: int, hz: real): string {
        return `${w}x${h}@${root.hzLabel(hz)}`;
    }

    function parse(text: string): var {
        let list;
        try {
            list = JSON.parse(text);
        } catch (e) {
            root.lastError = "hyprctl monitors: " + e;
            return root.monitors;
        }
        if (!Array.isArray(list))
            return root.monitors;
        const out = [];
        for (const j of list) {
            const modes = [];
            const seen = {};
            for (const s of (j.availableModes ?? [])) {
                const m = root.parseMode(String(s));
                if (!m || seen[m.label])
                    continue;
                seen[m.label] = true;
                modes.push(m);
            }
            // Nach Aufloesung gruppiert, groesste zuerst, Raten absteigend
            const byRes = {};
            const resolutions = [];
            for (const m of modes) {
                const k = `${m.w}x${m.h}`;
                if (!byRes[k]) {
                    byRes[k] = { w: m.w, h: m.h, label: k, rates: [] };
                    resolutions.push(byRes[k]);
                }
                byRes[k].rates.push(m.hz);
            }
            resolutions.sort((a, b) => b.w * b.h - a.w * a.h || b.w - a.w);
            for (const r of resolutions)
                r.rates.sort((a, b) => b - a);

            const name = String(j.name ?? "");
            const description = String(j.description ?? "");
            const key = root.keyOf(name, description);
            const rule = root.rules[key] ?? null;
            const disabled = !!j.disabled;
            // Abgeschaltete Monitore melden 0x0 – fuers Bild den ersten Modus
            const first = modes[0] ?? { w: 1920, h: 1080, hz: 60 };
            const width = Number(j.width) || first.w;
            const height = Number(j.height) || first.h;
            const refresh = Math.round((Number(j.refreshRate) || first.hz) * 100) / 100;
            const make = String(j.make ?? "").trim();
            const model = String(j.model ?? "").trim();
            out.push({
                id: Number(j.id ?? 0),
                name,
                key,
                description,
                make,
                model,
                serial: String(j.serial ?? "").trim(),
                // Kurzname fuers Bild: Modell, sonst Hersteller, sonst Port
                short: model !== "" && !/^0x/i.test(model) ? model : make !== "" ? make : name,
                width,
                height,
                refresh,
                x: Number(j.x ?? 0),
                y: Number(j.y ?? 0),
                scale: Number(j.scale ?? 1) || 1,
                transform: Number(j.transform ?? 0) || 0,
                vrr: !!j.vrr,
                // Regelwert 0/1/2, sonst der gemeldete Zustand
                vrrMode: rule && rule.vrr !== undefined ? Number(rule.vrr) : (j.vrr ? 1 : 0),
                disabled,
                focused: !!j.focused,
                dpms: j.dpmsStatus !== false,
                mirrorOf: j.mirrorOf && j.mirrorOf !== "none" ? String(j.mirrorOf) : "",
                format: String(j.currentFormat ?? ""),
                modes,
                resolutions,
                rule
            });
        }
        out.sort((a, b) => a.id - b.id);
        // mirrorOf meldet hyprctl je nach Stand als ID ("1") statt Port –
        // Regeln (mirror = …) und die Chips brauchen den Portnamen
        for (const o of out) {
            if (/^\d+$/.test(o.mirrorOf))
                o.mirrorOf = out.find(x => x.id === Number(o.mirrorOf))?.name ?? "";
        }
        return out;
    }

    Process {
        id: readProc

        command: ["hyprctl", "-j", "monitors", "all"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.monitors = root.parse(text);
                root.loaded = true;
            }
        }
    }

    // Nach Stecken/Ziehen und nach dem Umschalten erst einmal setzen lassen
    Timer {
        id: refreshDelay

        interval: 500
        onTriggered: root.refresh()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n === "monitoradded" || n === "monitorremoved" || n === "configreloaded")
                refreshDelay.restart();
        }
    }

    // ---- Regeln als Lua ----------------------------------------------------

    function luaString(s: string): string {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"';
    }

    function luaValue(v: var): string {
        if (typeof v === "number")
            return String(v);
        if (typeof v === "boolean")
            return v ? "true" : "false";
        return root.luaString(v);
    }

    // spec: { output, mode, position, scale, transform, vrr, disabled, mirror }
    // -> Felder fuer hl.monitor(); keepExtra uebernimmt auch fremde Felder
    // (workspaces, bitdepth, …) fuer die Datei
    function fieldsOf(spec: var, keepExtra: bool): var {
        const f = [["output", root.luaString(spec.output)]];
        if (spec.disabled) {
            f.push(["disabled", "true"]);
        } else {
            if (spec.mode !== undefined && spec.mode !== "")
                f.push(["mode", root.luaString(spec.mode)]);
            if (spec.position !== undefined && spec.position !== "")
                f.push(["position", root.luaString(spec.position)]);
            if (spec.scale !== undefined && spec.scale !== null)
                f.push(["scale", root.luaValue(spec.scale)]);
            if (spec.transform !== undefined && Number(spec.transform) !== 0)
                f.push(["transform", String(Number(spec.transform) || 0)]);
            if (spec.vrr !== undefined)
                f.push(["vrr", String(Number(spec.vrr) || 0)]);
            if (spec.mirror)
                f.push(["mirror", root.luaString(spec.mirror)]);
        }
        if (keepExtra) {
            const known = ["output", "mode", "position", "scale", "transform", "vrr", "disabled", "mirror"];
            for (const k of Object.keys(spec)) {
                const v = spec[k];
                if (!known.includes(k) && /^[A-Za-z_][A-Za-z0-9_]*$/.test(k)
                        && ["string", "number", "boolean"].includes(typeof v))
                    f.push([k, root.luaValue(v)]);
            }
        }
        return f;
    }

    // Live per eval (ohne workspaces & Co., die kennt hl.monitor nicht)
    function luaOf(spec: var): string {
        return `hl.monitor({ ${root.fieldsOf(spec, false).map(x => x[0] + " = " + x[1]).join(", ")} })`;
    }

    readonly property string luaText: {
        const lines = [
            "-- monitors.lua - Bildschirme dieses Rechners (git-ignoriert).",
            "-- Geschrieben von Dynamic Island (Einstellungen > Monitore); von Hand",
            "-- bearbeiten geht weiter, die Seite liest die Datei beim Oeffnen neu.",
            "-- Felder und Erklaerung: monitors.example.lua",
            "",
            "return {"
        ];
        for (const k of Object.keys(root.rules)) {
            lines.push("    {");
            for (const [key, val] of root.fieldsOf(Object.assign({}, root.rules[k], { output: k }), true))
                lines.push(`        ${key} = ${val},`);
            lines.push("    },");
        }
        lines.push("}", "");
        return lines.join("\n");
    }

    // Aktueller Stand eines Monitors als Regel (zum Zurueckdrehen)
    function snapshot(m: var): var {
        if (m.disabled)
            return { output: m.key, disabled: true };
        const spec = {
            output: m.key,
            mode: root.modeLabel(m.width, m.height, m.refresh),
            position: `${m.x}x${m.y}`,
            scale: m.scale,
            transform: m.transform,
            vrr: m.vrrMode
        };
        if (m.mirrorOf !== "")
            spec.mirror = m.mirrorOf;
        return spec;
    }

    // ---- Anwenden ------------------------------------------------------------

    // specs: Regeln, die probeweise gelten sollen; resets: keys, deren Regel
    // auf die Vorgabe zurueck soll (bevorzugt / auto / auto).
    // previous: der Stand davor (snapshot je betroffenem Monitor).
    function apply(specs: var, resets: var, previous: var): void {
        if (applyProc.running)
            return;
        const chunk = [];
        for (const s of specs)
            chunk.push(root.luaOf(s));
        for (const r of resets)
            chunk.push(root.luaOf({ output: r, mode: "preferred", position: "auto", scale: "auto" }));
        if (chunk.length === 0)
            return;
        root.lastError = "";
        root.pendingSpecs = specs;
        root.pendingResets = resets;
        root.previousSpecs = previous;
        applyProc.ask = true;
        applyProc.command = ["hyprctl", "eval", chunk.join("\n")];
        applyProc.running = true;
    }

    // Nur den alten Stand wiederherstellen, ohne Frage
    function restore(specs: var): void {
        const chunk = specs.map(s => root.luaOf(s));
        if (chunk.length === 0)
            return;
        applyProc.ask = false;
        applyProc.command = ["hyprctl", "eval", chunk.join("\n")];
        applyProc.running = true;
    }

    function keep(): void {
        if (!root.confirming)
            return;
        root.countdown = 0;
        const managed = ["mode", "position", "scale", "transform", "vrr", "disabled", "mirror"];
        const next = Object.assign({}, root.rules);
        for (const s of root.pendingSpecs) {
            // Felder der Seite aus der neuen Regel, alles andere (workspaces …)
            // aus der alten
            const r = Object.assign({}, root.rules[s.output] ?? {});
            for (const k of managed)
                delete r[k];
            for (const k of managed)
                if (s[k] !== undefined && s[k] !== false && s[k] !== "")
                    r[k] = s[k];
            next[s.output] = r;
        }
        for (const k of root.pendingResets) {
            // Zurueck auf Standard; eine Workspace-Gruppe bleibt stehen
            const ws = root.rules[k]?.workspaces;
            if (ws === undefined)
                delete next[k];
            else
                next[k] = { mode: "preferred", position: "auto", scale: "auto", workspaces: ws };
        }
        root.pendingSpecs = [];
        root.pendingResets = [];
        root.previousSpecs = [];
        root.commit(next);
        root.applied++;
        refreshDelay.restart();
    }

    function revert(): void {
        if (!root.confirming)
            return;
        root.countdown = 0;
        const prev = root.previousSpecs;
        root.pendingSpecs = [];
        root.pendingResets = [];
        root.previousSpecs = [];
        root.restore(prev);
    }

    Process {
        id: applyProc

        property bool ask: true

        // Ausgabe erst beim Exit auswerten (die Sammler sind dann komplett):
        // ueber onStreamFinished kaeme ein Fehler womoeglich erst nach dem
        // Start der Frage an
        stdout: StdioCollector {
            id: applyOut
        }
        stderr: StdioCollector {
            id: applyErr
        }
        onExited: (code, status) => {
            const out = applyOut.text.trim();
            const err = applyErr.text.trim();
            if (err !== "")
                root.lastError = err;
            else if (out !== "" && out !== "ok")
                root.lastError = out;
            if (code !== 0 && root.lastError === "")
                root.lastError = "hyprctl eval: Code " + code;
            if (applyProc.ask && root.lastError === "")
                root.countdown = root.confirmSeconds;
            else if (applyProc.ask) {
                // Nichts gilt – nichts zu fragen
                root.pendingSpecs = [];
                root.pendingResets = [];
                root.previousSpecs = [];
            }
            refreshDelay.restart();
        }
    }

    Timer {
        running: root.confirming
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.countdown <= 1)
                root.revert();
            else
                root.countdown--;
        }
    }

    // ---- monitors.lua ----------------------------------------------------

    function commit(next: var): void {
        root.rules = next;
        if (!root.writesHypr)
            return;
        if (!root.rulesWritable) {
            root.lastError = I18n.tr("monitors.lua konnte nicht gelesen werden – nichts gespeichert");
            return;
        }
        saveGuard.restart();
        backupProc.running = true;
    }

    function readRules(): void {
        if (!rulesProc.running)
            rulesProc.running = true;
    }

    // Vorher sichern, dann schreiben (Hyprland laedt die Datei danach selbst
    // neu, monitor-setup.lua wendet sie an)
    Process {
        id: backupProc

        command: ["sh", "-c", 'if [ -f "$1" ]; then cp -f "$1" "$1.bak"; fi', "sh", root.luaPath]
        onExited: luaFile.setText(root.luaText)
    }

    // monitors.lua per lua als JSON lesen: [{ output, … }]; "null" = kaputt,
    // "[]" = fehlt
    Process {
        id: rulesProc

        environment: ({ MONITORS_FILE: root.luaPath })
        command: ["sh", "-c", 'if [ ! -e "$MONITORS_FILE" ]; then echo "[]"; exit 0; fi; '
            + 'L=$(command -v lua || command -v luajit || command -v lua5.4 || command -v lua5.1) || { echo nolua; exit 0; }; '
            + 'exec "$L" -e "$1"', "sh", root.luaDump]

        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                let list = null;
                try {
                    list = t === "nolua" ? null : JSON.parse(t);
                } catch (e) {
                    list = null;
                }
                const next = {};
                for (const m of (Array.isArray(list) ? list : [])) {
                    if (!m || typeof m.output !== "string")
                        continue;
                    const r = Object.assign({}, m);
                    delete r.output;
                    next[m.output] = r;
                }
                root.rules = next;
                root.rulesWritable = Array.isArray(list);
                if (!root.rulesWritable)
                    root.lastError = t === "nolua" ? I18n.tr("Kein lua gefunden – Monitore werden nicht gespeichert")
                                                   : I18n.tr("monitors.lua ist fehlerhaft – Monitore werden nicht gespeichert");
                root.rulesLoaded = true;
                // Regelwerte (vrr) und Schluessel haengen an den Monitoren
                root.refresh();
            }
        }
    }

    readonly property string luaDump: 'local ok, t = pcall(dofile, os.getenv("MONITORS_FILE")) '
        + 'if not ok or type(t) ~= "table" then io.write("null") return end '
        + 'local function s(v) return \'"\' .. tostring(v):gsub(\'[%c"\\\\]\', function(c) return string.format("\\\\u%04x", c:byte()) end) .. \'"\' end '
        + 'local out = {} '
        + 'for _, m in ipairs(t) do if type(m) == "table" and type(m.output) == "string" then '
        + '  local f = {} '
        + '  for k, v in pairs(m) do local tv = type(v) '
        + '    if tv == "string" then f[#f + 1] = s(k) .. ":" .. s(v) '
        + '    elseif tv == "number" or tv == "boolean" then f[#f + 1] = s(k) .. ":" .. tostring(v) end '
        + '  end '
        + '  out[#out + 1] = "{" .. table.concat(f, ",") .. "}" '
        + 'end end '
        + 'io.write("[" .. table.concat(out, ",") .. "]")'

    Timer {
        id: saveGuard

        interval: 800
    }

    FileView {
        id: luaFile

        path: root.luaPath
        watchChanges: true
        printErrors: false
        atomicWrites: true
        // Von Hand oder von install.sh geaendert: neu lesen
        onFileChanged: if (!saveGuard.running) root.readRules()
    }

    // qs -c dynamic-island ipc call monitors list
    IpcHandler {
        target: "monitors"

        function list(): string {
            return JSON.stringify(root.monitors.map(m => ({ name: m.name, key: m.key, mode: root.modeLabel(m.width, m.height, m.refresh), position: `${m.x}x${m.y}`, scale: m.scale, transform: m.transform, vrr: m.vrrMode, disabled: m.disabled, rule: m.rule })), null, 2);
        }
        function rules(): string {
            return root.luaText;
        }
        function refresh(): void {
            root.refresh();
        }
        function keep(): void {
            root.keep();
        }
        function revert(): void {
            root.revert();
        }
    }

    Component.onCompleted: root.readRules()
}
