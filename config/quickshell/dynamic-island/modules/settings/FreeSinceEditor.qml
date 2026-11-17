pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.plugins
import qs.modules.services.system

// Startdatum des Zaehlers "Microslopfrei seit" (meta.editor "freesince").
//
// Geraetespezifisch: das Feld gilt nur fuer diesen Rechner (shell.json).
// Format JJJJ-MM-TT, leer heisst "nimm das Installationsdatum dieses
// Geraets" (SystemStats). Rechts daneben steht die Tageszahl, damit man
// sofort sieht, ob das Datum passt – bei leerem Feld ist das die
// automatische Zahl.
Item {
    id: editor

    readonly property string typed: input.text.trim()
    // Kann beim ersten Laden noch fehlen -> wie "leer" behandeln
    readonly property string saved: Config.notch.freeSince ?? ""

    // Startdatum nie mit der Uhrzeit von heute verwechseln: daysSince rechnet
    // ab Mitternacht des Tages, deshalb kommen ganze Tage heraus
    readonly property int previewDays: editor.typed === "" ? SystemStats.freeDays
                                                           : SystemStats.daysSince(editor.typed)

    implicitHeight: 32

    // Nur ein echtes Datum uebernehmen, sonst zurueck auf den gespeicherten Wert
    function commit(): void {
        const v = editor.typed;
        if (/^\d{4}-\d{2}-\d{2}$/.test(v) && !isNaN(new Date(v + "T00:00:00").getTime())) {
            if (v !== editor.saved)
                Plugins.set("notch", "freeSince", v);
        } else {
            input.text = editor.saved;
        }
    }

    function resetAuto(): void {
        if (editor.saved !== "")
            Plugins.set("notch", "freeSince", "");
        input.text = "";
    }

    Component.onCompleted: input.text = editor.saved

    // Von aussen geaendert (Automatisch, anderes Geraet, Datei von Hand):
    // nur nachziehen, wenn gerade niemand tippt
    Connections {
        target: Config.notch

        function onFreeSinceChanged(): void {
            if (!input.activeFocus && input.text !== editor.saved)
                input.text = editor.saved;
        }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Rectangle {
            id: box

            width: 132
            height: 28
            radius: 8
            color: Colors.alpha(Colors.fgSurface, 0.06)
            border.width: 1
            border.color: input.activeFocus ? Colors.alpha(Colors.primary, 0.5) : "transparent"

            Behavior on border.color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }

            TextInput {
                id: input

                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                }
                verticalAlignment: TextInput.AlignVCenter
                font.family: Config.font
                font.pixelSize: 12
                color: Colors.fgBackground
                selectionColor: Colors.alpha(Colors.primary, 0.35)
                clip: true
                onAccepted: editor.commit()
                onActiveFocusChanged: if (!activeFocus) editor.commit()
                Keys.onEscapePressed: event => {
                    input.text = editor.saved;
                    input.focus = false;
                    event.accepted = true;
                }

                Text {
                    anchors.fill: parent
                    visible: input.text === ""
                    text: I18n.tr("JJJJ-MM-TT")
                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                    font: input.font
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: editor.previewDays >= 0 ? I18n.tr("%1 Tage").arg(editor.previewDays)
                                          : I18n.tr("kein Datum")
            color: Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 11
        }

        // Zurueck auf das Installationsdatum dieses Geraets
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: editor.saved !== ""
            implicitWidth: autoText.implicitWidth + 22
            implicitHeight: 24
            radius: height / 2
            color: autoHover.hovered ? Colors.alpha(Colors.primary, 0.18)
                                     : Colors.alpha(Colors.fgSurface, 0.06)

            Behavior on color {
                ColorAnimation { duration: 120 }
            }

            Text {
                id: autoText

                anchors.centerIn: parent
                text: I18n.tr("Automatisch")
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 11
            }

            HoverHandler {
                id: autoHover
            }

            TapHandler {
                onTapped: editor.resetAuto()
            }
        }
    }
}
