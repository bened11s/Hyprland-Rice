pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs
import qs.modules.services.config

// Eine Taste der Tastatur-Vorschau (VirtualKeyboard): flache, abgerundete
// Kappe mit feiner Kontur und einer 2-px-Unterkante als Tiefe; gedrueckte
// Modifier rutschen auf die Unterkante. Beleuchtung je Taste: belegte Tasten
// bekommen Legende, leicht getoente Flaeche und Kontur in `light`, der
// gewaehlte Befehl (`lit`) kraeftiger plus schmalem Schein; freie Tasten
// bleiben neutral grau. Beschriftung wie deutsche Kappen: Shift-Zeichen
// oben, Hauptlegende darunter, AltGr-Zeichen unten rechts – bei kleinen
// Einheiten fallen die Nebenzeichen weg statt ueberzulaufen.
// ISO-Enter (spec.iso) als Kontur. Tooltips zeichnet die Tastatur (Overlay).
Item {
    id: key

    // { id, label, sub, alt, icon, x, y, w, h, mod, iso, lowerX, lowerW } aus KeyLayout.js
    required property var spec
    // Pixel je Tasteneinheit und Luecke zwischen Tasten
    required property real unit
    required property real gap
    // Belegung auf der Ebene: { title, group, disabled, changed, source, unnamed, keys, via } | null
    property var info: null
    // Lichtfarbe der Belegung (VirtualKeyboard.lightOf)
    property color light: "transparent"
    // Gehoert zum gewaehlten Befehl
    property bool lit: false
    // Modifier-Bit in der Ebene gesetzt: Kappe gedrueckt
    property bool pressed: false
    // "Auf Tastatur waehlen": freie Tasten sind Ziel
    property bool pick: false
    property bool interactive: true

    signal clicked
    // Rechtsklick (Kontextmenue)
    signal contextClicked

    readonly property bool occupied: key.info !== null
    readonly property bool free: key.info === null && key.spec.mod === 0 && key.spec.noPick !== true
    readonly property bool target: key.pick && key.free && key.interactive
    readonly property bool hovered: hover.hovered && key.interactive
    readonly property bool clickable: key.interactive && (key.spec.mod !== 0 || key.occupied || key.target)
    readonly property bool disabled: key.occupied && key.info.disabled === true

    // Lichtfarbe: Belegung, sonst Primaer (gedrueckt / Teil des gewaehlten Befehls)
    readonly property color beam: key.occupied ? key.light : Colors.primary
    readonly property bool glowing: key.lit || key.occupied || key.pressed
    // Staerke der Toenung 0..1
    readonly property real strength: key.lit ? 1 : key.occupied ? (key.disabled ? 0.4 : 0.55) : key.pressed ? 0.5 : 0

    readonly property color capBase: key.hovered && key.clickable ? Qt.lighter(Colors.surfaceBright, 1.1) : Colors.surfaceBright
    readonly property color capColor: key.glowing ? Qt.tint(key.capBase, Colors.alpha(key.beam, 0.28 * key.strength)) : key.capBase
    readonly property color edgeColor: key.target ? Colors.alpha(Colors.primary, key.hovered ? 0.9 : 0.5)
                                     : key.glowing ? Colors.alpha(key.beam, 0.35 + 0.55 * key.strength)
                                     : Colors.alpha(Colors.outline, 0.35)
    readonly property color legend: key.glowing ? (key.lit ? Qt.lighter(key.beam, 1.1) : key.beam)
                                  : Colors.alpha(Colors.fgSurfaceVariant, 0.8)
    readonly property color legendDim: key.glowing ? Colors.alpha(key.beam, 0.65) : Colors.alpha(Colors.fgSurfaceVariant, 0.45)

    // Geometrie
    readonly property real depth: Math.max(1, Math.round(key.unit * 0.04))
    readonly property real capY: key.pressed ? key.depth : 0
    readonly property real capH: key.height - key.depth
    readonly property real capRadius: Math.max(3, key.unit * 0.14)
    readonly property real pad: Math.max(3, key.unit * 0.1)
    // Nebenzeichen nur, wenn sie Platz haben
    readonly property bool showMinor: key.unit >= 34
    readonly property bool iso: key.spec.iso === true
    readonly property real lowerX: key.iso ? (key.spec.lowerX - key.spec.x) * key.unit : 0
    readonly property real lowerW: key.iso ? key.spec.lowerW * key.unit - key.gap : key.width
    readonly property bool centered: /^[←→↑↓⌫]$/.test(key.spec.label)

    x: key.spec.x * key.unit
    y: key.spec.y * key.unit
    width: key.spec.w * key.unit - key.gap
    height: key.spec.h * key.unit - key.gap
    z: key.hovered ? 2 : 0

    // Schmaler Schein um den gewaehlten Befehl
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: key.capRadius + 3
        color: Colors.alpha(key.beam, key.lit ? 0.22 : 0)
        visible: key.lit

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
    }

    // Unterkante (Tiefe) – in hell wie dunkel eine Stufe dunkler als die Kappe
    readonly property color edgeBase: Qt.darker(Colors.surfaceBright, 1.5)

    Rectangle {
        visible: !key.iso
        y: key.depth
        width: parent.width
        height: key.capH
        radius: key.capRadius
        color: key.edgeBase
    }

    // Kappe
    Rectangle {
        visible: !key.iso
        y: key.capY
        width: parent.width
        height: key.capH
        radius: key.capRadius
        color: key.capColor
        border.width: 1
        border.color: key.edgeColor

        Behavior on y {
            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
        Behavior on border.color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
    }

    // ISO-Enter: Unterkante und Kappe als Konturen
    Shape {
        visible: key.iso
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        IsoEnterPath {
            fillColor: key.edgeBase
            oy: key.depth
            w: key.width
            h: key.capH
            topH: key.unit - key.gap
            lowerX: key.lowerX
            lowerW: key.lowerW
            r: key.capRadius
        }

        IsoEnterPath {
            fillColor: key.capColor
            strokeColor: key.edgeColor
            strokeWidth: 1
            ox: 0.5
            oy: key.capY + 0.5
            w: key.width - 1
            h: key.capH - 1
            topH: key.unit - key.gap
            lowerX: key.lowerX
            lowerW: key.lowerW - 1
            r: key.capRadius

            Behavior on fillColor {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
            Behavior on strokeColor {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
        }
    }

    // Flaeche fuer die Legenden; clip haelt
    // alles in der Kappe
    Item {
        id: face

        // ISO-Enter: Beschriftung im oberen, breiten Teil wie auf echten Kappen
        x: 1
        y: key.capY + 1
        width: key.width - 2
        height: (key.iso ? key.unit - key.gap : key.capH) - 2
        clip: true

        Behavior on y {
            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
        }

        // Shift-Zeichen oben links
        Text {
            id: subText

            anchors {
                left: parent.left
                top: parent.top
                leftMargin: key.pad
                topMargin: key.pad * 0.5
            }
            visible: key.showMinor && (key.spec.sub ?? "") !== ""
            text: key.spec.sub ?? ""
            color: key.legendDim
            font.family: Config.font
            font.pixelSize: Math.max(8, Math.round(key.unit * 0.19))
            font.weight: Font.Medium
        }

        // Hauptlegende: mit Shift-Zeichen unten links, sonst oben links
        Text {
            anchors {
                left: parent.left
                leftMargin: key.pad
                top: subText.visible ? undefined : parent.top
                topMargin: key.pad * 0.6
                bottom: subText.visible ? parent.bottom : undefined
                bottomMargin: key.pad * 0.6
            }
            visible: !key.spec.icon && !key.centered
            width: parent.width - key.pad - 2
            text: key.spec.label
            color: key.legend
            opacity: key.disabled ? 0.7 : 1
            font.family: Config.font
            // F10–F12 wie F1–F9, nicht wie Esc/Druck
            font.pixelSize: key.spec.label.length > 2 && !/^F\d+$/.test(key.spec.label) ? Math.max(8, Math.round(key.unit * 0.19))
                          : Math.max(10, Math.round(key.unit * 0.29))
            font.weight: Font.Medium
            font.strikeout: key.disabled
            elide: Text.ElideRight

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
        }

        // Pfeile und Symbol-Tasten stehen mittig
        Text {
            anchors.centerIn: parent
            visible: key.spec.icon || key.centered
            text: key.spec.icon ? key.spec.icon : key.spec.label
            color: key.legend
            opacity: key.disabled ? 0.7 : 1
            font.family: key.spec.icon ? "Material Symbols Outlined" : Config.font
            font.pixelSize: Math.max(11, Math.round(key.unit * (key.spec.icon ? 0.4 : 0.34)))
            font.weight: Font.Medium

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
        }

        // AltGr-Zeichen / Zweitfunktion unten rechts
        Text {
            anchors {
                right: parent.right
                bottom: parent.bottom
                rightMargin: key.pad * 0.8
                bottomMargin: key.pad * 0.5
            }
            visible: key.showMinor && (key.spec.alt ?? "") !== ""
            text: key.spec.alt ?? ""
            // Belegung ueber den Zweitnamen: dieses Zeichen leuchtet
            color: key.info?.via ? key.legend : key.legendDim
            font.family: Config.font
            font.pixelSize: Math.max(8, Math.round(key.unit * (key.spec.alt.length > 1 ? 0.15 : 0.19)))
        }
    }

    HoverHandler {
        id: hover

        enabled: key.interactive
        cursorShape: key.clickable ? Qt.PointingHandCursor
                   : key.pick && key.occupied ? Qt.ForbiddenCursor
                   : Qt.ArrowCursor
    }

    TapHandler {
        enabled: key.clickable
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (point, button) => {
            if (button === Qt.RightButton)
                key.contextClicked();
            else
                key.clicked();
        }
    }
}
