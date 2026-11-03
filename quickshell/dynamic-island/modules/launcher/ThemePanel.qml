pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.modules.services.theme

import qs
import qs.modules.bar.components.notch
import qs.modules.services.config
import qs.modules.widgets

// Theme-Auswahl der Notch: eigenes Suchfeld, darunter das Farb-Karussell und
// ganz unten die Material-Varianten.
//
// Aufbau wie WallpaperPanel.qml – dritte Ansicht derselben Karte, gesteuert
// ueber LauncherState.mode. Anders als die Wallpaper-Auswahl hat sie keinen
// eigenen Knopf in der Leiste: erreichbar ist sie ueber `>theme` im Launcher.
Item {
    id: panel

    // ---- Schnittstelle zur Notch ----
    property real topOffset: 0
    property real cardRadius: 18
    property real inset: 2
    property bool active: false

    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    // Die Hoehe steht fest, Reserve und Ist sind dasselbe (siehe WallpaperPanel)
    readonly property alias maxOuterHeight: panel.outerHeight

    // Feste Hoehe des Kachelbereichs – das Karussell steckt in einem Loader
    // und ist im geschlossenen Zustand gar nicht da.
    readonly property real listHeight: 127
    readonly property real cardWidth: 125

    implicitWidth: 1000
    implicitHeight: searchRow.height + 1 + listWrapper.height + variantRow.height

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: panel.inset
        rightMargin: panel.inset
    }
    y: panel.topOffset

    // Per LazyPanel entsteht die Ansicht bereits aktiv – dann gibt es kein
    // Wechsel-Signal, die Startarbeit (Fokus, Suchfeld) wird nachgeholt
    Component.onCompleted: if (panel.active) Qt.callLater(panel.activeChanged)

    onActiveChanged: {
        if (active) {
            search.text = "";
            search.forceActiveFocus();
        }
    }

    // ---- Suchzeile ----
    Item {
        id: searchRow

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 50

        Text {
            id: searchIcon

            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: "palette"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 19
            color: Colors.primary
        }

        TextInput {
            id: search
            font.family: Config.font

            anchors {
                left: searchIcon.right
                leftMargin: 12
                right: shuffleButton.left
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            color: Colors.fgSurface
            font.pixelSize: 14
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            selectedTextColor: Colors.fgSurface
            clip: true

            Keys.onEscapePressed: LauncherState.close()
            Keys.onReturnPressed: themes.item?.apply()
            Keys.onEnterPressed: themes.item?.apply()
            // Die Pfeile blaettern im Karussell statt den Textcursor zu bewegen
            Keys.onLeftPressed: themes.item?.moveBy(-1)
            Keys.onRightPressed: themes.item?.moveBy(1)
            Keys.onUpPressed: themes.item?.moveBy(-1)
            Keys.onDownPressed: themes.item?.moveBy(1)
            Keys.onTabPressed: themes.item?.moveBy(1)

            Text {
                anchors.fill: parent
                visible: search.text === ""
                text: I18n.tr("Theme suchen…   %1 Schemata").arg(Themes.entries.length)
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                font: search.font
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Zufallsschema – wie der Shuffle-Knopf in der Wallpaper-Auswahl
        Rectangle {
            id: shuffleButton

            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            width: 32
            height: 32
            radius: height / 2
            color: shuffleArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08) : "transparent"

            Behavior on color {
                ColorAnimation { duration: 90 }
            }

            MouseArea {
                id: shuffleArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Themes.random();
                    LauncherState.close();
                }
            }

            Text {
                anchors.centerIn: parent
                text: "shuffle"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 17
                color: shuffleArea.containsMouse ? Colors.primary : Colors.fgSurfaceVariant
            }
        }
    }

    Rectangle {
        id: separator

        anchors {
            top: searchRow.bottom
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.alpha(Colors.outline, 0.35)
    }

    // ---- Karussell ----
    Item {
        id: listWrapper

        anchors {
            top: separator.bottom
            left: parent.left
            right: parent.right
        }
        height: panel.listHeight

        Loader {
            id: themes

            anchors.fill: parent
            anchors.margins: 6
            active: panel.active

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: edgeMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            sourceComponent: ThemeList {
                cardWidth: panel.cardWidth
                query: search.text
                onApplied: LauncherState.close()
            }
        }

        // Vignette nach aussen: die Reihe blendet zu den Kartenraendern hin aus
        // (Maske auf dem Inhalt, siehe EdgeMask – eine Flaeche in der
        // Theme-Farbe darueber stand auf der schwarzen Notch als grauer Balken)
        EdgeMask {
            id: edgeMask

            anchors.fill: themes
            fade: 200
        }
    }

    // ---- Material-Varianten ----
    // Sie bestimmen, wie aus dem Wallpaper eine Palette wird – wirken also nur
    // auf das dynamische Schema. Bei allen anderen bleibt die Reihe sichtbar,
    // aber zurueckgenommen.
    Item {
        id: variantRow

        anchors {
            top: listWrapper.bottom
            left: parent.left
            right: parent.right
        }
        height: 46

        // Ohne Beschriftung – dass die Reihe bei einem festen Schema nichts
        // bewirkt, sagt die Zuruecknahme.
        readonly property bool relevant: Themes.currentName === "dynamic"

        opacity: variantRow.relevant ? 1 : 0.45

        Behavior on opacity {
            NumberAnimation { duration: 160 }
        }

        // Die Chips behalten ihre natuerliche Breite, der Abstand dazwischen
        // verteilt den Rest – so fuellt die Reihe die Karte genau aus.
        //
        // Die Breiten melden die Chips selbst her: die Summe ueber `children`
        // waere keine Bindung, die nachzieht, wenn eine Beschriftung erst nach
        // dem Laden der Schrift ihre endgueltige Breite bekommt.
        Row {
            id: chips

            anchors {
                left: parent.left
                leftMargin: 16
                right: parent.right
                rightMargin: 16
                verticalCenter: parent.verticalCenter
            }

            property var widths: ({})
            readonly property real naturalWidth: {
                let sum = 0;
                for (const key in chips.widths)
                    sum += chips.widths[key];
                return sum;
            }

            function report(index: int, width: real): void {
                const next = Object.assign({}, chips.widths);
                next[index] = width;
                chips.widths = next;
            }

            spacing: Themes.variants.length > 1
                ? Math.max(4, (chips.width - chips.naturalWidth) / (Themes.variants.length - 1))
                : 0

            Repeater {
                model: Themes.variants

                Rectangle {
                    id: chip

                    required property int index
                    required property var modelData

                    readonly property bool isCurrent: chip.modelData.name === Themes.currentVariant

                    implicitWidth: chipRow.implicitWidth + 20
                    implicitHeight: 26

                    onImplicitWidthChanged: chips.report(chip.index, chip.implicitWidth)
                    Component.onCompleted: chips.report(chip.index, chip.implicitWidth)
                    radius: height / 2
                    color: chip.isCurrent ? Colors.alpha(Colors.primary, 0.18)
                         : chipArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08)
                         : "transparent"
                    border.width: chip.isCurrent ? 1 : 0
                    border.color: Colors.alpha(Colors.primary, 0.5)

                    Behavior on color {
                        ColorAnimation { duration: 90 }
                    }

                    Row {
                        id: chipRow

                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter

                            text: chip.modelData.icon
                            color: chip.isCurrent ? Colors.primary : Colors.fgSurfaceVariant
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 13
                        }

                        Text {
                            font.family: Config.font
                            anchors.verticalCenter: parent.verticalCenter

                            text: chip.modelData.name
                            color: chip.isCurrent ? Colors.primary : Colors.fgSurfaceVariant
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: chipArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Themes.setVariant(chip.modelData.name)
                    }
                }
            }
        }
    }
}
