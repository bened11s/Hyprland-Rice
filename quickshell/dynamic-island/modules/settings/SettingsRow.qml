pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.config
import qs.modules.services.plugins
import qs.modules.widgets

import qs

// Eine Zeile im Einstellungs-Fenster (die Karte drumherum und ihren Titel
// zeichnet SettingsCard). Was fuer ein Bedienelement erscheint, entscheidet
// der Typ des Werts in der Datei plus die Angaben in Config.meta:
//
//   Wahrheitswert                 Schalter
//   String mit `options`          aufklappbare Auswahl (Chips)
//   Zahl mit `min`/`max`          Schieberegler (Mausrad geht auch)
//   alles andere                  steht nur da
//
// Dazu: ein Zuruecksetzen-Knopf, sobald der Wert von der Vorgabe abweicht,
// und eine gedimmte Zeile, wenn ihre Voraussetzung (meta.requires) fehlt.
//
// Gelesen und geschrieben wird ueber die Plugins-Bruecke (get/set/reset/
// isDefault/satisfied mit derselben Signatur wie Config): Gruppen von
// Plugins ("plugin:<id>") landen in plugins.json, alle anderen reicht sie
// an Config weiter – die Zeile muss den Unterschied nicht kennen.
Item {
    id: row

    // { id, section, key, value, title, desc, options, min, max, step, unit, requires }
    required property var entry

    readonly property bool isBool: typeof row.entry?.value === "boolean"
    readonly property bool isNumber: typeof row.entry?.value === "number"
                                     && row.entry?.min !== undefined && row.entry?.max !== undefined
    readonly property bool isChoice: !row.isBool && !row.isNumber && Array.isArray(row.entry?.options)
    // Eigener Editor statt Bedienelement (meta.editor), z.B. der Kachel-Aufbau
    readonly property bool isEditor: (row.entry?.editor ?? "") !== ""
    // Verweis auf eine Plugin-Seite (SettingsCard haengt sie als Zeile an):
    // die ganze Zeile oeffnet die Seite
    readonly property bool isLink: (row.entry?.link ?? "") !== ""
    // Schrift-Auswahl: jede Option in ihrer eigenen Schrift zeigen und nur
    // anbieten, was auch installiert ist
    readonly property bool isFont: row.isChoice && String(row.entry?.key ?? "").toLowerCase().includes("font")
    readonly property bool interactive: row.isBool || row.isChoice || row.isNumber || row.isLink

    // Voraussetzung erfuellt? Sonst ist die Zeile gedimmt und gesperrt.
    readonly property bool available: Plugins.satisfied(row.entry?.requires)
    readonly property string requirementLabel: {
        const req = row.entry?.requires;
        if (!req)
            return "";
        const id = typeof req === "string" ? req : Object.keys(req)[0];
        const title = Plugins.metaFor(id)?.title ?? id;
        return typeof req === "string" ? I18n.tr("Braucht „%1“").arg(I18n.tr(title))
                                       : I18n.tr("Braucht „%1“ = %2").arg(I18n.tr(title)).arg(row.optionLabel(req[id]));
    }

    // Anzeigename einer Option: meta.labels, sonst der Wert selbst –
    // uebersetzt, Schriftnamen bleiben wie sie sind
    function optionLabel(value: var): string {
        const v = String(value ?? "");
        const label = row.entry?.labels?.[v];
        if (label !== undefined)
            return label;
        return row.isChoice && !row.isFont ? I18n.tr(v) : v;
    }
    readonly property bool changed: !row.isLink && !Plugins.isDefault(row.entry?.section ?? "", row.entry?.key ?? "")

    readonly property var choices: {
        if (!row.isChoice)
            return [];
        const installed = row.isFont ? Qt.fontFamilies() : null;
        const list = row.entry.options.filter(o => !installed || installed.includes(o));
        // Von Hand eingetragener Wert, der nicht in der Liste steht: trotzdem zeigen
        const current = String(row.entry.value ?? "");
        if (current !== "" && !list.includes(current))
            list.unshift(current);
        return list;
    }
    property bool expanded: false

    // ---- Zahlen ----
    readonly property real min: Number(row.entry?.min ?? 0)
    readonly property real max: Number(row.entry?.max ?? 1)
    readonly property real step: Number(row.entry?.step ?? 1)
    readonly property int decimals: {
        const s = String(row.step);
        return s.includes(".") ? s.split(".")[1].length : 0;
    }
    readonly property real fraction: row.max > row.min
        ? Math.max(0, Math.min(1, (Number(row.entry?.value ?? row.min) - row.min) / (row.max - row.min)))
        : 0

    function formatNumber(v: real): string {
        return v.toFixed(row.decimals) + (row.entry?.unit ? ` ${row.entry.unit}` : "");
    }

    function snap(v: real): real {
        const stepped = Math.round((v - row.min) / row.step) * row.step + row.min;
        return Number(Math.max(row.min, Math.min(row.max, stepped)).toFixed(row.decimals));
    }

    function setNumber(v: real): void {
        const next = row.snap(v);
        if (next !== Number(row.entry.value))
            Plugins.set(row.entry.section, row.entry.key, next);
    }

    // Zweite Zeile unter dem Titel: Beschreibung aus Config.meta oder die
    // fehlende Voraussetzung; ohne sie ist die Zeile niedriger
    readonly property string subtitle: !row.available && row.requirementLabel !== ""
                                       ? row.requirementLabel
                                       : (row.entry?.desc ?? "")
    readonly property real lineHeight: row.subtitle !== "" ? 52 : 44

    // Breite des Bedienelements je nach Zeilenbreite: der Schieberegler
    // waechst von 110 auf 220 px mit, ein Auswahlwert wird abgeschnitten,
    // bevor er dem Titel seine 160 px nimmt
    readonly property real sliderWidth: Math.max(110, Math.min(220, row.width - 300))
    readonly property real valueCap: Math.max(72, row.width - 28 - 160 - 10 - 26 - 24)

    implicitHeight: row.lineHeight
                    + (row.expanded ? choiceFlow.implicitHeight + 12 : 0)
                    + (row.isEditor ? editorLoader.implicitHeight + 14 : 0)

    Behavior on implicitHeight {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        radius: 12
        color: hover.hovered && row.available ? Colors.alpha(Colors.fgSurface, 0.05) : "transparent"
        opacity: row.available ? 1 : 0.45
        clip: true

        Behavior on color {
            ColorAnimation { duration: 120 }
        }
        Behavior on opacity {
            NumberAnimation { duration: 160 }
        }

        HoverHandler {
            id: hover

            cursorShape: row.interactive && row.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        // Die eigentliche Zeile; bei einer Auswahl haengt die Liste darunter
        Item {
            id: line

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: row.lineHeight

            TapHandler {
                enabled: (row.isBool || row.isChoice || row.isLink) && row.available
                onTapped: {
                    if (row.isLink)
                        SettingsState.openPage(row.entry.link, {});
                    else if (row.isBool)
                        Plugins.set(row.entry.section, row.entry.key, !row.entry.value);
                    else
                        row.expanded = !row.expanded;
                }
            }

            // Mausrad auf einer Zahl: einen Schritt rauf oder runter
            WheelHandler {
                enabled: row.isNumber && row.available
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                property real acc: 0

                onWheel: event => {
                    acc += event.angleDelta.y;
                    if (Math.abs(acc) >= 120) {
                        row.setNumber(Number(row.entry.value) + (acc > 0 ? row.step : -row.step));
                        acc = 0;
                    }
                    event.accepted = true;
                }
            }

            Column {
                anchors {
                    left: parent.left
                    leftMargin: 14
                    right: resetButton.left
                    rightMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2

                Row {
                    width: parent.width
                    spacing: 6

                    Text {
                        font.family: Config.font
                        width: Math.min(implicitWidth, parent.width - (row.changed ? 11 : 0))
                        text: row.entry?.title ?? ""
                        color: Colors.fgBackground
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    // Punkt: Wert weicht von der Vorgabe ab
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 5
                        radius: 2.5
                        color: Colors.primary
                        visible: row.changed
                    }
                }

                Text {
                    font.family: Config.font
                    width: parent.width
                    visible: text !== ""
                    text: row.subtitle
                    color: !row.available ? Colors.secondary : Colors.fgSurfaceVariant
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            // Zuruecksetzen – nur sichtbar, wenn der Wert abweicht und die
            // Zeile gehovert ist
            Item {
                id: resetButton

                anchors {
                    right: control.left
                    rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                width: row.changed ? 26 : 0
                height: 26
                opacity: row.changed && hover.hovered ? 1 : 0
                visible: width > 0

                Behavior on width {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Fade on opacity {}

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: resetHover.hovered ? Colors.alpha(Colors.fgSurface, 0.14) : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "restart_alt"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 15
                    }
                }

                HoverHandler {
                    id: resetHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: Plugins.reset(row.entry.section, row.entry.key)
                }
            }

            // ---- Das Bedienelement rechts ----
            Item {
                id: control

                anchors {
                    right: parent.right
                    rightMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                width: row.isBool ? 40 : row.isNumber ? numberControl.width : row.isEditor ? 0 : row.isLink ? 20 : valueRow.width
                height: 28

                Text {
                    anchors.centerIn: parent
                    visible: row.isLink
                    text: "chevron_right"
                    color: Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 20
                }

                // Schalter fuer Wahrheitswerte
                Rectangle {
                    anchors.centerIn: parent
                    width: 40
                    height: 22
                    radius: height / 2
                    visible: row.isBool
                    color: row.entry?.value ? Colors.primary : Colors.alpha(Colors.fgSurface, 0.18)

                    Behavior on color {
                        ColorAnimation { duration: 140 }
                    }

                    Rectangle {
                        width: 16
                        height: 16
                        radius: 8
                        y: 3
                        x: row.entry?.value ? parent.width - width - 3 : 3
                        color: row.entry?.value ? Colors.fgPrimary : Colors.fgSurfaceVariant

                        Morph on x {}
                    }
                }

                // Schieberegler fuer Zahlen: Wert links, Spur rechts
                Row {
                    id: numberControl

                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.isNumber
                    spacing: 10

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Config.font
                        width: 46
                        horizontalAlignment: Text.AlignRight
                        text: row.isNumber ? row.formatNumber(Number(row.entry.value)) : ""
                        color: Colors.fgSurface
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Item {
                        id: slider

                        anchors.verticalCenter: parent.verticalCenter
                        width: row.sliderWidth
                        height: 28

                        readonly property real handleSize: 14
                        readonly property real trackInset: handleSize / 2
                        readonly property real usable: width - handleSize

                        function valueAt(x: real): real {
                            const f = Math.max(0, Math.min(1, (x - slider.trackInset) / slider.usable));
                            return row.min + f * (row.max - row.min);
                        }

                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                leftMargin: slider.trackInset
                                rightMargin: slider.trackInset
                                verticalCenter: parent.verticalCenter
                            }
                            height: 4
                            radius: 2
                            color: Colors.alpha(Colors.fgSurface, 0.16)

                            Rectangle {
                                anchors {
                                    left: parent.left
                                    top: parent.top
                                    bottom: parent.bottom
                                }
                                width: parent.width * row.fraction
                                radius: 2
                                color: Colors.primary

                                Behavior on width {
                                    enabled: !sliderArea.pressed
                                    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Rectangle {
                            width: slider.handleSize
                            height: slider.handleSize
                            radius: height / 2
                            x: slider.usable * row.fraction
                            anchors.verticalCenter: parent.verticalCenter
                            color: Colors.fgBackground
                            scale: sliderArea.pressed ? 1.25 : sliderArea.containsMouse ? 1.1 : 1

                            Behavior on x {
                                enabled: !sliderArea.pressed
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                        }

                        MouseArea {
                            id: sliderArea

                            anchors.fill: parent
                            enabled: row.available
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true

                            onPressed: mouse => row.setNumber(slider.valueAt(mouse.x))
                            onPositionChanged: mouse => {
                                if (pressed)
                                    row.setNumber(slider.valueAt(mouse.x));
                            }
                        }
                    }
                }

                // Aktueller Wert (bei einer Auswahl mit Pfeil zum Aufklappen)
                Row {
                    id: valueRow

                    anchors.verticalCenter: parent.verticalCenter
                    // Ein Editor zeigt den Rohwert nicht – der steht in ihm selbst
                    visible: !row.isBool && !row.isNumber && !row.isEditor && !row.isLink
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, row.valueCap)
                        text: row.optionLabel(row.entry?.value)
                        color: Colors.fgSurfaceVariant
                        font.family: row.isFont ? String(row.entry?.value ?? "") : Config.font
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.isChoice
                        text: "expand_more"
                        rotation: row.expanded ? 180 : 0
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16

                        Behavior on rotation {
                            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }
        }

        // Eigener Editor unter der Zeile (meta.editor)
        Loader {
            id: editorLoader

            anchors {
                left: parent.left
                right: parent.right
                top: line.bottom
                leftMargin: 14
                rightMargin: 14
            }
            active: row.isEditor
            sourceComponent: row.entry?.editor === "quick" ? quickEditor
                           : row.entry?.editor === "desktop" ? desktopEditor
                           : row.entry?.editor === "lock" ? lockEditor
                           : row.entry?.editor === "sounds" ? soundsEditor
                           : null
        }

        Component {
            id: quickEditor

            QuickTilesEditor {}
        }

        Component {
            id: lockEditor

            LockLayoutEditor {}
        }

        Component {
            id: soundsEditor

            SoundsEditor {}
        }

        Component {
            id: desktopEditor

            DesktopSceneEditor {}
        }

        // Die Optionen einer Auswahl als Chips
        Flow {
            id: choiceFlow

            anchors {
                left: parent.left
                right: parent.right
                top: line.bottom
                leftMargin: 14
                rightMargin: 14
            }
            visible: row.isChoice
            opacity: row.expanded ? 1 : 0
            spacing: 6

            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }

            Repeater {
                model: row.choices

                Rectangle {
                    id: chip

                    required property string modelData
                    readonly property bool selected: chip.modelData === String(row.entry?.value ?? "")

                    readonly property bool previewed: (row.entry?.preview ?? "") !== ""

                    width: chip.previewed ? Math.max(76, chipLabel.implicitWidth + 16) : chipLabel.implicitWidth + 24
                    height: chip.previewed ? 58 : 28
                    radius: chip.previewed ? 12 : height / 2
                    color: chip.selected ? Colors.primary
                         : chipHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12)
                         : Colors.alpha(Colors.fgSurface, 0.06)

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    // Vorschau der Variante (Uhr, Visualiser, Workspaces)
                    Loader {
                        active: chip.previewed
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 6

                        sourceComponent: StylePreview {
                            kind: row.entry.preview
                            style: chip.modelData
                            color: chip.selected ? Colors.fgPrimary : Colors.fgSurface
                            accent: chip.selected ? Colors.fgPrimary : Colors.primary
                        }
                    }

                    Text {
                        id: chipLabel

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: chip.previewed ? undefined : parent.verticalCenter
                        anchors.bottom: chip.previewed ? parent.bottom : undefined
                        anchors.bottomMargin: 5
                        font.pixelSize: chip.previewed ? 9 : 11
                        text: row.optionLabel(chip.modelData)
                        color: chip.selected ? Colors.fgPrimary : Colors.fgSurface
                        font.family: row.isFont ? chip.modelData : Config.font
                    }

                    HoverHandler {
                        id: chipHover

                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        enabled: row.available
                        onTapped: Plugins.set(row.entry.section, row.entry.key, chip.modelData)
                    }
                }
            }
        }
    }
}
