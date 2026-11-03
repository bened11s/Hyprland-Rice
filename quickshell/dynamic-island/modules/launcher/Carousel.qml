pragma ComponentBehavior: Bound
import QtQuick

// Gemeinsames Karussell der Auswahl-Panels (Wallpaper, Theme): eine Reihe von
// Kacheln auf einer geraden Linie, die markierte in der Mitte und groesser,
// die Nachbarn kleiner.
//
// Alles, was mit dem
// Inhalt zu tun hat (Modell, Delegat, Auswahl), bringen die Nutzer mit; hier
// steht nur die Mechanik.
PathView {
    id: view

    // Breite einer Kachel samt Zwischenraum – daraus faellt alles Weitere
    property real itemWidth: 176

    // Der Pfad reicht links und rechts je eine halbe Kachel ueber den Rand
    // hinaus und traegt zwei Kacheln mehr. Die beiden aeussersten haengen damit
    // halb draussen und laufen in der Vignette des Panels aus, statt dass die
    // Reihe an beiden Seiten hart aufhoert (so macht es der Datumsstreifen).
    readonly property real overhang: view.itemWidth / 2

    // Mit dem Rad geblaettert – wer zwei Reihen hat, holt die Tastatur in
    // diese (WallpaperPanel)
    signal wheeled

    // Immer eine ungerade Zahl: sonst sitzt keine Kachel wirklich in der Mitte.
    readonly property int visibleItems: {
        const fits = Math.floor(view.width / view.itemWidth);
        if (fits <= 1)
            return 1;
        return fits % 2 === 0 ? fits - 1 : fits;
    }

    function moveBy(delta: int): void {
        if (view.count === 0)
            return;
        view.currentIndex = (view.currentIndex + delta + view.count) % view.count;
    }

    // Auswahl setzen UND das Karussell dorthin ruecken. currentIndex allein
    // reicht nicht: der Versatz bleibt nach einem Modellwechsel stehen, die
    // markierte Kachel sass dann neben der Mitte statt darin.
    function snapTo(index: int): void {
        if (view.count === 0)
            return;
        view.currentIndex = Math.max(0, Math.min(view.count - 1, index));
        view.positionViewAtIndex(view.currentIndex, PathView.SnapPosition);
    }

    pathItemCount: view.visibleItems + 2
    cacheItemCount: 2

    snapMode: PathView.SnapToItem
    preferredHighlightBegin: 0.5
    preferredHighlightEnd: 0.5
    highlightRangeMode: PathView.StrictlyEnforceRange
    highlightMoveDuration: 180

    // Mausrad blaettert durchs Karussell. Hi-Res-Raeder liefern Bruchteile
    // einer Rastung, deshalb aufsummieren (gleiches Muster wie im DatePanel).
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        property real accum: 0

        onWheel: event => {
            const angle = event.angleDelta.y + event.angleDelta.x;
            const pixels = event.pixelDelta.y + event.pixelDelta.x;
            accum += angle !== 0 ? angle / 120 : pixels / 40;

            const steps = accum > 0 ? Math.floor(accum) : Math.ceil(accum);
            if (steps !== 0) {
                accum -= steps;
                view.wheeled();
                view.moveBy(-steps);
            }
            event.accepted = true;
        }
    }

    path: Path {
        // Beide Haelften gleich lang, sonst stehen die Kacheln ungleichmaessig
        startX: -view.overhang
        startY: view.height / 2

        PathAttribute {
            name: "itemZ"
            value: 0
        }
        PathLine {
            x: view.width / 2
            relativeY: 0
        }
        PathAttribute {
            name: "itemZ"
            value: 1
        }
        PathLine {
            x: view.width + view.overhang
            relativeY: 0
        }
    }
}
