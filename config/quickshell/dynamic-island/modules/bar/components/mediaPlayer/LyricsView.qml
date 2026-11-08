pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.modules.services.media
import qs.modules.services.core

import qs
import qs.modules.services.config

// Songtext unter der Transportreihe (Config.media.lyrics). Oben eine
// Kopfzeile "Songtext" mit Zustand/Quelle rechts und einem Pfeil zum
// Zuklappen; darunter die Zeilen, die aktuelle gross und hell in der Mitte,
// die Nachbarn kleiner und gedimmt. Oben und unten laufen die Zeilen in die
// Karte aus (Maske, wie widgets/EdgeMask – kein Verlauf in Kartenfarbe, der
// stimmt bei durchscheinendem Cover nicht).
//
// Mitlaufen: Lyrics.index wechselt nur beim Zeilenwechsel, darauf hin faehrt
// die Liste EINMAL weich zur neuen Zeile (scrollAnim). Kein Behavior auf
// contentY, keine Dauer-Animation – zwischen zwei Zeilen zeichnet hier
// nichts.
//
// Bedarf (Lyrics.demand) meldet der Block selbst an: nur solange `shown`
// (Panel sichtbar und aufgeklappt) – siehe DemandRequest unten.
Item {
    id: view

    property color tint: Colors.background
    // Aufgeklappt? Zustand lebt nur hier im Panel, nicht in der Config
    property bool open: true
    // Ist das Panel drumherum ueberhaupt zu sehen? (sonst kein Bedarf)
    property bool shown: true
    // Hoehe der Textflaeche
    property real bodyHeight: 92

    readonly property bool hasText: Lyrics.status === "ok" && Lyrics.lines.length > 0
    readonly property bool bodyOpen: view.open && view.hasText
    readonly property real headerHeight: 18

    // Zeilenwechsel: nach der naechsten Layout-Runde zur Zeile fahren
    readonly property int current: Lyrics.index

    implicitHeight: view.headerHeight + (view.bodyOpen ? view.bodyHeight + 4 : 0)

    DemandRequest {
        demand: Lyrics.demand
        active: view.shown && view.open && Config.media.lyrics
    }

    onCurrentChanged: view.follow(true)
    onBodyOpenChanged: if (view.bodyOpen) Qt.callLater(() => view.follow(false))

    Connections {
        target: Lyrics

        // Neuer Text: nach oben, ohne Fahrt
        function onLinesChanged(): void {
            Qt.callLater(() => view.follow(false));
        }
    }

    // Die aktuelle Zeile in die Mitte der Flaeche holen. Kopf- und Fusszeile
    // der Liste sind je eine halbe Flaeche hoch, deshalb geht das auch fuer
    // die erste und letzte Zeile, ohne die Grenzen zu verlassen.
    function follow(animate: bool): void {
        if (!view.bodyOpen)
            return;
        const idx = Lyrics.index;
        let target = 0;
        if (idx >= 0) {
            const item = list.itemAtIndex(idx);
            if (item) {
                target = item.y + item.height / 2 - list.height / 2;
            } else {
                // Zeile liegt ausserhalb des Puffers (Seek): hinspringen
                scrollAnim.stop();
                list.positionViewAtIndex(idx, ListView.Center);
                return;
            }
        } else {
            // Vor der ersten Zeile: sie steht unterhalb der Mitte, als
            // "kommt gleich" (siehe header der Liste)
            target = 0;
        }
        const max = Math.max(0, list.contentHeight - list.height);
        target = Math.max(0, Math.min(max, target));
        if (!animate || !view.shown) {
            scrollAnim.stop();
            list.contentY = target;
            return;
        }
        scrollAnim.to = target;
        scrollAnim.restart();
    }

    // ---- Kopfzeile ----
    Item {
        id: header

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: view.headerHeight

        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -4
            anchors.rightMargin: -4
            radius: 6
            color: headHover.hovered ? Colors.shade(view.tint, 0.11) : "transparent"

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
        }

        Text {
            anchors {
                left: parent.left
                leftMargin: 4
                verticalCenter: parent.verticalCenter
            }
            font.family: Config.font
            text: I18n.tr("Songtext")
            color: Colors.alpha(Colors.fgSurfaceVariant, 0.75)
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }

        // Rechts: Zustand bzw. Quelle, ganz leise
        Text {
            anchors {
                right: chevron.left
                rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            font.family: Config.font
            text: Lyrics.status === "loading" ? I18n.tr("Lade Songtext…")
                : Lyrics.status === "none" ? I18n.tr("Kein Songtext")
                : Lyrics.status === "ok" ? (Lyrics.source === "spotify" ? "Spotify" : "lrclib")
                : ""
            color: Colors.alpha(Colors.fgSurfaceVariant, 0.55)
            font.pixelSize: 8
            font.weight: Font.Medium
        }

        Text {
            id: chevron

            anchors {
                right: parent.right
                rightMargin: 2
                verticalCenter: parent.verticalCenter
            }
            text: "expand_more"
            color: Colors.fgSurfaceVariant
            font.family: "Material Symbols Outlined"
            font.pixelSize: 14
            rotation: view.open ? 180 : 0
            opacity: view.hasText ? 1 : 0.4

            Behavior on rotation {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }
        }

        HoverHandler {
            id: headHover

            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: view.open = !view.open
        }
    }

    // ---- Textflaeche ----
    Item {
        id: body

        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            topMargin: 4
        }
        height: view.bodyHeight
        visible: view.bodyOpen

        // Die Liste ist eine Ebene mit Maske: innen deckend, oben und
        // unten auf 0 – die Zeilen selbst werden durchsichtig
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fadeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Item {
            id: fadeMask

            anchors.fill: parent
            visible: false
            layer.enabled: true

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Vertical

                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.28; color: "white" }
                    GradientStop { position: 0.72; color: "white" }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }

        ListView {
            id: list

            readonly property real rowStep: 20

            anchors.fill: parent
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            interactive: false
            // Alle Zeilen vorhalten: so kennt contentHeight die echte Hoehe
            // und itemAtIndex findet auch weit entfernte Zeilen
            cacheBuffer: 4000

            model: ScriptModel {
                values: Lyrics.lines
            }
            // Kein Highlight-Nachfuehren (siehe LauncherPanel.qml)
            highlightFollowsCurrentItem: false

            // Halbe Flaeche Luft oben und unten, damit auch die erste und
            // letzte Zeile in der Mitte stehen koennen. Oben eine Zeile
            // mehr: ganz am Anfang (contentY 0, Index -1) steht die erste
            // Zeile dann eine Stufe unter der Mitte – "kommt gleich".
            header: Item { width: 1; height: list.height / 2 + list.rowStep / 2 }
            footer: Item { width: 1; height: list.height / 2 - list.rowStep / 2 }

            delegate: Item {
                id: line

                required property var modelData
                required property int index

                readonly property bool active: Lyrics.synced && line.index === view.current
                readonly property int distance: Lyrics.synced && view.current >= 0 ? Math.abs(line.index - view.current) : 2

                width: list.width
                height: Math.max(list.rowStep, lineText.implicitHeight)

                Text {
                    id: lineText

                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 4
                        rightMargin: 4
                    }
                    font.family: Config.font
                    text: line.modelData.text || "♪"
                    color: Colors.fgBackground
                    font.pixelSize: 13
                    font.weight: line.active ? Font.DemiBold : Font.Medium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight

                    // Nachbarn kleiner (Skalierung statt Schriftgroesse: das
                    // Layout bleibt, nur die Darstellung aendert sich) und
                    // gedimmt. Beides wechselt nur beim Zeilenwechsel.
                    scale: line.active || !Lyrics.synced ? 1 : 0.86
                    opacity: !Lyrics.synced ? 0.55
                           : line.active ? 1
                           : line.distance === 1 ? 0.42 : 0.28

                    Behavior on scale {
                        NumberAnimation { duration: Appearance.fadeDuration * 1.5; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Appearance.fadeDuration * 1.5; easing.type: Easing.OutCubic }
                    }
                }
            }

            NumberAnimation {
                id: scrollAnim

                target: list
                property: "contentY"
                duration: Appearance.morphDuration
                easing.type: Easing.OutCubic
            }

            // Mausrad: von Hand blaettern (beim naechsten Zeilenwechsel
            // holt die Liste die aktuelle Zeile wieder in die Mitte)
            property real targetY: 0

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const angle = event.angleDelta.y;
                    const pixels = event.pixelDelta.y;
                    if (angle === 0 && pixels === 0) {
                        event.accepted = false;
                        return;
                    }
                    event.accepted = true;
                    const max = Math.max(0, list.contentHeight - list.height);

                    if (pixels !== 0) {
                        scrollAnim.stop();
                        list.contentY = Math.max(0, Math.min(max, list.contentY - pixels));
                        list.targetY = list.contentY;
                        return;
                    }

                    if (!scrollAnim.running)
                        list.targetY = list.contentY;
                    list.targetY = Math.max(0, Math.min(max, list.targetY - angle / 120 * list.rowStep * 2));
                    scrollAnim.to = list.targetY;
                    scrollAnim.restart();
                }
            }
        }
    }
}
