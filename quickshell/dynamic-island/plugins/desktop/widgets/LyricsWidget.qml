pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.services.media
import qs.modules.services.core

import qs
import qs.modules.services.config

// Desktop-Widget "Songtext": die aktuelle Zeile gross in der Akzentfarbe,
// darueber die vorige und darunter die naechste, beide kleiner und gedimmt
// (opts.lines == 1: nur die aktuelle). Liegt auf dem Wallpaper, deshalb ein
// leichter Schatten unter der Schrift (Text.Raised) – kein MultiEffect.
//
// Vertrag mit dem Widget-Host (modules/desktop): unit, active, editing, opts,
// color, accent werden gesetzt; Breite und Hoehe bestimmt das Widget selbst.
//
// Zeilenwechsel: die drei Zeilen ruecken EINMAL um eine Stufe nach oben
// (shift 1 -> 0) und die neue aktuelle blendet ein. Kein Behavior auf
// Werten, die sich laufend aendern. Ohne Titel oder Text ist das Widget
// unsichtbar; im Bearbeitungsmodus steht ein Platzhalter.
Item {
    id: root

    property real unit: 16
    property bool active: true
    property bool editing: false
    property var opts: ({})
    property color color: Colors.fgBackground
    property color accent: Colors.primary

    readonly property string align: root.opts?.align ?? "mitte"
    readonly property int lineCount: root.opts?.lines === 1 ? 1 : 3
    readonly property int hAlign: root.align === "links" ? Text.AlignLeft
                                : root.align === "rechts" ? Text.AlignRight
                                : Text.AlignHCenter

    readonly property real bigSize: root.unit * 1.6
    readonly property real smallSize: root.unit * 1.05
    readonly property real step: root.bigSize * 1.35

    readonly property bool synced: Lyrics.status === "ok" && Lyrics.synced && Lyrics.lines.length > 0
    readonly property int index: Lyrics.index
    readonly property string prevLine: root.synced && root.index > 0 ? (Lyrics.lines[root.index - 1]?.text ?? "") : ""
    readonly property string currentLine: root.synced && root.index >= 0 ? (Lyrics.lines[root.index]?.text ?? "") : ""
    readonly property string nextLine: root.synced ? (Lyrics.lines[root.index + 1]?.text ?? "") : ""
    readonly property bool hasContent: Media.available && root.synced
                                       && (root.currentLine !== "" || root.nextLine !== "")

    implicitWidth: root.unit * 28
    implicitHeight: root.lineCount === 1 ? root.bigSize * 1.6 : root.step * 2 + root.bigSize * 1.6

    opacity: root.hasContent || root.editing ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: Appearance.fadeDuration * 2; easing.type: Easing.OutCubic }
    }

    DemandRequest {
        demand: Lyrics.demand
        active: root.active && root.visible && Media.playing
    }

    // Beim Zeilenwechsel einmal nachruecken – nur, wenn das Widget
    // ueberhaupt laeuft; verdeckt bleibt alles still
    property real shift: 0

    onIndexChanged: {
        if (!root.active || !root.visible || !root.hasContent)
            return;
        slide.restart();
    }

    ParallelAnimation {
        id: slide

        NumberAnimation {
            target: root
            property: "shift"
            from: 1
            to: 0
            duration: Appearance.morphDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: current
            property: "opacity"
            from: 0.3
            to: 1
            duration: Appearance.morphDuration
            easing.type: Easing.OutCubic
        }
    }

    // Die Zeilen sitzen auf festen Stufen um die Mitte; `shift` verschiebt
    // alle drei um eine Stufe nach unten (= Ausgangslage vor dem Nachruecken)
    Item {
        id: stack

        width: parent.width
        height: parent.height
        y: root.shift * root.step

        // Vorige Zeile
        Text {
            id: previous

            visible: root.lineCount === 3
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            y: parent.height / 2 - root.step - height / 2

            text: root.prevLine
            color: root.color
            opacity: 0.45
            font.family: Config.font
            font.pixelSize: root.smallSize
            font.weight: Font.Medium
            horizontalAlignment: root.hAlign
            elide: Text.ElideRight
            maximumLineCount: 1
            style: Text.Raised
            styleColor: Colors.alpha("#000000", 0.4)
        }

        // Aktuelle Zeile
        Text {
            id: current

            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            y: parent.height / 2 - height / 2

            text: root.editing && !root.hasContent ? I18n.tr("Songtext") : root.currentLine
            color: root.accent
            font.family: Config.font
            font.pixelSize: root.bigSize
            font.weight: Font.DemiBold
            horizontalAlignment: root.hAlign
            elide: Text.ElideRight
            maximumLineCount: 1
            style: Text.Raised
            styleColor: Colors.alpha("#000000", 0.4)
        }

        // Naechste Zeile
        Text {
            id: next

            visible: root.lineCount === 3
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            y: parent.height / 2 + root.step - height / 2

            text: root.nextLine
            color: root.color
            opacity: 0.45
            font.family: Config.font
            font.pixelSize: root.smallSize
            font.weight: Font.Medium
            horizontalAlignment: root.hAlign
            elide: Text.ElideRight
            maximumLineCount: 1
            style: Text.Raised
            styleColor: Colors.alpha("#000000", 0.4)
        }
    }
}
