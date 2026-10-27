pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs
import qs.modules.services.config
import qs.modules.services.hypr
import qs.modules.widgets

// Workspace-Anzeige der Notch: senkrechte Staebchen, der aktive ist hoeher.
// Steht links neben der Uhr – eingeklappt wie aufgeklappt (Kopfzeile der
// Uebersicht und der Untermenues), ein Klick wechselt den Workspace.
//
// Drei Stile (Config.notch.workspaceStyle), gezeichnet vom Marker unten:
//   "staebchen"  senkrechte Striche, der aktive hoeher
//   "punkte"     waagerechte Punkte, der aktive als breite Pille
//   "zahlen"     Ziffern 1..n, der aktive voll deckend
// Klick, Hover, Mausrad und Specials sind in allen Stilen gleich; die Hoehe
// des Elements bleibt activeHeight, damit die Kopfzeile nicht springt.
//
// Special-Workspaces: ist auf DIESEM Monitor einer offen, treten die
// Workspace-Staebchen fast ganz zurueck und an ihrer Stelle stehen die
// vorhandenen Specials – ebenfalls als Staebchen, jeder in seiner eigenen
// Farbe (specialColor), der offene hoch wie der aktive Workspace. Klick
// toggelt. Ohne offenen Special sind Specials nicht zu sehen.
//
// Dieselbe Gruppenlogik wie WorkspaceSelector.qml: jede Leiste zeigt die
// Workspaces ihres eigenen Monitors (je `perMonitor` am Stueck). Frisch
// gehalten werden die Hyprland-Listen von HyprIpc.
Item {
    id: root

    // Dieselbe Einstellung wie die grosse Punktreihe (bar.workspaceCount)
    property int perMonitor: Math.max(1, Math.min(10, Config.bar.workspaceCount))
    property color color: Colors.primary
    property real barWidth: 5
    property real activeHeight: 15
    property real idleHeight: 9
    // Punkte-Stil: Durchmesser und Breite der aktiven Pille
    property real dotSize: 6
    property real pillWidth: 16
    // Zahlen-Stil: Schriftgroesse
    property real digitSize: 11

    readonly property string style: Config.notch.workspaceStyle
    // Abstand der Marker je Stil
    readonly property real gap: root.style === "punkte" ? 5 : root.style === "zahlen" ? 6 : 4

    readonly property HyprlandMonitor hyprMonitor: Hyprland.monitorFor(root.QsWindow.window?.screen ?? null)
    readonly property int activeId: root.hyprMonitor?.activeWorkspace?.id ?? 1
    readonly property int groupOffset: Math.floor((root.activeId - 1) / root.perMonitor) * root.perMonitor
    // Offener Special-Workspace auf DIESEM Monitor ("" = keiner)
    readonly property string activeSpecial: HyprIpc.specialOn(root.hyprMonitor)
    readonly property bool onSpecial: root.activeSpecial !== ""

    // { wsId: hatFenster }
    readonly property var occupied: {
        const occ = {};
        for (const ws of Hyprland.workspaces.values)
            occ[ws.id] = HyprIpc.windowsOn(ws) > 0;
        return occ;
    }
    // Alle vorhandenen Specials (fuer das Overlay)
    readonly property var specials: Hyprland.workspaces.values
        .filter(w => w.name.startsWith("special:"))
        .sort((a, b) => a.name.localeCompare(b.name))

    // Das Overlay ist genau so breit wie die Staebchen-Reihe – die Anzeige
    // behaelt ihre Groesse, egal ob ein Special offen ist
    implicitWidth: bars.implicitWidth
    implicitHeight: root.activeHeight

    // Mausrad: zum naechsten bzw. vorigen Workspace MIT Fenstern dieser
    // Gruppe springen (leere werden uebersprungen), am Ende geht es von vorn
    // weiter. Eine Rastung (120, Hi-Res-Teilschritte aufsummiert) = ein Sprung.
    function jump(dir: int): void {
        const ids = [];
        for (let i = 1; i <= root.perMonitor; i++) {
            const id = root.groupOffset + i;
            if (root.occupied[id] || id === root.activeId)
                ids.push(id);
        }
        if (ids.length < 2)
            return;
        const at = Math.max(0, ids.indexOf(root.activeId));
        const next = ids[((at + dir) % ids.length + ids.length) % ids.length];
        Hyprland.dispatch(Hyprland.usingLua
            ? `hl.dsp.focus({ workspace = ${next} })`
            : `workspace ${next}`);
    }

    WheelHandler {
        id: wheel

        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        // Waehrend ein Special offen ist, gehoert das Rad nicht hierher
        enabled: !root.onSpecial

        property real accum: 0

        onWheel: event => {
            const angle = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
            const pixels = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.pixelDelta.x;
            const delta = pixels !== 0 ? pixels / 60 : angle / 120;
            if (wheel.accum !== 0 && Math.sign(delta) !== Math.sign(wheel.accum))
                wheel.accum = 0;
            wheel.accum += delta;
            wheelDecay.restart();
            if (Math.abs(wheel.accum) < 1)
                return;
            // Rad nach unten = naechster Workspace
            root.jump(wheel.accum < 0 ? 1 : -1);
            wheel.accum = 0;
        }
    }

    Timer {
        id: wheelDecay

        interval: 500
        onTriggered: wheel.accum = 0
    }

    // Feste, gut unterscheidbare Farbe je Special: eigener Farbton, Helligkeit
    // und Saettigung am Theme ausgerichtet (die Theme-Rollen selbst liegen in
    // vielen Schemata zu nah beieinander). Unbekannte Specials reihum.
    function specialColor(key: string, index: int): color {
        const hues = {
            "music": 0.38,          // gruen
            "communication": 0.58,  // blau
            "sysmon": 0.07,         // orange
            "special": 0.78,        // violett
            "todo": 0.15            // gelb
        };
        const cycle = [0.38, 0.58, 0.07, 0.78, 0.15, 0.95];
        const hue = hues[key] ?? cycle[index % cycle.length];
        const light = Math.max(0.62, Math.min(0.75, Colors.primary.hslLightness));
        return Qt.hsla(hue, 0.7, light, 1);
    }

    // ---- Marker: ein Workspace in einem der drei Stile ----
    // Wird fuer Workspaces und Specials benutzt (StylePreview baut ihn fuer
    // die Vorschau im Menue mit festen Werten nach).
    component Marker: Item {
        id: marker

        property string style: "staebchen"
        property bool active: false
        property bool occupied: false
        property bool hovered: false
        property color color: Colors.primary
        // Beschriftung im Zahlen-Stil
        property string label: ""
        // Deckkraft unter dem Zeiger (Specials heben staerker an)
        property real hoverOpacity: 0.5
        property real barWidth: 5
        property real activeHeight: 15
        property real idleHeight: 9
        property real dotSize: 6
        property real pillWidth: 16
        property real digitSize: 11

        readonly property bool dots: marker.style === "punkte"
        readonly property bool digits: marker.style === "zahlen"
        // aktiv 1, belegt 0.6, leer 0.3 – Hover hebt an, senkt aber nie
        readonly property real fade: marker.active ? 1
            : marker.occupied ? Math.max(0.6, marker.hovered ? marker.hoverOpacity : 0)
            : marker.hovered ? marker.hoverOpacity
            : 0.3

        implicitWidth: marker.digits ? digit.implicitWidth
                     : marker.dots ? (marker.active ? marker.pillWidth : marker.dotSize)
                     : marker.barWidth
        implicitHeight: marker.activeHeight

        Behavior on implicitWidth {
            NumberAnimation { duration: Appearance.morphDuration * 0.6; easing.type: Easing.OutCubic }
        }

        // Staebchen bzw. Punkt/Pille
        Rectangle {
            anchors.centerIn: parent
            visible: !marker.digits
            width: marker.dots ? (marker.active ? marker.pillWidth : marker.dotSize) : marker.barWidth
            height: marker.dots ? marker.dotSize
                  : marker.active ? marker.activeHeight : marker.idleHeight
            radius: Math.min(width, height) / 2
            color: marker.color
            opacity: marker.fade

            Behavior on height {
                NumberAnimation { duration: Appearance.morphDuration * 0.6; easing.type: Easing.OutBack; easing.overshoot: 2 }
            }
            Behavior on width {
                NumberAnimation { duration: Appearance.morphDuration * 0.6; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
            }
            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }
        }

        // Ziffer
        Text {
            id: digit

            anchors.centerIn: parent
            visible: marker.digits
            text: marker.label
            color: marker.color
            font.family: Config.font
            font.pixelSize: marker.digitSize
            font.weight: Font.DemiBold
            // Ziffern sind feiner als Flaechen und brauchen etwas mehr Deckkraft
            opacity: Math.min(1, marker.fade + (marker.active ? 0 : 0.08))

            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }
        }
    }

    // ---- Workspaces ----
    Row {
        id: bars

        anchors.centerIn: parent
        spacing: root.gap
        height: root.activeHeight
        opacity: root.onSpecial ? 0.12 : 1
        scale: root.onSpecial ? 0.9 : 1
        // Im Special-Modus gehoeren die Klicks dem Overlay
        enabled: !root.onSpecial

        Fade on opacity {}
        Morph on scale {}

        Repeater {
            model: root.perMonitor

            Item {
                id: slot

                required property int index
                readonly property int ws: root.groupOffset + slot.index + 1
                readonly property bool active: slot.ws === root.activeId

                width: slotMarker.implicitWidth
                height: root.activeHeight

                Marker {
                    id: slotMarker

                    anchors.centerIn: parent
                    style: root.style
                    active: slot.active
                    occupied: root.occupied[slot.ws] ?? false
                    hovered: slotHover.hovered
                    color: root.color
                    label: String(slot.index + 1)
                    barWidth: root.barWidth
                    activeHeight: root.activeHeight
                    idleHeight: root.idleHeight
                    dotSize: root.dotSize
                    pillWidth: root.pillWidth
                    digitSize: root.digitSize
                }

                // Trefferflaeche groesser als der Marker
                Item {
                    anchors.centerIn: parent
                    width: slot.width + bars.spacing
                    height: root.activeHeight + 10

                    HoverHandler {
                        id: slotHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    // Klick auf den aktiven Workspace = Special oeffnen bzw.
                    // schliessen (wie der aktive Punkt der grossen Leiste)
                    TapHandler {
                        onTapped: {
                            if (slot.active)
                                Hyprland.dispatch(Hyprland.usingLua
                                    ? 'hl.dsp.workspace.toggle_special("special")'
                                    : "togglespecialworkspace special");
                            else
                                Hyprland.dispatch(Hyprland.usingLua
                                    ? `hl.dsp.focus({ workspace = ${slot.ws} })`
                                    : `workspace ${slot.ws}`);
                        }
                    }
                }
            }
        }
    }

    // ---- Specials als farbige Marker ----
    // Liegen mittig ueber der Workspace-Reihe, gleicher Stil und Bewegung;
    // im Zahlen-Stil steht der Anfangsbuchstabe des Specials.
    Row {
        id: specialBars

        anchors.centerIn: parent
        spacing: bars.spacing
        height: root.activeHeight
        opacity: root.onSpecial ? 1 : 0
        scale: root.onSpecial ? 1 : 0.6
        visible: opacity > 0

        Fade on opacity {}
        Morph on scale {}

        Repeater {
            model: root.specials

            Item {
                id: special

                required property var modelData   // HyprlandWorkspace
                required property int index
                readonly property string key: special.modelData.name.slice("special:".length)
                readonly property bool active: root.activeSpecial === special.modelData.name

                width: specialMarker.implicitWidth
                height: root.activeHeight

                Marker {
                    id: specialMarker

                    anchors.centerIn: parent
                    style: root.style
                    active: special.active
                    // Specials gelten immer als belegt (sie liegen ja vor)
                    occupied: true
                    hovered: specialHover.hovered
                    hoverOpacity: 0.8
                    color: root.specialColor(special.key, special.index)
                    label: special.key.charAt(0).toUpperCase()
                    barWidth: root.barWidth
                    activeHeight: root.activeHeight
                    idleHeight: root.idleHeight
                    dotSize: root.dotSize
                    pillWidth: root.pillWidth
                    digitSize: root.digitSize
                }

                Item {
                    anchors.centerIn: parent
                    width: special.width + specialBars.spacing
                    height: root.activeHeight + 10

                    HoverHandler {
                        id: specialHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: Hyprland.dispatch(Hyprland.usingLua
                            ? `hl.dsp.workspace.toggle_special("${special.key}")`
                            : `togglespecialworkspace ${special.key}`)
                    }
                }
            }
        }
    }
}
