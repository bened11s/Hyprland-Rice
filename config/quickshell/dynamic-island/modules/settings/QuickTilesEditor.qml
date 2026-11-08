pragma ComponentBehavior: Bound
import QtQuick

// Kachel-Editor im Einstellungs-Menue (`editor: "quick"`): die echten
// Kacheln der Steuerung im Bearbeitungsmodus, Vorbild Android 16 (siehe
// SettingsTiles / edit/QuickEdit). Ersetzt den frueheren Chip-Editor.
//
// SettingsTiles kommt per URL statt per Import: es importiert selbst
// qs.modules.settings (SettingsState), ein Import von hier aus waere ein
// Kreis zwischen den beiden Modulen.
Item {
    id: editor

    implicitHeight: tiles.item?.implicitHeight ?? 0

    Loader {
        id: tiles

        width: parent.width
        Component.onCompleted: tiles.setSource(Qt.resolvedUrl("../bar/components/settings/SettingsTiles.qml"), { editable: true })
    }
}
