pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Zifferblatt-Weiche: laedt je `style` eine der Uhr-Varianten aus diesem
// Ordner. Die Faces werden zweimal benutzt – klein in der Notch (size ~17)
// und gross als Desktop-Widget (size bis ~300) – und skalieren deshalb ueber
// `size` (Pixelhoehe der Hauptziffern bzw. Durchmesser-Basis), nicht per
// `scale`.
//
//     ClockFace { style: "split"; date: clock.date; size: 17 }
//
// Stile: "digital", "split", "gestapelt", "analog", "worte" – alles andere
// faellt auf digital zurueck. Die Zeit kommt per `date` von aussen (Minuten-
// Genauigkeit reicht): kein Timer, keine Dauer-Animation in den Faces.
Item {
    id: root

    property string style: "digital"
    property date date
    // Pixelhoehe der Hauptziffern (Analog: Basis des Durchmessers)
    property real size: 16
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property bool use12h: Config.appearance.clock === "12h"
    // Zweite Zeile mit dem Datum ("Mittwoch, 22. Oktober") – fuer den Desktop
    property bool showDate: false
    property string fontFamily: Config.font
    property int weight: Font.Bold

    // Das geladene Face (fuer Tests/Vorschau)
    readonly property Item face: faceLoader.item

    implicitWidth: Math.max(faceLoader.implicitWidth, dateLabel.visible ? dateLabel.implicitWidth : 0)
    implicitHeight: faceLoader.implicitHeight + (dateLabel.visible ? dateLabel.implicitHeight + column.spacing : 0)

    Column {
        id: column

        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Math.round(root.size * 0.12)

        Loader {
            id: faceLoader

            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: root.style === "split" ? split
                           : root.style === "gestapelt" ? stacked
                           : root.style === "analog" ? analog
                           : root.style === "worte" ? words
                           : digital
        }

        Text {
            id: dateLabel

            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.showDate
            text: I18n.date(root.date, "dddd, d. MMMM", "dddd, MMMM d")
            color: root.color
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Math.max(11, Math.round(root.size * 0.26))
            font.weight: Font.Medium
            font.letterSpacing: 0.3
        }
    }

    Component {
        id: digital
        ClockDigital {
            date: root.date; size: root.size; color: root.color; accent: root.accent
            use12h: root.use12h; fontFamily: root.fontFamily; weight: root.weight
        }
    }
    Component {
        id: split
        ClockSplit {
            date: root.date; size: root.size; color: root.color; accent: root.accent
            use12h: root.use12h; fontFamily: root.fontFamily; weight: root.weight
        }
    }
    Component {
        id: stacked
        ClockStacked {
            date: root.date; size: root.size; color: root.color; accent: root.accent
            use12h: root.use12h; fontFamily: root.fontFamily; weight: root.weight
        }
    }
    Component {
        id: analog
        ClockAnalog {
            date: root.date; size: root.size; color: root.color; accent: root.accent
            use12h: root.use12h; fontFamily: root.fontFamily; weight: root.weight
        }
    }
    Component {
        id: words
        ClockWords {
            date: root.date; size: root.size; color: root.color; accent: root.accent
            use12h: root.use12h; fontFamily: root.fontFamily; weight: root.weight
        }
    }
}
