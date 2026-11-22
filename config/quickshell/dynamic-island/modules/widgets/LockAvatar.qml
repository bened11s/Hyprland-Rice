pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import qs
import qs.modules.services.config

// ~/.face als Kreis mit Ring in der Zustandsfarbe; ohne Bild das Symbol
Item {
    id: av

    property real size: 48
    property color ring: "white"
    property color fg: Colors.fgSurface

    width: av.size
    height: av.size

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Colors.alpha(av.fg, 0.08)
        border.width: 2
        border.color: Colors.alpha(av.ring, 0.85)

        Behavior on border.color { ColorAnimation { duration: Appearance.fadeDuration } }
    }

    Image {
        id: face

        anchors.fill: parent
        anchors.margins: 4
        source: "file://" + Quickshell.env("HOME") + "/.face"
        sourceSize: Qt.size(96, 96)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    Rectangle {
        id: faceMask

        anchors.fill: face
        radius: width / 2
        layer.enabled: true
        visible: false
    }

    MultiEffect {
        anchors.fill: face
        source: face
        maskEnabled: true
        maskSource: faceMask
        visible: face.status === Image.Ready
    }

    Text {
        anchors.centerIn: parent
        visible: face.status !== Image.Ready
        text: "person"
        color: av.fg
        font.family: "Material Symbols Outlined"
        font.pixelSize: av.size * 0.5
        font.variableAxes: { "FILL": 1 }
    }
}
