import QtQuick

import qs

// Ein-/Ausblenden von Inhalten: `Fade on opacity {}`. Gegenstueck zu Morph,
// nur ohne Nachschwingen – Deckkraft ueber 1 gibt es nicht.
Behavior {
    NumberAnimation {
        duration: Appearance.fadeDuration
        easing.type: Easing.OutCubic
    }
}
