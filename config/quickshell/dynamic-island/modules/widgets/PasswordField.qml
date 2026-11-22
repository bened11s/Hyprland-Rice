pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Passwortfeld wie auf dem Sperrbildschirm (LockNotch): runde Pille mit
// einem Punkt je Zeichen statt Sternchen. `error` faerbt rot, `shake()`
// schuettelt, `checking` laesst die Punkte als Welle pulsieren. Tippen
// geht in ein unsichtbares TextInput; Fokus per forceActiveFocus().
FocusScope {
    id: field

    property string placeholder: I18n.tr("Passwort")
    property color fg: Colors.fgSurface
    property bool error: false
    property bool checking: false
    // Nicht-geheime Abfragen (polkit responseVisible) zeigen den Klartext
    property bool reveal: false
    readonly property alias text: input.text
    readonly property color stateColor: field.error ? Colors.error : field.fg
    signal accepted()

    function clear(): void {
        input.text = "";
    }

    function shake(): void {
        shakeAnim.restart();
    }

    implicitWidth: 260
    implicitHeight: 44
    activeFocusOnTab: true

    transform: Translate { id: shakeShift }

    SequentialAnimation {
        id: shakeAnim

        NumberAnimation { target: shakeShift; property: "x"; to: -12; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to: 10; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to: -7; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to: 4; duration: 60; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 70; easing.type: Easing.OutQuad }
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Colors.alpha(field.fg, input.activeFocus ? 0.09 : 0.06)
        border.width: 1
        // Wie im Lock: leer/Fehler deutlich, beim Tippen zurueckgenommen
        border.color: Colors.alpha(field.error ? Colors.error : input.activeFocus ? Colors.primary : field.fg,
                                   field.error ? 0.55 : input.activeFocus ? (input.text === "" ? 0.55 : 0.3) : 0.14)

        Behavior on border.color { ColorAnimation { duration: Appearance.fadeDuration } }
        Behavior on color { ColorAnimation { duration: Appearance.fadeDuration } }
    }

    TextInput {
        id: input

        anchors {
            fill: parent
            leftMargin: 18
            rightMargin: 18
        }
        focus: true
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        font.family: Config.font
        font.pixelSize: 14
        // Unsichtbar ausser bei `reveal` – sichtbar sind die Punkte
        color: field.reveal ? field.fg : "transparent"
        selectionColor: field.reveal ? Colors.alpha(Colors.primary, 0.35) : "transparent"
        selectedTextColor: color
        cursorVisible: field.reveal && activeFocus
        echoMode: field.reveal ? TextInput.Normal : TextInput.Password
        clip: true
        onAccepted: field.accepted()
    }

    PasswordDots {
        anchors.centerIn: parent
        width: parent.width - 32
        visible: !field.reveal
        count: input.text.length
        color: field.stateColor
        checking: field.checking
    }

    Text {
        anchors.centerIn: parent
        width: parent.width - 32
        horizontalAlignment: Text.AlignHCenter
        visible: input.text === "" && !field.checking
        text: field.placeholder
        color: Colors.alpha(field.fg, 0.38)
        font.family: Config.font
        font.pixelSize: 14
        elide: Text.ElideRight
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onPressed: input.forceActiveFocus()
    }
}
