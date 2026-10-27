pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Einstellungen der Shell, als Datei neben der CLI-Konfiguration:
//
//     ~/.config/dynamic-island/shell.json
//
// Nur Bordmittel: FileView +
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
    readonly property alias media: adapter.media
    readonly property alias lock: adapter.lock
    readonly property alias idle: adapter.idle
    readonly property alias sounds: adapter.sounds
    readonly property alias bluetooth: adapter.bluetooth

    // Schrift fuer alle Texte der Shell (Icons behalten Material Symbols)
    readonly property string font: adapter.appearance.font

    // Klartext zu den Schluesseln. Steht hier neben den Vorgaben, damit eine
    // neue Einstellung an einer einzigen Stelle entsteht: Default eintragen,
    // Beschriftung dazu – im Menue erscheint sie von selbst.
    //
    // Felder:  title, desc        Beschriftung
    //          options: [...]     feste Auswahl (Chips) fuer Strings
    //          labels: {...}      Anzeigenamen der Optionen (sonst I18n.tr(Wert))
    //          min, max, step     Zahl mit Schieberegler; `unit` haengt hinten dran
    //          requires           Zeile nur aktiv, wenn erfuellt: "bar.battery"
    //                             (Wahrheitswert) oder { "appearance.layout": "notch" }
    //          hidden             nicht im Menue (wird anderswo bedient)
    //          group              Karte innerhalb der Gruppe ("Workspaces", "Akku" …);
    //                             ohne Angabe teilen sich die Zeilen eine Karte ohne Titel
    readonly property var meta: ({
        "bar.workspaces": { title: "Workspace-Punkte", group: "Workspaces" },
        "bar.workspaceCount": {
            group: "Workspaces",
            title: "Workspaces je Monitor",
            min: 1, max: 10, step: 1, requires: "bar.workspaces"
        },
        "bar.stats": { title: "System-Pille", group: "Module" },
        "bar.tray": { title: "Systemtray", group: "Module" },
        "bar.settings": { title: "Settings-Karte", group: "Module" },
        "bar.media": { title: "Medien-Karte", group: "Module" },
        "bar.notifications": { title: "Benachrichtigungen", group: "Module" },
        "bar.battery": { title: "Akkuanzeige", group: "Akku" },
        // Anzeigen in der eingeklappten Notch (nur Notch-Layout)
        "notch.workspaces": {
            group: "Anzeigen",
            title: "Workspaces in der Notch",
            requires: { "appearance.layout": "notch" }
        },
        "notch.date": {
            group: "Anzeigen",
            title: "Datum in der Notch",
            requires: { "appearance.layout": "notch" }
        },
        "notch.media": {
            group: "Anzeigen",
            title: "Cover in der Notch",
            requires: { "appearance.layout": "notch" }
        },
        "notch.visualizer": {
            group: "Anzeigen",
            title: "Visualiser in der Notch",
            requires: { "appearance.layout": "notch" }
        },
        "notch.messages": {
            group: "Anzeigen",
            title: "Nachrichten-Zaehler",
            requires: { "appearance.layout": "notch" }
        },
        // Stil-Varianten der Notch-Anzeigen. `preview` zeigt im Menue statt
        // Text-Chips eine kleine Vorschau der Variante (SettingsRow -> StylePreview)
        "notch.clockStyle": {
            group: "Stile",
            title: "Uhr-Stil",
            options: ["digital", "split", "analog"], preview: "clock",
            requires: { "appearance.layout": "notch" }
        },
        "notch.workspaceStyle": {
            group: "Stile",
            title: "Workspace-Stil",
            options: ["staebchen", "punkte", "zahlen"], preview: "workspaces",
            requires: "notch.workspaces"
        },
        "notch.visualizerStyle": {
            group: "Stile",
            title: "Visualiser-Stil",
            options: ["spiegel", "saeulen", "punkte", "welle"], preview: "visualizer",
            requires: "notch.visualizer"
        },
        // Medienansicht (MediaPanel)
        "media.cover": {
            title: "Cover",
            options: ["rund", "vinyl"]
        },
        "media.lyrics": {
            title: "Songtexte", desc: "Spotify-Extension, sonst lrclib.net"
        },
        // Sperrbildschirm (modules/lock)
        // Was hinter dem Sperrbildschirm liegt. Das Desktop-Foto braucht er
        // ohnehin fuer den Uebergang, "wallpaper" blendet nur dahin ueber
        "lock.background": {
            group: "Bild",
            title: "Hintergrund",
            options: ["wallpaper", "desktop"]
        },
        "lock.blur": { title: "Wallpaper unscharf", group: "Bild" },
        // Sichtbarkeit von Uhr/Karte steht im Anordnungs-Editor (lock.layout
        // hidden); der alte Schalter gilt nur noch als Vorgabe dafuer
        "lock.media": { title: "Medien-Karte", hidden: true },
        "lock.notifications": { title: "Nachrichten-Zaehler" },
        "lock.layout": { title: "Anordnung", editor: "lock" },
        // Inaktivitaet (services/idle), ersetzt hypridle
        "idle.enabled": { title: "Automatisch sperren", group: "Sperren" },
        "idle.lockMinutes": {
            group: "Sperren",
            title: "Sperren nach", min: 1, max: 60, step: 1, unit: "min", requires: "idle.enabled"
        },
        "idle.warnSeconds": {
            group: "Sperren",
            title: "Vorher abdunkeln", min: 0, max: 30, step: 1, unit: "s", requires: "idle.enabled"
        },
        "idle.screenOffMinutes": {
            group: "Energie",
            title: "Bildschirme aus nach", desc: "0 = nie", min: 0, max: 60, step: 1, unit: "min", requires: "idle.enabled"
        },
        "idle.suspendMinutes": {
            group: "Energie",
            title: "Ruhezustand nach", desc: "0 = nie", min: 0, max: 120, step: 5, unit: "min", requires: "idle.enabled"
        },
        "idle.media": { title: "Nicht bei laufender Musik", group: "Ausnahmen", requires: "idle.enabled" },
        "idle.fullscreen": { title: "Nicht bei Vollbild-Apps", group: "Ausnahmen", requires: "idle.enabled" },
        "idle.lockOnSleep": { title: "Vor dem Ruhezustand sperren", group: "Sperren" },
        // Bluetooth (services/bluetooth); den Adapter waehlt das Bluetooth-Panel
        "bluetooth.adapter": { hidden: true },
        "bluetooth.notify": { title: "Verbinden und Trennen melden", group: "Meldungen", desc: "Nur was von allein passiert, nicht Klicks im Panel" },
        "bluetooth.lowBattery": { title: "Warnung bei schwachem Akku", group: "Meldungen", min: 0, max: 50, step: 5, unit: "%", desc: "0 = aus" },
        "bluetooth.scanSeconds": { title: "Suche endet nach", group: "Suche", min: 15, max: 300, step: 15, unit: "s" },
        // Kurze Systemklaenge (services/sounds)
        "sounds.enabled": { title: "Systemklänge" },
        "sounds.volume": { title: "Lautstärke", min: 10, max: 100, step: 5, unit: "%", requires: "sounds.enabled" },
        "sounds.notifications": { title: "Neue Nachricht", group: "Anlässe", requires: "sounds.enabled" },
        "sounds.screenshot": { title: "Screenshot", group: "Anlässe", requires: "sounds.enabled" },
        "sounds.power": { title: "Ladekabel", group: "Anlässe", requires: "sounds.enabled" },
        "sounds.lock": { title: "Sperren und Entsperren", group: "Anlässe", requires: "sounds.enabled" },
        "sounds.bluetooth": { title: "Bluetooth verbunden/getrennt", group: "Anlässe", requires: "sounds.enabled" },
        "sounds.library": { title: "Eigene Klänge", group: "Eigene Klänge", editor: "sounds" },
        "media.queueOpen": {
            title: "Warteschlange offen", desc: "Die ganze Spotify-Warteschlange zeigen statt nur vorigem und nächstem Titel"
        },
        "bar.batteryPulse": { title: "Akku-Ladeimpuls", group: "Akku", requires: "bar.battery" },
        "notifications.dnd": { title: "Nicht stören" },
        "vpn.provider": {
            title: "VPN-Anbieter",
            options: ["nordvpn", "cloudflare"]
        },
        "notifications.peekSeconds": {
            title: "Anzeigedauer",
            min: 2, max: 15, step: 1, unit: "s", requires: "bar.notifications"
        },
        // Sprache der Oberflaeche (I18n.qml). `labels` zeigt statt des Werts
        // einen Namen – Sprachnamen stehen immer in ihrer eigenen Sprache
        "appearance.language": {
            group: "Sprache und Schrift",
            title: "Sprache",
            options: ["en", "de"],
            labels: { "en": "English", "de": "Deutsch" }
        },
        // `options` macht aus der Zeile eine Auswahl. Nicht installierte
        // Schriften blendet das Menue aus.
        "appearance.font": {
            group: "Sprache und Schrift",
            title: "Schriftart",
            options: ["SF Pro", "SF Pro Rounded", "Inter", "Noto Sans", "Adwaita Sans", "Fira Sans", "Cantarell"]
        },
        // Welche Elemente die Leiste zeigt. "insel": alle Pillen. "notch": nur
        // die Notch, angedockt an der Oberkante (Bar.qml und Notch.qml lesen das).
        "appearance.layout": {
            group: "Form",
            title: "Layout",
            desc: "Insel: alle Pillen. Notch: nur die angedockte Notch oben in der Mitte",
            options: ["insel", "notch"]
        },
        // Nachschwingen der Pillen beim Aufklappen (siehe Appearance.qml)
        "appearance.bounce": {
            group: "Animation",
            title: "Nachschwingen",
            options: ["aus", "leicht", "mittel", "stark"]
        },
        "appearance.speed": {
            group: "Animation",
            title: "Animationstempo",
            min: 0.5, max: 2, step: 0.1, unit: "x"
        },
        "appearance.radius": {
            group: "Form",
            title: "Eckenrundung",
            min: 8, max: 28, step: 1, unit: "px"
        },
        "appearance.shadow": { title: "Schatten", group: "Form" },
        "appearance.clock": { title: "Uhrzeit", group: "Sprache und Schrift", options: ["24h", "12h"] },
        // Uebergang beim Wallpaperwechsel (modules/window/WallpaperStage.qml)
        "wallpaper.transition": {
            group: "Animation",
            title: "Übergang",
            options: ["blende", "wischen", "schieben", "kreis", "zoom", "aus", "zufall"]
        },
        "wallpaper.duration": {
            group: "Animation",
            title: "Dauer",
            min: 200, max: 2000, step: 100, unit: "ms"
        },
        // Zufallsmodus (Wallpapers.qml): "start" wuerfelt einmal je Login,
        // "timer" zusaetzlich alle randomMinutes
        "wallpaper.random": {
            group: "Zufall",
            title: "Zufallsmodus",
            desc: "Start: bei jedem Login ein zufälliges Wallpaper. Timer: dazu regelmäßig ein neues",
            options: ["aus", "start", "timer"]
        },
        "wallpaper.randomMinutes": {
            group: "Zufall",
            title: "Wechsel alle",
            desc: "Wartet bei Vollbild oder Game-Mode",
            min: 5, max: 240, step: 5, unit: "min", requires: { "wallpaper.random": "timer" }
        },
        "wallpaper.randomScope": {
            group: "Zufall",
            title: "Zufall aus",
            desc: "Ordner: nur der Ordner des aktuellen Bilds",
            options: ["alle", "ordner"]
        },
        // `editor` statt Bedienelement: das Menue laedt dafuer einen eigenen
        // Editor (z. B. modules/settings/QuickTilesEditor.qml)
        // Regler am rechten Rand (modules/osd)
        "osd.enabled": { title: "Regler am rechten Rand" },
        "osd.hover": { title: "Beim Hovern zeigen", requires: "osd.enabled" },
        "osd.brightness": { title: "Helligkeitsregler", requires: "osd.enabled" },
        "osd.hideDelay": {
            title: "Einblenddauer",
            min: 1, max: 10, step: 1, unit: "s", requires: "osd.enabled"
        },
        "quick.columns": {
            title: "Raster",
            min: 2, max: 6, step: 1
        },
        "quick.rows": {
            title: "Aufbau der Karte",
            editor: "quick"
        }
    })

    // Reihenfolge und Symbole der Gruppen im Menue (Material-Symbols-Namen).
    // Gruppen, die hier fehlen, haengt das Menue hinten an.
    readonly property var sectionOrder: ["bar", "quick", "bluetooth", "osd", "notch", "media", "lock", "idle", "sounds", "appearance", "wallpaper", "notifications", "vpn"]
    readonly property var sectionIcons: ({
        "bar": "space_dashboard",
        "quick": "dashboard_customize",
        "bluetooth": "bluetooth",
        "osd": "volume_up",
        "notch": "web_asset",
        "media": "music_note",
        "lock": "lock",
        "idle": "bedtime",
        "sounds": "notifications_active",
        "appearance": "palette",
        "wallpaper": "wallpaper_slideshow",
        "notifications": "notifications",
        "vpn": "vpn_key"
    })

    readonly property var sectionMeta: ({
        "bar": "Leiste",
        "quick": "Schnelleinstellungen",
        "bluetooth": "Bluetooth",
        "osd": "Regler am Rand",
        "notifications": "Benachrichtigungen",
        "vpn": "VPN",
        "appearance": "Darstellung",
        "wallpaper": "Wallpaper",
        "notch": "Notch-Layout",
        "media": "Medien",
        "lock": "Sperrbildschirm",
        "idle": "Inaktivität",
        "sounds": "Klänge"
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
        saveDelay.stop();
        file.writeAdapter();
    }

    // Schieberegler rufen set() bei jedem Rasterschritt – sofort schreiben
    // hiesse: Datei schreiben, Watcher, JSON neu parsen, alles neu binden,
    // dutzendfach pro Sekunde. Der Adapter und `raw` haben den Wert schon,
    // auf die Platte geht er gesammelt.
    Timer {
        id: saveDelay

        interval: 300
        onTriggered: root.save()
    }

    Component.onDestruction: if (saveDelay.running) file.writeAdapter()

    // Schluessel sortiert serialisieren: die Datei kommt alphabetisch zurueck,
    // `raw` in Einfuege-Reihenfolge – fuer den Vergleich in reread()
    function canonical(v: var): string {
        if (Array.isArray(v))
            return "[" + v.map(x => root.canonical(x)).join(",") + "]";
        if (typeof v === "object" && v !== null)
            return "{" + Object.keys(v).sort().map(k => JSON.stringify(k) + ":" + root.canonical(v[k])).join(",") + "}";
        return JSON.stringify(v);
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

        // Zahlen kommen von Schiebereglern (viele Schritte pro Sekunde) –
        // gesammelt schreiben. Alles andere sofort: QuickLayout rechnet mit
        // seinem 400-ms-Schutz ab dem Aufruf.
        if (typeof value === "number")
            saveDelay.restart();
        else
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
        let parsed;
        try {
            parsed = JSON.parse(file.text());
        } catch (e) {
            // Halb geschriebene Datei o.ae. – beim naechsten Mal wieder
            return;
        }
        // Meist ist das nur das Echo des eigenen Schreibens: dann `raw` nicht
        // neu setzen, sonst baut z.B. das Einstellungs-Fenster jede Zeile neu
        if (root.canonical(parsed) !== root.canonical(root.raw))
            root.raw = parsed;

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
                // "en" oder "de" (I18n.qml); install.sh setzt es beim Einrichten
                property string language: "en"
                property string font: "SF Pro"
                property string bounce: "mittel"
                property string layout: "insel"
                // Faktor auf Appearance.morphDuration (2 = doppelt so schnell)
                property real speed: 1.0
                property int radius: 20
                property bool shadow: true
                property string clock: "24h"
            }

            property JsonObject vpn: JsonObject {
                property string provider: "nordvpn"
            }

            // Wallpaperwechsel: Animation und ihre Dauer in ms, dazu der
            // Zufallsmodus (aus | start | timer) samt Abstand und Auswahl
            property JsonObject wallpaper: JsonObject {
                property string transition: "kreis"
                property int duration: 800
                property string random: "aus"
                property int randomMinutes: 30
                property string randomScope: "alle"
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
                property string clockStyle: "digital"
                property string workspaceStyle: "staebchen"
                property string visualizerStyle: "spiegel"
            }

            property JsonObject media: JsonObject {
                property string cover: "rund"
                property bool lyrics: true
                property bool queueOpen: false
            }

            // Sperrbildschirm (modules/lock)
            property JsonObject lock: JsonObject {
                // "wallpaper" | "desktop" (Foto des Desktops, LockScreen.qml)
                property string background: "wallpaper"
                property bool blur: true
                property bool media: true
                property bool notifications: true
                // Positionen von Uhr und Medien-Karte, leer = Standard
                // (modules/lock/LockLayout.qml)
                property var layout: ({})
            }

            // Inaktivitaet (services/idle/Idle.qml), Zeiten in Minuten
            property JsonObject idle: JsonObject {
                property bool enabled: true
                property int lockMinutes: 3
                property int warnSeconds: 10
                property int screenOffMinutes: 4
                property int suspendMinutes: 0
                property bool media: true
                property bool fullscreen: true
                property bool lockOnSleep: true
            }

            // Bluetooth (services/bluetooth/BluetoothService.qml)
            property JsonObject bluetooth: JsonObject {
                // adapterId ("hci1"), leer = automatisch
                property string adapter: ""
                property bool notify: true
                // Prozent, 0 = aus
                property int lowBattery: 15
                property int scanSeconds: 60
            }

            property JsonObject sounds: JsonObject {
                property bool enabled: false
                property int volume: 60
                property bool notifications: true
                property bool screenshot: true
                property bool power: true
                property bool lock: false
                property bool bluetooth: true
                // Nur Anker fuer den Editor (SoundsEditor); die Dateien liegen
                // in ~/.config/dynamic-island/sounds
                property string library: ""
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
                    "volume:4",
                    "mic:4",
                    "brightness:4"
                ]
            }
        }
    }
}
