pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.services.config
import qs.modules.widgets

import qs

// Einstellungs-Fenster, mittig auf dem Bildschirm.
//
// Links eine Gruppenleiste (Leiste, Notch-Layout, Darstellung, …), rechts
// die Zeilen der gewaehlten Gruppe. Die Liste baut sich aus
// ~/.config/dynamic-island/shell.json: jeder Abschnitt wird eine Gruppe,
// jeder Schluessel eine Zeile. Neue Schluessel im Adapter
// (services/config/Config.qml) tauchen hier von selbst auf – Namen,
// Beschreibungen und Bedienelemente kommen aus Config.meta, fehlt ein
// Eintrag, steht der Schluessel selbst da.
//
// Die Suche geht ueber alle Gruppen, die Gruppenleiste ist dann aus.
//
// Bewusst keine Anker: eine Layer-Oberflaeche ohne Anker setzt der Compositor
// mittig – genau das, was hier gebraucht wird. Das Fenster ist etwas groesser
// als die Karte, damit deren Schatten Platz hat.
//
// Gebaut wird es erst beim Oeffnen und nur auf dem Ziel-Monitor (LazyLoader) –
// frueher lebte es je Monitor versteckt mit, samt Gruppenleiste und Zeilen.
LazyLoader {
    active: SettingsState.open && SettingsState.screen !== null

    PanelWindow {
        id: win

        readonly property ShellScreen modelData: SettingsState.screen

        // Suchtext; leert sich beim Oeffnen
        property string filter: ""
        // Gewaehlte Gruppe in der Leiste; "" = alle
        property string section: SettingsState.requestedSection || Config.sectionOrder[0] || ""
        readonly property bool searching: win.filter.trim() !== ""

        Connections {
            target: SettingsState
            function onRequestedSectionChanged(): void {
                if (SettingsState.requestedSection !== "") {
                    win.section = SettingsState.requestedSection;
                    win.filter = "";
                    search.text = "";
                }
            }
        }

        readonly property real inset: 28

        // Gruppen in Menue-Reihenfolge, unbekannte hinten dran
        readonly property var sections: {
            const raw = Config.raw;
            const isGroup = s => typeof raw[s] === "object" && raw[s] !== null;
            const known = Config.sectionOrder.filter(isGroup);
            const extra = Object.keys(raw).filter(s => !known.includes(s) && isGroup(s));
            return known.concat(extra);
        }

        function sectionTitle(s: string): string {
            return Config.sectionMeta[s] ?? s;
        }

        // Anzahl Zeilen je Gruppe (fuer die Leiste)
        function countIn(s: string): int {
            const values = Config.raw[s];
            return typeof values === "object" && values !== null ? Object.keys(values).length : 0;
        }

        screen: win.modelData
        visible: SettingsState.open && SettingsState.screen === win.modelData

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dynamic-island-settings"
        // Fuers Suchfeld. Exclusive, weil das Fenster ueber einen Klick in der
        // Leiste aufgeht – es gibt keinen Klick, der ihm den Fokus gaebe.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        implicitWidth: 880 + inset * 2
        implicitHeight: 580 + inset * 2

        onVisibleChanged: {
            if (visible) {
                win.filter = "";
                win.section = SettingsState.requestedSection || Config.sectionOrder[0] || "";
                SettingsState.requestedSection = "";
                search.text = "";
                search.forceActiveFocus();
            }
        }
        // Entsteht bereits sichtbar – dann kommt kein Wechsel-Signal
        Component.onCompleted: if (visible) Qt.callLater(win.visibleChanged)

        // ---- Die Karte ----
        Surface {
            id: card

            anchors {
                fill: parent
                margins: win.inset
            }
            maxRadius: 24

            // Kommt beim Oeffnen leicht herangewachsen
            scale: win.visible ? 1 : 0.96
            opacity: win.visible ? 1 : 0
            Morph on scale {}
            Fade on opacity {}

            // Escape schliesst – auch, wenn das Suchfeld den Fokus verloren hat
            Keys.onEscapePressed: SettingsState.close()

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

                // Trennlinie
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
                    text: "Einstellungen"
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
                    text: Colors.name
                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                    font.pixelSize: 10
                }

                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: title.bottom
                        topMargin: 34
                        leftMargin: 12
                        rightMargin: 12
                    }
                    spacing: 2

                    component SectionButton: Rectangle {
                        id: button

                        required property string key
                        required property string label
                        required property string icon
                        property int count: 0

                        readonly property bool current: !win.searching && win.section === button.key

                        width: parent.width
                        height: 38
                        radius: 12
                        color: button.current ? Colors.alpha(Colors.primary, 0.16)
                             : buttonHover.hovered ? Colors.alpha(Colors.fgSurface, 0.07)
                             : "transparent"
                        opacity: win.searching ? 0.5 : 1

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 160 }
                        }

                        Text {
                            id: buttonIcon

                            anchors {
                                left: parent.left
                                leftMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            text: button.icon
                            color: button.current ? Colors.primary : Colors.fgSurfaceVariant
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 17
                            font.variableAxes: ({ FILL: button.current ? 1 : 0 })

                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }
                        }

                        Text {
                            font.family: Config.font
                            anchors {
                                left: buttonIcon.right
                                leftMargin: 10
                                right: countLabel.left
                                rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            text: button.label
                            color: button.current ? Colors.fgBackground : Colors.fgSurface
                            font.pixelSize: 12
                            font.weight: button.current ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }

                        Text {
                            id: countLabel

                            font.family: Config.font
                            anchors {
                                right: parent.right
                                rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            visible: button.count > 0
                            text: button.count
                            color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                            font.pixelSize: 10
                        }

                        HoverHandler {
                            id: buttonHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: {
                                win.section = button.key;
                                if (win.searching) {
                                    search.text = "";
                                    win.filter = "";
                                }
                                list.contentY = 0;
                            }
                        }
                    }

                    SectionButton {
                        key: ""
                        label: "Alle"
                        icon: "tune"
                    }

                    Repeater {
                        model: win.sections

                        SectionButton {
                            required property string modelData

                            key: modelData
                            label: win.sectionTitle(modelData)
                            icon: Config.sectionIcons[modelData] ?? "folder_open"
                            count: win.countIn(modelData)
                        }
                    }
                }

                // ---- Fuss: Datei und Zuruecksetzen ----
                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        leftMargin: 12
                        rightMargin: 12
                        bottomMargin: 14
                    }
                    spacing: 2

                    component FootButton: Rectangle {
                        id: foot

                        required property string icon
                        required property string label
                        property color tint: Colors.fgSurfaceVariant
                        signal clicked()

                        width: parent.width
                        height: 32
                        radius: 10
                        color: footHover.hovered ? Colors.alpha(Colors.fgSurface, 0.07) : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: 120 }
                        }

                        Text {
                            id: footIcon

                            anchors {
                                left: parent.left
                                leftMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            text: foot.icon
                            color: foot.tint
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 15

                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }
                        }

                        Text {
                            font.family: Config.font
                            anchors {
                                left: footIcon.right
                                leftMargin: 10
                                right: parent.right
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: foot.label
                            color: foot.tint
                            font.pixelSize: 11
                            elide: Text.ElideRight

                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }
                        }

                        HoverHandler {
                            id: footHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: foot.clicked()
                        }
                    }

                    FootButton {
                        icon: "open_in_new"
                        label: "shell.json öffnen"
                        onClicked: {
                            Quickshell.execDetached(["xdg-open", Config.path]);
                            SettingsState.close();
                        }
                    }

                    // Zweistufig: erst "Alles zuruecksetzen", dann 3 s lang
                    // "Wirklich?" – ein Fehlklick setzt sonst alles platt
                    FootButton {
                        id: resetAll

                        property bool armed: false

                        icon: armed ? "check" : "settings_backup_restore"
                        label: armed ? "Wirklich alles zurücksetzen?" : "Alles zurücksetzen"
                        tint: armed ? Colors.error : Colors.fgSurfaceVariant
                        onClicked: {
                            if (resetAll.armed) {
                                Config.resetAll();
                                resetAll.armed = false;
                            } else {
                                resetAll.armed = true;
                                disarm.restart();
                            }
                        }

                        Timer {
                            id: disarm

                            interval: 3000
                            onTriggered: resetAll.armed = false
                        }
                    }
                }
            }

            // ================= Rechte Seite =================
            Item {
                id: content

                anchors {
                    left: sidebar.right
                    right: parent.right
                    top: parent.top
                    bottom: parent.bottom
                }

                // Kopf: Gruppentitel + Suche
                Text {
                    id: heading
                    font.family: Config.font

                    anchors {
                        left: parent.left
                        leftMargin: 24
                        verticalCenter: searchBox.verticalCenter
                    }
                    width: 160
                    text: win.searching ? "Suche"
                        : win.section === "" ? "Alle"
                        : win.sectionTitle(win.section)
                    color: Colors.fgBackground
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Rectangle {
                    id: searchBox

                    anchors {
                        left: heading.right
                        right: closeButton.left
                        top: parent.top
                        leftMargin: 12
                        rightMargin: 10
                        topMargin: 22
                    }
                    height: 38
                    radius: height / 2
                    color: Colors.alpha(Colors.fgSurface, search.activeFocus ? 0.09 : 0.06)
                    border.width: 1
                    border.color: search.activeFocus ? Colors.alpha(Colors.primary, 0.5) : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }
                    Behavior on border.color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        id: searchIcon

                        anchors {
                            left: parent.left
                            leftMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        text: "search"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 17
                    }

                    TextInput {
                        id: search
                        font.family: Config.font

                        anchors {
                            left: searchIcon.right
                            leftMargin: 10
                            right: clearSearch.left
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        onTextChanged: win.filter = text
                        color: Colors.fgSurface
                        font.pixelSize: 13
                        selectionColor: Colors.alpha(Colors.primary, 0.35)
                        clip: true

                        Keys.onEscapePressed: {
                            if (search.text !== "")
                                search.text = "";
                            else
                                SettingsState.close();
                        }

                        Text {
                            anchors.fill: parent
                            visible: search.text === ""
                            text: "Einstellung suchen…"
                            color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                            font: search.font
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // Suchtext leeren
                    Item {
                        id: clearSearch

                        anchors {
                            right: parent.right
                            rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        width: search.text !== "" ? 26 : 0
                        height: 26
                        opacity: search.text !== "" ? 1 : 0
                        visible: width > 0

                        Behavior on width {
                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                        }
                        Fade on opacity {}

                        Text {
                            anchors.centerIn: parent
                            text: "close"
                            color: Colors.fgSurfaceVariant
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 15
                        }

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: search.text = ""
                        }
                    }
                }

                Rectangle {
                    id: closeButton

                    anchors {
                        right: parent.right
                        rightMargin: 20
                        verticalCenter: searchBox.verticalCenter
                    }
                    width: 32
                    height: 32
                    radius: height / 2
                    color: closeHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12) : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 17
                    }

                    HoverHandler {
                        id: closeHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: SettingsState.close()
                    }
                }

                // ---- Die Liste, gebaut aus der Datei ----
                ListView {
                    id: list

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: searchBox.bottom
                        bottom: parent.bottom
                        leftMargin: 12
                        rightMargin: 12
                        topMargin: 12
                        bottomMargin: 16
                    }
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    // Nicht per Ziehen scrollen: sonst klaut die Liste den
                    // Drag-and-Drop-Editoren ihre Geste. Das Mausrad reicht.
                    interactive: false

                    model: ScriptModel {
                        values: {
                            const needle = win.filter.trim().toLowerCase();
                            const out = [];
                            // shell.json kommt alphabetisch zurueck (QJsonObject
                            // sortiert beim Schreiben) – die Reihenfolge im Menue
                            // gibt deshalb die meta-Tabelle vor, Unbekanntes hinten
                            const order = Object.keys(Config.meta);
                            const rank = id => {
                                const i = order.indexOf(id);
                                return i < 0 ? order.length : i;
                            };

                            for (const section of win.sections) {
                                if (needle === "" && win.section !== "" && section !== win.section)
                                    continue;

                                const values = Config.raw[section];
                                const keys = Object.keys(values).sort((a, b) =>
                                    rank(`${section}.${a}`) - rank(`${section}.${b}`) || a.localeCompare(b));
                                for (const key of keys) {
                                    const id = `${section}.${key}`;
                                    const meta = Config.meta[id] ?? null;
                                    const entry = {
                                        id,
                                        section,
                                        key,
                                        value: values[key],
                                        title: meta?.title ?? key,
                                        // Ohne Eintrag in der Tabelle: ehrlich sagen,
                                        // dass der Schluessel neu ist
                                        desc: meta?.desc ?? `Schlüssel "${key}" aus shell.json`,
                                        options: meta?.options ?? null,
                                        min: meta?.min,
                                        max: meta?.max,
                                        step: meta?.step,
                                        unit: meta?.unit ?? "",
                                        requires: meta?.requires ?? null,
                                        editor: meta?.editor ?? ""
                                    };

                                    if (needle === ""
                                        || entry.title.toLowerCase().includes(needle)
                                        || entry.desc.toLowerCase().includes(needle)
                                        || id.toLowerCase().includes(needle)
                                        || win.sectionTitle(section).toLowerCase().includes(needle))
                                        out.push(entry);
                                }
                            }
                            return out;
                        }
                    }

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                        onWheel: event => {
                            const angle = event.angleDelta.y + event.angleDelta.x;
                            const pixels = event.pixelDelta.y + event.pixelDelta.x;
                            const delta = angle !== 0 ? angle / 120 : pixels / 40;

                            const max = Math.max(0, list.contentHeight - list.height);
                            list.contentY = Math.max(0, Math.min(max, list.contentY - delta * 60));
                            event.accepted = true;
                        }
                    }

                    delegate: SettingsRow {
                        required property var modelData
                        required property int index

                        width: ListView.view.width
                        entry: modelData
                        // Gruppentitel nur, wenn mehrere Gruppen zu sehen sind
                        // (Suche oder "Alle"), und nur ueber der ersten Zeile.
                        // Optional-Zugriff: waehrend des Filterns sind Index und
                        // Liste kurz auseinander, dann gibt es den Vorgaenger nicht
                        section: (win.searching || win.section === "")
                                 && (index === 0 || list.model.values[index - 1]?.section !== modelData.section)
                                 ? modelData.section : ""
                    }

                    // Weiche Kante unten, solange noch Zeilen folgen
                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 24
                        visible: list.contentHeight - list.contentY - list.height > 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: Colors.alpha(Colors.background, 0) }
                            GradientStop { position: 1; color: Colors.background }
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        spacing: 6

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "search_off"
                            color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 28
                        }

                        Text {
                            font.family: Config.font
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Nichts gefunden"
                            color: Colors.fgSurfaceVariant
                            font.pixelSize: 12
                        }
                    }
                }

                // Zaehler unten rechts
                Text {
                    font.family: Config.font
                    anchors {
                        right: parent.right
                        rightMargin: 24
                        bottom: parent.bottom
                        bottomMargin: 10
                    }
                    text: win.searching ? `${list.count} Treffer` : ""
                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                    font.pixelSize: 10
                }
            }
        }
    }
}
