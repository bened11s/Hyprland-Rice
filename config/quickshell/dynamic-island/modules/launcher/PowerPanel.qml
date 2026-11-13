pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs
import qs.modules.services.config

// Sitzungsmenue der Notch. Aufbau und Masse folgen den Auswahlkarten fuer
// Wallpaper und Themes; statt eines Karussells gibt es eine Reihe Aktionen.
Item {
    id: panel

    property real topOffset: 0
    property real cardRadius: 18
    property real inset: 2
    property bool active: false

    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    readonly property alias maxOuterHeight: panel.outerHeight

    // `danger`: markiert in der Fehlerfarbe statt in der Akzentfarbe
    readonly property var actions: [
        { label: "Sperren", icon: "lock",
          command: [Quickshell.env("HOME") + "/.config/hypr/scripts/lock.sh"] },
        { label: "Abmelden", icon: "logout",
          command: [Quickshell.env("HOME") + "/.config/hypr/scripts/session-exit.sh", "logout"] },
        { label: "Standby", icon: "bedtime",
          command: ["systemctl", "suspend"] },
        { label: "Neustart", icon: "restart_alt", danger: true,
          command: [Quickshell.env("HOME") + "/.config/hypr/scripts/session-exit.sh", "reboot"] },
        { label: "Ausschalten", icon: "power_settings_new", danger: true,
          command: [Quickshell.env("HOME") + "/.config/hypr/scripts/session-exit.sh", "poweroff"] }
    ]

    // Etwas breiter als die Blaetter-Seiten (548): Kacheln mit Luft
    implicitWidth: 660
    implicitHeight: actionArea.height

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: panel.inset
        rightMargin: panel.inset
    }
    y: panel.topOffset

    // Markierte Aktion – Pfeiltasten/Tab wandern, Maus-Hover setzt sie mit,
    // damit nie zwei Kacheln gleichzeitig leuchten. Startet auf "Sperren",
    // damit ein versehentliches Enter nichts Endgueltiges ausloest.
    property int current: 0

    // Per LazyPanel entsteht die Ansicht bereits aktiv – dann gibt es kein
    // Wechsel-Signal, die Startarbeit (Fokus, Suchfeld) wird nachgeholt
    Component.onCompleted: if (panel.active) Qt.callLater(panel.activeChanged)

    onActiveChanged: {
        if (active) {
            panel.current = 0;
            panel.forceActiveFocus();
        }
    }

    function move(dir: int): void {
        const n = panel.actions.length;
        panel.current = ((panel.current + dir) % n + n) % n;
    }

    Keys.onEscapePressed: LauncherState.close()
    Keys.onLeftPressed: panel.move(-1)
    Keys.onRightPressed: panel.move(1)
    Keys.onUpPressed: panel.move(-1)
    Keys.onDownPressed: panel.move(1)
    Keys.onTabPressed: panel.move(1)
    Keys.onBacktabPressed: panel.move(-1)
    Keys.onReturnPressed: panel.run(panel.actions[panel.current].command)
    Keys.onEnterPressed: panel.run(panel.actions[panel.current].command)
    Keys.onSpacePressed: panel.run(panel.actions[panel.current].command)

    function run(command: var): void {
        LauncherState.close();
        Quickshell.execDetached(command);
    }

    // Eine Gruppe wie die Leiste des Einstellungsfensters: Kacheln 2 px
    // auseinander, aussen rund, innen fast eckig; markiert = Akzentgrund
    // mit gefuelltem Symbolkreis.
    Item {
        id: actionArea

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 120

        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 2

            Repeater {
                model: panel.actions

                Rectangle {
                    id: action

                    required property var modelData
                    required property int index

                    readonly property bool hovered: panel.current === action.index
                    readonly property color hue: action.modelData.danger ? Colors.error : Colors.primary
                    readonly property real outer: Math.min(panel.cardRadius - 4, 16)

                    width: (actionArea.width - 20 - 2 * (panel.actions.length - 1)) / panel.actions.length
                    height: actionArea.height - 20
                    topLeftRadius: action.index === 0 ? action.outer : 6
                    bottomLeftRadius: action.index === 0 ? action.outer : 6
                    topRightRadius: action.index === panel.actions.length - 1 ? action.outer : 6
                    bottomRightRadius: action.index === panel.actions.length - 1 ? action.outer : 6
                    color: action.hovered ? Colors.alpha(action.hue, 0.18) : Colors.alpha(Colors.fgSurface, 0.04)

                    Behavior on color {
                        ColorAnimation { duration: 130 }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 10

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 38
                            height: 38
                            radius: 19
                            color: action.hovered ? action.hue : Colors.alpha(Colors.fgSurface, 0.06)

                            Behavior on color {
                                ColorAnimation { duration: 130 }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: action.modelData.icon
                                color: action.hovered ? (action.modelData.danger ? Colors.fgError : Colors.fgPrimary)
                                                      : Colors.fgSurfaceVariant
                                font.family: "Material Symbols Outlined"
                                // Kein FILL-Umschalten: gefuellt rendern bedtime/lock
                                // mit Loechern (Qt + variable Material Symbols)
                                font.pixelSize: 20
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.family: Config.font
                            text: I18n.tr(action.modelData.label)
                            color: action.hovered ? Colors.fgSurface : Colors.fgSurfaceVariant
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: if (containsMouse) panel.current = action.index
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.run(action.modelData.command)
                    }
                }
            }
        }
    }
}
