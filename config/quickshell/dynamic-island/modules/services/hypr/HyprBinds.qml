pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs
import "keysource.js" as KeySource

// Tastenkuerzel aus Hyprland fuer die Uebersicht (KeybindsPanel) und die
// Einstellungsseite Tastenkürzel (KeybindsEditor).
//
// Quelle ist `hyprctl binds -j`, nicht eine eigene Liste: die Binds tragen in
// hypr/profiles/simple.lua eine Beschreibung "Gruppe|Text" (optional
// "|Anzeige" statt der echten Taste, z.B. "1 … 0", und "|Anzeige|Einzeln"
// = Name dieses einen Binds). Nur beschriebene Binds erscheinen. Gleicher
// Text in derselben Gruppe wird in der Uebersicht eine Zeile mit mehreren
// Kuerzeln (Medientaste + Ersatzkuerzel); Binds mit derselben Anzeige
// ("Pfeile") dort nur einmal.
//
// Fuer die Einstellungen: `commands` = jeder Befehl (gleiche Beschreibung)
// einzeln mit all seinen Tasten, dazu `unnamed` (Binds ohne Beschreibung,
// nur fuer die Tastatur-Vorschau) und `origins` (wo der Bind in der Config
// steht und was er tut, siehe keysource.js).
//
// Gelesen wird beim Oeffnen der Uebersicht (refresh) und nach jedem
// `hyprctl reload`, solange schon einmal gelesen wurde.
//
// Setzen: Keybinds.qml haelt Aenderungen (neu belegt, abgeschaltet) und die
// Binds der Plugins/eigenen Kuerzel; jede Taste einer Zeile traegt dafuer ihre
// Ref. Nach jedem Sync dort (Keybinds.revision) wird neu gelesen.
//
// Ausfuehren (run): hypr/hyprland.lua legt die Aktion jedes beschriebenen
// Binds unter seiner Beschreibung ab, `hyprctl eval` ruft sie im laufenden
// Hyprland auf. Nicht anklickbar sind Maus-Binds (Ziehen/Groesse) und
// Sammelzeilen mit eigener Anzeige ("1 … 0", "Pfeile") – ein Klick wuerde
// dort nur einen der Binds ausloesen.
Singleton {
    id: root

    // [{ name, entries: [{ text, id, clickable, editable, disabled, changed,
    //    source, pluginName, combos: [{ keys: ["Super", "Q"], ref, canon,
    //    editable, disabled, changed, source }] }] }]
    // source: "config" | "plugin" | "custom"; disabled = alle Tasten aus
    property var groups: []
    property bool loaded: false

    // [{ id, group, text, part, title, label, source, pluginName, runnable,
    //    custom: { title, exec } | null,
    //    combos: [{ keys: ["Super", "Q"], keysText: "SUPER + Q", ref, canon,
    //               modmask, key, editable, disabled, changed, source, mouse }] }]
    // id = Beschreibung (zum Ausfuehren), title = Einzelname oder Text
    property var commands: []
    // Binds ohne Beschreibung: [{ canon, modmask, key, mouse }]
    property var unnamed: []

    // Alle Binds der Grundebene (auch unbeschriebene) fuer die
    // Konfliktpruefung: [{ canon, text, ref }]
    property var all: []

    // Kommt waehrend des Lesens eine Aenderung, danach gleich noch einmal
    property bool stale: false

    function refresh(): void {
        if (Object.keys(root.origins.refs).length === 0)
            root.refreshOrigins();
        if (proc.running)
            root.stale = true;
        else
            proc.running = true;
    }

    function run(entry: var): void {
        if (!entry?.clickable)
            return;
        root.runId(entry.id);
    }

    // Befehl aus `commands` ausfuehren (Maus-Binds wie Ziehen gehen nicht)
    function runCommand(command: var): void {
        if (command?.runnable)
            root.runId(command.id);
    }

    function runId(id: string): void {
        // Lange Lua-Klammern: die Beschreibung darf so jedes Zeichen enthalten
        // ausser der schliessenden Folge selbst
        Quickshell.execDetached(["hyprctl", "eval", `run_keybind([==[${id}]==])`]);
    }

    // ---- Herkunft (Einstellungen) -------------------------------------------

    readonly property string originPath: Quickshell.env("HOME") + "/.local/state/dynamic-island/keybinds-origin.tsv"
    // { refs: { <ref>: { file, line } }, files: { <pfad>: <inhalt> } }
    property var origins: ({ refs: {}, files: {} })

    // Wo ein Bind der Config steht und was er tut:
    // { file, line, keys, action: { kind, text, source } } | null
    function originOf(ref: string): var {
        const o = root.origins.refs[ref];
        if (!o)
            return null;
        const found = KeySource.actionAt(root.origins.files[o.file] ?? "", o.line);
        return { file: o.file, line: o.line, keys: found?.keys ?? "", action: found?.action ?? null };
    }

    // Was ein Befehl tut, fuer jede Quelle: { kind, text } | null
    function actionOf(command: var): var {
        if (!command)
            return null;
        if (command.custom)
            return { kind: "exec", text: command.custom.exec };
        const plugin = command.combos.find(c => c.source === "plugin");
        if (plugin)
            return { kind: "exec", text: Keybinds.stateOf(plugin.ref).exec ?? "" };
        const config = command.combos.find(c => c.source === "config");
        return config ? root.originOf(config.ref)?.action ?? null : null;
    }

    function refreshOrigins(): void {
        originProc.running = false;
        originProc.running = true;
    }

    Process {
        id: originProc

        // TSV, danach jede genannte Datei einmal ("\x1e<pfad>\n<inhalt>")
        command: ["sh", "-c", "[ -r \"$1\" ] || exit 0; cat \"$1\"; cut -f2 \"$1\" | sort -u | while IFS= read -r f; do [ -r \"$f\" ] && printf '\\036%s\\n' \"$f\" && cat \"$f\"; done", "sh", root.originPath]
        stdout: StdioCollector {
            onStreamFinished: root.origins = KeySource.parseOrigins(this.text)
        }
    }

    // Reihenfolge wie auf der Tastatur ueblich
    readonly property var modBits: [
        { bit: 64, name: "Super" },
        { bit: 4, name: "Strg" },
        { bit: 8, name: "Alt" },
        { bit: 1, name: "Shift" }
    ]

    readonly property var keyNames: ({
        left: "←", right: "→", up: "↑", down: "↓",
        comma: ",", period: ".", backslash: "\\", minus: "-", plus: "+",
        space: "Leertaste", tab: "Tab", escape: "Esc", return: "Enter",
        print: "Druck", delete: "Entf",
        backspace: "Rück", insert: "Einfg", home: "Pos1", end: "Ende", prior: "Bild↑", next: "Bild↓",
        page_up: "Bild↑", page_down: "Bild↓", scroll_lock: "Rollen", pause: "Pause", menu: "Menü",
        caps_lock: "Feststell", num_lock: "Num",
        ssharp: "ß", dead_circumflex: "^", asciicircum: "^", dead_acute: "´", dead_grave: "`",
        less: "<", numbersign: "#", adiaeresis: "Ä", odiaeresis: "Ö", udiaeresis: "Ü",
        at: "@", bar: "|", asciitilde: "~", braceleft: "{", braceright: "}",
        bracketleft: "[", bracketright: "]", eurosign: "€", mu: "µ", twosuperior: "²", threesuperior: "³",
        kp_divide: "Num /", kp_multiply: "Num *", kp_subtract: "Num -", kp_add: "Num +",
        kp_enter: "Num Enter", kp_decimal: "Num ,", kp_separator: "Num ,",
        kp_0: "Num 0", kp_1: "Num 1", kp_2: "Num 2", kp_3: "Num 3", kp_4: "Num 4",
        kp_5: "Num 5", kp_6: "Num 6", kp_7: "Num 7", kp_8: "Num 8", kp_9: "Num 9",
        kp_insert: "Num 0", kp_end: "Num 1", kp_down: "Num 2", kp_next: "Num 3", kp_left: "Num 4",
        kp_begin: "Num 5", kp_right: "Num 6", kp_home: "Num 7", kp_up: "Num 8", kp_prior: "Num 9",
        kp_delete: "Num ,",
        "mouse:272": "Linksklick", "mouse:273": "Rechtsklick", "mouse:274": "Mittelklick",
        mouse_down: "Rad ↓", mouse_up: "Rad ↑",
        xf86audiomute: "Stumm-Taste", xf86audiomicmute: "Mikro-Taste",
        xf86audioraisevolume: "Lauter-Taste", xf86audiolowervolume: "Leiser-Taste",
        xf86monbrightnessup: "Heller-Taste", xf86monbrightnessdown: "Dunkler-Taste",
        xf86audioplay: "Play-Taste", xf86audionext: "Weiter-Taste", xf86audioprev: "Zurück-Taste"
    })

    function keyLabel(key: string): string {
        const known = root.keyNames[key.toLowerCase()];
        if (known)
            return I18n.tr(known);
        // Modifier allein (SUPER loslassen): die Modmaske nennt ihn schon
        if (/^(super|control|alt|shift)_[lr]$/i.test(key))
            return "";
        return key.length === 1 ? key.toUpperCase() : key;
    }

    // Wie die Ref in hypr/hyprland.lua: "<modmask>:<taste klein>"
    function canonOf(bind: var): string {
        return bind.key === "" ? `${bind.modmask}:code:${bind.keycode}` : `${bind.modmask}:${bind.key.toLowerCase()}`;
    }

    // Wer die Kombination schon hat (abgeschaltete zaehlen nicht), ausser
    // der Bind `exceptRef` selbst. "" = frei
    function conflict(canon: string, exceptRef: string): string {
        for (const b of root.all)
            if (b.canon === canon && b.ref !== exceptRef && !Keybinds.stateOf(b.ref).disabled)
                return b.text;
        return "";
    }

    // Einschalten/Zuruecksetzen mit Konfliktpruefung: "" = erledigt, sonst
    // Fehlermeldung (die Kombination hat inzwischen ein anderer Bind)
    function enableChecked(ref: string): string {
        const own = root.all.find(b => b.ref === ref);
        const clash = own ? root.conflict(own.canon, ref) : "";
        if (clash !== "")
            return I18n.tr("Schon belegt: %1").arg(clash);
        Keybinds.setDisabled(ref, false);
        return "";
    }

    function resetChecked(ref: string): string {
        const canon = Keybinds.defaultCanonOf(ref);
        const clash = canon ? root.conflict(canon, ref) : "";
        if (clash !== "")
            return I18n.tr("Schon belegt: %1").arg(clash);
        Keybinds.reset(ref);
        return "";
    }

    // Wie in der Config: "SUPER + ALT + W" (fuer Keybinds.setKeys)
    function keysText(bind: var): string {
        const names = { 64: "SUPER", 4: "CTRL", 8: "ALT", 1: "SHIFT" };
        const keys = root.modBits.filter(m => bind.modmask & m.bit).map(m => names[m.bit]);
        keys.push(bind.key === "" ? `code:${bind.keycode}` : bind.key);
        return keys.join(" + ");
    }

    function combo(bind: var, label: string): var {
        const keys = root.modBits.filter(m => bind.modmask & m.bit).map(m => I18n.tr(m.name));
        const key = label ? I18n.tr(label) : root.keyLabel(bind.key);
        if (key)
            keys.push(key);
        return keys;
    }

    // Rohtext des letzten Laufs (mit Sprache). Die Uebersicht liest bei
    // jedem Oeffnen neu; ein unveraenderter Stand baute sonst alle ~140
    // Zeilen mitten in der Oeffnen-Animation neu auf (~50 ms).
    property string lastText: ""

    function parse(text: string): void {
        // Mit Keybinds.revision: an/aus aendert `hyprctl binds -j` nicht
        const key = I18n.language + "\n" + Keybinds.revision + "\n" + text;
        if (root.loaded && key === root.lastText)
            return;
        root.lastText = key;

        let binds = [];
        try {
            binds = JSON.parse(text);
        } catch (e) {
            console.warn("HyprBinds: hyprctl binds -j nicht lesbar:", e);
            return;
        }

        const order = [];
        const byName = {};
        const all = [];
        const commands = [];
        const byId = {};
        const unnamed = [];
        for (const bind of binds) {
            if (bind.submap !== "")
                continue;
            const canon = root.canonOf(bind);
            const parts = (bind.description ?? "").split("|");
            const key = bind.key === "" ? `code:${bind.keycode}` : bind.key.toLowerCase();
            // Ziehen/Groesse (mouse:272 …): hyprctl meldet bei Lua-Binds
            // `mouse: false`, deshalb auch an der Taste erkennen. Das Mausrad
            // (mouse_up/down) ist ein normaler Bind.
            const drag = bind.mouse || key.startsWith("mouse:");
            if (parts.length < 2) {
                all.push({ canon, text: I18n.tr("einem Bind ohne Beschreibung"), ref: "" });
                unnamed.push({ canon, modmask: bind.modmask, key, mouse: drag });
                continue;
            }
            const groupName = parts[0];
            const text = parts[1];
            const label = parts[2] ?? "";
            const part = parts[3] ?? "";
            const ref = Keybinds.refFor(bind.description, canon);
            const state = Keybinds.stateOf(ref);
            all.push({ canon, text: `${I18n.tr(groupName)} › ${I18n.tr(part || text)}`, ref });

            // Einstellungen: jeder Befehl einzeln, mit seinen echten Tasten
            let command = byId[bind.description];
            if (!command) {
                command = byId[bind.description] = {
                    id: bind.description,
                    group: groupName,
                    text,
                    part: part ?? "",
                    title: part || text,
                    label: label ?? "",
                    source: "config",
                    pluginName: "",
                    runnable: !drag,
                    custom: null,
                    combos: []
                };
                commands.push(command);
            }
            const realKeys = root.combo(bind, "");
            command.combos.push({
                keys: realKeys,
                keysText: root.keysText(bind),
                ref,
                canon,
                modmask: bind.modmask,
                key,
                editable: !drag,
                disabled: state.disabled,
                changed: state.changed,
                source: state.source,
                mouse: drag
            });

            let group = byName[groupName];
            if (!group) {
                group = byName[groupName] = { name: groupName, entries: [] };
                order.push(group);
            }

            // Sammelzeilen ("1 … 0") stehen fuer mehrere Binds, nur einer
            // traegt die Beschreibung – neu belegen wuerde nur ihn treffen
            // Zusatztasten zu Sammelzeilen ("1 … 0") zeigen ihre echte Taste
            const extra = state.source === "extra";
            const combo = {
                keys: root.combo(bind, extra ? "" : (label ?? "")),
                label: label ?? "",
                modmask: bind.modmask,
                ref,
                canon,
                editable: !label && !drag,
                disabled: state.disabled,
                changed: state.changed,
                source: state.source
            };
            const entry = group.entries.find(e => e.text === text);
            if (entry) {
                // Sammelzeile: "Super + Pfeile" nur einmal, auch wenn jede
                // Richtung ein eigener Bind ist
                const same = label && !extra && entry.combos.find(c => c.label === label && c.modmask === bind.modmask && c.source !== "extra");
                if (same) {
                    same.disabled = same.disabled && combo.disabled;
                    same.changed = same.changed || combo.changed;
                } else {
                    entry.combos.push(combo);
                }
            } else
                group.entries.push({
                    text,
                    id: bind.description,
                    clickable: !label && !drag,
                    source: state.source,
                    pluginName: state.pluginName ?? "",
                    combos: [combo]
                });
        }

        for (const group of order)
            for (const entry of group.entries) {
                entry.editable = entry.combos.some(c => c.editable);
                entry.disabled = entry.combos.every(c => c.disabled);
                entry.changed = entry.combos.some(c => c.changed || c.disabled);
            }

        // Quelle eines Befehls = die seiner eigentlichen Taste (nicht die
        // einer Zusatztaste)
        for (const command of commands) {
            const main = command.combos.find(x => x.source !== "extra") ?? command.combos[0];
            const state = Keybinds.stateOf(main.ref);
            command.source = main.source === "extra" ? "config" : main.source;
            command.pluginName = state.pluginName ?? "";
            if (main.source === "custom") {
                const id = main.ref.slice("custom:".length);
                const custom = (Keybinds.data.custom ?? []).find(x => x.id === id);
                command.custom = { title: custom?.title ?? command.text, exec: custom?.exec ?? "" };
            }
        }

        root.all = all;
        root.groups = order;
        root.commands = commands;
        root.unnamed = unnamed;
        root.loaded = true;
    }

    Process {
        id: proc

        command: ["hyprctl", "binds", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                root.parse(this.text);
                if (root.stale) {
                    root.stale = false;
                    Qt.callLater(root.refresh);
                }
            }
        }
    }

    Connections {
        target: Keybinds

        function onRevisionChanged(): void {
            if (root.loaded)
                root.refresh();
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "configreloaded" && root.loaded) {
                root.refresh();
                root.refreshOrigins();
            }
        }
    }
}
