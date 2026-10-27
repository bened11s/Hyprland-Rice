//@ pragma DefaultEnv QS_NO_RELOAD_POPUP=1
//@ pragma UseQApplication
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import "modules/bar"
import "modules/idle"
import "modules/lock"
import "modules/osd"
import "modules/screenshot"
import "modules/settings"
import "modules/window"
import qs.modules.services.plugins
import qs.modules.services.sounds
// Die Desktop-Ebene startet das Plugin `desktop` (plugins/desktop/Main.qml).
// Der Import bleibt hier, damit die Shell das Modul beim Start kennt –
// Plugin-QML darf nur Module importieren, die schon statisch geladen sind.
import qs.modules.desktop

// Minimaler Startpunkt für den eigenen Rice.
// Start:   dynamic-island shell -d         Stop: dynamic-island shell -k
//          (nicht `qs … -d` direkt: dann fehlen MALLOC_* aus shell.py SHELL_ENV)
// Log:     qs -c dynamic-island log        (Hot-Reload ist an: Datei speichern reicht)
//
// Die Komponenten bringen ihre Pro-Monitor-Logik (Variants) selbst mit:
// hier reicht die blanke Instanziierung ohne Argumente.
ShellRoot {
    settings.watchFiles: true

    // Plugins (plugins/<id>/) laufen auch ohne offenes Menue
    readonly property int pluginCount: Plugins.hosts.length
    // Singleton mit Signal-Verbindungen, wird sonst nie angefasst
    readonly property bool soundsOn: Sounds.dir !== ""

    Wallpaper {}
    Bar {}
    Osd {}
    SettingsWindow {}
    Lock {}
    IdleDim {}
    ScreenshotOverlay {}
    LockEditor {}
}
