pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.services.config

// Terminal-Programm als Desktop-Widget (Vertrag: modules/desktop/WidgetHost.qml).
//
// Das Programm laeuft in einem eigenen kitty-Panel (`kitty +kitten panel
// --edge=none --layer=bottom`), das genau ueber diesem Platzhalter liegt:
// durchsichtiger Hintergrund, keine Eingabe, Farben aus dem Widget.
//
// - Bearbeiten: Panel weg (es laege unter der Bearbeitungsebene), hier steht
//   ein Platzhalter. Nach "Fertig" startet es an der neuen Stelle.
// - Desktop verdeckt (`active: false`): SIGSTOP an kitty, danach SIGCONT.
//   Das Programm blockiert dann am vollen Terminal-Puffer und rechnet nicht.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    readonly property var forms: ({ "quer": [36, 20], "hoch": [20, 32], "breit": [56, 14] })
    readonly property var form: root.forms[root.opts.form] ?? root.forms["quer"]

    // Programme mit ihren Aufrufen; Farben kommen ueber die kitty-Palette
    readonly property var programs: ({
        "cmatrix": ["cmatrix", "-b", "-u", "5", "-C", "green"],
        "cava": ["cava"],
        "btop": ["btop"],
        "cbonsai": ["cbonsai", "-l", "-i", "-w", "4"]
    })
    readonly property var program: root.programs[root.opts.program] ?? root.programs["cmatrix"]

    implicitWidth: Math.round(root.form[0] * root.unit)
    implicitHeight: Math.round(root.form[1] * root.unit)

    function hex(c: color): string {
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0");
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    // Lage auf dem Ausgang; wird beim (Neu-)Start gelesen
    property string geometry: ""
    readonly property string screenName: root.QsWindow.window?.screen?.name ?? ""

    function measure(): void {
        const p = root.mapToItem(null, 0, 0);
        root.geometry = [root.screenName, Math.round(p.x), Math.round(p.y),
            Math.round(root.width), Math.round(root.height), root.program.join(" "),
            root.hex(root.color), root.hex(root.accent)].join("|");
    }

    // Lage erst nach dem Einschwingen messen (Laden, Szenenwechsel, Fertig)
    Timer {
        id: settle

        interval: 400
        onTriggered: root.measure()
    }

    onEditingChanged: if (!root.editing) settle.restart()
    onWidthChanged: settle.restart()
    onHeightChanged: settle.restart()
    onXChanged: settle.restart()
    onYChanged: settle.restart()
    onProgramChanged: settle.restart()
    Component.onCompleted: settle.restart()

    readonly property bool wanted: !root.editing && root.visible && root.geometry !== "" && root.screenName !== ""

    onGeometryChanged: {
        if (panel.running) {
            panel.running = false;
            restart.restart();
        }
    }

    Timer {
        id: restart

        interval: 150
        onTriggered: panel.running = Qt.binding(() => root.wanted)
    }

    Process {
        id: panel

        running: root.wanted

        command: {
            const g = root.geometry.split("|");
            const fg = root.hex(root.color), ac = root.hex(root.accent);
            return ["kitty", "+kitten", "panel",
                "--edge=none", "--layer=bottom", "--focus-policy=not-allowed",
                `--output-name=${g[0]}`,
                `--margin-left=${g[1]}`, `--margin-top=${g[2]}`,
                `--columns=${g[3]}px`, `--lines=${g[4]}px`,
                "--class=dynamic-island-tui",
                "-o", "background_opacity=0",
                "-o", `font_size=${Math.max(6, Math.round(root.unit * 0.55))}`,
                "-o", `foreground=${fg}`,
                // cmatrix/cava/btop nutzen die Grundfarben: gruen = Akzent
                "-o", `color2=${ac}`, "-o", `color10=${ac}`,
                "-o", `color7=${fg}`, "-o", `color15=${fg}`,
                "-o", "cursor_shape=block", "-o", "cursor_blink_interval=0",
                ...root.program];
        }

        onRunningChanged: {
            if (panel.running && !root.active)
                panel.signal(19);
        }
    }

    // SIGSTOP / SIGCONT
    onActiveChanged: {
        if (panel.running)
            panel.signal(root.active ? 18 : 19);
    }

    // Platzhalter beim Bearbeiten
    Rectangle {
        anchors.fill: parent
        visible: root.editing
        radius: 8
        color: Colors.alpha("#000000", 0.45)
        border.width: 1
        border.color: Colors.alpha(root.accent, 0.6)

        Column {
            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "terminal"
                color: root.accent
                font.family: "Material Symbols Outlined"
                font.pixelSize: root.unit * 2
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.program[0]
                color: root.color
                font.family: Config.font
                font.pixelSize: root.unit
            }
        }
    }
}
