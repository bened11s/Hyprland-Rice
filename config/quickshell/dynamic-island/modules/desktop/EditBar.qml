pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.services.config
import qs.modules.services.desktop

// Leiste rechts unten beim Bearbeiten der Desktop-Widgets (nur auf dem
// Monitor, auf dem bearbeitet wird) – gleicher Bau wie die Leiste des
// Sperrbildschirm-Editors (LockEditBar.qml): Szene (wohin die Aenderungen
// gehen, Menue darueber), Widget hinzufuegen, automatisch anordnen, Szene
// loeschen (fragt einmal nach), Abbrechen (alles seit dem Start zurueck),
// Fertig.
//
// Die Optionen eines Widgets haengen nicht hier, sondern angedockt am
// Widget selbst (WidgetOptions.qml).
//
// Im Szenen-Menue tragen Ziele ohne eigene Szene ein "+" (Klick legt sie
// als Kopie des Sichtbaren an). Das Menue gehoert zur Leiste (gleiche
// Grenzen), damit Hover und Klicks darauf nicht die Widgets darunter treffen.
Item {
    id: bar

    property string screenName: ""
    readonly property bool adding: Scenes.adding
    property bool dropArmed: false
    property bool scenesOpen: false
    readonly property var current: Scenes.targets.find(t => t.key === Scenes.target) ?? null
    readonly property bool canDrop: Scenes.target !== "*" && Array.isArray(Scenes.scenes[Scenes.target])

    onAddingChanged: if (bar.adding) bar.scenesOpen = false

    Timer {
        id: disarmDrop

        interval: 3000
        onTriggered: bar.dropArmed = false
    }

    implicitWidth: Math.max(pill.width, menu.visible ? menu.width : 0)
    implicitHeight: pill.height + (menu.visible ? menu.height + 8 : 0)
    width: implicitWidth
    height: implicitHeight

    // Maus ueber Leiste oder Menue: Widgets darunter sperren (WidgetHost.blocked)
    readonly property bool hovered: barHover.hovered

    HoverHandler {
        id: barHover
    }

    // Klicks bleiben auf der Leiste
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    // ---- Szenen-Menue ueber der Leiste ----

    Rectangle {
        id: menu

        visible: bar.scenesOpen
        x: bar.width - width
        // Breite nach dem laengsten Eintrag (Ordnernamen koennen lang sein)
        readonly property real entryW: {
            let w = 164;
            for (let i = 0; i < entries.count; i++) {
                const it = entries.itemAt(i);
                if (it)
                    w = Math.max(w, it.implicitWidth);
            }
            return w;
        }

        width: menu.entryW + 16
        height: menuCol.implicitHeight + 16
        radius: 16
        color: Colors.alpha(Colors.background, 0.94)
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.5)

        Column {
            id: menuCol

            x: 8
            y: 8
            spacing: 2

            EditLabel {
                leftPadding: 8
                topPadding: 2
                bottomPadding: 4
                text: I18n.tr("Szene")
            }

            Repeater {
                id: entries

                model: Scenes.targets

                Rectangle {
                    id: entry

                    required property var modelData
                    readonly property bool on: Scenes.target === entry.modelData.key

                    width: menu.entryW
                    implicitWidth: entryRow.implicitWidth + 20
                    height: 30
                    radius: 10
                    color: entry.on ? Colors.alpha(Colors.primary, 0.18)
                         : entryHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1) : "transparent"

                    Row {
                        id: entryRow

                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        spacing: 8

                        // Gewaehlt = Haken, ohne eigene Szene = "+"
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            text: entry.on ? "check" : entry.modelData.own ? "" : "add"
                            color: entry.on ? Colors.primary : Colors.fgSurfaceVariant
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 16
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.label
                            color: Colors.fgSurface
                            opacity: entry.modelData.own || entry.on ? 1 : 0.6
                            font.family: Config.font
                            font.pixelSize: 11
                            font.weight: entry.on ? Font.DemiBold : Font.Normal
                        }
                    }

                    HoverHandler {
                        id: entryHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: {
                            Scenes.setTarget(entry.modelData.key);
                            bar.scenesOpen = false;
                        }
                    }
                }
            }
        }
    }

    // ---- Leiste ----

    Rectangle {
        id: pill

        x: bar.width - width
        y: bar.height - height
        width: rows.implicitWidth + 24
        height: rows.implicitHeight + 20
        radius: 20
        color: Colors.alpha(Colors.background, 0.94)
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.5)

        Behavior on width {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        RowLayout {
            id: rows

            anchors.centerIn: parent
            spacing: 6

            EditChip {
                icon: "layers"
                text: bar.current?.label ?? I18n.tr("Szene")
                on: bar.scenesOpen
                onClicked: {
                    Scenes.adding = false;
                    bar.scenesOpen = !bar.scenesOpen;
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                color: Colors.alpha(Colors.outline, 0.5)
            }

            EditChip {
                icon: "add"
                text: I18n.tr("Widget")
                on: bar.adding
                // Auswahl ueber der Leiste (WidgetPicker, DesktopScreen)
                onClicked: {
                    if (Scenes.adding)
                        Scenes.adding = false;
                    else {
                        // auf dem Monitor dieser Leiste
                        Scenes.editScreen = bar.screenName;
                        Scenes.openPicker(null);
                    }
                }
            }

            EditChip {
                icon: "auto_awesome_mosaic"
                text: I18n.tr("Anordnen")
                visible: Scenes.widgets.length > 0 && Scenes.analysis !== null
                onClicked: Scenes.arrange()
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                color: Colors.alpha(Colors.outline, 0.5)
            }

            // Eigene Szene des Ziels loeschen – "Ueberall" und Ziele ohne
            // eigene Szene haben nichts zu loeschen (zurueckgenommen)
            EditChip {
                icon: bar.dropArmed ? "check" : "layers_clear"
                text: bar.dropArmed ? I18n.tr("Szene löschen?") : I18n.tr("Szene löschen")
                danger: true
                armed: bar.dropArmed
                dim: !bar.canDrop && !bar.dropArmed
                onClicked: {
                    if (bar.dropArmed) {
                        bar.dropArmed = false;
                        Scenes.dropTarget();
                    } else if (bar.canDrop) {
                        bar.dropArmed = true;
                        disarmDrop.restart();
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                color: Colors.alpha(Colors.outline, 0.5)
            }

            EditChip {
                icon: "close"
                text: I18n.tr("Abbrechen")
                onClicked: Scenes.cancel()
            }

            EditChip {
                icon: "check"
                text: I18n.tr("Fertig")
                on: true
                onClicked: Scenes.done()
            }
        }
    }
}
