pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.desktop
import qs.modules.settings

// Optionen eines Widgets, angedockt an seinen Auswahlrahmen (WidgetHost
// setzt Lage und die Ecke, die am Rahmen anliegt). Gleicher Rand wie der
// Rahmen, damit beides als eine Flaeche liest.
//
// Aufbau wie eine Gruppe im Einstellungsfenster (docs/settings-style.md):
// Kopf (Titel, Duplizieren, Loeschen – Loeschen fragt im Kopf nach),
// darunter Zeilen mit je einem Bedienelement (EditRow): Sichtbar, die
// Optionen des Typs (Schalter bzw. Auswahlknopf), Groesse, Farbe/Akzent als
// Farbtupfer, Monitor als Zweier-Segment.
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

    // Rueckfrage "Wirklich loeschen?" im Kopf
    property bool confirmDelete: false
    // Offene Listen der Auswahlknoepfe in den Zeilen
    property int menusOpen: 0

    function setSize(value: real): void {
        pop.store.patch(pop.widget.id, { size: Number(Math.max(0.3, Math.min(8, value)).toFixed(3)) });
    }

    // Anzeigename eines Auswahlwerts: uebersetzt und gross angefangen (wie
    // SettingsRow.optionLabel) – Werte sind Config-Schluessel ("mitte")
    function optionLabel(value: var): string {
        const shown = typeof value === "string" ? I18n.tr(value) : String(value);
        return shown.charAt(0).toUpperCase() + shown.slice(1);
    }

    implicitWidth: 320
    implicitHeight: body.implicitHeight + 10
    color: Colors.alpha(Colors.background, 0.96)
    border.width: 2
    border.color: Colors.primary

    // Maus ueber dem Feld: Widgets darunter sperren (WidgetHost.blocked).
    // Die Listen (⋮, Auswahlknoepfe) liegen als Popup ausserhalb des Felds –
    // solange eine offen ist, gilt dasselbe, sonst traefe ein Klick in die
    // Liste das Widget darunter (Qt 6 reicht den Druck an alle Handler weiter)
    readonly property bool hovered: popHover.hovered || pop.menusOpen > 0

    HoverHandler {
        id: popHover
    }

    // Klicks bleiben hier (nicht zum Desktop durch = Auswahl aufheben)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    Column {
        id: body

        x: 16
        y: 4
        width: pop.width - 32

        // ---- Kopf ----
        Item {
            width: parent.width
            height: 46

            Text {
                anchors {
                    left: parent.left
                    right: headActions.left
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                text: pop.confirmDelete ? I18n.tr("Wirklich löschen?") : I18n.tr(pop.info?.title ?? pop.widget?.type ?? "")
                color: Colors.fgBackground
                font.family: Config.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Row {
                id: headActions

                anchors {
                    right: parent.right
                    // Symbolknoepfe ragen in den Rand, ihr Symbol fluchtet mit den Bedienelementen
                    rightMargin: pop.confirmDelete ? 0 : -6
                    verticalCenter: parent.verticalCenter
                }
                spacing: 6

                // Direkt als Knoepfe: Loeschen fragt ohnehin hier im Kopf nach,
                // ein Umweg ueber ⋮ waere ein Schritt mehr
                EditButton {
                    visible: !pop.confirmDelete
                    icon: "content_copy"
                    onClicked: pop.store.duplicate(pop.widget.id)
                }

                EditButton {
                    visible: !pop.confirmDelete
                    icon: "delete"
                    danger: true
                    onClicked: pop.confirmDelete = true
                }

                EditButton {
                    visible: pop.confirmDelete
                    text: I18n.tr("Löschen")
                    danger: true
                    onClicked: pop.store.remove(pop.widget.id)
                }

                EditButton {
                    visible: pop.confirmDelete
                    text: I18n.tr("Abbrechen")
                    onClicked: pop.confirmDelete = false
                }
            }
        }

        // Anzeigen oder nur beim Anordnen sichtbar
        EditRow {
            label: I18n.tr("Sichtbar")

            SettingsSwitch {
                anchors.verticalCenter: parent.verticalCenter
                checked: !pop.widget?.hidden
                onToggled: pop.store.patch(pop.widget.id, { hidden: !pop.widget?.hidden })
            }
        }

        // ---- Optionen des Typs ----
        Repeater {
            model: pop.info ? Object.keys(pop.info.options ?? {}) : []

            EditRow {
                id: optRow

                required property string modelData
                readonly property var option: pop.info?.options?.[optRow.modelData] ?? ({})
                readonly property var value: DesktopWidgets.opt(pop.widget, optRow.modelData)

                label: I18n.tr(optRow.option.title ?? optRow.modelData)

                SettingsSwitch {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: optRow.option.bool === true
                    checked: !!optRow.value
                    onToggled: pop.store.setOpt(pop.widget.id, optRow.modelData, !optRow.value)
                }

                SettingsDropdown {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (optRow.option.values ?? []).length > 0
                    maxWidth: 180
                    options: optRow.option.values ?? []
                    current: optRow.value
                    labelOf: pop.optionLabel
                    onPicked: v => pop.store.setOpt(pop.widget.id, optRow.modelData, v)
                    onMenuOpenChanged: pop.menusOpen += menuOpen ? 1 : -1
                    // Zeile verschwindet mit offener Liste (anderer Typ)
                    Component.onDestruction: if (menuOpen) pop.menusOpen--
                }
            }
        }

        // ---- Groesse (auch: Griff an der Ecke, Tasten + / -) ----
        EditRow {
            label: I18n.tr("Größe")

            EditButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "remove"
                onClicked: pop.setSize(pop.size / 1.1)
            }

            // Klick auf den Wert: zurueck auf 100 %
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 50
                horizontalAlignment: Text.AlignHCenter
                text: Math.round(pop.size * 100) + " %"
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 12

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: pop.setSize(1)
                }
            }

            EditButton {
                anchors.verticalCenter: parent.verticalCenter
                icon: "add"
                onClicked: pop.setSize(pop.size * 1.1)
            }
        }

        // ---- Farben ----
        Repeater {
            model: [["color", "Farbe", "hell"], ["accent", "Akzent", "primary"]]

            EditRow {
                id: colorRow

                required property var modelData
                readonly property string current: pop.widget?.opts?.[colorRow.modelData[0]] ?? colorRow.modelData[2]

                label: I18n.tr(colorRow.modelData[1])

                Repeater {
                    // Feste Farbe der Szene (z.B. Cyberpunk-Gelb "#fcee0a") als
                    // weiterer Tupfer hinten
                    model: DesktopWidgets.colorNames.concat(colorRow.current.startsWith("#") ? [colorRow.current] : [])

                    Item {
                        id: dot

                        required property string modelData
                        readonly property bool on: colorRow.current === dot.modelData

                        anchors.verticalCenter: parent.verticalCenter
                        width: 24
                        height: 24

                        // Gewaehlt: Ring
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: "transparent"
                            border.width: 2
                            border.color: dot.on ? Colors.primary
                                        : dotHover.hovered ? Colors.alpha(Colors.fgSurface, 0.3) : "transparent"
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            radius: 7
                            color: DesktopWidgets.color(dot.modelData, "transparent")
                            border.width: 1
                            border.color: Colors.alpha(Colors.fgSurface, 0.3)
                        }

                        HoverHandler {
                            id: dotHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: pop.store.setOpt(pop.widget.id, colorRow.modelData[0], dot.modelData)
                        }
                    }
                }
            }
        }

        // ---- Monitor ----
        // Genau einer an. Festgelegt heisst der zweite wie der Monitor des
        // Widgets – auch wenn es nur hierher ragt (halb links, halb rechts)
        EditRow {
            visible: pop.monitors
            label: I18n.tr("Monitor")

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: segments.width + 4
                height: 30
                radius: 8
                color: Colors.alpha(Colors.fgSurface, 0.06)

                Row {
                    id: segments

                    x: 2
                    y: 2

                    Repeater {
                        model: [false, true]

                        Rectangle {
                            id: segment

                            required property bool modelData
                            readonly property bool on: pop.pinned === segment.modelData

                            width: segmentText.implicitWidth + 24
                            height: 26
                            radius: 6
                            color: segment.on ? Colors.alpha(Colors.primary, 0.2)
                                 : segmentHover.hovered ? Colors.alpha(Colors.fgSurface, 0.07) : "transparent"

                            Text {
                                id: segmentText

                                anchors.centerIn: parent
                                text: !segment.modelData ? I18n.tr("Beide")
                                    : I18n.tr("Nur %1").arg(pop.pinned ? pop.widget.monitor : pop.screenName)
                                color: segment.on ? Colors.primary : Colors.fgSurfaceVariant
                                font.family: Config.font
                                font.pixelSize: 12
                                font.weight: segment.on ? Font.DemiBold : Font.Normal
                            }

                            HoverHandler {
                                id: segmentHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: {
                                    if (!segment.on)
                                        pop.store.patch(pop.widget.id, { monitor: segment.modelData ? pop.screenName : "*" });
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
