pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.modules.services.config
import qs.modules.widgets
import qs.modules.settings.system
import qs.modules.services.user

Item {
    id: panel

    property real topOffset: 0
    property real cardRadius: 18
    property real inset: 2
    property bool active: false
    property var flow: null

    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    readonly property alias maxOuterHeight: panel.outerHeight

    implicitWidth: 440
    implicitHeight: buttons.y + buttons.height + 18

    // Fehlschlag: rot + schuetteln wie im Lock; Pruefen: Punkte als Welle
    property bool failed: false
    property bool checking: false
    // Zuletzt abgeschickte Antwort: Enter darf sie waehrend der Pruefung
    // nicht erneut senden (das Feld bleibt diesmal gefuellt)
    property string submittedText: ""

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: inset
        rightMargin: inset
    }
    y: topOffset

    // Per LazyPanel entsteht die Ansicht bereits aktiv – dann gibt es kein
    // Wechsel-Signal, die Startarbeit (Fokus, Suchfeld) wird nachgeholt
    Component.onCompleted: if (panel.active) Qt.callLater(panel.activeChanged)

    onActiveChanged: {
        password.clear();
        panel.failed = false;
        panel.checking = false;
        panel.submittedText = "";
        if (active)
            Qt.callLater(password.forceActiveFocus);
    }

    Keys.onEscapePressed: panel.flow?.cancelAuthenticationRequest()

    // Kopf wie ein Eintrag der Einstellungs-Leiste: Symbol im 38-px-Kreis,
    // daneben die polkit-Meldung (sagt schon, wofuer – kein eigener Titel)
    Rectangle {
        id: shield

        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 20
            topMargin: 18
        }
        width: 38
        height: 38
        radius: 19
        color: Colors.alpha(Colors.primary, 0.18)

        Text {
            anchors.centerIn: parent
            text: "shield_lock"
            color: Colors.primary
            font.family: "Material Symbols Outlined"
            font.pixelSize: 20
            // ungefuellt: gefuellt stanzt Material Symbols das Schloss als Loch aus
            font.variableAxes: { "wght": 500 }
        }
    }

    Column {
        id: heading

        anchors {
            left: shield.right
            right: parent.right
            leftMargin: 12
            rightMargin: 20
        }
        // Ein-/Zweizeiler mittig am Kreis, hoehere Bloecke buendig oben statt darueber hinaus
        y: shield.y + Math.max(0, (shield.height - height) / 2)
        spacing: 2

        Text {
            id: message

            width: parent.width
            text: panel.flow?.message || I18n.tr("Eine Anwendung benötigt zusätzliche Berechtigungen.")
            color: Colors.fgSurface
            font.family: Config.font
            font.pixelSize: 13
            // Die Meldung ist der freizugebende Befehl: lange Pfade umbrechen, nicht kuerzen
            wrapMode: Text.Wrap
            maximumLineCount: 6
            elide: Text.ElideRight
        }

        // Nur wenn nicht das eigene Konto gefragt ist (z. B. root)
        Text {
            width: parent.width
            visible: text !== ""
            text: panel.flow?.selectedIdentity && !panel.ownIdentity(panel.flow.selectedIdentity)
                ? I18n.tr("Als %1").arg(panel.flow.selectedIdentity.displayName) : ""
            color: Colors.fgSurfaceVariant
            font.family: Config.font
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    // Wie das Passwortfeld des Sperrbildschirms: Punkte-Pille
    PasswordField {
        id: password

        anchors {
            left: parent.left
            right: parent.right
            top: shield.bottom
            leftMargin: 20
            rightMargin: 20
            // Mehrzeilige Meldung ragt unter den Kreis
            topMargin: 16 + Math.max(0, heading.y + heading.height - shield.y - shield.height)
        }
        enabled: panel.flow?.isResponseRequired ?? false
        reveal: panel.flow?.responseVisible ?? false
        error: panel.failed
        checking: panel.checking
        placeholder: panel.checking ? ""
            : panel.flow?.isResponseRequired
                ? panel.promptText((panel.flow.inputPrompt ?? "").replace(/:\s*$/, ""))
                : I18n.tr("Authentifizierung wird vorbereitet…")
        onTextChanged: if (text !== "") panel.failed = false
        onAccepted: panel.submit()
    }

    Text {
        id: supplementary
        font.family: Config.font
        anchors {
            left: password.left
            right: password.right
            top: password.bottom
            topMargin: text !== "" ? 6 : 0
        }
        height: text !== "" ? 16 : 0
        horizontalAlignment: Text.AlignHCenter
        text: panel.flow?.supplementaryMessage || (panel.failed ? I18n.tr("Falsches Passwort") : "")
        color: panel.flow?.supplementaryIsError || panel.failed ? Colors.error : Colors.fgSurfaceVariant
        font.pixelSize: 11
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    // Textknoepfe wie in den Einstellungen: Abbrechen links, Bestaetigen rechts
    Item {
        id: buttons

        anchors {
            left: parent.left
            right: parent.right
            top: supplementary.bottom
            leftMargin: 20
            rightMargin: 20
            topMargin: 14
        }
        height: confirm.height

        // Beide gleich breit, egal wie lang die Beschriftung ist
        TextButton {
            id: cancel

            anchors.left: parent.left
            width: Math.max(cancel.implicitWidth, confirm.implicitWidth)
            tonal: true
            label: I18n.tr("Abbrechen")
            onClicked: panel.flow?.cancelAuthenticationRequest()
        }

        TextButton {
            id: confirm

            anchors.right: parent.right
            width: cancel.width
            filled: true
            label: I18n.tr("Bestätigen")
            enabled: (panel.flow?.isResponseRequired ?? false) && !panel.checking
            onClicked: panel.submit()
        }
    }

    Connections {
        target: panel.flow
        enabled: panel.active

        function onIsResponseRequiredChanged(): void {
            if (panel.flow?.isResponseRequired) {
                panel.checking = false;
                password.clear();
                Qt.callLater(password.forceActiveFocus);
            }
        }

        function onAuthenticationFailed(): void {
            panel.checking = false;
            panel.failed = true;
            password.clear();
            password.shake();
            Qt.callLater(password.forceActiveFocus);
        }
    }

    // polkit nennt das eigene Konto mal per Login, mal per Klarname
    function ownIdentity(id: var): bool {
        const name = id.displayName ?? "";
        return name === User.user || (User.name !== "" && name === User.name)
            || (id.string ?? "") === "unix-user:" + User.user;
    }

    // PAM fragt in der Systemsprache; das uebliche "Password" folgt der Shell-Sprache
    function promptText(prompt: string): string {
        return prompt === "" || /^passwor[dt]$/i.test(prompt) ? I18n.tr("Passwort") : prompt;
    }

    function submit(): void {
        if (!flow?.isResponseRequired)
            return;
        // Dieselbe Antwort nicht doppelt senden, solange polkit prueft
        if (panel.checking && password.text === panel.submittedText)
            return;

        panel.submittedText = password.text;
        flow.submit(password.text);
        panel.checking = true;
    }
}
