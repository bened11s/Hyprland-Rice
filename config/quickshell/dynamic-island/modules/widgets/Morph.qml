import QtQuick

import qs

// Groessen-Animation der Pillen und Karten – mit Nachschwingen.
//
//     Morph on width {}
//     Morph on height {}
//
// Ein Behavior, das seine Kurve aus Appearance holt: steht der Bounce auf
// "aus", wird daraus ein normales OutCubic. So haben alle Karten dieselbe
// Bewegung, und eine Aenderung an einer Stelle gilt ueberall.
//
// Nicht fuer Werte benutzen, die bis 0 gehen (z.B. Breiten mit
// `visible: width > 0`) – der Overshoot schiesst sonst ins Negative.
Behavior {
    NumberAnimation {
        duration: Appearance.morphDuration
        easing.type: Appearance.overshoot > 0 ? Easing.OutBack : Easing.OutCubic
        easing.overshoot: Appearance.overshoot
    }
}
