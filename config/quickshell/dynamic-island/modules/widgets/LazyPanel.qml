pragma ComponentBehavior: Bound
import QtQuick

// Ansicht der Notch, die erst beim Oeffnen gebaut wird (Launcher, Power,
// Untermenues, ...). Frueher lebten alle Ansichten dauerhaft – je Monitor –
// und wurden nur unsichtbar geschaltet: der Launcher durchsuchte schon beim
// Start alle Programme, das Steuerungs-Untermenue trug eine zweite komplette
// Settings-Karte samt Pollern.
//
//     LazyPanel {
//         id: launcher
//         open: notch.appsOpen
//         sourceComponent: LauncherPanel { topOffset: notch.launcherTop; active: true }
//     }
//
// Die Ansicht entsteht mit `active` bereits true – Startarbeit (Fokus,
// Suchfeld leeren) gehoert deshalb auch in ihr Component.onCompleted.
// Nur die Breite wird vorgegeben: die Hoehe bestimmt die Ansicht selbst.
Loader {
    id: root

    property bool open: false

    readonly property real outerWidth: root.item?.outerWidth ?? 0
    readonly property real outerHeight: root.item?.outerHeight ?? 0

    width: parent?.width ?? 0
    active: root.open
    visible: root.open
    opacity: root.open ? 1 : 0

    Fade on opacity {}
}
