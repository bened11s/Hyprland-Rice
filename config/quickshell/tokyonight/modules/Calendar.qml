// Kalender-Popup: Klick auf die Uhr blendet Kalender ein
import QtQuick
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    signal closeRequested()

    property bool open: false
    property int gridMonth: -1
    property int gridYear: -1
    property int today: 0

    function close() {
        open = false
        closeRequested()
    }

    // Heute markieren, einmalig beim Start
    Component.onCompleted: {
        let now = new Date()
        gridMonth = now.getMonth()
        gridYear = now.getFullYear()
        today = now.getDate()
    }

    // =========================
    // HINTERGRUND / AUSKLICKEN
    // =========================

    Rectangle {
        id: dimmer

        anchors.fill: parent

        color: "#000000"
        opacity: 0.45

        visible: root.open

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    // =========================
    // POPUP
    // =========================

    Rectangle {
        id: panel

        anchors.centerIn: parent

        width: 300
        height: 320
        radius: 8
        color: "#16161e"

        border.width: 1
        border.color: "#3b4261"

        visible: opacity > 0
        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 110
                easing.type: Easing.OutQuad
            }
        }

        // Sichtbarkeit an opacity binden, damit die Animation ausklingt
        onOpacityChanged: if (opacity === 0) visible = false

        // Klick im Panel darf NICHT schließen
        MouseArea {
            anchors.fill: parent
            onClicked: mouse.accepted
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // --- Kopfzeile: Monat + Navigation ---

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    id: monthLabel

                    text: Qt.formatDate(new Date(root.gridYear, root.gridMonth, 1), "MMMM yyyy")
                    color: "#c0caf5"

                    font.pixelSize: 14
                    font.family: "JetBrains Mono"
                    font.bold: true

                    Layout.fillWidth: true
                }

                Text {
                    text: "‹"
                    color: hover.hovered ? "#7aa2f7" : "#565f89"

                    font.pixelSize: 20
                    font.family: "JetBrains Mono"

                    HoverHandler { id: prevHover }

                    TapHandler {
                        onTapped: {
                            let d = new Date(root.gridYear, root.gridMonth - 1, 1)
                            root.gridMonth = d.getMonth()
                            root.gridYear = d.getFullYear()
                        }
                    }
                }

                Text {
                    text: "›"
                    color: hover.hovered ? "#7aa2f7" : "#565f89"

                    font.pixelSize: 20
                    font.family: "JetBrains Mono"

                    HoverHandler { id: nextHover }

                    TapHandler {
                        onTapped: {
                            let d = new Date(root.gridYear, root.gridMonth + 1, 1)
                            root.gridMonth = d.getMonth()
                            root.gridYear = d.getFullYear()
                        }
                    }
                }

                // Klick auf Monatsname = zurück zu heute
                HoverHandler {
                    id: hover
                    cursorShape: Qt.PointingHandCursor
                }
            }

            // --- Wochentage ---

            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

                    Text {
                        required property var modelData

                        text: modelData

                        color: modelData === "So" ? "#f7768e" : "#565f89"

                        font.pixelSize: 10
                        font.family: "JetBrains Mono"

                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // --- Tagesraster ---

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                columnSpacing: 0
                rowSpacing: 2

                Repeater {
                    model: root.visibleDays

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        readonly property bool isToday: modelData.day === root.today
                        readonly property bool inMonth: modelData.month === root.gridMonth

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        radius: 4
                        color: isToday ? "#7aa2f7" : cellHover.hovered ? "#1f2335" : "transparent"
                        opacity: inMonth ? 1 : 0.3

                        Text {
                            anchors.centerIn: parent

                            text: modelData.day

                            color: isToday ? "#0b0e14" : "#c0caf5"

                            font.pixelSize: 11
                            font.family: "JetBrains Mono"
                            font.bold: isToday
                        }

                        HoverHandler {
                            id: cellHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: {
                                let d = new Date(root.gridYear, modelData.month, modelData.day)
                                root.today = d.getDate()
                                root.gridMonth = d.getMonth()
                                root.gridYear = d.getFullYear()
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================
    // 6x7 = 42 Tage, Montag zuerst
    // =========================

    property var visibleDays: {
        let result = []

        let first = new Date(gridYear, gridMonth, 1)

        // Montag = 0 ... Sonntag = 6
        let offset = (first.getDay() + 6) % 7

        // Bis zum Ende des Monats ergaenzen
        let daysInMonth = new Date(gridYear, gridMonth + 1, 0).getDate()
        let daysInPrev = new Date(gridYear, gridMonth, 0).getDate()

        for (let i = 0; i < 42; i++) {
            let dayNum
            let monthNum

            if (i < offset) {
                dayNum = daysInPrev - offset + 1 + i
                monthNum = (gridMonth + 11) % 12
            } else if (i < offset + daysInMonth) {
                dayNum = i - offset + 1
                monthNum = gridMonth
            } else {
                dayNum = i - offset - daysInMonth + 1
                monthNum = (gridMonth + 1) % 12
            }

            result.push({ day: dayNum, month: monthNum })
        }

        return result
    }
}