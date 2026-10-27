pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell

import qs
import qs.modules.services.config
import qs.modules.widgets.clock

// Uhr auf dem Desktop, in der Sprache der Notch: ruhige, monochrome
// Typografie (Inter Display fuer die grossen Ziffern, Datum als kleine
// Versalien-Zeile), Akzent nur als Punkt. Stile:
//
//   insel            schwarze Pille wie die Notch, Zeit + Datum
//   sperrbildschirm  Datum ueber grosser Zeit, frei auf dem Bild
//   kontrast         Stunden fett, Minuten duenn – ohne Doppelpunkt
//   gestapelt        Stunden ueber Minuten, Minuten zurueckgenommen
//   analog, worte    Zifferblaetter aus modules/widgets/clock
//
// Freistehende Stile bekommen einen weichen Schatten, damit sie auf jedem
// Wallpaper lesbar sind. Er haengt an einer Layer-Textur, die sich nur mit
// der Minute aendert – ein Neuzeichnen pro Minute.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    // Alte Stilnamen aus frueheren Szenen
    readonly property string style: {
        const s = root.opts.style ?? "sperrbildschirm";
        return ({ "digital": "sperrbildschirm", "split": "kontrast" })[s] ?? s;
    }
    readonly property bool island: root.style === "insel"
    readonly property bool showDate: root.opts.date ?? true
    readonly property bool use12h: Config.appearance.clock === "12h"

    readonly property string display: Qt.fontFamilies().includes("Inter Display") ? "Inter Display" : Config.font
    readonly property string hours: Qt.formatDateTime(clock.date, root.use12h ? "h" : "HH")
    readonly property string minutes: Qt.formatDateTime(clock.date, "mm")
    readonly property string dateLine: I18n.date(clock.date, "dddd · d. MMMM", "dddd · MMMM d")

    implicitWidth: root.island ? card.width : body.width
    implicitHeight: root.island ? card.height : body.height

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    // Kleine Datumszeile mit Akzentpunkt
    component Caption: Row {
        id: cap

        property color tint: root.color
        property real px: root.unit * 0.8

        spacing: cap.px * 0.6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: cap.px * 0.45
            height: width
            radius: width / 2
            color: root.accent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.dateLine
            color: Colors.alpha(cap.tint, 0.72)
            font.family: Config.font
            font.pixelSize: cap.px
            font.weight: Font.DemiBold
        }
    }

    // Grosse Ziffern: Display-Schnitt, eng gesetzt, Ziffern gleich breit.
    // Die Hoehe ist die echte Ziffernhoehe (aus den Glyphen gemessen), die
    // Grundlinie liegt an der Unterkante – die Zeilenbox der Schrift ist fuer
    // Ziffern viel zu hoch, Abstaende stimmten mit ihr nie.
    component Digits: Item {
        id: digits

        property alias text: label.text
        property real px: root.unit * 6
        property int w: Font.Medium
        property color tint: root.color

        // Die Schriftgroesse lesen, damit neu gemessen wird: der Aufruf allein
        // ist fuer QML keine Abhaengigkeit – beim Skalieren blieb sonst die
        // alte Hoehe stehen und die Ziffern ragten aus dem Rahmen
        readonly property rect glyphs: metrics.font.pixelSize > 0 && metrics.font.family !== ""
                                       ? metrics.tightBoundingRect("0123456789") : Qt.rect(0, 0, 0, 0)

        implicitWidth: label.implicitWidth
        implicitHeight: Math.ceil(-digits.glyphs.y)

        FontMetrics {
            id: metrics

            font: label.font
        }

        Text {
            id: label

            y: digits.implicitHeight - label.baselineOffset
            color: digits.tint
            font.family: root.display
            font.pixelSize: digits.px
            font.weight: digits.w
            font.letterSpacing: -digits.px * 0.035
            font.features: ({ "tnum": 1 })
        }
    }

    // ---- Freistehend ----
    Item {
        id: body

        visible: !root.island
        width: content.implicitWidth
        height: content.implicitHeight

        Item {
            id: content

            implicitWidth: loader.item?.implicitWidth ?? 0
            implicitHeight: loader.item?.implicitHeight ?? 0
            layer.enabled: true
            visible: false

            Loader {
                id: loader

                sourceComponent: root.style === "kontrast" ? contrast
                               : root.style === "gestapelt" ? stacked
                               : root.style === "analog" || root.style === "worte" ? face
                               : lockscreen
            }
        }

        MultiEffect {
            source: content
            anchors.fill: content
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.45
            shadowBlur: 0.8
            shadowVerticalOffset: Math.round(root.unit * 0.15)
            blurMax: 48
            autoPaddingEnabled: true
        }
    }

    Component {
        id: lockscreen

        Column {
            spacing: root.unit * 1.0

            Caption {
                visible: root.showDate
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Digits {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hours + ":" + root.minutes
                px: root.unit * 7
                w: Font.DemiBold
            }
        }
    }

    Component {
        id: contrast

        Column {
            spacing: root.unit * 1.1

            Row {
                anchors.horizontalCenter: parent.horizontalCenter

                Digits {
                    text: root.hours
                    px: root.unit * 7
                    w: Font.Bold
                }

                Digits {
                    text: root.minutes
                    px: root.unit * 7
                    w: Font.ExtraLight
                    opacity: 0.85
                }
            }

            Caption {
                visible: root.showDate
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Component {
        id: stacked

        Column {
            spacing: root.unit * 0.9

            Digits {
                text: root.hours
                px: root.unit * 7.5
                w: Font.Bold
            }

            Digits {
                text: root.minutes
                px: root.unit * 7.5
                w: Font.Bold
                opacity: 0.45
            }

            Caption {
                visible: root.showDate
                px: root.unit * 0.7
            }
        }
    }

    Component {
        id: face

        Column {
            spacing: root.unit * 0.6

            ClockFace {
                anchors.horizontalCenter: parent.horizontalCenter
                style: root.style
                date: clock.date
                size: root.unit * (root.style === "analog" ? 4.5 : 3.2)
                color: root.color
                accent: root.accent
                fontFamily: root.display
                weight: Font.DemiBold
            }

            Caption {
                visible: root.showDate
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ---- Insel: schwarze Pille wie die Notch ----
    RectangularShadow {
        visible: root.island
        anchors.fill: card
        radius: card.radius
        offset.y: root.unit * 0.25
        blur: root.unit * 1.6
        spread: 0
        color: Colors.alpha("#000000", 0.45)
    }

    Rectangle {
        id: card

        visible: root.island
        width: islandRow.implicitWidth + root.unit * 2.6
        height: islandRow.implicitHeight + root.unit * 1.5
        radius: height / 2
        color: Appearance.notchColor
        border.width: 1
        border.color: Colors.alpha("#ffffff", 0.08)

        Row {
            id: islandRow

            anchors.centerIn: parent
            spacing: root.unit * 1.1

            Digits {
                anchors.verticalCenter: parent.verticalCenter
                text: root.hours + ":" + root.minutes
                px: root.unit * 3.2
                w: Font.DemiBold
                tint: "#f5f5f7"
            }

            Rectangle {
                visible: root.showDate
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: root.unit * 2.2
                color: Colors.alpha("#ffffff", 0.14)
            }

            Column {
                visible: root.showDate
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.unit * 0.15

                Text {
                    text: clock.date.toLocaleDateString(I18n.locale, "dddd")
                    color: "#f5f5f7"
                    font.family: Config.font
                    font.pixelSize: root.unit * 1.0
                    font.weight: Font.DemiBold
                }

                Row {
                    spacing: root.unit * 0.4

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.unit * 0.4
                        height: width
                        radius: width / 2
                        color: root.accent
                    }

                    Text {
                        text: I18n.date(clock.date, "d. MMMM", "MMMM d")
                        color: Colors.alpha("#f5f5f7", 0.55)
                        font.family: Config.font
                        font.pixelSize: root.unit * 0.85
                        font.weight: Font.Medium
                    }
                }
            }
        }
    }
}
