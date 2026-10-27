import QtQuick

import qs

// Dienst des Plugins (plugin.json: main). Lebt, solange das Plugin an ist –
// hier gehoeren Prozesse, Timer, FileViews und die Launcher-Aktionen hin.
//
// `plugin` kommt von der Shell:
//   plugin.settings        aktuelle Werte (bindbar, bei jeder Aenderung neu)
//   plugin.set(key, v)     Wert schreiben (landet in plugins.json)
//   plugin.url(rel)        Datei im Plugin-Ordner
//   plugin.statePath(rel)  ~/.local/state/dynamic-island/plugins/<id>/<rel>
//   plugin.cachePath(rel)  ~/.cache/dynamic-island/plugins/<id>/<rel>
//   plugin.log(msg)        ins Shell-Log
QtObject {
    id: root

    required property var plugin

    readonly property bool lamp: root.plugin.settings.lamp === true

    // Im Launcher unter ">" – gleiches Format wie LauncherActions
    readonly property var actions: [
        {
            name: I18n.tr("Beispiel-Lampe umschalten"),
            desc: root.lamp ? I18n.tr("Jetzt: an") : I18n.tr("Jetzt: aus"),
            keepOpen: true,
            run: () => root.plugin.set("lamp", !root.lamp)
        }
    ]

    // qs -c dynamic-island ipc call plugins call example lamp ""
    function ipc(cmd: string, arg: string): string {
        if (cmd === "lamp")
            return root.lamp ? "on" : "off";
        if (cmd === "toggle") {
            root.plugin.set("lamp", !root.lamp);
            return "ok";
        }
        return "unbekannt: lamp | toggle";
    }

    onLampChanged: root.plugin.log(`Lampe ${root.lamp ? "an" : "aus"}`)
}
