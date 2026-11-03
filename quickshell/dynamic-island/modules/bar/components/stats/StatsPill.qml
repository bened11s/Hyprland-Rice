pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.system

import qs
import qs.modules.services.config
import qs.modules.widgets

// System-Pille rechts neben dem Workspace-Selektor.
//
//   Grundzustand   Akkustand (Systemakku, sonst der schwaechste Geraete-Akku)
//   Hover          die Pille waechst nach RECHTS und zeigt die Energieprofile
//   Klick          die Karte waechst nach UNTEN mit Auslastung und Temperaturen
//                  und bleibt stehen, bis man wieder klickt
//
// Die Kreis-zu-Pille-Mechanik ist von der Tray-Pille uebernommen, nur
// spiegelverkehrt: der Inhalt haengt links fest, damit alles nach rechts
// waechst. Das Rasten per Klick ist das Toggle aus der Benachrichtigungs-Pille,
// hier aber ohne Hover-Nachlauf – die Karte soll ja stehenbleiben.
Item {
    id: root

    required property real verticalMargin
    required property real borderWidth
    required property color borderColor
    required property real cardRadius

    readonly property real collapsedSize: parent.height - verticalMargin
    readonly property real padding: 7
    readonly property real cardWidth: 340

    property bool open: false
    property bool profilesOpen: false

    // Breite im Grundzustand: der Kopf, mindestens aber ein Kreis
    readonly property real headWidth: Math.max(root.collapsedSize, head.implicitWidth + root.padding * 2)
    readonly property real profilesWidth: root.headWidth + profiles.implicitWidth + 6

    // Hoehe der Karte: Kopfband + Inhalt
    readonly property real cardHeight: root.collapsedSize + card.implicitHeight + 10
    // Reserve fuer das Bar-Fenster – immer der groesste Fall
    readonly property real maxDrop: Math.max(0, root.verticalMargin / 2 + root.cardHeight - parent.height)

    // Der Dienst misst nur, solange die Karte offen ist. Das Binding dafuer
    // steht zentral in Bar.qml (die Notch misst auch), sonst ueberschrieben
    // sich zwei Bindings gegenseitig.

    y: root.verticalMargin / 2
    width: root.open ? Math.max(root.cardWidth, root.headWidth)
         : root.profilesOpen ? root.profilesWidth
         : root.headWidth
    height: root.open ? root.cardHeight : root.collapsedSize

    Morph on width {}
    Morph on height {}

    // Profile erst nach kurzem Verweilen – sonst zuckt die Pille bei jedem
    // Vorbeifahren
    Timer {
        id: profileTimer

        interval: 200
        onTriggered: root.profilesOpen = true
    }

    Timer {
        id: closeProfiles

        interval: 260
        onTriggered: root.profilesOpen = false
    }

    Surface {
        id: pill

        anchors.fill: parent

        maxRadius: root.cardRadius
        borderWidth: root.borderWidth
        borderColor: root.borderColor

        HoverHandler {
            id: hover

            onHoveredChanged: {
                if (hovered) {
                    closeProfiles.stop();
                    if (!root.profilesOpen)
                        profileTimer.restart();
                } else {
                    profileTimer.stop();
                    closeProfiles.restart();
                }
            }
        }

        // ---- Kopf: Akkustand (oder nur das Symbol) ----
        Row {
            id: head

            anchors {
                left: parent.left
                leftMargin: root.padding
                top: parent.top
            }
            height: root.collapsedSize
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text: Power.hasBattery && !Power.showsSystem ? Power.deviceIcon(Power.shown)
                    : Power.hasBattery ? Power.batteryIcon
                    : "monitoring"
                color: Power.low ? Colors.error
                     : root.open ? Colors.primary : Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16

                Behavior on color {
                    ColorAnimation { duration: 140 }
                }
            }

            Text {
                font.family: Config.font
                anchors.verticalCenter: parent.verticalCenter
                visible: Power.hasBattery

                text: `${Power.percent} %`
                color: Colors.fgBackground
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        // Klick auf den Kopf rastet die Karte auf und wieder zu
        TapHandler {
            onTapped: root.open = !root.open
        }

        // ---- Energieprofile, rechts neben dem Kopf ----
        Row {
            id: profiles

            anchors {
                left: parent.left
                leftMargin: root.headWidth
                top: parent.top
            }
            height: root.collapsedSize
            spacing: 2
            opacity: root.profilesOpen && !root.open ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Repeater {
                model: Power.profiles

                Rectangle {
                    id: chip

                    required property var modelData

                    readonly property bool current: Power.profile === chip.modelData.value

                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: height / 2
                    color: chip.current ? Colors.alpha(Colors.primary, 0.22)
                         : chipArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.12)
                         : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: chip.modelData.icon
                        // Gedrosselte Leistung faellt genau hier auf
                        color: chip.current ? (Power.degraded && chip.modelData.value === 2 ? Colors.error
                                                                                           : Colors.primary)
                                            : Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: chipArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Power.setProfile(chip.modelData.value)
                    }
                }
            }
        }

        // ---- Karte: Auslastung und Temperaturen ----
        StatsCard {
            id: card

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                topMargin: root.collapsedSize
                leftMargin: 14
                rightMargin: 14
            }
            opacity: root.open ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }
        }
    }
}
