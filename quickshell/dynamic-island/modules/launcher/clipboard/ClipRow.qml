pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets

import qs
import qs.modules.widgets
import qs.modules.services.config
import qs.modules.services.clipboard

// Eine Zeile der Zwischenablage: Text (erste Zeile) oder Bildvorschau,
// rechts beim Ueberfahren/Markieren die Knoepfe Anheften und Loeschen.
// Zur Seite ziehen entfernt den Eintrag (wie bei den Benachrichtigungen).
// Aufgeklappt (Tab) steht unter einem Texteintrag der ganze Text.
//
// modelData: { key, section: "pin"|"hist", kind: "text"|"image", id,
//              pinKey, text, full, pinned, path, w, h, size }
Rectangle {
    id: row

    required property var modelData
    required property int index
    required property bool selected
    property bool expanded: false
    // Ganzer Text zum Aufklappen (das Panel holt ihn vom Dienst)
    property string fullText: ""
    property bool truncated: false

    signal activated
    signal hovered
    signal pinToggled
    signal removed
    // Rechtsklick, Position in Zeilen-Koordinaten
    signal contextRequested(real x, real y)

    readonly property bool isPin: row.modelData.section === "pin"
    readonly property bool isImage: row.modelData.kind === "image"
    readonly property bool showTools: row.selected || mouse.containsMouse
    readonly property real leftInset: 16
    readonly property real toolsWidth: 60

    // ---- Bildvorschau ----
    // Verlauf: verkleinertes PNG vom Dienst (leer, bis es fertig ist).
    // Angeheftet: die Datei selbst, klein dekodiert.
    readonly property string thumb: row.isImage
        ? (row.isPin ? row.modelData.path : (Clipboard.thumbs[row.modelData.id] ?? ""))
        : ""
    readonly property real maxThumbWidth: 360
    readonly property real maxThumbHeight: 120
    // Seitenverhaeltnis aus den Metadaten, sonst aus dem geladenen Bild
    readonly property real srcW: row.modelData.w > 0 ? row.modelData.w
                               : shot.status === Image.Ready ? shot.implicitWidth : 0
    readonly property real srcH: row.modelData.h > 0 ? row.modelData.h
                               : shot.status === Image.Ready ? shot.implicitHeight : 0
    readonly property real thumbHeight: row.srcW > 0 && row.srcH > 0
        ? Math.max(20, Math.min(row.maxThumbHeight, row.srcH, row.maxThumbWidth * row.srcH / row.srcW))
        : 72
    readonly property real thumbWidth: row.srcW > 0 && row.srcH > 0
        ? Math.max(28, Math.round(row.thumbHeight * row.srcW / row.srcH))
        : 128

    function requestThumb(): void {
        if (row.isImage && !row.isPin && row.thumb === "")
            Clipboard.requestThumb(row.modelData.id);
    }

    Component.onCompleted: row.requestThumb()
    // Wiederverwendete Delegaten bekommen neue Daten
    onModelDataChanged: {
        slideBack.stop();
        slideOut.stop();
        row.slide = 0;
        row.requestThumb();
    }

    // ---- Wegziehen ----
    // Versatz beim Ziehen; ueber ein Drittel der Breite fliegt die Zeile raus,
    // darunter federt sie zurueck
    property real slide: 0

    transform: Translate {
        x: row.slide
    }
    opacity: row.slide === 0 ? 1
           : 1 - Math.min(0.85, Math.abs(row.slide) / Math.max(1, row.width * 0.7))

    NumberAnimation {
        id: slideBack

        target: row
        property: "slide"
        to: 0
        duration: Appearance.fadeDuration
        easing.type: Easing.OutCubic
    }

    // Erst rausfliegen lassen, dann entfernen – sonst ist der Delegat weg,
    // bevor man die Bewegung sieht
    NumberAnimation {
        id: slideOut

        target: row
        property: "slide"
        duration: 140
        easing.type: Easing.OutCubic
        onFinished: row.removed()
    }

    // Aufgeklappt ersetzt der ganze Text die Vorschauzeile
    readonly property bool showBody: row.expanded && !row.isImage

    implicitHeight: row.isImage ? row.thumbHeight + 12
                  : row.showBody ? Math.max(36, body.implicitHeight + 20)
                  : 36
    radius: 10
    color: row.selected ? Colors.alpha(Colors.primary, 0.14)
         : mouse.containsMouse ? Colors.alpha(Colors.fgSurface, 0.06)
         : "transparent"

    Behavior on color {
        ColorAnimation { duration: Appearance.fadeDuration }
    }

    // Markierung an der linken Kante wie in der Trefferliste
    Rectangle {
        anchors {
            left: parent.left
            leftMargin: 4
            verticalCenter: head.verticalCenter
        }
        width: 3
        height: 22
        radius: 1.5
        color: Colors.primary
        opacity: row.selected ? 1 : 0

        Fade on opacity {}
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onEntered: row.hovered()
        onClicked: event => {
            if (event.button === Qt.RightButton)
                row.contextRequested(event.x, event.y);
            else
                row.activated();
        }

        // Nur die Waagerechte: senkrecht scrollt weiter die Liste. Uebernimmt
        // erst nach ein paar px, ein Klick kopiert also wie gehabt
        DragHandler {
            id: swipe

            target: null
            yAxis.enabled: false
            dragThreshold: 8

            readonly property real threshold: row.width * 0.3

            onTranslationChanged: if (swipe.active)
                row.slide = swipe.activeTranslation.x
            onActiveChanged: {
                if (swipe.active) {
                    slideBack.stop();
                    slideOut.stop();
                    return;
                }
                if (Math.abs(row.slide) > swipe.threshold) {
                    slideOut.to = row.slide > 0 ? row.width : -row.width;
                    slideOut.start();
                } else {
                    slideBack.start();
                }
            }
        }
    }

    // ---- Kopfzeile: Text oder Bild ----
    Item {
        id: head

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            leftMargin: row.leftInset
            rightMargin: row.toolsWidth
        }
        height: row.isImage ? row.thumbHeight + 12 : 36

        // Angeheftet-Marke vor dem Text, nur im Verlauf (die Pin-Liste
        // selbst braucht sie nicht)
        Text {
            id: pinMark

            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            visible: !row.isPin && row.modelData.pinned && !row.isImage
            text: "keep"
            color: Colors.primary
            font.family: "Material Symbols Outlined"
            font.pixelSize: 13
        }

        Text {
            anchors {
                left: pinMark.visible ? pinMark.right : parent.left
                leftMargin: pinMark.visible ? 6 : 0
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            visible: !row.isImage && !row.showBody
            text: row.modelData.text
            color: Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 13
            font.weight: row.selected ? Font.Medium : Font.Normal
            elide: Text.ElideRight
        }

        ClippingRectangle {
            id: preview

            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            visible: row.isImage
            width: row.thumbWidth
            height: row.thumbHeight
            radius: 7
            color: Colors.alpha(Colors.fgSurface, 0.06)

            Image {
                id: shot

                anchors.fill: parent
                source: row.thumb !== "" ? "file://" + row.thumb : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                // Angeheftete Bilder sind Originale – klein dekodieren
                sourceSize: row.isPin ? Qt.size(480, 0) : Qt.size(0, 0)
                opacity: status === Image.Ready ? 1 : 0

                Fade on opacity {}
            }
        }

        // Masse und Groesse als leise Meta-Angabe neben dem Bild
        Text {
            anchors {
                left: preview.right
                leftMargin: 12
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            visible: row.isImage
            text: {
                const parts = [];
                if (row.srcW > 0 && row.srcH > 0)
                    parts.push(Math.round(row.srcW) + " × " + Math.round(row.srcH));
                if (row.modelData.size)
                    parts.push(row.modelData.size);
                return parts.join("  ·  ");
            }
            color: Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    // ---- Ganzer Text (aufgeklappt) ----
    Text {
        id: body

        anchors {
            top: parent.top
            topMargin: 10
            left: parent.left
            right: parent.right
            leftMargin: row.leftInset + (pinMark.visible ? pinMark.width + 6 : 0)
            rightMargin: row.toolsWidth
        }
        visible: row.showBody
        text: row.fullText + (row.truncated ? " …" : "")
        color: Colors.fgSurface
        font.family: Config.font
        font.pixelSize: 13
        wrapMode: Text.Wrap
        maximumLineCount: 18
        elide: Text.ElideRight
    }

    // ---- Knoepfe rechts, nur beim Ueberfahren/Markieren ----
    Row {
        anchors {
            right: parent.right
            rightMargin: 6
            top: parent.top
            topMargin: 6
        }
        spacing: 2

        ClipIconButton {
            shown: row.showTools
            on: row.modelData.pinned
            icon: row.modelData.pinned ? "keep_off" : "keep"
            onClicked: row.pinToggled()
        }

        ClipIconButton {
            shown: row.showTools && !row.isPin
            icon: "close"
            danger: true
            onClicked: row.removed()
        }
    }
}
