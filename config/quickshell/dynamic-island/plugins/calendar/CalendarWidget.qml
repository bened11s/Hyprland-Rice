pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Qt.labs.qmlmodels
import Quickshell

import qs
import qs.modules.services.config
import "holidays.js" as Holidays

// Kalender auf dem Desktop, in der Sprache der Notch: frei stehende,
// monochrome Typografie direkt auf dem Wallpaper, Akzent nur fuer heute,
// Feiertagspunkte und den Punkt der Kopfzeile. Stile:
//
//   monat     Kopfzeile MONAT JAHR, Raster Mo–So (optional KW-Spalte),
//             heute als gefuellter Kreis, Wochenende zurueckgenommen,
//             Feiertage mit Akzentpunkt, Tage anderer Monate sehr blass
//   woche     grosser Wochentag + Datum, darunter die 7 Tage der Woche
//   streifen  14 Tage ab heute in einer Reihe, schmal und breit – fuer
//             den oberen oder unteren Rand
//
// Darunter (opts.upcoming) die naechsten Feiertage mit "in N Tagen".
//
// Der Inhalt aendert sich nur beim Tageswechsel (SystemClock in Minuten,
// neu gerechnet nur, wenn sich der Tag aendert) oder wenn eine Option
// wirklich anders ist – `opts` kommt bei jeder Aenderung als neues Objekt,
// darum haengen die Modelle an abgeleiteten Strings/Bools, nicht an `opts`.
// Der weiche Schatten liegt auf einer Layer-Textur und kostet darum nur
// beim Neuzeichnen etwas, also praktisch einmal am Tag.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    // ---- Optionen (als Werte, damit ein neues opts-Objekt nichts neu rechnet) ----
    readonly property string style: root.opts.style ?? "monat"
    readonly property bool showWeeks: root.opts.weeks ?? true
    readonly property string state: root.opts.holidays ?? "NW"
    readonly property bool showUpcoming: root.opts.upcoming ?? true

    readonly property var locale: I18n.locale
    readonly property string display: Qt.fontFamilies().includes("Inter Display") ? "Inter Display" : Config.font
    // Ziffer im Akzentkreis: dunkel auf hellem, hell auf dunklem Akzent
    readonly property color onAccent: root.accent.hslLightness > 0.6 ? "#161616" : "#fafafa"

    // ---- Heute (Mitternacht), nur beim Tageswechsel neu ----
    property date today: root.midnight(new Date())
    readonly property string todayKey: Holidays.key(root.today)

    function midnight(d: date): date {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }

    function checkDay() {
        if (!root.active)
            return;
        const k = Holidays.key(clock.date);
        if (k !== root.todayKey)
            root.today = root.midnight(clock.date);
    }

    onActiveChanged: root.checkDay()

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
        onDateChanged: root.checkDay()
    }

    // ---- Modelle ----
    function dayShort(d: date): string {
        // "Mo." -> "Mo"
        const day = d.getDay() === 0 ? 7 : d.getDay();
        return root.locale.standaloneDayName(day, Locale.ShortFormat).replace(".", "");
    }

    function cell(d: date, map: var, inMonth: bool): var {
        const k = Holidays.key(d);
        return {
            type: "day",
            day: d.getDate(),
            label: root.dayShort(d),
            inMonth: inMonth,
            weekend: d.getDay() === 0 || d.getDay() === 6,
            holiday: map[k] ?? "",
            today: k === root.todayKey,
            monday: d.getDay() === 1,
            week: Holidays.isoWeek(d)
        };
    }

    // Monatsraster als flache Liste: Kopfzeile (KW-Leer + Mo..So), dann
    // je Woche (KW +) 7 Tage. Zeilen so viele, wie der Monat braucht.
    readonly property var monthCells: {
        const t = root.today;
        const first = new Date(t.getFullYear(), t.getMonth(), 1);
        const offset = (first.getDay() + 6) % 7;
        const start = new Date(t.getFullYear(), t.getMonth(), 1 - offset);
        const daysIn = new Date(t.getFullYear(), t.getMonth() + 1, 0).getDate();
        const rows = Math.ceil((offset + daysIn) / 7);
        // Feiertage des Monats, ggf. mit Rand des Vor-/Folgejahres
        const map = Object.assign({}, Holidays.holidays(t.getFullYear() - 1, root.state), Holidays.holidays(t.getFullYear(), root.state), Holidays.holidays(t.getFullYear() + 1, root.state));

        const out = [];
        if (root.showWeeks)
            out.push({ type: "kwhead" });
        for (let i = 0; i < 7; i++)
            out.push({ type: "head", label: root.dayShort(new Date(2024, 0, 1 + i)), weekend: i >= 5 });
        for (let r = 0; r < rows; r++) {
            const monday = new Date(start.getFullYear(), start.getMonth(), start.getDate() + r * 7);
            if (root.showWeeks)
                out.push({ type: "kw", week: Holidays.isoWeek(monday) });
            for (let i = 0; i < 7; i++) {
                const d = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i);
                out.push(root.cell(d, map, d.getMonth() === t.getMonth()));
            }
        }
        return out;
    }

    // Die 7 Tage der aktuellen Woche
    readonly property var weekCells: {
        const t = root.today;
        const monday = new Date(t.getFullYear(), t.getMonth(), t.getDate() - ((t.getDay() + 6) % 7));
        const map = Object.assign({}, Holidays.holidays(t.getFullYear(), root.state), Holidays.holidays(t.getFullYear() + 1, root.state));
        const out = [];
        for (let i = 0; i < 7; i++) {
            const d = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i);
            out.push(root.cell(d, map, true));
        }
        return out;
    }

    // 14 Tage ab heute
    readonly property var stripCells: {
        const t = root.today;
        const map = Object.assign({}, Holidays.holidays(t.getFullYear(), root.state), Holidays.holidays(t.getFullYear() + 1, root.state));
        const out = [];
        for (let i = 0; i < 14; i++) {
            const d = new Date(t.getFullYear(), t.getMonth(), t.getDate() + i);
            out.push(root.cell(d, map, true));
        }
        return out;
    }

    // Im Streifen nur zwei, drei passen nicht in eine Zeile
    readonly property var upcoming: root.showUpcoming ? Holidays.upcoming(root.today, root.state, root.style === "streifen" ? 2 : 3) : []

    function inDays(n: int): string {
        return n === 0 ? I18n.tr("heute") : n === 1 ? I18n.tr("morgen") : I18n.tr("in %1 Tagen").arg(n);
    }

    readonly property string monthName: root.locale.standaloneMonthName(root.today.getMonth(), Locale.LongFormat).toUpperCase()
    readonly property string yearText: String(root.today.getFullYear())
    readonly property int currentWeek: Holidays.isoWeek(root.today)

    implicitWidth: body.width
    implicitHeight: body.height

    // ---- Bausteine ----

    // Kleine Versalien-Zeile mit Akzentpunkt (wie die Kopfzeilen der Notch)
    component Caption: Row {
        id: cap

        property string text: ""
        property string dim: ""
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
            color: Colors.alpha(root.color, 0.9)
            font.family: Config.font
            font.pixelSize: cap.px
            font.weight: Font.DemiBold
            font.letterSpacing: cap.px * 0.18
        }

        Text {
            visible: cap.dim !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: cap.dim
            color: Colors.alpha(root.color, 0.5)
            font.family: Config.font
            font.pixelSize: cap.px
            font.weight: Font.Medium
            font.letterSpacing: cap.px * 0.18
        }
    }

    // Eine Tageszelle: Zahl, heute als Akzentkreis, Feiertag als Punkt
    // darunter. Optional das Wochentag-Kuerzel ueber der Zahl.
    component DayCell: Item {
        id: dc

        required property var modelData
        property real size: root.unit * 1.9
        property bool withLabel: false
        property real numPx: root.unit * 0.95

        readonly property bool isDay: dc.modelData.type === "day"
        readonly property real alphaNum: !dc.isDay ? 0
                                       : dc.modelData.today ? 1
                                       : !dc.modelData.inMonth ? 0.16
                                       : dc.modelData.holiday !== "" ? 0.95
                                       : dc.modelData.weekend ? 0.42
                                       : 0.88

        width: dc.size
        height: dc.withLabel ? dc.size * 1.35 : dc.size

        // Wochentag-Kuerzel (Wochen- und Streifenstil)
        Text {
            visible: dc.withLabel && dc.isDay
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            text: dc.isDay ? dc.modelData.label.toUpperCase() : ""
            color: Colors.alpha(root.color, dc.modelData.today ? 0.9 : dc.modelData.weekend ? 0.32 : 0.5)
            font.family: Config.font
            font.pixelSize: root.unit * 0.6
            font.weight: Font.DemiBold
            font.letterSpacing: root.unit * 0.06
        }

        Rectangle {
            visible: dc.isDay && dc.modelData.today
            anchors.centerIn: num
            width: dc.size * 0.82
            height: width
            radius: width / 2
            color: root.accent
        }

        Text {
            id: num

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: (dc.size - height) / 2
            text: dc.isDay ? String(dc.modelData.day) : ""
            color: dc.isDay && dc.modelData.today ? root.onAccent : Colors.alpha(root.color, dc.alphaNum)
            font.family: root.display
            font.pixelSize: dc.numPx
            font.weight: dc.isDay && (dc.modelData.today || dc.modelData.holiday !== "") ? Font.Bold : Font.Medium
            font.features: ({ "tnum": 1 })
        }

        // Feiertagspunkt unter der Zahl
        Rectangle {
            visible: dc.isDay && dc.modelData.holiday !== "" && !dc.modelData.today
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: num.bottom
            anchors.topMargin: -root.unit * 0.05
            width: root.unit * 0.3
            height: width
            radius: width / 2
            color: root.accent
            opacity: dc.modelData.inMonth ? 1 : 0.3
        }
    }

    // Liste der naechsten Feiertage: Name links, "in N Tagen" rechts
    component UpcomingList: Column {
        id: ul

        property real w: root.unit * 14

        visible: root.upcoming.length > 0
        spacing: root.unit * 0.3

        Repeater {
            model: root.upcoming

            Item {
                id: urow

                required property var modelData

                width: ul.w
                height: root.unit * 1.05

                Rectangle {
                    id: udot

                    anchors.verticalCenter: parent.verticalCenter
                    width: root.unit * 0.3
                    height: width
                    radius: width / 2
                    color: root.accent
                    opacity: urow.modelData.days === 0 ? 1 : 0.55
                }

                Text {
                    anchors.left: udot.right
                    anchors.leftMargin: root.unit * 0.5
                    anchors.right: udays.left
                    anchors.rightMargin: root.unit * 0.6
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr(urow.modelData.name)
                    elide: Text.ElideRight
                    color: Colors.alpha(root.color, 0.85)
                    font.family: Config.font
                    font.pixelSize: root.unit * 0.8
                    font.weight: Font.Medium
                }

                Text {
                    id: udays

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.inDays(urow.modelData.days)
                    color: Colors.alpha(root.color, 0.5)
                    font.family: Config.font
                    font.pixelSize: root.unit * 0.75
                    font.weight: Font.Medium
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }

    // ---- Inhalt mit weichem Schatten (Layer-Textur) ----
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

                sourceComponent: root.style === "woche" ? week
                               : root.style === "streifen" ? strip
                               : month
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

    // ---- Monat ----
    Component {
        id: month

        Column {
            id: mcol

            readonly property real cell: root.unit * 1.9
            readonly property int cols: 7 + (root.showWeeks ? 1 : 0)

            spacing: root.unit * 0.7

            Caption {
                text: root.monthName
                dim: root.yearText
                px: root.unit * 0.85
            }

            Grid {
                id: mgrid

                columns: mcol.cols
                columnSpacing: 0
                rowSpacing: 0

                Repeater {
                    model: root.monthCells

                    DelegateChooser {
                        role: "type"

                        DelegateChoice {
                            roleValue: "day"

                            DayCell {
                                size: mcol.cell
                            }
                        }

                        DelegateChoice {
                            roleValue: "head"

                            Item {
                                id: hcell

                                required property var modelData

                                width: mcol.cell
                                height: root.unit * 1.1

                                Text {
                                    anchors.centerIn: parent
                                    text: hcell.modelData.label.toUpperCase()
                                    color: Colors.alpha(root.color, hcell.modelData.weekend ? 0.3 : 0.5)
                                    font.family: Config.font
                                    font.pixelSize: root.unit * 0.6
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: root.unit * 0.06
                                }
                            }
                        }

                        DelegateChoice {
                            roleValue: "kwhead"

                            Item {
                                required property var modelData

                                width: mcol.cell * 0.85
                                height: root.unit * 1.1

                                Text {
                                    anchors.centerIn: parent
                                    text: "KW"
                                    color: Colors.alpha(root.color, 0.3)
                                    font.family: Config.font
                                    font.pixelSize: root.unit * 0.55
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: root.unit * 0.06
                                }
                            }
                        }

                        DelegateChoice {
                            roleValue: "kw"

                            Item {
                                id: kcell

                                required property var modelData

                                width: mcol.cell * 0.85
                                height: mcol.cell

                                Text {
                                    anchors.centerIn: parent
                                    text: String(kcell.modelData.week)
                                    color: Colors.alpha(root.color, kcell.modelData.week === root.currentWeek ? 0.6 : 0.3)
                                    font.family: root.display
                                    font.pixelSize: root.unit * 0.65
                                    font.weight: Font.Medium
                                    font.features: ({ "tnum": 1 })
                                }
                            }
                        }
                    }
                }
            }

            UpcomingList {
                w: mgrid.width
            }
        }
    }

    // ---- Woche ----
    Component {
        id: week

        Column {
            id: wcol

            readonly property real cell: root.unit * 1.9

            spacing: root.unit * 0.7

            Caption {
                text: root.showWeeks ? "KW " + root.currentWeek : root.monthName
                dim: root.showWeeks ? root.monthName + " " + root.yearText : root.yearText
            }

            // Grosser Wochentag, Datum als zweite Zeile zurueckgenommen
            Column {
                spacing: -root.unit * 0.1

                Text {
                    text: root.locale.standaloneDayName(root.today.getDay() === 0 ? 7 : root.today.getDay(), Locale.LongFormat)
                    color: root.color
                    font.family: root.display
                    font.pixelSize: root.unit * 2.6
                    font.weight: Font.Bold
                    font.letterSpacing: -root.unit * 0.06
                }

                Text {
                    text: I18n.date(root.today, "d. MMMM yyyy", "MMMM d, yyyy")
                    color: Colors.alpha(root.color, 0.55)
                    font.family: root.display
                    font.pixelSize: root.unit * 1.1
                    font.weight: Font.Medium
                }
            }

            Row {
                id: wrow

                spacing: 0

                Repeater {
                    model: root.weekCells

                    DayCell {
                        size: wcol.cell
                        withLabel: true
                    }
                }
            }

            UpcomingList {
                w: wrow.width
            }
        }
    }

    // ---- Streifen ----
    Component {
        id: strip

        Column {
            id: scol

            readonly property real cell: root.unit * 1.9

            spacing: root.unit * 0.5

            Caption {
                text: root.monthName
                dim: root.yearText + (root.showWeeks ? "  ·  " + I18n.tr("KW %1").arg(root.currentWeek) : "")
                px: root.unit * 0.7
            }

            Row {
                id: srow

                spacing: 0

                Repeater {
                    model: root.stripCells

                    Row {
                        id: sitem

                        required property var modelData
                        required property int index

                        spacing: 0

                        // Wochentrenner vor jedem Montag (ausser ganz links):
                        // feine Linie, mit KW-Nummer oben, wenn KW an ist
                        Item {
                            visible: sitem.modelData.monday && sitem.index > 0
                            width: visible ? root.unit * (root.showWeeks ? 1.3 : 0.7) : 0
                            height: scol.cell * 1.35

                            Text {
                                visible: root.showWeeks
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: String(sitem.modelData.week)
                                color: Colors.alpha(root.color, 0.4)
                                font.family: root.display
                                font.pixelSize: root.unit * 0.6
                                font.weight: Font.Medium
                                font.features: ({ "tnum": 1 })
                            }

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: (scol.cell - height) / 2
                                width: 1
                                height: scol.cell * 0.6
                                color: Colors.alpha(root.color, 0.25)
                            }
                        }

                        DayCell {
                            modelData: sitem.modelData
                            size: scol.cell
                            withLabel: true
                        }
                    }
                }
            }

            // Im Streifen eine Zeile: "Allerheiligen in 9 Tagen · ..."
            Row {
                visible: root.upcoming.length > 0
                spacing: root.unit * 0.5

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.unit * 0.3
                    height: width
                    radius: width / 2
                    color: root.accent
                    opacity: 0.7
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: srow.width - root.unit * 0.8
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: root.upcoming.map(h => I18n.tr(h.name) + " <font color=\"" + Colors.alpha(root.color, 0.5) + "\">" + root.inDays(h.days) + "</font>").join("  ·  ")
                    color: Colors.alpha(root.color, 0.85)
                    font.family: Config.font
                    font.pixelSize: root.unit * 0.75
                    font.weight: Font.Medium
                }
            }
        }
    }
}
