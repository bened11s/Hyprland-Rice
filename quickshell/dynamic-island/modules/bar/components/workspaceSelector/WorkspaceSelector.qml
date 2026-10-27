pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import QtQuick.Layouts
import qs.modules.services.hypr
import qs.modules.services.config

import qs.modules.widgets

// Karte links in der Leiste. Rundung, Randstärke und Randfarbe kommen aus
// Bar.qml, damit sie sich nichts mit der Notch ausdenken muss.
// Die Punkte selbst stecken in Workspace.qml; hier wird nur einmal der
// Zustand ermittelt und an alle durchgereicht.
Item {
    id: root
    anchors {
        left: parent.left
        leftMargin: HyprGaps.left
    }

    required property real verticalMargin // margin über bzw unter der notch
    required property real borderWidth   // von außen überschreibbar (Bar.qml macht das)
    required property color borderColor
    required property real cardRadius
    // Luft zwischen Punktreihe und Kartenrand (je Seite). Die Punkte bringen
    // selbst schon 6px Trefferrand mit, deshalb hier 14 statt 20.
    property real padding: 14

    // Größe einer Monitor-Gruppe. `wsMonitorOffset` in der Hypr-Config vergibt
    // je 10 am Stück (HDMI-A-1 ab 1, DP-1 ab 11).
    property int workspacesPerMonitor: Math.max(1, Math.min(10, Config.bar.workspaceCount))

    // Der Monitor, auf dem DIESE Leiste sitzt – bewusst nicht der fokussierte.
    // Sonst zeigten beide Leisten dieselbe Gruppe an.
    readonly property HyprlandMonitor hyprMonitor: Hyprland.monitorFor(root.QsWindow.window?.screen ?? null)
    readonly property int activeWsId: root.hyprMonitor?.activeWorkspace?.id ?? 1

    // Ist auf DIESEM Monitor ein Special offen? Nur dann zeigt DIESE Leiste
    // das Overlay – der andere Bildschirm behaelt seine normalen Punkte.
    // (HyprIpc haelt die Monitor-JSON frisch, sodass der Eintritt sofort
    // passiert.)
    readonly property bool onSpecial: root.activeSpecialWs !== ""

    // Welcher Special ist hier offen – er bestimmt, welches Icon die Pille
    // traegt. Die ICON-LISTE im Overlay ist trotzdem global (alle Specials
    // aller Monitore), nur die Anzeige selbst ist monitoregebunden.
    readonly property string activeSpecialWs: HyprIpc.specialOn(root.hyprMonitor)

    // Blur der Punkte, solange ein Special offen ist. Eigene Property, weil
    // der Layer-Effekt am Wrapper haengt und beide animiert mitgehen sollen.
    property real dotBlur: root.onSpecial ? 1 : 0

    Behavior on dotBlur {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    // Welche 10er-Gruppe gehört zu diesem Monitor: 0 bei ws 1-10, 10 bei 11-20
    readonly property int groupOffset: Math.floor((root.activeWsId - 1) / root.workspacesPerMonitor) * root.workspacesPerMonitor

    // { wsId: hatFenster } – einmal gebaut statt zehnmal pro Punkt gefiltert
    readonly property var occupied: {
        const occ = {};
        for (const ws of Hyprland.workspaces.values)
            occ[ws.id] = HyprIpc.windowsOn(ws) > 0;
        return occ;
    }

    // Breite kommt von innen: das RowLayout rechnet sie aus seinen Punkten,
    // die Karte fuellt root. Andersherum (root von der Karte) waere es eine
    // Binding-Schleife. Im Special-Modus misst die Karte stattdessen das
    // Overlay – sie morpht also beim Eintritt auf dessen Breite, die Punkte
    // verblassen darunter (siehe dotsWrap).
    implicitWidth: root.padding * 2
                   + (root.onSpecial ? specialWs.implicitWidth : layout.implicitWidth)

    Morph on implicitWidth {}

    height: parent.height - verticalMargin
    y: verticalMargin / 2

    Surface {
        id: card
        anchors.fill: parent

        maxRadius: root.cardRadius
        borderWidth: root.borderWidth
        borderColor: root.borderColor

        // Scrollen schaltet Workspaces. Touchpads/Hi-Res-Räder liefern viele
        // kleine Events pro Zug, oft mit angleDelta.y == 0 (nur pixelDelta
        // gefuellt) – deshalb nicht blind aufs Vorzeichen gehen, sondern
        // ansummern und pro Rasterung (120) genau einmal schalten.
        WheelHandler {
            id: wheel

            parent: card
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            property real acc: 0

            onWheel: event => {
                wheel.acc += event.angleDelta.y;
                if (Math.abs(wheel.acc) < 120)
                    return;

                const dir = wheel.acc > 0 ? "m-1" : "m+1";
                wheel.acc = 0;
                Hyprland.dispatch(`hl.dsp.focus({ workspace = "${dir}" })`);
            }
        }

        // Die Punkte hängen in einem eigenen Wrapper, damit sie sich als
        // Ganzes zurücknehmen lassen: Beim Special-Eintritt schrumpfen sie,
        // verblassen und werden unscharf – das Overlay
        // legt sich darüber. Der Blur hängt am Layer des Wrappers; der harte
        // layer.enabled-Umschprung fällt nicht auf, weil dotBlur bei 0 startet.
        Item {
            id: dotsWrap

            anchors.centerIn: parent
            width: layout.implicitWidth
            height: layout.implicitHeight

            scale: root.onSpecial ? 0.8 : 1
            opacity: root.onSpecial ? 0.5 : 1

            // Wichtig: Punkte im Special-Modus komplett vom Input abkoppeln.
            // Pointer-Handler sind nicht exklusiv – die TapHandler der Punkte
            // bekommen vom Overlay-Klick sonst noch etwas mit (passiver Grab)
            // und es feuern beide Aktionen. Disable trifft alle Handler
            // inkl. Hover-Cursor der Kinder.
            enabled: !root.onSpecial

            layer.enabled: root.dotBlur > 0
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: root.dotBlur
                blurMax: 32
            }

            Behavior on scale {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            RowLayout {
                id: layout
                anchors.centerIn: parent

                // 0, weil der Abstand aus dem hitPadding der Punkte kommt –
                // so grenzen die Klickzonen lückenlos aneinander.
                spacing: 0

                Repeater {
                    id: workspaces

                    model: root.workspacesPerMonitor

                    Workspace {
                        activeWsId: root.activeWsId
                        occupied: root.occupied
                        groupOffset: root.groupOffset
                    }
                }
            }
        }

        // Special-Overlay, solange auf diesem Monitor ein Special offen ist
        // (siehe SpecialWorkspaces.qml). Liegt ZENTRIERT über den verwischten
        // Punkten. Die Punkte
        // sind im Special-Modus über `enabled` abgeschaltet (siehe dotsWrap),
        // weil Handler ihren Input sonst mit dem Overlay teilen würden.
        SpecialWorkspaces {
            id: specialWs

            anchors.centerIn: parent
            activeSpecial: root.activeSpecialWs

            opacity: root.onSpecial ? 1 : 0
            scale: root.onSpecial ? 1 : 0.5
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }
}
