import QtQuick

import qs.modules.widgets

import qs

// Schnellkachel: Desktop-Widgets ein-/ausblenden (Einstellung `hidden`).
// Ausgeblendet gibt es die Widgets nur beim Anordnen (SUPER+ALT+D) –
// sonst werden sie gar nicht erst gebaut und kosten nichts.
QuickTile {
    id: tile

    active: tile.plugin?.settings?.hidden !== true
    subtitle: tile.active ? I18n.tr("Sichtbar") : I18n.tr("Nur im Editor")
    icon: tile.active ? "widgets" : "visibility_off"

    onToggled: tile.plugin.set("hidden", tile.active)
}
