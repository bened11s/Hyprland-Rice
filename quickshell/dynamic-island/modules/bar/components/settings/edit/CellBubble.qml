pragma ComponentBehavior: Bound
import QtQuick

import qs

// Eine freie Zelle im Kachel-Editor als leere Blase (wie Android) – fuer
// Luecken und den Rest einer Reihe (SettingsTiles). Leuchtet, wenn eine
// gezogene Kachel genau hier landen wuerde (Ziel mit Spalte, siehe
// QuickEdit.freeTarget).
Rectangle {
    id: bubble

    required property QuickEdit edit
    required property int rowIndex
    required property int column

    readonly property var target: bubble.edit.target
    readonly property bool targeted: bubble.target !== null && bubble.target.column !== undefined
                                     && bubble.target.rowIndex === bubble.rowIndex
                                     && bubble.column >= bubble.target.column
                                     && bubble.column < bubble.target.column + bubble.target.span

    implicitHeight: 54
    radius: height / 2
    color: bubble.targeted ? Colors.alpha(Colors.primary, 0.2) : Colors.alpha(Colors.fgSurface, 0.05)
    border.width: 1
    border.color: bubble.targeted ? Colors.alpha(Colors.primary, 0.6) : Colors.alpha(Colors.outline, 0.18)

    Behavior on color {
        ColorAnimation { duration: 120 }
    }
    Behavior on border.color {
        ColorAnimation { duration: 120 }
    }
}
