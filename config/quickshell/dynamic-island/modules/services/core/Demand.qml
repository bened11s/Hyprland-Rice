pragma ComponentBehavior: Bound
import QtQuick

// Sammelt Anforderungen an einen Dienst, der nur laufen soll, solange ihn
// jemand braucht (cava, Systemwerte, WLAN-Status, ...).
//
// Frueher setzte jeder Verbraucher die Dienst-Property per `Binding`. Unter
// `Variants` gibt es die Verbraucher aber je Monitor – zwei Bindings auf
// dieselbe Property ueberschreiben sich, es gewinnt der zuletzt geaenderte
// Monitor. Hier meldet jeder Verbraucher seinen eigenen Wunsch an
// (`DemandRequest`), aktiv ist der Dienst, solange irgendeiner will.
//
//     // im Dienst
//     readonly property Demand demand: Demand {}
//     readonly property bool enabled: root.demand.active
//
//     // beim Verbraucher
//     DemandRequest { demand: Cava.demand; active: Media.playing && shown }
QtObject {
    id: root

    property var requests: ({})
    property int nextId: 0
    readonly property bool active: Object.keys(root.requests).length > 0

    function newKey(): string {
        return "r" + root.nextId++;
    }

    function set(key: string, on: bool): void {
        if (!!root.requests[key] === on)
            return;
        const next = Object.assign({}, root.requests);
        if (on)
            next[key] = true;
        else
            delete next[key];
        root.requests = next;
    }
}
