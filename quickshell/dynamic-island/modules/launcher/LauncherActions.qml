pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.services.wallpaper
import qs.modules.services.screenshot

import qs
import qs.modules.settings
import qs.modules.services.plugins

// Aktionen des Launchers.
// Erreichbar über das Präfix `>`.
//
// Eine Aktion ist ein schlichtes Objekt:
//   name  – Titel in der Liste
//   desc  – Untertitel
//   icon  – Material-Symbols-Name
// und genau eine der beiden Bauarten:
//   run:  () => { ... }   führt direkt aus und schließt den Launcher;
//                         mit `keepOpen: true` bleibt die Karte offen (für
//                         Aktionen, die nur umschalten)
//   mode: "name"          schaltet die Liste in einen eigenen Modus um; der
//                         Suchtext wird auf ">name " gesetzt und alles Weitere
//                         kommt aus der Quelle, die unter diesem Namen in
//                         LauncherPanel.modes registriert ist.
Singleton {
    id: root

    readonly property var actions: [
        {
            name: "Shell neu laden",
            icon: "refresh",
            run: () => Quickshell.reload(false)
        },
        {
            name: "Wallpaper",
            icon: "wallpaper_slideshow",
            // Eigene Ansicht in derselben Karte (WallpaperPanel.qml), deshalb
            // umschalten statt schliessen
            keepOpen: true,
            run: () => LauncherState.mode = "wallpaper"
        },
        {
            name: "Theme",
            icon: "palette",
            keepOpen: true,
            run: () => LauncherState.mode = "theme"
        },
        // Untermenues der Notch – dieselben Ansichten wie per Tastenkuerzel
        {
            name: "Medien",
            icon: "music_note",
            keepOpen: true,
            run: () => LauncherState.mode = "media"
        },
        {
            name: "Steuerung",
            icon: "toggle_on",
            keepOpen: true,
            run: () => LauncherState.mode = "control"
        },
        {
            name: "Benachrichtigungen",
            icon: "notifications",
            keepOpen: true,
            run: () => LauncherState.mode = "notifications"
        },
        {
            name: "System",
            icon: "monitoring",
            keepOpen: true,
            run: () => LauncherState.mode = "system"
        },
        {
            name: "Power",
            icon: "power_settings_new",
            keepOpen: true,
            run: () => LauncherState.mode = "power"
        },
        {
            name: "Tastenkürzel",
            desc: "SUPER+K",
            icon: "keyboard",
            keepOpen: true,
            run: () => LauncherState.mode = "keys"
        },
        {
            name: "Zwischenablage",
            desc: "SUPER+V",
            icon: "content_paste",
            keepOpen: true,
            run: () => LauncherState.mode = "clipboard"
        },
        {
            name: "Text aus Bildschirm",
            icon: "document_scanner",
            run: () => Screenshot.open("ocr")
        },
        {
            name: "Einstellungen",
            icon: "tune",
            run: () => SettingsState.toggleOnFocused()
        },
        {
            name: "Zufaelliges Wallpaper",
            icon: "shuffle",
            run: () => Wallpapers.random()
        }
    ]

    // Eingebaute Aktionen plus die der aktiven Plugins (Main.qml `actions`)
    readonly property var all: root.actions.concat(Plugins.actions)

    function search(needle: string): var {
        const query = needle.trim().toLowerCase();
        if (query === "")
            return root.all;

        // Deutscher Text und Uebersetzung: die Suche trifft in beiden Sprachen
        return root.all.filter(action => `${action.name} ${action.desc} ${I18n.tr(action.name)} ${I18n.tr(action.desc)}`.toLowerCase().includes(query));
    }
}
