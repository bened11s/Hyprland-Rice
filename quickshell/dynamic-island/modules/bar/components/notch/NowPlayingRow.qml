pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.services.media

// "Jetzt laeuft" in der aufgeklappten Notch (Uebersicht): Cover, Titel und
// Interpret, Visualiser, Play/Pause. Nur da, solange es einen Player gibt –
// alles Weitere (Player-Auswahl, Fortschritt, Vor/Zurueck) steht im
// Medien-Untermenue (SUPER+M bzw. blaettern).
//
// Wisch-Geste der Notch (swipe in Notch.qml): nur die Hintergruende wandern.
// Der Cover-Blend der echten Karte folgt dem Zeiger (`shift`), daneben
// haengt der Blend des naechsten bzw. vorigen Titels (ghost, nur
// Hintergrund) und wird mit hereingezogen. Kennt MediaQueue die
// Warteschlange (Spotify), ist das dessen Cover; sonst der aktuelle Blend.
// Cover, Titel, Visualiser und Knopf bleiben die ganze Zeit stehen. `pull`
// ist der Fortschritt bis zur Schwelle, -1..1 (negativ = nach links =
// naechster Titel).
//
// Beim Wechsel (skipSong → commit) faehrt der zweite Blend ganz herein,
// dann springt der Versatz ohne Animation auf 0 zurueck – der Blend der
// echten Karte zeigt dann denselben Titel, der Sprung ist unsichtbar. Der
// stehende Inhalt blendet derweil aus und mit dem neuen Titel wieder ein:
// erst der alte Titel (`flipFrom`), dann der neue aus dem Schnappschuss
// (`flipTo`) – MPRIS hinkt dem Wechsel ein paar hundert Millisekunden
// hinterher. Erst wenn Media nachgezogen hat (oder nach einer Frist),
// uebernimmt wieder der Live-Stand.
Item {
    id: root

    property real shift: 0
    property real pull: 0
    // Kartenfarbe, in die der Cover-Hintergrund nach rechts ausblendet
    property color fadeColor: Appearance.notchColor
    // Abstand zur zweiten Karte; so weit muss `shift` beim Wechsel laufen
    readonly property real gap: 16
    readonly property real flipDistance: root.width + root.gap
    // Zweite Karte rechts (naechster) oder links (voriger)
    readonly property real ghostSide: root.pull < 0 ? 1 : -1

    // ---- Was die Karten zeigen ----
    // Titel-Objekte wie aus MediaQueue: { title, artist, art }. `live` ist
    // der MPRIS-Stand, alles andere sind Schnappschuesse.
    readonly property var live: ({ title: Media.title, artist: Media.artist, art: Media.art })

    // Nachbar fuer die zweite Karte, beim ersten Zug eingefroren: die Queue
    // rechnet nach dem Wechsel um (bzw. ist kurz ungueltig), die Karte darf
    // mitten in der Fahrt nicht umspringen. null = Queue unbekannt (leer).
    property var ghostTrack: null
    property int ghostTrackSide: 0

    // Uebergabe beim Wechsel (siehe Kopfkommentar)
    property var flipFrom: null    // alter Titel, solange die echte Karte hinausfaehrt
    property var flipTo: null      // neuer Titel, bis Media nachgezogen hat
    readonly property var shown: root.flipFrom ?? root.flipTo ?? root.live

    // Media hat den neuen Titel samt Cover: Schnappschuss nicht mehr noetig.
    // Ohne das Cover-Kriterium blitzte kurz der Platzhalter auf, weil
    // Media.art beim Titelwechsel erst leer ist und dann aus dem Cache kommt.
    readonly property bool caughtUp: !!root.flipTo && Media.title === root.flipTo.title && Media.art !== ""
    // Entkoppelt per callLater: flipTo direkt im Handler zu leeren wertet
    // caughtUp mitten in seiner eigenen Auswertung neu aus (Binding-Loop)
    onCaughtUpChanged: {
        if (root.caughtUp) {
            catchUp.stop();
            Qt.callLater(() => root.flipTo = null);
        }
    }

    // Frist, falls Media nie passt (anderer Player, Titel weicht ab)
    Timer {
        id: catchUp

        interval: 1500
        onTriggered: root.flipTo = null
    }

    // Ueberblenden des stehenden Inhalts beim Wechsel: raus, solange die
    // Hintergruende fahren (commit), rein mit dem neuen Titel (pull → 0).
    // Einmalige Animationen statt Behavior – `shift`/`pull` aendern sich pro
    // Frame, die Deckkraft soll nur hier angestossen werden.
    property real contentOpacity: 1

    NumberAnimation {
        id: contentOut

        target: root
        property: "contentOpacity"
        to: 0
        duration: Appearance.morphDuration
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: contentIn

        target: root
        property: "contentOpacity"
        to: 1
        duration: Appearance.fadeDuration
        easing.type: Easing.OutCubic
    }

    implicitHeight: 52

    onPullChanged: {
        if (root.pull === 0) {
            // Zug vorbei (zurueckgeschnappt oder Wechsel durch): zweiter Blend
            // weg, der Inhalt zeigt ab jetzt flipTo bzw. den Live-Stand
            root.ghostTrack = null;
            root.ghostTrackSide = 0;
            root.flipFrom = null;
            // Inhalt wieder her – auch nach einem abgebrochenen Wechsel
            if (contentOut.running || root.contentOpacity < 1) {
                contentOut.stop();
                contentIn.restart();
            }
            return;
        }
        const sideChanged = root.ghostTrackSide !== root.ghostSide;
        // Waehrend des Wechsels steht der Schnappschuss fest – es sei denn,
        // der Zug wurde unterbrochen und laeuft in die andere Richtung
        if (root.flipFrom && !sideChanged)
            return;
        // Nachladen, solange das Cover der Queue noch fehlt (laedt gerade)
        if (sideChanged || !root.ghostTrack || !root.ghostTrack.art) {
            const next = MediaQueue.valid
                ? (root.ghostSide > 0 ? MediaQueue.upcoming : MediaQueue.previous)
                : null;
            root.ghostTrackSide = root.ghostSide;
            if (next !== root.ghostTrack)
                root.ghostTrack = next;
        }
    }

    // Vom Wechsel (Notch.skipSong) aufgerufen, bevor der zweite Blend ganz
    // hereinfaehrt: der alte Titel bleibt stehen und blendet aus, der neue
    // kommt vom Schnappschuss – auch wenn Media schon unterwegs umspringt.
    function commit(): void {
        root.flipFrom = root.shown;
        root.flipTo = root.ghostTrack;
        if (root.flipTo && !root.caughtUp)
            catchUp.restart();
        else {
            root.flipTo = null;
            catchUp.stop();
        }
        contentIn.stop();
        contentOut.restart();
    }

    // ---- Zweiter Blend: naechster / voriger Titel ----
    // Nur der Hintergrund, haengt neben der echten Karte und faehrt mit
    // `shift` herein. Solange nichts gezogen wird, liegt er ausserhalb der
    // Notch-Karte (die clippt).
    NowPlayingCard {
        id: ghost

        x: root.ghostSide * root.flipDistance
        width: root.width
        height: root.height
        transform: Translate { x: root.shift }
        visible: root.pull !== 0
        opacity: 0.45 + 0.55 * Math.abs(root.pull)
        fadeColor: root.fadeColor
        showContent: false
        track: root.ghostTrack
    }

    // ---- Echte Karte: Blend gleitet mit dem Zeiger, Inhalt steht ----
    NowPlayingCard {
        id: card

        anchors.fill: parent
        live: true
        fadeColor: root.fadeColor
        shift: root.shift
        contentOpacity: root.contentOpacity
        track: root.shown
    }
}
