pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.config

// Ein Punkt je Zeichen. Neue Punkte ploppen auf; sind es mehr, als in
// das Feld passen, ruecken sie zusammen. Beim Pruefen laeuft eine Welle.
Item {
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
