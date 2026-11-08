pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Tastenkuerzel setzen: was in den Einstellungen (Seite Tastenkürzel,
// KeybindsEditor) geaendert wird und welche Binds die Shell selbst mitbringt.
// Die Uebersicht (KeybindsPanel, SUPER+K) sucht und fuehrt nur aus.
//
//   ~/.config/dynamic-island/keybinds.json   (pro Rechner, wie shell.json)
//     { format: 1,
//       overrides: { <ref>: { keys, canon } | { disabled: true } },
//       custom: [{ id, title, group, exec, keys, disabled }],
//       extra: [{ id, of, keys, disabled }] }
//
// `extra` legt auf einen Bind der Config (of = seine Ref) eine weitere
// Kombination mit derselben Aktion (Einstellungen > Tastenkürzel).
//
// <ref> eines Binds:
//   aus der Hypr-Config   "Gruppe|Text@<modmask>:<taste>"  (Belegung laut Config)
//   aus einem Plugin      "plugin:<id>.<bind>"             (Manifest `keybinds`)
//   eigenes Kuerzel       "custom:<id>"
//   Zusatztaste           "extra:<id>"
//
// Daraus entsteht ~/.local/state/dynamic-island/keybinds.lua, die
// hypr/hyprland.lua beim Laden liest; nach jeder Aenderung wendet
// `hyprctl eval 'sync_keybinds()'` sie live an (ohne Reload). Plugin-Binds
// stehen nur drin, solange das Plugin an ist – so verschwinden sie mit dem
// Plugin aus Hyprland und aus der Uebersicht.
//
// Abhaengigkeit nur plugins -> hier: Plugins.qml setzt `pluginBinds` per
// Binding, dieser Dienst kennt das Plugin-System nicht.
Singleton {
    id: root

    readonly property string path: Quickshell.env("DYNAMIC_ISLAND_KEYBINDS_FILE")
                                   || Quickshell.env("HOME") + "/.config/dynamic-island/keybinds.json"
    readonly property string luaPath: Quickshell.env("DYNAMIC_ISLAND_KEYBINDS_LUA")
                                      || Quickshell.env("HOME") + "/.local/state/dynamic-island/keybinds.lua"
    // Nur die installierte Shell (oder eine mit eigener Lua-Datei) schreibt
    // nach Hyprland. Eine Testkopie mit eigener plugins.json hat sonst die
    // Plugin-Binds der echten Shell geloescht (2026-10-25: SUPER+ALT+D weg) –
    // und die echte schreibt erst wieder, wenn sich ihr Stand aendert.
    readonly property bool writesHypr: !!Quickshell.env("DYNAMIC_ISLAND_KEYBINDS_LUA")
                                       || Quickshell.shellPath("shell.qml") === Quickshell.env("HOME") + "/.config/quickshell/dynamic-island/shell.qml"

    property var data: ({ format: 1, overrides: {}, custom: [], extra: [] })
    property bool loaded: false

    // Von Plugins.qml: [{ ref, pluginId, pluginName, group, title, keys,
    // exec, release, repeating, locked }] aktiver Plugins
    property var pluginBinds: []
    // Erst schreiben, wenn das Plugin-System seinen Zustand kennt – sonst
    // flogen beim Start kurz alle Plugin-Binds raus
    property bool pluginsReady: false

    // Zaehlt jeden Sync hoch; HyprBinds liest danach neu
    property int revision: 0

    // ---- was die Shell bindet -----------------------------------------------

    // Plugin- und eigene Binds und Zusatztasten mit eingerechneten
    // Aenderungen:
    // [{ ref, source: "plugin"|"custom"|"extra", description, group, title,
    //    keys, defaultKeys, canon, exec, disabled, changed, release,
    //    repeating, locked, pluginId, pluginName, of }]
    // Zusatztasten haben kein exec: sie leihen sich die Aktion von `of`
    readonly property var managed: {
        const out = [];
        const overrides = root.data.overrides ?? {};
        for (const b of root.pluginBinds) {
            const o = overrides[b.ref] ?? {};
            const keys = o.keys ?? b.keys;
            out.push({
                ref: b.ref,
                source: "plugin",
                group: b.group,
                title: b.title,
                description: `${b.group}|${b.title}`,
                keys,
                defaultKeys: b.keys,
                canon: root.canonOf(keys),
                exec: b.exec,
                disabled: o.disabled === true,
                changed: o.keys !== undefined,
                release: !!b.release,
                repeating: !!b.repeating,
                locked: !!b.locked,
                pluginId: b.pluginId,
                pluginName: b.pluginName
            });
        }
        for (const c of root.data.custom ?? []) {
            if (!c?.keys || !c?.exec)
                continue;
            const group = c.group || "Eigene";
            out.push({
                ref: `custom:${c.id}`,
                source: "custom",
                group,
                title: c.title,
                description: `${group}|${c.title}`,
                keys: c.keys,
                defaultKeys: c.keys,
                canon: root.canonOf(c.keys),
                exec: c.exec,
                disabled: c.disabled === true,
                changed: false,
                release: false,
                repeating: false,
                locked: false,
                pluginId: "",
                pluginName: ""
            });
        }
        for (const e of root.data.extra ?? []) {
            if (!e?.keys || !e?.of)
                continue;
            const description = root.descriptionOf(e.of);
            const [group, title] = description.split("|");
            out.push({
                ref: `extra:${e.id}`,
                source: "extra",
                group: group ?? "",
                title: title ?? "",
                description,
                keys: e.keys,
                defaultKeys: e.keys,
                canon: root.canonOf(e.keys),
                exec: "",
                disabled: e.disabled === true,
                changed: false,
                release: false,
                repeating: false,
                locked: false,
                pluginId: "",
                pluginName: "",
                of: e.of
            });
        }
        return out;
    }

    // "Gruppe|Text@64:q" -> "Gruppe|Text"
    function descriptionOf(ref: string): string {
        const at = ref.lastIndexOf("@");
        return at < 0 ? ref : ref.slice(0, at);
    }

    // "<beschreibung>@<canon>" -> Eintrag aus `managed`
    readonly property var managedIndex: {
        const out = {};
        for (const m of root.managed)
            out[`${m.description}@${m.canon}`] = m;
        return out;
    }

    // Ref eines Binds aus `hyprctl binds -j`. Fuer Binds der Config steht in
    // der Ref die Belegung laut Config; ist er neu belegt, zeigt Hyprland die
    // neue – dann ueber die gespeicherte Aenderung zurueckfinden.
    function refFor(description: string, canon: string): string {
        const m = root.managedIndex[`${description}@${canon}`];
        if (m)
            return m.ref;
        const overrides = root.data.overrides ?? {};
        const prefix = description + "@";
        for (const ref in overrides)
            if (ref.startsWith(prefix) && overrides[ref].canon === canon)
                return ref;
        return prefix + canon;
    }

    // { source, disabled, changed, defaultKeys, pluginName } zu einer Ref
    function stateOf(ref: string): var {
        const m = root.managed.find(x => x.ref === ref);
        if (m)
            return m;
        const o = root.data.overrides?.[ref] ?? {};
        return {
            source: "config",
            disabled: o.disabled === true,
            changed: o.keys !== undefined,
            defaultKeys: "",
            pluginName: ""
        };
    }

    // ---- aendern --------------------------------------------------------------

    function setKeys(ref: string, keys: string): void {
        const next = root.copyData();
        if (ref.startsWith("custom:")) {
            next.custom = next.custom.map(c => `custom:${c.id}` === ref ? Object.assign({}, c, { keys }) : c);
            root.commit(next);
            return;
        }
        if (ref.startsWith("extra:")) {
            next.extra = next.extra.map(e => `extra:${e.id}` === ref ? Object.assign({}, e, { keys }) : e);
            root.commit(next);
            return;
        }
        const canon = root.canonOf(keys);
        const o = Object.assign({}, next.overrides[ref] ?? {});
        // Zurueck auf die Vorgabe = keine Aenderung mehr
        if (canon === root.defaultCanonOf(ref)) {
            delete o.keys;
            delete o.canon;
        } else {
            o.keys = keys;
            o.canon = canon;
        }
        root.putOverride(next, ref, o);
        root.commit(next);
    }

    function setDisabled(ref: string, disabled: bool): void {
        const next = root.copyData();
        if (ref.startsWith("custom:")) {
            next.custom = next.custom.map(c => `custom:${c.id}` === ref ? Object.assign({}, c, { disabled }) : c);
            root.commit(next);
            return;
        }
        if (ref.startsWith("extra:")) {
            next.extra = next.extra.map(e => `extra:${e.id}` === ref ? Object.assign({}, e, { disabled }) : e);
            root.commit(next);
            return;
        }
        const o = Object.assign({}, next.overrides[ref] ?? {});
        if (disabled)
            o.disabled = true;
        else
            delete o.disabled;
        root.putOverride(next, ref, o);
        root.commit(next);
    }

    // Belegung und an/aus zurueck auf die Vorgabe
    function reset(ref: string): void {
        const next = root.copyData();
        delete next.overrides[ref];
        root.commit(next);
    }

    // Gibt die Ref des neuen Kuerzels zurueck ("custom:k3")
    function addCustom(title: string, exec: string, keys: string): string {
        const next = root.copyData();
        let n = next.custom.length + 1;
        while (next.custom.some(c => c.id === `k${n}`))
            n++;
        const id = `k${n}`;
        next.custom.push({ id, title: root.uniqueTitle(next.custom, title, id), group: "Eigene", exec, keys, disabled: false });
        root.commit(next);
        return `custom:${id}`;
    }

    // Die Beschreibung "Eigene|<Titel>" ist zugleich der Schluessel der
    // Aktion in Hyprland (run_keybind) – zwei gleiche Titel wuerden zu einem
    // Befehl verschmelzen. Darum "Titel (2)" usw.
    function uniqueTitle(custom: var, title: string, ownId: string): string {
        const base = title.replace(/\|/g, "/").trim() || "Kürzel";
        const taken = t => custom.some(c => c.id !== ownId && c.title === t);
        let out = base;
        for (let i = 2; taken(out); i++)
            out = `${base} (${i})`;
        return out;
    }

    function removeCustom(ref: string): void {
        const next = root.copyData();
        next.custom = next.custom.filter(c => `custom:${c.id}` !== ref);
        next.extra = next.extra.filter(e => `extra:${e.id}` !== ref);
        root.commit(next);
    }

    // Weitere Kombination fuer einen Bind der Config (ref "Gruppe|Text@…")
    // Gibt die Ref der Zusatztaste zurueck ("extra:x2")
    function addExtra(of: string, keys: string): string {
        const next = root.copyData();
        let n = next.extra.length + 1;
        while (next.extra.some(e => e.id === `x${n}`))
            n++;
        next.extra.push({ id: `x${n}`, of, keys, disabled: false });
        root.commit(next);
        return `extra:x${n}`;
    }

    // Eigenes Kuerzel: Name/Befehl aendern
    function editCustom(ref: string, title: string, exec: string): void {
        const next = root.copyData();
        next.custom = next.custom.map(c => `custom:${c.id}` === ref
            ? Object.assign({}, c, { title: root.uniqueTitle(next.custom, title, c.id), exec }) : c);
        root.commit(next);
    }

    function putOverride(next: var, ref: string, o: var): void {
        if (Object.keys(o).length === 0)
            delete next.overrides[ref];
        else
            next.overrides[ref] = o;
    }

    function defaultCanonOf(ref: string): string {
        const m = root.managed.find(x => x.ref === ref);
        if (m)
            return root.canonOf(m.defaultKeys);
        const at = ref.lastIndexOf("@");
        return at < 0 ? "" : ref.slice(at + 1);
    }

    // ---- Tasten ---------------------------------------------------------------

    readonly property var modBits: ({
        SHIFT: 1, CTRL: 4, CONTROL: 4, ALT: 8, MOD1: 8, SUPER: 64, WIN: 64, LOGO: 64, MOD4: 64, META: 64
    })

    // "SUPER + ALT + W" -> "72:w" (wie die Ref aus hypr/hyprland.lua)
    function canonOf(keys: string): string {
        let mods = 0;
        let key = "";
        for (const part of String(keys).split("+").map(p => p.trim()).filter(p => p !== "")) {
            const bit = root.modBits[part.toUpperCase()];
            if (bit !== undefined)
                mods |= bit;
            else
                key = part.toLowerCase();
        }
        return `${mods}:${key}`;
    }

    // Qt-Taste -> xkb-Name fuer Hyprland. Mit Shift liefert Qt das
    // geshiftete Zeichen ("!" statt 1); Hyprland vergleicht aber die Taste
    // ohne Modifier – deshalb die Rueckuebersetzung fuer das deutsche Layout.
    readonly property var qtKeys: ({
        [Qt.Key_Left]: "left", [Qt.Key_Right]: "right", [Qt.Key_Up]: "up", [Qt.Key_Down]: "down",
        [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Escape]: "Escape",
        [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Tab", [Qt.Key_Space]: "space",
        [Qt.Key_Backspace]: "BackSpace", [Qt.Key_Delete]: "Delete", [Qt.Key_Insert]: "Insert",
        [Qt.Key_Home]: "Home", [Qt.Key_End]: "End", [Qt.Key_PageUp]: "Prior", [Qt.Key_PageDown]: "Next",
        [Qt.Key_Print]: "Print", [Qt.Key_Pause]: "Pause",
        [Qt.Key_Comma]: "comma", [Qt.Key_Semicolon]: "comma",
        [Qt.Key_Period]: "period", [Qt.Key_Colon]: "period",
        [Qt.Key_Minus]: "minus", [Qt.Key_Underscore]: "minus",
        [Qt.Key_Plus]: "plus", [Qt.Key_Asterisk]: "plus",
        [Qt.Key_NumberSign]: "numbersign", [Qt.Key_Apostrophe]: "numbersign",
        [Qt.Key_Less]: "less", [Qt.Key_Greater]: "less",
        [Qt.Key_Exclam]: "1", [Qt.Key_QuoteDbl]: "2", [Qt.Key_section]: "3", [Qt.Key_Dollar]: "4",
        [Qt.Key_Percent]: "5", [Qt.Key_Ampersand]: "6", [Qt.Key_Slash]: "7", [Qt.Key_ParenLeft]: "8",
        [Qt.Key_ParenRight]: "9", [Qt.Key_Equal]: "0", [Qt.Key_Question]: "ssharp",
        [Qt.Key_ssharp]: "ssharp", [Qt.Key_Adiaeresis]: "adiaeresis",
        [Qt.Key_Odiaeresis]: "odiaeresis", [Qt.Key_Udiaeresis]: "udiaeresis",
        [Qt.Key_VolumeUp]: "XF86AudioRaiseVolume", [Qt.Key_VolumeDown]: "XF86AudioLowerVolume",
        [Qt.Key_VolumeMute]: "XF86AudioMute", [Qt.Key_MicMute]: "XF86AudioMicMute",
        [Qt.Key_MediaPlay]: "XF86AudioPlay", [Qt.Key_MediaTogglePlayPause]: "XF86AudioPlay",
        [Qt.Key_MediaPause]: "XF86AudioPause", [Qt.Key_MediaStop]: "XF86AudioStop",
        [Qt.Key_MediaNext]: "XF86AudioNext", [Qt.Key_MediaPrevious]: "XF86AudioPrev",
        [Qt.Key_MonBrightnessUp]: "XF86MonBrightnessUp", [Qt.Key_MonBrightnessDown]: "XF86MonBrightnessDown",
        [Qt.Key_Calculator]: "XF86Calculator"
    })

    readonly property var modifierKeys: [
        Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Control, Qt.Key_Shift,
        Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_NumLock, Qt.Key_Hyper_L, Qt.Key_Hyper_R
    ]

    // Ziffernblock: Qt meldet dieselben Tasten wie im Hauptblock und setzt
    // nur KeypadModifier – Hyprland unterscheidet aber KP_7 von 7
    readonly property var keypadKeys: ({
        [Qt.Key_0]: "KP_0", [Qt.Key_1]: "KP_1", [Qt.Key_2]: "KP_2", [Qt.Key_3]: "KP_3",
        [Qt.Key_4]: "KP_4", [Qt.Key_5]: "KP_5", [Qt.Key_6]: "KP_6", [Qt.Key_7]: "KP_7",
        [Qt.Key_8]: "KP_8", [Qt.Key_9]: "KP_9",
        [Qt.Key_Slash]: "KP_Divide", [Qt.Key_Asterisk]: "KP_Multiply", [Qt.Key_Minus]: "KP_Subtract",
        [Qt.Key_Plus]: "KP_Add", [Qt.Key_Enter]: "KP_Enter", [Qt.Key_Return]: "KP_Enter",
        [Qt.Key_Comma]: "KP_Decimal", [Qt.Key_Period]: "KP_Decimal",
        [Qt.Key_Home]: "KP_Home", [Qt.Key_End]: "KP_End", [Qt.Key_Up]: "KP_Up", [Qt.Key_Down]: "KP_Down",
        [Qt.Key_Left]: "KP_Left", [Qt.Key_Right]: "KP_Right", [Qt.Key_PageUp]: "KP_Prior",
        [Qt.Key_PageDown]: "KP_Next", [Qt.Key_Insert]: "KP_Insert", [Qt.Key_Delete]: "KP_Delete",
        [Qt.Key_Clear]: "KP_Begin"
    })

    // Was Qt sonst noch liefert: Dead Keys (^ ´ `), AltGr-Zeichen, Menue,
    // Rollen. AltGr-Zeichen bindet Hyprland unter ihrem eigenen Namen
    // (CTRL + SUPER + backslash in simple.lua)
    readonly property var otherKeys: ({
        [Qt.Key_Dead_Circumflex]: "dead_circumflex", [Qt.Key_AsciiCircum]: "dead_circumflex",
        [Qt.Key_Dead_Acute]: "dead_acute", [Qt.Key_Dead_Grave]: "dead_acute", [Qt.Key_acute]: "dead_acute",
        [Qt.Key_QuoteLeft]: "dead_acute",
        [Qt.Key_Backslash]: "backslash", [Qt.Key_At]: "at", [Qt.Key_BraceLeft]: "braceleft",
        [Qt.Key_BraceRight]: "braceright", [Qt.Key_BracketLeft]: "bracketleft",
        [Qt.Key_BracketRight]: "bracketright", [Qt.Key_AsciiTilde]: "asciitilde", [Qt.Key_Bar]: "bar",
        [Qt.Key_mu]: "mu", [Qt.Key_twosuperior]: "twosuperior", [Qt.Key_threesuperior]: "threesuperior",
        [Qt.Key_degree]: "dead_circumflex",
        [Qt.Key_Menu]: "Menu", [Qt.Key_ScrollLock]: "Scroll_Lock"
    })

    // Tastendruck -> { keys: "SUPER + ALT + W" } | { wait: true } (nur
    // Modifier gedrueckt) | { error }
    function fromEvent(event: var): var {
        if (root.modifierKeys.includes(event.key))
            return { wait: true };
        const mods = [];
        if (event.modifiers & Qt.MetaModifier)
            mods.push("SUPER");
        if (event.modifiers & Qt.ControlModifier)
            mods.push("CTRL");
        if (event.modifiers & Qt.AltModifier)
            mods.push("ALT");
        if (event.modifiers & Qt.ShiftModifier)
            mods.push("SHIFT");

        let key = (event.modifiers & Qt.KeypadModifier) ? root.keypadKeys[event.key] : undefined;
        if (!key)
            key = root.qtKeys[event.key] ?? root.otherKeys[event.key];
        if (!key && event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
            key = String.fromCharCode(event.key);
        else if (!key && event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
            key = String.fromCharCode(event.key);
        else if (!key && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35)
            key = `F${event.key - Qt.Key_F1 + 1}`;
        if (!key)
            return { error: "Diese Taste kennt die Shell nicht" };

        // Ohne Modifier nur Tasten, die beim Tippen nicht fehlen
        const standalone = /^(F\d+|XF86\w+|Print|Pause|Insert)$/.test(key);
        if (mods.length === 0 && !standalone)
            return { error: "Ohne Super/Strg/Alt nur F-Tasten, Druck und Medientasten" };
        if (mods.length === 1 && mods[0] === "SHIFT" && !standalone)
            return { error: "Nur Shift reicht nicht – das braucht man zum Tippen" };

        return { keys: mods.concat([key]).join(" + ") };
    }

    // ---- Aufnahme -------------------------------------------------------------

    // Waehrend eine neue Kombination abgefragt wird, steht Hyprland in einer
    // Submap ohne Binds (hypr/hyprland.lua, keybind_capture) – sonst kaemen
    // SUPER-Kombinationen nie bei der Shell an
    property bool capturing: false

    // Testkopien (writesHypr = false) lassen Hyprland in Ruhe
    function startCapture(): void {
        root.capturing = true;
        if (root.writesHypr)
            Quickshell.execDetached(["hyprctl", "eval", "keybind_capture(true)"]);
    }

    function stopCapture(): void {
        if (!root.capturing)
            return;
        root.capturing = false;
        if (root.writesHypr)
            Quickshell.execDetached(["hyprctl", "eval", "keybind_capture(false)"]);
    }

    // ---- Lua-Datei --------------------------------------------------------------

    function luaString(s: var): string {
        return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")
                              .replace(/\r/g, "\\r").replace(/\0/g, "\\0") + '"';
    }

    readonly property string luaText: {
        const L = root.luaString;
        const lines = ["-- Erzeugt von der dynamic-island-Shell (modules/services/hypr/Keybinds.qml).",
                       "-- Nicht von Hand aendern: Quelle ist ~/.config/dynamic-island/keybinds.json", "return {", "\toverrides = {"];
        const overrides = root.data.overrides ?? {};
        for (const ref of Object.keys(overrides).sort()) {
            // Plugin-Aenderungen stecken schon in `binds`
            if (ref.startsWith("plugin:"))
                continue;
            const o = overrides[ref];
            const fields = [];
            if (o.keys)
                fields.push(`keys = ${L(o.keys)}`);
            if (o.disabled)
                fields.push("disabled = true");
            if (fields.length > 0)
                lines.push(`\t\t[${L(ref)}] = { ${fields.join(", ")} },`);
        }
        lines.push("\t},", "\tbinds = {");
        for (const m of root.managed) {
            if (m.source === "extra")
                continue;
            const fields = [`keys = ${L(m.keys)}`, `exec = ${L(m.exec)}`, `description = ${L(m.description)}`];
            for (const flag of ["disabled", "release", "repeating", "locked"])
                if (m[flag])
                    fields.push(`${flag} = true`);
            lines.push(`\t\t{ ${fields.join(", ")} },`);
        }
        lines.push("\t},", "\textra = {");
        for (const m of root.managed) {
            if (m.source !== "extra")
                continue;
            lines.push(`\t\t{ of = ${L(m.of)}, keys = ${L(m.keys)}${m.disabled ? ", disabled = true" : ""} },`);
        }
        lines.push("\t},", "}", "");
        return lines.join("\n");
    }

    onLuaTextChanged: if (root.loaded && root.pluginsReady) writeDelay.restart()
    onPluginsReadyChanged: if (root.loaded && root.pluginsReady) writeDelay.restart()
    onLoadedChanged: if (root.loaded && root.pluginsReady) writeDelay.restart()

    // Beim Start kommen die Plugins nacheinander – erst schreiben, wenn
    // sich nichts mehr tut
    Timer {
        id: writeDelay

        interval: 300
        onTriggered: {
            if (!root.writesHypr || luaFile.text() === root.luaText) {
                // Hyprland hat beim Laden schon diesen Stand gelesen
                root.revision++;
                return;
            }
            luaFile.setText(root.luaText);
            syncProc.running = false;
            syncProc.running = true;
        }
    }

    FileView {
        id: luaFile

        path: root.luaPath
        blockLoading: true
        // Erst fertig schreiben, dann sync_keybinds() – sonst las Lua
        // womoeglich noch den alten Stand
        blockWrites: true
        printErrors: false
        atomicWrites: true
    }

    Process {
        id: syncProc

        command: ["hyprctl", "eval", "sync_keybinds()"]
        onExited: root.revision++
    }

    // ---- keybinds.json ------------------------------------------------------

    function copyData(): var {
        return {
            format: 1,
            overrides: Object.assign({}, root.data.overrides ?? {}),
            custom: (root.data.custom ?? []).slice(),
            extra: (root.data.extra ?? []).slice()
        };
    }

    function commit(next: var): void {
        root.data = next;
        saveGuard.restart();
        jsonFile.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function readData(): void {
        let parsed;
        try {
            parsed = JSON.parse(jsonFile.text() || "{}");
        } catch (e) {
            return;
        }
        root.data = {
            format: 1,
            overrides: parsed.overrides ?? {},
            custom: Array.isArray(parsed.custom) ? parsed.custom : [],
            extra: Array.isArray(parsed.extra) ? parsed.extra : []
        };
        root.loaded = true;
    }

    // Wie in Plugins.qml: nach setText meldet der Watcher kurz den alten Stand
    Timer {
        id: saveGuard

        interval: 400
    }

    FileView {
        id: jsonFile

        path: root.path
        watchChanges: true
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: if (!saveGuard.running) root.readData()
        onLoadFailed: root.loaded = true
        onFileChanged: if (!saveGuard.running) reload()
    }

    // qs -c dynamic-island ipc call keybinds set 'Apps|Terminal@64:q' 'SUPER + T'
    IpcHandler {
        target: "keybinds"

        function list(): string {
            return JSON.stringify(root.data, null, 2);
        }
        function set(ref: string, keys: string): void { root.setKeys(ref, keys); }
        function disable(ref: string): void { root.setDisabled(ref, true); }
        function enable(ref: string): void { root.setDisabled(ref, false); }
        function reset(ref: string): void { root.reset(ref); }
        function add(title: string, exec: string, keys: string): void { root.addCustom(title, exec, keys); }
        function addExtra(of: string, keys: string): void { root.addExtra(of, keys); }
        function remove(ref: string): void { root.removeCustom(ref); }
    }

    // Shell beendet/neu geladen mitten in der Aufnahme: Hyprland nicht in
    // der leeren Submap lassen
    Component.onDestruction: root.stopCapture()
}
