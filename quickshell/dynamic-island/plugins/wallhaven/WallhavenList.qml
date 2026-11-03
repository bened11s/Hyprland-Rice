pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.modules.launcher
import qs.modules.services.wallpaper

import qs
import qs.modules.services.config

// Wallhaven-Treffer in der Wallpaper-Auswahl: dasselbe Karussell wie die
// lokale Reihe (WallpaperList), nur mit Bildern, die noch nicht da sind.
//
// Die Kacheln zeigen das kleine Vorschaubild von Wallhaven (432x243, von
// wallhaven.py gecacht), solange es noch laedt einen Platzhalter. Dazu die
// Aufloesung, ein Haekchen, wenn das Bild schon im Wallpaper-Ordner liegt,
// und waehrend des Downloads einen Ring auf der Kachel. Klick/Enter laedt
// und setzt, Rechtsklick/Shift+Enter laedt nur. Nahe dem Ende haengt sich
// die naechste Seite an.
//
// Beim Blaettern zeigt der Hintergrund den Treffer wie in der lokalen Reihe
// – zuerst als hochgezogenes Thumb (Wallpapers.previewThumb, Farben wie
// gehabt). Bleibt die Auswahl kurz stehen (hqTimer) und die Einstellung
// fullPreview ist an, holt der Dienst das Vollbild in den Cache und liefert
// eine Vorschau in Bildschirmbreite (`hq`), auf die der Hintergrund dann
// hochzieht; Weiterblaettern bricht den Abruf ab. Liegt das Bild schon
// lokal, zeigt der Hintergrund gleich die Datei. Kommt Thumb oder HQ erst
// nach der Auswahl an, zieht die Vorschau nach.
Carousel {
    id: view

    // Der Dienst (Main.qml): Treffer, Seiten, Downloads
    required property var wh

    // Hat diese Reihe die Tastatur? Sonst ist der Rahmen gedimmt und die
    // Vorschau bleibt aus.
    property bool focused: false
    // Von der Sektion vorgegeben, wie bei WallpaperList
    property real imageWidth: 160
    readonly property real imageHeight: Math.round(imageWidth / 16 * 9)
    readonly property real itemPadding: 8
    itemWidth: view.imageWidth + view.itemPadding * 2

    // Geklickt: die Sektion holt die Tastatur in diese Reihe
    signal activated

    readonly property string currentId: view.currentItem?.wid ?? ""
    readonly property string currentThumb: view.currentItem?.thumb ?? ""
    readonly property string currentLocal: view.currentItem?.local ?? ""
    readonly property string currentHq: view.currentItem?.hq ?? ""
    // Beste Vorschau, die es fuer die markierte Kachel schon gibt
    readonly property string currentBest: view.currentLocal || view.currentHq

    // Uebernehmen: herunterladen und (apply) setzen – fertig setzt der
    // Dienst das Bild und schliesst die Auswahl
    function apply(set: bool): void {
        if (view.currentId !== "")
            view.wh.download(view.currentId, set);
    }

    function previewNow(): void {
        previewTimer.restart();
        hqTimer.restart();
    }

    implicitHeight: view.itemPadding + view.imageHeight + 4 + 15 + view.itemPadding

    model: view.wh.items

    // Neue Suche: vorne anfangen (siehe snapTo – der Versatz bleibt sonst
    // vom alten Modell stehen)
    Connections {
        target: view.wh

        function onPageChanged(): void {
            if (view.wh.page === 1)
                Qt.callLater(() => view.snapTo(0));
        }
    }

    onCurrentIndexChanged: {
        // Weitergeblaettert: ein laufender Abruf gilt dem alten Bild
        if (view.wh.prefetchingId !== "" && view.wh.prefetchingId !== view.currentId)
            view.wh.cancelPrefetch();
        view.previewNow();
        // Die letzten fuenf Kacheln: Nachschub holen, bevor man ankommt
        if (view.count > 0 && view.currentIndex >= view.count - 5)
            view.wh.loadMore();
    }

    // Reihe verlassen oder zu: nichts mehr holen, was niemand sieht
    onFocusedChanged: {
        if (!view.focused) {
            hqTimer.stop();
            view.wh.cancelPrefetch();
        }
    }
    Component.onDestruction: view.wh.cancelPrefetch()

    // Erst nach kurzem Verweilen, wie in der lokalen Reihe – sonst laeuft
    // jeder Tastendruck in einen Hintergrund-Uebergang
    Timer {
        id: previewTimer

        interval: 160
        onTriggered: {
            if (!view.focused)
                return;
            if (view.currentBest !== "")
                Wallpapers.preview(view.currentBest);
            else if (view.currentThumb !== "")
                Wallpapers.previewThumb(view.currentThumb);
        }
    }

    // Laenger verweilt: das Vollbild holen (der Dienst prueft die
    // Einstellung und ob es schon da ist)
    Timer {
        id: hqTimer

        interval: 500
        onTriggered: {
            if (view.focused && view.currentId !== "" && view.currentBest === "")
                view.wh.prefetch(view.currentId);
        }
    }

    // 5781 -> "5,8k", 1234567 -> "1,2M"
    function compact(n: int): string {
        if (n >= 1000000)
            return (n / 1000000).toFixed(1).replace(".", ",") + "M";
        if (n >= 1000)
            return (n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(".", ",") + "k";
        return String(n);
    }

    delegate: Item {
        id: item

        required property int index
        required property string wid
        required property string thumb
        required property string resolution
        required property int favorites
        required property int views
        required property string local
        required property string hq
        required property string phase

        readonly property bool isCurrent: PathView.isCurrentItem
        readonly property bool onPath: PathView.onPath
        readonly property bool downloading: item.phase === "downloading"
        // Die HQ-Vorschau fuer diese Kachel ist unterwegs
        readonly property bool fetching: view.wh.prefetchingId === item.wid

        width: view.itemWidth
        height: view.height
        z: PathView.itemZ ?? 0

        scale: item.isCurrent ? 1 : item.onPath ? 0.86 : 0.5
        opacity: item.onPath ? 1 : 0

        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        // Kommt Thumb oder HQ-Vorschau der markierten Kachel nach, Vorschau
        // nachholen (previewNow laesst den HQ-Abruf nicht nochmal anlaufen,
        // der Dienst kennt den Stand)
        onThumbChanged: if (item.isCurrent) view.previewNow()
        onHqChanged: if (item.isCurrent && item.hq !== "") previewTimer.restart()

        // Keine Auswahl per Hover – siehe WallpaperList
        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (point, button) => {
                view.currentIndex = item.index;
                view.activated();
                view.apply(button !== Qt.RightButton);
            }
        }

        Rectangle {
            id: frame

            anchors.horizontalCenter: parent.horizontalCenter
            y: view.itemPadding

            width: view.imageWidth
            height: view.imageHeight
            radius: 12
            color: Colors.surfaceContainer
            border.width: item.isCurrent ? 2 : 0
            border.color: view.focused ? Colors.primary : Colors.alpha(Colors.primary, 0.4)

            Behavior on border.width {
                NumberAnimation { duration: 140 }
            }
            Behavior on border.color {
                ColorAnimation { duration: 140 }
            }

            // Platzhalter, solange das Thumb noch unterwegs ist: pulsiert
            // leicht, damit "laedt" von "kaputt" zu unterscheiden ist. Nur
            // solange der Prozess noch Thumbs liefert - ein nie ankommendes
            // Thumb (Timeout) liesse die Shell sonst endlos neu zeichnen
            Text {
                id: placeholder

                readonly property bool pending: item.thumb === "" && view.wh.busy

                anchors.centerIn: parent
                visible: thumb.status !== Image.Ready

                text: placeholder.pending ? "hourglass_top" : "image"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 22

                SequentialAnimation on opacity {
                    running: placeholder.visible && placeholder.pending
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                    onStopped: placeholder.opacity = 1
                }
            }

            Image {
                id: thumb

                anchors.fill: parent
                anchors.margins: frame.border.width

                // Nur das kleine Vorschaubild (siehe WallpaperList: Qt
                // dekodiert alles in einem Thread)
                source: item.thumb !== "" ? `file://${item.thumb}` : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: !view.moving
                visible: false          // nur Quelle fuer die Maske
            }

            Item {
                id: thumbMask

                anchors.fill: thumb
                layer.enabled: true
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: frame.radius - frame.border.width
                    color: "black"
                }
            }

            MultiEffect {
                anchors.fill: thumb
                visible: thumb.status === Image.Ready

                source: thumb
                maskEnabled: true
                maskSource: thumbMask
            }

            // Aufloesung unten links
            Rectangle {
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                    margins: 6
                }
                width: resolutionLabel.implicitWidth + 10
                height: 16
                radius: 5
                color: Colors.alpha("#000000", 0.55)

                Text {
                    id: resolutionLabel

                    anchors.centerIn: parent
                    text: item.resolution
                    font.family: Config.font
                    font.pixelSize: 9
                    color: "#ffffff"
                }
            }

            // HQ-Vorschau: unten rechts ein kleines "hd", pulsierend solange
            // sie laedt, danach still – dezent, nur als Hinweis, warum der
            // Hintergrund gleich scharf wird
            Text {
                id: hqBadge

                anchors {
                    right: parent.right
                    bottom: parent.bottom
                    margins: 6
                }
                visible: item.fetching || item.hq !== ""
                text: "hd"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 14
                color: item.fetching ? Colors.primary : Colors.alpha("#ffffff", 0.75)
                style: Text.Outline
                styleColor: Colors.alpha("#000000", 0.6)

                SequentialAnimation on opacity {
                    running: item.fetching
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 500; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutSine }
                    onStopped: hqBadge.opacity = 1
                }
            }

            // Schon im Wallpaper-Ordner
            Rectangle {
                anchors {
                    right: parent.right
                    top: parent.top
                    margins: 6
                }
                width: 18
                height: 18
                radius: 9
                visible: item.local !== ""
                color: Colors.primary

                Text {
                    anchors.centerIn: parent
                    text: "check"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 12
                    color: Colors.fgPrimary
                }
            }

            // Download laeuft (oder ist gescheitert): Schleier ueber dem Bild.
            // Inhalt haengt an `phase`, nicht an `downloading`: beim
            // Ausblenden nach dem Download stand sonst kurz "Fehler" da.
            Rectangle {
                anchors.fill: parent
                anchors.margins: frame.border.width
                radius: frame.radius - frame.border.width
                color: Colors.alpha("#000000", 0.55)
                visible: opacity > 0
                opacity: item.downloading || item.phase === "error" ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 160 }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        id: spinner

                        anchors.horizontalCenter: parent.horizontalCenter
                        text: item.phase === "error" ? "error" : "progress_activity"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 24
                        color: item.phase === "error" ? Colors.error : Colors.primary

                        RotationAnimation on rotation {
                            running: item.downloading
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                            onStopped: spinner.rotation = 0
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: item.phase === "error" ? I18n.tr("Fehler") : I18n.tr("lädt…")
                        font.family: Config.font
                        font.pixelSize: 10
                        color: "#ffffff"
                    }
                }
            }
        }

        // Unter der Kachel: Favoriten und Aufrufe statt eines Dateinamens
        Row {
            id: stats

            anchors {
                top: frame.bottom
                topMargin: 4
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 8

            readonly property color tint: item.isCurrent ? Colors.fgSurface : Colors.fgSurfaceVariant

            Row {
                spacing: 3

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "favorite"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 11
                    color: stats.tint
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.compact(item.favorites)
                    font.family: Config.font
                    font.pixelSize: 11
                    color: stats.tint
                }
            }

            Row {
                spacing: 3

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "visibility"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 11
                    color: stats.tint
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: view.compact(item.views)
                    font.family: Config.font
                    font.pixelSize: 11
                    color: stats.tint
                }
            }
        }
    }
}
