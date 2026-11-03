pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs

// Tastenkuerzel aus Hyprland fuer die Uebersicht (KeybindsPanel).
//
// Quelle ist `hyprctl binds -j`, nicht eine eigene Liste: die Binds tragen in
// hypr/profiles/simple.lua eine Beschreibung "Gruppe|Text" (optional
// "|Anzeige" statt der echten Taste, z.B. "1 … 0"). Nur beschriebene Binds
// erscheinen. Gleicher Text in derselben Gruppe wird eine Zeile mit mehreren
// Kuerzeln (Medientaste + Ersatzkuerzel).
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

    // Alle Binds der Grundebene (auch unbeschriebene) fuer die
    // Konfliktpruefung: [{ canon, text, ref }]
    property var all: []

    // Kommt waehrend des Lesens eine Aenderung, danach gleich noch einmal
    property bool stale: false

    function refresh(): void {
        if (proc.running)
            root.stale = true;
        else
            proc.running = true;
    }

    function run(entry: var): void {
        if (!entry?.clickable)
            return;
        // Lange Lua-Klammern: die Beschreibung darf so jedes Zeichen enthalten
        // ausser der schliessenden Folge selbst
        Quickshell.execDetached(["hyprctl", "eval", `run_keybind([==[${entry.id}]==])`]);
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
        const key = I18n.language + "\n" + text;
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
        for (const bind of binds) {
            if (bind.submap !== "")
                continue;
            const canon = root.canonOf(bind);
            const parts = (bind.description ?? "").split("|");
            if (parts.length < 2) {
                all.push({ canon, text: I18n.tr("einem Bind ohne Beschreibung"), ref: "" });
                continue;
            }
            const [groupName, text, label] = parts;
            const ref = Keybinds.refFor(bind.description, canon);
            const state = Keybinds.stateOf(ref);
            all.push({ canon, text: `${I18n.tr(groupName)} › ${I18n.tr(text)}`, ref });

            let group = byName[groupName];
            if (!group) {
                group = byName[groupName] = { name: groupName, entries: [] };
                order.push(group);
            }

            // Sammelzeilen ("1 … 0") stehen fuer mehrere Binds, nur einer
            // traegt die Beschreibung – neu belegen wuerde nur ihn treffen
            const combo = {
                keys: root.combo(bind, label ?? ""),
                ref,
                canon,
                editable: !label && !bind.mouse,
                disabled: state.disabled,
                changed: state.changed,
                source: state.source
            };
            const entry = group.entries.find(e => e.text === text);
            if (entry)
                entry.combos.push(combo);
            else
                group.entries.push({
                    text,
                    id: bind.description,
                    clickable: !label && !bind.mouse,
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

        root.all = all;
        root.groups = order;
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
            if (event.name === "configreloaded" && root.loaded)
                root.refresh();
        }
    }
}
