pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.services.config
import qs.modules.services.plugins
import qs.modules.services.system
import qs.modules.services.wallpaper
import qs.modules.widgets
import qs.modules.settings.wallpaper

import qs

// Die Karte des Einstellungs-Fensters – SettingsWindow.qml haengt sie in eine
// Layer-Oberflaeche. Als eigenes Item, damit sie sich auch ohne Fenster
// bauen laesst (Vorschau-Screenshots, Tests).
//
// Links eine Leiste mit wenigen Kategorien (card.categories, z. B. Aussehen =
// appearance + wallpaper), rechts die Zeilen ihrer shell.json-Abschnitte,
// je Abschnitt mit Ueberschrift. Die Liste baut sich aus
// ~/.config/dynamic-island/shell.json: jeder Schluessel eine Zeile. Neue
// Schluessel im Adapter (services/config/Config.qml) tauchen hier von selbst
// auf – Namen, Beschreibungen und Bedienelemente kommen aus Config.meta.
// Neue Abschnitte ohne Kategorie landen unter System.
//
// Plugins: ein Eintrag fuer die Verwaltung (PluginManager.qml); deren
// Zeilen oeffnen die Plugin-Gruppen ("plugin:<id>") und Komponenten.
// Gelesen und geschrieben wird ueber die Plugins-Bruecke (Plugins.get/set/...),
// die normale Gruppen an Config weiterreicht.
//
// Die Suche geht ueber alle Gruppen, die Gruppenleiste ist dann aus.
//
// Breite: das Fenster laesst sich frei ziehen. Unter `compact` schrumpft
// die Leiste zur Symbolspalte (Name beim Zeigen daneben). Die Zeilen stehen
// in Karten (je Gruppe und Config.meta-`group` eine), die Karten in so
// vielen Spalten (360–560 px), wie ins Fenster passen – jede Spalte waechst
// fuer sich, damit eine aufgeklappte Auswahl nur ihre eigene verschiebt.
// Karten mit einem breiten Editor (`wideEditors`) gehen ueber die volle Breite.
Surface {
    id: card

    // Suchtext; leert sich beim Oeffnen
    property string filter: ""
    // Gewaehlte Seite: eine Kategorie der Leiste (categories[].key), die
    // Plugin-Verwaltung (managerKey), die Bibliothek (wallsKey), eine
    // Plugin-Gruppe ("plugin:<id>") oder eine Plugin-Seite ("@page:…")
    property string section: "look"

    // Die Leiste: wenige Kategorien statt einer Zeile je shell.json-Abschnitt.
    // Eine Kategorie zeigt ihre Abschnitte untereinander, je mit Ueberschrift.
    readonly property var categories: [
        { key: "account", title: "Konto", desc: "Profilbild, Name, Passwort", icon: "account_circle", sections: ["account"] },
        { key: "look", title: "Aussehen", desc: "Wallpaper, Farben, Transparenz", icon: "palette", sections: ["wallpaper", "appearance"] },
        { key: "notch", title: "Notch", desc: "Layout, Anzeigen, Medien", icon: "top_panel_open", sections: ["notch", "media"] },
        { key: "bar", title: "Leiste", desc: "Workspaces, Module, Regler am Rand", icon: "web_asset", sections: ["bar", "osd"] },
        { key: "quick", title: "Schnelleinstellungen", desc: "Kacheln und ihre Anordnung", icon: "dashboard_customize", sections: ["quick"] },
        { key: "alerts", title: "Benachrichtigungen", desc: "Mitteilungen, Klänge", icon: "notifications", sections: ["notifications", "sounds"] },
        { key: "connect", title: "Bluetooth & VPN", desc: "Geräte, Meldungen, VPN-Anbieter", icon: "bluetooth", sections: ["bluetooth", "vpn"] },
        { key: "battery", title: "Akku", desc: "Anzeige, Warnungen, Verlauf", icon: "battery_charging_full", sections: ["battery"] },
        { key: "lock", title: "Sperren & Standby", desc: "Sperrbildschirm, Ruhezustand", icon: "lock_clock", sections: ["idle", "lock"] },
        { key: "monitors", title: "Monitore", desc: "Anordnung, Auflösung, Skalierung", icon: "monitor", sections: ["monitors"] },
        { key: "keybinds", title: "Tastenkürzel", desc: "Kürzel ansehen und ändern", icon: "keyboard", sections: ["keybinds"] },
        { key: "region", title: "Sprache & Region", desc: "Sprache, Uhrzeit", icon: "language", sections: ["region"] },
        { key: "info", title: "Info", desc: "Version, Updates, System", icon: "info", sections: ["system"] }
    ]
    // Die Leiste in Gruppen (Schluessel aus categories, dazu die Plugin-Verwaltung)
    readonly property var sidebarGroups: [
        ["account"],
        ["look", "notch", "bar", "quick"],
        ["alerts", "connect", "battery", "lock"],
        ["monitors", "keybinds", "region"],
        ["plugins", "info"].map(k => k === "plugins" ? card.managerKey : k)
    ]
    function sidebarEntry(key: string): var {
        return card.categories.find(c => c.key === key)
            ?? { key: card.managerKey, title: "Plugins", desc: "Erweiterungen verwalten", icon: "extension" };
    }
    // Seiten ohne eigenen shell.json-Abschnitt (nur Zeilen mit meta.page)
    readonly property var pageTitles: ({ "region": "Sprache & Region", "notch-media": "Medien", "notch-control": "Steuerung",
                                         "notch-notifications": "Benachrichtigungen", "notch-system": "System" })
    // Unterseiten (Zeilen mit meta.sub oeffnen sie): Seite -> Kategorie fuer Zurueck und Leiste
    readonly property var subParents: ({ "notch-media": "notch", "notch-control": "notch",
                                         "notch-notifications": "notch", "notch-system": "notch" })
    // Abschnitte aus shell.json, die keiner Kategorie gehoeren, landen unter Info
    readonly property var categorySections: {
        const known = [].concat(...card.categories.map(c => c.sections));
        const out = {};
        for (const c of card.categories)
            out[c.key] = c.key === "info" ? c.sections.concat(card.sections.filter(s => !known.includes(s))) : c.sections;
        return out;
    }
    function categoryOf(s: string): string {
        for (const key in card.categorySections)
            if (card.categorySections[key].includes(s))
                return key;
        return "";
    }
    readonly property var category: card.categories.find(c => c.key === card.section) ?? null
    // Abschnitte der gewaehlten Seite
    readonly property var currentSections: card.category ? card.categorySections[card.category.key] : [card.section]
    // Mehrere Abschnitte auf einer Seite: jeder bekommt eine Ueberschrift
    readonly property bool multiSection: !card.searching && card.currentSections.length > 1
    // Abschnitt, zu dem nach dem Aufbau gescrollt wird (openPage("vpn") u. a.)
    property string scrollTarget: ""
    readonly property bool searching: card.filter.trim() !== ""
    // Sichtbar? Steuert das Heranwachsen beim Oeffnen
    property bool shown: true

    readonly property string managerKey: "@plugins"
    readonly property bool managing: !card.searching && card.section === card.managerKey
    // Wallpaper-Bibliothek (WallpaperManager.qml) – dort filtert die Suche
    // die Bilder statt die Einstellungen, die Seite bleibt also stehen
    readonly property string wallsKey: "@wallpapers"
    readonly property bool browsing: card.section === card.wallsKey
    // Farbschemata (wallpaper/ColorsPage.qml) – Unterseite von Aussehen wie die Bibliothek
    readonly property string colorsKey: "@colors"
    readonly property bool coloring: card.section === card.colorsKey
    // Unterseiten von Aussehen: die Suche filtert dort Bilder bzw. Schemata
    readonly property bool lookSub: card.browsing || card.coloring
    // Plugin-Seite (Manifest `pages`, Plugins.pages): "@page:<plugin>/<seite>",
    // geladen ueber ihre URL statt der Zeilenliste; waehrend der Suche
    // zeigt die Karte wie bei der Verwaltung die Treffer
    readonly property var pageInfo: Plugins.pageFor(card.section)
    readonly property bool paging: !card.searching && Plugins.isPageSection(card.section)
    // Argumente fuer die Seite (SettingsState.openPage), leer bei Klick in der Leiste
    property var pageArgs: ({})

    // ---- Breite ----
    // Schmale Karte: Leiste nur mit Symbolen
    readonly property bool compact: card.width < 820
    readonly property real sidebarWidth: card.compact ? 64 : 300
    // Platz der Liste rechts der Leiste (Zielwert, nicht der animierte).
    // Direkt aus der Breite: ueber sidebarWidth gelesen war der Wert beim
    // Entstehen des Fensters kurz veraltet und baute die Karten einmal extra.
    readonly property real listRoom: card.width - (card.width < 820 ? 64 : 300) - 44

    // Gruppen aus shell.json in Menue-Reihenfolge, unbekannte hinten dran
    readonly property var sections: {
        const raw = Config.raw;
        const isGroup = s => typeof raw[s] === "object" && raw[s] !== null;
        const known = Config.sectionOrder.filter(isGroup);
        const extra = Object.keys(raw).filter(s => !known.includes(s) && isGroup(s));
        return known.concat(extra);
    }
    // Dahinter die Gruppen der aktiven Plugins
    readonly property var allSections: card.sections.concat(Plugins.sections)

    // Die Leiste unter "Plugins": je Plugin seine Gruppe (wenn es
    // Einstellungen hat) und darunter seine Seiten; Plugins nur mit Seiten
    // stehen mit diesen allein da
    readonly property var pluginMenu: {
        const out = Plugins.sections.map(s => ({ section: s, id: Plugins.idOf(s) }));
        for (const p of Plugins.pages)
            if (!out.some(e => e.id === p.pluginId))
                out.push({ section: "", id: p.pluginId });
        return out.map(e => ({ section: e.section, id: e.id, pages: Plugins.pages.filter(p => p.pluginId === e.id) }));
    }

    // Die gewaehlte Seite verschwindet (Plugin aus): zur Verwaltung – aber
    // erst, wenn sie einmal da war und eine Weile fehlt (beim Start und bei
    // `plugins reload` ist sie nur kurz weg)
    property bool pageSeen: false

    onPageInfoChanged: {
        if (card.pageInfo !== null) {
            card.pageSeen = true;
            pageGone.stop();
        } else if (card.pageSeen && Plugins.isPageSection(card.section))
            pageGone.restart();
    }

    Timer {
        id: pageGone

        interval: 2000
        onTriggered: {
            if (card.pageInfo === null && Plugins.isPageSection(card.section))
                card.section = card.managerKey;
        }
    }

    // Wunsch von aussen (SettingsState.openPage): Gruppe/Seite samt Argumenten
    function applyRequest(): void {
        const r = SettingsState.takeRequest();
        if (!r)
            return;
        card.pageArgs = r.args ?? {};
        card.select(r.section, true);
    }

    Connections {
        target: SettingsState

        function onRequestChanged(): void {
            if (SettingsState.request)
                card.applyRequest();
        }
    }

    // Die gewaehlte Plugin-Gruppe verschwindet (Plugin aus oder entfernt):
    // zur Verwaltung. Nur, wenn sie vorher da war – beim Einlesen der
    // Plugins (die Hosts entstehen einzeln) fehlt sie sonst nur kurz.
    property bool sectionSeen: false

    onSectionChanged: card.sectionSeen = card.allSections.includes(card.section)
    onAllSectionsChanged: {
        if (card.allSections.includes(card.section)) {
            card.sectionSeen = true;
            return;
        }
        if (card.sectionSeen && Plugins.isPluginSection(card.section))
            card.section = card.managerKey;
    }

    function sectionTitle(s: string): string {
        const cat = card.categories.find(c => c.key === s);
        if (cat)
            return I18n.tr(cat.title);
        if (card.pageTitles[s])
            return I18n.tr(card.pageTitles[s]);
        if (s === card.managerKey)
            return "Plugins";
        if (s === card.colorsKey)
            return I18n.tr("Farben");
        if (s === card.wallsKey)
            return I18n.tr("Bibliothek");
        if (Plugins.isPageSection(s))
            return I18n.tr(Plugins.pageFor(s)?.title ?? s.slice(Plugins.pagePrefix.length));
        if (Plugins.isPluginSection(s))
            return I18n.tr(Plugins.sectionTitle(s));
        return I18n.tr(Config.sectionMeta[s] ?? s);
    }

    // Titel eines shell.json-Abschnitts (Ueberschriften) – Kategorien heissen
    // teils wie Abschnitte ("lock"), hier zaehlt der Abschnitt
    function partTitle(s: string): string {
        if (Config.sectionMeta[s])
            return I18n.tr(Config.sectionMeta[s]);
        return card.sectionTitle(s);
    }

    function valuesOf(s: string): var {
        return Plugins.isPluginSection(s) ? Plugins.raw[s] : Config.raw[s];
    }

    // Zeilen anderer Gruppen, die per meta.page auf Seite `s` stehen:
    // [{ section, key, value }]
    function movedInto(s: string): var {
        const out = [];
        for (const id in Config.meta) {
            if (Config.meta[id]?.page !== s)
                continue;
            const dot = id.indexOf(".");
            const section = id.slice(0, dot);
            const key = id.slice(dot + 1);
            const values = card.valuesOf(section);
            if (section !== s && values && values[key] !== undefined)
                out.push({ section, key, value: values[key] });
        }
        return out;
    }

    // keepArgs: die Argumente einer Seite stehen schon (applyRequest)
    // Ein shell.json-Abschnitt ("vpn") oeffnet seine Kategorie und scrollt hin
    function select(s: string, keepArgs: bool): void {
        if (!keepArgs)
            card.pageArgs = {};
        const cat = card.categories.some(c => c.key === s) ? "" : card.categoryOf(s);
        card.scrollTarget = cat !== "" ? s : "";
        card.section = cat !== "" ? cat : s;
        if (card.searching) {
            search.text = "";
            card.filter = "";
        }
        list.contentY = 0;
        Qt.callLater(card.scrollToTarget);
    }

    // Beim Oeffnen: Suche leeren, Suchfeld fokussieren
    function reset(): void {
        card.filter = "";
        search.text = "";
        search.forceActiveFocus();
    }

    // ---- Die Zeilen, gebaut aus der Datei ----
    readonly property var entries: {
        const needle = card.filter.trim().toLowerCase();
        const out = [];
        // shell.json kommt alphabetisch zurueck (QJsonObject sortiert beim
        // Schreiben) – die Reihenfolge im Menue gibt deshalb die meta-Tabelle
        // vor, Unbekanntes hinten. Plugin-Gruppen: Reihenfolge wie im
        // Manifest (Plugins.meta)
        const order = Object.keys(Config.meta).concat(Object.keys(Plugins.meta));
        const rank = id => {
            const i = order.indexOf(id);
            return i < 0 ? order.length : i;
        };

        const pages = needle === "" ? card.currentSections
                                    : card.allSections.concat(Object.keys(card.pageTitles));
        for (const section of pages) {


            // Zeilen dieser Seite: die eigenen Schluessel ohne die, die per
            // meta.page woanders stehen, plus die von anderswo hierher
            // geholten (gespeichert wird weiter unter ihrem eigenen Schluessel)
            const values = card.valuesOf(section) ?? {};
            const items = Object.keys(values)
                .filter(key => (Plugins.metaFor(`${section}.${key}`)?.page ?? section) === section)
                .map(key => ({ section, key, value: values[key] }))
                .concat(card.movedInto(section));
            const sorted = items.sort((a, b) =>
                rank(`${a.section}.${a.key}`) - rank(`${b.section}.${b.key}`) || a.key.localeCompare(b.key));
            // Zeilen einer Karte (meta.group) zusammenziehen, Karten in der
            // Reihenfolge ihrer ersten Zeile
            const groupOf = item => Plugins.metaFor(`${item.section}.${item.key}`)?.group ?? "";
            const groupOrder = [...new Set(sorted.map(groupOf))];
            const rows = sorted.map((item, i) => ({ item, i }))
                .sort((a, b) => groupOrder.indexOf(groupOf(a.item)) - groupOrder.indexOf(groupOf(b.item)) || a.i - b.i)
                .map(r => r.item);
            for (const row of rows) {
                const key = row.key;
                const id = `${row.section}.${key}`;
                const meta = Plugins.metaFor(id);
                // Schluessel, die woanders bedient werden (meta.hidden)
                if (meta?.hidden)
                    continue;
                const entry = {
                    id,
                    section: row.section,
                    // Seite, auf der die Zeile steht (meta.page), fuer die Karten
                    page: section,
                    key,
                    group: meta?.group ?? "",
                    value: row.value,
                    title: meta?.title ? I18n.tr(meta.title) : key,
                    // Ohne Eintrag in der Tabelle: ehrlich sagen,
                    // dass der Schluessel neu ist
                    desc: meta?.desc ? I18n.tr(meta.desc) : (meta ? "" : I18n.tr("Schlüssel \"%1\" aus shell.json").arg(key)),
                    options: card.liveOptions(meta)?.options ?? meta?.options ?? null,
                    labels: card.liveOptions(meta)?.labels ?? meta?.labels ?? null,
                    min: meta?.min,
                    max: meta?.max,
                    step: meta?.step,
                    unit: meta?.unit ?? "",
                    requires: meta?.requires ?? null,
                    editor: meta?.editor ?? "",
                    preview: meta?.preview ?? "",
                    sub: meta?.sub ?? ""
                };

                if (needle === ""
                    || entry.title.toLowerCase().includes(needle)
                    || entry.desc.toLowerCase().includes(needle)
                    || id.toLowerCase().includes(needle)
                    || card.sectionTitle(section).toLowerCase().includes(needle))
                    out.push(entry);
            }
            // Seiten des Plugins (Manifest `pages`) als Zeilen mit Pfeil in
            // seiner Gruppe – dort sucht man sie, nicht in der Leiste
            if (Plugins.isPluginSection(section)) {
                for (const p of Plugins.pages.filter(p => p.pluginId === Plugins.idOf(section))) {
                    const title = I18n.tr(p.title);
                    if (needle === "" || title.toLowerCase().includes(needle)
                        || card.sectionTitle(section).toLowerCase().includes(needle))
                        out.push({ id: `${section}.@${p.key}`, section, key: "@" + p.key, group: "", value: null,
                                   title, desc: "", options: null, labels: null, unit: "", requires: null,
                                   editor: "", preview: "", link: Plugins.pageSection(p.key) });
                }
            }
        }
        return out;
    }

    // Auswahlen, die erst zur Laufzeit feststehen (meta.source) – etwa
    // welche Akkus gerade verbunden sind
    function liveOptions(meta: var): var {
        switch (meta?.source ?? "") {
        case "batteries":
            return { options: Power.targetChoices, labels: Power.targetLabels };
        default:
            return null;
        }
    }

    // Die Gruppen: aufeinanderfolgende Zeilen mit gleicher Seite und
    // gleichem meta.group, rows als Indizes in card.entries (durch einen
    // Repeater gereichte Objekte verlieren ihre JS-Arrays – `options` kaeme
    // als Sequenz an, nicht als Array). Alles steht in einer Spalte wie bei
    // Caelestia; nur die Tastatur der Tastenkuerzel nimmt die ganze Breite.
    readonly property var fullEditors: ["keybinds"]
    // Editoren, die sich samt Containern selbst zeichnen (GroupCard.bare)
    readonly property var bareEditors: ["system", "monitors", "keybinds", "wallpaperhero", "account"]
    readonly property real columnWidth: Math.min(card.listRoom, 760)
    readonly property var groupCards: {
        const out = [];
        card.entries.forEach((e, i) => {
            const last = out[out.length - 1];
            const bare = card.bareEditors.includes(e.editor);
            // Ein Editor, der sich selbst zeichnet, steht immer fuer sich
            if (last && !bare && !last.bare && last.page === (e.page ?? e.section) && last.group === e.group) {
                last.rows.push(i);
            } else {
                out.push({ section: e.section, page: e.page ?? e.section, group: e.group, rows: [i], bare,
                           full: card.fullEditors.includes(e.editor) });
            }
        });
        return out;
    }

    // Nach openPage("vpn") zum Abschnitt scrollen, sobald die Gruppen stehen
    onGroupCardsChanged: Qt.callLater(card.scrollToTarget)

    function scrollToTarget(): void {
        if (card.scrollTarget === "")
            return;
        for (const g of cardColumn.children) {
            if (g.group?.page === card.scrollTarget) {
                list.contentY = Math.max(0, Math.min(g.y, list.contentHeight - list.height));
                card.scrollTarget = "";
                return;
            }
        }
    }

    // Rueckfrage "Alles zuruecksetzen" (Leiste unten) offen?
    property bool resetAsk: false

    // Beim Zeigen auf die Symbolspalte: der Knopf, dessen Name daneben steht
    property Item railItem: null

    maxRadius: 24
    // Das Fenster hat keinen Blur dahinter – deckend, egal wie transparent die Pillen sind
    baseColor: Colors.background

    // Kommt beim Oeffnen leicht herangewachsen
    scale: card.shown ? 1 : 0.96
    opacity: card.shown ? 1 : 0
    Morph on scale {}
    Fade on opacity {}

    // Escape schliesst – auch, wenn das Suchfeld den Fokus verloren hat
    Keys.onEscapePressed: SettingsState.close()

    // Zaehler der Bibliothek in der Leiste (die Liste ist sonst erst da,
    // wenn die Auswahl oder die Bibliothek einmal offen war)
    Component.onCompleted: {
        Wallpapers.ensureLoaded();
        card.applyRequest();
    }

    // ================= Linke Leiste =================
    Item {
        id: sidebar

        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
        }
        width: card.sidebarWidth
        clip: true

        Behavior on width {
            NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: card.radius
            bottomLeftRadius: card.radius
            color: Colors.alpha(Colors.fgSurface, 0.035)
        }

        // Trennlinie
        Rectangle {
            anchors {
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }
            width: 1
            color: Colors.alpha(Colors.outline, 0.25)
        }

        // Schmal: oben das Symbol des Fensters (die Suche steht dann im Kopf)
        Text {
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
                topMargin: 30
            }
            text: "settings"
            color: Colors.fgBackground
            font.family: "Material Symbols Outlined"
            font.pixelSize: 22
            visible: card.compact
        }

        // Die Kategorien – scrollbar, falls das Fenster sehr niedrig ist
        Flickable {
            id: sidebarFlick

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                // Breit steht hier oben die Suche (searchBox liegt in content)
                topMargin: 80
                bottomMargin: 12
            }
            clip: true
            contentHeight: sidebarColumn.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds
            interactive: false

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y / 120 : event.pixelDelta.y / 40;
                    const max = Math.max(0, sidebarFlick.contentHeight - sidebarFlick.height);
                    sidebarFlick.contentY = Math.max(0, Math.min(max, sidebarFlick.contentY - delta * 40));
                    event.accepted = true;
                }
            }

            Column {
                id: sidebarColumn

                anchors {
                    left: parent.left
                    right: parent.right
                    leftMargin: 10
                    rightMargin: 10
                }
                spacing: 2

                Repeater {
                    // Gruppen wie bei Caelestia: Eintraege einer Gruppe kleben
                    // aneinander (2 px), aussen stark, innen leicht gerundet
                    model: card.sidebarGroups

                    Column {
                        id: sideGroup

                        required property var modelData

                        width: parent?.width ?? 0
                        spacing: 2
                        bottomPadding: 12

                Repeater {
                    model: sideGroup.modelData

                    Rectangle {
                        id: button

                        required property string modelData
                        required property int index
                        readonly property var info: card.sidebarEntry(button.modelData)
                        readonly property bool first: button.index === 0
                        readonly property bool last: button.index === sideGroup.modelData.length - 1
                        readonly property string label: I18n.tr(button.info.title)
                        // Unterseiten markieren ihre Kategorie: Bibliothek →
                        // Darstellung, Plugin-Gruppen und -Seiten → Plugins
                        readonly property string owner: card.lookSub ? "look"
                            : card.managing || Plugins.isPluginSection(card.section) || Plugins.isPageSection(card.section) ? card.managerKey
                            : card.subParents[card.section] ?? card.section
                        readonly property bool current: (!card.searching || card.lookSub) && button.owner === button.modelData

                        width: parent?.width ?? 0
                        height: card.compact ? 46 : 54
                        topLeftRadius: button.first ? 20 : 6
                        topRightRadius: button.first ? 20 : 6
                        bottomLeftRadius: button.last ? 20 : 6
                        bottomRightRadius: button.last ? 20 : 6
                        color: button.current ? Colors.alpha(Colors.primary, 0.18)
                             : buttonHover.hovered ? Colors.alpha(Colors.fgSurface, 0.08)
                             : Colors.alpha(Colors.fgSurface, 0.04)

                        Behavior on color {
                            ColorAnimation { duration: Appearance.fadeDuration }
                        }

                        // Symbol im Kreis; die gewaehlte Kategorie in der Akzentfarbe
                        Rectangle {
                            id: buttonIcon

                            x: card.compact ? (parent.width - width) / 2 : 11
                            anchors.verticalCenter: parent.verticalCenter
                            width: 38
                            height: 38
                            radius: 19
                            color: button.current ? Colors.primary : Colors.alpha(Colors.fgSurface, 0.07)

                            Behavior on color {
                                ColorAnimation { duration: Appearance.fadeDuration }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: button.info.icon
                                color: button.current ? Colors.fgPrimary : Colors.fgSurface
                                font.family: "Material Symbols Outlined"
                                font.pixelSize: 20
                            }
                        }

                        Column {
                            anchors {
                                left: buttonIcon.right
                                leftMargin: 13
                                right: parent.right
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            visible: !card.compact
                            spacing: 1

                            Text {
                                width: parent.width
                                text: button.label
                                color: button.current ? Colors.fgBackground : Colors.fgSurface
                                font.family: Config.font
                                font.pixelSize: 13
                                font.weight: button.current ? Font.DemiBold : Font.Medium
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: I18n.tr(button.info.desc)
                                color: Colors.fgSurfaceVariant
                                font.family: Config.font
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        HoverHandler {
                            id: buttonHover

                            cursorShape: Qt.PointingHandCursor
                            onHoveredChanged: {
                                if (hovered)
                                    card.railItem = button;
                                else if (card.railItem === button)
                                    card.railItem = null;
                            }
                        }

                        TapHandler {
                            onTapped: card.select(button.modelData, false)
                        }
                    }
                }
                    }
                }
            }
        }

        // Weiche Kante unten, solange noch Eintraege folgen
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                rightMargin: 1
                bottom: sidebarFlick.bottom
            }
            height: 20
            visible: sidebarFlick.contentHeight - sidebarFlick.contentY - sidebarFlick.height > 2
            gradient: Gradient {
                GradientStop { position: 0; color: Colors.alpha(Colors.background, 0) }
                GradientStop { position: 1; color: Colors.mix(Colors.background, Colors.fgSurface, 0.035) }
            }
        }
    }

    // ================= Rechte Seite =================
    Item {
        id: content

        anchors {
            left: sidebar.right
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }

        // Kopf: Gruppentitel + Suche. Der Titel nimmt sich seine Breite,
        // laesst dem Suchfeld aber mindestens 150 px; das Feld waechst mit
        // dem Fenster bis 520 px und bleibt vor dem Schliessen-Knopf stehen.
        // Plugin-Seite: zurueck zur Gruppe ihres Plugins
        // Unterseiten: zurueck zu ihrer Kategorie bzw. zur Plugin-Gruppe
        readonly property string backSection: {
            if (card.searching && !card.lookSub)
                return "";
            if (card.lookSub)
                return "look";
            if (card.subParents[card.section])
                return card.subParents[card.section];
            if (card.paging && card.pageInfo !== null) {
                const s = Plugins.sectionPrefix + card.pageInfo.pluginId;
                return Plugins.sections.includes(s) ? s : card.managerKey;
            }
            return Plugins.isPluginSection(card.section) ? card.managerKey : "";
        }

        // Kopfzeile: Zurueck, Seitentitel, (schmal: Suche), ⋮, Schliessen
        Item {
            id: header

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 82
        }

        Item {
            id: backButton

            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: header.verticalCenter
            }
            width: content.backSection !== "" ? 30 : 0
            height: 30
            visible: width > 0

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: backHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12) : "transparent"
            }

            Text {
                anchors.centerIn: parent
                text: "arrow_back"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 18
            }

            HoverHandler {
                id: backHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: card.select(content.backSection, false)
            }
        }

        Text {
            id: heading
            font.family: Config.font

            anchors {
                left: backButton.visible ? backButton.right : parent.left
                leftMargin: backButton.visible ? 6 : 24
                verticalCenter: header.verticalCenter
            }
            width: Math.max(0, Math.min(heading.implicitWidth, moreButton.x - 10 - heading.x - (card.compact ? 12 + 150 : 0)))
            // In der Bibliothek steht "Bibliothek › Ordner" in der Seite selbst
            text: card.browsing ? "Wallpaper"
                : card.coloring ? I18n.tr("Farben")
                : card.searching ? I18n.tr("Suche")
                : card.section === "" ? I18n.tr("Alle")
                : card.sectionTitle(card.section)
            color: Colors.fgBackground
            font.pixelSize: 24
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Rectangle {
            id: searchBox

            // Breit oben in der Leiste (links ausserhalb von content – content
            // schneidet nicht ab), schmal im Kopf neben dem Titel
            x: card.compact ? heading.x + heading.width + 12 : -card.sidebarWidth + 14
            y: card.compact ? (header.height - height) / 2 : 18
            width: card.compact ? Math.max(0, Math.min(moreButton.x - 10 - x, 520)) : card.sidebarWidth - 28
            height: card.compact ? 38 : 46
            radius: height / 2
            color: Colors.alpha(Colors.fgSurface, search.activeFocus ? 0.09 : 0.06)
            border.width: 1
            border.color: search.activeFocus ? Colors.alpha(Colors.primary, 0.5) : "transparent"

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }
            Behavior on border.color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }

            Text {
                id: searchIcon

                anchors {
                    left: parent.left
                    leftMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                text: "search"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 17
            }

            TextInput {
                id: search
                font.family: Config.font

                anchors {
                    left: searchIcon.right
                    leftMargin: 10
                    right: clearSearch.left
                    rightMargin: 6
                    verticalCenter: parent.verticalCenter
                }
                onTextChanged: card.filter = text
                color: Colors.fgSurface
                font.pixelSize: 13
                selectionColor: Colors.alpha(Colors.primary, 0.35)
                clip: true

                Keys.onEscapePressed: {
                    if (search.text !== "")
                        search.text = "";
                    else
                        SettingsState.close();
                }

                Text {
                    anchors.fill: parent
                    visible: search.text === ""
                    text: card.browsing ? I18n.tr("Bild suchen…") : card.coloring ? I18n.tr("Schema suchen…") : I18n.tr("Einstellung suchen…")
                    color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
                    font: search.font
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            // Suchtext leeren
            Item {
                id: clearSearch

                anchors {
                    right: parent.right
                    rightMargin: 6
                    verticalCenter: parent.verticalCenter
                }
                width: search.text !== "" ? 26 : 0
                height: 26
                opacity: search.text !== "" ? 1 : 0
                visible: width > 0

                Behavior on width {
                    NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
                }
                Fade on opacity {}

                Text {
                    anchors.centerIn: parent
                    text: "close"
                    color: Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 15
                }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: search.text = ""
                }
            }
        }

        // Selten gebraucht: Datei oeffnen, alles zuruecksetzen (mit Rueckfrage)
        SettingsMenuButton {
            id: moreButton

            anchors {
                right: closeButton.left
                rightMargin: 4
                verticalCenter: header.verticalCenter
            }
            entries: [
                { text: I18n.tr("shell.json öffnen"), icon: "open_in_new", action: () => {
                    Quickshell.execDetached(["xdg-open", Config.path]);
                    SettingsState.close();
                } },
                { separator: true },
                { text: I18n.tr("Alles zurücksetzen…"), icon: "settings_backup_restore", danger: true, action: () => card.resetAsk = true }
            ]
        }

        Rectangle {
            id: closeButton

            anchors {
                right: parent.right
                rightMargin: 20
                verticalCenter: header.verticalCenter
            }
            width: 32
            height: 32
            radius: height / 2
            color: closeHover.hovered ? Colors.alpha(Colors.fgSurface, 0.12) : "transparent"

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }

            Text {
                anchors.centerIn: parent
                text: "close"
                color: Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 17
            }

            HoverHandler {
                id: closeHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: SettingsState.close()
            }
        }

        // ---- Plugin-Verwaltung statt der Liste ----
        // Linksbuendig unter dem Titel; die Seite stellt ihre Karten ab
        // ~850 px selbst in zwei Spalten
        Loader {
            id: manager

            anchors {
                left: parent.left
                top: header.bottom
                bottom: parent.bottom
                leftMargin: Math.max(22, (parent.width - card.columnWidth) / 2)
                topMargin: 12
                bottomMargin: 16
            }
            width: card.columnWidth
            active: card.managing
            visible: active

            sourceComponent: PluginManager {
                onOpenSection: s => card.select(s)
            }
        }

        // ---- Farbschemata statt der Liste ----
        Loader {
            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                bottom: parent.bottom
                leftMargin: 24
                rightMargin: 16
                topMargin: 12
                bottomMargin: 16
            }
            active: card.coloring
            visible: active

            sourceComponent: ColorsPage {
                filter: card.filter
            }
        }

        // ---- Wallpaper-Bibliothek statt der Liste ----
        Loader {
            id: walls

            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                bottom: parent.bottom
                leftMargin: 24
                rightMargin: 16
                topMargin: 12
                bottomMargin: 16
            }
            active: card.browsing
            visible: active

            sourceComponent: WallpaperManager {
                filter: card.filter
            }
        }

        // ---- Plugin-Seite statt der Liste ----
        // Geladen ueber die URL aus Plugins.pages (mit Ladezeitpunkt, siehe
        // PluginHost.url): ein Plugin-Reload gibt eine neue URL, die Seite
        // wird dann neu gebaut. Die Seite bekommt `plugin` (Kontext) beim
        // Entstehen und `args` auch danach (SettingsState.openPage).
        Loader {
            id: pageLoader

            readonly property string pageUrl: card.pageInfo?.url ?? ""
            // Zuletzt gesetzte URL – `source` kaeme aufgeloest (qs:/…) zurueck
            // und verglich sich nie gleich, jede Pruefung baute die Seite neu
            property string loadedUrl: ""

            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                bottom: parent.bottom
                leftMargin: 24
                rightMargin: 16
                topMargin: 12
                bottomMargin: 16
            }
            active: card.paging && card.pageInfo !== null
            visible: active

            function sync(): void {
                // Abgeschaltet: beim naechsten Mal frisch mit den dann
                // gueltigen Argumenten bauen (statt der gemerkten alten)
                if (!pageLoader.active)
                    pageLoader.loadedUrl = "";
                if (!pageLoader.active || pageLoader.pageUrl === "")
                    return;
                if (pageLoader.loadedUrl !== pageLoader.pageUrl) {
                    pageLoader.loadedUrl = pageLoader.pageUrl;
                    pageLoader.setSource(pageLoader.pageUrl, { plugin: card.pageInfo.plugin, args: card.pageArgs });
                } else if (pageLoader.item && "args" in pageLoader.item)
                    pageLoader.item.args = card.pageArgs;
            }

            onActiveChanged: pageLoader.sync()
            onPageUrlChanged: pageLoader.sync()
            onLoaded: {
                if (pageLoader.item && "args" in pageLoader.item)
                    pageLoader.item.args = card.pageArgs;
            }
            onStatusChanged: {
                if (pageLoader.status === Loader.Error)
                    console.warn(`settings: Seite ${card.section} laedt nicht: ${pageLoader.sourceComponent?.errorString() ?? pageLoader.pageUrl}`);
            }
        }

        Connections {
            target: card

            function onPageArgsChanged(): void {
                pageLoader.sync();
            }
        }

        // ---- Die Liste ----
        // Eine Spalte, mittig unter dem Kopf (Caelestia): je Gruppe eine
        // Ueberschrift und ein Container (GroupCard)
        Flickable {
            id: list

            anchors {
                left: parent.left
                right: parent.right
                top: header.bottom
                bottom: parent.bottom
                leftMargin: 24
                rightMargin: 20
                topMargin: 18
                bottomMargin: 16
            }
            visible: !card.managing && !card.lookSub && !card.paging
            clip: true
            contentWidth: width
            contentHeight: cardColumn.height + 24
            boundsBehavior: Flickable.StopAtBounds
            // Nicht per Ziehen scrollen: sonst klaut die Liste den
            // Drag-and-Drop-Editoren ihre Geste. Das Mausrad reicht.
            interactive: false

            // Inhalt kuerzer geworden (Filter): nicht ins Leere zeigen
            onContentHeightChanged: list.contentY = Math.max(0, Math.min(list.contentY, list.contentHeight - list.height))

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

                onWheel: event => {
                    const angle = event.angleDelta.y + event.angleDelta.x;
                    const pixels = event.pixelDelta.y + event.pixelDelta.x;
                    const delta = angle !== 0 ? angle / 120 : pixels / 40;

                    const max = Math.max(0, list.contentHeight - list.height);
                    list.contentY = Math.max(0, Math.min(max, list.contentY - delta * 60));
                    event.accepted = true;
                }
            }

            Column {
                id: cardColumn

                width: list.width
                spacing: 22

                Repeater {
                    // Anzahl statt Liste: gleich viele Gruppen bauen nichts neu
                    model: card.groupCards.length

                    GroupCard {
                        required property int index

                        // Waehrend des Filterns sind Indizes und Liste kurz auseinander
                        group: card.groupCards[index] ?? null
                        width: group?.full ? list.width : card.columnWidth
                        x: (list.width - width) / 2
                        entries: card.entries
                        titleOf: s => card.partTitle(s)
                        sectionLabel: card.searching ? card.partTitle(group?.page ?? group?.section ?? "") : ""
                        pageTitle: card.searching ? "" : card.sectionTitle(card.section)
                    }
                }
            }
        }

        // Weiche Kante unten, solange noch Zeilen folgen
        Rectangle {
            anchors {
                left: list.left
                right: list.right
                bottom: list.bottom
            }
            height: 24
            visible: list.visible && list.contentHeight - list.contentY - list.height > 2
            gradient: Gradient {
                GradientStop { position: 0; color: Colors.alpha(Colors.background, 0) }
                GradientStop { position: 1; color: Colors.background }
            }
        }

        Column {
            anchors.centerIn: list
            visible: list.visible && card.entries.length === 0
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "search_off"
                color: Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                font.family: "Material Symbols Outlined"
                font.pixelSize: 28
            }

            Text {
                font.family: Config.font
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("Nichts gefunden")
                color: Colors.fgSurfaceVariant
                font.pixelSize: 12
            }
        }

        // Rueckfrage zu "Alles zuruecksetzen" – betrifft shell.json; Plugin-
        // Werte setzt die Verwaltung je Plugin zurueck
        Rectangle {
            anchors {
                horizontalCenter: list.horizontalCenter
                bottom: parent.bottom
                bottomMargin: 18
            }
            width: resetRow.implicitWidth + 28
            height: 48
            radius: 14
            visible: card.resetAsk
            color: Colors.surfaceContainer
            border.width: 1
            border.color: Colors.alpha(Colors.error, 0.4)

            Row {
                id: resetRow

                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    rightPadding: 8
                    text: I18n.tr("Alle Einstellungen auf die Vorgaben zurücksetzen?")
                    color: Colors.fgSurface
                    font.family: Config.font
                    font.pixelSize: 12
                }

                Repeater {
                    model: [
                        { text: I18n.tr("Abbrechen"), danger: false },
                        { text: I18n.tr("Zurücksetzen"), danger: true }
                    ]

                    Rectangle {
                        id: askButton

                        required property var modelData

                        anchors.verticalCenter: parent.verticalCenter
                        width: askLabel.implicitWidth + 24
                        height: 30
                        radius: 8
                        color: askButton.modelData.danger ? Colors.alpha(Colors.error, askHover.hovered ? 0.3 : 0.2)
                                                          : Colors.alpha(Colors.fgSurface, askHover.hovered ? 0.12 : 0.06)

                        Text {
                            id: askLabel

                            anchors.centerIn: parent
                            text: askButton.modelData.text
                            color: askButton.modelData.danger ? Colors.error : Colors.fgSurface
                            font.family: Config.font
                            font.pixelSize: 12
                            font.weight: Font.Medium
                        }

                        HoverHandler {
                            id: askHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: {
                                if (askButton.modelData.danger)
                                    Config.resetAll();
                                card.resetAsk = false;
                            }
                        }
                    }
                }
            }
        }

        // Zaehler unten rechts
        Text {
            font.family: Config.font
            anchors {
                right: parent.right
                rightMargin: 24
                bottom: parent.bottom
                bottomMargin: 10
            }
            // In der Bibliothek steht die Trefferzahl in deren Kopfzeile
            text: card.searching && !card.lookSub ? I18n.tr("%1 Treffer").arg(card.entries.length) : ""
            color: Colors.alpha(Colors.fgSurfaceVariant, 0.7)
            font.pixelSize: 10
        }
    }

    // Name des Knopfs neben der Symbolspalte
    Rectangle {
        id: railHint

        readonly property Item target: card.compact ? card.railItem : null
        // Beim Ausblenden bleibt der letzte Name stehen, statt leer zu verblassen
        property string label: ""

        readonly property string current: railHint.target?.label ?? ""
        onCurrentChanged: {
            if (railHint.current !== "")
                railHint.label = railHint.current;
        }

        x: sidebar.width + 8
        y: railHint.target ? railHint.target.mapToItem(card, 0, railHint.target.height / 2).y - height / 2 : 0
        width: hintLabel.implicitWidth + 20
        height: 26
        radius: 8
        color: Colors.mix(Colors.background, Colors.fgSurface, 0.1)
        border.width: 1
        border.color: Colors.alpha(Colors.outline, 0.3)
        visible: opacity > 0
        opacity: railHint.current !== "" ? 1 : 0

        Fade on opacity {}

        Text {
            id: hintLabel

            anchors.centerIn: parent
            font.family: Config.font
            text: railHint.label
            color: Colors.fgSurface
            font.pixelSize: 11
        }
    }
}
