pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.modules.services.config
import qs.modules.services.system
import qs.modules.services.theme

import qs

// Wallpaper-Dienst: kennt die Bilder im Wallpaper-Ordner, das aktuell
// gesetzte und das gerade nur vorgeschaute.
//
// Kommt ohne kompiliertes Plugin aus (Quickshell hat kein FileSystemModel):
// Die Liste kommt aus einem `find`; gescannt wird erst, wenn sie gebraucht
// wird (`ensureLoaded`, bei jedem Oeffnen der Auswahl - neue Bilder tauchen so
// ohne Neustart auf), damit der Start der Shell nichts davon merkt.
//
// Das Karussell zeigt nie die Originale, sondern kleine Vorschaubilder aus
// ~/.cache/dynamic-island/thumbs (thumbs.sh). Qt dekodiert alle Bilder der
// Shell in einem einzigen Thread; die Originale (bis 40 MB PNG) stauten
// dort alles, auch den Hintergrund – der hing dann auf dem alten Bild.
//
// Gesetzt wird ueber die CLI, nicht selbst: `dynamic-island wallpaper -f`
// schreibt den Pfad in den State, erzeugt die Material-You-Palette und legt
// scheme.json ab – woran wiederum Colors.qml haengt. Ein Wechsel faerbt also
// die ganze Shell mit um.
//
// Benutzung:  import qs.modules.services.wallpaper
Singleton {
    id: root

    // Denselben Ordner wie die CLI nehmen (utils/paths.py)
    readonly property string wallsDir: Quickshell.env("DYNAMIC_ISLAND_WALLPAPERS_DIR")
        || (Quickshell.env("HOME") + "/Pictures/Wallpapers")
    readonly property string statePath: Quickshell.env("HOME") + "/.local/state/dynamic-island/wallpaper/path.txt"
    // Absolut statt nur "dynamic-island": execDetached loest ueber die PATH des
    // Shell-Prozesses auf, und ob ~/.local/bin da drin steht, haengt an der
    // Session – hier nicht.
    readonly property string cli: Quickshell.env("HOME") + "/.local/bin/dynamic-island"
    readonly property string thumbsDir: Quickshell.env("HOME") + "/.cache/dynamic-island/thumbs"

    // [{ path, name }] – name ist der Pfad relativ zum Wallpaper-Ordner
    property var list: []
    property bool loaded: false
    property bool loading: false

    // Namen mit fertigem Vorschaubild ({ name: true }). Wird gesammelt neu
    // zugewiesen (siehe thumbFlush), damit nicht jede Zeile von thumbs.sh
    // alle Kacheln neu auswerten laesst.
    property var thumbs: ({})
    property var pendingThumbs: []

    // Tatsaechlich gesetzt (aus dem State) bzw. nur vorgeschaut (Auswahl im
    // Launcher). `current` ist das, was der Hintergrund anzeigen soll.
    property string actualCurrent: ""
    property string previewPath: ""
    property bool showPreview: false
    readonly property string current: root.showPreview && root.previewPath !== "" ? root.previewPath
                                                                                  : root.actualCurrent
    // Die Vorschau ist nur ein kleines Bild (previewThumb): der Hintergrund
    // dekodiert es dann in seiner Groesse, statt es auf Bildschirmgroesse
    // hochzurechnen. Als Funktion statt Bindung: WallpaperStage fragt beim
    // Wechsel von `current`, und eine zweite Bindung waere in dem Moment
    // womoeglich noch nicht nachgezogen (Reihenfolge der Benachrichtigung).
    property bool previewSmall: false

    function smallFor(path: string): bool {
        return root.showPreview && root.previewSmall && path === root.previewPath;
    }

    // ---- Uebergang ----
    // Welche Animation der Hintergrund beim Wechsel spielt (Config
    // wallpaper.transition). "zufall" wuerfelt – aber je Bild fest, damit
    // beide Monitore dieselbe zeigen, ohne sich abzusprechen.
    readonly property var transitions: ["blende", "wischen", "schieben", "kreis", "zoom"]

    function transitionFor(path: string): string {
        const chosen = Config.wallpaper.transition;
        if (chosen !== "zufall")
            return chosen;
        let h = 0;
        for (let i = 0; i < path.length; i++)
            h = (h * 31 + path.charCodeAt(i)) | 0;
        return root.transitions[Math.abs(h) % root.transitions.length];
    }

    // ---- Stil je Bild ----
    // Die Material-Variante, mit der aus einem Bild die Palette wird, haengt am
    // Bild: die CLI merkt sich eine feste Wahl je Pfad (variants.json), Bilder
    // ohne Eintrag bekommen den Stil, den sie aus der Farbigkeit ausrechnet
    // ("auto"). Wirkt nur beim dynamischen Schema.
    readonly property string variantsPath: Quickshell.env("HOME") + "/.local/state/dynamic-island/wallpaper/variants.json"
    property var variants: ({})

    // Was die Vorschau fuer das gerade markierte Bild ergeben hat – bei "auto"
    // der ausgerechnete Stil
    property string previewVariant: ""

    // Feste Wahl fuer ein Bild, leer = auto
    function variantFor(path: string): string {
        return root.variants[path] ?? "";
    }

    // Stil fuer ein Bild festlegen ("auto" nimmt die Wahl zurueck). Ist es das
    // aktuelle Bild, faerbt die CLI gleich um; sonst gilt er beim naechsten
    // Setzen. Die Vorschau rechnet danach mit dem neuen Stil nach.
    function setVariant(path: string, variant: string): void {
        if (path === "")
            return;
        const next = Object.assign({}, root.variants);
        if (variant === "auto")
            delete next[path];
        else
            next[path] = variant;
        root.variants = next;           // sofort, die Datei zieht gleich nach

        variantProc.running = false;
        variantProc.command = [root.cli, "wallpaper", "--variant", variant, "--for", path];
        variantProc.path = path;
        variantProc.running = true;
    }

    Process {
        id: variantProc

        property string path: ""

        onExited: {
            if (root.showPreview && root.previewPath === variantProc.path)
                root.preview(variantProc.path);
        }
    }

    FileView {
        path: root.variantsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.variants = typeof data === "object" && data ? data : {};
            } catch (e) {
                root.variants = {};
            }
        }
        onLoadFailed: root.variants = {}
    }

    // ---- Liste ----
    function ensureLoaded(): void {
        if (!root.loading)
            root.reload();
    }

    function reload(): void {
        root.loading = true;
        scan.running = true;
        thumbGen.running = true;
    }

    // Vorschaubild zu einem Eintrag – leer, solange es noch nicht fertig ist.
    // Bewusst kein Rueckfall aufs Original, das wuerde den Stau zurueckholen.
    function thumbFor(name: string): string {
        return root.thumbs[name] ? `file://${root.thumbsDir}/${name}.jpg` : "";
    }

    // Dasselbe als Dateipfad fuer ein beliebiges Wallpaper (Helligkeitsmessung
    // in Appearance). Liegt das Bild ausserhalb des Ordners: das Original.
    function thumbPathFor(path: string): string {
        const prefix = root.wallsDir + "/";
        if (path.startsWith(prefix))
            return `${root.thumbsDir}/${path.slice(prefix.length)}.jpg`;
        return "";
    }

    function search(needle: string): var {
        const query = needle.trim().toLowerCase();
        if (query === "")
            return root.list;
        return root.list.filter(w => w.name.toLowerCase().includes(query));
    }

    // ---- Setzen ----
    function set(path: string): void {
        // Erst das neue Bild eintragen, dann die Vorschau beenden: andersherum
        // sprang `current` kurz aufs alte Bild zurueck, und der Hintergrund
        // blendete erst dorthin und dann wieder zum neuen.
        root.actualCurrent = path;          // sofort, der State zieht gleich nach
        root.stopPreview();
        Quickshell.execDetached([root.cli, "wallpaper", "-f", path]);
    }

    function random(): void {
        root.stopPreview();
        Quickshell.execDetached([root.cli, "wallpaper", "-r"]);
    }

    // ---- Zufallsmodus ----
    // Config.wallpaper.random: "start" wuerfelt einmal je Login, "timer"
    // ausserdem alle randomMinutes. Die Shell startet aber nicht nur beim
    // Login (Hot-Reload, shell-restart, Neustart nach Crash) – darum merkt sich
    // randomSessionPath, fuer welche Hyprland-Instanz schon gewuerfelt wurde.
    readonly property string randomSessionPath: Quickshell.env("HOME")
        + "/.local/state/dynamic-island/wallpaper/random-session"
    readonly property string session: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "ohne-hyprland"
    readonly property bool randomOn: Config.wallpaper.random === "start" || Config.wallpaper.random === "timer"
    property bool startChecked: false

    // Nicht mitten ins Spiel wechseln: ein Wechsel faerbt Shell und Hyprland
    // um (scheme.json, hyprctl reload). Ebenso nicht, waehrend man in der
    // Auswahl blaettert.
    readonly property bool randomBusy: SessionModes.gameMode || root.showPreview
        || Hyprland.monitors.values.some(m => m.activeWorkspace?.hasFullscreen ?? false)

    // Ordner fuer `wallpaper -r`: ganzer Wallpaper-Ordner oder nur der
    // Unterordner des aktuellen Bilds
    function randomDir(): string {
        const prefix = root.wallsDir + "/";
        if (Config.wallpaper.randomScope === "ordner" && root.actualCurrent.startsWith(prefix)) {
            const dir = root.actualCurrent.slice(0, root.actualCurrent.lastIndexOf("/"));
            if (dir.length >= prefix.length)
                return dir;
        }
        return root.wallsDir;
    }

    function randomTick(): void {
        if (root.randomBusy) {
            root.randomPending = true;
            return;
        }
        root.randomPending = false;
        randomProc.only = "";
        randomProc.running = true;
    }

    // Einmal je Hyprland-Instanz; der Abgleich mit der Merkdatei steckt im
    // Skript, damit zwei Shell-Starts kurz nacheinander nicht doppelt wuerfeln
    function randomAtStart(): void {
        if (root.startChecked)
            return;
        root.startChecked = true;
        if (!root.randomOn)
            return;
        randomProc.only = root.session;
        randomProc.running = true;
    }

    // Verschobener Wechsel (Vollbild/Game-Mode/Auswahl offen): nachholen,
    // sobald wieder frei ist
    property bool randomPending: false

    onRandomBusyChanged: {
        if (!root.randomBusy && root.randomPending)
            pendingDelay.restart();
    }

    Timer {
        id: randomTimer

        running: Config.wallpaper.random === "timer"
        repeat: true
        interval: Math.max(1, Config.wallpaper.randomMinutes) * 60000
        onTriggered: root.randomTick()
    }

    // Kurz warten, bevor ein verschobener Wechsel kommt: nach dem Schliessen
    // eines Spiels nicht gleich im ersten Moment
    Timer {
        id: pendingDelay

        interval: 5000
        onTriggered: {
            if (Config.wallpaper.random === "timer")
                root.randomTick();
            else
                root.randomPending = false;
        }
    }

    Process {
        id: randomProc

        // Gesetzt: nur wuerfeln, wenn fuer diese Sitzung noch nicht geschehen
        property string only: ""

        // Laesst sich im Unterordner nichts Neues finden (nur ein Bild),
        // faellt es auf den ganzen Wallpaper-Ordner zurueck
        command: ["sh", "-c", `
            mark="$1"; only="$2"; cli="$3"; dir="$4"; all="$5"
            if [ -n "$only" ]; then
                [ "$(cat "$mark" 2>/dev/null)" = "$only" ] && exit 0
                mkdir -p "$(dirname "$mark")" && printf '%s\n' "$only" > "$mark"
            fi
            "$cli" wallpaper -r "$dir" 2>/dev/null || "$cli" wallpaper -r "$all"
        `, "sh", root.randomSessionPath, randomProc.only, root.cli, root.randomDir(), root.wallsDir]
    }

    // ---- Vorschau ----
    // Bild und Farben: `wallpaper -p` rechnet die Palette aus, die das Bild
    // ergeben WUERDE, ohne etwas zu setzen (~90-230ms, danach aus dem Cache).
    // Colors traegt sie nur zur Anzeige, gespeichert wird nichts.
    //
    // Nur wenn das Schema ueberhaupt am Wallpaper haengt: bei einem festen
    // Schema (catppuccin, tokyonight, ...) aendert ein Bildwechsel die Farben
    // nicht, die Vorschau wuerde also etwas zeigen, was nie eintritt.
    //
    // Der Pfad darf auch ausserhalb des Wallpaper-Ordners liegen (dann ohne
    // Vorschaubild der Auswahl – siehe thumbPathFor).
    function preview(path: string): void {
        root.previewSmall = false;
        root.previewAs(path);
    }

    // Dasselbe mit einem kleinen Bild (Thumb, z.B. ein Treffer aus dem Netz,
    // der lokal noch nicht liegt): der Hintergrund zieht es nur hoch, statt
    // es beim Dekodieren auf Bildschirmgroesse zu rechnen. Fuer die Palette
    // reicht es – die CLI rechnet ohnehin auf einem 128-px-Abzug.
    function previewThumb(path: string): void {
        root.previewSmall = true;
        root.previewAs(path);
    }

    function previewAs(path: string): void {
        if (root.previewPath !== path)
            root.previewVariant = "";
        root.previewPath = path;
        root.showPreview = true;

        if (Themes.currentName !== "dynamic")
            return;

        colourPreview.running = false;
        colourPreview.wall = path;
        colourPreview.running = true;
    }

    function stopPreview(): void {
        root.showPreview = false;
        root.previewPath = "";
        root.previewSmall = false;
        root.previewVariant = "";
        colourPreview.running = false;
        Colors.clearPreview();
    }

    Process {
        id: colourPreview

        property string wall: ""

        command: [root.cli, "wallpaper", "-p", colourPreview.wall]

        stdout: StdioCollector {
            onStreamFinished: {
                // Wer inzwischen weitergeblaettert oder zugemacht hat, soll
                // nicht die Farben von vorhin bekommen. Leer = der Prozess
                // wurde fuer das naechste Bild abgebrochen.
                if (text.trim() !== "" && root.showPreview && colourPreview.wall === root.previewPath) {
                    Colors.loadPreview(text);
                    try {
                        root.previewVariant = JSON.parse(text).variant ?? "";
                    } catch (e) {
                        root.previewVariant = "";
                    }
                }
            }
        }
    }

    Process {
        id: scan

        // %P = Pfad ohne den Ordner davor. Versteckte Ordner fliegen raus,
        // sonst laendet das .git des Wallpaper-Repos mit in der Liste.
        command: ["find", root.wallsDir, "-type", "f", "-not", "-path", "*/.*",
            "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png",
            "-o", "-iname", "*.webp", "-o", "-iname", "*.jxl", "-o", "-iname", "*.gif", ")",
            "-printf", "%P\n"]

        stdout: StdioCollector {
            onStreamFinished: {
                const entries = text.split("\n")
                    .map(line => line.trim())
                    .filter(line => line !== "")
                    .sort((a, b) => a.localeCompare(b))
                    .map(name => ({
                        path: `${root.wallsDir}/${name}`,
                        name
                    }));

                // Nur bei echter Aenderung neu zuweisen: das Karussell
                // springt bei jedem Modellwechsel zurueck auf das aktuelle Bild
                // – auch wenn man gleich nach dem Oeffnen schon blaettert.
                if (entries.map(e => e.name).join("\n") !== root.list.map(e => e.name).join("\n"))
                    root.list = entries;
                root.loaded = true;
                root.loading = false;
            }
        }
    }

    // Vorschaubilder anlegen bzw. melden (siehe thumbs.sh). Laeuft bei jedem
    // Oeffnen; ohne neue Bilder ist es nach ~20 ms durch.
    Process {
        id: thumbGen

        command: ["bash", Quickshell.shellPath("modules/services/wallpaper/thumbs.sh"),
            root.wallsDir, root.thumbsDir]

        stdout: SplitParser {
            onRead: line => {
                if (line === "" || root.thumbs[line])
                    return;
                root.pendingThumbs.push(line);
                if (!thumbFlush.running)
                    thumbFlush.start();
            }
        }
    }

    Timer {
        id: thumbFlush

        interval: 120
        onTriggered: {
            const next = Object.assign({}, root.thumbs);
            for (const name of root.pendingThumbs)
                next[name] = true;
            root.pendingThumbs = [];
            root.thumbs = next;
        }
    }

    // Aktuelles Wallpaper – dieselbe Datei, die auch die CLI schreibt
    FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.actualCurrent = text().trim();
            // Erst jetzt: "ordner" braucht das aktuelle Bild
            root.randomAtStart();
        }
        onLoadFailed: root.randomAtStart()
    }
}
