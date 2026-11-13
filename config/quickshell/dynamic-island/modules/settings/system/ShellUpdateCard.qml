pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config
import qs.modules.services.system

// Abschnitt "Updates" der Info-Seite (SystemEditor) fuer die Shell selbst,
// also das Git-Repo (ShellUpdate). Zeilen im Behaelter: der Stand der
// Pruefung mit "Nach Updates suchen" / "Aktualisieren" (shellupdate.sh,
// abgekoppelt), die neuen Commits des Upstreams (scrollt ab listMax), der
// Fehlertext von git, falls der Pull abgelehnt wurde, die eigenen
// Aenderungen (zugeklappt) und "Shell neu starten".
SectionCard {
    id: card

    readonly property int listMax: 204

    readonly property bool checking: ShellUpdate.checking
    readonly property bool updating: ShellUpdate.updating
    readonly property bool done: ShellUpdate.updateDone && !card.updating
    readonly property bool failed: ShellUpdate.updateFailed
                                 || (ShellUpdate.checkState === "error" && !card.updating && !ShellUpdate.updateDone)
    readonly property int behind: ShellUpdate.behind
    readonly property bool hasList: card.behind > 0 && ShellUpdate.incoming.length > 0
    readonly property bool hasError: ShellUpdate.updateError !== "" && (ShellUpdate.updateFailed || ShellUpdate.buildWarned) && !card.updating

    readonly property string statusText: {
        if (card.updating) {
            switch (ShellUpdate.updateStep) {
            case "build": return I18n.tr("Baue CLI-Helfer… (kann dauern)");
            case "hypr": return I18n.tr("Lade Hyprland neu…");
            case "restart": return I18n.tr("Starte Shell neu…");
            default: return I18n.tr("Lade Updates herunter…");
            }
        }
        if (ShellUpdate.updateFailed)
            return I18n.tr("Update fehlgeschlagen");
        if (card.done) {
            if (ShellUpdate.updatePulled === 1)
                return I18n.tr("Aktualisiert – 1 Commit übernommen");
            return I18n.tr("Aktualisiert – %1 Commits übernommen").arg(ShellUpdate.updatePulled);
        }
        if (card.checking)
            return I18n.tr("Suche nach Updates…");
        if (ShellUpdate.checkState === "error")
            return I18n.tr("Prüfung fehlgeschlagen");
        if (!ShellUpdate.loaded)
            return I18n.tr("Lade…");
        if (card.behind === 1)
            return I18n.tr("1 neuer Commit");
        if (card.behind > 1)
            return I18n.tr("%1 neue Commits").arg(card.behind);
        if (ShellUpdate.lastCheck === 0)
            return I18n.tr("Noch nicht geprüft");
        return I18n.tr("Shell ist aktuell");
    }

    readonly property string detailText: {
        if (card.updating || ShellUpdate.updateFailed)
            return "";
        if (card.done)
            return ShellUpdate.commit !== "" ? I18n.tr("Stand %1 · %2").arg(ShellUpdate.commit).arg(ShellUpdate.commitAge) : "";
        if (card.checking)
            return "";
        if (ShellUpdate.checkState === "error")
            return ShellUpdate.checkError;
        if (!ShellUpdate.loaded)
            return "";
        const parts = [];
        if (ShellUpdate.upstream !== "")
            parts.push(ShellUpdate.upstream);
        if (ShellUpdate.ahead === 1)
            parts.push(I18n.tr("1 eigener Commit"));
        else if (ShellUpdate.ahead > 1)
            parts.push(I18n.tr("%1 eigene Commits").arg(ShellUpdate.ahead));
        if (ShellUpdate.lastCheck > 0)
            parts.push(I18n.tr("geprüft %1").arg(Qt.formatTime(new Date(ShellUpdate.lastCheck), "HH:mm")));
        return parts.join("  ·  ");
    }

    // git-Fehler, bei dem eigene Aenderungen oder Commits im Weg stehen
    readonly property bool conflictHint: /overwritten|local changes|fast-forward|diverg|stash|commit your changes|überschrieben|lokale Änderungen|Vorspulen/i.test(ShellUpdate.updateError)

    title: I18n.tr("Updates")

    // Stand und Knoepfe; in schmalen Fenstern rutschen die Knoepfe unter den Text
    Item {
        id: statusRow

        readonly property bool narrow: width < 560

        width: parent.width
        height: (narrow ? statusColumn.implicitHeight + 10 + actions.height : Math.max(statusColumn.implicitHeight, actions.height)) + 26

        Column {
            id: statusColumn

            x: 16
            y: statusRow.narrow ? 13 : (parent.height - implicitHeight) / 2
            width: (statusRow.narrow ? parent.width : actions.x) - 32
            spacing: 3

            Text {
                width: parent.width
                text: I18n.tr("Shell-Updates")
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: card.statusText + (card.detailText !== "" ? "  ·  " + card.detailText : "")
                color: card.failed ? Colors.error : Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 11
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }
        }

        Row {
            id: actions

            x: statusRow.narrow ? 16 : parent.width - width - 16
            y: statusRow.narrow ? statusColumn.y + statusColumn.implicitHeight + 10 : (parent.height - height) / 2
            spacing: 8

            TextButton {
                label: I18n.tr("Nach Updates suchen")
                enabled: !card.checking && !card.updating
                onClicked: ShellUpdate.check(true)
            }

            TextButton {
                visible: ShellUpdate.canUpdate || card.updating
                label: card.updating ? I18n.tr("Läuft…") : I18n.tr("Aktualisieren")
                filled: true
                enabled: ShellUpdate.canUpdate
                onClicked: ShellUpdate.update()
            }
        }

        Divider {}
    }

    // Neue Commits: Betreff links, Hash und Alter rechts
    Item {
        width: parent.width
        visible: card.hasList
        height: Math.min(card.listMax, list.contentHeight)
        clip: true

        ListView {
            id: list

            anchors.fill: parent
            cacheBuffer: 2000
            boundsBehavior: Flickable.StopAtBounds
            model: ShellUpdate.incoming

            delegate: Item {
                id: entry

                required property var modelData

                width: list.width
                height: 34

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 16
                        right: whenLabel.left
                        rightMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    text: entry.modelData.subject
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                Text {
                    id: whenLabel

                    anchors {
                        right: parent.right
                        rightMargin: 16
                        verticalCenter: parent.verticalCenter
                    }
                    width: Math.min(implicitWidth, entry.width * 0.4)
                    text: entry.modelData.hash + "  ·  " + entry.modelData.when
                    color: Colors.fgSurfaceVariant
                    font.family: Config.font
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }
        }

        Divider {}
    }

    // Fehlertext von git/cargo (Pull abgelehnt, Build gescheitert)
    Item {
        width: parent.width
        visible: card.hasError
        height: errorColumn.implicitHeight + 24

        Column {
            id: errorColumn

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                leftMargin: 16
                rightMargin: 16
                topMargin: 12
            }
            spacing: 6

            Text {
                width: parent.width
                visible: ShellUpdate.buildWarned && !ShellUpdate.updateFailed
                text: I18n.tr("Die Rust-Helfer konnten nicht neu gebaut werden – die alten bleiben. Später ./install.sh ausführen.")
                color: Colors.fgSurface
                font.family: Config.font
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                text: ShellUpdate.updateError
                color: Colors.error
                font.family: Config.font
                font.pixelSize: 11
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            Text {
                width: parent.width
                visible: ShellUpdate.updateFailed && card.conflictHint
                text: I18n.tr("Eigene Änderungen an diesen Dateien zuerst sichern (git stash) – siehe README, Abschnitt „Updating“.")
                color: Colors.fgSurfaceVariant
                font.family: Config.font
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }

        Divider {}
    }


    Item {
        width: parent.width
        height: 56

        Text {
            anchors {
                left: parent.left
                leftMargin: 16
                right: restartButton.left
                rightMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: I18n.tr("Shell neu starten")
            color: Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 13
            elide: Text.ElideRight
        }

        TextButton {
            id: restartButton

            anchors {
                right: parent.right
                rightMargin: 16
                verticalCenter: parent.verticalCenter
            }
            label: I18n.tr("Neu starten")
            enabled: !card.updating
            onClicked: ShellUpdate.restart()
        }
    }
}
