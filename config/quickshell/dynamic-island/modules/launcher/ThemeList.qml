pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.theme

import qs
import qs.modules.services.config

// Theme-Auswahl: dasselbe Karussell wie bei den Wallpapern (Carousel.qml),
// nur zeigen die Kacheln hier keine Bilder, sondern die Farben des jeweiligen
// Schemas – Hintergrund als Flaeche, darauf Primaer, Sekundaer und Tertiaer.
//
// Bewusst ohne Vorschau: ein Schema anzusehen hiesse, es zu setzen. Erst der
// Klick (oder Enter) uebernimmt.
Carousel {
    id: view

    property string query: ""
    // Gesetzt, wenn ein Schema uebernommen wurde (die Karte schliesst dann)
    signal applied

    property real cardWidth: 125
    readonly property real cardHeight: 80
    readonly property real itemPadding: 8
    itemWidth: view.cardWidth + view.itemPadding * 2

    readonly property var entries: Themes.search(view.query)
    readonly property var currentEntry: view.entries[view.currentIndex] ?? null

    function apply(): void {
        if (!view.currentEntry)
            return;
        Themes.apply(view.currentEntry);
        view.applied();
    }

    implicitHeight: view.itemPadding + view.cardHeight + 4 + 15 + view.itemPadding

    model: view.entries

    // Wie im Wallpaper-Karussell: per callLater, weil am selben Signal auch
    // das Modell haengt (siehe Carousel.snapTo).
    function selectCurrent(): void {
        view.snapTo(view.query.trim() !== "" ? 0
            : view.entries.findIndex(e => e.key === Themes.currentKey));
    }

    onEntriesChanged: Qt.callLater(view.selectCurrent)

    Component.onCompleted: {
        Themes.ensureLoaded();
        Qt.callLater(view.selectCurrent);
    }

    delegate: Item {
        id: item

        required property int index
        required property var modelData

        readonly property bool isCurrent: PathView.isCurrentItem
        readonly property bool onPath: PathView.onPath
        readonly property bool isActive: item.modelData.key === Themes.currentKey

        // Das dynamische Schema hat keine Farben auf der Platte – es traegt
        // die, die gerade laufen.
        readonly property bool live: item.modelData.background === ""
        readonly property color bg: item.live ? Colors.background : item.modelData.background
        readonly property color primary: item.live ? Colors.primary : item.modelData.primary
        readonly property color secondary: item.live ? Colors.secondary : item.modelData.secondary
        readonly property color tertiary: item.live ? Colors.tertiary : item.modelData.tertiary

        width: view.itemWidth
        height: view.height
        z: PathView.itemZ ?? 0

        scale: item.isCurrent ? 1 : item.onPath ? 0.86 : 0.5
        opacity: item.onPath ? 1 : 0

        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        // Bewusst OHNE Auswahl per Hover: die Auswahl rueckt das Karussell zur
        // Mitte, damit schiebt sich die naechste Kachel unter den Zeiger, die
        // sich wieder auswaehlt – es lief endlos in die Richtung, in der die
        // Maus stand. Ausgewaehlt wird per Pfeiltasten und Rad, geklickt wird
        // direkt uebernommen.
        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: {
                view.currentIndex = item.index;
                view.apply();
            }
        }

        Rectangle {
            id: card

            anchors.horizontalCenter: parent.horizontalCenter
            y: view.itemPadding

            width: view.cardWidth
            height: view.cardHeight
            radius: 14
            // Wie die Kacheln im Settings-Feld: nicht der blanke Hintergrund
            // des Schemas – der ist bei den dunklen fast schwarz und die
            // Kachel verschwand in der Karte –, sondern eine Spur aufgehellt.
            color: Colors.shade(item.bg, 0.05)
            // Markiert = ausgewaehlt im Karussell, Ring = das laufende Schema
            border.width: item.isCurrent ? 2 : item.isActive ? 1 : 0
            border.color: item.isCurrent ? Colors.primary : Colors.outline

            Behavior on border.width {
                NumberAnimation { duration: 140 }
            }
            Behavior on color {
                ColorAnimation { duration: 140 }
            }

            // Hell oder dunkel – das ist bei den Schemata die halbe Miete
            Text {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 6
                }
                text: item.modelData.mode === "light" ? "light_mode" : "dark_mode"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 12
                color: Colors.alpha(item.primary, 0.7)
            }

            // Primaer als grosser Kreis, Sekundaer und Tertiaer daneben –
            // dasselbe Bild wie die Icon-Kreise der Settings-Kacheln.
            Row {
                anchors {
                    left: parent.left
                    leftMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                Rectangle {
                    width: 28
                    height: 28
                    radius: height / 2
                    color: item.primary
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter

                    width: 16
                    height: 16
                    radius: height / 2
                    color: item.secondary
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter

                    width: 16
                    height: 16
                    radius: height / 2
                    color: item.tertiary
                }
            }
        }

        Text {
            font.family: Config.font
            anchors {
                top: card.bottom
                topMargin: 4
                horizontalCenter: parent.horizontalCenter
            }
            width: view.cardWidth

            text: item.modelData.label
            color: item.isCurrent ? Colors.fgSurface : Colors.fgSurfaceVariant
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
