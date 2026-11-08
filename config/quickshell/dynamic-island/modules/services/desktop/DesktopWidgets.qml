pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.modules.services.plugins

// Welche Desktop-Widgets es gibt: alle aus Plugins (Manifest `widgets`,
// siehe plugins/README.md) – die Grundausstattung (Uhr, Visualiser, Songtext)
// bringt das Plugin `desktop` selbst mit, weitere kommen als seine
// Komponenten (Manifest `parent: "desktop"`).
//
// Je Typ: { pluginId, title, icon, url, size: [breite, hoehe] in `unit`, options }
// `size` ist nur die Startgroesse fuer die Platzsuche, gezeichnet wird mit
// der implicitWidth/-Height des Widgets.
//
// `options` beschreibt, was die Bearbeitungsleiste anbietet; die Werte
// landen in den `opts` des Widgets in scenes.json:
//   { key: { title, values: [...], default } }   Auswahl (Chips)
//   { key: { title, bool: true, default } }      Schalter
// Farbe und Akzent (`color`, `accent`) hat jedes Widget, die stehen hier nicht.
Singleton {
    id: root

    // Einstellungen des Plugins `desktop` (hidden, pause, fps)
    readonly property var settings: Object.assign({ hidden: false, pause: "fenster", fps: 30 }, Plugins.host("desktop")?.settings ?? {})

    // "Nur im Editor": Widgets ausserhalb der Bearbeitung ausblenden
    function setHidden(hidden: bool): void {
        Plugins.host("desktop")?.context.set("hidden", hidden);
    }

    readonly property var types: Plugins.widgets
    readonly property var typeNames: Object.keys(root.types)

    function info(type: string): var {
        return root.types[type] ?? null;
    }

    // Vorgaben eines Typs als opts-Objekt
    function defaults(type: string): var {
        const out = {};
        const options = root.info(type)?.options ?? {};
        for (const key in options)
            if (options[key].default !== undefined)
                out[key] = options[key].default;
        return out;
    }

    function opt(widget: var, key: string): var {
        const v = widget?.opts?.[key];
        if (v !== undefined)
            return v;
        return root.info(widget?.type)?.options?.[key]?.default;
    }

    // Farbnamen der Leiste -> Farbe. Rollen folgen dem Schema (Wallpaper),
    // Hex-Werte ("#fcee0a") bleiben fest – fuer Szenen mit eigener Optik.
    readonly property var colorNames: ["hell", "primary", "secondary", "tertiary", "weiss", "dunkel"]

    function color(name: string, fallback: color): color {
        switch (name) {
        case "primary": return Colors.primary;
        case "secondary": return Colors.secondary;
        case "tertiary": return Colors.tertiary;
        case "hell": return Colors.fgBackground;
        case "weiss": return "#ffffff";
        case "dunkel": return "#14141a";
        }
        if (typeof name === "string" && /^#[0-9a-fA-F]{6,8}$/.test(name))
            return name;
        return fallback;
    }
}
