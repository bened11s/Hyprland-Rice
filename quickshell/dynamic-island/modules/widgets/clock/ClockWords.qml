import QtQuick

import qs
import qs.modules.services.config

// Deutsche Wortuhr: "viertel nach acht", "kurz vor halb zehn", "punkt
// zwoelf". Zweizeilig – oben die Umschreibung, unten die Stunde gross in
// der Akzentfarbe. Fuer das Desktop-Widget gedacht.
//
// Auf 5 Minuten gerundet; bei den Landmarken (voll, viertel, halb) sagt
// "kurz vor" / "kurz nach" dazu, wie weit es noch ist.
Item {
    id: root

    property date date
    property real size: 16
    property color color: Colors.fgBackground
    property color accent: Colors.primary
    property bool use12h: Config.appearance.clock === "12h"
    property string fontFamily: Config.font
    property int weight: Font.Bold

    readonly property var hourWords: ["zwölf", "eins", "zwei", "drei", "vier", "fünf", "sechs",
                                      "sieben", "acht", "neun", "zehn", "elf"]

    // Zweiteiler [Umschreibung, Stunde] fuer die aktuelle Zeit
    readonly property var phrase: {
        let h = root.date.getHours();
        const m = root.date.getMinutes();
        let step = Math.round(m / 5) * 5;   // 0, 5, ..., 60
        const rest = m - step;              // -2..2
        if (step === 60) {                  // 58, 59 -> "kurz vor" naechste Stunde
            step = 0;
            h += 1;
        }
        // Ab "fuenf vor halb" bezieht sich alles auf die naechste Stunde –
        // im Englischen erst ab "twenty-five to"
        const hour = I18n.tr(root.hourWords[(h + (step >= (I18n.german ? 25 : 35) ? 1 : 0)) % 12]);
        const steps = {
            0: "punkt", 5: "fünf nach", 10: "zehn nach", 15: "viertel nach",
            20: "zwanzig nach", 25: "fünf vor halb", 30: "halb", 35: "fünf nach halb",
            40: "zwanzig vor", 45: "viertel vor", 50: "zehn vor", 55: "fünf vor"
        };
        let words = I18n.tr(steps[step]);
        const landmark = step % 15 === 0;
        if (landmark && rest !== 0) {
            const near = rest < 0 ? I18n.tr("kurz vor") : I18n.tr("kurz nach");
            words = step === 0 ? near : near + " " + words;
        }
        return [words, hour];
    }

    implicitWidth: Math.max(top.implicitWidth, bottom.implicitWidth)
    implicitHeight: top.implicitHeight + bottom.implicitHeight - root.size * 0.12

    Text {
        id: top

        anchors.horizontalCenter: parent.horizontalCenter
        text: root.phrase[0]
        color: root.color
        opacity: 0.85
        font.family: root.fontFamily
        font.pointSize: root.size * 0.75 * 0.46
        font.weight: Font.Medium
        font.letterSpacing: root.size * 0.02
    }

    Text {
        id: bottom

        anchors.horizontalCenter: parent.horizontalCenter
        y: top.implicitHeight - root.size * 0.12
        text: root.phrase[1]
        color: root.accent
        font.family: root.fontFamily
        font.pointSize: root.size * 0.75
        font.weight: root.weight
        font.letterSpacing: -root.size * 0.01
    }
}
