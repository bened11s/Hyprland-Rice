pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.system
import qs.modules.settings
import qs.modules.widgets

// Akkus aller Geraete fuer die aufgeklappte Notch (Uebersicht), unter den
// Systemwerten: je Geraet ein Chip mit Symbol, Batterie und Prozent. Klick
// oeffnet die Seite "Akku" im Einstellungs-Fenster (Verlauf, Kennzahlen).
// Ohne Akku – oder mit ausgeschalteter Akkuanzeige – ist die Reihe 0 hoch.
Row {
    id: root

    // Systemakku zuerst, dann die Geraete (schwaechster zuerst), hoechstens
    // fuenf – mehr passen nicht nebeneinander
    readonly property var batteries: {
        if (!Config.bar.battery)
            return [];
        const list = root.systemDevice ? [root.systemDevice] : [];
        return list.concat(Power.deviceBatteries).slice(0, 5);
    }
    readonly property var systemDevice: Power.hasSystemBattery ? Power.systemDevice : null

    spacing: 6
    height: root.batteries.length > 0 ? 30 : 0
    visible: root.batteries.length > 0

    Repeater {
        model: root.batteries

        Item {
            id: chip

            required property var modelData
            readonly property int percent: Math.round((chip.modelData?.percentage ?? 0) * 100)
            readonly property bool charging: Power.isCharging(chip.modelData)
            readonly property bool low: !chip.charging && chip.percent <= 20

            width: (root.width - root.spacing * (root.batteries.length - 1)) / root.batteries.length
            height: root.height

            Rectangle {
                anchors.fill: parent
                radius: 11
                color: chip.low ? Colors.alpha(Colors.error, 0.16)
                     : chipHover.hovered ? Colors.alpha(Colors.fgBackground, 0.1)
                     : Colors.alpha(Colors.fgBackground, 0.05)
            }

            Row {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.modelData?.isLaptopBattery ? "laptop" : Power.deviceIcon(chip.modelData)
                    color: chip.low ? Colors.error : Colors.primary
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 14
                }

                BatteryGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    bodyWidth: 16
                    bodyHeight: 9
                    percent: chip.percent
                    charging: chip.charging
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${chip.percent} %`
                    color: chip.low ? Colors.error : Colors.fgBackground
                    font.family: Config.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }

            HoverHandler {
                id: chipHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: {
                    BatteryHistory.focus(chip.modelData?.isLaptopBattery ? "" : (chip.modelData?.model ?? ""));
                    SettingsState.openPage("battery", {});
                }
            }
        }
    }
}
