pragma ComponentBehavior: Bound
import QtQuick

import qs

// Matrix-Regen als Desktop-Widget (Vertrag: modules/desktop/WidgetHost.qml).
//
// Alles passiert in einem Fragment-Shader (matrix.frag, kompiliert zu
// matrix.frag.qsb mit `qsb --glsl "100 es,120,150" --hlsl 50 --msl 12`):
// ein Rechteck, ein Draw-Call, egal wie viele Zeichen. Die Glyphen liegen
// einmal gerendert in einem Atlas. Bewegt wird nur die Zeit-Uniform, per
// Timer mit der Desktop-Bildrate (Einstellung fps des Plugins desktop) statt per Animation – eine
// Animation liefe mit der Monitorrate (180 Hz). Verdeckter Desktop: Timer
// steht, das letzte Bild bleibt.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property int fps: 30

    readonly property var forms: ({
        "quer": [30, 20],
        "hoch": [18, 30],
        "breit": [48, 12],
        "spalte": [8, 40]
    })
    readonly property var form: root.forms[root.opts.form] ?? root.forms["quer"]

    readonly property string glyphSet: {
        switch (root.opts.glyphs) {
        case "binär": return "01";
        case "hex": return "0123456789ABCDEF";
        }
        // Halbbreite Katakana wie im Film, dazu Ziffern und ein paar Zeichen
        return "ｦｱｳｴｵｶｷｹｺｻｼｽｾｿﾀﾂﾃﾅﾆﾇﾈﾊﾋﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ0123456789Z:・.\"=*+-<>¦|";
    }
    readonly property bool kana: !root.opts.glyphs || root.opts.glyphs === "katakana"
    readonly property string fontFamily: {
        const have = Qt.fontFamilies();
        if (root.kana && have.includes("Noto Sans CJK JP"))
            return "Noto Sans CJK JP";
        for (const f of ["JetBrainsMono Nerd Font", "JetBrains Mono NL", "Noto Sans Mono"])
            if (have.includes(f))
                return f;
        return "monospace";
    }

    readonly property real cellW: Math.round(root.unit * 1.1)
    readonly property real cellH: Math.round(root.unit * 1.4)

    implicitWidth: Math.round(root.form[0] * root.unit / root.cellW) * root.cellW
    implicitHeight: Math.round(root.form[1] * root.unit / root.cellH) * root.cellH

    // ---- Atlas: alle Glyphen nebeneinander, gespiegelt wie im Film ----
    Row {
        id: atlas

        Repeater {
            model: root.glyphSet.length

            Item {
                required property int index

                width: root.cellW
                height: root.cellH

                Text {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.glyphSet.charAt(parent.index)
                    color: "white"
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(root.cellH * 0.82)
                    font.weight: Font.Medium
                    transform: Scale {
                        origin.x: root.cellW / 2
                        xScale: root.kana ? -1 : 1
                    }
                }
            }
        }
    }

    ShaderEffectSource {
        id: atlasTex

        sourceItem: atlas
        hideSource: true
        smooth: true
    }

    ShaderEffect {
        id: rain

        anchors.fill: parent

        property real time: 0
        property real cols: Math.max(1, Math.round(root.width / root.cellW))
        property real rows: Math.max(1, Math.round(root.height / root.cellH))
        property real glyphs: root.glyphSet.length
        property real speed: root.opts.speed === "langsam" ? 5 : root.opts.speed === "schnell" ? 16 : 9
        property real density: root.opts.density === "dünn" ? 0.45 : root.opts.density === "dicht" ? 0.97 : 0.78
        property color headColor: Colors.mix(root.accent, "#ffffff", 0.75)
        property color trailColor: root.accent
        property variant atlas: atlasTex

        fragmentShader: Qt.resolvedUrl("matrix.frag.qsb")
    }

    Timer {
        running: root.active && root.visible
        repeat: true
        interval: Math.round(1000 / Math.max(5, root.fps))
        onTriggered: rain.time += interval / 1000
    }
}
