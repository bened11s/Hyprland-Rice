pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.modules.services.config

import "i18n/en.js" as En

// Sprache der Oberflaeche – ueberall per `I18n.tr("…")` nutzbar.
//
// Die Texte im Code bleiben deutsch und sind selbst der Schluessel: steht
// appearance.language auf "de", kommt der Text unveraendert zurueck, sonst
// die Uebersetzung aus i18n/en.js (fehlt eine, bleibt es beim deutschen
// Text, und das Log meldet ihn einmal). Platzhalter wie bei qsTr:
//
//     I18n.tr("Wechsel alle %1 min").arg(n)
//
// Weil tr() `language` liest, uebersetzen Bindungen beim Umschalten neu.
// Fehlende Eintraege findet auch `python i18n/check.py` (ohne Shell).
Singleton {
    id: root

    // "en" (Vorgabe, so setzt es auch install.sh) oder "de"
    readonly property string language: Config.appearance.language
    readonly property bool german: root.language === "de"
    // Fuer Datumsangaben: toLocaleDateString(I18n.locale, …)
    readonly property var locale: Qt.locale(root.german ? "de_DE" : "en_US")

    // Schon gemeldete Luecken, damit das Log nicht bei jeder Bindung anschlaegt
    property var reported: ({})

    function tr(text: string): string {
        if (root.german || !text)
            return text;
        const out = En.strings[text];
        if (out !== undefined)
            return out;
        if (!root.reported[text]) {
            root.reported[text] = true;
            console.info(`i18n: keine Uebersetzung fuer "${text}"`);
        }
        return text;
    }

    // Datum je Sprache: deutsches und englisches Muster getrennt, weil sich
    // nicht nur die Namen, sondern auch die Reihenfolge unterscheidet
    // ("d. MMMM" vs. "MMMM d")
    function date(value: var, de: string, en: string): string {
        return value.toLocaleDateString(root.locale, root.german ? de : en);
    }
}
