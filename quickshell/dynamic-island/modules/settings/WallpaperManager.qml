pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.modules.services.config
import qs.modules.services.plugins
import qs.modules.services.theme
import qs.modules.services.wallpaper
import qs.modules.widgets

import qs

// Wallpaper-Bibliothek – die Seite hinter "Wallpaper > Bibliothek" im
// Einstellungs-Fenster (SettingsCard.qml zeigt sie statt der Zeilenliste).
//
// Aufgebaut wie eine Foto-App: die Startansicht sind die Ordner als Karten
// (Titelbild = aktuelles Wallpaper, wenn es im Ordner liegt, sonst das
// erste), ein Ordner geoeffnet zeigt seine Bilder dicht als Raster ohne
// Dateinamen. Die Suche aus dem Kopf des Fensters geht ueber alle Ordner
// und zeigt die Treffer flach.
//
// Alles am Bild passiert ueber eine Leiste, die erst bei Auswahl unten
// erscheint (Setzen, Verschieben, Stil, Terminal-Look, Papierkorb), oder
// ueber das Rechtsklick-Menue – beides oeffnet dasselbe Popover, das in der
// Karte gezeichnet wird (Popups ausserhalb des Fensters gibt es nicht).
// Klick waehlt, Doppelklick setzt.
//
// Das Raster zeigt nie Originale, nur die kleinen Vorschaubilder aus
// Wallpapers.thumbFor (Qt dekodiert alle Bilder in einem Thread, ein grosses
// PNG staut sonst die ganze Shell). Keine Vorschau beim Hovern – die wuerde
// den Hintergrund umschalten.
//
// Dateien bewegt WallManager (wallmgr.py); `finished` zieht danach Auswahl
// und Ordner nach. Papierkorb ist zweistufig wie "Alles zuruecksetzen".
Item {
    id: page

    // Suchtext aus dem Kopf des Fensters – filtert ueber alle Ordner
    property string filter: ""

    // Startansicht (Ordner-Karten) oder ein geoeffneter Ordner
    // ("" = Bilder ohne Ordner, direkt im Wallpaper-Ordner)
    property bool overview: true
    property string folder: ""
    // Gewaehltes Bild (Pfad, "" = keins)
    property string selected: ""

    // Popover: "" = zu, sonst die Seite: "menu" (Rechtsklick), "verschieben",
    // "stil", "look" (Bild) oder "ordnerlook" (Ordner im Kopf)
    property string menu: ""
    // Seite, mit der das Popover geoeffnet wurde (Zurueck nur in Unterseiten)
    property string menuRoot: ""
    property real menuX: 0
    property real menuY: 0
    // Nach oben aufklappen (ueber der Leiste) statt nach unten
    property bool menuUp: false

    property bool newFolderOpen: false
    property bool renameOpen: false
    property bool trashArmed: false
    // Weggeklickte Fehlermeldung
    property string dismissedError: ""

    readonly property bool busy: WallManager.busy
    readonly property string error: WallManager.lastError !== page.dismissedError ? WallManager.lastError : ""

    readonly property bool terminalOn: Plugins.isEnabled("terminal")
    readonly property string terminalSection: Plugins.sectionPrefix + "terminal"
    readonly property bool lookTheme: Plugins.get(page.terminalSection, "theme") === true
    readonly property bool lookFolders: Plugins.get(page.terminalSection, "folderLooks") === true
    readonly property bool looksActive: page.terminalOn && page.lookTheme && page.lookFolders
    // Looks-Editor des Terminal-Plugins (Plugin-Seite, nur solange es laeuft)
    readonly property string editorSection: Plugins.pageSection("terminal/looks")
    readonly property bool editorAvailable: page.terminalOn && Plugins.pageFor(page.editorSection) !== null
    // Look, der zum offenen Ordner gehoert (Name oder feste Zuordnung), "" = keiner
    readonly property string folderEditLook: {
        const named = WallManager.conventionLook(page.folder);
        if (named !== "")
            return named;
        const own = page.folderLook;
        return own.source === "ordner" && own.id !== "scheme" && own.id !== "" ? own.id : "";
    }
    // Stil wirkt nur beim dynamischen Schema
    readonly property bool dynamicScheme: Themes.currentName === "dynamic"

    readonly property var styles: [{ name: "auto", icon: "auto_awesome" }].concat(Themes.variants)

    readonly property bool searching: page.filter.trim() !== ""
    // Raster statt Ordner-Karten: Suche oder geoeffneter Ordner
    readonly property bool showGrid: page.searching || !page.overview

    // Bilder direkt im Wallpaper-Ordner (ohne Unterordner)
    readonly property var loose: Wallpapers.list.filter(w => !w.name.includes("/"))

    // Was das Raster zeigt: Treffer der Suche oder der geoeffnete Ordner
    readonly property var images: {
        const needle = page.filter.trim().toLowerCase();
        if (needle !== "")
            return Wallpapers.list.filter(w => w.name.toLowerCase().includes(needle));
        return page.overview ? [] : page.imagesOf(page.folder);
    }
    readonly property int total: Wallpapers.list.length

    // Karten der Startansicht: Ordner, dahinter "Ohne Ordner" (wenn es
    // solche Bilder gibt)
    readonly property var cards: {
        const out = WallManager.folders.map(f => page.cardFor(f));
        if (page.loose.length > 0)
            out.push(page.cardFor(""));
        return out;
    }

    readonly property var selectedInfo: page.selected !== ""
        ? Wallpapers.list.find(w => w.path === page.selected) ?? null : null
    readonly property bool hasSelection: page.selectedInfo !== null
    readonly property string selectedFolder: page.hasSelection ? WallManager.folderOf(page.selected) : ""
    readonly property bool selectedIsCurrent: page.hasSelection && page.selected === Wallpapers.actualCurrent
    readonly property string selectedStyle: page.hasSelection ? (Wallpapers.variantFor(page.selected) || "auto") : "auto"
    readonly property var selectedLook: page.hasSelection ? WallManager.lookFor(page.selected) : ({ id: "scheme", source: "schema" })
    readonly property var folderLook: WallManager.folderLookFor(page.folder)

    // Raster-Masse aus der Breite: Kacheln um 200 px (Bilder) bzw. 220 px
    // (Ordner), nie weniger als zwei Spalten
    readonly property int gridGap: 6
    readonly property int gridColumns: Math.max(2, Math.floor((page.width + page.gridGap) / (200 + page.gridGap)))
    readonly property int cardGap: 14
    readonly property int cardColumns: Math.max(2, Math.floor((page.width + page.cardGap) / (220 + page.cardGap)))

    function imagesOf(f: string): var {
        return f === "" ? page.loose : WallManager.imagesIn(f);
    }

    function cardFor(f: string): var {
        const imgs = page.imagesOf(f);
        const current = imgs.find(w => w.path === Wallpapers.actualCurrent);
        return {
            folder: f,
            title: page.folderName(f),
            count: imgs.length,
            cover: (current ?? imgs[0])?.name ?? "",
            hasCurrent: current !== undefined
        };
    }

    function fileName(name: string): string {
        return name.slice(name.lastIndexOf("/") + 1);
    }

    function folderName(f: string): string {
        return f === "" ? I18n.tr("Ohne Ordner") : f.slice(f.lastIndexOf("/") + 1);
    }

    // one/many sind ganze Schluessel ("1 Bild", "%1 Bilder") – Englisch
    // braucht sein eigenes Plural
    function plural(n: int, one: string, many: string): string {
        return n === 1 ? I18n.tr(one) : I18n.tr(many).arg(n);
    }

    function lookTitle(id: string): string {
        return I18n.tr(WallManager.lookInfo(id)?.title ?? id);
    }

    function sourceLabel(source: string): string {
        return I18n.tr(({ bild: "für dieses Bild", ordner: "vom Ordner", name: "Ordner heißt wie der Look", schema: "Farbschema" })[source] ?? source);
    }

    // ---- Navigation ----
    function pickFolder(f: string): void {
        page.closeAll();
        page.folder = f;
        page.overview = false;
        page.selected = "";
        grid.contentY = 0;
    }

    function goBack(): void {
        page.closeAll();
        page.overview = true;
        page.selected = "";
        cardGrid.contentY = 0;
    }

    function pickImage(path: string): void {
        page.closeAll();
        page.selected = path;
    }

    function openMenu(kind: string, x: real, y: real, up: bool): void {
        page.trashArmed = false;
        page.renameOpen = false;
        page.newFolderOpen = false;
        page.menuRoot = kind;
        page.menu = kind;
        page.menuX = x;
        page.menuY = y;
        page.menuUp = up;
    }

    // Aus der Leiste: ueber dem Knopf aufklappen
    function openAbove(kind: string, button: Item): void {
        const pos = button.mapToItem(page, 0, 0);
        page.openMenu(kind, pos.x, pos.y - 6, true);
    }

    // Aus dem Kopf: unter dem Knopf, rechtsbuendig
    function openBelow(kind: string, button: Item): void {
        const pos = button.mapToItem(page, button.width, button.height);
        page.openMenu(kind, pos.x - 300, pos.y + 6, false);
    }

    function closeMenu(): void {
        page.menu = "";
    }

    function closeAll(): void {
        page.menu = "";
        page.newFolderOpen = false;
        page.renameOpen = false;
        page.trashArmed = false;
    }

    function armTrash(): void {
        page.closeAll();
        page.trashArmed = true;
        disarmTrash.restart();
    }

    function trashSelected(): void {
        page.trashArmed = false;
        WallManager.trash(page.selected);
    }

    Component.onCompleted: WallManager.ensureLoaded()

    // Nach Verschieben der Auswahl hinterher (nur in der Suche – im Ordner
    // ist das Bild weg), nach dem Papierkorb Auswahl leeren
    Connections {
        target: WallManager

        function onFinished(op: string, result: var): void {
            if (!result.ok)
                return;
            if (op === "move")
                page.selected = page.searching && result.path ? result.path : "";
            else if (op === "trash")
                page.selected = "";
            else if (op === "rename-folder" && result.folder !== undefined)
                page.folder = result.folder;
        }
    }

    Timer {
        id: disarmTrash

        interval: 3000
        onTriggered: page.trashArmed = false
    }

    // ---- Bausteine ----

    // Leiser Knopf: Text, optional Symbol davor und Pfeil dahinter; `filled`
    // fuer die eine Hauptaktion (Setzen)
    component Quiet: Rectangle {
        id: button

        property string icon: ""
        property string label: ""
        property bool filled: false
        property bool chevron: false
        property color tint: Colors.fgSurface
        signal clicked()

        implicitWidth: buttonRow.implicitWidth + (button.label === "" ? 14 : 20)
        implicitHeight: 28
        radius: 9
        opacity: enabled ? 1 : 0.4
        color: button.filled ? (buttonHover.hovered ? Colors.alpha(Colors.primary, 0.85) : Colors.primary)
             : buttonHover.hovered ? Colors.alpha(Colors.fgSurface, 0.1)
             : "transparent"

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
        Fade on opacity {}

        Row {
            id: buttonRow

            anchors.centerIn: parent
            spacing: 5

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.icon !== ""
                text: button.icon
                color: button.filled ? Colors.fgPrimary : button.tint
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.label !== ""
                font.family: Config.font
                text: button.label
                color: button.filled ? Colors.fgPrimary : button.tint
                font.pixelSize: 11
                font.weight: button.filled ? Font.DemiBold : Font.Medium
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.chevron
                text: "expand_more"
                color: Colors.alpha(button.tint, 0.7)
                font.family: "Material Symbols Outlined"
                font.pixelSize: 14
            }
        }

        HoverHandler {
            id: buttonHover

            cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: button.enabled
            onTapped: button.clicked()
        }
    }

    // Einzeiliges Textfeld (Ordnername) – Enter bestaetigt, Esc bricht ab
    component InlineField: Rectangle {
        id: field

        property string placeholder: ""
        property string text: ""
        signal accepted(string value)
        signal cancelled()

        implicitHeight: 30
        radius: 9
        color: Colors.alpha(Colors.fgSurface, 0.07)
        border.width: 1
        border.color: input.activeFocus ? Colors.alpha(Colors.primary, 0.5) : "transparent"

        Behavior on border.color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        Component.onCompleted: {
            input.text = field.text;
            input.selectAll();
            input.forceActiveFocus();
        }

        TextInput {
            id: input

            anchors {
                left: parent.left
                right: okButton.left
                leftMargin: 10
                rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            font.family: Config.font
            font.pixelSize: 12
            color: Colors.fgBackground
            selectionColor: Colors.alpha(Colors.primary, 0.35)
            clip: true
            onAccepted: if (text.trim() !== "") field.accepted(text.trim())
            Keys.onEscapePressed: event => {
                field.cancelled();
                event.accepted = true;
            }

            Text {
                anchors.fill: parent
                visible: input.text === ""
                text: field.placeholder
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                font: input.font
                verticalAlignment: Text.AlignVCenter
            }
        }

        Quiet {
            id: okButton

            anchors {
                right: cancelButton.left
                verticalCenter: parent.verticalCenter
            }
            icon: "check"
            tint: Colors.primary
            enabled: input.text.trim() !== ""
            onClicked: field.accepted(input.text.trim())
        }

        Quiet {
            id: cancelButton

            anchors {
                right: parent.right
                rightMargin: 1
                verticalCenter: parent.verticalCenter
            }
            icon: "close"
            tint: Colors.fgSurfaceVariant
            onClicked: field.cancelled()
        }
    }

    // Vorschaubild mit runden Ecken (nur Thumbs – nie Originale)
    component Thumb: Rectangle {
        id: thumbFrame

        required property string name
        property real cornerRadius: 6

        radius: thumbFrame.cornerRadius
        color: Colors.alpha(Colors.fgSurface, 0.05)

        Image {
            id: thumbImage

            anchors.fill: parent
            source: Wallpapers.thumbFor(thumbFrame.name)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
        }

        Item {
            id: thumbMask

            anchors.fill: thumbImage
            layer.enabled: true
            visible: false

            Rectangle {
                anchors.fill: parent
                radius: thumbFrame.cornerRadius
                color: "black"
            }
        }

        // Runde Ecken gehen nur ueber eine Maske – `clip` schneidet rechteckig
        MultiEffect {
            anchors.fill: thumbImage
            visible: thumbImage.status === Image.Ready
            source: thumbImage
            maskEnabled: true
            maskSource: thumbMask
        }

        // Platzhalter, solange das Vorschaubild fehlt oder laedt
        Text {
            anchors.centerIn: parent
            visible: thumbImage.status !== Image.Ready
            text: thumbFrame.name === "" ? "folder" : "image"
            color: Colors.alpha(Colors.fgSurfaceVariant, 0.4)
            font.family: "Material Symbols Outlined"
            font.pixelSize: 22
        }
    }

    // ================= Kopf =================
    // Nur im Raster: Zurueck, Pfad, rechts die leisen Ordner-Aktionen
    Item {
        id: header

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: page.showGrid ? 34 : 0
        visible: page.showGrid
        clip: true

        Quiet {
            id: backButton

            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            visible: !page.searching
            icon: "arrow_back"
            tint: Colors.fgSurfaceVariant
            onClicked: page.goBack()
        }

        // Pfad: "Bibliothek › Miku" – Bibliothek klickbar
        Row {
            id: crumbs

            anchors {
                left: page.searching ? header.left : backButton.right
                right: headerActions.left
                leftMargin: page.searching ? 10 : 4
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            spacing: 6
            visible: !page.renameOpen

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.font
                text: I18n.tr("Bibliothek")
                color: crumbHover.hovered ? Colors.fgSurface : Colors.fgSurfaceVariant
                font.pixelSize: 13

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }

                HoverHandler {
                    id: crumbHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: page.goBack()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.font
                text: "›"
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                font.pixelSize: 13
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, crumbs.width - 140)
                font.family: Config.font
                text: page.searching ? I18n.tr("Suche") : page.folderName(page.folder)
                color: Colors.fgBackground
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.font
                text: page.searching ? page.plural(page.images.length, "1 Treffer", "%1 Treffer") : page.plural(page.images.length, "1 Bild", "%1 Bilder")
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                font.pixelSize: 11
                leftPadding: 4
            }
        }

        // Umbenennen: das Feld ersetzt den Pfad
        Loader {
            anchors {
                left: backButton.right
                right: headerActions.left
                leftMargin: 4
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            active: page.renameOpen
            visible: active

            sourceComponent: InlineField {
                placeholder: I18n.tr("Neuer Name…")
                text: page.folder
                onAccepted: value => {
                    page.renameOpen = false;
                    if (value !== page.folder)
                        WallManager.renameFolder(page.folder, value);
                }
                onCancelled: page.renameOpen = false
            }
        }

        Row {
            id: headerActions

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            spacing: 2
            visible: !page.searching && !page.renameOpen

            // Laeuft gerade etwas?
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: page.busy
                rightPadding: 6
                text: "progress_activity"
                color: Colors.primary
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15

                // Nur solange etwas laeuft – nicht endlos
                RotationAnimation on rotation {
                    running: page.busy
                    from: 0
                    to: 360
                    loops: Animation.Infinite
                    duration: Appearance.morphDuration * 3
                }
            }

            Quiet {
                id: folderLookButton

                visible: page.terminalOn && page.folder !== ""
                label: I18n.tr("Terminal-Look · %1").arg(page.lookTitle(page.folderLook.id))
                tint: page.menu === "ordnerlook" ? Colors.fgBackground : Colors.fgSurfaceVariant
                chevron: true
                onClicked: page.menu === "ordnerlook" ? page.closeMenu() : page.openBelow("ordnerlook", folderLookButton)
            }

            Quiet {
                visible: page.folder !== ""
                icon: "edit"
                tint: Colors.fgSurfaceVariant
                enabled: !page.busy
                onClicked: {
                    page.closeAll();
                    page.renameOpen = true;
                }
            }

            Quiet {
                icon: "folder_open"
                tint: Colors.fgSurfaceVariant
                onClicked: {
                    Quickshell.execDetached(["xdg-open", Wallpapers.wallsDir + (page.folder === "" ? "" : "/" + page.folder)]);
                    // Das Fenster laege sonst ueber dem Dateimanager
                    SettingsState.close();
                }
            }
        }
    }

    // ---- Fehler von wallmgr.py ----
    Item {
        id: errorRow

        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            leftMargin: 8
            rightMargin: 4
        }
        height: page.error !== "" ? errorText.implicitHeight + 14 : 0
        visible: height > 0
        clip: true

        Behavior on height {
            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
        }

        Text {
            id: errorText

            anchors {
                left: parent.left
                right: dismiss.left
                rightMargin: 6
                verticalCenter: parent.verticalCenter
            }
            font.family: Config.font
            text: page.error
            color: Colors.error
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Quiet {
            id: dismiss

            anchors {
                right: parent.right
                verticalCenter: parent.verticalCenter
            }
            icon: "close"
            tint: Colors.error
            onClicked: page.dismissedError = WallManager.lastError
        }
    }

    // ================= Ordner-Karten =================
    GridView {
        id: cardGrid

        readonly property real tileWidth: cardGrid.cellWidth - page.cardGap
        readonly property real coverHeight: Math.round(cardGrid.tileWidth * 10 / 16)

        // Haengt rechts um einen Abstand ueber: so passen n Spalten mit
        // n-1 Luecken genau in die Seite
        anchors {
            left: parent.left
            right: parent.right
            top: errorRow.bottom
            bottom: parent.bottom
            topMargin: 4
            rightMargin: -page.cardGap
        }
        visible: !page.showGrid
        clip: true
        cellWidth: Math.floor(width / page.cardColumns)
        cellHeight: cardGrid.coverHeight + 50
        boundsBehavior: Flickable.StopAtBounds
        // Mausrad statt Ziehen (wie die Zeilenliste)
        interactive: false
        cacheBuffer: cardGrid.cellHeight * 2

        // Hinter den Ordnern eine stille letzte Karte: Neuer Ordner
        model: ScriptModel {
            values: page.cards.concat([{ folder: null, title: "", count: 0, cover: "", hasCurrent: false }])
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: event => {
                const angle = event.angleDelta.y + event.angleDelta.x;
                const pixels = event.pixelDelta.y + event.pixelDelta.x;
                const delta = angle !== 0 ? angle / 120 : pixels / 40;
                const max = Math.max(0, cardGrid.contentHeight - cardGrid.height);
                cardGrid.contentY = Math.max(0, Math.min(max, cardGrid.contentY - delta * 60));
                event.accepted = true;
            }
        }

        delegate: Item {
            id: card

            required property var modelData

            readonly property bool isNew: card.modelData.folder === null

            width: cardGrid.cellWidth
            height: cardGrid.cellHeight

            // ---- Ordner ----
            Item {
                anchors.fill: parent
                anchors.rightMargin: page.cardGap
                visible: !card.isNew

                Thumb {
                    id: cover

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    height: cardGrid.coverHeight
                    name: card.modelData.cover
                    cornerRadius: 10

                    // Leicht aufhellen beim Hovern
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Colors.fgSurface
                        opacity: cardHover.hovered ? 0.07 : 0

                        Fade on opacity {}
                    }

                    // Das aktuelle Wallpaper liegt hier
                    Rectangle {
                        anchors {
                            right: parent.right
                            bottom: parent.bottom
                            margins: 8
                        }
                        visible: card.modelData.hasCurrent
                        width: 9
                        height: 9
                        radius: 4.5
                        color: Colors.primary
                        border.width: 2
                        border.color: Colors.alpha(Colors.background, 0.9)
                    }
                }

                Text {
                    id: cardTitle

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: cover.bottom
                        topMargin: 8
                        leftMargin: 2
                    }
                    font.family: Config.font
                    text: card.modelData.title
                    color: cardHover.hovered ? Colors.fgBackground : Colors.fgSurface
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideMiddle

                    Behavior on color {
                        ColorAnimation { duration: Appearance.fadeDuration }
                    }
                }

                Text {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: cardTitle.bottom
                        topMargin: 1
                        leftMargin: 2
                    }
                    font.family: Config.font
                    text: card.modelData.count === 0 ? I18n.tr("Leer") : page.plural(card.modelData.count, "1 Bild", "%1 Bilder")
                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                    font.pixelSize: 10
                }

                HoverHandler {
                    id: cardHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: page.pickFolder(card.modelData.folder)
                }
            }

            // ---- Neuer Ordner ----
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    rightMargin: page.cardGap
                }
                height: cardGrid.coverHeight
                visible: card.isNew
                radius: 10
                color: newHover.hovered || page.newFolderOpen ? Colors.alpha(Colors.fgSurface, 0.05) : "transparent"
                border.width: 1
                border.color: Colors.alpha(Colors.outline, newHover.hovered ? 0.4 : 0.22)

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }
                Behavior on border.color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }

                Column {
                    anchors.centerIn: parent
                    visible: !page.newFolderOpen
                    spacing: 4

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "add"
                        color: Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 22
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.family: Config.font
                        text: I18n.tr("Neuer Ordner")
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 11
                    }
                }

                Loader {
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: 10
                    }
                    active: page.newFolderOpen
                    visible: active

                    sourceComponent: InlineField {
                        placeholder: I18n.tr("Name…")
                        onAccepted: value => {
                            page.newFolderOpen = false;
                            WallManager.makeFolder(value);
                        }
                        onCancelled: page.newFolderOpen = false
                    }
                }

                HoverHandler {
                    id: newHover

                    cursorShape: page.newFolderOpen ? Qt.ArrowCursor : Qt.PointingHandCursor
                }

                TapHandler {
                    enabled: !page.newFolderOpen && !page.busy
                    onTapped: {
                        page.closeAll();
                        page.newFolderOpen = true;
                    }
                }
            }
        }

        // Weiche Kante unten, solange noch Reihen folgen
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 24
            visible: cardGrid.contentHeight - cardGrid.contentY - cardGrid.height > 2
            gradient: Gradient {
                GradientStop { position: 0; color: Colors.alpha(Colors.background, 0) }
                GradientStop { position: 1; color: Colors.background }
            }
        }

        // Leer: noch nichts da
        Column {
            anchors.centerIn: parent
            width: parent.width - 40
            visible: page.cards.length === 0
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Wallpapers.loading && page.total === 0 ? "hourglass_empty" : "photo_library"
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.5)
                font.family: "Material Symbols Outlined"
                font.pixelSize: 28
            }

            Text {
                width: parent.width
                font.family: Config.font
                text: Wallpapers.loading && page.total === 0 ? I18n.tr("Bilder werden gesucht…")
                    : I18n.tr("Keine Wallpaper in %1").arg(Wallpapers.wallsDir.replace(Quickshell.env("HOME"), "~"))
                color: Colors.fgSurfaceVariant
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    // ================= Bilder-Raster =================
    GridView {
        id: grid

        readonly property real tileWidth: grid.cellWidth - page.gridGap
        readonly property real tileHeight: Math.round(grid.tileWidth * 9 / 16)

        anchors {
            left: parent.left
            right: parent.right
            top: errorRow.bottom
            bottom: parent.bottom
            topMargin: 8
            rightMargin: -page.gridGap
            bottomMargin: page.hasSelection ? sheet.height + 10 : 0
        }
        visible: page.showGrid
        clip: true
        cellWidth: Math.floor(width / page.gridColumns)
        cellHeight: grid.tileHeight + page.gridGap
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        cacheBuffer: grid.cellHeight * 2

        Behavior on anchors.bottomMargin {
            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
        }

        model: ScriptModel {
            values: page.images
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: event => {
                const angle = event.angleDelta.y + event.angleDelta.x;
                const pixels = event.pixelDelta.y + event.pixelDelta.x;
                const delta = angle !== 0 ? angle / 120 : pixels / 40;
                const max = Math.max(0, grid.contentHeight - grid.height);
                grid.contentY = Math.max(0, Math.min(max, grid.contentY - delta * 60));
                event.accepted = true;
            }
        }

        // Klick auf leere Flaeche: Bild abwaehlen. Der Handler sieht auch
        // Klicks auf Kacheln (beide greifen passiv) – die ueberlaesst er dem
        // Kachel-Handler.
        TapHandler {
            onTapped: point => {
                if (grid.indexAt(point.position.x + grid.contentX, point.position.y + grid.contentY) >= 0)
                    return;
                page.selected = "";
                page.closeAll();
            }
        }

        delegate: Item {
            id: tile

            required property var modelData

            readonly property bool chosen: tile.modelData.path === page.selected
            readonly property bool isCurrent: tile.modelData.path === Wallpapers.actualCurrent

            width: grid.cellWidth
            height: grid.cellHeight

            Thumb {
                id: frame

                anchors {
                    left: parent.left
                    top: parent.top
                }
                width: grid.tileWidth
                height: grid.tileHeight
                name: tile.modelData.name
                cornerRadius: 6

                // Name nur beim Hovern oder in der Auswahl, unten im Bild
                Item {
                    anchors.fill: parent
                    opacity: tileHover.hovered || tile.chosen ? 1 : 0
                    visible: opacity > 0

                    Fade on opacity {}

                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: Math.min(parent.height, 44)
                        bottomLeftRadius: frame.radius
                        bottomRightRadius: frame.radius
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
                        }
                    }

                    Text {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            margins: 7
                            rightMargin: tile.isCurrent ? 22 : 7
                        }
                        font.family: Config.font
                        text: page.searching ? tile.modelData.name : page.fileName(tile.modelData.name)
                        color: "white"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                    }
                }

                // Das gesetzte Bild: ein Punkt
                Rectangle {
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        margins: 7
                    }
                    visible: tile.isCurrent
                    width: 9
                    height: 9
                    radius: 4.5
                    color: Colors.primary
                    border.width: 2
                    border.color: Colors.alpha(Colors.background, 0.9)
                }
            }

            // Auswahl: Ring mit Luft um die Kachel
            Rectangle {
                anchors.fill: frame
                anchors.margins: -3
                visible: tile.chosen
                radius: frame.radius + 3
                color: "transparent"
                border.width: 2
                border.color: Colors.primary
            }

            HoverHandler {
                id: tileHover

                cursorShape: Qt.PointingHandCursor
            }

            // Klick waehlt (auch der erste des Doppelklicks), Doppelklick setzt
            TapHandler {
                onTapped: page.pickImage(tile.modelData.path)
                onDoubleTapped: Wallpapers.set(tile.modelData.path)
            }

            // Rechtsklick: Auswahl + Menue an der Stelle
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: point => {
                    const pos = tile.mapToItem(page, point.position.x, point.position.y);
                    page.pickImage(tile.modelData.path);
                    page.openMenu("menu", pos.x, pos.y, false);
                }
            }
        }

        // Weiche Kante unten, solange noch Reihen folgen
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 24
            visible: grid.contentHeight - grid.contentY - grid.height > 2
            gradient: Gradient {
                GradientStop { position: 0; color: Colors.alpha(Colors.background, 0) }
                GradientStop { position: 1; color: Colors.background }
            }
        }

        // Leer: nichts gefunden / Ordner leer
        Column {
            anchors.centerIn: parent
            width: parent.width - 40
            visible: grid.count === 0
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: page.searching ? "search_off" : "folder_open"
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.5)
                font.family: "Material Symbols Outlined"
                font.pixelSize: 28
            }

            Text {
                width: parent.width
                font.family: Config.font
                text: page.searching ? I18n.tr("Nichts gefunden") : I18n.tr("Dieser Ordner ist leer")
                color: Colors.fgSurfaceVariant
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                visible: !page.searching
                font.family: Config.font
                text: I18n.tr("Bilder aus anderen Ordnern per „Verschieben“ hierher holen")
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    // ================= Leiste zum gewaehlten Bild =================
    Rectangle {
        id: sheet

        // Platz fuer Name und Ordner neben den Knoepfen? Und fuer die Werte
        // hinter Stil/Look?
        readonly property bool roomy: sheet.width > 680
        readonly property bool compact: sheet.width < 560

        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 54
        radius: 14
        color: Colors.mix(Colors.background, Colors.fgSurface, 0.07)
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.25)
        visible: opacity > 0
        opacity: page.hasSelection ? 1 : 0
        transform: Translate {
            y: page.hasSelection ? 0 : 12

            Behavior on y {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }
        }

        Fade on opacity {}

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 7
                rightMargin: 7
            }
            spacing: 4

            Thumb {
                Layout.preferredWidth: sheet.compact ? 48 : 60
                Layout.preferredHeight: sheet.compact ? 30 : 36
                name: page.selectedInfo?.name ?? ""
                cornerRadius: 5
            }

            Column {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                visible: sheet.roomy
                spacing: 1

                Text {
                    width: parent.width
                    font.family: Config.font
                    text: page.fileName(page.selectedInfo?.name ?? "")
                    color: Colors.fgBackground
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideMiddle
                }

                Text {
                    width: parent.width
                    font.family: Config.font
                    text: page.folderName(page.selectedFolder) + (page.selectedIsCurrent ? I18n.tr(" · aktuelles Wallpaper") : "")
                    color: Colors.fgSurfaceVariant
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Item {
                Layout.fillWidth: !sheet.roomy
            }

            Quiet {
                filled: true
                enabled: !page.selectedIsCurrent
                label: page.selectedIsCurrent ? I18n.tr("Gesetzt") : I18n.tr("Setzen")
                onClicked: Wallpapers.set(page.selected)
            }

            Quiet {
                id: moveButton

                enabled: !page.busy
                label: I18n.tr("Verschieben")
                chevron: true
                tint: page.menu === "verschieben" ? Colors.fgBackground : Colors.fgSurface
                onClicked: page.menu === "verschieben" ? page.closeMenu() : page.openAbove("verschieben", moveButton)
            }

            Quiet {
                id: styleButton

                label: sheet.compact ? I18n.tr("Stil") : I18n.tr("Stil · %1").arg(page.selectedStyle)
                chevron: true
                tint: page.menu === "stil" ? Colors.fgBackground : Colors.fgSurface
                onClicked: page.menu === "stil" ? page.closeMenu() : page.openAbove("stil", styleButton)
            }

            Quiet {
                id: lookButton

                visible: page.terminalOn
                label: sheet.compact ? "Look" : "Look · " + page.lookTitle(page.selectedLook.id)
                chevron: true
                tint: page.menu === "look" ? Colors.fgBackground : Colors.fgSurface
                onClicked: page.menu === "look" ? page.closeMenu() : page.openAbove("look", lookButton)
            }

            // Zweistufig: erst das Symbol, dann 3 s lang "Wirklich?"
            Quiet {
                enabled: !page.busy
                icon: page.trashArmed ? "" : "delete"
                label: page.trashArmed ? (sheet.compact ? I18n.tr("Wirklich?") : I18n.tr("Wirklich löschen?")) : ""
                tint: page.trashArmed ? Colors.error : Colors.fgSurfaceVariant
                onClicked: page.trashArmed ? page.trashSelected() : page.armTrash()
            }

            Quiet {
                icon: "close"
                tint: Colors.fgSurfaceVariant
                onClicked: {
                    page.selected = "";
                    page.closeAll();
                }
            }
        }
    }

    // ================= Popover =================
    // Klick daneben schliesst
    MouseArea {
        anchors.fill: parent
        visible: page.menu !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: page.closeMenu()
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        id: popover

        readonly property bool isLook: page.menu === "look" || page.menu === "ordnerlook"
        readonly property bool sub: page.menu !== page.menuRoot
        readonly property real maxHeight: page.height - 12
        readonly property real pad: 6

        // Hinweis ueber den Eintraegen (Plugin aus, Schema statisch …)
        readonly property string note: {
            if (page.menu === "stil")
                return page.dynamicScheme ? "" : I18n.tr("Wirkt nur beim dynamischen Schema – gerade ist „%1“ gewählt.").arg(Themes.currentName);
            if (popover.isLook) {
                if (!page.terminalOn)
                    return I18n.tr("Das Plugin „Terminal-Looks“ ist aus.");
                if (!page.lookTheme)
                    return I18n.tr("„An Theme anpassen“ ist in Terminal-Looks aus – das Terminal zeigt immer Vocaloid.");
                if (!page.lookFolders)
                    return I18n.tr("Ordner-Looks sind in Terminal-Looks ausgeschaltet – Zuordnungen gelten nicht.");
                if (page.menu === "ordnerlook")
                    return I18n.tr("Für alle Bilder des Ordners ohne eigenen Look.");
            }
            return "";
        }

        readonly property string title: I18n.tr(({
            menu: "", verschieben: "Verschieben nach", stil: "Stil", look: "Terminal-Look", ordnerlook: "Terminal-Look des Ordners"
        })[page.menu] ?? "")

        // Eintraege der aktuellen Seite:
        // { title, desc, icon, card, current, enabled, sub, danger, action }
        readonly property var rows: {
            const m = page.menu;
            if (m === "menu") {
                const out = [
                    { title: page.selectedIsCurrent ? I18n.tr("Ist gesetzt") : I18n.tr("Setzen"), icon: "wallpaper", enabled: !page.selectedIsCurrent,
                      action: () => { Wallpapers.set(page.selected); page.closeMenu(); } },
                    { title: I18n.tr("Verschieben"), icon: "drive_file_move", sub: true, enabled: !page.busy, action: () => page.menu = "verschieben" },
                    { title: I18n.tr("Stil"), desc: page.selectedStyle, icon: "palette", sub: true, action: () => page.menu = "stil" }
                ];
                if (page.terminalOn)
                    out.push({ title: I18n.tr("Terminal-Look"), desc: page.lookTitle(page.selectedLook.id), icon: "terminal", sub: true, action: () => page.menu = "look" });
                out.push({ title: I18n.tr("Papierkorb"), icon: "delete", danger: true, enabled: !page.busy,
                           action: () => { page.closeMenu(); page.armTrash(); } });
                return out;
            }
            if (m === "verschieben") {
                const targets = [""].concat(WallManager.folders).filter(f => f !== page.selectedFolder);
                return targets.map(f => ({
                    title: page.folderName(f), icon: f === "" ? "home" : "folder",
                    action: () => { page.closeMenu(); WallManager.move(page.selected, f); }
                }));
            }
            if (m === "stil")
                return page.styles.map(s => ({
                    title: s.name === "auto" ? I18n.tr("Automatisch") : s.name, icon: s.icon,
                    current: page.selectedStyle === s.name,
                    action: () => { Wallpapers.setVariant(page.selected, s.name); page.closeMenu(); }
                }));
            if (popover.isLook) {
                const forFolder = m === "ordnerlook";
                const key = forFolder ? WallManager.folderKey(page.folder) : WallManager.keyFor(page.selected);
                const fallback = forFolder
                    ? (WallManager.conventionLook(page.folder) !== ""
                        ? { id: WallManager.conventionLook(page.folder), source: "name" }
                        : { id: "scheme", source: "schema" })
                    : WallManager.folderLookFor(page.selectedFolder);
                const own = WallManager.assignments[key] ?? "";
                const hasOwn = own !== "" && WallManager.exists(own);
                const out = [{
                    title: I18n.tr("Automatisch"), desc: page.lookTitle(fallback.id) + " · " + page.sourceLabel(fallback.source),
                    icon: "auto_awesome", card: WallManager.lookInfo(fallback.id)?.card ?? "",
                    current: !hasOwn, enabled: page.looksActive,
                    action: () => { WallManager.setLook(key, ""); page.closeMenu(); }
                }];
                for (const l of WallManager.looks)
                    out.push({
                        title: I18n.tr(l.title), desc: l.cards > 0 ? page.plural(l.cards, "1 Karte", "%1 Karten") : I18n.tr(l.desc),
                        icon: "palette", card: l.card, current: hasOwn && own === l.id, enabled: page.looksActive,
                        action: () => { WallManager.setLook(key, l.id); page.closeMenu(); }
                    });
                // Ordner: zum Looks-Editor des Terminal-Plugins (Seite
                // "terminal/looks") – den Look des Ordners bearbeiten oder
                // einen fuer ihn anlegen
                if (forFolder && page.editorAvailable) {
                    const edit = page.folderEditLook;
                    out.push({
                        title: edit !== "" ? I18n.tr("Look bearbeiten") : I18n.tr("Eigenen Look anlegen"),
                        icon: edit !== "" ? "edit" : "add",
                        action: () => {
                            page.closeMenu();
                            SettingsState.openPage(page.editorSection, edit !== "" ? { look: edit } : { create: page.folder.split("/").pop() });
                        }
                    });
                }
                return out;
            }
            return [];
        }

        visible: page.menu !== ""
        width: popover.isLook ? 300 : 230
        height: Math.min(popover.maxHeight, popoverColumn.implicitHeight + popover.pad * 2)
        x: Math.max(0, Math.min(page.width - popover.width, page.menuX))
        y: page.menuUp ? Math.max(0, page.menuY - popover.height)
                       : Math.max(0, Math.min(page.height - popover.height, page.menuY))
        radius: 14
        color: Colors.surfaceContainer
        border.width: 1
        border.color: Colors.outlineVariant
        clip: true

        // Kommt leicht herangewachsen
        opacity: page.menu !== "" ? 1 : 0
        scale: page.menu !== "" ? 1 : 0.96
        transformOrigin: page.menuUp ? Item.Bottom : Item.Top

        Fade on opacity {}
        Behavior on scale {
            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
        }

        // Klicks bleiben hier
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = true
        }

        Flickable {
            id: popoverFlick

            anchors.fill: parent
            anchors.margins: popover.pad
            clip: true
            contentHeight: popoverColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const angle = event.angleDelta.y + event.angleDelta.x;
                    const pixels = event.pixelDelta.y + event.pixelDelta.x;
                    const delta = angle !== 0 ? angle / 120 : pixels / 40;
                    const max = Math.max(0, popoverFlick.contentHeight - popoverFlick.height);
                    popoverFlick.contentY = Math.max(0, Math.min(max, popoverFlick.contentY - delta * 60));
                    event.accepted = true;
                }
            }

            Column {
                id: popoverColumn

                width: parent.width
                spacing: 1

                // Kopf: Titel, in Unterseiten mit Zurueck
                Item {
                    width: parent.width
                    height: popover.title !== "" ? 30 : 0
                    visible: popover.title !== ""

                    Quiet {
                        id: popBack

                        anchors {
                            left: parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        visible: popover.sub
                        icon: "arrow_back"
                        tint: Colors.fgSurfaceVariant
                        onClicked: page.menu = page.menuRoot
                    }

                    Text {
                        anchors {
                            left: parent.left
                            right: parent.right
                            leftMargin: popover.sub ? popBack.width + 2 : 10
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        font.family: Config.font
                        text: popover.title
                        color: Colors.fgBackground
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }

                Text {
                    width: parent.width
                    visible: popover.note !== ""
                    leftPadding: 10
                    rightPadding: 10
                    bottomPadding: 6
                    font.family: Config.font
                    text: popover.note
                    color: Colors.fgSurfaceVariant
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    visible: page.menu === "verschieben" && popover.rows.length === 0
                    leftPadding: 10
                    rightPadding: 10
                    topPadding: 4
                    bottomPadding: 8
                    font.family: Config.font
                    text: I18n.tr("Kein anderer Ordner – in der Bibliothek „Neuer Ordner“ anlegen")
                    color: Colors.fgSurfaceVariant
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: popover.rows

                    Rectangle {
                        id: row

                        required property var modelData

                        readonly property bool current: row.modelData.current === true
                        readonly property bool on: row.modelData.enabled !== false
                        readonly property bool hasCard: popover.isLook
                        readonly property color fg: row.modelData.danger === true ? Colors.error
                                                  : row.current ? Colors.fgBackground : Colors.fgSurface

                        width: parent.width
                        height: popover.isLook ? Math.max(44, rowText.implicitHeight + 12) : 30
                        radius: 9
                        opacity: row.on ? 1 : 0.45
                        color: row.current ? Colors.alpha(Colors.primary, 0.14)
                             : rowHover.hovered && row.on ? Colors.alpha(Colors.fgSurface, 0.08)
                             : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Appearance.fadeDuration }
                        }

                        // Links: Symbol oder die 3:4-Logo-Karte
                        Item {
                            id: lead

                            anchors {
                                left: parent.left
                                leftMargin: popover.isLook ? 6 : 8
                                verticalCenter: parent.verticalCenter
                            }
                            width: popover.isLook ? 27 : 18
                            height: popover.isLook ? 36 : 18

                            Rectangle {
                                id: cardFrame

                                anchors.fill: parent
                                visible: popover.isLook
                                radius: 5
                                color: Colors.alpha(Colors.fgSurface, 0.08)

                                Image {
                                    id: cardImage

                                    anchors.fill: parent
                                    visible: false
                                    source: (row.modelData.card ?? "") !== "" ? "file://" + row.modelData.card : ""
                                    // Nur eine Briefmarke der 600x800-Karte dekodieren
                                    sourceSize: Qt.size(54, 72)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }

                                Item {
                                    id: cardMask

                                    anchors.fill: cardImage
                                    layer.enabled: true
                                    visible: false

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: cardFrame.radius
                                        color: "black"
                                    }
                                }

                                MultiEffect {
                                    anchors.fill: cardImage
                                    visible: cardImage.status === Image.Ready
                                    source: cardImage
                                    maskEnabled: true
                                    maskSource: cardMask
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: !popover.isLook || cardImage.status !== Image.Ready
                                text: row.modelData.icon ?? ""
                                color: row.modelData.danger === true ? Colors.error
                                     : row.current ? Colors.primary : Colors.fgSurfaceVariant
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 16
                                font.variableAxes: ({ FILL: row.current ? 1 : 0 })
                            }
                        }

                        Column {
                            id: rowText

                            anchors {
                                left: lead.right
                                right: trailing.left
                                leftMargin: 9
                                rightMargin: 4
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 1

                            Text {
                                width: parent.width
                                font.family: Config.font
                                text: row.modelData.title
                                color: row.fg
                                font.pixelSize: 11
                                font.weight: row.current ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: popover.isLook && (row.modelData.desc ?? "") !== ""
                                font.family: Config.font
                                text: row.modelData.desc ?? ""
                                color: Colors.fgSurfaceVariant
                                font.pixelSize: 9
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        // Rechts: Haken, Pfeil in Unterseiten oder der Wert (Menue)
                        Row {
                            id: trailing

                            anchors {
                                right: parent.right
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 4

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !popover.isLook && (row.modelData.desc ?? "") !== ""
                                font.family: Config.font
                                text: row.modelData.desc ?? ""
                                color: Colors.fgSurfaceVariant
                                font.pixelSize: 10
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: row.current || row.modelData.sub === true
                                text: row.current ? "check" : "chevron_right"
                                color: row.current ? Colors.primary : Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 15
                            }
                        }

                        HoverHandler {
                            id: rowHover

                            cursorShape: row.on ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }

                        TapHandler {
                            enabled: row.on
                            onTapped: row.modelData.action()
                        }
                    }
                }
            }
        }
    }
}
