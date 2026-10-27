pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.system

import qs
import qs.modules.services.config

// Inhalt der System-Karte: CPU-Name, Auslastung von CPU/GPU/VRAM/RAM/Platte,
// weitere Temperaturen, Geraete-Akkus. Genutzt von der System-Pille
// (Insel-Layout) und vom System-Untermenue der Notch (SystemPanel).
//
// Misst nur, solange SystemStats.watching an ist – das schaltet Bar.qml
// zentral (ein Binding fuer alle Verbraucher).
Column {
    id: card

    spacing: 2

    Text {
        font.family: Config.font
        width: parent.width
        text: SystemStats.cpuName !== "" ? SystemStats.cpuName : "System"
        color: Colors.fgSurfaceVariant
        font.pixelSize: 10
        font.weight: Font.Medium
        elide: Text.ElideRight
        bottomPadding: 4
    }

    StatRow {
        width: parent.width
        icon: "developer_board"
        label: "CPU"
        value: SystemStats.cpuUsage
        warn: SystemStats.cpuTemp >= 80 || SystemStats.cpuUsage >= 0.9
        detail: `${Math.round(SystemStats.cpuUsage * 100)} %` +
                (SystemStats.cpuTemp > 0 ? ` · ${SystemStats.formatTemp(SystemStats.cpuTemp)}` : "")
    }

    StatRow {
        width: parent.width
        visible: SystemStats.hasGpu
        icon: "monitoring"
        label: "GPU"
        value: SystemStats.gpuUsage
        warn: SystemStats.gpuTemp >= 85 || SystemStats.gpuUsage >= 0.9
        detail: `${Math.round(SystemStats.gpuUsage * 100)} %` +
                (SystemStats.gpuTemp > 0 ? ` · ${SystemStats.formatTemp(SystemStats.gpuTemp)}` : "")
    }

    StatRow {
        width: parent.width
        visible: SystemStats.vramTotal > 0
        icon: "memory"
        label: "VRAM"
        value: SystemStats.vramTotal > 0 ? SystemStats.vramUsed / SystemStats.vramTotal : 0
        detail: `${SystemStats.formatBytes(SystemStats.vramUsed)} / ${SystemStats.formatBytes(SystemStats.vramTotal)}`
    }

    StatRow {
        width: parent.width
        icon: "memory"
        label: "RAM"
        value: SystemStats.memTotal > 0 ? SystemStats.memUsed / SystemStats.memTotal : 0
        warn: SystemStats.memTotal > 0 && SystemStats.memUsed / SystemStats.memTotal >= 0.9
        detail: `${SystemStats.formatBytes(SystemStats.memUsed)} / ${SystemStats.formatBytes(SystemStats.memTotal)}`
    }

    StatRow {
        width: parent.width
        visible: SystemStats.diskTotal > 0
        icon: "hard_drive"
        label: I18n.tr("Platte")
        value: SystemStats.diskTotal > 0 ? SystemStats.diskUsed / SystemStats.diskTotal : 0
        detail: I18n.tr("%1 frei").arg(SystemStats.formatBytes(SystemStats.diskFree))
    }

    // Was sonst noch Temperatur hat, in einer Zeile
    Text {
        font.family: Config.font
        width: parent.width
        topPadding: 4
        visible: text !== ""
        text: {
            const parts = [];
            for (const t of SystemStats.nvmeTemps)
                parts.push(`SSD ${Math.round(t)} °C`);
            if (SystemStats.waterTemp > 0)
                parts.push(I18n.tr("Wasser %1 °C").arg(Math.round(SystemStats.waterTemp)));
            return parts.join("  ·  ");
        }
        color: Colors.fgSurfaceVariant
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    // Geraete-Akkus: am Desktop steht der erste schon in der Pille,
    // hier stehen sie mit Namen
    Text {
        font.family: Config.font
        width: parent.width
        visible: text !== ""
        text: {
            const parts = [];
            for (const d of Power.deviceBatteries)
                parts.push(`${Power.deviceName(d)} ${Math.round(d.percentage * 100)} %`);
            return parts.join("  ·  ");
        }
        color: Colors.fgSurfaceVariant
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    Text {
        font.family: Config.font
        width: parent.width
        topPadding: 2
        visible: Power.degraded
        text: I18n.tr("Leistung gedrosselt: %1").arg(Power.degradedReason)
        color: Colors.error
        font.pixelSize: 10
        elide: Text.ElideRight
    }
}
