import QtQuick
import QtQuick.Layouts

import qs
import qs.modules.services.config

// Der kleine "Warteschlange"-Hinweis in der Akzentfarbe: ein Titel, den man
// von Hand in die Warteschlange gelegt hat, statt aus der Playlist zu kommen
// (QueueRow, beide Varianten).
Rectangle {
    Layout.preferredWidth: tagText.implicitWidth + 8
    Layout.preferredHeight: 12

    radius: height / 2
    color: Colors.alpha(Colors.primary, 0.16)

    Text {
        id: tagText

        anchors.centerIn: parent
        font.family: Config.font
        text: I18n.tr("Warteschlange")
        color: Colors.primary
        font.pixelSize: 8
        font.weight: Font.DemiBold
    }
}
