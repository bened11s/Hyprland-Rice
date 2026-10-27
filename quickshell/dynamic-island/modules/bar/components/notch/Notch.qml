pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell

import qs.modules.services.config
import qs.modules.services.auth
import qs.modules.services.record
import qs.modules.services.system
import qs.modules.services.media
import qs.modules.services.notifications

import qs
import qs.modules.launcher
import qs.modules.widgets
// Fuer den Ring um die Uhr – derselbe, der an der Settings-Pille haengt
import qs.modules.bar.components.settings

// Notch mit Uhr: Karte, Hover-Logik und Auf-/Zuklapp-Animation. Den Inhalt des
// ausgeklappten Teils bringt DatePanel komplett selbst mit (Datum, Gesten,
// eigene Einrückung) – hier steht nur, wie groß die Karte dafür wird.
// Es bleibt ein einziges Rechteck, deshalb gibt es keine Naht. Damit die Karte
// unter die Leiste ragen kann, ist das Bar-Fenster höher (siehe Bar.qml).
Item {
    id: notch

    required property real verticalMargin // margin über bzw unter der notch
    required property real borderWidth   // von außen überschreibbar (Bar.qml macht das)
    required property color borderColor
    required property real cardRadius

    readonly property bool containsMouse: hoverSensor.hovered
    readonly property alias clock: clock

    // Notch-Layout: die Karte haengt an der Oberkante (oben eckig, der Rand
    // liegt knapp ausserhalb des Bildschirms) und ist das einzige Element
    // der Leiste – Bar.qml blendet die anderen Pillen aus. Etwas hoeher und
    // breiter als die Insel, damit sie als Notch liest und nicht als Pille.
    readonly property bool docked: Config.appearance.layout === "notch"

    // ---- Angedockte Notch (saneAspect-Vorbild) ----
    // Schwarz wie der Displayrahmen, ohne Rand, mit gewoelbten Schultern an
    // der Oberkante (NotchShoulder links und rechts AUSSERHALB der Breite).
    // Eingeklappt ist sie eine breite, flache Leiste: links die Workspaces,
    // mittig die Uhr, rechts Datum und Hinweise. Beide Seiten sind gleich
    // breit (compactSide), damit die Uhr immer in der Mitte steht.
    readonly property real shoulder: open ? Appearance.notchShoulderOpen : Appearance.notchShoulder
    // Unter dem Zeiger waechst sie ein Stueck nach unten und zur Seite
    readonly property bool hoverGrow: docked && hoverSensor.hovered && !open
    readonly property real growth: hoverGrow ? Appearance.notchHoverLift : 0
    readonly property real compactEdge: 14   // Kante -> erstes Element
    readonly property real compactGap: 14    // Element -> Uhr
    readonly property real compactMinWidth: 196
    readonly property bool showWorkspaces: docked && Config.notch.workspaces
    readonly property real compactLeft: showMedia ? mediaArtSize - (compactEdge - mediaEdge)
                                      : showWorkspaces ? compactWorkspaces.implicitWidth
                                      : 0
    readonly property real compactSide: Math.max(compactLeft, compactRight.implicitWidth)
    // Hoehe des oberen Bands (eingeklappt plus Hover-Wachstum): Uhr und
    // Seitenelemente bleiben darin mittig
    readonly property real bandHeight: collapsedHeight + growth

    // ---- Aufgeklappt: Uebersicht + Untermenues (Notch-Layout) ----
    // Beim Hover zeigt die Notch nur das Wichtigste (Uebersicht): Uhr mit
    // Glocke, Datum, "Jetzt laeuft" und kurze Systemwerte. Alles Weitere sind
    // Untermenues – Launcher-Modi wie Apps oder Power (LauncherState.views):
    // Medien, Steuerung, Benachrichtigungen, System. Aufruf per Tastenkuerzel
    // (simple.lua), Launcher-Befehl (`>medien` ...) oder Blaettern mit dem
    // Mausrad bzw. Wischen; der Seiten-Indikator unten zeigt die Position.
    readonly property bool cardShown: expanded && !launcherOpen && !authOpen
    readonly property bool overviewShown: docked && cardShown
    readonly property real overviewInset: 14
    // Alle Blaetter-Seiten (Uebersicht + Untermenues) sind gleich breit:
    // die Steuerung (Settings-Karte 520) plus Rand. So verschiebt sich beim
    // Blaettern seitlich nichts, nur die Hoehe aendert sich nach unten.
    readonly property real pageWidth: 548
    readonly property real panelBottom: collapsedHeight + clockDropMax + panel.outerHeight
    readonly property bool showNowPlaying: Media.available
    readonly property real overviewBottom: systemGlance.y + systemGlance.height
    // Seiten-Indikator: Punkte fuer Uebersicht + Untermenues
    readonly property bool pagerShown: docked && (overviewShown || viewOpen)
    // Mitte der Kopfzeile: Uhr (Uebersicht) bzw. Titel (Untermenue) stehen
    // beide auf dieser Hoehe, die Punkte links daneben
    readonly property real headerCenter: collapsedHeight / 2 + clockDropMax
    // Blaetter-Zone: die Kopfzeile. Die Karte haengt oben am Bildschirmrand,
    // deshalb bleibt dieser Streifen fest, egal wie hoch die Seiten sind.
    readonly property real flipZoneHeight: collapsedHeight + clockDropMax

    // Blaettern: Inhalt gleitet in Scrollrichtung herein (siehe flipWheel)
    property real slide: 0
    // Song-Wechsel per Wischen: die Jetzt-laeuft-Karte folgt dem Zeiger 1:1,
    // daneben kommt eine zweite Karte mit dem naechsten/vorigen Titel
    // (NowPlayingRow, Queue aus MediaQueue) mit herein. songPull =
    // Fortschritt bis zur Schwelle, -1..1 (negativ = nach links = naechster
    // Titel), aus songSlide abgeleitet, damit Zurueckschnappen und Einblenden
    // dieselbe Animation nutzen.
    property real songSlide: 0
    readonly property real songPull: Math.max(-1, Math.min(1, songSlide / swipe.threshold))

    // Eine Seite weiter (dir = +1) oder zurueck (-1) – Mausrad und Wischen
    // landen beide hier. Die neue Seite gleitet aus der Zugrichtung herein.
    function flip(dir: int): void {
        const before = LauncherState.viewIndex;
        const view = LauncherState.step(notch.QsWindow.window.screen, dir);
        if (view === "overview")
            notch.expanded = true;
        if (LauncherState.viewIndex !== before || view === "overview" && before !== 0) {
            slideIn.from = dir * 36;
            slideIn.restart();
        } else {
            // Nichts passiert (z.B. nur eine Seite): zurueckschnappen
            slideIn.from = notch.slide;
            slideIn.restart();
        }
    }

    // Song vor (dir = +1) oder zurueck (-1). Die zweite Karte faehrt ganz
    // herein (songFlip), der Player wechselt derweil; am Ende springt der
    // Versatz auf 0 und die echte Karte zeigt den neuen Titel an derselben
    // Stelle (NowPlayingRow.commit friert dafuer alten und neuen Titel ein,
    // bis MPRIS nachgezogen hat). Geht es nicht, schnappt die Karte nur zurueck.
    function skipSong(dir: int): void {
        const can = dir > 0 ? Media.canNext : Media.canPrevious;
        if (can) {
            nowPlaying.commit();
            if (dir > 0) {
                Media.next();
            } else {
                // Spotifys "Zurueck" startet den laufenden Titel neu, wenn er
                // schon ein paar Sekunden laeuft – erst an den Anfang, dann
                // springt es wirklich zum vorigen (wie im Medien-Untermenue)
                Media.seek(0);
                Media.previous();
            }
            songFlip.to = -dir * nowPlaying.flipDistance;
            songFlip.restart();
        } else {
            songSlideIn.from = notch.songSlide;
            songSlideIn.restart();
        }
    }

    // Direkt auf eine Seite springen (Klick auf einen Seiten-Punkt). Gleitet
    // aus der Richtung herein, in der die Seite im Pager liegt.
    function showView(index: int): void {
        const before = LauncherState.viewIndex;
        if (index === before)
            return;
        const view = LauncherState.views[index];
        if (view === "overview") {
            LauncherState.close();
            notch.expanded = true;
        } else {
            LauncherState.showMode(notch.QsWindow.window.screen, view);
        }
        slideIn.from = (index > before ? 1 : -1) * 36;
        slideIn.restart();
    }

    // Was die Bar zentral einschaltet (Bar.qml): Visualiser, Systemwerte,
    // Medien-Position, Tastaturfokus fuers WLAN-Passwort in der Steuerung
    readonly property bool wantsVisualizer: (overviewShown && Media.available) || mediaOpen
    readonly property bool wantsStats: overviewShown || systemOpen
    readonly property bool wantsMediaPosition: mediaOpen
    readonly property bool controlTyping: controlOpen && (controlView?.typing ?? false)
    // Steuerungs-Untermenue (nur gebaut, solange offen – sonst null)
    readonly property Item controlView: controlLoader.item

    // Kopfzeile der aufgeklappten Karte: runde Knoepfe links und rechts der Uhr
    // (nur Insel-Layout; angedockt steht dort nur die Glocke)
    readonly property real headerButtonSize: 30
    readonly property real headerInset: docked ? 12 : 8
    readonly property real headerSpacing: 6

    // Datums-Ansicht (per Hover) und Launcher (per Zug nach unten) teilen sich
    // dieselbe Karte – der Launcher hat Vorrang.
    property bool expanded: false
    readonly property var hostScreen: notch.QsWindow.window?.screen ?? null
    readonly property bool launcherOpen: LauncherState.open && LauncherState.screen === hostScreen
    // Die Karte hat im Launcher-Modus drei Ansichten (siehe LauncherState.mode)
    readonly property bool wallpaperOpen: launcherOpen && LauncherState.mode === "wallpaper"
    readonly property bool themeOpen: launcherOpen && LauncherState.mode === "theme"
    readonly property bool powerOpen: launcherOpen && LauncherState.mode === "power"
    readonly property bool keysOpen: launcherOpen && LauncherState.mode === "keys"
    readonly property bool clipboardOpen: launcherOpen && LauncherState.mode === "clipboard"
    // Untermenues (siehe oben)
    readonly property bool mediaOpen: launcherOpen && LauncherState.mode === "media"
    readonly property bool controlOpen: launcherOpen && LauncherState.mode === "control"
    readonly property bool notificationsOpen: launcherOpen && LauncherState.mode === "notifications"
    readonly property bool systemOpen: launcherOpen && LauncherState.mode === "system"
    readonly property bool viewOpen: mediaOpen || controlOpen || notificationsOpen || systemOpen
    // Direkt am Modus, nicht als "keine der anderen": die abgeleiteten
    // Flags oben werden nach `launcherOpen` neu ausgewertet, waren also kurz
    // noch false – dann war appsOpen fuer einen Moment wahr und jedes andere
    // Menue baute beim Oeffnen den App-Launcher mit (~25 ms) und warf ihn weg.
    readonly property bool appsOpen: launcherOpen && LauncherState.mode === "apps"
    readonly property bool authOpen: Auth.active && Auth.screen === hostScreen
    readonly property bool open: expanded || launcherOpen || authOpen

    // Die Uhr rutscht beim Aufklappen etwas nach unten
    readonly property real clockDropMax: 7
    readonly property real clockDrop: open ? clockDropMax : 0

    // Roter Punkt neben der Uhr, solange eine Bildschirmaufnahme läuft.
    // Solange er da ist, wird die Pille um genau seinen Platz breiter und die
    // Uhr rückt um die Hälfte davon nach links – so steht das Paar aus Uhr
    // und Punkt weiterhin mittig in der Pille.
    readonly property bool recording: Recorder.active
    readonly property real recordDotSize: 8
    readonly property real recordGap: 7
    // Angedockt sitzt der Punkt in der rechten Gruppe (compactRight)
    readonly property real recordReserve: recording && !docked ? recordDotSize + recordGap : 0

    // Live-Activity: laeuft Musik, zeigt die Insel links das Cover und rechts
    // drei Pegelbalken – die Dynamic-Island-Idee. Beides weicht, sobald die
    // Karte aufklappt, dort sitzen dann die Knoepfe. Die Pille wird dafuer
    // auf beiden Seiten gleich breiter, die Uhr bleibt also mittig.
    readonly property bool showMedia: docked && Config.notch.media && Media.playing
    // Pegel rechts – eigene Einstellung, unabhaengig vom Cover
    readonly property bool showVisualizer: docked && Config.notch.visualizer && Media.playing
    readonly property real mediaArtSize: 20
    readonly property real mediaEdge: 8

    // Nachrichten-Zaehler rechts neben der Uhr (nur Notch-Layout, schaltbar)
    readonly property bool showMessages: docked && Config.notch.messages && Notifications.count > 0
    readonly property real messageBadgeSize: 16
    // Im Launcher-Modus ist die Uhr ausgeblendet, das Panel beginnt oben
    readonly property real launcherTop: 10

    // Maße: eingeklappt exakt wie vorher, ausgeklappt wächst die Karte nach
    // unten und mittig etwas in die Breite.
    // Angedockt: 1 px hoeher, weil der obere Rand ausserhalb liegt (y < 0)
    readonly property real collapsedHeight: docked ? parent.height - 8 : parent.height - verticalMargin
    readonly property real collapsedWidth: docked
        ? Math.max(compactMinWidth, clock.implicitWidth + 2 * (compactSide + compactGap + compactEdge))
        : clock.implicitWidth + 50 + recordReserve
    readonly property real launcherWidth: wallpaperOpen ? wallpapers.outerWidth
                                        : themeOpen ? themes.outerWidth
                                        : powerOpen ? powerMenu.outerWidth
                                        : keysOpen ? keysView.outerWidth
                                        : clipboardOpen ? clipboardView.outerWidth
                                        : mediaOpen ? mediaView.outerWidth
                                        : controlOpen ? controlLoader.outerWidth
                                        : notificationsOpen ? notificationsView.outerWidth
                                        : systemOpen ? systemView.outerWidth
                                        : launcher.outerWidth
    readonly property real launcherHeight: wallpaperOpen ? wallpapers.outerHeight
                                         : themeOpen ? themes.outerHeight
                                         : powerOpen ? powerMenu.outerHeight
                                         : keysOpen ? keysView.outerHeight
                                         : clipboardOpen ? clipboardView.outerHeight
                                         : mediaOpen ? mediaView.outerHeight
                                         : controlOpen ? controlLoader.outerHeight
                                         : notificationsOpen ? notificationsView.outerHeight
                                         : systemOpen ? systemView.outerHeight
                                         : launcher.outerHeight

    readonly property real expandedWidth: authOpen ? Math.max(collapsedWidth, authPanel.outerWidth)
                                                   : launcherOpen ? (docked && viewOpen ? pageWidth
                                                                                        : Math.max(collapsedWidth, launcherWidth))
                                                   : docked ? pageWidth
                                                            : Math.max(collapsedWidth, panel.outerWidth)
    readonly property real expandedHeight: authOpen ? launcherTop + authPanel.outerHeight
                                                    : launcherOpen ? launcherTop + launcherHeight
                                                    : docked ? overviewBottom + overviewInset
                                                             : panelBottom

    anchors.horizontalCenter: parent.horizontalCenter
    // Angedockt mit Kontur: die obere Randlinie liegt ausserhalb des Bildes
    y: docked ? -pill.borderWidth : verticalMargin / 2
    width: open ? expandedWidth : collapsedWidth + 2 * growth
    height: open ? expandedHeight : collapsedHeight + growth

    // Die Insel reagiert sofort auf den Zeiger – noch bevor sie aufklappt.
    // Angedockt waechst sie stattdessen (growth): eine skalierte Notch
    // wuerde sich mitsamt Schultern von der Oberkante loesen.
    scale: !docked && hoverSensor.hovered && !open ? 1.04 : 1

    // Aufklappen erst nach kurzem Verweilen, Zuklappen mit Nachlauf
    onContainsMouseChanged: {
        if (containsMouse) {
            closeTimer.stop();
            if (!expanded && !launcherOpen)
                openTimer.restart();
        } else {
            openTimer.stop();
            closeTimer.restart();
        }
    }

    // Beim Zuklappen wieder auf heute zurückspringen
    onExpandedChanged: if (!expanded) panel.dayOffset = 0
    // Der Launcher übernimmt die Karte: Datums-Ansicht dabei einklappen
    onLauncherOpenChanged: if (launcherOpen) expanded = false
    onAuthOpenChanged: {
        if (authOpen) {
            expanded = false;
            LauncherState.close();
        }
    }

    Timer {
        id: openTimer
        interval: 200
        onTriggered: notch.expanded = true
    }

    Timer {
        id: closeTimer
        interval: 250
        onTriggered: {
            if (panel.dragging || swipe.active)   // beim Ziehen darf die Maus rausrutschen
                closeTimer.restart();
            else
                notch.expanded = false;
        }
    }

    Morph on width {}
    Morph on height {}
    Morph on scale {}

    // Pille, solange sie flach ist; ab 2 x cardRadius Hoehe eine Karte.
    // Verlauf, Rand und Schatten bringt Surface mit (modules/widgets).
    Surface {
        id: pill
        anchors.fill: parent

        maxRadius: notch.cardRadius
        // Angedockt: schwarz, flach und ohne Rand – sie soll wie ein Teil
        // des Displayrahmens wirken, die Schultern muessen nahtlos passen.
        baseColor: notch.docked ? Appearance.notchColor : Colors.background
        lift: notch.docked ? 0 : Appearance.lift
        // Kontur nur, wenn sie sich sonst nicht vom Wallpaper abhebt
        borderWidth: notch.docked ? (Appearance.notchBorder ? 1 : 0) : notch.borderWidth
        borderColor: notch.docked ? Appearance.notchBorderColor : notch.borderColor
        docked: notch.docked
        // Die Kontur der Seiten setzt unter der (animierten) Schulter an
        shoulder: shoulderLeft.size
        // Eingeklappt ist sie Rahmen, kein Objekt – Schatten erst, wenn sie
        // als Karte ueber den Fenstern liegt
        shadowStrength: !notch.docked || notch.open ? 1 : 0

        Behavior on shadowStrength {
            NumberAnimation { duration: Appearance.morphDuration * 0.65; easing.type: Easing.OutCubic }
        }

        // Nach unten ziehen öffnet den Launcher. Solange diese Geste läuft,
        // ist das Ziehen im Datumsstreifen stillgelegt.
        DragHandler {
            id: launcherDrag

            target: null
            xAxis.enabled: false
            enabled: !LauncherState.open && !Auth.active

            readonly property real threshold: 55
            property bool triggered: false

            onActiveChanged: if (active) triggered = false
            onTranslationChanged: {
                if (!launcherDrag.active || launcherDrag.triggered)
                    return;
                if (launcherDrag.activeTranslation.y > launcherDrag.threshold) {
                    launcherDrag.triggered = true;
                    LauncherState.show(notch.QsWindow.window.screen);
                }
            }
        }

        // Seitlich ziehen: auf der Jetzt-laeuft-Zeile der Uebersicht (und
        // eingeklappt auf der Notch mit Cover) wechselt es den Song, ueberall
        // sonst blaettert es die Seiten wie das Mausrad – auch im Medien-
        // Untermenue, das hat eigene Skip-Knoepfe. Welche Geste es wird,
        // entscheidet der Druckpunkt. Links ziehen = naechster Song bzw.
        // naechste Seite. Waehrend des Zugs folgt der Inhalt (bzw. beim Song
        // nur der Zeilen-Hintergrund) gedaempft dem Zeiger; beim Loslassen
        // zaehlt nur die Strecke, nicht die Zeit.
        //
        // Datumsstreifen, Fortschrittsbalken und Benachrichtigungs-Zeilen
        // haben eigene seitliche Zuege – deren Handler liegen tiefer im Baum
        // und greifen zuerst zu. Wegnehmen darf dieser hier ihnen den Zeiger
        // nicht: Handler mit eigenen Properties sind fuer Qt jeweils ein
        // eigener Typ, und das Standardrecht CanTakeOverFromHandlersOf-
        // DifferentType liesse ihn sonst mitten im Zug uebernehmen (so war
        // das Wegwischen von Nachrichten kaputt). Zum Launcher-Zug (nur
        // senkrecht) gibt es keinen Konflikt: die Achse, die zuerst die Schwelle reisst, gewinnt.
        DragHandler {
            id: swipe

            target: null
            yAxis.enabled: false
            grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.ApprovesTakeOverByAnything
            enabled: !Auth.active && (notch.pagerShown || (notch.showMedia && !notch.open))

            readonly property real threshold: 60
            readonly property real follow: 0.4     // Daempfung beim Blaettern
            readonly property real followMax: 48
            // Beim Song folgt die Karte 1:1, hoechstens bis die zweite Karte steht
            readonly property real songFollowMax: nowPlaying.flipDistance
            // "song", "tabs" oder "" (nichts zu tun)
            property string kind: ""
            // Letzte Zugstrecke – beim Loslassen ist activeTranslation ggf. schon weg
            property real lastX: 0

            function kindAt(p: point): string {
                if (nowPlaying.visible && nowPlaying.contains(nowPlaying.mapFromItem(pill, p)))
                    return "song";
                if (notch.showMedia && !notch.open)
                    return "song";
                return notch.pagerShown ? "tabs" : "";
            }

            onActiveChanged: {
                if (swipe.active) {
                    swipe.lastX = 0;
                    swipe.kind = swipe.kindAt(swipe.centroid.pressPosition);
                    slideIn.stop();
                    songSlideIn.stop();
                    songFlip.stop();
                    return;
                }
                const dir = swipe.lastX < 0 ? 1 : -1;
                const far = Math.abs(swipe.lastX) >= swipe.threshold;
                if (swipe.kind === "song") {
                    if (far)
                        notch.skipSong(dir);
                    else {
                        songSlideIn.from = notch.songSlide;
                        songSlideIn.restart();
                    }
                } else if (swipe.kind === "tabs") {
                    if (far)
                        notch.flip(dir);
                    else {
                        slideIn.from = notch.slide;
                        slideIn.restart();
                    }
                }
                swipe.kind = "";
            }

            onTranslationChanged: {
                if (!swipe.active || swipe.kind === "")
                    return;
                swipe.lastX = swipe.activeTranslation.x;
                if (swipe.kind === "song")
                    notch.songSlide = Math.max(-swipe.songFollowMax, Math.min(swipe.songFollowMax, swipe.lastX));
                else
                    notch.slide = Math.max(-swipe.followMax, Math.min(swipe.followMax, swipe.lastX * swipe.follow));
            }
        }

        Clock {
            id: clock

            anchors.horizontalCenter: parent.horizontalCenter
            // Platz für den Aufnahme-Punkt rechts daneben (0, wenn keiner da)
            anchors.horizontalCenterOffset: -notch.recordReserve / 2
            // im eingeklappten Band zentriert, beim Aufklappen etwas tiefer;
            // im Launcher-Modus macht sie ganz Platz
            y: (notch.bandHeight - height) / 2 + notch.clockDrop
            // Angedockt wird sie aufgeklappt zur Ueberschrift der Karte
            scale: notch.docked && notch.expanded ? 1.3 : 1
            // Aufgeklappt nimmt die Uhr die Akzentfarbe an
            color: notch.open ? Colors.primary : Colors.fgBackground
            opacity: notch.launcherOpen || notch.authOpen ? 0 : 1
            visible: opacity > 0

            Behavior on color {
                ColorAnimation { duration: Appearance.fadeDuration }
            }

            Behavior on y {
                NumberAnimation { duration: Appearance.morphDuration * 0.65; easing.type: Easing.OutCubic }
            }
            Morph on scale {}
            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }
            // Gleiches Timing wie die Pille selbst, damit Uhr und Kante
            // zusammen wandern
            Behavior on anchors.horizontalCenterOffset {
                NumberAnimation { duration: Appearance.morphDuration * 0.65; easing.type: Easing.OutCubic }
            }
        }

        // Der Aufnahme-Punkt. Er pulst langsam, damit er als Zustand lesbar
        // ist und nicht als Deko; im Launcher-Modus geht er mit der Uhr.
        Item {
            id: recordDot

            anchors {
                left: clock.right
                leftMargin: notch.recordGap
                verticalCenter: clock.verticalCenter
            }
            implicitWidth: notch.recordDotSize
            implicitHeight: notch.recordDotSize
            opacity: notch.recording && !notch.docked && !notch.launcherOpen && !notch.authOpen ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: islandRecordDot

                anchors.fill: parent

                radius: width / 2
                color: Colors.record

                // Nur pulsen, solange der Punkt zu sehen ist – eine laufende
                // Animation zeichnet sonst das ganze Leistenfenster neu
                SequentialAnimation on opacity {
                    running: notch.recording && islandRecordDot.visible
                    loops: Animation.Infinite

                    NumberAnimation { from: 1; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
            }
        }

        // ---- Links: Workspaces (Notch-Layout) ----
        // Die Staebchen bleiben beim Aufklappen stehen und wandern nur an den
        // Kartenrand – in der Kopfzeile der Uebersicht und der Untermenues
        // (wie der Visualiser: eine Anzeige, die mit der Notch mitgeht).
        // Eingeklappt nimmt bei laufender Musik das Cover (mediaArt) ihren
        // Platz ein. Specials zeigt sie als kleines Overlay (NotchWorkspaces).
        NotchWorkspaces {
            id: compactWorkspaces

            anchors {
                left: parent.left
                leftMargin: notch.open ? notch.overviewInset + 2 : notch.compactEdge + notch.growth
                verticalCenter: clock.verticalCenter
            }
            opacity: !notch.showWorkspaces ? 0
                   : notch.open ? (notch.overviewShown || notch.docked && notch.viewOpen ? 1 : 0)
                   : notch.showMedia ? 0 : 1
            visible: opacity > 0

            Fade on opacity {}
            Behavior on anchors.leftMargin {
                NumberAnimation { duration: Appearance.morphDuration; easing.type: Easing.OutCubic }
            }
        }

        // ---- Eingeklappt, rechts: Hinweise + Datum bzw. Pegel ----
        // Von innen nach aussen: Aufnahme-Punkt, Nachrichten-Zaehler, dann
        // Datum – oder, solange Musik laeuft, die Cava-Pegel. Die Notch misst
        // ihre Breite an dieser Gruppe (compactSide), die Uhr bleibt mittig.
        Row {
            id: compactRight

            anchors {
                right: parent.right
                rightMargin: (notch.showVisualizer ? notch.mediaEdge + 3 : notch.compactEdge) + notch.growth
                verticalCenter: clock.verticalCenter
            }
            spacing: 8
            opacity: notch.docked && !notch.open ? 1 : 0
            visible: opacity > 0

            Fade on opacity {}

            // Aufnahme-Punkt, pulst langsam wie sein Gegenstueck im Insel-Layout
            Rectangle {
                id: dockedRecordDot

                anchors.verticalCenter: parent.verticalCenter
                visible: notch.recording
                width: notch.recordDotSize
                height: notch.recordDotSize
                radius: width / 2
                color: Colors.record

                SequentialAnimation on opacity {
                    running: notch.recording && notch.docked && dockedRecordDot.visible
                    loops: Animation.Infinite

                    NumberAnimation { from: 1; to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.35; to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
            }

            // Nachrichten-Zaehler
            Rectangle {
                id: messageBadge

                anchors.verticalCenter: parent.verticalCenter
                visible: notch.showMessages
                width: Math.max(notch.messageBadgeSize, badgeText.implicitWidth + 8)
                height: notch.messageBadgeSize
                radius: height / 2
                color: Colors.primary

                Text {
                    id: badgeText

                    anchors.centerIn: parent
                    font.family: Config.font
                    text: Notifications.count > 9 ? "9+" : Notifications.count
                    color: Colors.fgPrimary
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }

            // Akku (nur mit Systemakku und Einstellung "Akkuanzeige"). Der Ring
            // des Insel-Layouts passt nicht um die angedockte Notch – hier
            // stehen Symbol und Prozent, knapp = rot.
            Row {
                id: compactBattery

                readonly property bool low: Power.percent <= 20 && !Power.charging

                anchors.verticalCenter: parent.verticalCenter
                visible: Power.hasSystemBattery && Config.bar.battery
                spacing: 2

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Power.batteryIcon
                    rotation: 90
                    color: compactBattery.low ? Colors.error
                         : Power.charging ? Colors.primary
                         : Colors.alpha(Colors.fgBackground, 0.7)
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 15
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${Power.percent}%`
                    color: compactBattery.low ? Colors.error : Colors.alpha(Colors.fgBackground, 0.7)
                    font.family: Config.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }

            // Wochentag und Tag, gedaempft – die Uhr bleibt der Blickfang
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Config.notch.date && !notch.showVisualizer
                text: clock.date.toLocaleDateString(I18n.locale, "ddd d")
                color: Colors.alpha(Colors.fgBackground, 0.55)
                font.family: Config.font
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            // Live-Activity: Pegel als gespiegelte Wellenform
            Visualizer {
                id: mediaBars

                anchors.verticalCenter: parent.verticalCenter
                visible: notch.showVisualizer
                height: notch.mediaArtSize - 4
                count: 5
                barWidth: 3
                active: Media.playing
            }
        }

        // ---- Knoepfe der Kopfzeile ----
        // Runde Chips links und rechts der Uhr, sobald die Karte aufgeklappt
        // ist: aussen Wallpaper bzw. Power, innen (nur Notch-Layout) die
        // Schalter fuer das, was die eingeklappte Notch zeigt. Ein aktiver
        // Schalter fuellt sich in der Akzentfarbe, `danger` faerbt den Hover
        // rot (Power).
        //
        // TapHandler statt MouseArea, damit der Launcher-DragHandler in der
        // Karte seinen Druck behaelt: ein Zug nach unten bricht den Tap ab.
        component NotchButton: Item {
            id: button

            required property string icon
            property bool active: false
            property bool danger: false
            // Zusaetzliche Bedingung (die Schalter gibt es nur angedockt)
            property bool available: true
            signal clicked()

            readonly property bool shown: button.available && notch.expanded
                                          && !notch.launcherOpen && !notch.authOpen

            implicitWidth: notch.headerButtonSize
            implicitHeight: notch.headerButtonSize
            opacity: button.shown ? 1 : 0
            visible: opacity > 0
            scale: buttonHover.hovered ? 1.08 : 1

            Fade on opacity {}
            Morph on scale {}

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: button.active ? Colors.alpha(Colors.primary, 0.2)
                     : buttonHover.hovered ? Colors.alpha(button.danger ? Colors.error : Colors.fgBackground, 0.14)
                     : Colors.alpha(Colors.fgBackground, 0.06)

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }
            }

            Text {
                anchors.centerIn: parent
                text: button.icon   // Material-Symbols-Ligatur
                color: button.active ? Colors.primary
                     : buttonHover.hovered ? (button.danger ? Colors.error : Colors.fgBackground)
                     : Colors.fgSurfaceVariant
                font.family: "Material Symbols Outlined"
                font.pixelSize: 16
                // Variable Font: Strichstaerke ueber die wght-Achse
                font.variableAxes: ({ wght: button.active ? 700 : 500, FILL: button.active ? 1 : 0 })

                Behavior on color {
                    ColorAnimation { duration: Appearance.fadeDuration }
                }
            }

            HoverHandler {
                id: buttonHover

                cursorShape: Qt.PointingHandCursor
            }

            TapHandler {
                onTapped: button.clicked()
            }
        }

        // Wallpaper: oeffnet den Launcher direkt in der Wallpaper-Auswahl –
        // derselbe Weg wie `>wallpaper` im Suchfeld. Nur im Insel-Layout:
        // angedockt sind Wallpaper und Power per Kuerzel/Befehl erreichbar
        // (nicht alles braucht einen Knopf).
        NotchButton {
            id: wallpaperButton

            anchors {
                left: parent.left
                leftMargin: notch.headerInset
                verticalCenter: clock.verticalCenter
            }
            available: !notch.docked
            icon: "wallpaper_slideshow"
            onClicked: LauncherState.showWallpapers(notch.QsWindow.window.screen)
        }

        NotchButton {
            id: powerButton

            anchors {
                right: parent.right
                rightMargin: notch.headerInset
                verticalCenter: clock.verticalCenter
            }
            available: !notch.docked
            icon: "power_settings_new"
            danger: true
            onClicked: LauncherState.showPower(notch.QsWindow.window.screen)
        }

        // ---- Glocke oben rechts ----
        // Glocke mit Zaehler. Ein Klick oeffnet das Untermenue
        // "Benachrichtigungen" (wie SUPER+N), steht man schon darin, geht es
        // zurueck zur Uebersicht.
        Item {
            id: bell

            anchors {
                right: parent.right
                rightMargin: notch.overviewInset + 4
                verticalCenter: clock.verticalCenter
            }
            width: 22
            height: 22
            opacity: notch.overviewShown || notch.docked && notch.viewOpen ? 1 : 0
            visible: opacity > 0
            scale: bellHover.hovered ? 1.12 : 1

            Fade on opacity {}
            Morph on scale {}

            // Trefferflaeche etwas groesser als das Symbol
            Item {
                anchors.centerIn: parent
                width: 34
                height: 34

                HoverHandler {
                    id: bellHover

                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: {
                        if (notch.notificationsOpen) {
                            LauncherState.close();
                            notch.expanded = true;
                        } else {
                            LauncherState.showMode(notch.QsWindow.window.screen, "notifications");
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                text: Notifications.dnd ? "notifications_off" : "notifications"
                color: Notifications.count > 0 ? Colors.fgBackground : Colors.alpha(Colors.fgSurfaceVariant, 0.6)
                font.family: "Material Symbols Outlined"
                font.pixelSize: 17
                font.variableAxes: ({ FILL: Notifications.count > 0 ? 1 : 0 })
            }

            Rectangle {
                visible: Notifications.count > 0
                x: parent.width - width / 2 - 3
                y: -3
                width: Math.max(15, bellCount.implicitWidth + 7)
                height: 15
                radius: height / 2
                color: Colors.primary

                Text {
                    id: bellCount

                    anchors.centerIn: parent
                    text: Notifications.count > 9 ? "9+" : Notifications.count
                    color: Colors.fgPrimary
                    font.family: Config.font
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }
        }

        // ---- Uebersicht: Jetzt laeuft ----
        NowPlayingRow {
            id: nowPlaying
            transform: Translate { x: notch.slide }

            shift: notch.songSlide
            pull: notch.songPull
            fadeColor: pill.baseColor

            x: notch.overviewInset
            y: notch.panelBottom + 8
            width: parent.width - 2 * notch.overviewInset
            height: notch.showNowPlaying ? implicitHeight : 0
            opacity: notch.overviewShown && notch.showNowPlaying ? 1 : 0
            visible: opacity > 0

            Fade on opacity {}
        }

        // ---- Uebersicht: Systemwerte ----
        SystemGlance {
            id: systemGlance
            transform: Translate { x: notch.slide }

            x: notch.overviewInset
            y: notch.showNowPlaying ? nowPlaying.y + nowPlaying.height + 8 : notch.panelBottom + 8
            width: parent.width - 2 * notch.overviewInset
            opacity: notch.overviewShown ? 1 : 0
            visible: opacity > 0

            Fade on opacity {}
        }

        // ---- Seiten-Indikator ----
        // Ein Punkt je Ansicht (LauncherState.views), der aktive breit in der
        // Akzentfarbe. Klick springt direkt auf die Seite; blaettern geht
        // ausserdem mit dem Mausrad bzw. Wischen ueber der Kopfzeile
        // (flipZone). Sitzt rechts oben neben der
        // Glocke – alle Blaetter-Seiten sind gleich breit (pageWidth) und
        // haengen oben fest, also steht er immer an derselben Stelle.
        Row {
            id: pager

            anchors {
                right: bell.left
                rightMargin: 12
            }
            y: notch.headerCenter - height / 2
            height: 6
            spacing: 5
            opacity: notch.pagerShown ? 1 : 0
            visible: opacity > 0

            Fade on opacity {}

            Repeater {
                model: LauncherState.views.length

                Rectangle {
                    id: dot

                    required property int index
                    readonly property bool current: dot.index === LauncherState.viewIndex

                    width: dot.current ? 16 : 6
                    height: 6
                    radius: 3
                    color: dot.current ? Colors.primary
                         : Colors.alpha(Colors.fgBackground, dotHover.hovered ? 0.5 : 0.22)

                    Behavior on width {
                        NumberAnimation { duration: Appearance.fadeDuration * 1.5; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Appearance.fadeDuration }
                    }

                    // Trefferflaeche deutlich groesser als der 6-px-Punkt,
                    // ohne Luecke zum Nachbarn
                    Item {
                        anchors.centerIn: parent
                        width: dot.width + pager.spacing
                        height: 22

                        HoverHandler {
                            id: dotHover

                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: notch.showView(dot.index)
                        }
                    }
                }
            }
        }

        // ---- Blaettern: Mausrad / Wischen ----
        // Nur die Kopfzeile blaettert. Darunter gehoert das Rad dem Inhalt
        // (Datum, Listen), damit es an jeder Stelle immer dasselbe tut.
        //
        // Hi-Res-Raeder (G502) liefern ~15 Einheiten je Event statt 120 je
        // Rastung. Deshalb aufsummieren und je voller Rastung eine Seite
        // weiter – ohne Sperre danach, eine Rastung = eine Seite.
        // Den Zaehler NICHT bei kurzen Pausen zuruecksetzen, sonst kommt
        // langsames Drehen nie ueber die Schwelle (accumDecay erst nach 500 ms).
        // Unter allem anderen (z: -1): wer ein eigenes Rad hat – die
        // Workspace-Staebchen springen damit zwischen Workspaces – nimmt es
        // zuerst, der Rest der Kopfzeile faellt hierher durch.
        Item {
            id: flipZone

            z: -1
            width: parent.width
            height: notch.flipZoneHeight
        }

        WheelHandler {
            id: flipWheel

            parent: flipZone
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            enabled: notch.pagerShown

            property real accum: 0

            onWheel: event => {
                event.accepted = true;
                accumDecay.restart();

                const horizontal = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)
                    || Math.abs(event.pixelDelta.x) > Math.abs(event.pixelDelta.y);
                const angle = horizontal ? event.angleDelta.x : event.angleDelta.y;
                const pixels = horizontal ? event.pixelDelta.x : event.pixelDelta.y;
                // Eine Seite je echter Rastung (120). Das Hi-Res-Rad der G502
                // liefert die in ~8 Teilen zu 15 – die werden aufsummiert.
                // Touchpad: 60 px Zug je Seite.
                const delta = pixels !== 0 ? pixels / 60 : angle / 120;

                // Richtungswechsel verwirft den Rest der alten Richtung
                if (flipWheel.accum !== 0 && Math.sign(delta) !== Math.sign(flipWheel.accum))
                    flipWheel.accum = 0;
                flipWheel.accum += delta;
                if (Math.abs(flipWheel.accum) < 1)
                    return;

                // Rad nach unten bzw. nach links wischen = naechste Ansicht
                const dir = flipWheel.accum < 0 ? 1 : -1;
                flipWheel.accum = 0;

                notch.flip(dir);
            }
        }

        // Angefangener Zug verfaellt erst nach einer echten Pause
        Timer {
            id: accumDecay

            interval: 500
            onTriggered: flipWheel.accum = 0
        }

        NumberAnimation {
            id: slideIn

            target: notch
            property: "slide"
            to: 0
            duration: Appearance.morphDuration
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            id: songSlideIn

            target: notch
            property: "songSlide"
            to: 0
            duration: Appearance.morphDuration
            easing.type: Easing.OutCubic
        }

        // Wechsel: zweite Karte ganz herein, dann ohne Animation zurueck auf 0
        NumberAnimation {
            id: songFlip

            target: notch
            property: "songSlide"
            duration: Appearance.morphDuration
            easing.type: Easing.OutCubic
            onFinished: notch.songSlide = 0
        }

        // ---- Live-Activity: Cover links ----
        Item {
            id: mediaArt
            transform: Translate { x: notch.songSlide }

            anchors {
                left: parent.left
                leftMargin: notch.mediaEdge + notch.growth
                verticalCenter: clock.verticalCenter
            }
            width: notch.mediaArtSize
            height: notch.mediaArtSize
            opacity: notch.showMedia && !notch.open ? 1 : 0
            visible: opacity > 0
            scale: notch.showMedia && !notch.open ? 1 : 0.5

            Fade on opacity {}
            Morph on scale {}

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: Colors.surfaceContainer

                Text {
                    anchors.centerIn: parent
                    visible: !artEffect.visible

                    text: "music_note"
                    color: Colors.fgSurfaceVariant
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 11
                }
            }

            Image {
                id: artImage

                anchors.fill: parent
                source: Media.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: notch.mediaArtSize * 2
                sourceSize.height: notch.mediaArtSize * 2
                visible: false
            }

            // Rundes Cover: `clip` schneidet nur rechteckig, deshalb die
            // Rundung als Maske (dasselbe Muster wie der Kartengrund der
            // Medien-Karte).
            Rectangle {
                id: artMask

                anchors.fill: parent
                radius: 6
                color: "black"
                layer.enabled: true
                visible: false
            }

            MultiEffect {
                id: artEffect

                anchors.fill: parent
                source: artImage
                maskEnabled: true
                maskSource: artMask
                visible: artImage.status === Image.Ready
            }
        }

        // Akku-Ring am Aussenrand der Pille, wenn ein Systemakku da ist.
        // Derselbe Ring wie an der Settings-Pille: die Stadion-Form legt sich
        // um die flache Pille, die Luecke sitzt unten in der Mitte.
        //
        // Nur eingeklappt – aufgeklappt waere es ein Rahmen um eine grosse
        // Karte, und die Uhr ist dann ohnehin nicht mehr der Inhalt.
        //
        // `value` und `muted` ueberschreiben die Audio-Vorgaben der Datei
        // (so macht es Settings.qml schon fuer die Helligkeit).
        Audioslider {
            id: batteryRing

            // Voll = Primaerfarbe, leer = Fehlerfarbe. Der Umschlag ist bei
            // 20 % erreicht, bei 60 % haelt sich beides die Waage; die 0.8
            // unten ist die einzige Stellschraube dafuer.
            // Der Exponent haelt die Mitte ausgewogen: linear waere bei 50 %
            // schon fast alles rot.
            readonly property real drain: Math.pow(Math.max(0, Math.min(1,
                (1 - Power.percent / 100) / 0.8)), 1.5)

            arcWidth: 2
            arcGap: 3
            showTrack: false
            value: Power.percent / 100
            muted: false
            activeColor: Colors.mix(Colors.primary, Colors.error, batteryRing.drain)

            opacity: notch.open || notch.docked || !Power.hasSystemBattery || !Config.bar.battery ? 0 : 1
            // Nicht ueber die aufklappende Karte mitstrecken. Beim Schliessen
            // darf der Ring weiterhin weich wieder eingeblendet werden.
            visible: !notch.open && !notch.docked && Power.hasSystemBattery && Config.bar.battery

            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }
        }

        // Der leere Teil bleibt ein statischer Pfad und wird deshalb nur bei
        // einer Aenderung des Akkustands neu aufgebaut.
        Audioslider {
            id: batteryEmpty

            readonly property real progress: Power.percent / 100

            arcWidth: 2
            arcGap: 3
            showTrack: false
            muted: false
            fromValue: progress
            value: 1
            activeColor: Colors.alpha(batteryRing.activeColor, 0.55)

            opacity: notch.open || notch.docked || !Power.hasSystemBattery || !Config.bar.battery ? 0 : 1
            // Sofort ausblenden: Sonst wird der Wellenpfad waehrend der
            // breiten Launcher-Animation fuer jeden Frame neu berechnet.
            visible: !notch.open && !notch.docked && Power.hasSystemBattery && Config.bar.battery
        }

        // Effizienter Ladeimpuls: statt den SVG-Pfad pro Frame neu zu bauen,
        // bewegt sich nur ein kleines Rechteck entlang der vorhandenen
        // Ring-Geometrie. Die Weggeschwindigkeit skaliert mit der Ladeleistung.
        Item {
            id: batteryPulse

            readonly property real chargeProgress: Power.percent / 100
            readonly property bool running: Config.bar.batteryPulse
                && Config.bar.battery && Power.activelyCharging
                && chargeProgress < 0.995 && !notch.open && !notch.docked
            readonly property real rateFactor: Math.max(0, Math.min(1,
                (Power.chargeRate - 5) / 60))
            readonly property real pathStart: batteryRing.fromLength
                + (batteryRing.toLength - batteryRing.fromLength) * chargeProgress
            readonly property real pathLength: Math.max(0, batteryRing.toLength - pathStart)
            readonly property real distance: pathStart + pathLength * travel
            // Nur waehrend des Impulses: sonst rechnete der Punkt jede
            // Groessenaenderung der Pille mit (~1000x/s waehrend eines Morphs)
            readonly property var point: running ? batteryRing.pointAt(distance) : Qt.point(0, 0)
            readonly property int travelDuration: Math.round(750 - rateFactor * 400)
            readonly property int pulseInterval: Math.round(1800 - rateFactor * 1200)

            property real travel: 0

            anchors.fill: parent
            visible: running

            Rectangle {
                width: 7
                height: 7
                radius: width / 2
                x: batteryPulse.point.x - width / 2
                y: batteryPulse.point.y - height / 2
                color: Colors.alpha(batteryRing.activeColor, 0.22)
                opacity: pulseCore.opacity
            }

            Rectangle {
                id: pulseCore

                width: 3
                height: 3
                radius: width / 2
                x: batteryPulse.point.x - width / 2
                y: batteryPulse.point.y - height / 2
                color: Colors.mix(batteryRing.activeColor, Colors.fgBackground, 0.7)
                opacity: Math.max(0, Math.min(1,
                    Math.min(batteryPulse.travel / 0.1,
                             (1 - batteryPulse.travel) / 0.18)))
            }

            SequentialAnimation on travel {
                running: batteryPulse.running
                loops: Animation.Infinite

                NumberAnimation {
                    from: 0
                    to: 1
                    duration: batteryPulse.travelDuration
                    easing.type: Easing.InOutSine
                }

                PauseAnimation {
                    duration: batteryPulse.pulseInterval
                }
            }
        }

        DatePanel {
            id: panel
            transform: Translate { x: notch.slide }

            topOffset: notch.collapsedHeight + notch.clockDrop
            cardRadius: notch.cardRadius
            // Insel: Mausrad gilt auf der ganzen Karte. Angedockt nur auf dem
            // Streifen selbst – sonst blaettert das Rad die Ansichten
            gestureArea: notch.docked ? panel : pill
            fadeColor: pill.baseColor
            // Angedockt ist die Karte so breit wie alle Blaetter-Seiten – das
            // Karussell fuellt sie mit mehr Tagen, statt mittig zu stehen
            visibleColumns: notch.docked ? 15 : 7
            columnWidth: notch.docked ? 30 : 26
            dragEnabled: !launcherDrag.active
            opacity: notch.cardShown ? 1 : 0
            // Beim Wechsel zum Launcher (oder zur Steuerungs-Seite) sofort aus
            // dem Renderpfad nehmen. So wird der Datumsstreifen nicht auf die
            // neue Kartenbreite mitanimiert.
            visible: notch.cardShown

            Behavior on opacity {
                NumberAnimation { duration: Appearance.fadeDuration; easing.type: Easing.OutCubic }
            }
        }

        LazyPanel {
            id: launcher

            open: notch.appsOpen

            sourceComponent: LauncherPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        LazyPanel {
            id: wallpapers

            open: notch.wallpaperOpen

            sourceComponent: WallpaperPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        LazyPanel {
            id: themes

            open: notch.themeOpen

            sourceComponent: ThemePanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        LazyPanel {
            id: powerMenu

            open: notch.powerOpen

            sourceComponent: PowerPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        LazyPanel {
            id: keysView

            open: notch.keysOpen

            sourceComponent: KeybindsPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        LazyPanel {
            id: clipboardView

            open: notch.clipboardOpen

            sourceComponent: ClipboardPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        // ---- Untermenues (Notch-Layout und Insel) ----
        LazyPanel {
            id: mediaView
            transform: Translate { x: notch.slide }

            open: notch.mediaOpen

            sourceComponent: MediaViewPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        LazyPanel {
            id: controlLoader
            transform: Translate { x: notch.slide }

            open: notch.controlOpen

            sourceComponent: ControlPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        LazyPanel {
            id: notificationsView
            transform: Translate { x: notch.slide }

            open: notch.notificationsOpen

            sourceComponent: NotificationsPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        LazyPanel {
            id: systemView
            transform: Translate { x: notch.slide }

            open: notch.systemOpen

            sourceComponent: SystemPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
            }
        }

        LazyPanel {
            id: authPanel

            open: notch.authOpen

            sourceComponent: AuthPanel {
                topOffset: notch.launcherTop
                cardRadius: notch.cardRadius
                active: true
                flow: Auth.flow
            }
        }
    }

    // ---- Schultern (Notch-Layout) ----
    // Ausserhalb der Breite, damit die Notch selbst ein Rechteck bleibt
    // (Maske, Anker, Innenmasse). Nach der Karte deklariert, damit sie ueber
    // deren Schatten liegen und die Kante sauber schliessen.
    NotchShoulder {
        id: shoulderLeft

        x: -width
        y: 0
        size: notch.shoulder
        color: Appearance.notchColor
        strokeWidth: pill.borderWidth
        strokeColor: Appearance.notchBorderColor
        visible: notch.docked

        Morph on size {}
    }

    NotchShoulder {
        x: notch.width
        y: 0
        size: notch.shoulder
        color: Appearance.notchColor
        strokeWidth: pill.borderWidth
        strokeColor: Appearance.notchBorderColor
        mirrored: true
        visible: notch.docked

        Morph on size {}
    }

    // Reiner Hover-Sensor fuer das Auf-/Zuklappen.
    //
    // Frueher eine MouseArea mit `hoverEnabled` – die nimmt Hover-Events aber
    // exklusiv an. Dadurch kam der HoverHandler des Power-Knopfs darunter nie
    // zum Zug: kein Farbwechsel, keine Cursor-Form. HoverHandler blockieren
    // sich gegenseitig nicht, beide sehen denselben Zeiger. Klicks nimmt der
    // hier ohnehin keine, der DragHandler in der Karte behaelt seinen Druck.
    HoverHandler {
        id: hoverSensor
    }
}
