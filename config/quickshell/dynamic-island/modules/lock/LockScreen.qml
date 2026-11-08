pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell

import qs
import qs.modules.services.config
import qs.modules.services.media
import qs.modules.services.wallpaper

// Was auf jedem Monitor zu sehen ist, solange gesperrt ist:
//
//   - der Hintergrund: beim Sperren zieht ein Foto des Desktops von kurz
//     vorher (Lock.qml, grim) sich heran, wird unscharf und blendet dabei ins
//     Wallpaper ueber (lock.background "wallpaper") oder bleibt das Foto
//     ("desktop"). Beim Entsperren laeuft das genau rueckwaerts, bis es
//     deckungsgleich mit dem echten Desktop ist – erst dann faellt die Sperre.
//   - oben die Notch (LockNotch), die zum Passwortfeld aufklappt
//   - die Uhr: Stunden in Schriftfarbe, Minuten im Akzent des Wallpapers
//   - unten die Medien-Karte, nur auf dem Monitor, der beim Sperren den
//     Fokus hatte
//
// Ohne echte Sperre benutzbar (Vorschau, Tests): `context` reicht.
Item {
    id: view

    required property LockContext context
    property bool leaving: false
    property bool primary: true
    // Nur auf dem aktiven Monitor klappt die Notch auf (Lock.activeName).
    // `activated` meldet: hier wurde getippt oder der Zeiger ist hier.
    property bool active: true
    signal activated
    // file://-URL des Desktop-Fotos dieses Monitors ("" = Wallpaper nehmen)
    property string snapshot: ""
    // Dauer des Abgangs; Lock.qml gibt die Sperre erst danach frei
    property int exitDuration: Math.round(Appearance.morphDuration * 1.4)
    // Vorschau im Anordnungs-Editor (LockEditor): Medien-Karte auch ohne
    // Musik, keine Szenen-Animationen (sonst hinge die Uhr beim Ziehen
    // hinterher). Uhr und Karte sind ueber clockItem/mediaItem erreichbar,
    // ihre Lage kommt aus LockLayout (leer = das Bild wie bisher).
    property bool preview: false
    readonly property Item clockItem: clockBlock
    readonly property Item mediaItem: media

    // Kurz nach dem Erscheinen true: alle Eingangs-Animationen haengen daran
    property bool entered: false
    readonly property bool shown: view.entered && !view.gone

    // Der Abgang in zwei Schritten: erst die Dauern umstellen (exitMode),
    // dann die Ziele (gone). Haengen beide direkt an `leaving`, entscheidet
    // die Reihenfolge der Bindungen, ob ein Behavior noch mit der alten
    // Dauer startet – die Uhr hing dann als Geist bis zum Schluss im Bild.
    property bool exitMode: false
    property bool gone: false

    onLeavingChanged: {
        view.exitMode = view.leaving;
        view.gone = view.leaving;
    }

    readonly property int sceneDuration: view.preview ? 0 : Math.round(Appearance.morphDuration * 2.2)
    // Hintergrund: rein weich auslaufend, raus gleichmaessig bis zum Ende –
    // sonst ist das Bild nach der halben Zeit fast fertig und "steht"
    readonly property int sceneTime: view.exitMode ? view.exitDuration : view.sceneDuration
    readonly property int sceneCurve: view.exitMode ? Easing.InOutCubic : Easing.OutCubic
    // Uhr, Karte, Notch verschwinden zuerst, das Bild folgt
    readonly property int overlayOut: Math.round(view.exitDuration * 0.45)

    Timer {
        interval: 16
        running: true
        onTriggered: view.entered = true
    }

    Keys.onPressed: event => {
        view.activated();
        view.context.handleKey(event);
        event.accepted = true;
    }

    // ---- Hintergrund ----
    Rectangle {
        anchors.fill: parent
        color: Colors.background
    }

    Item {
        id: backdrop

        anchors.fill: parent
        scale: view.shown ? 1.05 : 1

        Behavior on scale {
            NumberAnimation { duration: view.sceneTime; easing.type: view.sceneCurve }
        }

        Item {
            id: stack

            anchors.fill: parent

            Image {
                id: shot

                anchors.fill: parent
                visible: view.snapshot !== ""
                source: view.snapshot
                sourceSize: Qt.size(view.width, view.height)
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                // Das Foto liegt bei jeder Sperre unter demselben Namen
                cache: false
            }

            // Wallpaper-Modus: liegt ueber dem Foto und blendet im selben Zug
            // ein, in dem das Bild unscharf wird – und beim Entsperren wieder
            // aus, damit am Ende das Foto (= der Desktop) steht
            Image {
                id: wall

                readonly property bool wanted: view.snapshot === ""
                    || (Config.lock.background !== "desktop" && view.shown)

                anchors.fill: parent
                visible: opacity > 0
                opacity: wall.wanted ? 1 : 0
                source: Wallpapers.actualCurrent !== "" ? "file://" + Wallpapers.actualCurrent : ""
                sourceSize: Qt.size(view.width, view.height)
                fillMode: Image.PreserveAspectCrop
                asynchronous: false

                Behavior on opacity {
                    NumberAnimation { duration: view.sceneTime; easing.type: view.sceneCurve }
                }
            }
        }

        // Auch bei blur 0 zeichnet der Effekt das Bild eine Spur weicher und
        // dunkler. Steht er auf null, liegt darum das Bild selbst obenauf –
        // pixelgenau wie der Desktop, auf den die Sperre gleich freigibt.
        MultiEffect {
            id: effect

            anchors.fill: parent
            source: stack
            visible: (shot.status === Image.Ready || wall.status === Image.Ready)
                     && (effect.blur > 0.002 || effect.brightness < -0.002 || effect.saturation > 0.002)

            blurEnabled: Config.lock.blur
            blurMax: 64
            blur: view.shown ? 0.7 : 0
            brightness: view.shown ? -0.16 : 0
            saturation: view.shown ? 0.12 : 0

            Behavior on blur {
                NumberAnimation { duration: view.sceneTime; easing.type: view.sceneCurve }
            }
            Behavior on brightness {
                NumberAnimation { duration: view.sceneTime; easing.type: view.sceneCurve }
            }
            Behavior on saturation {
                NumberAnimation { duration: view.sceneTime; easing.type: view.sceneCurve }
            }
        }
    }

    // Unten dunkler, damit Karte und Uhr auf hellen Bildern lesbar bleiben
    Rectangle {
        anchors.fill: parent
        opacity: view.shown ? 1 : 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.alpha("black", 0.18) }
            GradientStop { position: 0.45; color: Colors.alpha("black", 0.0) }
            GradientStop { position: 1.0; color: Colors.alpha("black", 0.42) }
        }

        Behavior on opacity {
            NumberAnimation { duration: view.sceneTime; easing.type: view.sceneCurve }
        }
    }

    // ---- Uhr ----
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    readonly property bool use12h: Config.appearance.clock === "12h"
    readonly property string hours: {
        const h = clock.date.getHours();
        return view.use12h ? String(h % 12 || 12) : String(h).padStart(2, "0");
    }
    readonly property string minutes: String(clock.date.getMinutes()).padStart(2, "0")
    readonly property real clockSize: Math.round(Math.min(view.width * 0.13, view.height * 0.22, 230) * LockLayout.scale("clock"))

    Item {
        id: clockBlock

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: LockLayout.offsetX("clock", view.width)
        // Rein: von oben herabsinken. Raus: an Ort und Stelle leicht
        // schrumpfen und verblassen, als sinke sie ins Bild zurueck
        y: LockLayout.top("clock", view.height, height) + (view.entered ? 0 : -40)
        width: clockColumn.width
        height: clockColumn.height
        // Ausgeblendet (LockLayout.hidden) – im Editor bleibt sie als
        // Platzhalter stehen, den Griff dimmt EditHandle
        opacity: view.shown && (view.preview || !LockLayout.hidden("clock")) ? 1 : 0
        visible: opacity > 0
        scale: view.gone ? 0.96 : 1

        Behavior on y {
            NumberAnimation { duration: view.sceneDuration; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: view.exitMode ? view.overlayOut : view.sceneDuration; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: view.overlayOut; easing.type: Easing.OutCubic }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowOpacity: 0.35
            shadowBlur: 1
            blurMax: 48
            shadowVerticalOffset: 3
        }

        Column {
            id: clockColumn

            spacing: Math.round(view.clockSize * 0.02)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.date(clock.date, "dddd, d. MMMM", "dddd, MMMM d")
                color: Colors.alpha(Colors.fgBackground, 0.88)
                font.family: Config.font
                font.pixelSize: Math.round(view.clockSize * 0.12)
                font.weight: Font.Medium
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(view.clockSize * 0.16)

                Text {
                    text: view.hours
                    color: Colors.fgBackground
                    font.family: Config.font
                    font.pixelSize: view.clockSize
                    font.weight: Font.Black
                    font.letterSpacing: -view.clockSize * 0.035
                    font.features: { "tnum": 1 }
                }

                Text {
                    text: view.minutes
                    color: Colors.mix(Colors.primary, Colors.fgBackground, 0.18)
                    font.family: Config.font
                    font.pixelSize: view.clockSize
                    font.weight: Font.Black
                    font.letterSpacing: -view.clockSize * 0.035
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    // ---- Notch ----
    LockNotch {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        context: view.context
        active: view.active
        shown: view.entered
        leaving: view.gone
        exitMode: view.exitMode
        fadeDuration: view.overlayOut
    }

    // ---- Medien ----
    LockMedia {
        id: media

        readonly property bool wanted: view.preview || (view.primary && !LockLayout.hidden("media") && Media.available)

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: LockLayout.offsetX("media", view.width)
        y: LockLayout.top("media", view.height, height) + (view.entered && media.wanted ? 0 : 36)
        width: Math.min(implicitWidth, view.width - 48)
        height: implicitHeight
        scale: LockLayout.scale("media")
        opacity: view.shown && media.wanted ? 1 : 0
        visible: opacity > 0

        Behavior on y {
            NumberAnimation { duration: view.sceneDuration; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: view.exitMode ? view.overlayOut : view.sceneDuration; easing.type: Easing.OutCubic }
        }
    }

    // ---- Widgets (LockLayout.widgets, nur Hauptmonitor) ----
    // ListModel statt des Arrays: jede Aenderung am Layout (auch waehrend
    // des Ziehens im Editor) baute sonst alle Widgets neu auf
    ListModel {
        id: widgetModel
    }

    function syncWidgets(): void {
        const ids = (view.primary || view.preview) ? LockLayout.widgets.map(w => w.id) : [];
        for (let i = widgetModel.count - 1; i >= 0; i--)
            if (!ids.includes(widgetModel.get(i).wid))
                widgetModel.remove(i);
        for (const id of ids) {
            let found = false;
            for (let i = 0; i < widgetModel.count; i++)
                if (widgetModel.get(i).wid === id)
                    found = true;
            if (!found)
                widgetModel.append({ wid: id });
        }
    }

    Connections {
        target: LockLayout
        function onWidgetsChanged(): void {
            view.syncWidgets();
        }
    }
    onPrimaryChanged: view.syncWidgets()
    Component.onCompleted: view.syncWidgets()

    // Fuer den Editor: Element eines Widgets (EditHandle.target)
    property int widgetRevision: 0

    function widgetItem(id: string): Item {
        for (let i = 0; i < widgetRepeater.count; i++) {
            const it = widgetRepeater.itemAt(i);
            if (it && it.wid === id)
                return it;
        }
        return null;
    }

    Item {
        id: widgetLayer

        anchors.fill: parent
        opacity: view.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: view.exitMode ? view.overlayOut : view.sceneDuration; easing.type: Easing.OutCubic }
        }

        Repeater {
            id: widgetRepeater

            model: widgetModel
            onItemAdded: view.widgetRevision++
            onItemRemoved: view.widgetRevision++

            LockWidget {
                active: view.shown
                preview: view.preview
            }
        }
    }

    HoverHandler {
        onHoveredChanged: if (hovered) view.activated()
    }

    // Klick irgendwohin holt den Tastaturfokus zurueck
    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: view.forceActiveFocus()
    }
}
