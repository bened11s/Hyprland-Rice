pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Senkrechter Regler fuer das OSD am rechten Rand. Eine Spur, die sich von unten fuellt, darauf ein runder
// Griff mit dem Symbol – waehrend man zieht oder der Wert sich gerade
// geaendert hat, steht statt des Symbols die Prozentzahl.
//
//   Ziehen / Klicken   setzt den Wert (Signal `moved`)
//   Mausrad            eine Stufe rauf oder runter
//   Klick auf den Griff ohne Bewegung   Signal `handleTapped` (z.B. Stumm)
Item {
    id: slider

    required property string icon
    property real value: 0
    property real step: 0.05
    // Gedaempfter Zustand (stumm): Fuellung in der Fehlerfarbe
    property bool muted: false
    property bool interactive: true

    signal moved(real value)
    signal handleTapped()

    readonly property real handleSize: width
    readonly property real travel: height - handleSize
    readonly property bool dragging: area.pressed && area.movedSincePress
    property bool showValue: false

    implicitWidth: 30
    implicitHeight: 112
    opacity: slider.interactive ? 1 : 0.45

    onValueChanged: {
        slider.showValue = true;
        valueFlash.restart();
    }

    function valueAt(y: real): real {
        return Math.max(0, Math.min(1, 1 - (y - slider.handleSize / 2) / slider.travel));
    }

    Timer {
        id: valueFlash

        interval: 700
        onTriggered: {
            if (!area.pressed)
                slider.showValue = false;
        }
    }

    // ---- Spur ----
    // Dieselben Farben wie der Lautstaerke-Regler in der Settings-Karte
    // (LevelSlider): neutrale Spur, volle Akzent-Fuellung, das Symbol sitzt
    // oben in der Fuellung. Der Griff ist das obere Ende der Fuellung.
    readonly property color accent: slider.muted ? Colors.error : Colors.primary
    readonly property color foreground: slider.muted ? Colors.fgError : Colors.fgPrimary

    Rectangle {
        id: track

        anchors.fill: parent
        radius: width / 2
        color: Colors.alpha(Colors.fgSurface, 0.16)

        // Fuellung von unten bis zur Griff-Mitte
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: track.height - handle.y
            radius: parent.radius
            color: slider.accent

            Behavior on color {
                ColorAnimation { duration: 140 }
            }
        }
    }

    // ---- Griff ----
    Rectangle {
        id: handle

        width: slider.handleSize
        height: slider.handleSize
        radius: width / 2
        y: (1 - Math.max(0, Math.min(1, slider.value))) * slider.travel
        color: slider.accent
        scale: area.pressed ? 1.06 : 1

        Behavior on color {
            ColorAnimation { duration: 140 }
        }

        Behavior on y {
            enabled: !slider.dragging
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: slider.showValue ? 0 : 1
            text: slider.showValue ? Math.round(slider.value * 100) : slider.icon
            color: slider.foreground
            font.family: slider.showValue ? Config.font : "Material Symbols Outlined"
            font.pixelSize: slider.showValue ? 9 : 14
            font.weight: slider.showValue ? Font.Bold : Font.Normal
        }
    }

    MouseArea {
        id: area

        property bool movedSincePress: false
        property real pressY: 0

        anchors.fill: parent
        enabled: slider.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        onPressed: mouse => {
            area.movedSincePress = false;
            area.pressY = mouse.y;
            // Klick neben dem Griff springt sofort dorthin
            if (mouse.y < handle.y || mouse.y > handle.y + handle.height) {
                area.movedSincePress = true;
                slider.moved(slider.valueAt(mouse.y));
            }
        }
        onPositionChanged: mouse => {
            if (!area.pressed)
                return;
            if (Math.abs(mouse.y - area.pressY) > 3)
                area.movedSincePress = true;
            if (area.movedSincePress)
                slider.moved(slider.valueAt(mouse.y));
        }
        onReleased: mouse => {
            if (!area.movedSincePress)
                slider.handleTapped();
            valueFlash.restart();
        }
    }

    WheelHandler {
        enabled: slider.interactive
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        property real acc: 0

        onWheel: event => {
            acc += event.angleDelta.y;
            if (Math.abs(acc) >= 120) {
                slider.moved(Math.max(0, Math.min(1, slider.value + (acc > 0 ? slider.step : -slider.step))));
                acc = 0;
            }
            event.accepted = true;
        }
    }
}
