pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs
import qs.modules.services.config
import qs.modules.services.desktop

// Ein Widget auf dem Desktop: laedt den Typ (DesktopWidgets), setzt ihn auf
// seinen Mittelpunkt (x/y als Anteil des Bildschirms) und reicht Groesse,
// Farben, Optionen und `active` durch.
//
// Beim Bearbeiten: Rahmen, Ziehen mit Einrasten (Drittel, Mitte, Raender und
// an den anderen Widgets: Kante an Kante, Mitte an Mitte), Griffe an den
// Ecken = Groesse (gegenueberliegende Ecke bleibt stehen, rastet mit der
// Kante oder auf gleiche Breite/Hoehe eines anderen Widgets ein). Shift beim
// Ziehen = frei, ohne Einrasten. Gespeichert wird erst beim Loslassen.
// Ein auf einen Monitor festgelegtes Widget darf ueber dessen Rand ragen
// (halb links, halb rechts, die Naht rastet ein) oder ganz hinueberziehen;
// der Nachbar zeichnet den Rest (Scenes.live/extents). Ein "*"-Widget bleibt
// auf allen Monitoren an derselben relativen Stelle, auch beim Ziehen.
// Monitore duerfen beliebig viele, versetzt und verschieden gross sein.
//
// Vertrag fuer Widget-Komponenten (eingebaut wie aus Plugins):
//   property real unit      Grundeinheit in px (16 bei 1440p * size)
//   property bool active    false = Desktop verdeckt: nichts rechnen/animieren
//   property bool editing
//   property var opts       Optionen aus scenes.json (Vorgaben schon eingesetzt)
//   property color color, accent
//   property int fps        Obergrenze fuer eigene Animationen (Einstellung fps des Plugins desktop)
//   implicitWidth/Height    setzt das Widget selbst
Item {
    id: host

    property var widget: null
    property string screenName: ""
    property ShellScreen shellScreen: null
    property real unit: 16
    property bool active: true
    property bool editing: false
    // Optionsfeld des ausgewaehlten Widgets zeigen (nur auf einem Monitor)
    property bool showOptions: true
    property Item guideX
    // Maus liegt ueber Optionsfeld oder Leiste (DesktopScreen): Qt 6 reicht
    // einen Druck auch an die Handler darunterliegender Elemente weiter,
    // obwohl oben schon eine MouseArea ihn angenommen hat – ohne Sperre
    // waehlte ein Klick ins Optionsfeld das Widget darunter aus (das Feld
    // war weg) und der Bonsai darunter wuchs neu
    property bool blocked: false
    property Item guideY

    readonly property var info: DesktopWidgets.info(host.widget?.type ?? "")
    readonly property bool selected: host.editing && Scenes.selected === (host.widget?.id ?? "")
    // Nur auf einem Monitor ("Nur <name>") – darf auf einen anderen wechseln
    readonly property bool pinned: (host.widget?.monitor ?? "*") !== "*"

    // Waehrend des Ziehens lokale Werte, danach wieder die aus der Szene
    property bool dragging: dragger.active || host.resizing
    property real dragX: 0
    property real dragY: 0
    property real liveSize: 1

    // Groesse aendern: die Ecke gegenueber dem Griff (anchorX/Y) bleibt
    // stehen, resizeDx/Dy = Richtung der gezogenen Ecke (-1/1). Der
    // Mittelpunkt folgt der echten Breite, so sitzt die feste Ecke aufs Pixel
    property bool resizing: false
    property real anchorX: 0
    property real anchorY: 0
    property int resizeDx: 0
    property int resizeDy: 0
    // Beim Skalieren auf gleiche Breite/Hoehe eingerastet: { id, title, axis }
    property var sizeMatch: null

    // Festgelegt auf einen anderen Monitor, ragt aber hierher (halb links,
    // halb rechts): dessen Lage relativ zu diesem in px
    readonly property ShellScreen home: host.pinned ? (Scenes.homeOf(host.widget) ?? host.shellScreen) : host.shellScreen
    readonly property real originX: (host.home?.x ?? 0) - (host.shellScreen?.x ?? 0)
    readonly property real originY: (host.home?.y ?? 0) - (host.shellScreen?.y ?? 0)
    // Groesse wie auf dem eigenen Monitor (Grundeinheit haengt an dessen
    // Hoehe) – sonst passten die Haelften bei verschiedenen Aufloesungen nicht
    readonly property real homeScale: (host.home?.height ?? 1) / (host.shellScreen?.height ?? 1)
    // Wird gerade gezogen/skaliert, hier oder auf einem anderen Monitor (Scenes.live)
    readonly property var live: Scenes.live?.id === (host.widget?.id ?? "") ? Scenes.live : null

    readonly property real size: host.resizing ? host.liveSize : (host.live?.size ?? host.widget?.size ?? 1)
    // Festgelegt: global (ueber den Rand ragend), "*": auf jedem Monitor an
    // derselben relativen Stelle – auch der gezogene selbst, der springt
    // also auf dem Nachbarn an die gespiegelte Stelle hier
    readonly property real cx: host.resizing ? host.anchorX + host.resizeDx * host.width / 2
                             : dragger.active && host.pinned ? host.dragX
                             : host.live ? (host.pinned ? host.live.gx - (host.shellScreen?.x ?? 0) : host.live.rx * host.areaW)
                             : dragger.active ? host.dragX
                             : host.originX + (host.widget?.x ?? 0.5) * (host.home?.width ?? host.areaW)
    readonly property real cy: host.resizing ? host.anchorY + host.resizeDy * host.height / 2
                             : dragger.active && host.pinned ? host.dragY
                             : host.live ? (host.pinned ? host.live.gy - (host.shellScreen?.y ?? 0) : host.live.ry * host.areaH)
                             : dragger.active ? host.dragY
                             : host.originY + (host.widget?.y ?? 0.5) * (host.home?.height ?? host.areaH)

    // Ziehen/Skalieren hier: die Kopien auf den anderen Monitoren folgen
    function publish(): void {
        if (!(dragger.active || host.resizing) || !host.widget)
            return;
        const lx = dragger.active ? host.dragX : host.cx;
        const ly = dragger.active ? host.dragY : host.cy;
        const own = host.shellScreen;
        const gx = (own?.x ?? 0) + lx, gy = (own?.y ?? 0) + ly;
        // Monitor unter dem Mittelpunkt (zwischen Monitoren: dieser)
        const t = host.otherScreenAt(lx, ly) ?? own;
        const rel = (v, a, len) => Math.max(0, Math.min(1, (v - a) / len));
        Scenes.live = {
            id: host.widget.id,
            gx: gx,
            gy: gy,
            rx: t ? rel(gx, t.x, t.width) : rel(lx, 0, host.areaW),
            ry: t ? rel(gy, t.y, t.height) : rel(ly, 0, host.areaH),
            size: host.size
        };
    }
    onDragXChanged: host.publish()
    onDragYChanged: host.publish()
    onCxChanged: if (host.resizing) host.publish()
    onCyChanged: if (host.resizing) host.publish()
    onSizeChanged: if (host.resizing) host.publish()

    // Auf dem eigenen Monitor die Groesse melden – daran sieht der Nachbar,
    // ob das Widget zu ihm herueberragt (Scenes.widgetsFor)
    readonly property bool isHome: host.pinned && host.home?.name === host.screenName
    function report(): void {
        if (host.isHome)
            Scenes.setExtent(host.widget.id, host.width, host.height);
    }
    onWidthChanged: host.report()
    onHeightChanged: host.report()
    onIsHomeChanged: host.report()
    // Ein anderes Widget rastet gerade auf unsere Breite/Hoehe ein ("breite"/"hoehe")
    readonly property string matchedAxis: host.editing && host.widget && host.parent?.sizeMatch?.id === host.widget.id
                                          ? host.parent.sizeMatch.axis : ""

    readonly property var opts: Object.assign(DesktopWidgets.defaults(host.widget?.type ?? ""), host.widget?.opts ?? {})

    // Angedockte Widgets (z.B. Visualiser "unten") setzen `dock` und bekommen
    // die volle Breite (`areaWidth`); x/y aus der Szene gelten dann nicht
    readonly property string dock: loader.item?.dock ?? ""
    readonly property real areaW: host.parent?.width ?? 0
    readonly property real areaH: host.parent?.height ?? 0

    width: Math.max(host.editing ? 40 : 0, loader.item?.implicitWidth ?? 0)
    height: Math.max(host.editing ? 24 : 0, loader.item?.implicitHeight ?? 0)
    x: host.dock !== "" ? 0 : Math.round(host.cx - host.width / 2)
    y: host.dock === "unten" ? host.areaH - host.height
     : host.dock === "oben" ? 0
     : Math.round(host.cy - host.height / 2)
    visible: host.widget !== null && host.info !== null
    z: host.selected ? 3 : 1

    function select(): void {
        Scenes.selected = host.widget.id;
    }

    onSelectedChanged: if (host.selected && host.parent && host.parent.selectedHost !== undefined) host.parent.selectedHost = host

    Loader {
        id: loader

        anchors.centerIn: parent
        // Eigene Handler der Widgets ebenfalls – und beim Bearbeiten nur am
        // ausgewaehlten Widget, sonst reagierte ein Widget schon beim
        // Auswaehlen oder unter einem anderen
        enabled: !host.blocked && (!host.editing || host.selected)
        // Nur im Editor sichtbar (widget.hidden): dort blass
        opacity: host.editing && host.widget?.hidden ? 0.35 : 1
        active: host.info !== null
        source: host.info?.url ?? ""
        asynchronous: false

        onStatusChanged: {
            if (loader.status === Loader.Error)
                console.warn("Desktop: Widget", host.widget?.type, "laedt nicht:", host.info?.url);
        }
    }

    Binding {
        target: loader.item
        property: "unit"
        value: host.unit * host.homeScale * host.size
        when: loader.item !== null
    }
    Binding {
        target: loader.item
        property: "active"
        value: host.active
        when: loader.item !== null
    }
    Binding {
        target: loader.item
        property: "editing"
        value: host.editing
        when: loader.item !== null
    }
    Binding {
        target: loader.item
        property: "opts"
        value: host.opts
        when: loader.item !== null
    }
    Binding {
        target: loader.item
        property: "color"
        value: DesktopWidgets.color(host.opts.color ?? "hell", Colors.fgBackground)
        when: loader.item !== null
    }
    Binding {
        target: loader.item
        property: "accent"
        value: DesktopWidgets.color(host.opts.accent ?? "primary", Colors.primary)
        when: loader.item !== null
    }
    Binding {
        target: loader.item
        property: "fps"
        value: DesktopWidgets.settings.fps
        when: loader.item !== null && loader.item.fps !== undefined
    }
    Binding {
        target: loader.item
        property: "areaWidth"
        value: host.areaW
        when: loader.item !== null && loader.item.areaWidth !== undefined
    }
    // Plugin-Widgets kommen an ihr Plugin (Einstellungen, Ordner) ueber `plugin`
    Binding {
        target: loader.item
        property: "plugin"
        value: host.info?.plugin ?? null
        when: loader.item !== null && host.info?.plugin !== undefined && loader.item.plugin !== undefined
    }

    // ---- Bearbeiten ----

    // Auswahlrahmen (8 px um das Widget). Liegt das Optionsfeld buendig an
    // seiner linken Kante an, wird die Ecke dort eckig – Rahmen und Feld
    // lesen sich dann als eine Flaeche.
    readonly property real frame: 8

    Rectangle {
        id: frameRect

        anchors.fill: parent
        anchors.margins: -host.frame
        visible: host.editing
        radius: 12
        bottomLeftRadius: options.item && options.item.flushBelow ? 0 : 12
        topLeftRadius: options.item && options.item.flushAbove ? 0 : 12
        color: host.selected ? Colors.alpha(Colors.primary, 0.08)
             : host.matchedAxis !== "" ? Colors.alpha(Colors.primary, 0.05) : "transparent"
        border.width: host.selected || host.matchedAxis !== "" ? 2 : 1
        border.color: host.selected || host.matchedAxis !== "" ? Colors.primary
                    : Colors.alpha("#ffffff", hoverArea.hovered ? 0.6 : 0.3)

        // Typ als kleines Etikett oben links (nicht, wenn das Feld dort andockt)
        Rectangle {
            visible: (host.selected || hoverArea.hovered || host.matchedAxis !== "")
                     && !(options.item && options.item.flushAbove)
            x: 10
            y: -height / 2
            width: label.implicitWidth + 12
            height: 18
            radius: 9
            color: host.selected || host.matchedAxis !== "" ? Colors.primary : Colors.alpha("#000000", 0.6)

            Text {
                id: label

                readonly property string title: I18n.tr(host.info?.title ?? host.widget?.type ?? "")

                anchors.centerIn: parent
                // Beim Skalieren: Groesse in Prozent, eingerastet auch woran
                text: host.matchedAxis !== "" ? (host.matchedAxis === "breite" ? I18n.tr("%1 · gleiche Breite") : I18n.tr("%1 · gleiche Höhe")).arg(label.title)
                    : !host.resizing ? label.title
                    : `${label.title} · ${Math.round(host.liveSize * 100)} %`
                      + (host.sizeMatch ? (host.sizeMatch.axis === "breite" ? I18n.tr(" · Breite wie %1") : I18n.tr(" · Höhe wie %1")).arg(I18n.tr(host.sizeMatch.title)) : "")
                color: host.selected || host.matchedAxis !== "" ? Colors.fgPrimary : "#ffffff"
                font.family: Config.font
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }

    // Rahmen (host.frame) gehoert zum Widget: Hover, Antippen und Ziehen
    // greifen auch dort, nicht nur auf dem Widget selbst
    HoverHandler {
        id: hoverArea

        enabled: host.editing && !host.blocked
        margin: host.frame
        cursorShape: host.dock !== "" ? Qt.PointingHandCursor
                   : dragger.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }

    // Auswahl schon beim Druecken – das Optionsfeld ist sofort da
    TapHandler {
        id: tap

        enabled: host.editing && (!host.blocked || tap.pressed)
        margin: host.frame
        gesturePolicy: TapHandler.DragThreshold
        // Ueberlappen sich Widgets, bekommen alle den Druck – waehlen darf
        // sich nur das, das an der Stelle oben liegt (DesktopScreen.hostAt)
        onPressedChanged: {
            if (!tap.pressed)
                return;
            const p = host.mapToItem(host.parent, tap.point.position.x, tap.point.position.y);
            const top = typeof host.parent?.hostAt === "function" ? host.parent.hostAt(p.x, p.y) : host;
            if (top === null || top === host)
                host.select();
        }
    }

    // Optionsfeld: unter dem Rahmen, sonst darueber; linksbuendig mit dem
    // Rahmen, am Bildschirmrand eingefangen. Angedockte (volle Breite) mittig.
    Loader {
        id: options

        active: host.selected && host.showOptions && !host.dragging
        z: 10

        sourceComponent: WidgetOptions {
            id: pop

            widget: host.widget
            screenName: host.screenName

            readonly property real fx: host.x - host.frame
            readonly property real fy: host.y - host.frame
            readonly property real fw: host.width + host.frame * 2
            readonly property real fh: host.height + host.frame * 2
            readonly property bool fits: pop.fy + pop.fh + pop.height + 16 <= host.areaH

            // Angedockte Lage (am Rahmen, unten wenn Platz ist)
            readonly property real dockX: host.dock !== "" ? Math.round((host.areaW - pop.width) / 2)
                                        : Math.max(16, Math.min(host.areaW - pop.width - 16, pop.fx))
            function dockY(below: bool): real {
                return below ? pop.fy + pop.fh - 2 : pop.fy - pop.height + 2;
            }

            // Lage festhalten, solange das Widget ausgewaehlt bleibt: aendert
            // eine Option seine Groesse (Stil, Zeilen …), bliebe das Feld sonst
            // nicht unter der Maus, sondern sprang mit oder auf die andere
            // Seite. Neu angedockt wird nach dem Ziehen (das Feld entsteht dann
            // neu), wenn das Widget ins Feld waechst, sich weit entfernt oder
            // das Feld aus dem Bild ragt.
            property real heldX: NaN
            property real heldY: NaN
            property bool heldBelow: true
            readonly property bool holding: !isNaN(pop.heldY)
            readonly property bool below: pop.holding ? pop.heldBelow : pop.fits
            readonly property real sx: pop.holding ? pop.heldX : pop.dockX
            readonly property real sy: pop.holding ? pop.heldY : pop.dockY(pop.below)

            // Beim Neu-Andocken bleibt das Feld auf seiner Seite, solange es
            // dort noch Platz hat – sonst wechselte es bei jedem Wachsen
            property bool sideKnown: false

            function hold(): void {
                const fitsAbove = pop.fy - pop.height - 16 >= 0;
                pop.heldBelow = !pop.sideKnown ? pop.fits
                              : pop.heldBelow ? (pop.fits || !fitsAbove)
                              : (!fitsAbove && pop.fits);
                pop.sideKnown = true;
                pop.heldX = pop.dockX;
                pop.heldY = pop.dockY(pop.heldBelow);
            }
            function redock(): void {
                pop.heldX = NaN;
                pop.heldY = NaN;
                holdLater.restart();
            }

            // Statt Qt.callLater: ein Timer stirbt mit dem Feld (callLater
            // liefe nach dem Abwaehlen ins zerstoerte Objekt)
            Timer {
                id: holdLater

                interval: 0
                onTriggered: pop.hold()
            }
            Timer {
                id: redockLater

                interval: 0
                onTriggered: pop.redock()
            }

            readonly property bool misplaced: {
                if (!pop.holding)
                    return false;
                // Ueberlappt den Rahmen (4 px Toleranz fuer das Andocken)
                const overlap = pop.sx < pop.fx + pop.fw && pop.sx + pop.width > pop.fx
                                && pop.sy + 4 < pop.fy + pop.fh && pop.sy + pop.height - 4 > pop.fy;
                // Weit weg vom Rahmen
                const gap = pop.below ? pop.sy - (pop.fy + pop.fh) : pop.fy - (pop.sy + pop.height);
                const apart = gap > 80 || pop.sx > pop.fx + pop.fw - 40 || pop.sx + pop.width < pop.fx + 40;
                // Ragt aus dem Bild
                const outside = pop.sy < 8 || pop.sy + pop.height > host.areaH - 8;
                return overlap || (host.dock === "" && apart) || outside;
            }
            // Erst nach der Auswertung umsetzen: redock aendert, wovon
            // `misplaced` abhaengt (sonst Binding-Schleife)
            onMisplacedChanged: if (pop.misplaced) redockLater.restart()
            Component.onCompleted: holdLater.restart()
            Connections {
                target: host

                function onDockChanged(): void {
                    pop.redock();
                }
            }

            // Liegt das Feld buendig am Rahmen, verschmelzen die Ecken
            readonly property bool touching: Math.abs(pop.sy - pop.dockY(pop.below)) < 1
            readonly property bool aligned: host.dock === "" && pop.touching && Math.abs(pop.sx - pop.fx) < 1
            readonly property bool flushBelow: pop.aligned && pop.below
            readonly property bool flushAbove: pop.aligned && !pop.below

            width: implicitWidth
            height: implicitHeight
            // 2 px Ueberlappung: Rand von Rahmen und Feld fallen zusammen
            x: pop.sx - host.x
            y: pop.sy - host.y
            radius: 14
            // Angedockt (volle Breite): sitzt wie ein Reiter auf dem Rahmen
            topLeftRadius: pop.flushBelow || (host.dock !== "" && pop.touching && pop.below) ? 0 : 14
            topRightRadius: host.dock !== "" && pop.touching && pop.below ? 0 : 14
            bottomLeftRadius: pop.flushAbove || (host.dock !== "" && pop.touching && !pop.below) ? 0 : 14
            bottomRightRadius: host.dock !== "" && pop.touching && !pop.below ? 0 : 14
        }
    }

    // Gehoert ein Punkt (Koordinaten der Buehne) zu diesem Widget – Rahmen,
    // Groessen-Griff oder Optionsfeld? Dann ist ein Klick dort kein Klick ins
    // Leere (DesktopScreen hebt sonst die Auswahl auf)
    function owns(px: real, py: real): bool {
        if (!host.visible || !host.editing)
            return false;
        // Rahmen plus Platz fuer den Griff, der aussen an der Ecke sitzt
        const m = host.frame + (host.selected ? 16 : 0);
        if (px >= host.x - m && py >= host.y - m && px <= host.x + host.width + m && py <= host.y + host.height + m)
            return true;
        return host.optionsContain(px, py);
    }

    readonly property bool panelHovered: options.item?.hovered ?? false

    // Liegt ein Punkt (Koordinaten der Buehne) auf dem Optionsfeld?
    function optionsContain(px: real, py: real): bool {
        const it = options.item;
        if (!it)
            return false;
        const p = it.mapFromItem(host.parent, px, py);
        return p.x >= 0 && p.y >= 0 && p.x <= it.width && p.y <= it.height;
    }

    // ---- Einrasten ----

    // Fangbereich in px
    readonly property real snapRange: 12

    // Die anderen frei stehenden Widgets auf diesem Monitor
    function others(): var {
        const out = [];
        for (const c of host.parent?.children ?? [])
            if (c !== host && c.visible && typeof c.owns === "function" && c.widget && c.dock === "")
                out.push(c);
        return out;
    }

    // Linien einer Achse: Bildschirm (Mitte und Drittel fuer Mittelpunkte,
    // Rand mit Abstand fuer Kanten; senkrecht mehr wegen der Notch) und die
    // anderen Widgets (Kanten fuer Kanten, Mitte fuer Mitte).
    // { at, center } – center = nur fuer Mittelpunkte.
    // Kanten sind immer die des sichtbaren Rahmens (host.frame um das
    // Widget): daran richtet man aus, dort liegen die Hilfslinien, und
    // Kante an Kante laesst zwischen zwei Widgets den doppelten Rahmen frei
    function snapLines(vertical: bool): var {
        const total = vertical ? host.areaH : host.areaW;
        const margin = total * (vertical ? 0.07 : 0.035);
        const lines = [
            { at: total / 3, center: true },
            { at: total / 2, center: true },
            { at: total * 2 / 3, center: true },
            { at: margin, center: false },
            { at: total - margin, center: false }
        ];
        // Naht zu einem Nachbarmonitor: Mitte darauf = halb hier, halb dort.
        // Nur festgelegte – ein "*"-Widget ragt nie hinueber
        if (host.pinned) {
            if (host.touches(vertical, false))
                lines.push({ at: 0, center: true, seam: true });
            if (host.touches(vertical, true))
                lines.push({ at: total, center: true, seam: true });
        }
        for (const o of host.others()) {
            const a = vertical ? o.y : o.x;
            const len = vertical ? o.height : o.width;
            lines.push({ at: a - host.frame, center: false },
                       { at: a + len + host.frame, center: false },
                       { at: a + len / 2, center: true });
        }
        return lines;
    }

    // Verschieben: Mittelpunkt c (Laenge len ohne Rahmen) so, dass eine
    // Rahmenkante oder die Mitte auf der naechsten Linie liegt.
    // { v, line } – line -1 = frei
    function snapMove(c: real, len: real, lines: var): var {
        const half = len / 2 + host.frame;
        let best = { v: c, line: -1, d: host.snapRange };
        for (const l of lines)
            for (const part of l.center ? [0] : [-half, half]) {
                const v = l.at - part;
                const d = Math.abs(v - c);
                if (d < best.d)
                    best = { v: v, line: l.at, d: d };
            }
        return best;
    }

    // Skalieren: Groesse s so, dass die gezogene Rahmenkante auf einer
    // Linie liegt oder die Laenge gleich der eines anderen Widgets ist.
    // a = feste Inhaltsecke, dir = Richtung, k = px je Groesseneinheit.
    // { s, line, match, d } – d = Abstand in px
    function snapResize(s: real, a: real, dir: int, k: real, lines: var, lengths: var): var {
        let best = { s: s, line: -1, match: null, d: host.snapRange };
        const test = (ss, line, match) => {
            const d = Math.abs(ss - s) * k;
            if (ss > 0 && d < best.d)
                best = { s: ss, line: line, match: match, d: d };
        };
        for (const l of lines)
            if (!l.center)
                test((dir * (l.at - a) - host.frame) / k, l.at, null);
        for (const m of lengths)
            test(m.len / k, -1, m);
        return best;
    }

    // Wie weit die Maus seit dem Druck gewandert ist, in Fensterkoordinaten.
    // Nicht `translation`: die misst Qt im Element des Handlers, und das
    // wandert hier selbst mit (Einrasten, Groesse) – das schaukelte sich auf
    function moved(handler: var): point {
        const c = handler.centroid;
        return Qt.point(c.scenePosition.x - c.scenePressPosition.x, c.scenePosition.y - c.scenePressPosition.y);
    }

    // Shift gedrueckt: frei, ohne Einrasten
    function free(handler: var): bool {
        return (handler.centroid.modifiers & Qt.ShiftModifier) !== 0;
    }

    // Anderer Monitor unter dem Punkt (lokale Koordinaten), sonst null
    function otherScreenAt(lx: real, ly: real): var {
        const own = host.shellScreen;
        if (!own || (lx >= 0 && ly >= 0 && lx < host.areaW && ly < host.areaH))
            return null;
        const gx = own.x + lx, gy = own.y + ly;
        for (const s of Quickshell.screens)
            if (s.name !== own.name && gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height)
                return s;
        return null;
    }

    // Grenzt ein anderer Monitor an diese Kante (auch versetzt oder anders
    // gross)? vertical = obere/untere Kante, far = rechte/untere
    function touches(vertical: bool, far: bool): bool {
        const o = host.shellScreen;
        if (!o)
            return false;
        for (const s of Quickshell.screens) {
            if (s.name === o.name)
                continue;
            if (vertical ? (far ? s.y === o.y + o.height : s.y + s.height === o.y) && s.x < o.x + o.width && s.x + s.width > o.x
                         : (far ? s.x === o.x + o.width : s.x + s.width === o.x) && s.y < o.y + o.height && s.y + s.height > o.y)
                return true;
        }
        return false;
    }

    // Wohin ein losgelassenes Widget gehoert (Mittelpunkt lx/ly lokal): Anteil
    // des Monitors unter dem Mittelpunkt (zwischen Monitoren: dieser). Ein
    // festgelegtes zieht dabei auf diesen Monitor um (`monitor`), ein "*"-
    // Widget bleibt auf allen
    function placement(lx: real, ly: real): var {
        const clamp = v => Number(Math.max(0, Math.min(1, v)).toFixed(4));
        const own = host.shellScreen;
        if (!own)
            return { x: clamp(lx / host.areaW), y: clamp(ly / host.areaH) };
        const t = host.otherScreenAt(lx, ly) ?? own;
        const gx = own.x + lx, gy = own.y + ly;
        const out = { x: clamp((gx - t.x) / t.width), y: clamp((gy - t.y) / t.height) };
        if (host.pinned)
            out.monitor = t.name;
        return out;
    }

    // Aenderung nach dem Loslassen speichern. Zieht das Widget von diesem
    // Monitor weg, verschwindet der Host dabei – dann erst nach dem Handler
    function commit(changes: var): void {
        if (changes.monitor !== undefined && changes.monitor !== host.screenName) {
            const id = host.widget.id;
            Qt.callLater(() => {
                Scenes.patch(id, changes);
                Scenes.live = null;
            });
            return;
        }
        Scenes.patch(host.widget.id, changes);
        Scenes.live = null;
    }

    DragHandler {
        id: dragger

        // Ein laufendes Ziehen nicht abbrechen, wenn es ueber die Leiste geht
        enabled: host.editing && host.dock === "" && (dragger.active || (!host.blocked && !host.resizing))
        margin: host.frame
        target: null
        dragThreshold: 4

        property real startX: 0
        property real startY: 0
        // Linien beim Start einmal sammeln – waehrend des Ziehens aendern sie sich nicht
        property var linesX: []
        property var linesY: []

        onActiveChanged: {
            if (dragger.active) {
                Scenes.selected = host.widget.id;
                dragger.startX = host.cx;
                dragger.startY = host.cy;
                dragger.linesX = host.snapLines(false);
                dragger.linesY = host.snapLines(true);
                host.dragX = host.cx;
                host.dragY = host.cy;
                return;
            }
            host.guideX.at = -1;
            host.guideY.at = -1;
            // Leiste und Optionsfeld wandern mit auf den Monitor, auf dem es landet
            const landed = host.otherScreenAt(host.dragX, host.dragY);
            if (landed)
                Scenes.editScreen = landed.name;
            host.commit(host.placement(host.dragX, host.dragY));
        }

        onCentroidChanged: {
            if (!dragger.active)
                return;
            const m = host.moved(dragger);
            const nx = dragger.startX + m.x;
            const ny = dragger.startY + m.y;
            const other = host.otherScreenAt(nx, ny);
            const free = host.free(dragger);
            if (other && !host.pinned) {
                // "*"-Widget mit dem Mittelpunkt auf einem anderen Monitor: es
                // steht hier an der gespiegelten Stelle – dort einrasten
                const own = host.shellScreen;
                const kx = host.areaW / other.width, ky = host.areaH / other.height;
                const wx = (own.x + nx - other.x) * kx, wy = (own.y + ny - other.y) * ky;
                const mx = free ? { v: wx, line: -1 } : host.snapMove(wx, host.width, dragger.linesX);
                const my = free ? { v: wy, line: -1 } : host.snapMove(wy, host.height, dragger.linesY);
                host.dragX = other.x - own.x + mx.v / kx;
                host.dragY = other.y - own.y + my.v / ky;
                host.guideX.at = mx.line;
                host.guideY.at = my.line;
                return;
            }
            // Festgelegt und schon auf dem Nachbarmonitor: dort rastet nur die
            // Naht ein (dessen Linien kennt dieser Host nicht). Der Rest wird
            // hier am Rand abgeschnitten und dort gezeichnet (Scenes.live)
            const linesX = other ? dragger.linesX.filter(l => l.seam) : dragger.linesX;
            const linesY = other ? dragger.linesY.filter(l => l.seam) : dragger.linesY;
            const sx = free ? { v: nx, line: -1 } : host.snapMove(nx, host.width, linesX);
            const sy = free ? { v: ny, line: -1 } : host.snapMove(ny, host.height, linesY);
            host.dragX = sx.v;
            host.dragY = sy.v;
            host.guideX.at = sx.line;
            host.guideY.at = sy.line;
        }
    }

    // Groesse: Griffe an den vier Ecken – ueber dem angedockten Optionsfeld
    // (z 10), sonst deckt dessen Kante den Griff halb zu. Angedockte Widgets
    // (volle Breite) haben nur einen Griff, dort zaehlt nur die Hoehe.
    Repeater {
        model: host.dock !== "" ? [{ dx: 1, dy: host.dock === "unten" ? -1 : 1 }]
                                : [{ dx: -1, dy: -1 }, { dx: 1, dy: -1 }, { dx: -1, dy: 1 }, { dx: 1, dy: 1 }]

        Rectangle {
            id: grip

            required property var modelData
            readonly property int dx: grip.modelData.dx
            readonly property int dy: grip.modelData.dy

            visible: host.selected
            z: 11
            x: (host.dock !== "" ? host.width - 40 : grip.dx < 0 ? -host.frame : host.width + host.frame) - width / 2
            y: (grip.dy < 0 ? -host.frame : host.height + host.frame) - height / 2
            width: 16
            height: 16
            radius: 8
            color: Colors.primary
            border.width: 2
            border.color: Colors.fgPrimary

            HoverHandler {
                cursorShape: host.dock !== "" ? Qt.SizeVerCursor
                           : grip.dx === grip.dy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
            }

            DragHandler {
                id: sizer

                target: null
                dragThreshold: 1
                // Der Griff gewinnt gegen alles darunter (Widget-Ziehen, Optionsfeld)
                grabPermissions: PointerHandler.CanTakeOverFromAnything

                property real startSize: 1
                property real startW: 1
                property real startH: 1
                property var linesX: []
                property var linesY: []
                property var widths: []
                property var heights: []

                onActiveChanged: {
                    if (sizer.active) {
                        sizer.startSize = host.widget?.size ?? 1;
                        sizer.startW = Math.max(20, host.width);
                        sizer.startH = Math.max(20, host.height);
                        sizer.linesX = host.snapLines(false);
                        sizer.linesY = host.snapLines(true);
                        const others = host.others();
                        const entry = (o, len, axis) => ({ len: len, id: o.widget.id, title: o.info?.title ?? o.widget.type, axis: axis });
                        sizer.widths = others.map(o => entry(o, o.width, "breite"));
                        sizer.heights = others.map(o => entry(o, o.height, "hoehe"));
                        host.anchorX = host.cx - grip.dx * host.width / 2;
                        host.anchorY = host.cy - grip.dy * host.height / 2;
                        host.resizeDx = host.dock !== "" ? 0 : grip.dx;
                        host.resizeDy = host.dock !== "" ? 0 : grip.dy;
                        host.liveSize = sizer.startSize;
                        host.resizing = true;
                        return;
                    }
                    host.resizing = false;
                    host.sizeMatch = null;
                    if (host.parent)
                        host.parent.sizeMatch = null;
                    host.guideX.at = -1;
                    host.guideY.at = -1;
                    // Frei stehend: der Mittelpunkt ist mitgewandert
                    const patch = host.dock === "" && host.parent ? host.placement(host.cx, host.cy) : {};
                    patch.size = Number(host.liveSize.toFixed(3));
                    host.commit(patch);
                }

                onCentroidChanged: {
                    if (!sizer.active)
                        return;
                    const m = host.moved(sizer);
                    // Angedockt: nur die Hoehe (unten angedockt waechst nach oben)
                    if (host.dock !== "") {
                        const r = (sizer.startH + grip.dy * m.y) / sizer.startH;
                        host.liveSize = Math.max(0.3, Math.min(8, sizer.startSize * r));
                        return;
                    }
                    // px je Groesseneinheit, beim Start gemessen. NICHT bei
                    // jeder Bewegung neu: Column & Co. rechnen ihre Groesse
                    // erst beim naechsten Frame, eine schnelle Maus schickt
                    // mehrere Ereignisse je Frame – alte Breite / neue Groesse
                    // schaukelte sich auf (Uhr sprang zwischen winzig und riesig)
                    const kw = sizer.startW / sizer.startSize;
                    const kh = sizer.startH / sizer.startSize;
                    // Groesse, bei der die Rahmenkante je Achse unter der Maus
                    // laege (a waagerecht, b senkrecht). Das Seitenverhaeltnis
                    // ist fest, also zaehlt die Achse, auf der die Maus weiter
                    // gewandert ist – gewichtet mit der 4. Potenz der Pixel:
                    // zieht man ungefaehr waagerecht, klebt die Kante an der
                    // Maus und etwas Drift nach oben/unten stoert nicht; schraeg
                    // wird stufenlos gemischt, nie gesprungen. (Gemittelt bzw.
                    // gegenlaeufig addiert liess wenig Drift viel kosten.)
                    const s0 = sizer.startSize;
                    const a = (sizer.startW + grip.dx * m.x) / kw - s0;
                    const b = (sizer.startH + grip.dy * m.y) / kh - s0;
                    const wa = Math.pow(m.x, 4), wb = Math.pow(m.y, 4);
                    let s = s0 + (wa + wb > 0 ? (a * wa + b * wb) / (wa + wb) : 0);
                    let lineX = -1, lineY = -1, match = null;
                    if (!host.free(sizer)) {
                        const sx = host.snapResize(s, host.anchorX, grip.dx, kw, sizer.linesX, sizer.widths);
                        const sy = host.snapResize(s, host.anchorY, grip.dy, kh, sizer.linesY, sizer.heights);
                        const best = sx.d <= sy.d ? sx : sy;
                        if (best.d < host.snapRange) {
                            s = best.s;
                            match = best.match;
                            if (best === sx)
                                lineX = best.line;
                            else
                                lineY = best.line;
                        }
                    }
                    host.liveSize = Math.max(0.3, Math.min(8, s));
                    host.sizeMatch = match;
                    if (host.parent)
                        host.parent.sizeMatch = match;
                    host.guideX.at = lineX;
                    host.guideY.at = lineY;
                }
            }
        }
    }
}
