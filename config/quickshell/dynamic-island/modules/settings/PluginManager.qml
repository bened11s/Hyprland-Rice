pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Qt.labs.folderlistmodel
import qs.modules.services.config
import qs.modules.services.plugins
import qs.modules.widgets

import qs

// Plugin-Verwaltung – die Seite hinter "Plugins verwalten" im Einstellungs-
// Fenster (SettingsCard.qml zeigt sie statt der Zeilenliste).
//
// Eine einspaltige Liste (hoechstens 820 px breit) in einem gerundeten
// Behaelter: je Plugin eine Zeile aus Symbol, Name, einer Unterzeile
// (Beschreibung bzw. Zwischenzustand/Fehler) und rechts Einstellungen-Knopf,
// An/Aus-Schalter und ⋮-Menue (Komponenten, Exportieren, Zuruecksetzen,
// Entfernen – zweistufig, die Rueckfrage steht in der Zeile).
// Kopfzeile: Importieren, rechts ⋮ mit "Ordner oeffnen" und dem Schalter fuer
// Einstellungswerte im Export.
//
// Import und Export laufen ueber die CLI (Plugins.importPlugin/exportPlugin/
// removePlugin); das Ergebnis steht in Plugins.lastResult und erscheint hier
// als Banner, solange es nicht weggeklickt ist.
//
// Kein Dateidialog: das Fenster ist eine Layer-Oberflaeche mit exklusivem
// Tastaturfokus, ein zenity/kdialog-Fenster laege darunter und waere nicht
// bedienbar. Stattdessen listet die Import-Ansicht die .dip-Pakete aus
// ~/Downloads, ~ und ~/Documents (FolderListModel) und hat ein Pfadfeld;
// Exporte landen in ~/Downloads/<id>-<version>.dip (page.exportDir).
//
// Komponenten (Manifest `parent`, z.B. Bonsai unter Desktop-Widgets) stehen
// nicht oben, sondern im Untermenue ihres Plugins: der Eintrag im ⋮-Menue
// (Titel aus Manifest `components`) oeffnet es. Dort stehen die
// Grundausstattung des Plugins (seine eigenen `widgets`), die Zeilen der
// Komponenten und ein Import, der nur Komponenten dieses Plugins annimmt.
Item {
    id: page

    // Zur Gruppe eines Plugins springen ("plugin:<id>")
    signal openSection(string section)

    readonly property string home: Quickshell.env("HOME")
    readonly property string exportDir: page.home + "/Downloads"

    property bool importOpen: false
    property string importPath: ""
    property bool importEnable: true
    property bool exportWithSettings: true

    // Offenes Untermenue: id des Eltern-Plugins, "" = Uebersicht
    property string subPage: ""
    readonly property var subInfo: page.subPage !== "" ? Plugins.plugins.find(p => p.id === page.subPage) ?? null : null
    readonly property var subChildren: page.subPage !== "" ? Plugins.childrenOf(page.subPage) : []
    readonly property string subTitle: I18n.tr(page.subInfo?.components?.title ?? "Komponenten")
    // Plugin verschwunden (entfernt, Manifest kaputt) -> zurueck zur Uebersicht
    onSubInfoChanged: if (page.subPage !== "" && page.subInfo === null) page.subPage = ""

    function openSub(id: string): void {
        page.subPage = id;
        page.importOpen = false;
        page.importPath = "";
        flick.contentY = 0;
    }

    readonly property bool busy: Plugins.busy
    // Ergebnis-Banner: das letzte CLI-Ergebnis, bis es weggeklickt wird
    property var dismissed: null
    readonly property var result: Plugins.lastResult !== null && Plugins.lastResult !== page.dismissed
                                  ? Plugins.lastResult : null

    // Was gerade in der Liste steht: oben die Plugins, im Untermenue die Komponenten
    readonly property var listed: page.subPage !== "" ? page.subChildren : Plugins.topLevel

    function openFolder(path: string): void {
        Quickshell.execDetached(["xdg-open", path]);
        // Das Fenster laege sonst ueber dem Dateimanager
        SettingsState.close();
    }

    function exportPlugin(info: var): void {
        Plugins.exportPlugin(info.id, `${page.exportDir}/${info.id}-${info.version}.dip`, page.exportWithSettings);
    }

    function expand(path: string): string {
        let p = path.trim();
        if (p.startsWith("file://"))
            p = p.slice(7);
        if (p === "~" || p.startsWith("~/"))
            p = page.home + p.slice(1);
        return p;
    }

    function runImport(): void {
        const p = page.expand(page.importPath);
        if (p === "" || page.busy)
            return;
        Plugins.importPlugin(p, page.importEnable, page.subPage);
    }

    // An/Aus zeigt der Schalter selbst; Text nur fuer die Zwischenzustaende
    function statusLabel(s: string): string {
        return ({ blocked: I18n.tr("Wartet"), loading: I18n.tr("Lädt"), error: I18n.tr("Fehler"), invalid: I18n.tr("Ungültig") })[s] ?? "";
    }

    function statusColor(s: string): color {
        return s === "ready" ? Colors.primary
             : s === "loading" ? Colors.secondary
             : s === "off" || s === "blocked" ? Colors.fgSurfaceVariant
             : Colors.error;
    }

    function opLabel(op: string): string {
        return ({ "import": "Import", "export": "Export", "remove": I18n.tr("Entfernen") })[op] ?? op;
    }

    function formatSize(bytes: real): string {
        if (bytes >= 1048576)
            return (bytes / 1048576).toFixed(1) + " MB";
        if (bytes >= 1024)
            return Math.round(bytes / 1024) + " KB";
        return bytes + " B";
    }

    function pluginName(id: string): string {
        const name = Plugins.plugins.find(p => p.id === id)?.name;
        return name ? I18n.tr(name) : id;
    }

    function shortPath(p: string): string {
        return p.startsWith(page.home) ? "~" + p.slice(page.home.length) : p;
    }

    // Nach einem geglueckten Import die Import-Ansicht zuklappen; ein neues
    // Ergebnis zeigt sich immer, auch wenn das alte weggeklickt war
    Connections {
        target: Plugins

        function onLastResultChanged(): void {
            page.dismissed = null;
            const r = Plugins.lastResult;
            if (r?.ok && r.op === "import") {
                page.importOpen = false;
                page.importPath = "";
            }
        }
    }

    // ---- .dip-Pakete in den ueblichen Ordnern ----
    component DipFolder: FolderListModel {
        nameFilters: ["*.dip"]
        showDirs: false
        showDotAndDotDot: false
        showOnlyReadable: true
        sortField: FolderListModel.Time
        onCountChanged: page.collectFiles()
        onStatusChanged: if (status === FolderListModel.Ready) page.collectFiles()
    }

    DipFolder { id: dlFolder; folder: "file://" + page.home + "/Downloads" }
    DipFolder { id: homeFolder; folder: "file://" + page.home }
    DipFolder { id: docFolder; folder: "file://" + page.home + "/Documents" }

    // [{ name, path, dir, size, modified }], neueste zuerst
    property var files: []

    function collectFiles(): void {
        const out = [];
        for (const f of [dlFolder, homeFolder, docFolder]) {
            for (let i = 0; i < f.count; i++) {
                const path = f.get(i, "filePath");
                out.push({
                    name: f.get(i, "fileName"),
                    path,
                    dir: page.shortPath(path.slice(0, path.lastIndexOf("/"))) || "/",
                    size: f.get(i, "fileSize"),
                    modified: f.get(i, "fileModified")
                });
            }
        }
        out.sort((a, b) => b.modified - a.modified);
        page.files = out;
    }

    // ---- Bausteine ----

    // Knopf: nur Text (flache Pille) oder nur Symbol (rund, ohne Flaeche)
    component ActionButton: Rectangle {
        id: button

        property string icon: ""
        property string label: ""
        property color tint: Colors.fgSurface
        property bool filled: false
        signal clicked()

        implicitWidth: button.label !== "" ? buttonLabel.implicitWidth + 28 : 30
        implicitHeight: 30
        radius: height / 2
        opacity: enabled ? 1 : 0.4
        color: button.filled ? Colors.alpha(Colors.primary, buttonHover.hovered ? 0.85 : 1)
             : Colors.alpha(Colors.fgSurface, (button.label !== "" ? 0.07 : 0) + (buttonHover.hovered && button.enabled ? 0.07 : 0))

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }
        Fade on opacity {}

        Text {
            anchors.centerIn: parent
            visible: button.label === ""
            text: button.icon
            color: button.tint === Colors.fgSurface ? Colors.fgSurfaceVariant : button.tint
            font.family: "Material Symbols Outlined"
            font.pixelSize: 18
        }

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            visible: button.label !== ""
            font.family: Config.font
            text: button.label
            color: button.filled ? Colors.fgPrimary : button.tint
            font.pixelSize: 12
            font.weight: Font.Medium
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

    // Schalter wie in SettingsRow
    component Toggle: Rectangle {
        id: sw

        property bool checked: false
        signal toggled()

        width: 40
        height: 22
        radius: height / 2
        opacity: enabled ? 1 : 0.4
        color: sw.checked ? Colors.primary : Colors.alpha(Colors.fgSurface, 0.18)

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        Rectangle {
            width: 16
            height: 16
            radius: 8
            y: 3
            x: sw.checked ? parent.width - width - 3 : 3
            color: sw.checked ? Colors.fgPrimary : Colors.fgSurfaceVariant

            Morph on x {}
        }

        HoverHandler {
            cursorShape: sw.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: sw.enabled
            onTapped: sw.toggled()
        }
    }

    // ---- Die Zeile eines Plugins ----
    component PluginCard: Item {
        id: pcard

        required property var info
        // Trennlinie zur Zeile darueber
        property bool divider: true
        readonly property string section: Plugins.sectionPrefix + pcard.info.id
        // Eigener Schalter – eine Komponente kann an sein, waehrend ihr
        // Eltern-Plugin aus ist (Status "Wartet")
        readonly property bool on: pcard.info.selfEnabled
        readonly property var components: Plugins.childrenOf(pcard.info.id)
        readonly property bool hasSub: pcard.info.components !== null || pcard.components.length > 0
        readonly property bool hasSettings: pcard.info.hasSettings
        // Irgendein Wert weicht von der Vorgabe ab?
        readonly property bool changed: pcard.hasSettings
            && Object.keys(Plugins.raw[pcard.section] ?? {}).some(k => !Plugins.isDefault(pcard.section, k))
        // Rueckfrage, Fehler oder Zwischenzustand ersetzen die Beschreibung
        readonly property bool alert: pcard.removeArmed || pcard.info.error !== ""
                                      || ["error", "invalid"].includes(pcard.info.status)
        readonly property string subline: {
            const info = pcard.info;
            if (pcard.removeArmed)
                return I18n.tr("Wirklich entfernen?");
            // Pfade auf den Dateinamen kuerzen, sonst fuellt der Pfad die Zeile
            if (info.error !== "")
                return info.error.trim().replace(/\S*\/([^\/\s]+)/g, "$1").replace(/\?v=\d+/g, "");
            if (info.status === "blocked")
                return I18n.tr("%1 aus").arg(page.pluginName(info.parent));
            // Komponente, deren Plugin fehlt – steht deshalb oben
            if (info.parentMissing)
                return I18n.tr("gehört zu „%1“ (nicht installiert)").arg(info.parent);
            return page.statusLabel(info.status) || I18n.tr(info.description);
        }
        readonly property var menu: {
            const info = pcard.info;
            const e = [];
            if (info.status !== "invalid")
                e.push({ text: "v" + info.version + (info.author !== "" ? " · " + info.author : ""), icon: "info", enabled: false });
            if (pcard.hasSub)
                e.push({
                    text: `${I18n.tr(info.components?.title ?? "Komponenten")} · ${pcard.components.length}`,
                    icon: info.components?.icon ?? "extension",
                    action: () => page.openSub(info.id)
                });
            // Eingebaute Plugins gehoeren zur Shell: weder Export noch Entfernen
            if (!info.builtin)
                e.push({ text: I18n.tr("Exportieren"), icon: "upload", enabled: !page.busy && info.status !== "invalid",
                         action: () => page.exportPlugin(info) });
            if (pcard.hasSettings)
                e.push({ text: I18n.tr("Zurücksetzen"), icon: "restart_alt", enabled: pcard.changed,
                         action: () => Plugins.resetPlugin(info.id) });
            if (!info.builtin) {
                if (e.length > 0)
                    e.push({ separator: true });
                e.push({ text: I18n.tr("Entfernen"), icon: "delete", danger: true, enabled: !page.busy,
                         action: () => { pcard.removeArmed = true; disarmRemove.restart(); } });
            }
            return e;
        }

        // Zweistufig: der Menue-Eintrag stellt nur die Rueckfrage in die Zeile
        property bool removeArmed: false

        width: parent.width
        implicitHeight: Math.max(56, texts.implicitHeight + 20)

        Timer {
            id: disarmRemove

            interval: 6000
            onTriggered: pcard.removeArmed = false
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 52
            }
            height: 1
            visible: pcard.divider
            color: Colors.alpha(Colors.outline, 0.16)
        }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 16
                rightMargin: 10
            }
            spacing: 6

            Text {
                Layout.preferredWidth: 24
                Layout.rightMargin: 6
                horizontalAlignment: Text.AlignHCenter
                text: pcard.info.icon
                color: pcard.on ? Colors.primary : Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 20

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }
            }

            Column {
                id: texts

                Layout.fillWidth: true
                Layout.rightMargin: 6
                spacing: 2

                Text {
                    width: parent.width
                    font.family: Config.font
                    text: I18n.tr(pcard.info.name)
                    color: Colors.fgSurface
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                // Fehlermeldungen (Manifest kaputt, Main.qml laedt nicht)
                // duerfen zwei Zeilen haben, alles andere eine
                Text {
                    width: parent.width
                    font.family: Config.font
                    visible: text !== ""
                    text: pcard.subline
                    color: pcard.alert ? Colors.error
                         : pcard.info.status === "loading" ? Colors.secondary
                         : Colors.fgSurfaceVariant
                    font.pixelSize: 11
                    wrapMode: pcard.info.error !== "" && !pcard.removeArmed ? Text.Wrap : Text.NoWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            ActionButton {
                visible: pcard.removeArmed
                label: I18n.tr("Abbrechen")
                onClicked: pcard.removeArmed = false
            }

            ActionButton {
                visible: pcard.removeArmed
                enabled: !page.busy
                label: I18n.tr("Entfernen")
                tint: Colors.error
                onClicked: {
                    pcard.removeArmed = false;
                    Plugins.removePlugin(pcard.info.id);
                }
            }

            Toggle {
                Layout.leftMargin: 4
                Layout.rightMargin: 2
                visible: !pcard.removeArmed
                checked: pcard.on
                enabled: pcard.info.status !== "invalid" && !page.busy
                onToggled: Plugins.toggle(pcard.info.id)
            }

            SettingsMenuButton {
                visible: !pcard.removeArmed
                enabled: pcard.menu.length > 0
                entries: pcard.menu
            }

            // Zu den Einstellungen des Plugins; ohne Einstellungen bleibt der
            // Platz frei, damit die Schalter untereinander stehen
            ActionButton {
                visible: !pcard.removeArmed
                enabled: pcard.hasSettings && pcard.info.enabled
                opacity: pcard.hasSettings ? (enabled ? 1 : 0.4) : 0
                icon: "chevron_right"
                onClicked: page.openSection(pcard.section)
            }
        }
    }

    // ================= Die Seite =================
    Flickable {
        id: flick

        anchors.fill: parent
        clip: true
        contentHeight: column.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds
        interactive: false

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: event => {
                const angle = event.angleDelta.y + event.angleDelta.x;
                const pixels = event.pixelDelta.y + event.pixelDelta.x;
                const delta = angle !== 0 ? angle / 120 : pixels / 40;
                const max = Math.max(0, flick.contentHeight - flick.height);
                flick.contentY = Math.max(0, Math.min(max, flick.contentY - delta * 60));
                event.accepted = true;
            }
        }

        Column {
            id: column

            x: 2
            width: Math.min(flick.width - 4, 820)
            spacing: 10

            // ---- Kopfzeile ----
            Item {
                width: parent.width
                height: 34

                Row {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6

                    ActionButton {
                        visible: page.subPage !== ""
                        icon: "arrow_back"
                        onClicked: page.openSub("")
                    }

                    ActionButton {
                        label: page.importOpen ? I18n.tr("Abbrechen") : I18n.tr("Importieren")
                        onClicked: page.importOpen = !page.importOpen
                    }
                }

                Row {
                    anchors {
                        right: parent.right
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: page.busy
                        text: "progress_activity"
                        color: Colors.primary
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 16

                        RotationAnimation on rotation {
                            running: page.busy
                            from: 0
                            to: 360
                            loops: Animation.Infinite
                            duration: Appearance.morphDuration * 3
                        }
                    }

                    SettingsMenuButton {
                        entries: [
                            { text: I18n.tr("Ordner öffnen"), icon: "folder_open", action: () => page.openFolder(Plugins.dir) },
                            { text: I18n.tr("Einstellungswerte beim Export mitnehmen"), current: page.exportWithSettings,
                              action: () => page.exportWithSettings = !page.exportWithSettings }
                        ]
                    }
                }
            }

            // ---- Ergebnis-Banner ----
            Rectangle {
                id: banner

                readonly property bool ok: page.result?.ok === true
                readonly property string path: page.result?.data?.path ?? ""
                readonly property color tint: banner.ok ? Colors.primary : Colors.error

                width: parent.width
                height: page.result ? Math.max(56, bannerBody.implicitHeight + 20) : 0
                visible: height > 0
                clip: true
                radius: 14
                color: Colors.alpha(banner.tint, 0.1)

                Behavior on height {
                    NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    id: bannerBody

                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 16
                        rightMargin: 10
                    }
                    spacing: 6

                    Text {
                        Layout.preferredWidth: 24
                        Layout.rightMargin: 6
                        horizontalAlignment: Text.AlignHCenter
                        text: banner.ok ? "check_circle" : "error"
                        color: banner.tint
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 20
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.rightMargin: 6
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            font.family: Config.font
                            text: I18n.tr(banner.ok ? "%1 erledigt" : "%1 fehlgeschlagen").arg(page.opLabel(page.result?.op ?? ""))
                            color: Colors.fgSurface
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        Text {
                            Layout.fillWidth: true
                            font.family: Config.font
                            visible: text !== ""
                            text: page.result?.message ?? ""
                            color: Colors.fgSurfaceVariant
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            font.family: Config.font
                            visible: banner.path !== ""
                            text: page.shortPath(banner.path)
                            color: Colors.fgSurfaceVariant
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                    }

                    ActionButton {
                        visible: banner.ok && banner.path !== ""
                        icon: "folder_open"
                        onClicked: page.openFolder(banner.path.slice(0, banner.path.lastIndexOf("/")))
                    }

                    ActionButton {
                        visible: banner.ok && page.result?.op === "import" && (page.result?.data?.id ?? "") !== ""
                                 && Plugins.sections.includes(Plugins.sectionPrefix + page.result.data.id)
                        icon: "tune"
                        onClicked: page.openSection(Plugins.sectionPrefix + page.result.data.id)
                    }

                    ActionButton {
                        icon: "close"
                        onClicked: page.dismissed = Plugins.lastResult
                    }
                }
            }

            // ---- Import-Ansicht ----
            Rectangle {
                id: importPanel

                width: parent.width
                height: page.importOpen ? importBody.implicitHeight + 12 : 0
                visible: height > 0
                clip: true
                radius: 14
                color: Colors.alpha(Colors.fgSurface, 0.045)

                Behavior on height {
                    NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
                }

                Column {
                    id: importBody

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 6
                    }
                    spacing: 2

                    // Gefundene Pakete
                    Repeater {
                        model: page.files

                        Rectangle {
                            id: fileRow

                            required property var modelData
                            readonly property bool selected: page.expand(page.importPath) === fileRow.modelData.path

                            width: parent.width
                            height: 40
                            radius: 10
                            color: fileRow.selected ? Colors.alpha(Colors.primary, 0.16)
                                 : fileHover.hovered ? Colors.alpha(Colors.fgSurface, 0.07)
                                 : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: Appearance.fadeDuration }
                            }

                            RowLayout {
                                anchors {
                                    fill: parent
                                    leftMargin: 10
                                    rightMargin: 12
                                }
                                spacing: 12

                                Text {
                                    Layout.preferredWidth: 24
                                    horizontalAlignment: Text.AlignHCenter
                                    text: "package_2"
                                    color: fileRow.selected ? Colors.primary : Colors.fgSurfaceVariant
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 18
                                }

                                Text {
                                    Layout.maximumWidth: fileRow.width * 0.5
                                    font.family: Config.font
                                    text: fileRow.modelData.name
                                    color: Colors.fgSurface
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                }

                                Text {
                                    Layout.fillWidth: true
                                    font.family: Config.font
                                    text: fileRow.modelData.dir
                                    color: Colors.fgSurfaceVariant
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                }

                                Text {
                                    font.family: Config.font
                                    text: page.formatSize(fileRow.modelData.size)
                                    color: Colors.fgSurfaceVariant
                                    font.pixelSize: 11
                                }
                            }

                            HoverHandler {
                                id: fileHover

                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: page.importPath = page.shortPath(fileRow.modelData.path)
                            }
                        }
                    }

                    Text {
                        visible: page.files.length === 0
                        height: 40
                        leftPadding: 10
                        verticalAlignment: Text.AlignVCenter
                        font.family: Config.font
                        text: I18n.tr("Keine .dip-Pakete in ~/Downloads, ~ oder ~/Documents")
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 11
                    }

                    // Pfadfeld
                    Rectangle {
                        width: parent.width
                        height: 36
                        radius: 10
                        color: Colors.alpha(Colors.fgSurface, pathInput.activeFocus ? 0.09 : 0.06)
                        border.width: 1
                        border.color: pathInput.activeFocus ? Colors.alpha(Colors.primary, 0.5) : "transparent"

                        Behavior on color {
                            ColorAnimation { duration: Appearance.fadeDuration }
                        }
                        Behavior on border.color {
                            ColorAnimation { duration: Appearance.fadeDuration }
                        }

                        TextInput {
                            id: pathInput

                            anchors {
                                left: parent.left
                                leftMargin: 12
                                right: parent.right
                                rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            font.family: Config.font
                            font.pixelSize: 12
                            color: Colors.fgSurface
                            selectionColor: Colors.alpha(Colors.primary, 0.35)
                            clip: true
                            text: page.importPath
                            onTextEdited: page.importPath = text
                            onAccepted: page.runImport()

                            Text {
                                anchors.fill: parent
                                visible: pathInput.text === ""
                                text: I18n.tr("~/Downloads/mein-plugin-1.0.0.dip")
                                color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                                font: pathInput.font
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // Im Untermenue: was der Import annimmt
                    Text {
                        width: parent.width
                        visible: page.subPage !== ""
                        topPadding: 6
                        leftPadding: 10
                        rightPadding: 10
                        font.family: Config.font
                        text: I18n.tr("Angenommen werden nur Komponenten (Manifest \"parent\": \"%1\").").arg(page.subPage)
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        width: parent.width
                        height: 46
                        spacing: 10

                        Text {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            font.family: Config.font
                            text: I18n.tr("Nach dem Import einschalten")
                            color: Colors.fgSurface
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Toggle {
                            checked: page.importEnable
                            onToggled: page.importEnable = !page.importEnable
                        }

                        ActionButton {
                            Layout.rightMargin: 4
                            filled: true
                            enabled: page.importPath.trim() !== "" && !page.busy
                            label: I18n.tr("Importieren")
                            onClicked: page.runImport()
                        }
                    }
                }
            }

            // ---- Untermenue: Kopf ----
            Column {
                id: subHead

                readonly property bool parentOn: page.subInfo?.enabled ?? false

                x: 16
                width: parent.width - 32
                visible: page.subPage !== ""
                topPadding: 4
                spacing: 3

                Text {
                    width: parent.width
                    font.family: Config.font
                    text: I18n.tr(page.subInfo?.name ?? "") + " › " + page.subTitle
                    color: Colors.fgSurface
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    font.family: Config.font
                    visible: text !== ""
                    text: I18n.tr(page.subInfo?.components?.desc ?? "")
                    color: Colors.fgSurfaceVariant
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }

                // Was das Plugin selbst schon mitbringt
                Text {
                    width: parent.width
                    font.family: Config.font
                    visible: (page.subInfo?.widgets ?? []).length > 0
                    text: I18n.tr("Eingebaut") + ": " + (page.subInfo?.widgets ?? []).map(w => I18n.tr(w.title)).join(", ")
                    color: Colors.fgSurfaceVariant
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }
            }

            // ---- Die Plugins (bzw. im Untermenue die Komponenten) ----
            Rectangle {
                width: parent.width
                height: rows.implicitHeight
                visible: height > 0
                radius: 14
                color: Colors.alpha(Colors.fgSurface, 0.045)

                Column {
                    id: rows

                    width: parent.width

                    // Eltern-Plugin aus: Komponenten warten
                    Item {
                        width: parent.width
                        height: 56
                        visible: page.subPage !== "" && !subHead.parentOn

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 16
                                rightMargin: 10
                            }
                            spacing: 6

                            Text {
                                Layout.preferredWidth: 24
                                Layout.rightMargin: 6
                                horizontalAlignment: Text.AlignHCenter
                                text: "pause_circle"
                                color: Colors.fgSurfaceVariant
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 20
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.rightMargin: 6
                                font.family: Config.font
                                text: I18n.tr("%1 ist aus – eingeschaltete Komponenten laufen erst, wenn es an ist.").arg(I18n.tr(page.subInfo?.name ?? ""))
                                color: Colors.fgSurfaceVariant
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            ActionButton {
                                enabled: !page.busy && page.subInfo?.status !== "invalid"
                                label: I18n.tr("Einschalten")
                                onClicked: Plugins.setEnabled(page.subPage, true)
                            }
                        }
                    }

                    Repeater {
                        model: page.listed

                        PluginCard {
                            required property var modelData
                            required property int index

                            info: modelData
                            divider: index > 0 || (page.subPage !== "" && !subHead.parentOn)
                        }
                    }
                }
            }

            // Untermenue ohne Komponenten / kein Plugin da
            Text {
                x: 16
                width: parent.width - 32
                topPadding: 8
                visible: page.subPage !== "" ? page.listed.length === 0 : Plugins.plugins.length === 0
                font.family: Config.font
                text: page.subPage !== "" ? I18n.tr("Noch keine %1 installiert").arg(page.subTitle)
                    : I18n.tr("Keine Plugins gefunden") + " – "
                      + I18n.tr("Ein Paket importieren oder einen Ordner nach %1 legen").arg(page.shortPath(Plugins.dir))
                color: Colors.fgSurfaceVariant
                font.pixelSize: 12
                wrapMode: Text.Wrap
            }
        }
    }

    // Weiche Kante unten, solange noch etwas folgt
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 24
        visible: flick.contentHeight - flick.contentY - flick.height > 2
        gradient: Gradient {
            GradientStop { position: 0; color: Colors.alpha(Colors.background, 0) }
            GradientStop { position: 1; color: Colors.background }
        }
    }
}
