pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Einstellungen der Shell, als Datei neben der CLI-Konfiguration:
//
//     ~/.config/dynamic-island/shell.json
//
// Dieselbe Idee wie caelestias shell.json, nur mit Bordmitteln: FileView +
// JsonAdapter (dasselbe Gespann wie in LauncherFavorites.qml). Die Defaults
// stehen unten im Adapter – fehlt ein Schluessel in der Datei, gilt der
// Default, und die Datei wird beim ersten Start angelegt.
//
// Geaendert wird ueber die Einstellungs-Ansicht (`>einstellungen` im
// Launcher), die nach jeder Aenderung `save()` ruft. Wer lieber tippt, kann
// die Datei auch von Hand bearbeiten – `watchChanges` liest sie sofort neu.
//
// Benutzung:  import qs.modules.services.config
Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/dynamic-island/shell.json"

    readonly property alias bar: adapter.bar
    readonly property alias notifications: adapter.notifications
    readonly property alias appearance: adapter.appearance
    readonly property alias vpn: adapter.vpn
    readonly property alias notch: adapter.notch
    readonly property alias quick: adapter.quick
    readonly property alias osd: adapter.osd
    readonly property alias wallpaper: adapter.wallpaper

    // Schrift fuer alle Texte der Shell (Icons behalten Material Symbols)
    readonly property string font: adapter.appearance.font

    // Klartext zu den Schluesseln. Steht hier neben den Vorgaben, damit eine
    // neue Einstellung an einer einzigen Stelle entsteht: Default eintragen,
    // Beschriftung dazu – im Menue erscheint sie von selbst.
    //
    // Felder:  title, desc        Beschriftung
    //          options: [...]     feste Auswahl (Chips) fuer Strings
    //          min, max, step     Zahl mit Schieberegler; `unit` haengt hinten dran
    //          requires           Zeile nur aktiv, wenn erfuellt: "bar.battery"
    //                             (Wahrheitswert) oder { "appearance.layout": "notch" }
    readonly property var meta: ({
        "bar.workspaces": { title: "Workspace-Punkte", desc: "Die Punktreihe links aussen" },
        "bar.workspaceCount": {
            title: "Workspaces je Monitor",
            desc: "Wie viele Punkte die Reihe zeigt (Hyprland vergibt je Monitor 10)",
            min: 1, max: 10, step: 1, requires: "bar.workspaces"
        },
        "bar.stats": { title: "System-Pille", desc: "Akkustand, Energieprofile und Auslastung" },
        "bar.tray": { title: "Systemtray", desc: "Die Icons links neben der Uhr" },
        "bar.settings": { title: "Settings-Karte", desc: "Der Kreis rechts der Uhr mit WLAN, Bluetooth und Co." },
        "bar.media": { title: "Medien-Karte", desc: "Titel, Cover und Steuerung rechts aussen" },
        "bar.notifications": { title: "Benachrichtigungen", desc: "Die Glocke mit Zaehler in der Leiste" },
        "bar.battery": { title: "Akkuanzeige", desc: "Ring um die Uhr und Akkustand in der Settings-Pille" },
        // Anzeigen in der eingeklappten Notch (nur Notch-Layout)
        "notch.workspaces": {
            title: "Workspaces in der Notch", desc: "Kleine Staebchen links neben der Uhr, solange die Notch zu ist",
            requires: { "appearance.layout": "notch" }
        },
        "notch.date": {
            title: "Datum in der Notch", desc: "Wochentag und Tag rechts neben der Uhr",
            requires: { "appearance.layout": "notch" }
        },
        "notch.media": {
            title: "Cover in der Notch", desc: "Albumcover links neben der Uhr, solange etwas spielt",
            requires: { "appearance.layout": "notch" }
        },
        "notch.visualizer": {
            title: "Visualiser in der Notch", desc: "Pegel rechts neben der Uhr, solange etwas spielt (statt des Datums)",
            requires: { "appearance.layout": "notch" }
        },
        "notch.messages": {
            title: "Nachrichten-Zaehler", desc: "Anzahl ungelesener Benachrichtigungen neben der Uhr",
            requires: { "appearance.layout": "notch" }
        },
        "bar.batteryPulse": { title: "Akku-Ladeimpuls", desc: "Bewegter Impuls im leeren Teil des Akkurings", requires: "bar.battery" },
        "notifications.dnd": { title: "Nicht stören", desc: "Nachrichten sammeln, aber nicht von selbst aufklappen" },
        "vpn.provider": {
            title: "VPN-Anbieter",
            desc: "Anbieter der VPN-Kachel",
            options: ["nordvpn", "cloudflare"]
        },
        "notifications.peekSeconds": {
            title: "Anzeigedauer",
            desc: "Wie lange eine neue Nachricht in der Leiste aufklappt, wenn sie keine eigene Dauer mitbringt",
            min: 2, max: 15, step: 1, unit: "s", requires: "bar.notifications"
        },
        // `options` macht aus der Zeile eine Auswahl. Nicht installierte
        // Schriften blendet das Menue aus.
        "appearance.font": {
            title: "Schriftart",
            desc: "Für alle Texte der Shell",
            options: ["SF Pro", "SF Pro Rounded", "Inter", "Noto Sans", "Adwaita Sans", "Fira Sans", "Cantarell"]
        },
        // Welche Elemente die Leiste zeigt. "insel": alle Pillen. "notch": nur
        // die Notch, angedockt an der Oberkante (Bar.qml und Notch.qml lesen das).
        "appearance.layout": {
            title: "Layout",
            desc: "Insel: alle Pillen. Notch: nur die angedockte Notch oben in der Mitte",
            options: ["insel", "notch"]
        },
        // Nachschwingen der Pillen beim Aufklappen (siehe Appearance.qml)
        "appearance.bounce": {
            title: "Nachschwingen",
            desc: "Wie stark Pillen und Karten beim Aufklappen federn",
            options: ["aus", "leicht", "mittel", "stark"]
        },
        "appearance.speed": {
            title: "Animationstempo",
            desc: "Faktor fuer alle Auf- und Zuklapp-Bewegungen",
            min: 0.5, max: 2, step: 0.1, unit: "x"
        },
        "appearance.radius": {
            title: "Eckenrundung",
            desc: "Rundung der aufgeklappten Karten; flache Pillen bleiben halbrund",
            min: 8, max: 28, step: 1, unit: "px"
        },
        "appearance.shadow": { title: "Schatten", desc: "Weicher Schatten unter Pillen und Karten" },
        "appearance.opacity": { title: "Deckkraft", desc: "Transparenz der Shell-Flaechen, Text bleibt deckend", min: 0.65, max: 1, step: 0.05 },
        "appearance.clock": { title: "Uhrzeit", desc: "Anzeigeformat der Uhr in der Notch", options: ["24h", "12h"] },
        // Uebergang beim Wallpaperwechsel (modules/window/WallpaperStage.qml);
        // dieselbe Auswahl steht als Chip-Reihe in der Wallpaper-Auswahl
        "wallpaper.transition": {
            title: "Übergang",
            desc: "Wie das neue Wallpaper erscheint. Zufall würfelt je Bild",
            options: ["blende", "wischen", "schieben", "kreis", "zoom", "aus", "zufall"]
        },
        "wallpaper.duration": {
            title: "Dauer",
            desc: "Länge des Übergangs. Beim Durchblättern in der Auswahl läuft er schneller",
            min: 200, max: 2000, step: 100, unit: "ms"
        },
        // `editor` statt Bedienelement: das Menue laedt dafuer einen eigenen
        // Editor (modules/settings/QuickLayoutEditor.qml)
        // Regler am rechten Rand (modules/osd)
        "osd.enabled": { title: "Regler am rechten Rand", desc: "Lautstärke und Helligkeit, mittig an der rechten Bildschirmkante" },
        "osd.hover": { title: "Beim Hovern zeigen", desc: "Maus an den rechten Rand in der Bildschirmmitte", requires: "osd.enabled" },
        "osd.brightness": { title: "Helligkeitsregler", desc: "Zweiter Regler unter der Lautstärke", requires: "osd.enabled" },
        "osd.hideDelay": {
            title: "Einblenddauer",
            desc: "Wie lange die Regler nach einer Änderung sichtbar bleiben",
            min: 1, max: 10, step: 1, unit: "s", requires: "osd.enabled"
        },
        "quick.columns": {
            title: "Raster",
            desc: "Spalten des Kachel-Rasters; eine Kachel kann mehrere belegen",
            min: 2, max: 6, step: 1
        },
        "quick.rows": {
            title: "Aufbau der Karte",
            desc: "Kacheln ziehen: umsortieren, neue Reihe, ausblenden. Am rechten Rand ziehen: breiter oder schmaler",
            editor: "quick"
        }
    })

    // Reihenfolge und Symbole der Gruppen im Menue (Material-Symbols-Namen).
    // Gruppen, die hier fehlen, haengt das Menue hinten an.
    readonly property var sectionOrder: ["bar", "quick", "osd", "notch", "appearance", "wallpaper", "notifications", "vpn"]
    readonly property var sectionIcons: ({
        "bar": "space_dashboard",
        "quick": "dashboard_customize",
        "osd": "volume_up",
        "notch": "web_asset",
        "appearance": "palette",
        "wallpaper": "wallpaper_slideshow",
        "notifications": "notifications",
        "vpn": "vpn_key"
    })

    readonly property var sectionMeta: ({
        "bar": "Leiste",
        "quick": "Schnelleinstellungen",
        "osd": "Regler am Rand",
        "notifications": "Benachrichtigungen",
        "vpn": "VPN",
        "appearance": "Darstellung",
        "wallpaper": "Wallpaper",
        "notch": "Notch-Layout"
    })

    // Die Datei als einfaches Objekt – daraus baut das Einstellungs-Fenster
    // seine Liste, ohne dass dort jeder Schluessel einzeln stehen muss.
    // Neue Schluessel im Adapter tauchen dadurch von selbst im Menue auf.
    property var raw: ({})

    // Die Vorgaben aus dem Adapter, eingesammelt bevor die Datei geladen ist
    // (FileView laedt asynchron, onCompleted des Adapters kommt vorher).
    // Damit kann das Menue "geaendert" markieren und zuruecksetzen.
    property var defaults: ({})

    function snapshot(adapterObj: var): var {
        const out = {};
        for (const section in adapterObj) {
            const group = adapterObj[section];
            if (section === "objectName" || typeof group !== "object" || group === null)
                continue;
            out[section] = {};
            for (const key in group) {
                const v = group[key];
                if (key === "objectName" || typeof v === "function")
                    continue;
                // Listen (list<string>) kopieren, andere Objekte ueberspringen
                if (typeof v === "object" && v !== null) {
                    if (v.length !== undefined)
                        out[section][key] = Array.prototype.slice.call(v);
                    continue;
                }
                out[section][key] = v;
            }
        }
        return out;
    }

    function isDefault(section: string, key: string): bool {
        const d = root.defaults[section]?.[key];
        if (d === undefined)
            return true;
        const v = root.raw[section]?.[key];
        // Listen inhaltlich vergleichen
        return typeof d === "object" ? JSON.stringify(d) === JSON.stringify(v) : d === v;
    }

    function reset(section: string, key: string): void {
        const d = root.defaults[section]?.[key];
        if (d !== undefined)
            root.set(section, key, d);
    }

    function resetAll(): void {
        const next = {};
        for (const section in root.defaults) {
            const target = root[section];
            if (!target)
                continue;
            next[section] = Object.assign({}, root.raw[section] ?? {});
            for (const key in root.defaults[section]) {
                target[key] = root.defaults[section][key];
                next[section][key] = root.defaults[section][key];
            }
        }
        root.raw = Object.assign({}, root.raw, next);
        root.save();
    }

    // Ist die Voraussetzung einer Einstellung (meta.requires) erfuellt?
    function satisfied(req: var): bool {
        if (!req)
            return true;
        if (typeof req === "string") {
            const [s, k] = req.split(".");
            return !!root.get(s, k);
        }
        for (const id in req) {
            const [s, k] = id.split(".");
            if (root.get(s, k) !== req[id])
                return false;
        }
        return true;
    }

    function save(): void {
        file.writeAdapter();
    }

    // Wert setzen, ohne den Namen fest zu verdrahten
    function set(section: string, key: string, value: var): void {
        const target = root[section];
        if (!target)
            return;
        target[key] = value;

        // FileView writes asynchronously. Reflect the new value immediately
        // instead of reading the still-old file back into the settings model.
        const next = Object.assign({}, root.raw);
        next[section] = Object.assign({}, next[section] ?? {});
        next[section][key] = value;
        root.raw = next;

        root.save();
    }

    function get(section: string, key: string): var {
        return root[section]?.[key];
    }

    // Einmal pro Start schreiben wir die Datei zurueck – aber nur, wenn ihr
    // Schluessel fehlen. Der Adapter hat dann schon alles aus ihr gelesen,
    // ergaenzt aber fehlende Schluessel mit ihren Vorgaben – so taucht eine
    // neu dazugekommene Einstellung im Menue auf, das sich ja aus der Datei
    // baut. Ohne fehlende Schluessel waere das Schreiben nur ein zweiter
    // Ladedurchlauf (Watcher -> reread -> alles neu). Das Flag verhindert die
    // Schleife Schreiben -> Dateiwaechter -> Schreiben.
    property bool normalised: false

    function missingKeys(): bool {
        const full = root.snapshot(adapter);
        for (const section in full) {
            for (const key in full[section]) {
                if (root.raw[section]?.[key] === undefined)
                    return true;
            }
        }
        return false;
    }

    function reread(): void {
        try {
            root.raw = JSON.parse(file.text());
        } catch (e) {
            // Halb geschriebene Datei o.ae. – beim naechsten Mal wieder
            return;
        }

        if (!root.normalised) {
            root.normalised = true;
            if (root.missingKeys())
                file.writeAdapter();
        }
    }

    FileView {
        id: file

        path: root.path
        watchChanges: true
        // Synchron lesen (die Datei ist ~1 KB): sonst baut sich die ganze
        // Oberflaeche erst mit den Vorgaben auf (Layout "insel", andere
        // Schrift, andere Kachel-Raster) und gleich danach noch einmal
        blockLoading: true
        onLoaded: root.reread()
        // Beim allerersten Start gibt es die Datei noch nicht – das ist kein
        // Fehler, den man melden muesste (angelegt wird sie unten)
        printErrors: false
        onFileChanged: reload()
        // Beim ersten Start gibt es die Datei noch nicht – dann einmal anlegen
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                file.writeAdapter();
        }

        adapter: JsonAdapter {
            id: adapter

            Component.onCompleted: root.defaults = root.snapshot(adapter)

            // Was in der Leiste sichtbar ist. Die Notch selbst steht nicht zur
            // Wahl – ohne sie gaebe es weder Uhr noch Launcher.
            // Alles, was hier steht, erscheint automatisch im Menue
            property JsonObject notifications: JsonObject {
                property bool dnd: false
                // Sekunden, die eine neue Nachricht aufklappt (ohne eigene Dauer)
                property int peekSeconds: 5
            }

            property JsonObject appearance: JsonObject {
                property string font: "SF Pro"
                property string bounce: "mittel"
                property string layout: "insel"
                // Faktor auf Appearance.morphDuration (2 = doppelt so schnell)
                property real speed: 1.0
                property real opacity: 1.0
                property int radius: 20
                property bool shadow: true
                property string clock: "24h"
            }

            property JsonObject vpn: JsonObject {
                property string provider: "nordvpn"
            }

            // Wallpaperwechsel: Animation und ihre Dauer in ms
            property JsonObject wallpaper: JsonObject {
                property string transition: "kreis"
                property int duration: 800
            }

            property JsonObject bar: JsonObject {
                property bool workspaces: true
                property int workspaceCount: 5
                property bool tray: true
                property bool settings: true
                property bool media: true
                property bool notifications: true
                // Die System-Pille ist neu und standardmaessig aus
                property bool stats: false
                property bool battery: true
                property bool batteryPulse: true
            }

            // Was die eingeklappte Notch im Notch-Layout zeigt
            property JsonObject notch: JsonObject {
                property bool workspaces: true
                property bool date: true
                property bool media: true
                property bool visualizer: true
                property bool messages: true
            }

            // Aufbau der Schnelleinstellungen (Settings-Karte): je Eintrag eine
            // Reihe, Kachel-IDs mit Komma getrennt (siehe QuickLayout.qml).
            // Was hier fehlt, ist ausgeblendet.
            // Regler am rechten Bildschirmrand (modules/osd/Osd.qml)
            property JsonObject osd: JsonObject {
                property bool enabled: true
                property bool hover: true
                property bool brightness: true
                // Sekunden nach einer Aenderung
                property int hideDelay: 2
            }

            // Aufbau der Schnelleinstellungen: ein Raster mit `columns` Spalten,
            // je Eintrag eine Reihe, Kacheln als "id:breite" (Breite in
            // Spalten). Was fehlt, ist ausgeblendet. Siehe QuickLayout.qml.
            property JsonObject quick: JsonObject {
                property int columns: 4
                property list<string> rows: [
                    "wifi:2,bluetooth:2",
                    "vpn:2,nosleep:2",
                    "gamemode:2,settings:2",
                    "record:4",
                    "monitors:4",
                    "volume:4",
                    "mic:4",
                    "brightness:4"
                ]
            }
        }
    }
}
