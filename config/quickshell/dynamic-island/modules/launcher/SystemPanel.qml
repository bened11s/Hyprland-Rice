pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.bar.components.stats

// Untermenue "System" der Notch: dieselbe Karte wie die System-Pille.
// SystemStats misst, solange die Ansicht offen ist (Binding in Bar.qml).
// Aufruf: SUPER+I, `>system`, Blaettern.
ViewPanel {
    id: root

    title: I18n.tr("System")
    icon: "monitoring"
    contentWidth: 340
    contentHeight: card.implicitHeight

    StatsCard {
        id: card

        width: parent.width
    }
}
