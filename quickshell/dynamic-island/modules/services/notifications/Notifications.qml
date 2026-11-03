pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.modules.services.config

import qs

// Benachrichtigungs-Dienst: die Shell IST hier der Notification-Daemon.
//
// Auf diesem Rechner lief bisher keiner – org.freedesktop.Notifications hatte
// keinen Besitzer, und der einzige aktivierbare Dienst ist Plasmas
// `plasma_waitforname`, das nur wartet. `notify-send` blieb deshalb einfach
// haengen. Mit diesem Server funktionieren Benachrichtigungen ueberhaupt erst.
//
// Ein Eintrag ist bewusst nur { notif, time } statt einer Kopie aller
// Felder: die Zeilen binden direkt an
// die lebende Notification, dadurch gehen Nachrichten, die sich selbst
// aktualisieren (Lautstaerke, Fortschritt), live mit. Ein Zeitstempel fehlt
// der Notification dagegen – den setzen wir selbst.
//
// Benutzung:  import qs.modules.services.notifications
Singleton {
    id: root

    // [{ notif, time }] – neueste vorne
    property var list: []
    readonly property int count: root.list.length
    readonly property var latest: root.list[0] ?? null

    // Nach App gebuendelt: [{ app, entries }]. `list` ist schon neueste-zuerst,
    // und eine Map behaelt die Einfuegereihenfolge – dadurch steht die App mit
    // der juengsten Nachricht oben und innerhalb einer Gruppe ebenso.
    readonly property var groups: {
        const map = new Map();
        for (const e of root.list) {
            const app = e.notif?.appName || "System";
            if (!map.has(app))
                map.set(app, []);
            map.get(app).push(e);
        }
        return Array.from(map, ([app, entries]) => ({ app, entries }));
    }

    // Nicht stoeren: unterdrueckt nur das Aufklappen der Pille, gesammelt wird
    // weiter. Liegt in der
    // Konfiguration, ueberlebt also einen Neustart.
    readonly property bool dnd: Config.notifications.dnd

    function toggleDnd(): void {
        Config.set("notifications", "dnd", !root.dnd);
    }

    // Zaehlt hoch, damit sich die Altersangaben ("5m") von selbst auffrischen
    property int tick: 0

    // Die Pille haengt daran und klappt kurz auf
    signal arrived(var entry)

    function add(n: var): void {
        const entry = { notif: n, time: new Date() };
        root.list = [entry, ...root.list];

        // Schliesst die App die Nachricht selbst, darf kein toter Verweis
        // in der Liste zurueckbleiben
        n.closed.connect(() => root.drop(n));

        if (!root.dnd)
            root.arrived(entry);
    }

    function drop(n: var): void {
        root.list = root.list.filter(e => e.notif !== n);
    }

    function dismiss(entry: var): void {
        root.list = root.list.filter(e => e !== entry);
        entry?.notif?.dismiss();
    }

    // Eine ganze App wegraeumen (Kreuz am Gruppenkopf)
    function dismissGroup(group: var): void {
        const entries = group?.entries ?? [];
        root.list = root.list.filter(e => !entries.includes(e));
        for (const e of entries)
            e?.notif?.dismiss();
    }

    function clear(): void {
        const old = root.list;
        root.list = [];
        for (const e of old)
            e?.notif?.dismiss();
    }

    // Aktionen einer Nachricht, aufgeteilt nach der Spezifikation:
    //
    //   "default"  gehoert dem Klick auf die Nachricht selbst und wird NICHT
    //              als Knopf gezeigt (fast jede App schickt so eine mit)
    //   alles andere kommt als Knopf unter den Text
    function defaultAction(entry: var): var {
        const actions = entry?.notif?.actions ?? [];
        return actions.find(a => a.identifier === "default") ?? null;
    }

    function actionButtons(entry: var): var {
        const actions = entry?.notif?.actions ?? [];
        return actions.filter(a => a.identifier !== "default");
    }

    // "jetzt" / "5m" / "2h" / "3d" – knapp genug fuer die Pille
    function formatAge(time: var): string {
        if (!time)
            return "";

        const m = Math.floor((Date.now() - time.getTime()) / 60000);
        if (m < 1)
            return I18n.tr("jetzt");
        if (m < 60)
            return `${m}m`;

        const h = Math.floor(m / 60);
        if (h < 24)
            return `${h}h`;
        return `${Math.floor(h / 24)}d`;
    }

    NotificationServer {
        id: server

        // Ueberlebt den Hot-Reload beim Speichern einer Datei
        keepOnReload: true

        bodySupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true
        // Ein Klick auf eine Zeile loest die erste Aktion aus (siehe
        // NotificationRow) – deshalb duerfen Apps welche mitschicken.
        actionsSupported: true

        onNotification: n => {
            n.tracked = true;   // ohne das wird die Notification sofort zerstoert
            root.add(n);
        }
    }

    // Nach einem Reload liegen die behaltenen Nachrichten schon im Server,
    // ohne dass das Signal nochmal feuert – hier wieder einsammeln.
    Component.onCompleted: {
        for (const n of server.trackedNotifications.values)
            if (!root.list.some(e => e.notif === n))
                root.add(n);
    }

    Timer {
        interval: 30000
        running: root.count > 0
        repeat: true
        onTriggered: root.tick++
    }

    // Erreichbar ueber:  qs -c dynamic-island ipc call notifs count
    IpcHandler {
        target: "notifs"

        function count(): int {
            return root.count;
        }

        function clear(): void {
            root.clear();
        }

        function toggleDnd(): bool {
            root.toggleDnd();
            return root.dnd;
        }
    }
}
