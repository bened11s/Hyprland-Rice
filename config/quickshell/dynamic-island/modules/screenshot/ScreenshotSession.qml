pragma ComponentBehavior: Bound
import QtQuick

import qs.modules.services.screenshot

// Der Ausschnitt des Screenshot-Overlays – einer fuer alle Monitore. Er
// gehoert immer genau einem Monitor (`screen`); faengt man auf einem anderen
// Monitor neu an, wandert er dorthin. Koordinaten logisch, relativ zum
// Monitor, ganzzahlig.
QtObject {
    id: session

    property string screen: ""
    property bool has: false
    property int x: 0
    property int y: 0
    property int w: 0
    property int h: 0

    function set(screen: string, x: real, y: real, w: real, h: real): void {
        session.screen = screen;
        session.x = Math.round(x);
        session.y = Math.round(y);
        session.w = Math.round(w);
        session.h = Math.round(h);
        session.has = session.w >= 1 && session.h >= 1;
    }

    function clear(): void {
        session.has = false;
        session.screen = "";
    }

    // Aktion auf dem Ausschnitt: "copy" | "save" | "edit" | "ocr" | "qr" |
    // "record". Der Dienst blendet das Overlay selbst aus.
    function run(action: string): void {
        if (!session.has)
            return;
        if (action === "record")
            Screenshot.record(session.screen, session.x, session.y, session.w, session.h);
        else
            Screenshot.act(action, session.screen, session.x, session.y, session.w, session.h);
    }
}
