pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.hypr

// Liste aller Befehle (HyprBinds.commands) mit Suche und Filter-Chips,
// gruppiert nach `group`. Ein Klick waehlt den Befehl (selected) – der
// Editor zeigt ihn rechts und auf der Tastatur.
Item {
    id: list

    property string selectedId: ""
    // "all" | "changed" | "disabled" | "custom" | "plugin"
    property string filter: "all"
    // Volltext je Befehl, einmal gebaut (Editor): { <id>: "…" }
    property var searchIndex: ({})
    property alias queryText: search.text
    // Formular "Eigenes Kürzel" offen (Chip am Ende der Filterzeile)
    property bool adding: false

    signal selected(string id)
    signal addToggled
    // Rechtsklick auf eine Zeile (Position in Listenkoordinaten)
    signal contextRequested(string id, real x, real y)
    readonly property alias addButton: addBtn

    readonly property string query: search.text.trim().toLowerCase()

    readonly property var filters: [
        { id: "all", label: "Alle" },
        { id: "changed", label: "Geändert" },
        { id: "disabled", label: "Aus" },
        { id: "custom", label: "Eigene" },
        { id: "plugin", label: "Plugins" }
    ]

    function passes(c: var): bool {
        switch (list.filter) {
        case "changed":
            return c.combos.some(x => x.changed || x.disabled || x.source === "extra");
        case "disabled":
            return c.combos.some(x => x.disabled);
        case "custom":
            return c.source === "custom";
        case "plugin":
            return c.source === "plugin";
        }
        return true;
    }

    // Flach: Gruppenkopf, dann seine Befehle. Nach Gruppe gesammelt (in der
    // Reihenfolge ihres ersten Auftretens) – Binds derselben Gruppe stehen in
    // der Config nicht immer beieinander
    readonly property var rows: {
        const q = list.query;
        const order = [];
        const byGroup = {};
        for (const c of HyprBinds.commands) {
            if (!list.passes(c))
                continue;
            if (q !== "" && !(list.searchIndex[c.id] ?? "").includes(q))
                continue;
            if (!byGroup[c.group]) {
                byGroup[c.group] = [];
                order.push(c.group);
            }
            byGroup[c.group].push(c);
        }
        const out = [];
        for (const group of order) {
            out.push({ header: true, name: group, id: "#" + group });
            for (const c of byGroup[group])
                out.push({ header: false, command: c, id: c.id });
        }
        return out;
    }

    readonly property int count: list.rows.filter(r => !r.header).length

    function scrollTo(id: string): void {
        const i = list.rows.findIndex(r => r.id === id);
        if (i >= 0)
            view.positionViewAtIndex(i, ListView.Contain);
    }

    KbField {
        id: search

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        icon: "search"
        placeholder: I18n.tr("Befehl, Gruppe oder Taste suchen")
    }

    Flow {
        id: chips

        anchors {
            top: search.bottom
            topMargin: 8
            left: parent.left
            right: parent.right
        }
        spacing: 4

        Repeater {
            model: list.filters

            KbChip {
                id: chip

                required property var modelData

                size: 24
                label: I18n.tr(chip.modelData.label)
                checked: list.filter === chip.modelData.id
                onClicked: list.filter = chip.modelData.id
            }
        }

        KbIconButton {
            id: addBtn

            size: 24
            icon: "add"
            hint: I18n.tr("Eigenes Kürzel anlegen")
            checked: list.adding
            onClicked: list.addToggled()
        }
    }

    Rectangle {
        id: frame

        anchors {
            top: chips.bottom
            topMargin: 8
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        radius: 12
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Colors.alpha(Colors.fgSurface, 0.06)
        clip: true

        ListView {
            id: view

            anchors {
                fill: parent
                leftMargin: 6
                rightMargin: 6
                topMargin: 8
                bottomMargin: 8
            }
            model: list.rows
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Nur per Rad (unten) – Ziehen gehoert dem Einstellungsfenster
            interactive: false
            spacing: 1
            // Treffer nicht hinter dem Rand verstecken, wenn die Liste kuerzer wird
            onContentHeightChanged: view.contentY = Math.max(0, Math.min(view.contentY, view.contentHeight - view.height))

            // Das Rad nur nehmen, wenn es hier etwas zu scrollen gibt – sonst
            // scrollt die Einstellungsseite weiter
            WheelHandler {
                enabled: view.contentHeight > view.height
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const angle = event.angleDelta.y + event.angleDelta.x;
                    const pixels = event.pixelDelta.y + event.pixelDelta.x;
                    const delta = angle !== 0 ? angle / 120 : pixels / 40;
                    const max = Math.max(0, view.contentHeight - view.height);
                    view.contentY = Math.max(0, Math.min(max, view.contentY - delta * 60));
                    event.accepted = true;
                }
            }

            delegate: Item {
                id: row

                required property var modelData

                readonly property bool header: row.modelData.header === true
                readonly property var command: row.modelData.command ?? null
                readonly property bool current: !row.header && row.command.id === list.selectedId
                readonly property bool off: !row.header && row.command.combos.length > 0 && row.command.combos.every(c => c.disabled)

                width: view.width
                height: row.header ? 28 : 30

                // Gruppenkopf
                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        bottom: parent.bottom
                        bottomMargin: 5
                    }
                    visible: row.header
                    text: row.header ? I18n.tr(row.modelData.name) : ""
                    color: Colors.primary
                    font.family: Config.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                // Befehl
                Rectangle {
                    anchors.fill: parent
                    visible: !row.header
                    radius: 8
                    color: row.current ? Colors.alpha(Colors.primary, 0.14)
                         : rowHover.hovered ? Colors.alpha(Colors.fgSurface, 0.06)
                         : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: Appearance.fadeDuration }
                    }

                    Rectangle {
                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        width: 3
                        height: parent.height - 10
                        radius: 1.5
                        color: Colors.primary
                        opacity: row.current ? 1 : 0
                    }

                    Text {
                        id: title

                        anchors {
                            left: parent.left
                            leftMargin: 12
                            right: caps.left
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        text: row.command ? I18n.tr(row.command.title) : ""
                        color: row.current ? Colors.fgSurface : row.off ? Colors.fgSurfaceVariant : Colors.fgSurface
                        opacity: row.off ? 0.55 : 1
                        font.family: Config.font
                        font.pixelSize: 12
                        font.weight: row.current ? Font.DemiBold : Font.Normal
                        font.strikeout: row.off
                        elide: Text.ElideRight
                    }

                    // Erste Kombination als Kappen, dazu Hinweise auf weitere/aus/Plugin
                    Row {
                        id: caps

                        anchors {
                            right: parent.right
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 3

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.command?.source === "plugin"
                            text: "extension"
                            color: Colors.alpha(Colors.secondary, 0.9)
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 13
                            rightPadding: 3
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.command?.source === "custom"
                            text: "person"
                            color: Colors.alpha(Colors.tertiary, 0.9)
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 13
                            rightPadding: 3
                        }

                        Repeater {
                            model: row.command ? (row.command.combos[0]?.keys ?? []) : []

                            Keycap {
                                required property string modelData

                                anchors.verticalCenter: parent?.verticalCenter
                                text: modelData
                                size: 18
                                accent: row.command?.combos[0]?.changed ?? false
                                dim: row.command?.combos[0]?.disabled ?? false
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: (row.command?.combos.length ?? 0) > 1
                            text: "+" + ((row.command?.combos.length ?? 1) - 1)
                            color: Colors.fgSurfaceVariant
                            font.family: Config.font
                            font.pixelSize: 10
                            leftPadding: 3
                        }
                    }

                    HoverHandler {
                        id: rowHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onTapped: (point, button) => {
                            if (button === Qt.RightButton) {
                                const p = row.mapToItem(list, point.position.x, point.position.y);
                                list.contextRequested(row.command.id, p.x, p.y);
                            } else
                                list.selected(row.command.id);
                        }
                    }
                }
            }
        }

        // Weiche Kanten oben und unten, damit angeschnittene Zeilen nicht hart enden
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 1
            }
            height: 14
            radius: 11
            visible: view.contentY > 0
            gradient: Gradient {
                GradientStop { position: 0; color: Colors.surfaceContainer }
                GradientStop { position: 1; color: Colors.alpha(Colors.surfaceContainer, 0) }
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 1
            }
            height: 14
            radius: 11
            visible: view.contentY < view.contentHeight - view.height - 1
            gradient: Gradient {
                GradientStop { position: 0; color: Colors.alpha(Colors.surfaceContainer, 0) }
                GradientStop { position: 1; color: Colors.surfaceContainer }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: list.rows.length === 0
            text: HyprBinds.loaded ? I18n.tr("Keine Treffer") : I18n.tr("Lese Tastenkürzel…")
            color: Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 12
        }
    }
}
