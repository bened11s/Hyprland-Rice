import QtQuick

// Maske fuer eine Reihe, die links und rechts ausblenden soll (Karussells):
// innen deckend, zu den Seiten hin auf 0. Als maskSource eines MultiEffect
// auf dem Inhalt – anders als EdgeFade, das eine Flaeche in der Kartenfarbe
// darueberlegt, werden hier die Kacheln selbst durchsichtig. Das passt so zu
// jeder Karte, auch zur schwarzen Notch und zu ihrem Verlauf.
//
//     layer.enabled: true
//     layer.effect: MultiEffect {
//         maskEnabled: true
//         maskSource: mask
//         maskThresholdMin: 0.5   // mit Spread 1 = Maskenalpha 1:1
//         maskSpreadAtMin: 1
//     }
//     EdgeMask { id: mask; anchors.fill: <inhalt>; fade: 160 }
//
// Die Ebene ist von Anfang an an (layer.enabled erst zur Laufzeit
// einzuschalten liess die Maske leer) und das Item selbst unsichtbar.
Item {
    id: mask

    // Breite des Auslaufs je Seite in Pixeln
    property real fade: 160

    readonly property real edge: mask.width > 0 ? Math.min(0.5, mask.fade / mask.width) : 0

    visible: false
    layer.enabled: true

    Rectangle {
        anchors.fill: parent

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: mask.edge; color: "white" }
            GradientStop { position: 1 - mask.edge; color: "white" }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
