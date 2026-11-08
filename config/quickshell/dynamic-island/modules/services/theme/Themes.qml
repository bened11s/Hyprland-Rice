pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Farbschema-Dienst: kennt die verfuegbaren Schemata der CLI, das aktuell
// gesetzte und die Material-Varianten.
//
// Ein Eintrag ist eine konkrete Kombination aus Name, Flavour und Modus – so
// liegen sie auch auf der Platte (<schemes>/<name>/<flavour>/<mode>.txt). Die
// meisten Schemata gibt es nur in einem Modus (catppuccin latte ist hell,
// mocha dunkel), ein Hell/Dunkel-Schalter waere also die falsche Bedienung.
//
// Die Vorschaufarben kommen direkt aus diesen Dateien statt aus
// `dynamic-island scheme list`: das JSON dort traegt nur die Farben im gerade
// gesetzten Modus, die Kacheln waeren also zur Haelfte falsch.
//
// Gesetzt wird ueber die CLI (`dynamic-island scheme set`); die schreibt
// scheme.json, woran Colors.qml haengt – die Shell faerbt sich also live um.
//
// Benutzung:  import qs.modules.services.theme
Singleton {
    id: root

    readonly property string cli: Quickshell.env("HOME") + "/.local/bin/dynamic-island"
    readonly property string schemePath: Quickshell.env("HOME") + "/.local/state/dynamic-island/scheme.json"

    // ---- Aktuell gesetzt (aus scheme.json) ----
    property string currentName: ""
    property string currentFlavour: ""
    property string currentMode: ""
    property string currentVariant: ""

    readonly property string currentKey: `${root.currentName}/${root.currentFlavour}/${root.currentMode}`

    // ---- Auswahl ----
    // [{ key, name, flavour, mode, label, background, primary, secondary, tertiary }]
    property var entries: []
    property bool loaded: false
    property bool loading: false

    // Die Material-Varianten der CLI (nur fuer das dynamische Schema von
    // Belang – sie steuern, wie aus dem Wallpaper eine Palette wird).
    // Die Icons sind Material-Symbols-Ligaturen; alle in der installierten
    // Schriftversion vorhanden (geprueft ueber die post-Tabelle der Datei).
    readonly property var variants: [
        { name: "tonalspot", icon: "tonality" },
        { name: "vibrant", icon: "flare" },
        { name: "expressive", icon: "brush" },
        { name: "fidelity", icon: "colorize" },
        { name: "fruitsalad", icon: "local_florist" },
        { name: "monochrome", icon: "filter_b_and_w" },
        { name: "neutral", icon: "opacity" },
        { name: "rainbow", icon: "looks" },
        { name: "content", icon: "photo_filter" }
    ]

    function ensureLoaded(): void {
        if (!root.loaded && !root.loading)
            root.reload();
    }

    function reload(): void {
        root.loading = true;
        scan.running = true;
    }

    function search(needle: string): var {
        const query = needle.trim().toLowerCase();
        if (query === "")
            return root.entries;
        return root.entries.filter(e => e.label.toLowerCase().includes(query));
    }

    // ---- Setzen ----
    function apply(entry: var): void {
        if (!entry)
            return;
        // Sofort eintragen: die Markierung im Karussell springt so gleich um,
        // statt auf die CLI und den Dateiwaechter zu warten. scheme.json
        // bestaetigt bzw. korrigiert es kurz danach.
        root.currentName = entry.name;
        root.currentFlavour = entry.flavour;
        root.currentMode = entry.mode;
        Quickshell.execDetached([root.cli, "scheme", "set",
            "--name", entry.name, "--flavour", entry.flavour, "--mode", entry.mode]);
    }

    function setVariant(variant: string): void {
        Quickshell.execDetached([root.cli, "scheme", "set", "--variant", variant]);
    }

    function random(): void {
        Quickshell.execDetached([root.cli, "scheme", "set", "--random"]);
    }

    // ---- Einlesen ----
    // Ein Durchlauf ueber alle Schema-Dateien, der pro Datei nur die paar
    // Farben ausgibt, die die Kachel braucht. Den Ordner findet das Skript
    // ueber die CLI selbst (sie liegt als Symlink in ~/.local/bin), damit hier
    // kein Pfad ins CLI-Paket fest verdrahtet ist.
    //
    // "dynamic" hat keine Dateien – seine Farben entstehen erst aus dem
    // Wallpaper. Es kommt deshalb unten von Hand dazu.
    Process {
        id: scan

        // `sh -c`, nicht `-lc`: eine Login-Shell liest erst das ganze Profil
        command: ["sh", "-c",
            'dir="$(dirname "$(readlink -f "$HOME/.local/bin/dynamic-island")")/../src/dynamic_island/data/schemes";'
            + ' grep -H -E "^(background|primary|secondary|tertiary) " "$dir"/*/*/*.txt']

        stdout: StdioCollector {
            onStreamFinished: {
                const byKey = {};

                for (const line of text.split("\n")) {
                    // <pfad>/<name>/<flavour>/<mode>.txt:<rolle> <hex>
                    const split = line.lastIndexOf(".txt:");
                    if (split < 0)
                        continue;

                    const parts = line.slice(0, split).split("/");
                    const mode = parts[parts.length - 1];
                    const flavour = parts[parts.length - 2];
                    const name = parts[parts.length - 3];
                    const [role, hex] = line.slice(split + 5).trim().split(" ");
                    if (!role || !hex)
                        continue;

                    const key = `${name}/${flavour}/${mode}`;
                    if (!byKey[key])
                        byKey[key] = root.makeEntry(name, flavour, mode);
                    byKey[key][role] = `#${hex}`;
                }

                const list = Object.keys(byKey).sort().map(k => byKey[k]);

                // Das dynamische Schema: Flavour und Modus gibt es, Farben
                // nicht – die Kachel zeigt stattdessen die laufende Palette.
                for (const flavour of ["default", "hard"])
                    for (const mode of ["dark", "light"])
                        list.push(root.makeEntry("dynamic", flavour, mode));

                root.entries = list;
                root.loaded = true;
                root.loading = false;
            }
        }
    }

    function makeEntry(name: string, flavour: string, mode: string): var {
        return {
            key: `${name}/${flavour}/${mode}`,
            name,
            flavour,
            mode,
            // "default" sagt nichts, das lassen wir im Titel weg
            label: flavour === "default" ? name : `${name} ${flavour}`,
            background: "",
            primary: "",
            secondary: "",
            tertiary: ""
        };
    }

    // Aktuelles Schema – dieselbe Datei, an der auch Colors.qml haengt
    FileView {
        path: root.schemePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text());
                root.currentName = s.name ?? "";
                root.currentFlavour = s.flavour ?? "";
                root.currentMode = s.mode ?? "";
                root.currentVariant = s.variant ?? "";
            } catch (e) {
                console.warn("Themes: scheme.json unparsebar:", e);
            }
        }
    }
}
