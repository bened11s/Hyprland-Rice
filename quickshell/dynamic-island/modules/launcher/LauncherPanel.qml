pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs
import qs.modules.services.config

// Launcher-Inhalt der Notch: Suchfeld mit Favoriten-Schalter und Trefferliste.
// Steckt wie das DatePanel in der Karte der Notch – die sagt nur, wo es
// anfängt (`topOffset`) und wie rund die Kartenecken sind.
//
// Drei Quellen:
//   ohne Präfix   Desktop-Einträge (Favoriten zuerst)
//   `>`           Aktionen aus LauncherActions, sonst als Shell-Befehl
//   `>name ...`   eigener Listen-Modus, falls unter `modes` registriert
//
// Die Wallpaper-Auswahl ist bewusst NICHT hier drin, sondern eine eigene
// Ansicht mit eigenem Suchfeld (WallpaperPanel.qml) – die Notch zeigt je nach
// LauncherState.mode die eine oder die andere.
Item {
    id: panel

    // ---- Schnittstelle zur Notch ----
    property real topOffset: 0
    property real cardRadius: 18
    property real inset: 2
    property bool active: false          // true, solange der Launcher offen ist

    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    // Höhe, die die Karte im schlimmsten Fall braucht (für die Fenster-Reserve)
    readonly property real maxOuterHeight: searchRow.height + 1 + maxListHeight + 12 + inset

    // Eigene Listen-Modi: { wallpaper: quelle, ... }
    // Eine Quelle braucht `results(query)` -> [{ name, desc, icon }]
    // und `activate(item)`.
    property var modes: ({})

    readonly property string prefix: ">"
    readonly property real maxListHeight: 340
    readonly property int maxResults: 40

    readonly property bool actionMode: search.text.startsWith(prefix)
    readonly property string actionQuery: search.text.slice(prefix.length)
    readonly property string modeName: actionMode ? actionQuery.split(" ")[0] : ""
    readonly property var modeSource: panel.modes[modeName] ?? null
    readonly property string modeQuery: actionQuery.slice(modeName.length + 1)

    property bool favoritesOnly: false

    // Treffer als schlichte Objekte: { kind, name, desc, icon, ... }
    readonly property var results: {
        if (panel.modeSource)
            return panel.modeResults();
        if (panel.actionMode)
            return panel.actionResults();
        return panel.appResults(search.text.trim().toLowerCase());
    }

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: panel.inset
        rightMargin: panel.inset
    }
    y: panel.topOffset
    implicitWidth: 620
    implicitHeight: searchRow.height + 1 + listWrapper.implicitHeight

    // Per LazyPanel entsteht die Ansicht bereits aktiv – dann gibt es kein
    // Wechsel-Signal, die Startarbeit (Fokus, Suchfeld) wird nachgeholt
    Component.onCompleted: {
        LauncherState.warmApps();
        if (panel.active)
            Qt.callLater(panel.activeChanged);
    }

    onActiveChanged: {
        if (active) {
            search.text = "";
            panel.favoritesOnly = false;
            search.forceActiveFocus();
        }
    }

    onResultsChanged: list.currentIndex = results.length > 0 ? 0 : -1

    // ---- Quellen ----
    // Einfaches Scoring: Namenstreffer schlagen Beschreibungstreffer, 0 fliegt raus
    function score(entry: var, needle: string): int {
        const name = entry.name.toLowerCase();
        if (needle === "")
            return 1;
        if (name === needle)
            return 100;
        if (name.startsWith(needle))
            return 80;
        if (name.includes(needle))
            return 60;

        const haystack = [entry.genericName, entry.comment, entry.keywords, entry.id].join(" ").toLowerCase();
        return haystack.includes(needle) ? 30 : 0;
    }

    function appResults(needle: string): var {
        const scored = [];
        for (const entry of LauncherState.apps) {
            if (entry.noDisplay)
                continue;

            const favorite = LauncherFavorites.isFavorite(entry.id);
            if (panel.favoritesOnly && !favorite)
                continue;

            const points = panel.score(entry, needle);
            if (points > 0)
                scored.push({
                    points: points + (favorite ? 10 : 0),   // Favoriten nach oben
                    kind: "app",
                    name: entry.name,
                    desc: entry.comment || entry.genericName || "",
                    icon: entry.icon,
                    id: entry.id,
                    favorite,
                    entry
                });
        }

        scored.sort((a, b) => b.points - a.points || a.name.localeCompare(b.name));
        return scored.slice(0, panel.maxResults);
    }

    function actionResults(): var {
        const hits = LauncherActions.search(panel.actionQuery).map(action => ({
            kind: "action",
            name: I18n.tr(action.name),
            desc: I18n.tr(action.desc),
            icon: action.icon,
            action
        }));

        // Kein Treffer, aber etwas getippt -> als Shell-Befehl anbieten
        const raw = panel.actionQuery.trim();
        if (hits.length === 0 && raw !== "")
            hits.push({
                kind: "command",
                name: raw,
                desc: I18n.tr("Als Befehl ausführen"),
                icon: "terminal",
                command: raw
            });

        return hits;
    }

    function modeResults(): var {
        return panel.modeSource.results(panel.modeQuery).map(item => ({
            kind: "mode",
            name: item.name,
            desc: item.desc ?? "",
            icon: item.icon ?? "",
            item
        }));
    }

    // ---- Auslösen ----
    function activate(index: int): void {
        const hit = panel.results[index];
        if (!hit)
            return;

        if (hit.kind === "app") {
            hit.entry.execute();
        } else if (hit.kind === "action") {
            if (hit.action.mode) {
                // Autocomplete: Liste in den Modus schalten, offen lassen
                search.text = `${panel.prefix}${hit.action.mode} `;
                return;
            }
            hit.action.run();
            // Aktionen, die die Karte umschalten statt etwas auszufuehren,
            // duerfen sie nicht gleich wieder zumachen
            if (hit.action.keepOpen)
                return;
        } else if (hit.kind === "command") {
            Quickshell.execDetached(["sh", "-lc", hit.command]);
        } else if (hit.kind === "mode") {
            panel.modeSource.activate(hit.item);
        }

        LauncherState.close();
    }

    function move(delta: int): void {
        const count = panel.results.length;
        if (count === 0)
            return;
        list.currentIndex = (list.currentIndex + delta + count) % count;
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    function toggleFavorite(index: int): void {
        const hit = panel.results[index];
        if (hit?.kind === "app")
            LauncherFavorites.toggle(hit.id);
    }

    // ---- Suchzeile ----
    Item {
        id: searchRow

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 50

        Text {
            id: searchIcon

            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: panel.modeSource ? "list" : panel.actionMode ? "terminal" : "search"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 19
            color: panel.actionMode ? Colors.primary : Colors.fgSurfaceVariant
        }

        TextInput {
            id: search
            font.family: Config.font

            anchors {
                left: searchIcon.right
                leftMargin: 12
                right: actionsButton.left
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            color: Colors.fgSurface
            font.pixelSize: 14
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            selectedTextColor: Colors.fgSurface
            clip: true

            Keys.onEscapePressed: LauncherState.close()
            Keys.onUpPressed: panel.move(-1)
            Keys.onDownPressed: panel.move(1)
            Keys.onTabPressed: panel.move(1)
            Keys.onReturnPressed: panel.activate(list.currentIndex)
            Keys.onEnterPressed: panel.activate(list.currentIndex)

            Text {
                anchors.fill: parent
                visible: search.text === ""
                text: panel.favoritesOnly ? I18n.tr("Favoriten durchsuchen…") : I18n.tr("Suchen…   >  für Aktionen")
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                font: search.font
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Aktionen-Menue: dieselbe Liste wie mit `>` getippt, nur per Klick
        SearchButton {
            id: actionsButton

            anchors {
                right: favoriteButton.left
                rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            checked: panel.actionMode
            glyph: "tune"
            glyphFamily: "Material Symbols Outlined"
            glyphSize: 19
            onClicked: {
                panel.favoritesOnly = false;
                search.text = panel.actionMode ? "" : panel.prefix;
                search.forceActiveFocus();
            }
        }

        // Favoriten-Filter
        SearchButton {
            id: favoriteButton

            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            checked: panel.favoritesOnly
            // Unicode statt Material Symbols: die gefüllte Variante gibt es
            // dort nur über die FILL-Achse, und die greift mit dieser
            // Schriftdatei nicht (fontconfig meldet sie als nicht-variabel).
            glyph: panel.favoritesOnly ? "★" : "☆"
            onClicked: {
                // Favoriten filtern nur Apps – aus den Aktionen geht es zurück
                if (panel.actionMode)
                    search.text = "";
                panel.favoritesOnly = !panel.favoritesOnly;
                search.forceActiveFocus();
            }
        }
    }

    Rectangle {
        id: separator

        anchors {
            top: searchRow.bottom
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.alpha(Colors.outline, 0.35)
    }

    // ---- Trefferliste ----
    Item {
        id: listWrapper

        anchors {
            top: separator.bottom
            left: parent.left
            right: parent.right
        }
        // Ohne Treffer traegt die Liste nichts bei (contentHeight == 0). Dann
        // waere der Wrapper nur 12px hoch, waehrend der Hinweis darunter rund
        // 16px braucht -- er ragte unten aus der Karte heraus und stand damit
        // ohne Hintergrund vor den Fenstern dahinter. Im leeren Fall richtet
        // sich die Hoehe deshalb nach dem Hinweis.
        implicitHeight: panel.results.length === 0
            ? emptyHint.implicitHeight + 24
            : Math.min(panel.maxListHeight, list.contentHeight + 12)

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: 6
            clip: true
            spacing: 2
            model: panel.results
            boundsBehavior: Flickable.StopAtBounds
            // Ohne Highlight-Item trotzdem aus: sonst fuehrt die ListView ein
            // unsichtbares Highlight dem aktuellen Eintrag nach (400 px/s, auch
            // highlightMoveDuration: 0 zaehlt als "nicht gesetzt") – bei ~600 px
            // Zeilenbreite zeichnete das Fenster nach jedem Oeffnen 1,5 s mit 180 Hz.
            highlightFollowsCurrentItem: false

            // Mausrad: weich animiert, drei Zeilen pro Rastung. Hi-Res-Räder
            // liefern Bruchteile davon, das ergibt hier von selbst ein
            // stufenloses Scrollen.
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const angle = event.angleDelta.y + event.angleDelta.x;
                    const pixels = event.pixelDelta.y + event.pixelDelta.x;
                    const delta = angle !== 0 ? angle / 120 : pixels / 40;

                    const step = 46 * 3;
                    const max = Math.max(0, list.contentHeight - list.height);
                    const from = scrollAnim.running ? scrollAnim.to : list.contentY;
                    const to = Math.max(0, Math.min(max, from - delta * step));

                    scrollAnim.stop();
                    scrollAnim.from = list.contentY;
                    scrollAnim.to = to;
                    scrollAnim.start();
                    event.accepted = true;
                }
            }

            NumberAnimation {
                id: scrollAnim

                target: list
                property: "contentY"
                duration: 160
                easing.type: Easing.OutCubic
            }

            // modelData deklariert ResultItem selbst – hier nochmal `required`
            // zu schreiben würde es verschatten, dann bleibt es in der Basis
            // uninitialisiert und der Delegat stirbt.
            delegate: ResultItem {
                required property int index

                width: ListView.view.width
                position: index
                selected: list.currentIndex === index

                onActivated: panel.activate(index)
                onHovered: list.currentIndex = index
                onFavoriteToggled: panel.toggleFavorite(index)
            }
        }

        Text {
            id: emptyHint
            font.family: Config.font

            anchors.centerIn: parent
            // Leere Favoritenliste bleibt leer
            opacity: panel.results.length === 0 && !panel.favoritesOnly ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 140 }
            }

            text: I18n.tr("Keine Treffer")
            color: Colors.fgSurfaceVariant
            font.pixelSize: 12
        }
    }

    // Runder Knopf in der Suchzeile (Aktionen, Favoriten)
    component SearchButton: Rectangle {
        id: button

        property bool checked: false
        property string glyph: ""
        property string glyphFamily: Config.font
        property int glyphSize: 17

        signal clicked()

        width: 32
        height: 32
        radius: height / 2
        color: button.checked ? Colors.alpha(Colors.primary, 0.18)
             : buttonArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08)
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: 90 }
        }

        MouseArea {
            id: buttonArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }

        Text {
            anchors.centerIn: parent
            text: button.glyph
            font.family: button.glyphFamily
            font.pixelSize: button.glyphSize
            color: button.checked ? Colors.primary : Colors.fgSurfaceVariant
        }
    }
}
