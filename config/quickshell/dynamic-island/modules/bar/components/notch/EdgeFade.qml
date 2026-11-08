pragma ComponentBehavior: Bound
import QtQuick

import qs

// Weiche Kante: Verlauf von der Kartenfarbe nach transparent, damit der
// Tagesstreifen an den Rändern ausläuft statt hart abzubrechen.
// `mirrored` dreht die Seite, `cornerRadius` folgt der Rundung der Karte –
// ohne das würde der Verlauf die runde Ecke wieder rechteckig auffüllen.
Rectangle {
    id: fade

    property bool mirrored: false
    property color baseColor: Colors.background
    property real cornerRadius: 0

    implicitWidth: 36
    bottomLeftRadius: mirrored ? 0 : cornerRadius
    bottomRightRadius: mirrored ? cornerRadius : 0

    gradient: Gradient {
        orientation: Gradient.Horizontal

        GradientStop {
            position: 0
            color: fade.mirrored ? Colors.alpha(fade.baseColor, 0) : fade.baseColor
        }
        GradientStop {
            position: 0.5
            color: Colors.alpha(fade.baseColor, 0.8)
        }
        GradientStop {
            position: 1
            color: fade.mirrored ? fade.baseColor : Colors.alpha(fade.baseColor, 0)
        }
    }
}
