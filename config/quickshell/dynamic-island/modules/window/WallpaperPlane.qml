pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

// Eine Bildebene der WallpaperStage. Es gibt immer zwei davon: die vordere
// zeigt das aktuelle Bild bzw. blendet beim Wechsel das neue ein, die hintere
// haelt waehrenddessen das alte (oder laedt unsichtbar das naechste).
//
// Wie die Ebene sich bewegt, sagt die Stage ueber kind/progress/isFront –
// hier steht nur, wie jede Animation aussieht.
Item {
    id: plane

    // ---- von der Stage ----
    property size decodeSize
    property bool isFront: false
    property bool transitioning: false
    property string kind: "blende"
    property real progress: 1

    // ---- Bild ----
    property string path: ""
    // Kleines Bild (Thumb): in seiner Groesse dekodieren, nicht in decodeSize
    // – mit PreserveAspectCrop rechnet Qt sonst auch hoch
    property bool small: false
    readonly property bool ready: plane.path !== "" && img.status === Image.Ready

    // Laesst sich das Bild nicht laden (geloescht, kaputt, falscher Pfad),
    // kommt statt einer leeren Flaeche das hier. Nur ein Versuch – scheitert
    // auch der Fallback, bleibt es eben leer.
    readonly property url fallback: Qt.resolvedUrl("../../assets/wallpaper-error.jpg")
    property bool failed: false

    function load(p: string, small: bool): void {
        plane.path = p;
        plane.failed = false;
        // Vor der Quelle setzen: sourceSize wechseln laedt neu
        plane.small = small;
        img.source = p !== "" ? `file://${p}` : "";
    }

    readonly property bool animFront: plane.isFront && plane.transitioning
    readonly property bool animBack: !plane.isFront && plane.transitioning
    readonly property real p: plane.animFront ? plane.progress : 1

    width: parent?.width ?? 0
    height: parent?.height ?? 0
    z: plane.isFront ? 1 : 0
    // Hinten nur sichtbar, solange das alte Bild durchscheint – laedt dort
    // schon das naechste, soll davon nichts zu sehen sein (Bilder mit Alpha)
    visible: plane.isFront || plane.transitioning

    // blende: Deckkraft. zoom: Deckkraft und von gross auf normal.
    opacity: plane.animFront && (plane.kind === "blende" || plane.kind === "zoom") ? plane.p : 1

    // schieben: das neue faehrt von rechts herein, das alte weicht mit
    // weniger Weg nach links aus (Parallaxe statt starrer Schiebetuer)
    x: plane.kind !== "schieben" ? 0
        : plane.animFront ? plane.width * (1 - plane.p)
        : plane.animBack ? -plane.width * 0.3 * plane.progress
        : 0

    // kreis: das neue Bild waechst als Kreis aus der Insel oben in der Mitte
    readonly property bool masked: plane.animFront && plane.kind === "kreis"

    // wischen: das neue schiebt sich als Kante von links nach rechts drueber
    readonly property bool wiping: plane.animFront && plane.kind === "wischen"

    Item {
        id: window

        width: plane.wiping ? plane.width * plane.p : plane.width
        height: plane.height
        clip: plane.wiping

        Image {
            id: img

            width: plane.width
            height: plane.height
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Nur in Bildschirmgroesse decodieren (statt z. B. 6K voll) und
            // ueber den Cache teilen – beide Monitore zeigen dasselbe Bild.
            // Ein Thumb bleibt klein (0x0 = Originalgroesse) und wird nur
            // beim Zeichnen hochgezogen (smooth)
            sourceSize: plane.small ? Qt.size(0, 0) : plane.decodeSize
            smooth: true
            cache: true
            visible: !plane.masked

            onStatusChanged: {
                if (status === Image.Error && plane.path !== "" && !plane.failed) {
                    console.warn("Wallpaper laedt nicht, nehme Fallback:", plane.path);
                    plane.failed = true;
                    img.source = plane.fallback;
                }
            }

            scale: plane.kind !== "zoom" ? 1
                : plane.animFront ? 1.12 - 0.12 * plane.p
                : plane.animBack ? 1 + 0.04 * plane.progress
                : 1
        }

        Item {
            id: circle

            anchors.fill: img
            visible: false
            // Dauerhaft an: schaltet man den Layer erst zum Uebergang ein,
            // behaelt MultiEffect die leere Textur von vorher und das neue
            // Bild bleibt unsichtbar. Dafuer in Viertelaufloesung – das spart
            // Grafikspeicher und macht die Kreiskante beim Hochskalieren weich.
            layer.enabled: true
            layer.smooth: true
            layer.textureSize: Qt.size(Math.max(1, width / 4), Math.max(1, height / 4))

            Rectangle {
                // Bis in die unteren Ecken: von oben-mitte aus gemessen
                readonly property real reach: Math.hypot(plane.width / 2, plane.height)

                width: 2 * reach * plane.p
                height: width
                radius: width / 2
                x: (plane.width - width) / 2
                y: -height / 2
                color: "black"
                antialiasing: true
            }
        }

        MultiEffect {
            anchors.fill: img
            visible: plane.masked

            source: img
            maskEnabled: true
            maskSource: circle
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    // Weicher Schatten an der Wischkante, damit sie wie ein Blatt ueber dem
    // alten Bild liegt statt wie ein harter Schnitt
    Rectangle {
        visible: plane.wiping
        x: window.width
        width: 48
        height: plane.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
