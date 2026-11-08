pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import "KeyLayout.js" as Layout

// Tastatur-Vorschau: ein Gehaeuse in voller Groesse (ISO-QWERTZ mit
// Ziffernblock) mit Platte, oben links ein Display (Ebene, gehoverter/
// gewaehlter Befehl), oben rechts ueber dem Ziffernblock Medienknoepfe und
// Lautstaerke-Walze; daneben (oder bei wenig Platz darunter) eine Maus fuer
// Maus-Binds.
//
// `mask` ist die Modifier-Maske, deren Belegung die Tasten zeigen; Klick auf
// eine Modifier-Taste schaltet ihr Bit (modifierToggled). `index` kommt vom
// Editor: Canon "64:q" -> { title, group, disabled, changed, source, unnamed,
// keys } – eine Map fuer alle Ebenen, jede Taste schlaegt einmal nach.
// Zweitnamen (AltGr-Zeichen, Ziffernblock ohne Num) landen auf ihrer
// physischen Taste (KeyLayout.ALIAS).
//
// Tooltips: ein einziges Popover im Overlay ueber allem (hoverAt), nie von
// Nachbartasten verdeckt, am Rand nach innen geschoben.
Item {
    id: board

    property int mask: 64
    property var index: ({})
    // Tasten des gewaehlten Befehls: { q: true, super_l: true }
    property var litKeys: ({})
    // Freie Tasten sind anklickbar ("Auf Tastatur wählen")
    property bool pick: false
    property bool interactive: true
    property real maxUnit: 56
    // Gewaehlter Befehl fuers Display, wenn nichts gehovert ist
    property string statusTitle: ""
    property var statusKeys: []

    signal keyClicked(string id)
    signal modifierToggled(int bit)
    // Rechtsklick auf eine belegte Taste/Knopf (Kontextmenue des Editors)
    signal keyContext(string id, Item item)
    // Ebene fuer den Tooltip (Overlay des Editors), sonst die Tastatur selbst
    property Item tipLayer: null

    // ---- Masse ----
    readonly property real bezelSide: 0.45
    readonly property real bezelTop: 1.35
    readonly property real bezelBottom: 0.45
    readonly property real padGap: 0.5
    readonly property real padUnits: 3
    readonly property real caseUnits: Layout.UNITS_WIDE + board.bezelSide * 2
    // Maus rechts daneben, solange die Tasten dann nicht zu klein werden
    readonly property bool padRight: board.width / (board.caseUnits + board.padGap + board.padUnits) >= 36
    readonly property real unit: Math.max(22, Math.min(board.maxUnit, board.width / (board.padRight ? board.caseUnits + board.padGap + board.padUnits : board.caseUnits)))
    readonly property real gap: Math.max(3, Math.round(board.unit * 0.08))
    readonly property real caseW: board.unit * board.caseUnits - board.gap
    readonly property real caseH: board.unit * (board.bezelTop + Layout.UNITS_HIGH + board.bezelBottom) - board.gap
    readonly property real totalW: board.caseW + (board.padRight ? board.unit * (board.padGap + board.padUnits) : 0)
    readonly property real x0: Math.round((board.width - board.totalW) / 2)

    implicitHeight: board.caseH
                    + (board.padRight ? 0 : pad.height + 10)
                    + (others.visible ? others.implicitHeight + 10 : 0)

    // ---- Farben ----
    readonly property color caseColor: Colors.surfaceContainer
    readonly property color plateColor: Qt.darker(Colors.surface, 1.3)

    // Belegung einer Taste auf der Ebene, Zweitnamen eingerechnet
    function infoFor(id: string): var {
        const direct = board.index[`${board.mask}:${id}`];
        if (direct)
            return direct;
        for (const alias of Layout.aliasesOf(id)) {
            const via = board.index[`${board.mask}:${alias}`];
            if (via)
                return Object.assign({ via: alias }, via);
        }
        return null;
    }

    // Lichtfarben: Config = Primaer; Plugin und Eigenes als klar andere
    // Farbtoene aus dem Farbkreis der Primaerfarbe (Secondary/Tertiary liegen
    // in vielen Schemata zu nah beieinander), Geaendert weiss, unbeschriebene
    // Binds neutral grau, abgeschaltete im Fehlerton
    function tone(shift: real): color {
        let h = Colors.primary.hslHue;
        if (h < 0)
            h = 0.15;
        return Qt.hsla((h + shift) % 1, 0.75, Appearance.darkText ? 0.36 : 0.66, 1);
    }
    readonly property color pluginLight: board.tone(0.38)
    readonly property color customLight: board.tone(0.72)
    readonly property color changedLight: Colors.fgSurface
    readonly property color unnamedLight: Colors.fgSurfaceVariant

    function lightOf(info: var): color {
        if (!info)
            return "transparent";
        if (info.disabled)
            return Colors.error;
        if (info.unnamed)
            return board.unnamedLight;
        if (info.changed)
            return board.changedLight;
        if (info.source === "plugin")
            return board.pluginLight;
        if (info.source === "custom" || info.source === "extra")
            return board.customLight;
        return Colors.primary;
    }

    function litOf(id: string): bool {
        if (board.litKeys[id] === true)
            return true;
        for (const alias of Layout.aliasesOf(id))
            if (board.litKeys[alias] === true)
                return true;
        return false;
    }

    // ---- Hover: Display und Tooltip ----
    property var hoverInfo: null
    property Item tipItem: null
    property string tipTitle: ""

    // Von den Tasten/Knoepfen: `title` ist der Rueckfall ohne Belegung
    // ("Hier ablegen", Name des Medienknopfs); leer = kein Tooltip
    function hoverAt(on: bool, item: Item, info: var, title: string): void {
        if (on) {
            board.tipItem = item;
            board.hoverInfo = info ?? null;
            board.tipTitle = title ?? "";
        } else if (board.tipItem === item) {
            board.tipItem = null;
            board.hoverInfo = null;
            board.tipTitle = "";
        }
    }

    function titleOf(info: var): string {
        if (!info)
            return "";
        if (info.unnamed)
            return I18n.tr("Belegt (ohne Beschreibung)");
        return `${I18n.tr(info.group)} › ${I18n.tr(info.title)}`;
    }

    // Gebundene Tasten ohne Platz (z.B. code:NN)
    readonly property var otherKeys: {
        const seen = {};
        const out = [];
        for (const canon in board.index) {
            const id = canon.slice(canon.indexOf(":") + 1);
            if (seen[id] || Layout.onBoard(id) || Layout.isMouse(id) || Layout.isMedia(id))
                continue;
            seen[id] = true;
            out.push(id);
        }
        return out.sort();
    }

    // Infos fuer Maus/Walze als Maps (einmal je Ebene)
    readonly property var mouseInfos: {
        const out = {};
        for (const id of Layout.MOUSE)
            out[id] = board.infoFor(id);
        return out;
    }
    readonly property var mouseLights: {
        const out = {};
        for (const id of Layout.MOUSE)
            out[id] = board.lightOf(board.mouseInfos[id]);
        return out;
    }
    readonly property var mouseLits: {
        const out = {};
        for (const id of Layout.MOUSE)
            out[id] = board.litOf(id);
        return out;
    }
    readonly property var rollerInfos: Layout.ROLLER.map(id => board.infoFor(id))

    // ================= Gehaeuse =================
    Rectangle {
        id: shell

        x: board.x0
        width: board.caseW
        height: board.caseH
        radius: board.unit * 0.42
        color: board.caseColor
        border.width: 1
        border.color: Colors.alpha(Colors.fgSurface, 0.07)

        // Kante oben: leichtes Highlight
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: parent.radius
                rightMargin: parent.radius
                topMargin: 1
            }
            height: 1
            color: Colors.alpha(Colors.fgSurface, 0.1)
        }

        // Platte
        Rectangle {
            x: board.unit * board.bezelSide - board.gap * 0.5 - board.unit * 0.1
            y: board.unit * board.bezelTop - board.gap * 0.5 - board.unit * 0.1
            width: board.unit * Layout.UNITS_WIDE - board.gap + board.unit * 0.2
            height: board.unit * Layout.UNITS_HIGH - board.gap + board.unit * 0.2
            radius: board.unit * 0.22
            color: board.plateColor
            border.width: 1
            border.color: Colors.alpha(Colors.background, 0.6)
        }

        // ---- Display (oben links) ----
        Rectangle {
            id: display

            x: board.unit * board.bezelSide
            y: board.unit * 0.3
            width: board.unit * 6.6
            height: board.unit * 0.8
            radius: board.unit * 0.14
            color: board.plateColor
            border.width: 1
            border.color: Colors.alpha(Colors.background, 0.7)
            clip: true

            readonly property string line: board.hoverInfo ? board.titleOf(board.hoverInfo) : board.statusTitle
            readonly property var lineKeys: board.hoverInfo ? (board.hoverInfo.keys ?? []) : board.statusKeys
            readonly property real inner: width - board.unit * 0.4

            Column {
                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: board.unit * 0.2
                    rightMargin: board.unit * 0.2
                    verticalCenter: parent.verticalCenter
                }
                spacing: Math.max(1, board.unit * 0.04)

                // Ebene
                Row {
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Ebene")
                        color: Colors.alpha(Colors.primary, 0.6)
                        font.family: Config.font
                        font.pixelSize: Math.max(8, Math.round(board.unit * 0.17))
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1
                        rightPadding: 4
                    }

                    Repeater {
                        model: Layout.modLabels(board.mask)

                        Text {
                            required property string modelData
                            required property int index

                            anchors.verticalCenter: parent.verticalCenter
                            text: (index > 0 ? "+ " : "") + I18n.tr(modelData)
                            color: Colors.primary
                            font.family: Config.font
                            font.pixelSize: Math.max(9, Math.round(board.unit * 0.19))
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: board.mask === 0
                        text: I18n.tr("ohne Modifier")
                        color: Colors.primary
                        font.family: Config.font
                        font.pixelSize: Math.max(9, Math.round(board.unit * 0.19))
                        font.weight: Font.DemiBold
                    }
                }

                // Gehoverter / gewaehlter Befehl mit Kombination
                Row {
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(20, Math.min(implicitWidth, display.inner - (keysRow.visible ? keysRow.width + 6 : 0)))
                        text: display.line !== "" ? display.line : "—"
                        color: display.line !== "" ? Colors.fgSurface : Colors.alpha(Colors.fgSurfaceVariant, 0.5)
                        font.family: Config.font
                        font.pixelSize: Math.max(9, Math.round(board.unit * 0.19))
                        elide: Text.ElideRight
                    }

                    Row {
                        id: keysRow

                        anchors.verticalCenter: parent.verticalCenter
                        // Kappen nur, wenn sie neben den Text passen
                        visible: display.lineKeys.length > 0 && width < display.inner * 0.6
                        spacing: 2

                        Repeater {
                            model: display.lineKeys

                            Keycap {
                                required property string modelData

                                anchors.verticalCenter: parent?.verticalCenter
                                text: modelData
                                size: Math.max(12, Math.round(board.unit * 0.27))
                            }
                        }
                    }
                }
            }
        }

        // ---- Medien (oben rechts, ueber dem Ziffernblock) ----
        Row {
            id: media

            anchors {
                right: parent.right
                rightMargin: board.unit * board.bezelSide + board.gap
            }
            y: board.unit * 0.3 + (board.unit * 0.8 - board.unit * 0.56) / 2
            spacing: board.unit * 0.14

            Repeater {
                model: Layout.MEDIA

                MediaButton {
                    id: mb

                    required property var modelData

                    spec: mb.modelData
                    unit: board.unit
                    info: board.infoFor(mb.spec.id)
                    light: board.lightOf(mb.info)
                    lit: board.litOf(mb.spec.id)
                    pick: board.pick
                    interactive: board.interactive
                    onClicked: board.keyClicked(mb.spec.id)
                    onContextClicked: board.keyContext(mb.spec.id, mb)
                    onHoveredChanged: board.hoverAt(mb.hovered, mb, mb.info, I18n.tr(mb.spec.title))
                }
            }

            Item {
                width: board.unit * 0.1
                height: 1
            }

            VolumeRoller {
                id: roller

                anchors.verticalCenter: parent.verticalCenter
                unit: board.unit
                infos: board.rollerInfos
                lights: board.rollerInfos.map(i => board.lightOf(i))
                lits: Layout.ROLLER.map(id => board.litOf(id))
                pick: board.pick
                interactive: board.interactive
                onClicked: id => board.keyClicked(id)
                onContextClicked: id => board.keyContext(id, roller)
                onHoverSideChanged: board.hoverAt(hoverSide >= 0, roller, hoverSide >= 0 ? board.rollerInfos[hoverSide] : null,
                                                  I18n.tr(hoverSide === 0 ? "Leiser" : "Lauter"))
            }
        }

        // ---- Tasten ----
        Item {
            id: keys

            x: board.unit * board.bezelSide
            y: board.unit * board.bezelTop
            width: board.unit * Layout.UNITS_WIDE
            height: board.unit * Layout.UNITS_HIGH

            Repeater {
                model: Layout.keys()

                KeyboardKey {
                    id: k

                    required property var modelData

                    spec: k.modelData
                    unit: board.unit
                    gap: board.gap
                    info: board.infoFor(k.spec.id)
                    light: board.lightOf(k.info)
                    lit: board.litOf(k.spec.id)
                    pressed: k.spec.mod !== 0 && (board.mask & k.spec.mod) !== 0
                    pick: board.pick
                    interactive: board.interactive
                    onHoveredChanged: board.hoverAt(k.hovered, k, k.info, k.target ? I18n.tr("Hier ablegen") : "")
                    onContextClicked: board.keyContext(k.spec.id, k)
                    // Modifier schalten immer die Ebene – auch wenn auf ihnen
                    // etwas liegt (Super allein = App-Menue); den Befehl dazu
                    // erreicht man ueber die Liste
                    onClicked: {
                        if (k.spec.mod !== 0)
                            board.modifierToggled(k.spec.mod);
                        else
                            board.keyClicked(k.spec.id);
                    }
                }
            }
        }
    }

    // ================= Mauspad =================
    Rectangle {
        id: pad

        // Rechts: buendig mit der Gehaeuse-Unterkante; sonst unter dem Gehaeuse rechts
        x: board.padRight ? shell.x + shell.width + board.unit * board.padGap : shell.x + shell.width - width
        y: board.padRight ? board.caseH - height : board.caseH + 10
        width: board.unit * board.padUnits
        height: board.unit * 4.2
        radius: board.unit * 0.3
        color: Qt.darker(board.caseColor, 1.12)
        border.width: 1
        border.color: Colors.alpha(Colors.fgSurface, 0.05)

        MouseView {
            id: mouseView

            anchors.centerIn: parent
            unit: board.unit
            infos: board.mouseInfos
            lights: board.mouseLights
            lits: board.mouseLits
            interactive: board.interactive
            onClicked: id => board.keyClicked(id)
            onContextClicked: id => board.keyContext(id, mouseView)
            onHoverIdChanged: board.hoverAt(hoverId !== "", mouseView, hoverId !== "" ? (board.mouseInfos[hoverId] ?? null) : null,
                                            I18n.tr(Layout.MOUSE_NAMES[hoverId] ?? ""))
        }
    }

    // ================= Sonstige gebundene Tasten =================
    Flow {
        id: others

        anchors {
            top: shell.bottom
            topMargin: 10
        }
        x: board.x0
        width: board.padRight ? board.totalW : Math.max(100, board.caseW - pad.width - 20)
        visible: board.otherKeys.length > 0
        spacing: 10

        Repeater {
            model: board.otherKeys

            Row {
                id: other

                required property string modelData
                readonly property var info: board.infoFor(other.modelData)

                spacing: 5

                Keycap {
                    anchors.verticalCenter: parent.verticalCenter
                    text: other.modelData
                    size: 18
                    accent: other.info !== null
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: other.info ? (other.info.unnamed ? I18n.tr("belegt") : I18n.tr(other.info.title)) : ""
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 10
                }

                TapHandler {
                    enabled: other.info !== null
                    onTapped: board.keyClicked(other.modelData)
                }
            }
        }
    }

    // ================= Tooltip-Overlay =================
    KeyTooltip {
        id: tip

        readonly property bool shown: board.tipItem !== null && board.interactive && (board.hoverInfo !== null || board.tipTitle !== "")
        // Position aus der Lage der Taste: ueber ihr, in den oberen Reihen
        // darunter; seitlich innerhalb der Tastatur
        readonly property Item host: board.tipLayer ? board.tipLayer : board
        readonly property rect at: board.tipItem ? board.tipItem.mapToItem(tip.host, 0, 0, board.tipItem.width, board.tipItem.height) : Qt.rect(0, 0, 0, 0)
        readonly property bool below: tip.at.y < tip.height + 10

        parent: tip.host
        z: 100
        visible: tip.shown
        x: Math.round(Math.max(0, Math.min(tip.host.width - width, tip.at.x + tip.at.width / 2 - width / 2)))
        y: Math.round(tip.below ? tip.at.y + tip.at.height + 6 : tip.at.y - height - 6)
        title: board.hoverInfo ? board.titleOf(board.hoverInfo) : board.tipTitle
        keys: board.hoverInfo?.keys ?? []
        hint: board.hoverInfo?.disabled ? I18n.tr("aus") : ""
    }
}
