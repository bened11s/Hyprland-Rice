pragma ComponentBehavior: Bound

import QtQuick

import qs
import qs.modules.services.config

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
    implicitHeight: 238

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
        password.text = "";
        if (active)
            Qt.callLater(password.forceActiveFocus);
    }

    Keys.onEscapePressed: panel.flow?.cancelAuthenticationRequest()

    Text {
        id: shield

        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 20
            topMargin: 14
        }
        text: "shield_lock"
        color: Colors.primary
        font.family: "Material Symbols Outlined"
        font.pixelSize: 27
        font.variableAxes: ({ wght: 600 })
    }

    Text {
        font.family: Config.font
        anchors {
            left: shield.right
            right: parent.right
            top: parent.top
            leftMargin: 12
            rightMargin: 20
            topMargin: 13
        }
        text: I18n.tr("Authentifizierung erforderlich")
        color: Colors.fgBackground
        font.pixelSize: 16
        font.weight: Font.DemiBold
    }

    Text {
        id: message
        font.family: Config.font

        anchors {
            left: parent.left
            right: parent.right
            top: shield.bottom
            leftMargin: 20
            rightMargin: 20
            topMargin: 10
        }
        text: panel.flow?.message ?? I18n.tr("Eine Anwendung benötigt zusätzliche Berechtigungen.")
        color: Colors.fgSurfaceVariant
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }

    Text {
        id: identity
        font.family: Config.font

        anchors {
            left: message.left
            right: message.right
            top: message.bottom
            topMargin: 7
        }
        text: panel.flow?.selectedIdentity
            ? I18n.tr("Als %1").arg(panel.flow.selectedIdentity.displayName) : ""
        color: Colors.alpha(Colors.fgSurfaceVariant, 0.72)
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    Rectangle {
        id: inputBox

        anchors {
            left: parent.left
            right: parent.right
            top: identity.bottom
            leftMargin: 20
            rightMargin: 20
            topMargin: 10
        }
        height: 42
        radius: 12
        color: Colors.surfaceContainer
        border.width: password.activeFocus ? 1 : 0
        border.color: Colors.primary

        TextInput {
            id: password
            font.family: Config.font

            anchors {
                fill: parent
                leftMargin: 13
                rightMargin: 13
            }
            enabled: panel.flow?.isResponseRequired ?? false
            verticalAlignment: TextInput.AlignVCenter
            color: Colors.fgSurface
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            font.pixelSize: 12
            echoMode: panel.flow?.responseVisible ? TextInput.Normal : TextInput.Password
            passwordCharacter: "*"
            clip: true

            Keys.onReturnPressed: panel.submit()
            Keys.onEnterPressed: panel.submit()

            Text {
                anchors.fill: parent
                visible: password.text === ""
                text: panel.flow?.isResponseRequired
                    ? (panel.flow.inputPrompt || I18n.tr("Passwort"))
                    : I18n.tr("Authentifizierung wird vorbereitet...")
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.65)
                font: password.font
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    Text {
        font.family: Config.font
        anchors {
            left: inputBox.left
            right: inputBox.right
            top: inputBox.bottom
            topMargin: 6
        }
        height: 16
        text: panel.flow?.supplementaryMessage ?? ""
        color: panel.flow?.supplementaryIsError ? Colors.error : Colors.fgSurfaceVariant
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    Rectangle {
        id: cancelButton

        anchors {
            right: confirmButton.left
            bottom: parent.bottom
            rightMargin: 9
            bottomMargin: 14
        }
        width: 88
        height: 36
        radius: 11
        color: cancelHover.hovered ? Colors.surfaceBright : Colors.surfaceContainer

        Text {
            font.family: Config.font
            anchors.centerIn: parent
            text: I18n.tr("Abbrechen")
            color: Colors.fgSurface
            font.pixelSize: 11
            font.weight: Font.Medium
        }

        HoverHandler {
            id: cancelHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: panel.flow?.cancelAuthenticationRequest()
        }
    }

    Rectangle {
        id: confirmButton

        readonly property bool ready: panel.flow?.isResponseRequired ?? false

        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: 20
            bottomMargin: 14
        }
        width: 112
        height: 36
        radius: 11
        color: ready ? (confirmHover.hovered ? Colors.shade(Colors.primary, 0.08) : Colors.primary)
                     : Colors.alpha(Colors.primary, 0.35)

        Text {
            font.family: Config.font
            anchors.centerIn: parent
            text: I18n.tr("Bestätigen")
            color: Colors.fgPrimary
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        HoverHandler {
            id: confirmHover
            enabled: confirmButton.ready
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            enabled: confirmButton.ready
            onTapped: panel.submit()
        }
    }

    Connections {
        target: panel.flow
        enabled: panel.active

        function onIsResponseRequiredChanged(): void {
            if (panel.flow?.isResponseRequired) {
                password.text = "";
                Qt.callLater(password.forceActiveFocus);
            }
        }

        function onAuthenticationFailed(): void {
            password.text = "";
            Qt.callLater(password.forceActiveFocus);
        }
    }

    function submit(): void {
        if (!flow?.isResponseRequired)
            return;

        flow.submit(password.text);
        password.text = "";
    }
}
