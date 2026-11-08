pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

import qs.modules.services.audio
import qs.modules.services.brightness
import qs.modules.services.config
import qs.modules.services.core
import qs.modules.widgets

import qs

// OSD am rechten Bildschirmrand, mittig: senkrechte Regler fuer Lautstaerke
// und Helligkeit.
//
// Zwei Wege, es zu sehen:
//   Hover    Maus an den rechten Rand in der Bildschirmmitte – das Fenster
//            ist nur so hoch wie die Karte plus etwas Luft, und solange es
//            versteckt ist, nimmt es nur einen 4 px schmalen Streifen an der
//            Kante als Eingabe (mask). Alles andere faellt durch.
//   Aenderung  Lautstaerke, Stumm oder Helligkeit aendern sich (Tasten,
//            Mausrad auf der Settings-Pille) – dann blendet es fuer
//            Config.osd.hideDelay Sekunden ein.
//
// Die Karte dockt an der Kante an (Surface.dockedRight: Reverse-Rundung
// oben und unten), faehrt von rechts
// herein (Morph) und blendet dabei ein. Bei einer Aenderung erscheint sie nur
// auf dem fokussierten Monitor; der Helligkeitsregler stellt nur den
// Monitor, auf dem er sitzt (Brightness.setValueFor).
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win

        required property ShellScreen modelData

        readonly property bool enabled: Config.osd.enabled
        readonly property bool hovered: hover.hovered
        // Durch eine Aenderung ausgeloest, laeuft bis der Timer abgelaufen ist
        property bool flashed: false
        // Beim Start setzen die Dienste ihre Werte – das ist keine Aenderung
        property bool settled: false

        readonly property bool shown: win.enabled && ((win.hovered && Config.osd.hover) || win.flashed)

        readonly property string monitorName: win.modelData.name
        readonly property bool focused: Hyprland.focusedMonitor?.name === win.monitorName
        readonly property real brightness: Brightness.valueFor(win.monitorName)
        property real lastBrightness: -1

        readonly property real shadowRoom: 24 // Platz fuer den Schatten links/oben/unten

        // Nur der fokussierte Monitor zeigt eine Aenderung – sonst klappen
        // beide Bildschirme auf
        function flash(): void {
            if (!win.settled || !win.enabled || !win.focused)
                return;
            win.flashed = true;
            hideTimer.restart();
        }

        screen: win.modelData
        visible: win.enabled

        // Nur rechts angedockt: ohne oben/unten setzt der Compositor es mittig
        anchors.right: true
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dynamic-island-osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        implicitWidth: card.implicitWidth + win.shadowRoom
        implicitHeight: card.implicitHeight + win.shadowRoom * 2

        // Versteckt: nur der Streifen an der Kante ist Eingabeflaeche
        mask: Region {
            x: win.shown ? 0 : win.width - 4
            y: 0
            width: win.shown ? win.width : 4
            height: win.height
        }

        // Helligkeit nachlesen, solange das OSD offen ist
        DemandRequest {
            demand: Brightness.demand
            active: win.shown
        }

        Timer {
            id: settle

            interval: 2500
            running: true
            onTriggered: win.settled = true
        }

        Timer {
            id: hideTimer

            interval: Math.max(500, Config.osd.hideDelay * 1000)
            onTriggered: {
                if (!win.hovered)
                    win.flashed = false;
            }
        }

        onHoveredChanged: {
            if (!win.hovered)
                hideTimer.restart();
        }

        Connections {
            target: Audio

            function onVolumeChanged(): void { win.flash(); }
            function onMutedChanged(): void { win.flash(); }
        }

        // Helligkeit: nur, wenn sich der Wert DIESES Monitors geaendert hat
        onBrightnessChanged: {
            if (win.lastBrightness >= 0 && Brightness.readyFor(win.monitorName))
                win.flash();
            win.lastBrightness = win.brightness;
        }

        Item {
            anchors.fill: parent

            HoverHandler {
                id: hover
            }

            Surface {
                id: card

                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    // Angedockt: der rechte Rand liegt knapp ausserhalb, oben
                    // und unten waechst die Karte mit "Ohren" aus der Kante.
                    // Versteckt: ganz nach rechts aus dem Bild geschoben.
                    rightMargin: win.shown ? -card.borderWidth : -card.width - 12
                }
                dockedRight: true
                // Luft um die Regler: links/rechts je 11 px, oben/unten je 14 px
                implicitWidth: column.implicitWidth + 22
                implicitHeight: column.implicitHeight + 28
                opacity: win.shown ? 1 : 0

                // Dieselbe Optik wie die angedockte Notch: Rahmen-Schwarz,
                // flach, Kontur nur bei hellem Wallpaper, kein Schatten,
                // Schultern in Notch-Groesse
                baseColor: Appearance.notchColor
                lift: 0
                borderWidth: Appearance.notchBorder ? 1 : 0
                borderColor: Appearance.notchBorderColor
                shadow: false
                earRadius: Appearance.notchShoulderOpen

                Morph on anchors.rightMargin {}
                Fade on opacity {}

                Column {
                    id: column

                    anchors.centerIn: parent
                    spacing: 12

                    OsdSlider {
                        icon: Audio.muted ? "volume_off"
                            : Audio.volume >= 0.66 ? "volume_up"
                            : Audio.volume > 0 ? "volume_down" : "volume_mute"
                        value: Audio.volume
                        muted: Audio.muted
                        onMoved: value => Audio.setVolume(value)
                        onHandleTapped: Audio.toggleMute()
                    }

                    OsdSlider {
                        visible: Config.osd.brightness
                        icon: win.brightness >= 0.66 ? "brightness_7"
                            : win.brightness >= 0.33 ? "brightness_6" : "brightness_5"
                        value: win.brightness
                        interactive: Brightness.readyFor(win.monitorName)
                        onMoved: value => Brightness.setValueFor(win.monitorName, value)
                    }
                }
            }
        }
    }
}
