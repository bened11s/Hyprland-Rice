pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.media
import qs.modules.bar.components.mediaPlayer

// Untermenue "Medien" der Notch: dieselbe Ansicht wie die aufgeklappte
// Medien-Pille – Player-Auswahl oben, Cover mit Visualiser-Ring, Titel,
// Fortschritt, Transport. Aufruf: SUPER+M, `>medien`, Blaettern.
ViewPanel {
    id: root

    title: I18n.tr("Medien")
    icon: "music_note"
    contentWidth: 380
    contentHeight: Media.available ? media.outerHeight : 60
    maxContentHeight: Math.max(60, media.outerHeight)

    // Zeilen (Player-Auswahl, Titel, Fortschritt) nutzen die volle Breite,
    // das Cover ist gedeckelt – sonst wuerde es in der breiten Karte riesig
    MediaPanel {
        id: media

        topOffset: 0
        padding: 0
        maxCoverSize: 190
        tint: Appearance.notchLayout ? Appearance.notchColor : Colors.background
        visible: Media.available
    }

    Text {
        anchors.centerIn: parent
        visible: !Media.available
        text: I18n.tr("Nichts spielt gerade")
        color: Colors.fgSurfaceVariant
        font.family: Config.font
        font.pixelSize: 12
    }
}
