import QtQuick
import Quickshell

import qs.modules.desktop
import qs.modules.services.desktop

// Die Desktop-Ebene (modules/desktop) laeuft genau so lange, wie das Plugin
// an ist. Die Ebene selbst bleibt Teil der Shell: ihre Dateien brauchen sich
// gegenseitig als Typen, und das geht nur in einem qs-Modul, das die Shell
// beim Start kennt (Plugin-Ordner laedt sie nur per URL, siehe README).
Scope {
    required property var plugin

    Desktop {}

    // Beim Ausschalten mitten im Anordnen: Bearbeitung beenden, sonst bliebe
    // Scenes.editing stehen und die Leiste kaeme beim Einschalten wieder
    function onDisable(): void {
        if (Scenes.editing)
            Scenes.cancel();
    }
}
