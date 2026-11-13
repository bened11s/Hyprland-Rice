pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.config
import qs.modules.services.theme
import qs.modules.settings

import qs

// Farbschema-Auswahl im Einstellungs-Fenster (Seite "@colors", hinter
// "Aussehen > Farben") – statt des Karussells im Launcher, damit aus den
// Einstellungen heraus nichts in der Notch aufgeht.
//
// Oben das dynamische Schema (Farben aus dem Wallpaper) mit seinen
// Stellschrauben, darunter die festen Schemata als Raster. Klick setzt.
Item {
    id: page

    // Suchtext aus dem Kopf des Fensters
    property string filter: ""

    readonly property var found: Themes.search(page.filter)
    readonly property var schemes: page.found.filter(e => e.name !== "dynamic")
    readonly property bool showDynamic: page.found.some(e => e.name === "dynamic")

    readonly property bool dynamicCurrent: Themes.currentName === "dynamic"
    // Flavour und Modus, mit denen das dynamische Schema gesetzt wird: die
    // laufenden, sonst Standard im Modus des laufenden Schemas
    readonly property string dynFlavour: page.dynamicCurrent && Themes.currentFlavour !== "" ? Themes.currentFlavour : "default"
    readonly property string dynMode: Themes.currentMode === "light" ? "light" : "dark"

    readonly property string currentLabel: {
        if (page.dynamicCurrent)
            return I18n.tr("Dynamisch");
        return Themes.entries.find(e => e.key === Themes.currentKey)?.label ?? Themes.currentName;
    }

    // Der Inhalt steht mittig, hoechstens 820 px breit
    readonly property real contentWidth: Math.min(820, page.width)

    readonly property int gap: 14
    readonly property int columns: Math.max(2, Math.floor((page.contentWidth + page.gap) / (150 + page.gap)))
    readonly property real cellWidth: Math.floor((page.contentWidth - (page.columns - 1) * page.gap) / page.columns)

    function applyDynamic(flavour: string, mode: string): void {
        Themes.apply({ name: "dynamic", flavour, mode });
    }

    Component.onCompleted: Themes.ensureLoaded()

    Flickable {
        id: flick

        anchors.fill: parent
        contentHeight: content.height
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        clip: true

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: event => {
                const angle = event.angleDelta.y + event.angleDelta.x;
                const pixels = event.pixelDelta.y + event.pixelDelta.x;
                const delta = angle !== 0 ? angle / 120 : pixels / 40;
                const max = Math.max(0, flick.contentHeight - flick.height);
                flick.contentY = Math.max(0, Math.min(max, flick.contentY - delta * 60));
                event.accepted = true;
            }
        }

        Column {
            id: content

            x: Math.round((page.width - page.contentWidth) / 2)
            width: page.contentWidth
            spacing: 10
            bottomPadding: 8

            // ---- Aktuelles Schema ----
            Item {
                width: parent.width
                height: 48

                Text {
                    anchors {
                        left: parent.left
                        right: shuffle.left
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    text: page.currentLabel
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                HeroButton {
                    id: shuffle

                    anchors.right: parent.right
                    icon: "shuffle"
                    label: I18n.tr("Zufällig")
                    onClicked: Themes.random()
                }
            }

            // ---- Dynamisch ----
            Text {
                visible: page.showDynamic
                topPadding: 8
                text: I18n.tr("Aus dem Wallpaper")
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Rectangle {
                visible: page.showDynamic
                width: parent.width
                height: dynTile.height + 28
                radius: 16
                color: Colors.alpha(Colors.fgSurface, 0.04)

                ColorSchemeTile {
                    id: dynTile

                    x: 14
                    y: 14
                    width: 150
                    entry: ({ mode: page.dynMode, background: "", primary: "", secondary: "", tertiary: "" })
                    title: I18n.tr("Dynamisch")
                    current: page.dynamicCurrent
                    onClicked: page.applyDynamic(page.dynFlavour, page.dynMode)
                }

                Column {
                    anchors {
                        left: dynTile.right
                        leftMargin: 24
                        right: parent.right
                        rightMargin: 14
                        verticalCenter: parent.verticalCenter
                    }

                    ColorsOption {
                        label: I18n.tr("Stil")
                        // Die Varianten wirken nur auf das dynamische Schema
                        enabled: page.dynamicCurrent
                        options: Themes.variants.map(v => v.name)
                        current: Themes.currentVariant
                        onPicked: v => Themes.setVariant(v)
                    }

                    ColorsOption {
                        label: I18n.tr("Modus")
                        options: ["dark", "light"]
                        current: page.dynMode
                        labelOf: v => v === "light" ? I18n.tr("Hell") : I18n.tr("Dunkel")
                        onPicked: v => page.applyDynamic(page.dynFlavour, v)
                    }

                    ColorsOption {
                        label: I18n.tr("Flächen")
                        options: ["default", "hard"]
                        current: page.dynFlavour
                        labelOf: v => v === "hard" ? I18n.tr("Dunkler") : I18n.tr("Standard")
                        onPicked: v => page.applyDynamic(v, page.dynMode)
                    }
                }
            }

            // ---- Feste Schemata ----
            Text {
                visible: page.schemes.length > 0
                topPadding: 8
                text: I18n.tr("Farbschemata")
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Flow {
                visible: page.schemes.length > 0
                width: parent.width
                spacing: page.gap

                Repeater {
                    model: page.schemes

                    ColorSchemeTile {
                        required property var modelData

                        width: page.cellWidth
                        entry: modelData
                        title: modelData.label
                        current: modelData.key === Themes.currentKey
                        onClicked: Themes.apply(modelData)
                    }
                }
            }

            Text {
                visible: !Themes.loading && page.found.length === 0
                width: parent.width
                topPadding: 40
                text: I18n.tr("Keine Treffer")
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
