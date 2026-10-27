pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Regler-Kachel im Android-Stil: die ganze Kachel ist die Spur. Von links
// fuellt sie sich in der Akzentfarbe, darueber liegen Symbol, Titel und
// Prozentzahl – auf der Fuellung in der Akzent-Vordergrundfarbe, daneben in
// Neutral (zwei Textlagen, die obere auf die Fuellbreite geclippt).
//
//   Ziehen / Klicken   setzt den Wert (Signal `adjusted`)
//   Mausrad            5 % rauf oder runter
//   Pfeil rechts       `detailsRequested` (z.B. Audio-Panel), wenn
//                      detailsAvailable
//   Symbol links       `iconClicked` (z.B. stummschalten), wenn
//                      iconClickable – die Zone setzt dann keinen Wert
Rectangle {
    id: root

    required property string title
    required property string icon
    property real value: 0
    property color accent: Colors.primary
    property color foreground: Colors.fgPrimary
    property bool detailsAvailable: false
    property bool iconClickable: false

    signal adjusted(real value)
    signal detailsRequested()
    signal iconClicked()

    readonly property real fillWidth: width * Math.max(0, Math.min(1, root.value))
    readonly property real detailsReserve: root.detailsAvailable ? 40 : 0
    readonly property real iconReserve: root.iconClickable ? 50 : 0

    implicitHeight: 54
    radius: height / 2
    color: Colors.alpha(Colors.fgSurface, 0.08)
    clip: true

    function adjustAt(x: real): void {
        root.adjusted(Math.max(0, Math.min(1, x / root.width)));
    }

    // ---- Fuellung ----
    Rectangle {
        width: root.fillWidth
        height: parent.height
        radius: root.radius
        color: root.accent

        Behavior on width {
            enabled: !inputArea.pressed
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: 140 }
        }
    }

    // Hover-Schleier
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Colors.alpha(Colors.fgSurface, inputArea.containsMouse ? 0.05 : 0)

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
    }

    // ---- Beschriftung, Lage 1: neutral ----
    component Label: Item {
        id: label

        property color fg: Colors.fgBackground
        property color fgDim: Colors.fgSurfaceVariant

        // Immer so gross wie die ganze Kachel – auch in der geclippten Lage,
        // sonst rutscht die Prozentzahl an die Fuellkante und steht doppelt da
        width: root.width
        height: root.height

        Text {
            id: labelIcon

            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: root.icon
            font.family: "Material Symbols Outlined"
            font.pixelSize: 22
            color: label.fg
        }

        Text {
            font.family: Config.font
            anchors {
                left: labelIcon.right
                leftMargin: 12
                verticalCenter: parent.verticalCenter
            }
            text: root.title
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: label.fg
        }

        Text {
            font.family: Config.font
            anchors {
                right: parent.right
                rightMargin: 16 + root.detailsReserve
                verticalCenter: parent.verticalCenter
            }
            // Anzeige immer 0-100, egal was der Dienst gerade liefert
            text: `${Math.round(Math.max(0, Math.min(1, root.value)) * 100)} %`
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: label.fgDim
        }
    }

    Label {}

    // ---- Beschriftung, Lage 2: auf der Fuellung, geclippt ----
    Item {
        width: root.fillWidth
        height: parent.height
        clip: true

        Behavior on width {
            enabled: !inputArea.pressed
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Label {
            fg: root.foreground
            fgDim: Colors.alpha(root.foreground, 0.8)
        }
    }

    MouseArea {
        id: inputArea

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            rightMargin: root.detailsReserve
            leftMargin: root.iconReserve
        }
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => root.adjustAt(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                root.adjustAt(mouse.x);
        }
    }

    // Eigene Klickflaeche fuer das Symbol, ueber beiden Beschriftungslagen
    MouseArea {
        id: iconArea

        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: root.iconReserve
        visible: root.iconClickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.iconClicked()

        Rectangle {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 3
            width: 36
            height: 36
            radius: height / 2
            color: Colors.alpha(Colors.fgSurface, iconArea.containsMouse ? 0.12 : 0)

            Behavior on color {
                ColorAnimation { duration: 120 }
            }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        property real acc: 0

        onWheel: event => {
            acc += event.angleDelta.y;
            if (Math.abs(acc) >= 120) {
                const base = Math.max(0, Math.min(1, root.value));
                root.adjusted(Math.max(0, Math.min(1, base + (acc > 0 ? 0.05 : -0.05))));
                acc = 0;
            }
            event.accepted = true;
        }
    }

    // ---- Pfeil zu den Details (Audio-Panel) ----
    Rectangle {
        anchors {
            right: parent.right
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        width: 34
        height: 34
        radius: 17
        visible: root.detailsAvailable
        // Liegt der Pfeil schon auf der Fuellung, Knopf in der Vordergrundfarbe
        readonly property bool onFill: root.fillWidth > root.width - 44
        color: detailsArea.containsMouse ? Colors.alpha(onFill ? root.foreground : Colors.fgSurface, 0.3)
                                         : Colors.alpha(onFill ? root.foreground : Colors.fgSurface, 0.14)

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Text {
            anchors.centerIn: parent
            text: "chevron_right"
            color: parent.onFill ? root.foreground : Colors.fgBackground
            font.family: "Material Symbols Outlined"
            font.pixelSize: 18
        }

        MouseArea {
            id: detailsArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.detailsRequested()
        }
    }
}
