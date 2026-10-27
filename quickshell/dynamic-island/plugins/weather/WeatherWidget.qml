pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

import qs
import qs.modules.services.config

// Wetter auf dem Desktop, in der Sprache der Notch: frei stehende, monochrome
// Typografie direkt auf dem Wallpaper (keine Karte), Inter Display fuer die
// grosse Temperatur, Ort als kleine Versalien-Kopfzeile mit Akzentpunkt,
// Symbole aus Material Symbols. Stile (opts.style):
//
//   aktuell   grosses Symbol + grosse Temperatur, Beschreibung, Min/Max heute
//   stunden   Jetzt kompakt, darunter die naechsten acht Stunden als Reihe
//   woche     sieben Tage mit Temperatur-Spannbalken (wie iOS)
//   kompakt   eine Zeile: Symbol, Temperatur, Beschreibung
//
// opts.details haengt eine Zeile mit Gefuehlt/Wind/Regen/Sonne an (bzw. die
// Regen-% in den Reihen), opts.place zeigt den Ort als Kopfzeile.
//
// Daten kommen vom Dienst des Plugins (plugin.main.data -> wx, da "data"
// die Default-Property von Item ist; Format im Kopf von
// weather.py). Ohne Daten steht ein ruhiger Hinweis, veraltete Daten bekommen
// eine kleine "Stand HH:MM"-Notiz in der Kopfzeile.
//
// Der weiche Schatten haengt an einer Layer-Textur des Inhalts – sie wird nur
// neu gezeichnet, wenn sich der Inhalt aendert (alle 15 min mit den Daten).
// Keine Animationen, keine Timer: bei active == false passiert hier nichts.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property var plugin: null

    readonly property string style: root.opts.style ?? "aktuell"
    readonly property bool details: root.opts.details ?? true
    readonly property bool showPlace: root.opts.place ?? true

    readonly property var wx: root.plugin?.main?.data ?? null
    readonly property bool ready: root.wx?.ok === true && !!root.wx?.current
    readonly property bool loading: root.plugin?.main?.loading === true
    readonly property bool stale: root.ready && root.wx?.stale === true
    readonly property var cur: root.ready ? root.wx.current : null
    readonly property var today: root.ready ? (root.wx.today ?? null) : null
    readonly property var hours: root.ready ? (root.wx.hours ?? []).slice(0, 8) : []
    readonly property var days: root.ready ? (root.wx.days ?? []).slice(0, 7) : []

    // Zeit des letzten Abrufs fuer den Stale-Hinweis
    readonly property string updatedAt: {
        if (!root.wx?.updated)
            return "";
        const d = new Date(root.wx.updated);
        return isNaN(d.getTime()) ? "" : Qt.formatTime(d, "HH:mm");
    }

    readonly property string display: Qt.fontFamilies().includes("Inter Display") ? "Inter Display" : Config.font
    readonly property color dim: Colors.alpha(root.color, 0.72)
    readonly property color faint: Colors.alpha(root.color, 0.45)

    implicitWidth: body.width
    implicitHeight: body.height

    function deg(t): string {
        return (t === undefined || t === null) ? "–" : Math.round(t) + "°";
    }

    // ---- Bausteine ----

    // Material-Symbol, gefuellt
    component Icon: Text {
        property real px: root.unit * 1.2
        property bool fill: true

        color: root.color
        font.family: "Material Symbols Outlined"
        font.pixelSize: px
        font.variableAxes: ({ FILL: fill ? 1 : 0, wght: 400, opsz: 48 })
        verticalAlignment: Text.AlignVCenter
    }

    // Normaler Text in der Shell-Schrift
    component Label: Text {
        property real px: root.unit * 1.0

        color: root.color
        font.family: Config.font
        font.pixelSize: px
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }

    // Temperatur im Display-Schnitt, eng gesetzt
    component Temp: Text {
        property real px: root.unit * 5
        property int w: Font.DemiBold

        color: root.color
        font.family: root.display
        font.pixelSize: px
        font.weight: w
        font.letterSpacing: -px * 0.04
        font.features: ({ "tnum": 1 })
    }

    // Kleine Kopfzeile mit Akzentpunkt
    component Caption: Row {
        id: cap

        property string text: ""
        property string note: ""
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
            text: cap.text
            color: root.dim
            font.family: Config.font
            font.pixelSize: cap.px
            font.weight: Font.DemiBold
        }

        Text {
            visible: cap.note !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: (cap.text !== "" ? "· " : "") + cap.note
            color: root.faint
            font.family: Config.font
            font.pixelSize: cap.px
            font.weight: Font.Medium
        }
    }

    // Kopfzeile: Ort und/oder Stale-Hinweis
    component Header: Caption {
        visible: (root.showPlace && (root.wx?.place ?? "") !== "") || root.stale
        text: root.showPlace ? (root.wx?.place ?? "") : ""
        note: root.stale && root.updatedAt !== "" ? I18n.tr("Stand %1").arg(root.updatedAt) : ""
    }

    // Ein Wert mit kleinem Symbol davor (Detailzeile)
    component Fact: Row {
        property string icon: ""
        property string value: ""

        spacing: root.unit * 0.3

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.icon
            px: root.unit * 1.0
            fill: false
            color: root.dim
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            px: root.unit * 0.85
            color: root.dim
        }
    }

    // Detailzeile: gefuehlt, Wind, Regen-%, Sonnenauf-/untergang
    component Details: Row {
        spacing: root.unit * 0.9

        Fact { icon: "thermostat"; value: "gefuehlt " + root.deg(root.cur?.feels) }
        Fact { icon: "air"; value: Math.round(root.cur?.wind ?? 0) + " km/h" }
        Fact { icon: "water_drop"; value: Math.round(root.today?.rain ?? root.cur?.precip ?? 0) + " %" }
        Fact { visible: !!root.today?.sunrise; icon: "wb_twilight"; value: (root.today?.sunrise ?? "") + " – " + (root.today?.sunset ?? "") }
    }

    // ---- Inhalt mit Schatten ----
    Item {
        id: body

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

                sourceComponent: !root.ready ? placeholder
                               : root.style === "stunden" ? hourly
                               : root.style === "woche" ? weekly
                               : root.style === "kompakt" ? compact
                               : current
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

    // ---- Ohne Daten: laedt / Fehler ----
    Component {
        id: placeholder

        Row {
            spacing: root.unit * 0.7

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.loading && !root.wx ? "sync" : root.wx ? "cloud_off" : "cloud"
                px: root.unit * 1.6
                fill: false
                color: root.dim
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.unit * 0.25

                Caption {
                    text: root.loading && !root.wx ? I18n.tr("WETTER WIRD GELADEN")
                        : root.wx ? I18n.tr("WETTER NICHT VERFUEGBAR")
                        : I18n.tr("KEINE WETTERDATEN")
                }

                Label {
                    visible: (root.wx?.error ?? "") !== ""
                    text: root.wx?.error ?? ""
                    px: root.unit * 0.8
                    color: root.faint
                    elide: Text.ElideRight
                    width: root.unit * 16
                }
            }
        }
    }

    // ---- aktuell ----
    Component {
        id: current

        Column {
            spacing: root.unit * 0.5

            Header {}

            Row {
                spacing: root.unit * 0.9

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.cur?.icon ?? "cloud"
                    px: root.unit * 4.6
                }

                Temp {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.deg(root.cur?.temp)
                    px: root.unit * 5.2
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.unit * 0.15
                    leftPadding: root.unit * 0.2

                    Label {
                        text: I18n.tr(root.cur?.text ?? "")
                        px: root.unit * 1.15
                        font.weight: Font.DemiBold
                    }

                    Row {
                        spacing: root.unit * 0.5

                        Label { text: "H " + root.deg(root.today?.max); px: root.unit * 0.95; color: root.dim }
                        Label { text: "T " + root.deg(root.today?.min); px: root.unit * 0.95; color: root.faint }
                    }
                }
            }

            Details {
                visible: root.details
                topPadding: root.unit * 0.1
            }
        }
    }

    // ---- stunden ----
    Component {
        id: hourly

        Column {
            spacing: root.unit * 0.8

            Header {}

            Row {
                spacing: root.unit * 0.6

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.cur?.icon ?? "cloud"
                    px: root.unit * 2.4
                }

                Temp {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.deg(root.cur?.temp)
                    px: root.unit * 2.6
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: root.unit * 0.3
                    text: I18n.tr(root.cur?.text ?? "")
                    px: root.unit * 1.05
                    font.weight: Font.DemiBold
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "H " + root.deg(root.today?.max) + "  T " + root.deg(root.today?.min)
                    px: root.unit * 0.9
                    color: root.dim
                }
            }

            Row {
                spacing: root.unit * 0.55

                Repeater {
                    model: root.hours

                    Column {
                        id: hour

                        required property var modelData
                        required property int index

                        width: root.unit * 2.8
                        spacing: root.unit * 0.3

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: hour.index === 0 ? I18n.tr("Jetzt") : (hour.modelData.time ?? "")
                            px: root.unit * 0.75
                            color: hour.index === 0 ? root.color : root.dim
                            font.weight: Font.DemiBold
                            font.letterSpacing: root.unit * 0.04
                        }

                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: hour.modelData.icon ?? "cloud"
                            px: root.unit * 1.5
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.deg(hour.modelData.temp)
                            px: root.unit * 1.0
                            font.weight: Font.DemiBold
                        }

                        Label {
                            visible: root.details
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: (hour.modelData.rain ?? 0) > 0 ? Math.round(hour.modelData.rain) + " %" : "·"
                            px: root.unit * 0.7
                            color: (hour.modelData.rain ?? 0) >= 50 ? root.accent : root.faint
                        }
                    }
                }
            }
        }
    }

    // ---- woche ----
    Component {
        id: weekly

        Column {
            id: week

            // Spanne der ganzen Woche fuer die Balken
            readonly property real wmin: root.days.length ? Math.min(...root.days.map(d => d.min)) : 0
            readonly property real wmax: root.days.length ? Math.max(...root.days.map(d => d.max)) : 1
            readonly property real range: Math.max(1, week.wmax - week.wmin)
            readonly property real track: root.unit * 7

            spacing: root.unit * 0.45

            Header {}

            Repeater {
                model: root.days

                Row {
                    id: day

                    required property var modelData
                    required property int index

                    readonly property bool today: day.index === 0

                    spacing: root.unit * 0.7

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.unit * 2.6
                        text: day.today ? I18n.tr("Heute") : I18n.tr(day.modelData.weekday ?? "")
                        px: root.unit * 0.95
                        font.weight: Font.DemiBold
                        color: day.today ? root.color : root.dim
                    }

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.unit * 1.7
                        horizontalAlignment: Text.AlignHCenter
                        text: day.modelData.icon ?? "cloud"
                        px: root.unit * 1.35
                    }

                    Label {
                        visible: root.details
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.unit * 2.2
                        horizontalAlignment: Text.AlignRight
                        text: (day.modelData.rain ?? 0) > 0 ? Math.round(day.modelData.rain) + " %" : ""
                        px: root.unit * 0.75
                        color: (day.modelData.rain ?? 0) >= 50 ? root.accent : root.faint
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.unit * 1.8
                        horizontalAlignment: Text.AlignRight
                        text: root.deg(day.modelData.min)
                        px: root.unit * 0.95
                        color: root.faint
                    }

                    // Spannbalken: Spur ueber die Woche, Fuellung Min..Max des Tages,
                    // heute mit Akzentpunkt bei der aktuellen Temperatur
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: week.track
                        height: root.unit * 0.35

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Colors.alpha(root.color, 0.16)
                        }

                        Rectangle {
                            x: ((day.modelData.min ?? week.wmin) - week.wmin) / week.range * parent.width
                            width: Math.max(height, ((day.modelData.max ?? week.wmax) - (day.modelData.min ?? week.wmin)) / week.range * parent.width)
                            height: parent.height
                            radius: height / 2
                            color: Colors.alpha(root.color, day.today ? 0.95 : 0.6)
                        }

                        Rectangle {
                            visible: day.today && root.cur !== null
                            x: Math.min(parent.width - width, Math.max(0, ((root.cur?.temp ?? week.wmin) - week.wmin) / week.range * parent.width - width / 2))
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.unit * 0.55
                            height: width
                            radius: width / 2
                            color: root.accent
                            border.width: Math.max(1, root.unit * 0.1)
                            border.color: Colors.alpha("#000000", 0.5)
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.unit * 1.8
                        text: root.deg(day.modelData.max)
                        px: root.unit * 0.95
                        font.weight: Font.DemiBold
                    }
                }
            }
        }
    }

    // ---- kompakt ----
    Component {
        id: compact

        Row {
            spacing: root.unit * 0.55

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.cur?.icon ?? "cloud"
                px: root.unit * 1.9
            }

            Temp {
                anchors.verticalCenter: parent.verticalCenter
                text: root.deg(root.cur?.temp)
                px: root.unit * 2.0
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr(root.cur?.text ?? "")
                px: root.unit * 1.05
                font.weight: Font.DemiBold
            }

            Label {
                visible: root.details
                anchors.verticalCenter: parent.verticalCenter
                text: "H " + root.deg(root.today?.max) + "  T " + root.deg(root.today?.min)
                px: root.unit * 0.9
                color: root.dim
            }

            Caption {
                visible: (root.showPlace && (root.wx?.place ?? "") !== "") || root.stale
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: root.unit * 0.3
                text: root.showPlace ? (root.wx?.place ?? "") : ""
                note: root.stale && root.updatedAt !== "" ? I18n.tr("Stand %1").arg(root.updatedAt) : ""
                px: root.unit * 0.75
            }
        }
    }
}
