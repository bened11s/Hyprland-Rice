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
// Oben Importieren und Ordner oeffnen, darunter je Plugin eine Karte:
// Symbol, Name, Version, Autor, Beschreibung, was es mitbringt (Einstellungen,
// Kacheln, Launcher-Aktionen, Kuerzel – eine Textzeile), ein An/Aus-
// Schalter und die Knoepfe Einstellungen / Exportieren / Zuruecksetzen /
// Entfernen (zweistufig, wie "Alles zuruecksetzen" in der Leiste).
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
// nicht oben, sondern im Untermenue ihres Plugins: der Knopf auf dessen
// Karte (Titel aus Manifest `components`) oeffnet es. Dort gibt es die
// Grundausstattung des Plugins (seine eigenen `widgets`), die Karten der
// Komponenten und einen Import, der nur Komponenten dieses Plugins annimmt.
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
    readonly property int activeCount: page.listed.filter(p => p.enabled).length

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

    // Knopf im Chip-Stil (wie "Standard" im Kachel-Editor)
    component ActionButton: Rectangle {
        id: button

        required property string icon
        required property string label
        property color tint: Colors.fgSurface
        property bool filled: false
        signal clicked()

        implicitWidth: buttonRow.implicitWidth + 22
        implicitHeight: 28
        radius: height / 2
        opacity: enabled ? 1 : 0.4
        color: button.filled ? (buttonHover.hovered ? Colors.alpha(Colors.primary, 0.85) : Colors.primary)
             : buttonHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12)
             : Colors.alpha(Colors.fgSurface, 0.06)

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
                text: button.icon
                color: button.filled ? Colors.fgPrimary : button.tint
                font.family: "Material Symbols Outlined"
                font.pixelSize: 15

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Config.font
                text: button.label
                color: button.filled ? Colors.fgPrimary : button.tint
                font.pixelSize: 11
                font.weight: button.filled ? Font.DemiBold : Font.Normal

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }
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

    // ---- Die Karte eines Plugins ----
    component PluginCard: Rectangle {
        id: pcard

        required property var info
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
        readonly property color statusTint: page.statusColor(pcard.info.status)
        // Was das Plugin mitbringt, als eine Zeile: "4 Einstellungen, 1 Kachel, SUPER+ALT+D"
        readonly property string features: {
            const info = pcard.info;
            const parts = [];
            if (info.settingsCount > 0)
                parts.push(info.settingsCount === 1 ? I18n.tr("1 Einstellung") : I18n.tr("%1 Einstellungen").arg(info.settingsCount));
            if (info.tiles.length > 0)
                parts.push(info.tiles.length === 1 ? I18n.tr("1 Kachel") : I18n.tr("%1 Kacheln").arg(info.tiles.length));
            if (info.widgets.length > 0)
                parts.push(info.widgets.length === 1 ? I18n.tr("1 Desktop-Widget") : I18n.tr("%1 Desktop-Widgets").arg(info.widgets.length));
            if (info.actions > 0)
                parts.push(info.actions === 1 ? I18n.tr("1 Launcher-Aktion") : I18n.tr("%1 Launcher-Aktionen").arg(info.actions));
            for (const k of info.keybinds)
                parts.push(k.keys);
            // Komponente, deren Plugin fehlt – steht deshalb oben
            if (info.parentMissing)
                parts.push(I18n.tr("gehört zu „%1“ (nicht installiert)").arg(info.parent));
            return parts.join(", ");
        }

        property bool removeArmed: false

        width: parent.width
        implicitHeight: body.implicitHeight + 28
        radius: 14
        color: Colors.alpha(Colors.fgSurface, cardHover.hovered ? 0.07 : 0.045)
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.18)

        Behavior on color {
            ColorAnimation { duration: Appearance.fadeDuration }
        }

        HoverHandler {
            id: cardHover
        }

        Timer {
            id: disarmRemove

            interval: 3000
            onTriggered: pcard.removeArmed = false
        }

        ColumnLayout {
            id: body

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 14
            }
            spacing: 10

            // Kopf: Symbol, Name, Status, Schalter
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignTop
                    radius: 13
                    color: pcard.on ? Colors.alpha(Colors.primary, 0.16) : Colors.alpha(Colors.fgSurface, 0.08)

                    Behavior on color {
                        ColorAnimation { duration: Appearance.fadeDuration }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: pcard.info.icon
                        color: pcard.on ? Colors.primary : Colors.fgSurfaceVariant
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 22
                        font.variableAxes: ({ FILL: pcard.on ? 1 : 0 })

                        Behavior on color {
                            ColorAnimation { duration: Appearance.fadeDuration }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Row {
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Config.font
                            text: I18n.tr(pcard.info.name)
                            color: Colors.fgBackground
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pcard.info.status !== "invalid"
                            width: versionLabel.implicitWidth + 12
                            height: 18
                            radius: 9
                            color: Colors.alpha(Colors.fgSurface, 0.08)

                            Text {
                                id: versionLabel

                                anchors.centerIn: parent
                                font.family: Config.font
                                text: "v" + pcard.info.version
                                color: Colors.fgSurfaceVariant
                                font.pixelSize: 10
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Config.font
                            visible: pcard.info.author !== ""
                            text: I18n.tr("von %1").arg(pcard.info.author)
                            color: Colors.fgSurfaceVariant
                            font.pixelSize: 10
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        font.family: Config.font
                        visible: text !== ""
                        text: I18n.tr(pcard.info.description)
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    // Fehlermeldung (Manifest kaputt, Main.qml laedt nicht)
                    RowLayout {
                        Layout.fillWidth: true
                        visible: pcard.info.error !== ""
                        spacing: 5

                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: "error"
                            color: Colors.error
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 13
                        }

                        Text {
                            Layout.fillWidth: true
                            font.family: Config.font
                            text: pcard.info.error
                            color: Colors.error
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }
                }

                // Zwischenzustand (Wartet, Laedt, Fehler, Ungueltig) – An/Aus
                // sagt der Schalter
                Text {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 6
                    font.family: Config.font
                    visible: text !== ""
                    text: pcard.info.status === "blocked" ? I18n.tr("%1 aus").arg(page.pluginName(pcard.info.parent))
                        : page.statusLabel(pcard.info.status)
                    color: pcard.statusTint
                    font.pixelSize: 10
                }

                Toggle {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                    checked: pcard.on
                    enabled: pcard.info.status !== "invalid" && !page.busy
                    onToggled: Plugins.toggle(pcard.info.id)
                }
            }

            // Was das Plugin mitbringt – buendig mit der Beschreibung
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 52
                font.family: Config.font
                visible: pcard.info.status !== "invalid" && text !== ""
                text: pcard.features
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            // Knoepfe
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 52
                spacing: 6

                // Untermenue mit den Komponenten
                ActionButton {
                    visible: pcard.hasSub
                    filled: true
                    icon: pcard.info.components?.icon ?? "extension"
                    label: `${I18n.tr(pcard.info.components?.title ?? "Komponenten")} · ${pcard.components.length}`
                    onClicked: page.openSub(pcard.info.id)
                }

                ActionButton {
                    visible: pcard.hasSettings
                    enabled: pcard.info.enabled
                    icon: "tune"
                    label: I18n.tr("Einstellungen")
                    onClicked: page.openSection(pcard.section)
                }

                // Eingebaute Plugins gehoeren zur Shell: nur an/aus
                ActionButton {
                    visible: !pcard.info.builtin
                    enabled: !page.busy && pcard.info.status !== "invalid"
                    icon: "upload"
                    label: I18n.tr("Exportieren")
                    onClicked: page.exportPlugin(pcard.info)
                }

                ActionButton {
                    visible: pcard.hasSettings
                    enabled: pcard.changed
                    icon: "restart_alt"
                    label: I18n.tr("Zurücksetzen")
                    onClicked: Plugins.resetPlugin(pcard.info.id)
                }

                // Zweistufig, wie "Alles zuruecksetzen": erst "Entfernen",
                // dann 3 s lang "Wirklich?"
                ActionButton {
                    visible: !pcard.info.builtin
                    enabled: !page.busy
                    icon: pcard.removeArmed ? "check" : "delete"
                    label: pcard.removeArmed ? I18n.tr("Wirklich entfernen?") : I18n.tr("Entfernen")
                    tint: pcard.removeArmed ? Colors.error : Colors.fgSurface
                    onClicked: {
                        if (pcard.removeArmed) {
                            pcard.removeArmed = false;
                            Plugins.removePlugin(pcard.info.id);
                        } else {
                            pcard.removeArmed = true;
                            disarmRemove.restart();
                        }
                    }
                }
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

            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 2
                rightMargin: 2
            }
            spacing: 8

            // ---- Kopfzeile ----
            Item {
                width: parent.width
                height: 36

                Row {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6

                    ActionButton {
                        visible: page.subPage !== ""
                        icon: "arrow_back"
                        label: I18n.tr("Alle Plugins")
                        onClicked: page.openSub("")
                    }

                    ActionButton {
                        icon: page.importOpen ? "expand_less" : "download"
                        label: I18n.tr("Importieren")
                        filled: page.importOpen
                        onClicked: page.importOpen = !page.importOpen
                    }

                    ActionButton {
                        visible: page.subPage === ""
                        icon: "folder_open"
                        label: I18n.tr("Ordner öffnen")
                        onClicked: page.openFolder(Plugins.dir)
                    }
                }

                // Rechts: Einstellungswerte in den Export mitnehmen, Zaehler
                // oder "laeuft"
                Row {
                    anchors {
                        right: parent.right
                        rightMargin: 4
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Plugins.plugins.length > 0 && page.subPage === "" && !page.busy
                        font.family: Config.font
                        text: I18n.tr("Einstellungswerte mitnehmen")
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 10
                    }

                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Plugins.plugins.length > 0 && page.subPage === "" && !page.busy
                        checked: page.exportWithSettings
                        onToggled: page.exportWithSettings = !page.exportWithSettings
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Plugins.plugins.length > 0 && page.subPage === "" && !page.busy
                        width: 1
                        height: 14
                        color: Colors.alpha(Colors.outline, 0.3)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: page.busy
                        text: "progress_activity"
                        color: Colors.primary
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 15

                        RotationAnimation on rotation {
                            running: page.busy
                            from: 0
                            to: 360
                            loops: Animation.Infinite
                            duration: Appearance.morphDuration * 3
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Config.font
                        text: page.busy ? I18n.tr("Bitte warten…")
                            : page.listed.length === 0 ? ""
                            : page.subPage !== "" ? (page.listed.length === 1 ? I18n.tr("1 Komponente · %1 aktiv").arg(page.activeCount)
                                                     : I18n.tr("%1 Komponenten · %2 aktiv").arg(page.listed.length).arg(page.activeCount))
                            : (page.listed.length === 1 ? I18n.tr("1 Plugin · %1 aktiv").arg(page.activeCount)
                               : I18n.tr("%1 Plugins · %2 aktiv").arg(page.listed.length).arg(page.activeCount))
                        color: page.busy ? Colors.primary : Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                        font.pixelSize: 10
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
                height: page.result ? bannerBody.implicitHeight + 20 : 0
                visible: height > 0
                clip: true
                radius: 12
                color: Colors.alpha(banner.tint, 0.1)
                border.width: 1
                border.color: Colors.alpha(banner.tint, 0.35)

                Behavior on height {
                    NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    id: bannerBody

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        leftMargin: 14
                        rightMargin: 8
                        topMargin: 10
                    }
                    spacing: 10

                    Text {
                        Layout.alignment: Qt.AlignTop
                        text: banner.ok ? "check_circle" : "error"
                        color: banner.tint
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 18
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            Layout.fillWidth: true
                            font.family: Config.font
                            text: I18n.tr(banner.ok ? "%1 erledigt" : "%1 fehlgeschlagen").arg(page.opLabel(page.result?.op ?? ""))
                            color: Colors.fgBackground
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Text {
                            Layout.fillWidth: true
                            font.family: Config.font
                            visible: text !== ""
                            text: page.result?.message ?? ""
                            color: Colors.fgSurfaceVariant
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            font.family: Config.font
                            visible: banner.path !== ""
                            text: page.shortPath(banner.path)
                            color: Colors.fgSurface
                            font.pixelSize: 10
                            elide: Text.ElideMiddle
                        }
                    }

                    ActionButton {
                        Layout.alignment: Qt.AlignTop
                        visible: banner.ok && banner.path !== ""
                        icon: "folder_open"
                        label: I18n.tr("Im Ordner zeigen")
                        onClicked: page.openFolder(banner.path.slice(0, banner.path.lastIndexOf("/")))
                    }

                    ActionButton {
                        Layout.alignment: Qt.AlignTop
                        visible: banner.ok && page.result?.op === "import" && (page.result?.data?.id ?? "") !== ""
                                 && Plugins.sections.includes(Plugins.sectionPrefix + page.result.data.id)
                        icon: "tune"
                        label: I18n.tr("Einstellungen")
                        onClicked: page.openSection(Plugins.sectionPrefix + page.result.data.id)
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        width: 26
                        height: 26
                        radius: 13
                        color: dismissHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "close"
                            color: Colors.fgSurfaceVariant
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 15
                        }

                        HoverHandler {
                            id: dismissHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: page.dismissed = Plugins.lastResult
                        }
                    }
                }
            }

            // ---- Import-Ansicht ----
            Rectangle {
                id: importPanel

                width: parent.width
                height: page.importOpen ? importBody.implicitHeight + 28 : 0
                visible: height > 0
                clip: true
                radius: 14
                color: Colors.alpha(Colors.fgSurface, 0.045)
                border.width: 1
                border.color: Colors.alpha(Colors.primary, 0.35)

                Behavior on height {
                    NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
                }

                Column {
                    id: importBody

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 14
                    }
                    spacing: 8

                    Text {
                        font.family: Config.font
                        text: page.subPage !== "" ? I18n.tr("%1 für %2 importieren").arg(page.subTitle).arg(I18n.tr(page.subInfo?.name ?? "")) : I18n.tr("Paket importieren")
                        color: Colors.fgBackground
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Text {
                        width: parent.width
                        font.family: Config.font
                        text: I18n.tr("Ein .dip-Paket aus Downloads, Home oder Dokumenten wählen – oder unten den Pfad eintragen.")
                              + (page.subPage !== "" ? " " + I18n.tr("Angenommen werden nur Komponenten (Manifest \"parent\": \"%1\").").arg(page.subPage) : "")
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }

                    // Gefundene Pakete
                    Column {
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: page.files

                            Rectangle {
                                id: fileRow

                                required property var modelData
                                readonly property bool selected: page.expand(page.importPath) === fileRow.modelData.path

                                width: parent.width
                                height: 34
                                radius: 10
                                color: fileRow.selected ? Colors.alpha(Colors.primary, 0.16)
                                     : fileHover.hovered ? Colors.alpha(Colors.fgSurface, 0.07)
                                     : "transparent"

                                Behavior on color {
                                    ColorAnimation { duration: Appearance.fadeDuration }
                                }

                                Text {
                                    id: fileIcon

                                    anchors {
                                        left: parent.left
                                        leftMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: "package_2"
                                    color: fileRow.selected ? Colors.primary : Colors.fgSurfaceVariant
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 17
                                }

                                Text {
                                    id: fileName

                                    font.family: Config.font
                                    anchors {
                                        left: fileIcon.right
                                        leftMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: fileRow.modelData.name
                                    color: Colors.fgBackground
                                    font.pixelSize: 11
                                    font.weight: fileRow.selected ? Font.DemiBold : Font.Normal
                                }

                                Text {
                                    font.family: Config.font
                                    anchors {
                                        left: fileName.right
                                        leftMargin: 8
                                        right: fileSize.left
                                        rightMargin: 8
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: fileRow.modelData.dir
                                    color: Colors.fgSurfaceVariant
                                    font.pixelSize: 10
                                    elide: Text.ElideMiddle
                                }

                                Text {
                                    id: fileSize

                                    font.family: Config.font
                                    anchors {
                                        right: parent.right
                                        rightMargin: 12
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: page.formatSize(fileRow.modelData.size)
                                    color: Colors.fgSurfaceVariant
                                    font.pixelSize: 10
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

                        Row {
                            visible: page.files.length === 0
                            height: 30
                            spacing: 6
                            leftPadding: 10

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "search_off"
                                color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 15
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Config.font
                                text: I18n.tr("Keine .dip-Pakete in ~/Downloads, ~ oder ~/Documents")
                                color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                                font.pixelSize: 10
                            }
                        }
                    }

                    // Pfadfeld
                    Rectangle {
                        width: parent.width
                        height: 32
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

                        Text {
                            id: pathIcon

                            anchors {
                                left: parent.left
                                leftMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: "draft"
                            color: Colors.fgSurfaceVariant
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 15
                        }

                        TextInput {
                            id: pathInput

                            anchors {
                                left: pathIcon.right
                                leftMargin: 8
                                right: parent.right
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            font.family: Config.font
                            font.pixelSize: 11
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

                    Item {
                        width: parent.width
                        height: 30

                        Row {
                            anchors {
                                left: parent.left
                                leftMargin: 4
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 8

                            Toggle {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: page.importEnable
                                onToggled: page.importEnable = !page.importEnable
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Config.font
                                text: I18n.tr("Nach dem Import einschalten")
                                color: Colors.fgSurface
                                font.pixelSize: 11
                            }
                        }

                        ActionButton {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            filled: true
                            enabled: page.importPath.trim() !== "" && !page.busy
                            icon: "download"
                            label: I18n.tr("Importieren")
                            onClicked: page.runImport()
                        }
                    }
                }
            }

            // ---- Untermenue: Kopf ----
            Rectangle {
                id: subHead

                readonly property bool parentOn: page.subInfo?.enabled ?? false

                width: parent.width
                visible: page.subPage !== ""
                implicitHeight: subBody.implicitHeight + 28
                radius: 14
                color: Colors.alpha(Colors.primary, 0.06)
                border.width: 1
                border.color: Colors.alpha(Colors.primary, 0.22)

                ColumnLayout {
                    id: subBody

                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 14
                    }
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Layout.alignment: Qt.AlignTop
                            radius: 13
                            color: Colors.alpha(Colors.primary, subHead.parentOn ? 0.16 : 0.08)

                            Text {
                                anchors.centerIn: parent
                                text: page.subInfo?.components?.icon ?? page.subInfo?.icon ?? "extension"
                                color: subHead.parentOn ? Colors.primary : Colors.fgSurfaceVariant
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 22
                                font.variableAxes: ({ FILL: subHead.parentOn ? 1 : 0 })
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            Row {
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: Config.font
                                    text: I18n.tr(page.subInfo?.name ?? "")
                                    color: Colors.fgSurfaceVariant
                                    font.pixelSize: 13
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "chevron_right"
                                    color: Colors.fgSurfaceVariant
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 15
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: Config.font
                                    text: page.subTitle
                                    color: Colors.fgBackground
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                font.family: Config.font
                                visible: text !== ""
                                text: I18n.tr(page.subInfo?.components?.desc ?? "")
                                color: Colors.fgSurfaceVariant
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // Eltern-Plugin aus: Komponenten warten
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 52
                        visible: !subHead.parentOn
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            font.family: Config.font
                            text: I18n.tr("%1 ist aus – eingeschaltete Komponenten laufen erst, wenn es an ist.").arg(I18n.tr(page.subInfo?.name ?? ""))
                            color: Colors.secondary
                            font.pixelSize: 10
                            wrapMode: Text.WordWrap
                        }

                        ActionButton {
                            enabled: !page.busy && page.subInfo?.status !== "invalid"
                            icon: "power_settings_new"
                            label: I18n.tr("Einschalten")
                            onClicked: Plugins.setEnabled(page.subPage, true)
                        }
                    }

                    // Was das Plugin selbst schon mitbringt
                    Text {
                        Layout.fillWidth: true
                        font.family: Config.font
                        visible: (page.subInfo?.widgets ?? []).length > 0
                        text: I18n.tr("Eingebaut") + ": " + (page.subInfo?.widgets ?? []).map(w => I18n.tr(w.title)).join(", ")
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.8)
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---- Die Plugins (bzw. im Untermenue die Komponenten) ----
            // Ab ~850 px zwei Spalten (Karten mindestens 420 px), abwechselnd
            // verteilt; jede Spalte waechst fuer sich
            Row {
                id: cards

                readonly property int columns: cards.width >= 2 * 420 + cards.spacing ? 2 : 1

                width: parent.width
                spacing: 10

                Repeater {
                    model: cards.columns

                    Column {
                        id: cardColumn

                        required property int index

                        width: (cards.width - cards.spacing * (cards.columns - 1)) / cards.columns
                        spacing: 8

                        Repeater {
                            model: page.listed.filter((p, i) => i % cards.columns === cardColumn.index)

                            PluginCard {
                                required property var modelData

                                info: modelData
                            }
                        }
                    }
                }
            }

            // Untermenue ohne Komponenten
            Item {
                width: parent.width
                height: 120
                visible: page.subPage !== "" && page.listed.length === 0

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "add_circle"
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 28
                    }

                    Text {
                        font.family: Config.font
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("Noch keine %1 installiert").arg(page.subTitle)
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 12
                    }

                    Text {
                        font.family: Config.font
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("Oben über „Importieren“ ein .dip-Paket hinzufügen")
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                        font.pixelSize: 10
                    }
                }
            }

            // Kein Plugin da
            Item {
                width: parent.width
                height: 160
                visible: page.subPage === "" && Plugins.plugins.length === 0

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "extension_off"
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 28
                    }

                    Text {
                        font.family: Config.font
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("Keine Plugins gefunden")
                        color: Colors.fgSurfaceVariant
                        font.pixelSize: 12
                    }

                    Text {
                        font.family: Config.font
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("Ein Paket importieren oder einen Ordner nach %1 legen").arg(page.shortPath(Plugins.dir))
                        color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                        font.pixelSize: 10
                    }
                }
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
