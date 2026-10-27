pragma ComponentBehavior: Bound
import QtQuick

import qs
import qs.modules.lock
import qs.modules.services.desktop

// Ein Desktop-Widget auf dem Sperrbildschirm (LockLayout.widgets). Gleiche
// Bindungen wie WidgetHost auf dem Desktop, aber ohne Bearbeiten und ohne
// Eingaben: `enabled: false` – auf der Sperre darf nichts bedienbar sein.
// Groesse wie auf dem Desktop: size multipliziert die Einheit (16 px bei
// 1440 px Hoehe), das Widget waechst also selbst, nicht per scale.
Item {
    id: host

    required property string wid
    property bool active: true
    // Im Anordnungs-Editor: ausgeblendete (widget.hidden) blass zeigen
    property bool preview: false

    readonly property var widget: LockLayout.widget(host.wid)
    readonly property var info: host.widget ? DesktopWidgets.info(host.widget.type) : null
    readonly property real areaW: host.parent?.width ?? 0
    readonly property real areaH: host.parent?.height ?? 0
    readonly property real unit: 16 * host.areaH / 1440
    readonly property real size: LockLayout.scale(host.wid)
    readonly property var opts: Object.assign(DesktopWidgets.defaults(host.widget?.type ?? ""), host.widget?.opts ?? {})
    // Angedockte Widgets (Visualiser "unten") bekommen die volle Breite
    readonly property string dock: loader.item?.dock ?? ""

    width: loader.item?.implicitWidth ?? 0
    height: loader.item?.implicitHeight ?? 0
    x: host.dock !== "" ? 0 : Math.round((host.widget?.x ?? 0.5) * host.areaW - host.width / 2)
    y: host.dock === "unten" ? host.areaH - host.height
     : host.dock === "oben" ? 0
     : Math.round((host.widget?.y ?? 0.5) * host.areaH - host.height / 2)
    visible: host.widget !== null && host.info !== null && (host.preview || !host.widget.hidden)
    enabled: false

    Loader {
        id: loader

        anchors.centerIn: parent
        opacity: host.preview && host.widget?.hidden ? 0.35 : 1
        active: host.info !== null && !LockLayout.excluded.includes(host.widget?.type ?? "")
        source: host.info?.url ?? ""
        asynchronous: false
    }

    Binding {
        target: loader.item
        property: "unit"
        value: host.unit * host.size
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
        value: false
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
    Binding {
        target: loader.item
        property: "plugin"
        value: host.info?.plugin ?? null
        when: loader.item !== null && host.info?.plugin !== undefined && loader.item.plugin !== undefined
    }
}
