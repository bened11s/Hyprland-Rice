pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import Quickshell.Io

import qs.modules.services.config
import qs.modules.services.wallpaper

// Gestalt-Singleton – ueberall per `Appearance.<wert>` nutzbar.
//
// Hier steht einmal, wie sich die Pillen und Karten der Shell anfuehlen:
// Rundung, Rand, Schatten, Verlauf und vor allem die Bewegung. Die
// Komponenten holen sich die Werte ueber Surface.qml und Morph.qml
// (modules/widgets), statt sie jede fuer sich zu kennen.
//
// Vorbild ist saneAspects "Dynamite": eine schwarze Insel, die mit echtem
// Nachschwingen auf- und zuklappt. Wie stark sie schwingt, stellt man im
// Einstellungs-Menue ein (appearance.bounce).
Singleton {
    id: root

    // ---- Form ----
    // Eckenrundung der Karten. Flache Pillen deckeln ohnehin auf height / 2.
    readonly property real radius: Config.appearance.radius
    readonly property real borderWidth: 1
    // Der Rand ist bewusst halbtransparent: er zeichnet die Kante nach,
    // ohne auf hellen Wallpapern als grauer Ring zu stehen.
    readonly property color borderColor: Colors.alpha(Colors.outline, 0.38)

    // Leichter Verlauf: oben eine Spur heller als der Grund, unten der Grund
    // selbst. Das gibt den Pillen eine Oberseite, auf der Licht liegt.
    readonly property real lift: 0.035

    // ---- Notch-Layout ----
    // Die angedockte Notch ist schwarz wie ein Displayrahmen und geht ueber
    // gewoelbte Schultern in die Oberkante ueber (saneAspect-Vorbild).
    readonly property bool notchLayout: Config.appearance.layout === "notch"
    // Normal schwarz. Hat das Farbschema aber dunkle Schrift (helles Schema,
    // helles Wallpaper), waere die auf Schwarz kaum lesbar – dann nimmt die
    // Notch den hellen Theme-Hintergrund.
    readonly property bool darkText: root.luminance(Colors.fgBackground) < 0.45
    readonly property color notchColor: root.darkText ? Colors.background : "#000000"

    // Hebt sich die Notch nicht vom Wallpaper ab (schwarz auf sehr dunklem
    // Bild, hell auf sehr hellem), bekommt sie eine leichte Kontur. Gemessen
    // wird nur der Streifen oben in der Mitte, wo die Notch sitzt.
    property real wallTopLuma: -1          // -1 = noch nicht gemessen
    readonly property bool notchBorder: root.wallTopLuma >= 0
        && Math.abs(root.wallTopLuma - root.luminance(root.notchColor)) < 0.14
    readonly property color notchBorderColor: Colors.alpha(Colors.fgBackground, 0.22)

    function luminance(c: color): real {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }
    // Radius der Schultern (eingeklappt / aufgeklappt). Aufgeklappt folgt er
    // der Eckenrundung (appearance.radius), damit Ober- und Unterecken der
    // Karte zueinander passen.
    readonly property real notchShoulder: 10
    readonly property real notchShoulderOpen: Math.max(notchShoulder, Math.round(radius * 0.8))
    // So viel waechst die eingeklappte Notch unter dem Zeiger: nach unten
    // um den Wert, zur Seite um das Doppelte – statt zu skalieren, was die
    // Schultern von der Kante loesen wuerde.
    readonly property real notchHoverLift: 5

    // ---- Schatten ----
    readonly property bool shadow: Config.appearance.shadow
    readonly property color shadowColor: "#000000"
    readonly property real shadowBlur: 0.9
    readonly property real shadowOpacity: 0.5
    readonly property real shadowOffset: 4

    // ---- Bewegung ----
    // Dauer der Groessen-Animationen (Pille <-> Karte)
    readonly property real speed: Math.max(0.25, Config.appearance.speed)
    readonly property int morphDuration: Math.round(340 / speed)
    // Ein-/Ausblenden von Inhalten
    readonly property int fadeDuration: Math.round(160 / speed)

    // Nachschwingen beim Aufklappen. 0 = klassisch weich (OutCubic), sonst
    // OutBack mit diesem Overshoot (Qt-Default waere 1.70158 ~ 10 %).
    readonly property var bounceLevels: ({
        "aus": 0,
        "leicht": 0.7,
        "mittel": 1.3,
        "stark": 2.1
    })
    readonly property real overshoot: root.bounceLevels[Config.appearance.bounce] ?? 1.3

    // ---- Wallpaper-Helligkeit oben mittig ----
    // Einmal je Wallpaper (auch waehrend der Vorschau in der Auswahl): klein
    // rechnen, oberen Mittelstreifen ausschneiden, mittlere Helligkeit 0..1.
    readonly property string wallpaper: Wallpapers.current

    onWallpaperChanged: lumaDelay.restart()
    Component.onCompleted: lumaDelay.restart()

    Timer {
        id: lumaDelay

        interval: 250
        onTriggered: if (root.wallpaper !== "") {
            lumaProc.running = false;
            lumaProc.running = true;
        }
    }

    Process {
        id: lumaProc

        // Vom Vorschaubild der Wallpaper-Auswahl, wenn es eins gibt: das
        // Original kostete bei grossen PNGs (7500x5000) ~3 s CPU je Messung,
        // und gemessen wird bei jedem Vorschau-Schritt. Das Vorschaubild ist
        // mittig auf 16:9 zugeschnitten, also genau der sichtbare Ausschnitt.
        command: ["sh", "-c", 'f="$1[0]"; [ -s "$2" ] && f="$2"; exec magick "$f" -resize 480x -gravity North '
                  + '-crop 34%x7%+0+0 +repage -colorspace Gray -format "%[fx:mean]" info:',
                  "sh", root.wallpaper, Wallpapers.thumbPathFor(root.wallpaper)]

        stdout: StdioCollector {
            onStreamFinished: {
                const v = parseFloat(text);
                if (!isNaN(v))
                    root.wallTopLuma = v;
            }
        }
    }
}
