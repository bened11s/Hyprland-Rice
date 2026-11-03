pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.services.config
import qs.modules.services.desktop

// Optionen eines Widgets, angedockt an seinen Auswahlrahmen (WidgetHost
// setzt Lage und die Ecke, die am Rahmen anliegt). Gleicher Rand wie der
// Rahmen, damit beides als eine Flaeche liest.
//
// Inhalt: Kopf (Typ, Duplizieren, Loeschen mit Rueckfrage), je Option eine
// Chip-Reihe (Schalter als "an | aus"), Groesse, Farbe/Akzent (die gewaehlte
// mit Namen), Monitor.
Rectangle {
    id: pop

    required property var widget
    property string screenName: ""
    // Wohin die Aenderungen gehen: Scenes (Desktop) oder LockLayout
    // (Sperrbildschirm) – beide haben patch/setOpt/duplicate/remove
    property var store: Scenes
    // Zeile "Monitor" (nur der Desktop kennt Widgets je Monitor)
    property bool monitors: true
    // Auf einen Monitor festgelegt ("Nur <name>") statt auf beiden
    readonly property bool pinned: !!pop.widget?.monitor && pop.widget.monitor !== "*"

    readonly property var info: pop.widget ? DesktopWidgets.info(pop.widget.type) : null
    readonly property real size: pop.widget?.size ?? 1
    // Breite der Beschriftungsspalte ("Wachsen zeigen" passt gerade so)
    readonly property real labelWidth: 100

    // Loeschen ist zweistufig: erster Klick fragt, 3 s lang
    property bool deleteArmed: false

    readonly property var colorLabels: ({
        "hell": "Hell", "primary": "Primär", "secondary": "Sekundär",
        "tertiary": "Tertiär", "weiss": "Weiß", "dunkel": "Dunkel"
    })

    function setSize(value: real): void {
        pop.store.patch(pop.widget.id, { size: Number(Math.max(0.3, Math.min(8, value)).toFixed(3)) });
    }

    Timer {
        id: disarm

        interval: 3000
        onTriggered: pop.deleteArmed = false
    }

    implicitWidth: Math.max(300, rows.implicitWidth + 28)
    implicitHeight: rows.implicitHeight + 24
    color: Colors.alpha(Colors.background, 0.96)
    border.width: 2
    border.color: Colors.primary

    // Maus ueber dem Feld: Widgets darunter sperren (WidgetHost.blocked)
    readonly property bool hovered: popHover.hovered

    HoverHandler {
        id: popHover
    }

    // Klicks bleiben hier (nicht zum Desktop durch = Auswahl aufheben)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    ColumnLayout {
        id: rows

        x: 14
        y: 12
        spacing: 8

        // ---- Kopf ----
        RowLayout {
            spacing: 8
            Layout.fillWidth: true

            Text {
                text: pop.info?.icon ?? "widgets"
                color: Colors.primary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 18
            }

            Text {
                text: I18n.tr(pop.info?.title ?? pop.widget?.type ?? "")
                color: Colors.fgBackground
                font.family: Config.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

            // Anzeigen oder nur beim Anordnen sichtbar
            EditChip {
                icon: pop.widget?.hidden ? "visibility_off" : "visibility"
                text: pop.widget?.hidden ? I18n.tr("Nur im Editor") : I18n.tr("Sichtbar")
                on: !pop.widget?.hidden
                onClicked: pop.store.patch(pop.widget.id, { hidden: !pop.widget?.hidden })
            }

            EditChip {
                icon: "content_copy"
                onClicked: pop.store.duplicate(pop.widget.id)
            }

            EditChip {
                icon: pop.deleteArmed ? "check" : "delete"
                text: pop.deleteArmed ? I18n.tr("Löschen?") : ""
                danger: true
                armed: pop.deleteArmed
                onClicked: {
                    if (pop.deleteArmed) {
                        pop.store.remove(pop.widget.id);
                    } else {
                        pop.deleteArmed = true;
                        disarm.restart();
                    }
                }
            }
        }

        // ---- Optionen des Typs ----
        Repeater {
            model: pop.info ? Object.keys(pop.info.options ?? {}) : []

            RowLayout {
                id: optRow

                required property string modelData
                readonly property var option: pop.info.options[optRow.modelData]
                readonly property var value: DesktopWidgets.opt(pop.widget, optRow.modelData)

                spacing: 6

                EditLabel {
                    text: I18n.tr(optRow.option.title ?? optRow.modelData)
                    Layout.preferredWidth: pop.labelWidth
                }

                // Schalter: beide Zustaende sichtbar, der aktive hervorgehoben
                Repeater {
                    model: optRow.option.bool === true ? [true, false] : []

                    EditChip {
                        required property bool modelData

                        text: modelData ? I18n.tr("an") : I18n.tr("aus")
                        on: !!optRow.value === modelData
                        onClicked: pop.store.setOpt(pop.widget.id, optRow.modelData, modelData)
                    }
                }

                Flow {
                    visible: (optRow.option.values ?? []).length > 0
                    spacing: 6
                    Layout.maximumWidth: 420
                    Layout.preferredWidth: implicitWidth

                    Repeater {
                        model: optRow.option.values ?? []

                        EditChip {
                            required property var modelData

                            // Werte sind Config-Schluessel; nur Woerter werden uebersetzt
                            text: typeof modelData === "string" ? I18n.tr(modelData) : String(modelData)
                            on: optRow.value === modelData
                            onClicked: pop.store.setOpt(pop.widget.id, optRow.modelData, modelData)
                        }
                    }
                }
            }
        }

        // ---- Groesse (auch: Griff an der Ecke, Tasten + / -) ----
        RowLayout {
            spacing: 6
            visible: pop.widget !== null

            EditLabel {
                text: I18n.tr("Größe")
                Layout.preferredWidth: pop.labelWidth
            }

            EditChip {
                icon: "remove"
                onClicked: pop.setSize(pop.size / 1.1)
            }

            EditChip {
                text: Math.round(pop.size * 100) + " %"
                Layout.preferredWidth: 64
                onClicked: pop.setSize(1)
            }

            EditChip {
                icon: "add"
                onClicked: pop.setSize(pop.size * 1.1)
            }
        }

        // ---- Farben ----
        Repeater {
            model: [["color", "Farbe", "hell"], ["accent", "Akzent", "primary"]]

            RowLayout {
                id: colorRow

                required property var modelData
                readonly property string current: pop.widget?.opts?.[colorRow.modelData[0]] ?? colorRow.modelData[2]

                spacing: 6

                EditLabel {
                    text: I18n.tr(colorRow.modelData[1])
                    Layout.preferredWidth: pop.labelWidth
                }

                Repeater {
                    model: DesktopWidgets.colorNames

                    EditChip {
                        required property string modelData

                        swatch: DesktopWidgets.color(modelData, "transparent")
                        on: colorRow.current === modelData
                        // Name nur an der gewaehlten Farbe, sonst wird die Reihe zu breit
                        text: on ? I18n.tr(pop.colorLabels[modelData] ?? modelData) : ""
                        onClicked: pop.store.setOpt(pop.widget.id, colorRow.modelData[0], modelData)
                    }
                }

                // Feste Farbe der Szene (z.B. Cyberpunk-Gelb)
                EditChip {
                    visible: colorRow.current.startsWith("#")
                    swatch: colorRow.current.startsWith("#") ? colorRow.current : "transparent"
                    text: I18n.tr("Eigene")
                    on: true
                }
            }
        }

        // ---- Monitor ----
        RowLayout {
            visible: pop.monitors
            spacing: 6

            EditLabel {
                text: I18n.tr("Monitor")
                Layout.preferredWidth: pop.labelWidth
            }

            // Genau einer an. Festgelegt heisst der zweite wie der Monitor des
            // Widgets – auch wenn es nur hierher ragt (halb links, halb rechts)
            EditChip {
                text: I18n.tr("Beide")
                on: !pop.pinned
                onClicked: pop.store.patch(pop.widget.id, { monitor: "*" })
            }

            EditChip {
                text: I18n.tr("Nur %1").arg(pop.pinned ? pop.widget.monitor : pop.screenName)
                on: pop.pinned
                onClicked: if (!pop.pinned) pop.store.patch(pop.widget.id, { monitor: pop.screenName })
            }
        }
    }
}
