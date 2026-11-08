pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.desktop

// Auswahl "Widget hinzufuegen" beim Bearbeiten der Desktop-Widgets.
// Geoeffnet ueber den Knopf "Widget" der Leiste (dann ueber ihr, Platz sucht
// Scenes.place) oder per Rechtsklick auf freie Flaeche (dann an der Stelle,
// das Widget kommt genau dorthin – Scenes.addAt). DesktopScreen setzt Lage
// und laedt sie nur, solange Scenes.adding.
//
// Kacheln je Typ (Symbol, Name; die Beschreibung aus Manifest `desc` zaehlt
// nur fuer die Suche), getrennt in die Grundausstattung des Plugins `desktop`
// und die Komponenten. Tippen filtert, Pfeile/Tab waehlen, Enter fuegt hinzu,
// Esc schliesst (geht an die Buehne weiter). Schon vorhandene Widgets tragen
// ihre Anzahl.
Rectangle {
    id: picker

    // Wohin hinzugefuegt wird: Scenes (Desktop) oder LockLayout
    // (Sperrbildschirm) – beide haben add/widgets/adding/addAt
    property var store: Scenes
    // Typen, die hier nicht angeboten werden
    property var exclude: []

    readonly property real tileW: 216
    readonly property real gap: 8
    readonly property real pad: 16
    readonly property int columns: 3

    // Maus ueber der Auswahl: Widgets darunter sperren (WidgetHost.blocked)
    readonly property bool hovered: pickerHover.hovered
    readonly property bool here: picker.store.addAt !== null

    property string query: ""
    property int current: 0

    // [{ type, title, desc, icon, plugin, builtin }] – Grundausstattung
    // zuerst, dann nach Name
    readonly property var entries: {
        const out = [];
        for (const t of DesktopWidgets.typeNames) {
            const i = DesktopWidgets.info(t);
            if (!i || picker.exclude.includes(t))
                continue;
            out.push({
                type: t,
                title: i.title ?? t,
                desc: i.desc ?? "",
                icon: i.icon ?? "widgets",
                plugin: i.pluginName ?? "",
                builtin: i.pluginId === "desktop"
            });
        }
        out.sort((a, b) => (b.builtin - a.builtin) || a.title.localeCompare(b.title));
        return out;
    }

    readonly property var shown: {
        const q = picker.query.trim().toLowerCase();
        if (q === "")
            return picker.entries;
        // Deutscher Text und Uebersetzung: die Suche trifft in beiden Sprachen
        return picker.entries.filter(e => (e.title + " " + e.desc + " " + I18n.tr(e.title) + " " + I18n.tr(e.desc) + " " + e.plugin + " " + e.type).toLowerCase().includes(q));
    }
    readonly property var builtins: picker.shown.filter(e => e.builtin)
    readonly property var components: picker.shown.filter(e => !e.builtin)

    // Wie oft jeder Typ schon in der Szene steht
    readonly property var counts: {
        const out = {};
        for (const w of picker.store.widgets)
            out[w.type] = (out[w.type] ?? 0) + 1;
        return out;
    }

    onQueryChanged: picker.current = 0

    // Erst nach dem Klick hinzufuegen: Qt 6 reicht denselben Klick danach
    // noch an den Hintergrund weiter – waere die Auswahl dann schon zu,
    // galte er als Klick ins Leere und hoebe die Auswahl des neuen Widgets
    // gleich wieder auf
    function pick(type: string): void {
        Qt.callLater(() => picker.store.add(type));
    }

    function move(delta: int): void {
        const n = picker.shown.length;
        if (n > 0)
            picker.current = (picker.current + delta + n) % n;
    }

    implicitWidth: picker.columns * picker.tileW + (picker.columns - 1) * picker.gap + picker.pad * 2
    implicitHeight: body.implicitHeight + picker.pad * 2
    width: implicitWidth
    height: implicitHeight
    radius: 20
    color: Colors.alpha(Colors.background, 0.96)
    border.width: 1
    border.color: Colors.alpha(Colors.outline, 0.5)

    HoverHandler {
        id: pickerHover
    }

    // Klicks bleiben hier (DesktopScreen wertet die Flaeche zusaetzlich aus,
    // weil Qt 6 den Druck trotzdem an die Handler darunter weiterreicht)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    component Section: Text {
        color: Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: 10
        font.weight: Font.DemiBold
    }

    component Tile: Rectangle {
        id: tile

        required property var modelData
        readonly property int index: picker.shown.indexOf(tile.modelData)
        readonly property bool current: tile.index === picker.current
        readonly property int count: picker.counts[tile.modelData.type] ?? 0

        width: picker.tileW
        height: 52
        radius: 14
        color: tileHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12)
             : tile.current ? Colors.alpha(Colors.primary, 0.12)
             : Colors.alpha(Colors.fgSurface, 0.05)
        border.width: tile.current ? 1.5 : 0
        border.color: Colors.primary

        Behavior on color {
            ColorAnimation { duration: 120 }
        }

        Rectangle {
            id: badge

            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 18
            color: Colors.alpha(Colors.primary, tile.current || tileHover.hovered ? 0.22 : 0.14)

            Text {
                anchors.centerIn: parent
                text: tile.modelData.icon
                color: Colors.primary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 20
                font.variableAxes: ({ FILL: 1 })
            }
        }

        Text {
            anchors {
                left: badge.right
                leftMargin: 10
                right: parent.right
                rightMargin: tile.count > 0 ? 34 : 12
                verticalCenter: parent.verticalCenter
            }
            text: I18n.tr(tile.modelData.title)
            color: Colors.fgBackground
            font.family: Config.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        // Schon in der Szene
        Rectangle {
            visible: tile.count > 0
            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            width: countText.implicitWidth + 10
            height: 16
            radius: 8
            color: Colors.alpha(Colors.fgSurface, 0.1)

            Text {
                id: countText

                anchors.centerIn: parent
                text: tile.count + "×"
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }

        HoverHandler {
            id: tileHover

            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered) picker.current = tile.index
        }

        TapHandler {
            onTapped: picker.pick(tile.modelData.type)
        }
    }

    Column {
        id: body

        x: picker.pad
        y: picker.pad
        width: picker.width - picker.pad * 2
        spacing: 10

        // ---- Kopf ----
        Item {
            width: parent.width
            height: 28

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: picker.here ? "add_location_alt" : "add_circle"
                    color: Colors.primary
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 20
                    font.variableAxes: ({ FILL: 1 })
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: picker.here ? I18n.tr("Widget hier einfügen") : I18n.tr("Widget hinzufügen")
                    color: Colors.fgBackground
                    font.family: Config.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }

            EditChip {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                icon: "close"
                onClicked: picker.store.adding = false
            }
        }

        // ---- Suche ----
        Rectangle {
            width: parent.width
            height: 34
            radius: 11
            color: Colors.alpha(Colors.fgSurface, input.activeFocus ? 0.09 : 0.06)
            border.width: 1
            border.color: input.activeFocus ? Colors.alpha(Colors.primary, 0.5) : "transparent"

            Text {
                id: searchIcon

                anchors {
                    left: parent.left
                    leftMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                text: "search"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16
            }

            TextInput {
                id: input

                anchors {
                    left: searchIcon.right
                    leftMargin: 8
                    right: parent.right
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                color: Colors.fgSurface
                selectionColor: Colors.alpha(Colors.primary, 0.35)
                font.family: Config.font
                font.pixelSize: 12
                clip: true
                focus: true
                onTextEdited: picker.query = text
                onAccepted: {
                    const e = picker.shown[picker.current];
                    if (e)
                        picker.pick(e.type);
                }

                // Pfeile/Tab waehlen die Kachel; links/rechts nur bei leerem
                // Feld (sonst bewegen sie den Cursor im Text). Esc wird nicht
                // angenommen und schliesst ueber die Buehne.
                Keys.onPressed: event => {
                    const empty = input.text === "";
                    if (event.key === Qt.Key_Down)
                        picker.move(picker.columns);
                    else if (event.key === Qt.Key_Up)
                        picker.move(-picker.columns);
                    else if (event.key === Qt.Key_Tab)
                        picker.move(1);
                    else if (event.key === Qt.Key_Backtab)
                        picker.move(-1);
                    else if (empty && event.key === Qt.Key_Right)
                        picker.move(1);
                    else if (empty && event.key === Qt.Key_Left)
                        picker.move(-1);
                    else
                        return;
                    event.accepted = true;
                }

                Text {
                    anchors.fill: parent
                    visible: input.text === ""
                    text: I18n.tr("Suchen")
                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                    font: input.font
                    verticalAlignment: Text.AlignVCenter
                }

                Component.onCompleted: input.forceActiveFocus()
            }
        }

        // ---- Grundausstattung ----
        Section {
            visible: picker.builtins.length > 0
            text: I18n.tr("Grundausstattung")
        }

        Flow {
            width: parent.width
            visible: picker.builtins.length > 0
            spacing: picker.gap

            Repeater {
                model: picker.builtins

                Tile {}
            }
        }

        // ---- Komponenten ----
        Section {
            visible: picker.components.length > 0
            text: I18n.tr("Komponenten")
        }

        Flow {
            width: parent.width
            visible: picker.components.length > 0
            spacing: picker.gap

            Repeater {
                model: picker.components

                Tile {}
            }
        }

        Text {
            visible: picker.shown.length === 0
            width: parent.width
            topPadding: 6
            bottomPadding: 6
            horizontalAlignment: Text.AlignHCenter
            text: I18n.tr("Kein Widget passt zu „%1“").arg(picker.query)
            color: Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 11
        }
    }
}
