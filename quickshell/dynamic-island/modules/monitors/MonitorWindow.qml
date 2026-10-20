pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs
import qs.modules.services.config
import qs.modules.services.monitors
import qs.modules.widgets

// Bildschirm-Fenster: Ausrichtung, Modus, Skalierung und Spiegelung der
// Monitore – im Stil der Einstellungen (Surface, Colors, Morph/Fade).
//
// Links die Monitorliste, rechts oben die Anordnung zum Ziehen, darunter
// die Einstellungen des gewaehlten Monitors, unten die Aktionsleiste.
//
// Bewusst keine Anker, wie SettingsWindow: eine Layer-Oberflaeche ohne
// Anker setzt der Compositor mittig.
//
// Anwenden setzt per hyprctl eval ins laufende Hyprland, Speichern
// schreibt ~/.config/hypr/monitors.lua (siehe services/monitors).
LazyLoader {
    active: MonitorState.open && MonitorState.screen !== null

    PanelWindow {
        id: win

        readonly property ShellScreen modelData: MonitorState.screen

        // Gewaehlter Monitor in der Liste
        property string selected: ""
        readonly property var selectedLive: Monitors.live(win.selected)

        // Waehrend des Ziehens eingefroren: ohne das rechnet die gesamte
        // Vorschau bei JEDER Positionsaenderung um (Bounds waechst/schrumpft
        // -> alle Kasten skalieren mit -> "verbogen"), und die Maus haengt in
        // der mitlaufenden Box (Feedback-Loop -> Zittern).
        property bool dragging: false
        property real frozenScale: 0
        property var frozenBounds: ({ x: 0, y: 0, w: 1, h: 1 })

        // Vorschau-Massstab: Gesamtanordnung passt in die Flaäche
        readonly property var bounds: win.dragging ? win.frozenBounds : Monitors.layoutInfo()
        readonly property real previewScale: {
            if (win.dragging && win.frozenScale > 0)
                return win.frozenScale;
            if (!Monitors.loaded || bounds.w <= 0 || bounds.h <= 0)
                return 1;
            const area = Math.min((win.width - win.inset * 2 - 236 - 60) / bounds.w,
                                  (win.height - win.inset * 2 - 210) / bounds.h);
            return Math.max(0.02, Math.min(0.5, area));
        }

        readonly property real inset: 28

        screen: win.modelData
        visible: MonitorState.open && MonitorState.screen === win.modelData

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dynamic-island-monitors"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        implicitWidth: 1010 + inset * 2
        implicitHeight: 640 + inset * 2

        // Liste beim Oeffnen auf den fokussierten Monitor stellen
        onVisibleChanged: if (visible && win.selected === "")
            win.selected = Monitors.monitors.find(m => m.focused)?.name
                ?? Monitors.monitors[0]?.name ?? "";

        // Erstes Lesen verzoegert, damit die Liste nicht leer startet
        Connections {
            target: Monitors

            function onLoadedChanged(): void {
                if (win.visible && win.selected === "")
                    win.selected = Monitors.monitors[0]?.name ?? "";
                // Auswahl pruefen: weggezogener Monitor darf nicht gewaehlt bleiben
                if (win.selected !== "" && !Monitors.live(win.selected))
                    win.selected = Monitors.monitors[0]?.name ?? "";
            }
        }

        // --------------------------------------------- Hilfsfunktionen ----
        // logischeSize und layoutInfo liegen jetzt im Service (Monitors.*),
        // damit auch die Kachel/sonstige Nutzer dieselben Werte haben.

        // ================= Die Karte =================
        Surface {
            id: card

            // Escape schliesst das Fenster (auf der Karte: PanelWindow ist
            // kein Item und traegt kein Keys, dieselbe Stelle wie in SettingsWindow)
            Keys.onEscapePressed: MonitorState.close()

            anchors {
                fill: parent
                margins: win.inset
            }
            maxRadius: 24

            scale: win.visible ? 1 : 0.96
            opacity: win.visible ? 1 : 0
            Morph on scale {}
            Fade on opacity {}

            // ================= Linke Leiste =================
            Item {
                id: sidebar

                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: 236

                Rectangle {
                    anchors.fill: parent
                    topLeftRadius: card.radius
                    bottomLeftRadius: card.radius
                    color: Colors.alpha(Colors.fgSurface, 0.035)
                }

                Rectangle {
                    anchors {
                        right: parent.right
                        top: parent.top
                        bottom: parent.bottom
                    }
                    width: 1
                    color: Colors.alpha(Colors.outline, 0.25)
                }

                Text {
                    id: title

                    font.family: Config.font
                    anchors {
                        left: parent.left
                        leftMargin: 22
                        top: parent.top
                        topMargin: 24
                    }
                    text: "Bildschirm"
                    color: Colors.fgBackground
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }

                Text {
                    font.family: Config.font
                    anchors {
                        left: title.left
                        top: title.bottom
                        topMargin: 2
                    }
                    text: Monitors.loaded
                          ? Monitors.monitors.filter(m => !Monitors.eff(m.name, "enabled", !m.disabled)).length === 0
                            ? Monitors.monitors.length + " Monitore aktiv"
                            : Monitors.monitors.filter(m => Monitors.eff(m.name, "enabled", !m.disabled)).length
                              + " von " + Monitors.monitors.length + " aktiv"
                          : "Lese Monitore …"
                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                    font.pixelSize: 10
                }

                // ---- Monitorliste ----
                Flickable {
                    id: list

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: title.bottom
                        topMargin: 28
                        bottom: parent.bottom
                        bottomMargin: 16
                    }
                    contentHeight: listColumn.implicitHeight + 8
                    clip: true

                    Column {
                        id: listColumn

                        width: parent.width - 24
                        x: 12
                        spacing: 2

                        Repeater {
                            model: Monitors.monitors

                            delegate: Rectangle {
                                id: entry

                                required property var modelData
                                readonly property var m: entry.modelData
                                readonly property bool isSelected: win.selected === entry.m.name
                                readonly property bool isOn: Monitors.eff(entry.m.name, "enabled", !entry.m.disabled)
                                // Im Entwurf geaendert?
                                readonly property bool touched: Monitors.draft[entry.m.name] !== undefined

                                width: parent.width
                                height: 52
                                radius: 12
                                color: entry.isSelected ? Colors.alpha(Colors.primary, 0.16)
                                     : entryHover.hovered ? Colors.alpha(Colors.fgSurface, 0.07)
                                     : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }

                                TapHandler {
                                    onTapped: win.selected = entry.m.name
                                }

                                HoverHandler {
                                    id: entryHover
                                }

                                Text {
                                    anchors {
                                        left: parent.left
                                        leftMargin: 14
                                        top: parent.top
                                        topMargin: 9
                                    }
                                    text: entry.m.name
                                    font.family: Config.font
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: entry.isSelected ? Colors.primary : Colors.fgBackground
                                    opacity: entry.isOn ? 1 : 0.45
                                }

                                Text {
                                    anchors {
                                        left: parent.left
                                        leftMargin: 14
                                        top: parent.top
                                        topMargin: 27
                                    }
                                    width: parent.width - 34
                                    elide: Text.ElideRight
                                    text: {
                                        const label = [entry.m.make, entry.m.model].filter(s => s && s !== "Unknown").join(" ");
                                        return label !== "" ? label : entry.m.description;
                                    }
                                    font.family: Config.font
                                    font.pixelSize: 10
                                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.85)
                                    opacity: entry.isOn ? 1 : 0.45
                                }

                                // Punkt: aktiv / aus / im Entwurf geaendert
                                Rectangle {
                                    anchors {
                                        right: parent.right
                                        rightMargin: 14
                                        verticalCenter: parent.verticalCenter
                                    }
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: !entry.isOn ? Colors.alpha(Colors.fgSurfaceVariant, 0.5)
                                         : entry.touched ? Colors.tertiary
                                         : Colors.primary
                                }
                            }
                        }
                    }
                }
            }

            // ================= Rechts: Inhalt =================
            Item {
                id: content

                anchors {
                    left: sidebar.right
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }

                // ---- Anordnung (Vorschau) ----
                Item {
                    id: preview

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: 26
                        rightMargin: 26
                        topMargin: 22
                    }
                    height: 200

                    Text {
                        id: previewLabel

                        font.family: Config.font
                        text: "Anordnung"
                        color: Colors.fgBackground
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        font.family: Config.font
                        anchors {
                            left: previewLabel.right
                            leftMargin: 10
                            verticalCenter: previewLabel.verticalCenter
                        }
                        visible: Monitors.dirty
                        text: "· Entwurf"
                        color: Colors.tertiary
                        font.pixelSize: 11
                    }

                    // Flaeche, in der die Monitore liegen
                    Item {
                        id: canvas

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: previewLabel.bottom
                            topMargin: 10
                            bottom: parent.bottom
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: Colors.alpha(Colors.fgSurface, 0.04)
                            border.width: 1
                            border.color: Colors.alpha(Colors.outline, 0.2)
                        }

                        Repeater {
                            model: Monitors.monitors

                            delegate: Rectangle {
                                id: box

                                required property var modelData
                                readonly property var m: box.modelData
                                readonly property bool isOn: Monitors.eff(box.m.name, "enabled", !box.m.disabled)
                                readonly property bool isSelected: win.selected === box.m.name
                                readonly property bool mirrored: Monitors.eff(box.m.name, "mirror", box.m.mirrorOf) !== ""

                                // Obere linke Ecke in logischen Pixeln
                                readonly property real lx: Monitors.eff(box.m.name, "x", box.m.x)
                                readonly property real ly: Monitors.eff(box.m.name, "y", box.m.y)
                                readonly property var size: Monitors.logicalSize(box.m)

                                visible: box.isOn && !box.mirrored
                                // Ursprung des Ausschnitts abziehen: beginnt die
                                // Anordnung z.B. bei x=1920, steht der Kasten trotzdem
                                // links in der Vorschau
                                x: (lx - win.bounds.x) * win.previewScale
                                y: (ly - win.bounds.y) * win.previewScale
                                width: Math.max(24, box.size.w * win.previewScale)
                                height: Math.max(24, box.size.h * win.previewScale)
                                radius: 8
                                color: box.isSelected ? Colors.alpha(Colors.primary, 0.22)
                                     : Colors.alpha(Colors.surfaceContainer, 0.9)
                                border.width: box.isSelected ? 2 : 1
                                border.color: box.isSelected ? Colors.primary
                                             : Colors.alpha(Colors.outline, 0.45)
                                opacity: 1

                                // Waehrend des Ziehens keine Animation – sonst
                                // nachlaufende, gummibandartige Bewegung
                                Behavior on x {
                                    enabled: !win.dragging
                                    NumberAnimation { duration: 140 }
                                }
                                Behavior on y {
                                    enabled: !win.dragging
                                    NumberAnimation { duration: 140 }
                                }

                                TapHandler {
                                    onTapped: win.selected = box.m.name
                                }

                                // Ziehen: laufend ueber den Entwurf setzen, damit
                                // die x/y-Bindings des Kastens heil bleiben.
                                // Koordinaten ueber canvas (mapToItem) – nicht ueber
                                // die Maus in der Box, denn die Box zieht mit und
                                // erzeugt sonst eine Feedback-Schleife (Zittern).
                                MouseArea {
                                    id: dragArea

                                    anchors.fill: parent
                                    cursorShape: Qt.SizeAllCursor

                                    property real startCx: 0
                                    property real startCy: 0
                                    property real startLx: 0
                                    property real startLy: 0

                                    function canvasPos(mouse: var): var {
                                        return dragArea.mapToItem(canvas, mouse.x, mouse.y);
                                    }

                                    onEntered: win.selected = box.m.name
                                    onPressed: (mouse) => {
                                        // ERST die Werte merken, DANN einfrieren –
                                        // sonst liest bounds/scale schon den
                                        // eingefrorenen (noch leeren) Zustand
                                        win.frozenScale = win.previewScale;
                                        win.frozenBounds = win.bounds;
                                        win.dragging = true;
                                        const p = dragArea.canvasPos(mouse);
                                        startCx = p.x;
                                        startCy = p.y;
                                        startLx = box.lx;
                                        startLy = box.ly;
                                    }
                                    onPositionChanged: (mouse) => {
                                        if (!pressed)
                                            return;
                                        const p = dragArea.canvasPos(mouse);
                                        const scale = win.frozenScale > 0 ? win.frozenScale : win.previewScale;
                                        let nx = Math.round(startLx + (p.x - startCx) / scale);
                                        let ny = Math.round(startLy + (p.y - startCy) / scale);
                                        // Kanten-Snapping wie Plasma
                                        const snapped = Monitors.snap(box.m.name, nx, ny);
                                        nx = snapped.x;
                                        ny = snapped.y;
                                        if (nx !== Monitors.eff(box.m.name, "x", box.m.x))
                                            Monitors.set(box.m.name, "x", nx);
                                        if (ny !== Monitors.eff(box.m.name, "y", box.m.y))
                                            Monitors.set(box.m.name, "y", ny);
                                    }
                                    onReleased: {
                                        win.dragging = false;
                                        win.frozenScale = 0;
                                        if (Monitors.dirty) {
                                            // Hart andocken: die Drag-Toleranz
                                            // (16px) laesst sonst Luecken wie
                                            // 24px stehen – an denen der Cursor
                                            // haengenbleibt (kein Kantenwechsel)
                                            const x = Monitors.eff(box.m.name, "x", box.m.x);
                                            const y = Monitors.eff(box.m.name, "y", box.m.y);
                                            const p = Monitors.snap(box.m.name, x, y, 40);
                                            if (p.x !== x)
                                                Monitors.set(box.m.name, "x", p.x);
                                            if (p.y !== y)
                                                Monitors.set(box.m.name, "y", p.y);
                                            Monitors.apply();
                                        }
                                    }
                                    onCanceled: {
                                        win.dragging = false;
                                        win.frozenScale = 0;
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: box.m.name
                                    font.family: Config.font
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                    color: box.isSelected ? Colors.primary : Colors.fgSurfaceVariant
                                }

                                Text {
                                    anchors {
                                        horizontalCenter: parent.horizontalCenter
                                        bottom: parent.bottom
                                        bottomMargin: 4
                                    }
                                    text: box.size.w + "×" + box.size.h
                                    font.family: Config.font
                                    font.pixelSize: 8
                                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                                }
                            }
                        }

                        // Hinweis, solange nichts gelesen ist
                        Text {
                            anchors.centerIn: parent
                            visible: !Monitors.loaded
                            text: "Monitore werden gelesen …"
                            font.family: Config.font
                            font.pixelSize: 11
                            color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                        }
                    }
                }

                // ---- Einstellungen des gewaehlten Monitors ----
                Flickable {
                    id: settings

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: preview.bottom
                        topMargin: 14
                        bottom: actions.top
                        bottomMargin: 10
                        leftMargin: 26
                        rightMargin: 26
                    }
                    contentHeight: settingsCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: settingsCol

                        width: parent.width
                        spacing: 8

                        Text {
                            visible: win.selectedLive === null
                            text: Monitors.loaded ? "Kein Monitor gewaehlt" : "Lade …"
                            font.family: Config.font
                            font.pixelSize: 12
                            color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                        }

                        // ---- Modus (Aufloesung @ Hz) ----
                        Row {
                            visible: win.selectedLive !== null
                            spacing: 10

                            Text {
                                width: 96
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Modus"
                                font.family: Config.font
                                font.pixelSize: 12
                                color: Colors.fgSurfaceVariant
                            }

                            // Kompakte Chip-Auswahl statt Dropdown: die Liste
                            // der Modi ist kurz genug und man sieht alles
                            Flow {
                                width: settingsCol.width - 106
                                spacing: 6

                                Repeater {
                                    model: win.selectedLive?.modes ?? []

                                    delegate: Rectangle {
                                        id: modeChip

                                        required property var modelData
                                        // Fallback: exakter String des ZUSTAENDIGEN
                                        // Modus aus availableModes (Rundung "60" vs
                                        // "60.00" matchte sonst nie)
                                        readonly property bool isSelected: Monitors.eff(win.selected, "mode", Monitors.currentModeString(win.selectedLive)) === modelData.mode

                                        height: 28
                                        radius: 8
                                        color: modeChip.isSelected ? Colors.alpha(Colors.primary, 0.18)
                                             : modeHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1)
                                             : Colors.alpha(Colors.fgSurface, 0.05)
                                        border.width: 1
                                        border.color: modeChip.isSelected ? Colors.alpha(Colors.primary, 0.5)
                                                     : "transparent"

                                        Behavior on color {
                                            ColorAnimation { duration: 120 }
                                        }

                                        HoverHandler {
                                            id: modeHover
                                        }

                                        TapHandler {
                                            onTapped: Monitors.set(win.selected, "mode", modeChip.modelData.mode)
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            anchors.margins: 0
                                            leftPadding: 10
                                            rightPadding: 10
                                            text: modeChip.modelData.mode.replace("@", " @ ") + " Hz"
                                            font.family: Config.font
                                            font.pixelSize: 11
                                            color: modeChip.isSelected ? Colors.primary : Colors.fgBackground
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Skalierung ----
                        Row {
                            visible: win.selectedLive !== null
                            spacing: 10

                            Text {
                                width: 96
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Skalierung"
                                font.family: Config.font
                                font.pixelSize: 12
                                color: Colors.fgSurfaceVariant
                            }

                            Flow {
                                width: settingsCol.width - 106
                                spacing: 6

                                Repeater {
                                    // Nur Stufen, die fuer diese Aufloesung sauber
                                    // teilen (sonst "Invalid scale" bei Hyprland),
                                    // plus der aktuell eingestellte Wert, damit die
                                    // laufende Skalierung immer markiert ist
                                    model: {
                                        const list = Monitors.validScales(win.selectedLive);
                                        const cur = Monitors.eff(win.selected, "scale", win.selectedLive?.scale ?? 1);
                                        if (!list.some(s => Math.abs(s - cur) < 0.01))
                                            list.push(cur);
                                        return list;
                                    }

                                    delegate: Rectangle {
                                        id: scaleChip

                                        required property real modelData
                                        readonly property bool isSelected: Math.abs(Monitors.eff(win.selected, "scale", win.selectedLive?.scale ?? 1) - modelData) < 0.01

                                        height: 28
                                        width: 52
                                        radius: 8
                                        color: scaleChip.isSelected ? Colors.alpha(Colors.primary, 0.18)
                                             : scaleHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1)
                                             : Colors.alpha(Colors.fgSurface, 0.05)
                                        border.width: 1
                                        border.color: scaleChip.isSelected ? Colors.alpha(Colors.primary, 0.5)
                                                     : "transparent"

                                        HoverHandler {
                                            id: scaleHover
                                        }

                                        TapHandler {
                                            onTapped: Monitors.set(win.selected, "scale", scaleChip.modelData)
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: scaleChip.modelData.toFixed(2).replace(/\.?0+$/, "").replace(".", ",")
                                            font.family: Config.font
                                            font.pixelSize: 11
                                            color: scaleChip.isSelected ? Colors.primary : Colors.fgBackground
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Ausrichtung ----
                        Row {
                            visible: win.selectedLive !== null
                            spacing: 10

                            Text {
                                width: 96
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Ausrichtung"
                                font.family: Config.font
                                font.pixelSize: 12
                                color: Colors.fgSurfaceVariant
                            }

                            Flow {
                                width: settingsCol.width - 106
                                spacing: 6

                                Repeater {
                                    // transform 0–7: 0–3 gedreht, 4–7 gespiegelt
                                    model: [
                                        { t: 0, label: "Quer" },
                                        { t: 1, label: "Hoch 90°" },
                                        { t: 2, label: "180°" },
                                        { t: 3, label: "270°" },
                                        { t: 4, label: "Gespiegelt" },
                                        { t: 5, label: "Hoch 90° gesp." },
                                        { t: 6, label: "180° gesp." },
                                        { t: 7, label: "270° gesp." }
                                    ]

                                    delegate: Rectangle {
                                        id: rotChip

                                        required property var modelData
                                        readonly property bool isSelected: Monitors.eff(win.selected, "transform", win.selectedLive?.transform ?? 0) === modelData.t

                                        height: 28
                                        radius: 8
                                        color: rotChip.isSelected ? Colors.alpha(Colors.primary, 0.18)
                                             : rotHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1)
                                             : Colors.alpha(Colors.fgSurface, 0.05)
                                        border.width: 1
                                        border.color: rotChip.isSelected ? Colors.alpha(Colors.primary, 0.5)
                                                     : "transparent"

                                        HoverHandler {
                                            id: rotHover
                                        }

                                        TapHandler {
                                            onTapped: Monitors.set(win.selected, "transform", rotChip.modelData.t)
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            leftPadding: 10
                                            rightPadding: 10
                                            text: rotChip.modelData.label
                                            font.family: Config.font
                                            font.pixelSize: 11
                                            color: rotChip.isSelected ? Colors.primary : Colors.fgBackground
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Spiegelung ----
                        Row {
                            visible: win.selectedLive !== null && Monitors.monitors.length > 1
                            spacing: 10

                            Text {
                                width: 96
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Spiegelung"
                                font.family: Config.font
                                font.pixelSize: 12
                                color: Colors.fgSurfaceVariant
                            }

                            Flow {
                                width: settingsCol.width - 106
                                spacing: 6

                                Repeater {
                                    // "Kein Spiegel" + alle anderen Monitore
                                    model: [""].concat(Monitors.monitors
                                        .filter(m => m.name !== win.selected)
                                        .map(m => m.name))

                                    delegate: Rectangle {
                                        id: mirrorChip

                                        required property string modelData
                                        readonly property bool isSelected: (Monitors.eff(win.selected, "mirror", win.selectedLive?.mirrorOf ?? "") || "") === modelData

                                        height: 28
                                        radius: 8
                                        color: mirrorChip.isSelected ? Colors.alpha(Colors.primary, 0.18)
                                             : mirrorHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1)
                                             : Colors.alpha(Colors.fgSurface, 0.05)
                                        border.width: 1
                                        border.color: mirrorChip.isSelected ? Colors.alpha(Colors.primary, 0.5)
                                                     : "transparent"

                                        HoverHandler {
                                            id: mirrorHover
                                        }

                                        TapHandler {
                                            onTapped: Monitors.set(win.selected, "mirror", mirrorChip.modelData)
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            leftPadding: 10
                                            rightPadding: 10
                                            text: mirrorChip.modelData === "" ? "Kein Spiegel" : mirrorChip.modelData
                                            font.family: Config.font
                                            font.pixelSize: 11
                                            color: mirrorChip.isSelected ? Colors.primary : Colors.fgBackground
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Schalter: Aktiv / VRR ----
                        Row {
                            visible: win.selectedLive !== null
                            spacing: 10

                            Text {
                                width: 96
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Sonstiges"
                                font.family: Config.font
                                font.pixelSize: 12
                                color: Colors.fgSurfaceVariant
                            }

                            component MiniToggle: Rectangle {
                                id: mini

                                property string label
                                property bool checked
                                signal toggled()

                                height: 28
                                radius: 8
                                color: mini.checked ? Colors.alpha(Colors.primary, 0.18)
                                     : miniHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1)
                                     : Colors.alpha(Colors.fgSurface, 0.05)
                                border.width: 1
                                border.color: mini.checked ? Colors.alpha(Colors.primary, 0.5) : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: 120 }
                                }

                                HoverHandler {
                                    id: miniHover
                                }

                                TapHandler {
                                    onTapped: mini.toggled()
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 5

                                    Item { width: 10; height: 1 }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: mini.label
                                        font.family: Config.font
                                        font.pixelSize: 11
                                        color: mini.checked ? Colors.primary : Colors.fgBackground
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: mini.checked ? "check" : "close"
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 13
                                        color: mini.checked ? Colors.primary : Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                                    }

                                    Item { width: 10; height: 1 }
                                }
                            }

                            MiniToggle {
                                label: "Aktiv"
                                checked: Monitors.eff(win.selected, "enabled", !(win.selectedLive?.disabled ?? true))
                                onToggled: Monitors.set(win.selected, "enabled", !checked)
                            }

                            MiniToggle {
                                label: "VRR (variabel)"
                                // vrr ist ein Int: -1 unset/global, 0 aus, 1 ein
                                checked: Monitors.eff(win.selected, "vrr", win.selectedLive?.vrr ?? -1) >= 1
                                onToggled: Monitors.set(win.selected, "vrr", !checked ? 1 : 0)
                            }
                        }
                    }
                }

                // ---- Aktionsleiste ----
                Row {
                    id: actions

                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        leftMargin: 26
                        rightMargin: 26
                        bottomMargin: 20
                    }
                    spacing: 10

                    component ActionButton: Rectangle {
                        id: btn

                        property string label
                        property string icon
                        property bool primary: false
                        property bool enabled: true
                        signal tapped()

                        height: 36
                        radius: 12
                        opacity: btn.enabled ? 1 : 0.4
                        color: btn.primary ? (btnHover.hovered ? Colors.shade(Colors.primary, 0.08) : Colors.primary)
                             : btnHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12)
                             : Colors.alpha(Colors.fgSurface, 0.06)
                        border.width: btn.primary ? 0 : 1
                        border.color: Colors.alpha(Colors.outline, 0.3)

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }

                        HoverHandler {
                            id: btnHover
                            enabled: btn.enabled
                        }

                        TapHandler {
                            enabled: btn.enabled
                            onTapped: btn.tapped()
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Item { width: 14; height: 1 }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: btn.icon
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 15
                                color: btn.primary ? Colors.fgPrimary : Colors.fgBackground
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: btn.label
                                font.family: Config.font
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                color: btn.primary ? Colors.fgPrimary : Colors.fgBackground
                            }

                            Item { width: 14; height: 1 }
                        }
                    }

                    ActionButton {
                        label: "Verwerfen"
                        icon: "undo"
                        enabled: Monitors.dirty && !Monitors.busy
                        onTapped: Monitors.revert()
                    }

                    ActionButton {
                        label: "Anwenden"
                        icon: "check"
                        primary: true
                        enabled: Monitors.loaded && !Monitors.busy
                        onTapped: Monitors.apply()
                    }

                    ActionButton {
                        label: "Speichern"
                        icon: "save"
                        enabled: Monitors.loaded && !Monitors.busy
                        onTapped: Monitors.persist()
                    }

                    // Statuszeile rechts
                    Item {
                        width: parent.width - statusText.implicitWidth - 120
                        height: 1

                        Text {
                            id: statusText

                            anchors {
                                right: parent.right
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: Monitors.status
                            font.family: Config.font
                            font.pixelSize: 11
                            color: Monitors.status.includes("fehlgeschlagen") ? Colors.error
                                 : Colors.alpha(Colors.fgSurfaceVariant, 0.85)
                        }
                    }
                }

                // Schliessen-Knopf oben rechts
                Rectangle {
                    anchors {
                        right: parent.right
                        top: parent.top
                        rightMargin: 20
                        topMargin: 18
                    }
                    width: 30
                    height: 30
                    radius: 15
                    color: closeHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12) : "transparent"

                    HoverHandler {
                        id: closeHover
                    }

                    TapHandler {
                        onTapped: MonitorState.close()
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16
                        color: Colors.fgSurfaceVariant
                    }
                }
            }
        }
    }
}
