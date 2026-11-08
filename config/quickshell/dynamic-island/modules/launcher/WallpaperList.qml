pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.modules.services.wallpaper

import qs
import qs.modules.services.config

// Wallpaper-Auswahl im Launcher: ein Karussell aus Vorschaubildern, das
// aktuelle steht in der Mitte.
//
// Die Mechanik (Pfad, Rad, Einrasten) steckt in Carousel.qml – hier stehen nur
// die Bilder: Liste aus dem Wallpapers-Dienst, Kachel mit Vorschaubild.
//
// Waehrend man sich durchbewegt, zeigt der Hintergrund das markierte Bild
// schon an (Vorschau) – aber erst nach kurzem Verweilen, sonst dekodiert Qt
// bei jedem Tastendruck ein Bild in voller Bildschirmgroesse.
Carousel {
    id: view

    property string query: ""
    // Wird gesetzt, wenn ein Bild uebernommen wurde (der Launcher schliesst dann)
    signal applied

    // Hat diese Reihe die Tastatur? Sonst (Plugin-Sektion aktiv) ist der
    // Rahmen der markierten Kachel gedimmt.
    property bool focused: true

    // Von aussen setzbar: das Panel entscheidet, wie breit die Kacheln sind
    property real imageWidth: 160
    readonly property real imageHeight: Math.round(imageWidth / 16 * 9)
    readonly property real itemPadding: 8
    itemWidth: view.imageWidth + view.itemPadding * 2

    readonly property var entries: Wallpapers.search(view.query)
    readonly property string currentPath: view.entries[view.currentIndex]?.path ?? ""

    // Uebernehmen: Bild setzen und Bescheid geben
    function apply(): void {
        if (view.currentPath === "")
            return;
        Wallpapers.set(view.currentPath);
        view.applied();
    }

    implicitHeight: view.itemPadding + view.imageHeight + 4 + 15 + view.itemPadding

    model: view.entries

    // Beim Aufbau auf dem aktuell gesetzten Bild stehen, bei einer Suche vorne.
    //
    // Per callLater, weil an derselben Aenderung auch das Modell haengt: setzt
    // man den Index direkt, stellt PathView ihn beim Modellwechsel gleich
    // wieder auf 0 – das Karussell stand dann immer auf dem ersten Bild statt
    // auf dem aktuellen.
    function selectCurrent(): void {
        view.snapTo(view.query.trim() !== "" ? 0
            : view.entries.findIndex(w => w.path === Wallpapers.actualCurrent));
    }

    onEntriesChanged: Qt.callLater(view.selectCurrent)

    Component.onCompleted: {
        Wallpapers.ensureLoaded();
        Qt.callLater(view.selectCurrent);
    }
    // Der Launcher hat die Auswahl verlassen -> Hintergrund zurueck auf echt
    Component.onDestruction: Wallpapers.stopPreview()

    onCurrentIndexChanged: previewTimer.restart()

    Timer {
        id: previewTimer

        interval: 160
        onTriggered: if (view.currentPath !== "")
            Wallpapers.preview(view.currentPath)
    }

    delegate: Item {
        id: item

        required property int index
        required property var modelData

        readonly property bool isCurrent: PathView.isCurrentItem
        readonly property bool onPath: PathView.onPath

        width: view.itemWidth
        // Vom Panel vorgegeben (der Loader fuellt dessen Listenbereich);
        // implicitHeight ist nur der Eigenbedarf, falls jemand es frei stellt.
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

        // Rahmen + Platzhalter, solange das Bild noch laedt
        Rectangle {
            id: frame

            anchors.horizontalCenter: parent.horizontalCenter
            y: view.itemPadding

            width: view.imageWidth
            height: view.imageHeight
            radius: 12
            color: Colors.surfaceContainer
            border.width: item.isCurrent ? 2 : 0
            border.color: view.focused ? Colors.primary : Colors.alpha(Colors.primary, 0.4)

            Behavior on border.width {
                NumberAnimation { duration: 140 }
            }
            Behavior on border.color {
                ColorAnimation { duration: 140 }
            }

            Text {
                anchors.centerIn: parent
                visible: thumb.status !== Image.Ready

                text: "image"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 22
            }

            Image {
                id: thumb

                anchors.fill: parent
                anchors.margins: frame.border.width

                // Immer das kleine Vorschaubild (480x270 aus thumbs.sh), nie
                // das Original: Qt dekodiert alle Bilder in einem Thread, und
                // ein 40-MB-PNG je Kachel staute dort auch den Hintergrund.
                // Fehlt es noch, bleibt der Platzhalter stehen.
                source: Wallpapers.thumbFor(item.modelData.name)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // Klein genug, um im Cache zu bleiben: zurueckblaettern zeigt
                // die Kachel sofort statt neu zu laden
                cache: true
                smooth: !view.moving
                visible: false          // nur Quelle fuer die Maske
            }

            Item {
                id: thumbMask

                anchors.fill: thumb
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: frame.radius - frame.border.width
                    color: "black"
                }
            }

            // Runde Ecken gehen nur ueber eine Maske – `clip` schneidet
            // rechteckig (siehe Cover im MediaPanel).
            MultiEffect {
                anchors.fill: thumb
                visible: thumb.status === Image.Ready

                source: thumb
                maskEnabled: true
                maskSource: thumbMask
            }
        }

        Text {
            font.family: Config.font
            anchors {
                top: frame.bottom
                topMargin: 4
                horizontalCenter: parent.horizontalCenter
            }
            width: view.imageWidth

            text: item.modelData.name
            color: item.isCurrent ? Colors.fgSurface : Colors.fgSurfaceVariant
            font.pixelSize: 11
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
