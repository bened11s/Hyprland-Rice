pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.services.config

// Zettel auf dem Desktop: liest eine schlichte Textdatei, zeigt die erste
// Zeile als Ueberschrift und danach die naechsten Zeilen. Kein Editor –
// schreiben laesst sich die Datei von ueberall (Terminal, Editor, Skript),
// das Widget liest sie beim Start und wenn der Desktop wieder sichtbar wird.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    readonly property string path: Quickshell.env("HOME") + "/.config/dynamic-island/notiz.txt"
    readonly property int maxLines: parseInt(root.opts.zeilen ?? "5")
    readonly property bool showHead: root.opts.kopf ?? true

    readonly property string display: Qt.fontFamilies().includes("Inter Display") ? "Inter Display" : Config.font
    readonly property real headPx: Math.max(11, root.unit * 1.0)
    readonly property real bodyPx: Math.max(10, root.unit * 0.85)

    property string body: ""
    property bool missing: false

    readonly property var lines: {
        const raw = root.body.replace(/\r/g, "").split("\n");
        const out = [];
        for (let i = 0; i < raw.length; ++i) {
            const t = raw[i].trim();
            if (t.length === 0)
                continue;
            out.push(t);
            if (out.length >= root.maxLines)
                break;
        }
        return out;
    }

    Process {
        id: reader

        command: ["cat", root.path]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.body = text
        }

        onExited: code => root.missing = code !== 0
    }

    Component.onCompleted: reader.running = true
    onActiveChanged: if (root.active)
        reader.running = true

    implicitWidth: root.unit * 16
    implicitHeight: column.implicitHeight

    Column {
        id: column

        width: parent.width
        spacing: Math.round(root.unit * 0.35)

        // Kopfzeile mit Akzentstrich
        Row {
            visible: root.showHead
            width: parent.width
            height: root.headPx * 1.4
            spacing: root.unit * 0.4

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(2, root.unit * 0.12)
                height: root.headPx * 0.9
                radius: width / 2
                color: root.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.missing ? "Notiz" : (root.lines.length > 0 ? root.lines[0] : "Notiz")
                font.family: root.display
                font.pixelSize: root.headPx
                font.weight: Font.DemiBold
                font.letterSpacing: root.headPx * 0.03
                color: root.color
                elide: Text.ElideRight
                width: parent.width - root.unit * 1.2
            }
        }

        // Leerzustand: sagt, wo der Zettel liegt
        Text {
            visible: root.missing
            width: parent.width
            text: "Zeilen in ~/.config/dynamic-island/notiz.txt schreiben"
            wrapMode: Text.WordWrap
            font.family: root.display
            font.pixelSize: root.bodyPx
            color: Colors.alpha(root.color, 0.55)
        }

        Repeater {
            model: root.missing ? [] : root.lines.slice(root.showHead ? 1 : 0)

            delegate: Text {
                required property string modelData

                width: column.width
                text: modelData
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: root.display
                font.pixelSize: root.bodyPx
                lineHeight: 1.15
                color: Colors.alpha(root.color, 0.78)
            }
        }
    }
}
