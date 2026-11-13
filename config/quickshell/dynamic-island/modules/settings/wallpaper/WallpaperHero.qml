pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.modules.services.config
import qs.modules.services.wallpaper
import qs.modules.settings
import qs.modules.widgets

import qs

// Kopf der Seite "Aussehen" im Einstellungs-Fenster (Config.meta editor
// "wallpaperhero"): das gesetzte Bild gross und mittig, darunter die Knoepfe
// "Wallpaper" (Bibliothek, Seite @wallpapers im selben Fenster), "Farben"
// (Farbschema-Auswahl der Notch) und Zufall – wie bei Caelestia.
//
// Nur das Vorschaubild (Wallpapers.displayThumbFor, 480x270 aus thumbs.sh,
// notfalls das der CLI), nie das Original: Qt dekodiert alle Bilder in einem
// Thread, ein grosses PNG staut sonst die ganze Shell. Beim Wechsel blenden
// zwei Bildplaetze ueber; das neue kommt erst nach vorn, wenn es geladen ist.
Item {
    id: hero

    readonly property string path: Wallpapers.actualCurrent

    // Von SettingsRow gesetzt; der Kopf sieht ueberall gleich aus
    property bool inLibrary: false

    readonly property real previewWidth: Math.min(hero.width, 570)
    readonly property real previewHeight: Math.round(hero.previewWidth * 320 / 570)

    implicitHeight: hero.previewHeight + 16 + buttons.height + 12

    // Seite wechseln, das Fenster bleibt offen (SettingsCard reagiert auf
    // die Aenderung von SettingsState.request)
    function openLibrary(): void {
        SettingsState.openPage("@wallpapers", {});
    }

    // Farbschemata als Unterseite im selben Fenster (ColorsPage), nicht in der Notch
    function openColors(): void {
        SettingsState.openPage("@colors", {});
    }

    // ---- Das Bild ----
    Item {
        id: frame

        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: 4
        }
        width: hero.previewWidth
        height: hero.previewHeight

        readonly property string wanted: Wallpapers.displayThumbFor(hero.path)
        // Welcher Platz vorn liegt (0 = slotA)
        property int front: 0
        readonly property var frontSlot: frame.front === 0 ? slotA : slotB
        readonly property var backSlot: frame.front === 0 ? slotB : slotA
        readonly property bool shown: frame.frontSlot.key !== "" && frame.frontSlot.status === Image.Ready

        // Neues Bild in den hinteren Platz laden; nach vorn kommt es erst,
        // wenn es fertig ist (ready) – so bleibt das alte bis dahin stehen
        function load(): void {
            if (frame.frontSlot.key === frame.wanted)
                return;
            frame.backSlot.key = frame.wanted;
            frame.backSlot.source = frame.wanted;
            if (frame.wanted === "")
                frame.front = 1 - frame.front;
        }

        function ready(slot: var): void {
            if (slot === frame.backSlot && slot.status === Image.Ready && slot.key === frame.wanted)
                frame.front = 1 - frame.front;
        }

        onWantedChanged: frame.load()
        Component.onCompleted: frame.load()

        // Platzhalter, solange (noch) kein Vorschaubild da ist
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Colors.surfaceContainer

            Text {
                anchors.centerIn: parent
                text: "image"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 34
                color: Colors.fgSurfaceVariant
                opacity: frame.shown ? 0 : 1

                Fade on opacity {}
            }
        }

        Item {
            id: images

            anchors.fill: parent
            visible: false          // nur Quelle fuer die Maske
            layer.enabled: true

            Image {
                id: slotA

                property string key: ""

                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: frame.front === 0 ? 1 : 0
                onStatusChanged: frame.ready(slotA)

                Fade on opacity {}
            }

            Image {
                id: slotB

                property string key: ""

                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: frame.front === 1 ? 1 : 0
                onStatusChanged: frame.ready(slotB)

                Fade on opacity {}
            }
        }

        Item {
            id: mask

            anchors.fill: parent
            layer.enabled: true
            visible: false

            Rectangle {
                anchors.fill: parent
                radius: 16
                color: "black"
            }
        }

        MultiEffect {
            anchors.fill: images
            source: images
            maskEnabled: true
            maskSource: mask
            shadowEnabled: Appearance.shadow
            shadowColor: Appearance.shadowColor
            shadowOpacity: 0.45
            shadowBlur: 0.8
            shadowVerticalOffset: 3
        }

        // Beim Zeigen leicht aufhellen (Klick = Bibliothek)
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: Colors.fgSurface
            opacity: frameHover.hovered ? 0.08 : 0

            Fade on opacity {}
        }

        HoverHandler {
            id: frameHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: hero.openLibrary()
        }
    }

    Row {
        id: buttons

        anchors {
            horizontalCenter: parent.horizontalCenter
            top: frame.bottom
            topMargin: 16
        }
        spacing: 10

        HeroButton {
            icon: "photo_library"
            label: I18n.tr("Wallpaper")
            onClicked: hero.openLibrary()
        }

        HeroButton {
            icon: "palette"
            label: I18n.tr("Farben")
            onClicked: hero.openColors()
        }

        HeroButton {
            icon: "shuffle"
            onClicked: Wallpapers.random()
        }
    }
}
