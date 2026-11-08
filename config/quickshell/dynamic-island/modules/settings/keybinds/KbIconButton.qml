import QtQuick

import qs
import qs.modules.services.config

// Kleiner runder Symbolknopf mit Beschriftung beim Ueberfahren (Titel
// erscheint rechts daneben, wenn `hint` gesetzt ist – sonst nur das Symbol).
Item {
    id: ib

    required property string icon
    property string hint: ""
    property bool danger: false
    property bool checked: false
    property int size: 28

    signal clicked

    width: ib.size
    height: ib.size
    opacity: ib.enabled ? 1 : 0.35

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: ib.checked ? Colors.alpha(Colors.primary, hover.hovered ? 0.3 : 0.18)
             : hover.hovered ? Colors.alpha(ib.danger ? Colors.error : Colors.fgSurface, 0.12)
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
    }

    Text {
        anchors.centerIn: parent
        text: ib.icon
        color: ib.checked ? Colors.primary
             : ib.danger && hover.hovered ? Colors.error
             : Colors.fgSurfaceVariant
        font.family: "Material Symbols Outlined"
        font.pixelSize: Math.round(ib.size * 0.6)
    }

    // Die Beschriftung zeichnet das Overlay des Editors (kbOverlay in der
    // Elternkette) – als Kind des Knopfs laege sie unter spaeter gezeichneten
    // Geschwistern (Listenrahmen). Ohne Overlay faellt sie zurueck auf lokal.
    function overlay(): var {
        let p = ib.parent;
        while (p) {
            if (p.kbOverlay !== undefined && p.kbOverlay)
                return p.kbOverlay;
            p = p.parent;
        }
        return null;
    }

    property bool hasOverlay: false
    Component.onCompleted: ib.hasOverlay = ib.overlay() !== null

    onHintChanged: if (hover.hovered) ib.hoverReport(true)

    function hoverReport(on: bool): void {
        const o = ib.overlay();
        if (!o)
            return;
        if (on && ib.hint !== "" && ib.enabled)
            o.showHint(ib, ib.hint);
        else
            o.hideHint(ib);
    }

    Rectangle {
        anchors {
            top: parent.bottom
            topMargin: 4
            horizontalCenter: parent.horizontalCenter
        }
        z: 5
        visible: !ib.hasOverlay && ib.hint !== "" && hover.hovered
        width: hintText.implicitWidth + 14
        height: 22
        radius: 6
        color: Colors.surfaceBright
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.4)

        Text {
            id: hintText

            anchors.centerIn: parent
            text: ib.hint
            color: Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 11
        }
    }

    HoverHandler {
        id: hover

        enabled: ib.enabled
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: ib.hoverReport(hovered)
    }

    Component.onDestruction: ib.hoverReport(false)

    TapHandler {
        enabled: ib.enabled
        onTapped: ib.clicked()
    }
}
