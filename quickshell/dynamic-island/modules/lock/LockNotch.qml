pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell

import qs
import qs.modules.widgets
import qs.modules.bar.components.notch
import qs.modules.services.config
import qs.modules.services.notifications
import qs.modules.services.system

// Die Notch des Sperrbildschirms. Sie startet genau so, wie die Notch der
// Leiste eingeklappt aussieht, und wird zum Passwortfeld, sobald man tippt:
//
//   eingeklappt   Schloss, daneben ggf. Feststelltaste und Nachrichten
//   aufgeklappt   Avatar | Feld mit einem Punkt je Zeichen | Status-Symbol
//
// Aufklappen: tippen oder mit der Maus ueber die Notch fahren.
//
// Falsches Passwort: sie schuettelt sich. Richtiges: das Schloss geht auf,
// sie klappt wieder ein und uebergibt an die Notch der Leiste darunter.
Item {
    id: notch

    required property LockContext context
    property bool shown: false
    property bool leaving: false
    // Wird vor `leaving` gesetzt: die Dauern stehen schon um, wenn die
    // Ziele wechseln (siehe LockScreen.qml)
    property bool exitMode: false
    // Beim Abgang: so lange klappt sie ein und blendet aus. Darunter liegt
    // im Desktop-Foto die Notch der Leiste an derselben Stelle.
    property int fadeDuration: Appearance.morphDuration

    // Unter dem Zeiger offen; nach dem Verlassen kurz nachhalten, damit sie
    // nicht flattert, wenn der Zeiger knapp an der Kante entlangfaehrt
    property bool hoverOpen: false
    // Auf den anderen Monitoren bleibt sie eingeklappt, auch waehrend getippt wird
    property bool active: true
    readonly property bool open: !notch.leaving && notch.shown && notch.active
                                 && (notch.context.phase !== "idle" || notch.hoverOpen)
    readonly property bool hasMessage: notch.open && notch.context.message !== ""

    readonly property bool showCount: Config.lock.notifications && Notifications.count > 0
    // Akkustand nur mit Systemakku (Laptop) – Maus- und Headset-Akkus
    // gehoeren nicht auf den Sperrbildschirm. Beschreibbar fuer Tests.
    property bool showBattery: Power.hasSystemBattery
    property int batteryPercent: Power.percent
    property bool batteryCharging: Power.charging
    readonly property color batteryColor: notch.batteryCharging ? Colors.primary
                                        : notch.batteryPercent <= 15 ? Colors.error
                                        : notch.fg
    // Eingeklappt so breit wie der Inhalt. Vor dem Erscheinen so breit wie
    // die eingeklappte Notch der Leiste, aus der sie hervorgeht.
    readonly property real closedWidth: notch.shown ? Math.max(84, compactRow.implicitWidth + 40) : 196
    readonly property real closedHeight: 32
    readonly property real openWidth: 400
    readonly property real openHeight: notch.hasMessage ? 112 : 88

    readonly property color fg: Appearance.darkText ? Colors.fgBackground : "#ffffff"
    readonly property color stateColor: notch.context.phase === "failed" ? Colors.error
                                      : notch.context.phase === "success" ? Colors.primary
                                      : notch.fg

    width: notch.open ? notch.openWidth : notch.closedWidth
    height: notch.open ? notch.openHeight : notch.closedHeight

    // Wie Morph, nur beim Abgang ohne Nachschwingen: dort soll sie ruhig
    // zusammengehen, nicht noch einmal federn
    Behavior on width {
        NumberAnimation {
            duration: notch.exitMode ? notch.fadeDuration : Appearance.morphDuration
            easing.type: notch.exitMode ? Easing.InOutCubic
                       : Appearance.overshoot > 0 ? Easing.OutBack : Easing.OutCubic
            easing.overshoot: Appearance.overshoot
        }
    }
    Behavior on height {
        NumberAnimation {
            duration: notch.exitMode ? notch.fadeDuration : Appearance.morphDuration
            easing.type: notch.exitMode ? Easing.InOutCubic
                       : Appearance.overshoot > 0 ? Easing.OutBack : Easing.OutCubic
            easing.overshoot: Appearance.overshoot
        }
    }

    opacity: notch.leaving ? 0 : 1

    Behavior on opacity {
        NumberAnimation { duration: notch.fadeDuration; easing.type: Easing.InCubic }
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                hoverClose.stop();
                notch.hoverOpen = true;
            } else {
                hoverClose.restart();
            }
        }
    }

    Timer {
        id: hoverClose

        interval: 450
        onTriggered: notch.hoverOpen = false
    }

    // ---- Schuetteln bei Fehlschlag ----
    transform: Translate { id: shakeShift }

    Connections {
        target: notch.context

        function onShakesChanged(): void {
            shake.restart();
        }
    }

    SequentialAnimation {
        id: shake

        NumberAnimation { target: shakeShift; property: "x"; to: -16; duration: 55; easing.type: Easing.OutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to: 13; duration: 80; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to: -9; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to: 5; duration: 60; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to: 0; duration: 70; easing.type: Easing.OutQuad }
    }

    // ---- Form ----
    Surface {
        id: pill

        anchors.fill: parent
        maxRadius: notch.open ? 30 : Appearance.radius
        baseColor: Appearance.notchColor
        lift: 0
        borderWidth: Appearance.notchBorder ? 1 : 0
        borderColor: Appearance.notchBorderColor
        docked: true
        shoulder: shoulderLeft.size
        shadowStrength: notch.open ? 1 : 0

        Behavior on shadowStrength {
            NumberAnimation { duration: Appearance.morphDuration * 0.65; easing.type: Easing.OutCubic }
        }

        // -- eingeklappt --
        Item {
            id: compact

            anchors.fill: parent
            opacity: !notch.open && !notch.leaving ? 1 : 0
            visible: opacity > 0

            Fade on opacity {}

            // Schloss in der Mitte, Feststelltaste, Akku und Nachrichten
            // ruecken als Gruppe daneben – die Notch ist so breit wie das,
            // was sie zeigt
            Row {
                id: compactRow

                anchors.centerIn: parent
                spacing: 12

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: notch.context.capsLock
                    text: "keyboard_capslock"
                    size: 16
                    color: Colors.tertiary
                }

                // Akku: Zahl + liegende Batterie, Fuellung nach Ladestand;
                // beim Laden Blitz davor und Fuellung im Akzent, unter 15 % rot
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    visible: notch.showBattery

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: notch.batteryCharging
                            text: "bolt"
                            size: 14
                            color: Colors.primary
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: notch.batteryPercent
                            color: notch.batteryCharging ? notch.fg : notch.batteryColor
                        font.family: Config.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                    }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Rectangle {
                            width: 20
                            height: 11
                            radius: 3.5
                            color: "transparent"
                            border.width: 1.5
                            border.color: Colors.alpha(notch.fg, 0.55)

                            Rectangle {
                                x: 2.5
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(2, (parent.width - 5) * Math.min(100, notch.batteryPercent) / 100)
                                height: parent.height - 5
                                radius: 1.5
                                color: notch.batteryColor
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: 4
                            radius: 1
                            color: Colors.alpha(notch.fg, 0.55)
                        }
                    }
                }

                LockGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 13
                    color: notch.fg
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    visible: notch.showCount

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 3.5
                        color: Colors.primary
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Notifications.count
                        color: notch.fg
                        font.family: Config.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }

        // -- aufgeklappt --
        Item {
            id: full

            anchors {
                fill: parent
                topMargin: 14
                leftMargin: 18
                rightMargin: 18
                bottomMargin: 14
            }
            opacity: notch.open ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    // Beim Aufklappen erst einblenden, wenn Platz da ist
                    duration: notch.open ? Appearance.fadeDuration * 1.6 : Appearance.fadeDuration * 0.7
                    easing.type: Easing.OutCubic
                }
            }

            Item {
                id: row

                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                }
                height: 60

                Avatar {
                    id: avatar

                    anchors.verticalCenter: parent.verticalCenter
                    size: 48
                    ring: notch.stateColor
                }

                Rectangle {
                    id: field

                    anchors {
                        left: avatar.right
                        leftMargin: 14
                        right: status.left
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    height: 44
                    radius: height / 2
                    color: Colors.alpha(notch.fg, 0.07)
                    border.width: 1
                    border.color: Colors.alpha(notch.stateColor, notch.context.phase === "typing" ? 0.18 : 0.55)

                    Behavior on border.color { ColorAnimation { duration: Appearance.fadeDuration } }

                    PasswordDots {
                        anchors.centerIn: parent
                        width: parent.width - 32
                        count: notch.context.buffer.length
                        color: notch.stateColor
                        checking: notch.context.phase === "checking"
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: notch.context.buffer.length === 0 && notch.context.phase !== "success"
                        text: notch.context.phase === "checking" ? "" : I18n.tr("Passwort")
                        color: Colors.alpha(notch.fg, 0.35)
                        font.family: Config.font
                        font.pixelSize: 14
                    }
                }

                Item {
                    id: status

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    width: 22
                    height: 24

                    LockGlyph {
                        anchors.centerIn: parent
                        visible: !caps.visible
                        size: 17
                        open: notch.context.phase === "success"
                        color: notch.stateColor
                    }

                    Icon {
                        id: caps

                        anchors.centerIn: parent
                        visible: notch.context.capsLock && notch.context.phase !== "success"
                        text: "keyboard_capslock"
                        size: 22
                        color: Colors.tertiary
                    }
                }
            }

            Text {
                anchors {
                    top: row.bottom
                    topMargin: 4
                    horizontalCenter: row.horizontalCenter
                    horizontalCenterOffset: (avatar.width + 14 - status.width - 12) / 2
                }
                opacity: notch.hasMessage ? 1 : 0
                text: notch.context.message
                color: Colors.error
                font.family: Config.font
                font.pixelSize: 13
                font.weight: Font.Medium

                Fade on opacity {}
            }
        }
    }

    NotchShoulder {
        id: shoulderLeft

        x: -width
        y: 0
        size: notch.open ? Appearance.notchShoulderOpen : Appearance.notchShoulder
        color: Appearance.notchColor
        strokeWidth: pill.borderWidth
        strokeColor: Appearance.notchBorderColor

        Morph on size {}
    }

    NotchShoulder {
        x: notch.width
        y: 0
        size: shoulderLeft.size
        color: Appearance.notchColor
        strokeWidth: pill.borderWidth
        strokeColor: Appearance.notchBorderColor
        mirrored: true
    }

    // ---- Bausteine ----

    // Vorhaengeschloss, selbst gezeichnet: Koerper als runde Platte, Buegel
    // als Bogen. `open` hebt den Buegel heraus und kippt ihn – mit Feder,
    // wie das Schloss beim Entsperren aufspringt.
    component LockGlyph: Item {
        id: glyph

        property real size: 16
        property color color: "white"
        property bool open: false

        readonly property real stroke: Math.max(1.6, glyph.size * 0.16)
        readonly property real legX: glyph.size * 0.5 - glyph.size * 0.36 + glyph.stroke / 2

        width: glyph.size
        height: glyph.size * 1.25

        Behavior on color { ColorAnimation { duration: Appearance.fadeDuration } }

        Shape {
            id: shackle

            width: glyph.size
            height: glyph.size * 0.75
            preferredRendererType: Shape.CurveRenderer
            transform: [
                Rotation {
                    origin.x: glyph.size - glyph.legX
                    origin.y: glyph.size * 0.62
                    angle: glyph.open ? 22 : 0

                    Behavior on angle {
                        NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                },
                Translate {
                    y: glyph.open ? -glyph.size * 0.2 : 0

                    Behavior on y {
                        NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    }
                }
            ]

            ShapePath {
                strokeWidth: glyph.stroke
                strokeColor: glyph.color
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                startX: glyph.legX
                startY: glyph.size * 0.66
                PathLine { x: glyph.legX; y: glyph.size * 0.42 }
                PathArc {
                    x: glyph.size - glyph.legX
                    y: glyph.size * 0.42
                    radiusX: glyph.size * 0.5 - glyph.legX
                    radiusY: glyph.size * 0.5 - glyph.legX
                }
                PathLine { x: glyph.size - glyph.legX; y: glyph.size * 0.66 }
            }
        }

        Rectangle {
            y: glyph.size * 0.58
            width: glyph.size
            height: glyph.size * 0.67
            radius: glyph.size * 0.2
            color: glyph.color
        }
    }

    component Icon: Text {
        property real size: 18

        font.family: "Material Symbols Outlined"
        font.pixelSize: size
        font.variableAxes: { "FILL": 1 }
    }

    // ~/.face als Kreis mit Ring in der Zustandsfarbe; ohne Bild das Symbol
    component Avatar: Item {
        id: av

        property real size: 48
        property color ring: "white"

        width: av.size
        height: av.size

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Colors.alpha(notch.fg, 0.08)
            border.width: 2
            border.color: Colors.alpha(av.ring, 0.85)

            Behavior on border.color { ColorAnimation { duration: Appearance.fadeDuration } }
        }

        Image {
            id: face

            anchors.fill: parent
            anchors.margins: 4
            source: "file://" + Quickshell.env("HOME") + "/.face"
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }

        Rectangle {
            id: faceMask

            anchors.fill: face
            radius: width / 2
            layer.enabled: true
            visible: false
        }

        MultiEffect {
            anchors.fill: face
            source: face
            maskEnabled: true
            maskSource: faceMask
            visible: face.status === Image.Ready
        }

        Icon {
            anchors.centerIn: parent
            visible: face.status !== Image.Ready
            text: "person"
            size: av.size * 0.5
            color: notch.fg
        }
    }

    // Ein Punkt je Zeichen. Neue Punkte ploppen auf; sind es mehr, als in
    // das Feld passen, ruecken sie zusammen. Beim Pruefen laeuft eine Welle.
    component PasswordDots: Item {
        id: dots

        property int count: 0
        property color color: "white"
        property bool checking: false

        readonly property real dot: 10
        readonly property real gap: Math.min(8, Math.max(2, (dots.width - dots.count * dots.dot) / Math.max(1, dots.count - 1)))
        readonly property int shownCount: Math.max(0, Math.min(dots.count, Math.floor((dots.width + 2) / (dots.dot + 2))))

        height: dots.dot

        // Ein Zahl-Modell wuerde bei jedem Zeichen alle Punkte neu anlegen
        // (und alle ploppen lassen) – das ListModel waechst nur am Ende
        ListModel { id: dotModel }

        onShownCountChanged: {
            while (dotModel.count < dots.shownCount)
                dotModel.append({});
            if (dotModel.count > dots.shownCount)
                dotModel.remove(dots.shownCount, dotModel.count - dots.shownCount);
        }
        Component.onCompleted: dots.shownCountChanged()

        Row {
            anchors.centerIn: parent
            spacing: dots.gap

            Repeater {
                model: dotModel

                Rectangle {
                    id: d

                    required property int index

                    width: dots.dot
                    height: dots.dot
                    radius: width / 2
                    color: dots.color

                    Behavior on color { ColorAnimation { duration: Appearance.fadeDuration } }

                    // Erst klein anlegen, dann per Behavior aufploppen
                    property bool born: false
                    scale: d.born ? 1 : 0.2
                    Component.onCompleted: d.born = true

                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.fadeDuration * 1.4
                            easing.type: Easing.OutBack
                            easing.overshoot: 2.4
                        }
                    }

                    SequentialAnimation on opacity {
                        running: dots.checking
                        loops: Animation.Infinite
                        alwaysRunToEnd: true

                        PauseAnimation { duration: Math.max(0, d.index) * 55 }
                        NumberAnimation { to: 0.25; duration: 260; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 260; easing.type: Easing.InOutSine }
                        PauseAnimation { duration: Math.max(0, (dots.shownCount - d.index) * 55) }
                    }
                }
            }
        }
    }
}
