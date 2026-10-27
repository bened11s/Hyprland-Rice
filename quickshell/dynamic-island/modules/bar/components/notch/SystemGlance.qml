pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.system

// Kurze Systemwerte fuer die aufgeklappte Notch (Uebersicht): CPU, RAM,
// CPU- und GPU-Temperatur als gleich breite Chips. Die volle Karte steht im
// System-Untermenue (SUPER+I bzw. blaettern). SystemStats misst nur, solange
// die Uebersicht offen ist (Binding in Bar.qml).
Row {
    id: root

    readonly property real memShare: SystemStats.memTotal > 0 ? SystemStats.memUsed / SystemStats.memTotal : 0

    // Nur WELCHE Chips es gibt steht im Modell – das aendert sich fast nie.
    // Die Werte bindet jeder Chip selbst (entry()), sonst baute der Repeater
    // bei jedem 2-s-Takt von SystemStats alle Chips neu auf.
    // Als String gefuehrt: der aendert sich nur, wenn sich der Inhalt aendert
    // (ein neu gebautes Array waere jedes Mal ein "neues" Modell)
    readonly property string keyList: {
        const list = ["cpu", "mem"];
        if (SystemStats.cpuTemp > 0)
            list.push("cpuTemp");
        if (Power.hasSystemBattery && Config.bar.battery)
            list.push("battery");
        if (SystemStats.hasGpu && SystemStats.gpuTemp > 0)
            list.push("gpuTemp");
        return list.join(",");
    }
    readonly property var keys: root.keyList.split(",")

    function entry(key: string): var {
        switch (key) {
        case "cpu":
            return { icon: "developer_board", text: `${Math.round(SystemStats.cpuUsage * 100)} %`, warn: SystemStats.cpuUsage >= 0.9 };
        case "mem":
            return { icon: "memory", text: `${Math.round(root.memShare * 100)} %`, warn: root.memShare >= 0.9 };
        case "cpuTemp":
            return { icon: "thermostat", text: SystemStats.formatTemp(SystemStats.cpuTemp), warn: SystemStats.cpuTemp >= 80 };
        case "battery":
            return { icon: Power.batteryIcon, text: `${Power.percent} %`, warn: Power.percent <= 20 && !Power.charging };
        default:
            return { icon: "videogame_asset", text: SystemStats.formatTemp(SystemStats.gpuTemp), warn: SystemStats.gpuTemp >= 85 };
        }
    }

    spacing: 6
    height: 30

    Repeater {
        model: root.keys

        Item {
            id: chip

            required property string modelData
            readonly property var info: root.entry(chip.modelData)

            width: (root.width - root.spacing * (root.keys.length - 1)) / root.keys.length
            height: root.height

            Rectangle {
                anchors.fill: parent
                radius: 11
                color: chip.info.warn ? Colors.alpha(Colors.error, 0.16)
                                           : Colors.alpha(Colors.fgBackground, 0.05)
            }

            Row {
                anchors.centerIn: parent
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.info.icon
                    color: chip.info.warn ? Colors.error : Colors.primary
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 14
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.info.text
                    color: chip.info.warn ? Colors.error : Colors.fgBackground
                    font.family: Config.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
