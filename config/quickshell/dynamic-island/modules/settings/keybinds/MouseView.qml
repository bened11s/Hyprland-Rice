pragma ComponentBehavior: Bound
import QtQuick

import qs

// Kleine Maus neben der Tastatur: linke/rechte Taste, Rad (hoch / Klick /
// runter). Jede Flaeche leuchtet mit ihrer Belegung, Klick waehlt den Befehl.
Item {
    id: mouse

    required property real unit
    // id -> info | null  (mouse:272, mouse:273, mouse:274, mouse_up, mouse_down)
    property var infos: ({})
    // id -> Lichtfarbe
    property var lights: ({})
    // id -> gehoert zum gewaehlten Befehl
    property var lits: ({})
    property bool interactive: true

    signal clicked(string id)
    signal contextClicked(string id)

    readonly property color rockBase: Qt.darker(Colors.surfaceBright, 1.5)
    readonly property color shell: Colors.surfaceBright
    readonly property real r: mouse.unit * 0.85

    property string hoverId: ""

    function tint(id: string): color {
        const info = mouse.infos[id] ?? null;
        if (!info)
            return mouse.hoverId === id ? Qt.lighter(mouse.shell, 1.15) : mouse.shell;
        const strength = (mouse.lits[id] ? 0.55 : 0.32) * (info.disabled ? 0.5 : 1);
        return Qt.tint(mouse.hoverId === id ? Qt.lighter(mouse.shell, 1.15) : mouse.shell, Colors.alpha(mouse.lights[id] ?? "transparent", strength));
    }

    function glowOf(id: string): real {
        const info = mouse.infos[id] ?? null;
        return !info ? 0 : mouse.lits[id] ? 0.3 : 0.14;
    }

    width: mouse.unit * 1.9
    height: mouse.unit * 3.1
    z: mouse.hoverId !== "" ? 2 : 0

    // Schein um den Korpus (Summe der Lichter: staerkstes gewinnt)
    Rectangle {
        anchors.fill: parent
        anchors.margins: -mouse.unit * 0.14
        radius: mouse.r + mouse.unit * 0.14
        color: {
            let best = "";
            let strength = 0;
            for (const id of ["mouse:272", "mouse:273", "mouse:274", "mouse_up", "mouse_down"]) {
                const g = mouse.glowOf(id);
                if (g > strength) {
                    strength = g;
                    best = id;
                }
            }
            return strength > 0 ? Colors.alpha(mouse.lights[best] ?? "transparent", strength) : "transparent";
        }

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
    }

    // Korpus (Rock)
    Rectangle {
        anchors.fill: parent
        radius: mouse.r
        color: mouse.rockBase
    }

    // Unterer Teil der Schale
    Rectangle {
        x: mouse.unit * 0.05
        y: mouse.unit * 1.32
        width: parent.width - mouse.unit * 0.1
        height: parent.height - y - mouse.unit * 0.06
        topLeftRadius: mouse.unit * 0.18
        topRightRadius: mouse.unit * 0.18
        bottomLeftRadius: mouse.r
        bottomRightRadius: mouse.r
        color: mouse.shell
    }

    // Linke Taste
    Rectangle {
        id: leftButton

        x: mouse.unit * 0.05
        y: mouse.unit * 0.04
        width: parent.width / 2 - mouse.unit * 0.09
        height: mouse.unit * 1.22
        topLeftRadius: mouse.r
        topRightRadius: mouse.unit * 0.12
        bottomLeftRadius: mouse.unit * 0.12
        bottomRightRadius: mouse.unit * 0.12
        color: mouse.tint("mouse:272")

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        HoverHandler {
            enabled: mouse.interactive
            cursorShape: mouse.infos["mouse:272"] ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHoveredChanged: mouse.hoverId = hovered ? "mouse:272" : (mouse.hoverId === "mouse:272" ? "" : mouse.hoverId)
        }

        TapHandler {
            enabled: mouse.interactive && !!mouse.infos["mouse:272"]
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (point, button) => button === Qt.RightButton ? mouse.contextClicked("mouse:272") : mouse.clicked("mouse:272")
        }
    }

    // Rechte Taste
    Rectangle {
        id: rightButton

        x: parent.width / 2 + mouse.unit * 0.04
        y: mouse.unit * 0.04
        width: parent.width / 2 - mouse.unit * 0.09
        height: mouse.unit * 1.22
        topLeftRadius: mouse.unit * 0.12
        topRightRadius: mouse.r
        bottomLeftRadius: mouse.unit * 0.12
        bottomRightRadius: mouse.unit * 0.12
        color: mouse.tint("mouse:273")

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        HoverHandler {
            enabled: mouse.interactive
            cursorShape: mouse.infos["mouse:273"] ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHoveredChanged: mouse.hoverId = hovered ? "mouse:273" : (mouse.hoverId === "mouse:273" ? "" : mouse.hoverId)
        }

        TapHandler {
            enabled: mouse.interactive && !!mouse.infos["mouse:273"]
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (point, button) => button === Qt.RightButton ? mouse.contextClicked("mouse:273") : mouse.clicked("mouse:273")
        }
    }

    // Rad: oben hoch, Mitte Klick, unten runter
    Rectangle {
        id: wheel

        anchors.horizontalCenter: parent.horizontalCenter
        y: mouse.unit * 0.3
        width: mouse.unit * 0.3
        height: mouse.unit * 0.85
        radius: width / 2
        color: Qt.darker(Colors.surfaceBright, 1.35)
        clip: true

        Repeater {
            model: [
                { id: "mouse_up", at: 0 },
                { id: "mouse:274", at: 1 },
                { id: "mouse_down", at: 2 }
            ]

            Rectangle {
                id: zone

                required property var modelData

                y: zone.modelData.at * wheel.height / 3
                width: wheel.width
                height: wheel.height / 3
                color: {
                    const info = mouse.infos[zone.modelData.id] ?? null;
                    const base = mouse.hoverId === zone.modelData.id ? Colors.alpha(Colors.fgSurface, 0.18) : "transparent";
                    if (!info)
                        return base;
                    return Colors.alpha(mouse.lights[zone.modelData.id] ?? "transparent", (mouse.lits[zone.modelData.id] ? 0.9 : 0.55) * (info.disabled ? 0.5 : 1));
                }

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }

                HoverHandler {
                    enabled: mouse.interactive
                    cursorShape: mouse.infos[zone.modelData.id] ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onHoveredChanged: mouse.hoverId = hovered ? zone.modelData.id : (mouse.hoverId === zone.modelData.id ? "" : mouse.hoverId)
                }

                TapHandler {
                    enabled: mouse.interactive && !!mouse.infos[zone.modelData.id]
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: (point, button) => button === Qt.RightButton ? mouse.contextClicked(zone.modelData.id) : mouse.clicked(zone.modelData.id)
                }
            }
        }

        // Rillen
        Column {
            anchors.centerIn: parent
            spacing: Math.max(2, mouse.unit * 0.06)

            Repeater {
                model: 7

                Rectangle {
                    width: wheel.width - 4
                    height: 1
                    color: Colors.alpha(Colors.background, 0.5)
                }
            }
        }
    }
}
