pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Farb-Singleton – überall per `Colors.<rolle>` nutzbar.
//
// Zwei Quellen:
// 1. DYNAMISCH (Standard): ~/.local/state/dynamic-island/scheme.json – die dynamic-island-CLI
//    erzeugt daraus eine Material-You-Palette direkt aus dem Wallpaper und
//    schreibt die Datei bei jedem Wallpaper-Wechsel neu. Diese Shell watcht sie
//    und färbt sich live um.
// 2. STATISCH (Fallback): themes/<name>.json – aktiver Name in themes/current.
//    Wird genutzt, wenn useDynamic = false ist oder scheme.json (noch) fehlt /
//    einen Key nicht enthält.
//
// Rollen: "fg*" = Text/Icon auf der jeweiligen Fläche (bewusst nicht "on*", QML liest das als Signal-Handler).
Singleton {
    id: root

    readonly property string themeDir: Quickshell.env("HOME") + "/.config/quickshell/dynamic-island/themes/"
    readonly property string schemePath: Quickshell.env("HOME") + "/.local/state/dynamic-island/scheme.json"

    // Auf false setzen, um statisch bei den themes/*.json zu bleiben
    property bool useDynamic: true

    // geparstes scheme.json ({name, mode, colours:{...}}) – {} wenn nicht geladen
    property var scheme: ({})

    // ---- Vorschau ----
    // Waehrend man im Launcher durch die Wallpaper blaettert, faerbt sich die
    // Shell schon in den Farben des markierten Bildes. Die kommen aus
    // `dynamic-island wallpaper -p` (siehe Wallpapers.qml) und liegen nur hier,
    // nicht in scheme.json – nichts davon wird gespeichert.
    property var previewScheme: ({})
    property bool showPreview: false
    readonly property bool dynamicActive: root.useDynamic && root.scheme.name !== undefined

    // ---- Dynamische Quelle: scheme.json (wallpaper-basiert) ----
    FileView {
        id: schemeFile
        path: root.schemePath
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loadScheme(text())
    }

    function loadScheme(data: string): void {
        try {
            const s = JSON.parse(data);
            if (s && s.colours)
                root.scheme = s;
        } catch (e) {
            console.warn("Colors: scheme.json unparsebar:", e);
        }
    }

    function loadPreview(data: string): void {
        try {
            const s = JSON.parse(data);
            if (s && s.colours) {
                root.previewScheme = s;
                root.showPreview = true;
            }
        } catch (e) {
            console.warn("Colors: Vorschau-Schema unparsebar:", e);
        }
    }

    function clearPreview(): void {
        root.showPreview = false;
        root.previewScheme = ({});
    }

    // Rollen-Auflösung: Vorschau schlaegt dynamisch, dynamisch schlaegt Theme
    function pick(key: string, fallback: color): color {
        const colours = root.showPreview && root.previewScheme.colours ? root.previewScheme.colours
                                                                       : root.scheme.colours;
        const c = colours ? colours[key] : null;
        return c ? ("#" + c) : fallback;
    }

    // ---- Statische Quelle: Theme-Dateien ----
    FileView {
        id: currentFile
        path: root.themeDir + "current"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property string themeName: currentFile.text().trim() || "ink"

    // Theme-Datei; JsonAdapter-Defaults = Fallback, falls ein Key fehlt
    FileView {
        id: themeFile
        path: root.themeDir + root.themeName + ".json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()

        adapter: JsonAdapter {
            id: t
            property string name: "Ink"
            property list<string> palette: ["#000A0F", "#FB1418", "#0ED2FC", "#0372DC", "#DE8673"]

            property string background: "#000A0F"
            property string surface: "#04141C"
            property string surfaceContainer: "#0B1F29"
            property string surfaceBright: "#153039"
            property string outline: "#3A5561"

            property string fgBackground: "#E0F4FA"
            property string fgSurfaceVariant: "#A9C2CC"

            property string primary: "#0ED2FC"
            property string fgPrimary: "#000A0F"
            property string primaryDim: "#036B85"

            property string secondary: "#0372DC"
            property string fgSecondary: "#EAF3FF"

            property string tertiary: "#DE8673"
            property string fgTertiary: "#000A0F"

            property string error: "#FB1418"
            property string fgError: "#FFF1F1"
        }
    }

    // ---- Öffentliche Rollen (dynamisch bevorzugt, Theme als Fallback) ----
    readonly property string name: root.dynamicActive ? (root.scheme.name ?? t.name) : t.name
    readonly property var palette: root.dynamicActive ? [
        root.pick("primaryPaletteKeyColor", t.palette[0]),
        root.pick("secondaryPaletteKeyColor", t.palette[1]),
        root.pick("tertiaryPaletteKeyColor", t.palette[2]),
        root.pick("errorPaletteKeyColor", t.palette[3]),
        root.pick("neutralPaletteKeyColor", t.palette[4])
    ] : t.palette   // 5 Basisfarben, z.B. für Verläufe

    readonly property color background: root.pick("background", t.background)
    readonly property color surface: root.pick("surface", t.surface)
    readonly property color surfaceContainer: root.pick("surfaceContainer", t.surfaceContainer)
    readonly property color surfaceBright: root.pick("surfaceBright", t.surfaceBright)
    readonly property color outline: root.pick("outline", t.outline)
    readonly property color outlineVariant: root.pick("outlineVariant", t.outline)   // dezente Border-Neutralfarbe (M3)

    readonly property color fgBackground: root.pick("onBackground", t.fgBackground)
    readonly property color fgSurface: root.pick("onSurface", t.fgBackground)
    readonly property color fgSurfaceVariant: root.pick("onSurfaceVariant", t.fgSurfaceVariant)

    readonly property color primary: root.pick("primary", t.primary)
    readonly property color fgPrimary: root.pick("onPrimary", t.fgPrimary)
    readonly property color primaryDim: root.pick("primaryDim", t.primaryDim)

    readonly property color secondary: root.pick("secondary", t.secondary)
    readonly property color fgSecondary: root.pick("onSecondary", t.fgSecondary)

    readonly property color tertiary: root.pick("tertiary", t.tertiary)
    readonly property color fgTertiary: root.pick("onTertiary", t.fgTertiary)

    readonly property color error: root.pick("error", t.error)
    readonly property color fgError: root.pick("onError", t.fgError)

    // Aufnahme-Rot. Bewusst fest und nicht aus dem Schema: der Punkt an der
    // Uhr soll in jedem Theme als "es laeuft eine Aufnahme" lesbar sein, und
    // `error` ist je nach Schema auch mal pink oder orange.
    readonly property color record: "#ff4d4f"
    readonly property color fgRecord: "#ffffff"

    // Farbe mit Alpha, z.B. Colors.alpha(Colors.surface, 0.8)
    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Zwei Farben ueberblenden, t = 0 gibt a, t = 1 gibt b.
    // z.B. Colors.mix(Colors.primary, Colors.error, 0.5)
    function mix(a: color, b: color, t: real): color {
        const f = Math.max(0, Math.min(1, t));
        return Qt.rgba(a.r + (b.r - a.r) * f,
                       a.g + (b.g - a.g) * f,
                       a.b + (b.b - a.b) * f,
                       a.a + (b.a - a.a) * f);
    }

    // Farbe aufhellen (f > 0) bzw. abdunkeln (f < 0), z.B. Colors.shade(Colors.background, 0.06)
    function shade(c: color, f: real): color {
        return Qt.hsla(c.hslHue, c.hslSaturation,
                       Math.max(0, Math.min(1, c.hslLightness + f)), 1);
    }
}
