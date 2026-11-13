import QtQuick

import qs
import qs.modules.widgets

// An/Aus-Schalter 40×22 (Stil des Einstellungsfensters). `checked` setzt der
// Verwender, ein Klick meldet nur `toggled()`.
Rectangle {
    id: sw

    property bool checked: false
    signal toggled

    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    opacity: enabled ? 1 : 0.4
    color: sw.checked ? Colors.primary : Colors.alpha(Colors.fgSurface, 0.18)

    Behavior on color {
        ColorAnimation { duration: 140 }
    }

    Rectangle {
        width: 16
        height: 16
        radius: 8
        y: 3
        x: sw.checked ? parent.width - width - 3 : 3
        color: sw.checked ? Colors.fgPrimary : Colors.fgSurfaceVariant

        Morph on x {}
    }

    HoverHandler {
        cursorShape: sw.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    TapHandler {
        enabled: sw.enabled
        onTapped: sw.toggled()
    }
}
