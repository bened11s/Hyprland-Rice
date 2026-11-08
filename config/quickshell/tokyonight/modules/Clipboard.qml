// Clipboard-History mit wl-paste/wl-copy (kein cliphist noetig)
// Ueberwacht die Zwischenablage, speichert bis zu N Eintraenge,
// Klick auf einen Eintrag kopiert ihn zurueck.
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    signal closeRequested()

    property bool open: false
    property int maxEntries: 30
    property var entries: []

    readonly property string storePath: Quickshell.stateDir + "/clipboard.json"

    function close() {
        open = false
        closeRequested()
    }

    function remember(raw) {
        if (!raw)
            return

        // Newlines abschneiden, Leerraum trimmen
        let text = raw.replace(/\s+$/, "").trim()

        if (text.length < 2)
            return

        // Nicht das gleiche zweimal hintereinander
        if (entries.length > 0 && entries[0] === text)
            return

        let next = [text]

        for (let i = 0; i < entries.length && next.length < maxEntries; i++) {
            if (entries[i] !== text)
                next.push(entries[i])
        }

        entries = next

        saveTimer.restart()
    }

    // =========================
    // SPEICHERN / LADEN
    // =========================

    // Jede Property des Adapters = ein Key in der JSON-Datei.
    FileView {
        id: store

        path: root.storePath

        watchChanges: false
        atomicWrites: true

        onLoaded: root.loadFromStore()
        onLoadFailed: {
            // Datei existiert noch nicht -> leerer Start ist normal
        }

        JsonAdapter {
            property list<string> items: []
        }
    }

    function loadFromStore() {
        let list = store.adapter.items

        if (Array.isArray(list) && list.length > 0)
            entries = list
    }

    Timer {
        id: saveTimer

        interval: 900

        onTriggered: {
            store.adapter.items = root.entries
            store.writeAdapter()
        }
    }

    Component.onCompleted: store.reload()

    // =========================
    // CLIPBOARD UEBERWACHEN
    // =========================

    property string lastSeen: ""

    Timer {
        interval: 700
        running: true
        repeat: true

        onTriggered: {
            if (!root.open)
                watchProcess.running = true
        }
    }

    Process {
        id: watchProcess

        command: ["wl-paste", "--no-newline"]

        stdout: StdioCollector {
            onStreamFinished: {
                // Wie in remember() bereinigen, sonst greift der
                // Duplikatschutz nicht (Newline/Trailing-Space).
                let value = text.replace(/\s+$/, "").trim()

                if (value.length >= 2 && value !== root.lastSeen) {
                    root.lastSeen = value
                    root.remember(value)
                }
            }
        }
    }

    // =========================
    // ZURUECKKOPIEREN
    // =========================

    function copyBack(text) {
        copyProcess.command = ["wl-copy", "--clearmodifiers", text]
        copyProcess.running = true
        root.lastSeen = text
        root.close()
    }

    Process {
        id: copyProcess

        running: false
    }

    // =========================
    // ANZEIGE
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

    Rectangle {
        id: panel

        anchors.centerIn: parent

        width: 420
        height: Math.min(440, listView.contentHeight + 60)
        radius: 8
        color: "#16161e"

        border.width: 1
        border.color: "#3b4261"

        opacity: root.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 110
                easing.type: Easing.OutQuad
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: mouse.accepted
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            // --- Kopf ---

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Zwischenablage"
                    color: "#c0caf5"
                    font.pixelSize: 13
                    font.family: "JetBrains Mono"
                    font.bold: true

                    Layout.fillWidth: true
                }

                Text {
                    text: root.entries.length + " Einträge"
                    color: "#565f89"
                    font.pixelSize: 10
                    font.family: "JetBrains Mono"
                }
            }

            // --- Liste ---

            ListView {
                id: listView

                Layout.fillWidth: true
                Layout.fillHeight: true

                clip: true
                spacing: 2
                model: root.entries

                ScrollBar.vertical: ScrollBar {
                    id: vbar

                    policy: ScrollBar.AsNeeded

                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2

                        color: vbar.pressed ? "#7aa2f7" : "#3b4261"

                        opacity: vbar.active ? 0.9 : 0
                    }
                }

                delegate: Rectangle {
                    required property int index
                    required property string modelData

                    width: listView.width
                    height: Math.max(28, entryText.implicitHeight + 12)
                    radius: 4

                    color: rowHover.hovered ? "#1f2335" : "transparent"

                    Text {
                        id: entryText

                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6

                        text: parent.modelData
                        color: "#c0caf5"

                        font.pixelSize: 11
                        font.family: "JetBrains Mono"

                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    HoverHandler {
                        id: rowHover
                        cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                        onTapped: root.copyBack(parent.modelData)
                    }
                }
            }

            // --- Leer-Hinweis ---

            Text {
                Layout.fillWidth: true

                text: root.entries.length === 0
                    ? "Noch nichts kopiert"
                    : ""

                visible: root.entries.length === 0

                color: "#565f89"
                font.pixelSize: 11
                font.family: "JetBrains Mono"

                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}