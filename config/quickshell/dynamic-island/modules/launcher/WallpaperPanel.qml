pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.modules.services.plugins
import qs.modules.services.theme
import qs.modules.services.wallpaper

import qs
import qs.modules.bar.components.notch
import qs.modules.services.config
import qs.modules.widgets

// Wallpaper-Auswahl der Notch: eigenes Suchfeld und darunter das Karussell.
//
// Steckt wie LauncherPanel und DatePanel in der Karte der Notch und ist deren
// dritte Ansicht – welche gilt, sagt LauncherState.mode. Bewusst ein eigenes
// Panel statt eines Modus im Launcher: eigenes Suchfeld, eigene Breite.
//
// Unter der Stil-Reihe koennen Plugins eine Sektion anhaengen (Manifest
// `panels.wallpaper`, Plugins.panels): je Sektion ein Knopf in der Suchzeile,
// aufgeklappt ist hoechstens eine. Die lokale Reihe bleibt dabei stehen, die
// Notch waechst nur nach unten (Morph). Welche offen ist, merkt sich
// LauncherState – ueber das Schliessen hinweg, das Panel entsteht ja jedes
// Mal neu.
//
// Vertrag mit der Sektion (plugins/README.md, "Sektionen"): das Panel laedt
// ihre QML-Datei mit `plugin` (Kontext) und `host` (s.u.); sie bringt ihr
// Suchfeld und ihre Tasten selbst mit und meldet ueber host zurueck. Ihre
// implicitHeight sagt, wie weit die Karte waechst.
//
// Tasten (im lokalen Suchfeld; die Sektion belegt ihres gleich):
//   Esc               schliessen
//   Links/Rechts, Tab blaettern in der Reihe
//   Hoch/Runter       Sektion zu: blaettern; offen: Tastatur in die Sektion
//   Enter             setzen
//   Strg+Links/Rechts Stil des markierten lokalen Bilds wechseln
//   Strg+W            Sektionen durchschalten (auf, naechste, ..., zu)
Item {
    id: panel

    // ---- Schnittstelle zur Notch ----
    property real topOffset: 0
    property real cardRadius: 18
    property real inset: 2
    property bool active: false          // true, solange diese Ansicht offen ist

    readonly property real outerWidth: implicitWidth + inset * 2
    readonly property real outerHeight: implicitHeight + inset
    // Die Hoehe steht fest (siehe listHeight), Reserve und Ist sind dasselbe.
    // Die Notch fragt trotzdem danach, wie beim LauncherPanel.
    readonly property alias maxOuterHeight: panel.outerHeight

    // Feste Hoehe fuer den Bildbereich. Bewusst nicht aus dem Karussell
    // gelesen: das steckt in einem Loader und ist im geschlossenen Zustand gar
    // nicht da – die Notch braucht die Reserve aber schon vorher, sonst
    // schneidet das Fenster die Karte beim Aufgehen einen Frame lang ab.
    readonly property real listHeight: 145

    // Breiter als der Launcher, damit fuenf Bilder nebeneinander passen:
    // 988 nutzbare Breite / 191 je Kachel = 5 (PathView braucht eine ungerade
    // Zahl, sonst sitzt keines in der Mitte).
    implicitWidth: 1000
    // Kachelbreite; die Hoehe darunter haengt daran (16:9 + Beschriftung)
    readonly property real imageWidth: 175
    implicitHeight: searchRow.height + 1 + listWrapper.implicitHeight + 1 + styleRow.height
        + (panel.sectionOpen ? 1 + sectionWrapper.implicitHeight : 0)

    // ---- Plugin-Sektionen ----
    // [{ pluginId, icon, url, plugin }] der aktiven Plugins; offen ist die
    // mit der id aus LauncherState (und nur, solange es sie noch gibt)
    readonly property var sections: Plugins.panels.wallpaper ?? []
    readonly property string openSection: LauncherState.wallpaperSection
    readonly property var section: panel.sections.find(s => s.pluginId === panel.openSection) ?? null
    readonly property bool sectionOpen: panel.section !== null

    // Welche Reihe die Tastatur hat: "local" oder "section". Faengt bei
    // jedem Oeffnen lokal an, ausser LauncherState verlangt die Sektion.
    property string row: "local"
    readonly property bool sectionFocused: panel.sectionOpen && panel.row === "section"

    function focusRow(name: string): void {
        if (name === "section" && !panel.sectionOpen)
            name = "local";
        panel.row = name;
        // Die Sektion holt sich die Tastatur selbst, sobald host.focused kippt
        if (name === "local")
            search.forceActiveFocus();
    }

    // Zurueck in der lokalen Reihe: deren Vorschau nachholen – die Karussells
    // zeigen sie nur beim Blaettern. (Die Sektion macht das fuer sich, wenn
    // host.focused kippt.)
    onRowChanged: {
        if (panel.row === "local") {
            const path = walls.item?.currentPath ?? "";
            if (path !== "")
                Wallpapers.preview(path);
        }
    }

    // Sektion weg (zugeklappt, Plugin aus): die Tastatur darf nicht in ihrem
    // Suchfeld haengen bleiben
    onSectionOpenChanged: if (!panel.sectionOpen && panel.row === "section") panel.focusRow("local")

    // Aufklappen (""= zu); die Tastatur geht mit
    function openSectionTo(id: string): void {
        LauncherState.wallpaperSection = id;
        panel.focusRow(id !== "" ? "section" : "local");
    }

    // Knopf in der Suchzeile: dieselbe nochmal = zu
    function toggleSection(id: string): void {
        panel.openSectionTo(panel.openSection === id ? "" : id);
    }

    // Strg+W: erste auf, dann die naechste, nach der letzten zu
    function cycleSection(): void {
        const ids = panel.sections.map(s => s.pluginId);
        const at = ids.indexOf(panel.openSection);
        panel.openSectionTo(at + 1 < ids.length ? ids[at + 1] : "");
    }

    // Was die Sektion von der Auswahl sieht (Vertrag in plugins/README.md)
    readonly property QtObject host: QtObject {
        // Masse der lokalen Reihe, damit die Sektion dazu passt
        readonly property real listHeight: panel.listHeight
        readonly property real imageWidth: panel.imageWidth
        // Die Sektion hat die Tastatur: Suchfeld fokussieren, Vorschau ihrer
        // markierten Kachel zeigen. Kann beim Erzeugen schon true sein.
        readonly property bool focused: panel.sectionFocused
        // Pfad des markierten Bilds der lokalen Reihe ("" ohne Bilder) – fuer
        // Sektionen, die etwas zu diesem Bild zeigen (Terminal-Look)
        readonly property string currentPath: panel.targetPath

        // Die Sektion will die Tastatur (Klick oder Rad auf eine Kachel)
        function takeFocus(): void {
            panel.focusRow("section");
        }
        // Tastatur zurueck in die lokale Reihe (Hoch/Runter)
        function leaveFocus(): void {
            panel.focusRow("local");
        }
        // Strg+W in der Sektion: weiter zur naechsten bzw. zu
        function toggle(): void {
            panel.cycleSection();
        }
        // Auswahl schliessen (Esc)
        function close(): void {
            LauncherState.close();
        }
        // Strg+Links/Rechts: Stil des markierten lokalen Bilds
        function cycleStyle(delta: int): void {
            panel.cycleStyle(delta);
        }
        // Links/Rechts in einer Sektion ohne eigene Liste: in der lokalen
        // Reihe weiterblaettern (die Tastatur bleibt in der Sektion)
        function moveBy(delta: int): void {
            walls.item?.moveBy(delta);
        }
    }

    // Stil-Reihe unten: "auto" und die Material-Varianten. Sie gilt fuer das
    // markierte Bild, nicht fuer alle – die CLI merkt sich die Wahl je Bild.
    readonly property string targetPath: walls.item?.currentPath ?? ""
    readonly property var styles: [{ name: "auto", icon: "auto_awesome" }].concat(Themes.variants)

    // Feste Wahl des markierten Bilds, sonst "auto"
    readonly property string pinnedStyle: Wallpapers.variantFor(panel.targetPath) || "auto"

    // Was "auto" fuer das markierte Bild ergibt: aus der Vorschau, beim
    // gerade gesetzten Bild ohne Vorschau aus scheme.json
    readonly property string resolvedStyle: Wallpapers.previewPath === panel.targetPath && Wallpapers.previewVariant !== ""
        ? Wallpapers.previewVariant
        : panel.targetPath === Wallpapers.actualCurrent ? Themes.currentVariant : ""

    function pickStyle(name: string): void {
        Wallpapers.setVariant(panel.targetPath, name);
    }

    function cycleStyle(delta: int): void {
        const names = panel.styles.map(v => v.name);
        const at = Math.max(0, names.indexOf(panel.pinnedStyle));
        panel.pickStyle(names[(at + delta + names.length) % names.length]);
    }

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: panel.inset
        rightMargin: panel.inset
    }
    y: panel.topOffset

    // Per LazyPanel entsteht die Ansicht bereits aktiv – dann gibt es kein
    // Wechsel-Signal, die Startarbeit (Fokus, Suchfeld) wird nachgeholt
    Component.onCompleted: if (panel.active) Qt.callLater(panel.activeChanged)

    onActiveChanged: {
        if (active) {
            search.text = "";
            // Tastatur lokal – ausser jemand hat die Sektion verlangt
            // (showWallpaperSection, z.B. per IPC aus dem Plugin)
            const toSection = LauncherState.wallpaperSectionFocus && panel.sectionOpen;
            LauncherState.wallpaperSectionFocus = false;
            panel.focusRow(toSection ? "section" : "local");
        }
    }

    // Dasselbe bei schon offener Auswahl (die Sektion ist dann ueber die
    // Bindung an LauncherState.wallpaperSection bereits aufgeklappt)
    Connections {
        target: LauncherState

        function onWallpaperSectionFocusChanged(): void {
            if (LauncherState.wallpaperSectionFocus && panel.active) {
                LauncherState.wallpaperSectionFocus = false;
                panel.focusRow("section");
            }
        }
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
            text: "wallpaper_slideshow"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 19
            color: Colors.primary
        }

        TextInput {
            id: search
            font.family: Config.font

            anchors {
                left: searchIcon.right
                leftMargin: 12
                right: sectionButtons.left
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            color: Colors.fgSurface
            font.pixelSize: 14
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            selectedTextColor: Colors.fgSurface
            clip: true

            Keys.onEscapePressed: LauncherState.close()
            Keys.onReturnPressed: walls.item?.apply()
            Keys.onEnterPressed: walls.item?.apply()
            // Die Pfeile blaettern hier im Karussell statt den Textcursor zu
            // bewegen – im Suchfeld steht ohnehin nur ein Filterwort.
            // Mit Strg waehlen sie den Stil des markierten Bilds.
            Keys.onLeftPressed: event => {
                if (event.modifiers & Qt.ControlModifier)
                    panel.cycleStyle(-1);
                else
                    walls.item?.moveBy(-1);
            }
            Keys.onRightPressed: event => {
                if (event.modifiers & Qt.ControlModifier)
                    panel.cycleStyle(1);
                else
                    walls.item?.moveBy(1);
            }
            // Mit offener Sektion wechseln Hoch/Runter die Reihe
            Keys.onUpPressed: panel.sectionOpen ? panel.focusRow("section") : walls.item?.moveBy(-1)
            Keys.onDownPressed: panel.sectionOpen ? panel.focusRow("section") : walls.item?.moveBy(1)
            Keys.onTabPressed: walls.item?.moveBy(1)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
                    panel.cycleSection();
                    event.accepted = true;
                }
            }

            Text {
                anchors.fill: parent
                visible: search.text === ""
                text: I18n.tr("Wallpaper suchen…   %1 Bilder").arg(Wallpapers.list.length)
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                font: search.font
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Ein Knopf je Plugin-Sektion (auf-/zuklappen); die offene bleibt
        // getoent. Ohne Plugins ist die Reihe leer und nimmt keinen Platz.
        Row {
            id: sectionButtons

            anchors {
                right: shuffleButton.left
                rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            spacing: 4

            Repeater {
                model: panel.sections

                delegate: Rectangle {
                    id: sectionButton

                    required property var modelData

                    readonly property bool open: panel.openSection === sectionButton.modelData.pluginId

                    width: 32
                    height: 32
                    radius: height / 2
                    color: sectionButton.open ? Colors.alpha(Colors.primary, sectionArea.containsMouse ? 0.28 : 0.18)
                        : sectionArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08) : "transparent"

                    Behavior on color {
                        ColorAnimation { duration: 90 }
                    }

                    MouseArea {
                        id: sectionArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.toggleSection(sectionButton.modelData.pluginId)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: sectionButton.modelData.icon
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 17
                        color: sectionButton.open || sectionArea.containsMouse ? Colors.primary : Colors.fgSurfaceVariant
                    }
                }
            }
        }

        // Zufallsbild – das Gegenstueck zum Favoriten-Stern im Launcher
        Rectangle {
            id: shuffleButton

            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            width: 32
            height: 32
            radius: height / 2
            color: shuffleArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08) : "transparent"

            Behavior on color {
                ColorAnimation { duration: 90 }
            }

            MouseArea {
                id: shuffleArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Wallpapers.random();
                    LauncherState.close();
                }
            }

            Text {
                anchors.centerIn: parent
                text: "shuffle"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 17
                color: shuffleArea.containsMouse ? Colors.primary : Colors.fgSurfaceVariant
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

    // ---- Karussell ----
    Item {
        id: listWrapper

        anchors {
            top: separator.bottom
            left: parent.left
            right: parent.right
        }
        implicitHeight: panel.listHeight

        // Als Loader, damit das Karussell nur existiert, solange die Ansicht
        // offen ist: beim Zerstoeren nimmt es seine Hintergrund-Vorschau
        // zurueck und gibt die Vorschaubilder frei.
        Loader {
            id: walls

            anchors.fill: parent
            anchors.margins: 6
            active: panel.active

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: edgeMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            sourceComponent: WallpaperList {
                imageWidth: panel.imageWidth
                query: search.text
                focused: !panel.sectionFocused
                onApplied: LauncherState.close()
                onWheeled: panel.focusRow("local")
            }
        }

        // Vignette nach aussen: die Reihe blendet zu den Kartenraendern hin aus
        // (Maske auf dem Inhalt, siehe EdgeMask – eine Flaeche in der
        // Theme-Farbe darueber stand auf der schwarzen Notch als grauer Balken)
        EdgeMask {
            id: edgeMask

            anchors.fill: walls
            fade: 200
        }
    }

    Rectangle {
        id: separator2

        anchors {
            top: listWrapper.bottom
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.alpha(Colors.outline, 0.35)
    }

    // ---- Stil ----
    // Wie aus dem markierten Bild die Palette wird. Ein Klick legt den Stil
    // fuer dieses Bild fest (beim aktuellen faerbt es gleich um, sonst zeigt
    // die Vorschau ihn); "auto" rechnet ihn aus der Farbigkeit aus, der
    // ausgerechnete Stil ist dann duenn umrandet. Strg+Pfeile im Suchfeld
    // schalten durch. Wirkt nur beim dynamischen Schema – sonst bleibt die
    // Reihe sichtbar, aber zurueckgenommen (wie in der Theme-Auswahl).
    Item {
        id: styleRow

        anchors {
            top: separator2.bottom
            left: parent.left
            right: parent.right
        }
        height: 46

        opacity: Themes.currentName === "dynamic" ? 1 : 0.45

        Behavior on opacity {
            NumberAnimation { duration: 160 }
        }

        Text {
            id: styleIcon

            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: "palette"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 19
            color: Colors.primary
        }

        // Die Chips behalten ihre natuerliche Breite, der Abstand dazwischen
        // verteilt den Rest (wie in ThemePanel.qml)
        Row {
            id: chips

            anchors {
                left: styleIcon.right
                leftMargin: 14
                right: parent.right
                rightMargin: 14
                verticalCenter: parent.verticalCenter
            }

            property var widths: ({})
            readonly property real naturalWidth: {
                let sum = 0;
                for (const key in chips.widths)
                    sum += chips.widths[key];
                return sum;
            }

            function report(index: int, width: real): void {
                const next = Object.assign({}, chips.widths);
                next[index] = width;
                chips.widths = next;
            }

            spacing: Math.max(4, (chips.width - chips.naturalWidth) / (panel.styles.length - 1))

            Repeater {
                model: panel.styles

                delegate: Rectangle {
                    id: chip

                    required property int index
                    required property var modelData

                    readonly property bool selected: panel.pinnedStyle === chip.modelData.name
                    // Bei "auto": der Stil, den das Bild tatsaechlich bekommt
                    readonly property bool resolved: panel.pinnedStyle === "auto"
                        && panel.resolvedStyle === chip.modelData.name

                    implicitWidth: chipContent.implicitWidth + 20
                    implicitHeight: 28

                    onImplicitWidthChanged: chips.report(chip.index, chip.implicitWidth)
                    Component.onCompleted: chips.report(chip.index, chip.implicitWidth)

                    radius: height / 2
                    color: chip.selected ? Colors.primary
                        : chipArea.containsMouse ? Colors.alpha(Colors.fgSurface, 0.08)
                        : Colors.alpha(Colors.fgSurface, 0.04)
                    border.width: chip.resolved ? 1 : 0
                    border.color: Colors.alpha(Colors.primary, 0.6)

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Row {
                        id: chipContent

                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.icon
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 14
                            color: chip.selected ? Colors.fgPrimary
                                : chip.resolved ? Colors.primary
                                : Colors.fgSurfaceVariant
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.name
                            font.family: Config.font
                            font.pixelSize: 11
                            color: chip.selected ? Colors.fgPrimary
                                : chip.resolved ? Colors.primary
                                : Colors.fgSurface
                        }
                    }

                    MouseArea {
                        id: chipArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.pickStyle(chip.modelData.name)
                    }
                }
            }
        }
    }

    // ---- Plugin-Sektion ----
    // Der aufklappbare Bereich unter der Stil-Reihe. Die Hoehe des Panels
    // springt sofort, die Notch zieht per Morph nach und schneidet so lange
    // ab – deshalb bleibt die Sektion beim Zuklappen stehen, bis sie
    // ausgeblendet ist, sonst schrumpft die Karte ueber leerem Grund. Erst
    // danach wird sie zerstoert (zugeklappt gibt es also keine Sektion, keine
    // Timer, nichts).
    Rectangle {
        id: separator3

        anchors {
            top: styleRow.bottom
            left: parent.left
            right: parent.right
        }
        height: 1
        color: Colors.alpha(Colors.outline, 0.35)
        opacity: sectionWrapper.opacity
        visible: sectionWrapper.visible
    }

    Item {
        id: sectionWrapper

        anchors {
            top: separator3.bottom
            left: parent.left
            right: parent.right
        }
        implicitHeight: sectionLoader.item?.implicitHeight ?? 0
        height: implicitHeight

        opacity: panel.sectionOpen ? 1 : 0
        visible: opacity > 0

        Fade on opacity {}

        // Die zuletzt offene Sektion, bis sie ausgeblendet ist – ausser ihr
        // Plugin ist weg (ausgeschaltet): dann sofort, ihr Dienst
        // (plugin.main) verschwindet gleich mit. Beim Erzeugen kann schon
        // eine offen sein (LauncherState merkt sie sich, showWallpaperSection)
        // – dann kommt kein Wechsel-Signal, also hier setzen
        property var shown: null

        Component.onCompleted: if (panel.section) sectionWrapper.shown = panel.section

        Connections {
            target: panel

            function onSectionChanged(): void {
                if (panel.section)
                    sectionWrapper.shown = panel.section;
            }
            function onSectionsChanged(): void {
                if (sectionWrapper.shown && !panel.sections.some(s => s.pluginId === sectionWrapper.shown.pluginId))
                    sectionWrapper.shown = null;
            }
        }
        onOpacityChanged: if (sectionWrapper.opacity === 0 && !panel.sectionOpen) sectionWrapper.shown = null

        Loader {
            id: sectionLoader

            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }

            // Nur der Pfad als Abhaengigkeit: Plugins.panels wird bei jeder
            // Plugin-Aenderung neu gebaut, die Sektion soll aber nur neu
            // laden, wenn ihre Datei wechselt (wie die Kacheln in SettingsTiles)
            readonly property string url: sectionWrapper.shown?.url ?? ""

            function rebuild(): void {
                if (sectionLoader.url === "")
                    sectionLoader.source = "";
                else
                    sectionLoader.setSource(sectionLoader.url, { plugin: sectionWrapper.shown.plugin, host: panel.host });
            }

            onUrlChanged: sectionLoader.rebuild()
            onStatusChanged: {
                if (sectionLoader.status === Loader.Error)
                    console.warn(`Wallpaper-Sektion ${sectionWrapper.shown?.pluginId}: ${sectionLoader.url} laedt nicht`);
            }
        }
    }
}
