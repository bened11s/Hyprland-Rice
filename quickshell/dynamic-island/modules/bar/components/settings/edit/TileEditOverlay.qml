pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Liegt ueber jeder Kachel des Kachel-Editors (ein Loader je Platz in
// SettingsTiles baut es, nur wenn `editable`).
//
// Der exklusive TapHandler frisst jede Eingabe, damit die Kachel nicht
// schaltet (ReleaseWithinBounds greift beim Druecken exklusiv – Handler
// darunter bekommen den Punkt nicht mehr, Items auch nicht; dasselbe
// Prinzip wie die MiniButtons der Kacheln). Dazu:
//   antippen            waehlt (Akzent-Ring)
//   ziehen              umsortieren (Geist + Markierung, siehe QuickEdit)
//   Griff rechts ziehen Breite in Spalten (nur bei gewaehlter Kachel)
Item {
    id: overlay

    required property QuickEdit edit
    required property string tileId
    required property int span
    // Breite einer Rasterspalte samt Luecke – ein Schritt am Griff
    required property real step

    readonly property bool editing: overlay.edit.editing && overlay.edit.mode === "tiles"
    readonly property bool selected: overlay.editing && overlay.edit.selectedId === overlay.tileId
    readonly property bool stretching: overlay.edit.resizeId === overlay.tileId

    // Kachel ist eine Pille: Ring und Griff folgen ihrem Radius
    readonly property real tileRadius: height / 2

    // ---- Eingaben schlucken, antippen waehlt ----
    TapHandler {
        enabled: overlay.editing
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: overlay.edit.select(overlay.tileId)
    }

    // Mausrad abfangen, sonst stellt der Regler darunter weiter
    WheelHandler {
        enabled: overlay.editing
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        target: null
        onWheel: event => event.accepted = true
    }

    HoverHandler {
        enabled: overlay.editing
        cursorShape: overlay.edit.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }

    DragHandler {
        id: move

        enabled: overlay.editing && !handleHover.hovered && overlay.edit.resizeId === ""
        target: null
        onActiveChanged: {
            if (move.active)
                overlay.edit.beginDrag(overlay.tileId);
            else
                overlay.edit.endDrag();
        }
        onCentroidChanged: {
            if (move.active)
                overlay.edit.updateDrag(move.centroid.scenePosition);
        }
    }

    // ---- Auswahl-Ring ----
    // Akzentring mit dunkler Fuge dazwischen – sonst verschwaende er auf
    // einer aktiven (akzentfarbenen) Kachel
    Item {
        anchors.fill: parent
        opacity: overlay.selected ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 120 }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: overlay.tileRadius + 2
            color: "transparent"
            border.width: 2
            border.color: Colors.background
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: overlay.tileRadius + 4
            color: "transparent"
            border.width: 2
            border.color: Colors.primary
        }
    }

    // Breite als Zahl, solange am Griff gezogen wird
    Rectangle {
        anchors {
            right: handle.left
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        width: spanLabel.implicitWidth + 12
        height: 20
        radius: 10
        color: Colors.primary
        visible: overlay.stretching

        Text {
            id: spanLabel

            anchors.centerIn: parent
            font.family: Config.font
            text: overlay.edit.resizeSpan
            color: Colors.fgPrimary
            font.pixelSize: 11
            font.weight: Font.Bold
        }
    }

    // ---- Griff am rechten Rand: Breite ziehen ----
    Item {
        id: handle

        anchors {
            right: parent.right
            rightMargin: -8
            top: parent.top
            bottom: parent.bottom
        }
        width: 24
        visible: overlay.selected
        z: 2

        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 28
            radius: 4
            color: handleHover.hovered || overlay.stretching ? Colors.primary : Colors.alpha(Colors.primary, 0.85)
            border.width: 2
            border.color: Colors.background
            scale: handleHover.hovered || overlay.stretching ? 1.1 : 1

            Behavior on scale {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }

        HoverHandler {
            id: handleHover

            cursorShape: Qt.SizeHorCursor
        }

        DragHandler {
            id: stretch

            property int startSpan: 0

            target: null
            xAxis.enabled: true
            yAxis.enabled: false

            onActiveChanged: {
                if (stretch.active) {
                    stretch.startSpan = overlay.span;
                    overlay.edit.resizeSpan = overlay.span;
                    overlay.edit.resizeId = overlay.tileId;
                } else {
                    const next = overlay.edit.resizeSpan;
                    overlay.edit.resizeId = "";
                    QuickLayout.resize(overlay.tileId, next);
                }
            }
            onTranslationChanged: {
                if (!stretch.active)
                    return;
                const wanted = stretch.startSpan + Math.round(stretch.activeTranslation.x / overlay.step);
                overlay.edit.resizeSpan = Math.max(QuickLayout.minSpan(overlay.tileId),
                                                   Math.min(QuickLayout.maxSpan(overlay.tileId), wanted));
            }
        }
    }
}
