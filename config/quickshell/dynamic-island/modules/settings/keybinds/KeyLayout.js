.pragma library

// Tastatur-Vorschau der Einstellungsseite Tastenkürzel: deutsches ISO-QWERTZ
// in voller Groesse (100 %, mit Ziffernblock). Jede Taste traegt ihre xkb-ID
// klein, so wie HyprBinds sie in combo.key liefert (escape, f1,
// dead_circumflex, ssharp, kp_7, …). Masse in Tasteneinheiten (1u = eine
// Buchstabentaste).
//
//   { id, label, sub, alt, x, y, w, h, mod }
//   label  Hauptlegende, sub  Shift-Zeichen (oben), alt  AltGr-Zeichen bzw.
//          Zweitfunktion (unten rechts, klein)
//   mod    Modifier-Bit der Hyprland-Modmaske (Shift 1, Strg 4, Alt 8, Super 64)
//
// ISO-Enter ist zwei Zeilen hoch und oben breiter – die Vorschau zeichnet
// ihn als Sonderform (iso: true), hier steht er mit der oberen Breite.

// Hauptblock 15u | 0,5u | Nav 3u | 0,5u | Ziffernblock 4u
var NAV_X = 15.5;
var NUM_X = 19;
var UNITS_WIDE = 23;
var UNITS_HIGH = 6.5;

var MODS = [
    { bit: 64, name: "SUPER", label: "Super" },
    { bit: 4, name: "CTRL", label: "Strg" },
    { bit: 8, name: "ALT", label: "Alt" },
    { bit: 1, name: "SHIFT", label: "Shift" }
];

// xkb-Schreibweise, wie Keybinds.fromEvent sie speichert (Hyprland vergleicht
// Tastennamen ohne Gross/Klein, so bleiben Config und Aufnahme einheitlich)
var XKB = {
    escape: "Escape", print: "Print", scroll_lock: "Scroll_Lock", pause: "Pause",
    dead_circumflex: "dead_circumflex", ssharp: "ssharp", dead_acute: "dead_acute",
    backspace: "BackSpace", insert: "Insert", home: "Home", prior: "Prior",
    tab: "Tab", udiaeresis: "udiaeresis", plus: "plus", "return": "Return",
    "delete": "Delete", end: "End", next: "Next", caps_lock: "Caps_Lock",
    odiaeresis: "odiaeresis", adiaeresis: "adiaeresis", numbersign: "numbersign",
    less: "less", comma: "comma", period: "period", minus: "minus",
    up: "up", down: "down", left: "left", right: "right", space: "space",
    menu: "Menu", super_l: "SUPER_L", super_r: "SUPER_R",
    num_lock: "Num_Lock", kp_divide: "KP_Divide", kp_multiply: "KP_Multiply",
    kp_subtract: "KP_Subtract", kp_add: "KP_Add", kp_enter: "KP_Enter", kp_decimal: "KP_Decimal",
    kp_0: "KP_0", kp_1: "KP_1", kp_2: "KP_2", kp_3: "KP_3", kp_4: "KP_4",
    kp_5: "KP_5", kp_6: "KP_6", kp_7: "KP_7", kp_8: "KP_8", kp_9: "KP_9",
    xf86audiomute: "XF86AudioMute", xf86audiomicmute: "XF86AudioMicMute",
    xf86audiolowervolume: "XF86AudioLowerVolume", xf86audioraisevolume: "XF86AudioRaiseVolume",
    xf86audioprev: "XF86AudioPrev", xf86audioplay: "XF86AudioPlay", xf86audionext: "XF86AudioNext",
    xf86monbrightnessdown: "XF86MonBrightnessDown", xf86monbrightnessup: "XF86MonBrightnessUp"
};

function xkbName(id) {
    if (XKB[id] !== undefined)
        return XKB[id];
    if (/^f\d+$/.test(id))
        return id.toUpperCase();
    return id.length === 1 ? id.toUpperCase() : id;
}

// Tasten, die sich nicht als Ziel beim "Auf Tastatur waehlen" eignen:
// Modifier, AltGr, Feststell, Num
function pickable(id) {
    var all = keys();
    for (var i = 0; i < all.length; i++)
        if (all[i].id === id)
            return all[i].mod === 0 && !all[i].noPick;
    return true;
}

// Tasten, die allein (ohne Super/Strg/Alt) gebunden werden duerfen – wie
// Keybinds.fromEvent
function standalone(id) {
    return /^(f\d+|xf86\w+|print|pause|insert)$/.test(id);
}

// Modmaske + Tasten-ID -> "SUPER + ALT + W" (fuer KeyCapture.saveAs)
function keysText(mask, id) {
    var out = [];
    for (var i = 0; i < MODS.length; i++)
        if (mask & MODS[i].bit)
            out.push(MODS[i].name);
    out.push(xkbName(id));
    return out.join(" + ");
}

// Modmaske -> ["Super", "Alt"] (Anzeige, Beschriftungen gehen durch I18n.tr)
function modLabels(mask) {
    var out = [];
    for (var i = 0; i < MODS.length; i++)
        if (mask & MODS[i].bit)
            out.push(MODS[i].label);
    return out;
}

// Zweitnamen -> physische Taste: AltGr-Zeichen (backslash leuchtet auf ß)
// und Ziffernblock ohne Num (kp_home = kp_7). Der Tooltip nennt die echte
// Kombination.
var ALIAS = {
    backslash: "ssharp", bar: "less", at: "q", braceleft: "7", bracketleft: "8",
    bracketright: "9", braceright: "0", asciitilde: "plus", eurosign: "e", euro: "e",
    mu: "m", twosuperior: "2", threesuperior: "3",
    kp_home: "kp_7", kp_up: "kp_8", kp_prior: "kp_9", kp_left: "kp_4", kp_begin: "kp_5",
    kp_right: "kp_6", kp_end: "kp_1", kp_down: "kp_2", kp_next: "kp_3", kp_insert: "kp_0",
    kp_delete: "kp_decimal", kp_separator: "kp_decimal"
};

// Umkehrung: physische Taste -> [Zweitnamen]
var ALIAS_OF = null;

function aliasesOf(id) {
    if (!ALIAS_OF) {
        ALIAS_OF = {};
        for (var k in ALIAS) {
            if (!ALIAS_OF[ALIAS[k]])
                ALIAS_OF[ALIAS[k]] = [];
            ALIAS_OF[ALIAS[k]].push(k);
        }
    }
    return ALIAS_OF[id] || [];
}

function key(id, label, x, y, w, extra) {
    var k = { id: id, label: label, sub: "", alt: "", x: x, y: y, w: w === undefined ? 1 : w, h: 1, mod: 0 };
    if (extra)
        for (var p in extra)
            k[p] = extra[p];
    return k;
}

function row(ids, labels, x, y, subs, alts) {
    var out = [];
    for (var i = 0; i < ids.length; i++)
        out.push(key(ids[i], labels[i], x + i, y, 1, { sub: subs ? subs[i] : "", alt: alts ? alts[i] : "" }));
    return out;
}

var _keys = null;

function keys() {
    if (_keys)
        return _keys;
    var k = [];
    var y = 0;
    // Funktionsreihe: Esc | 1u | F1–F4 | 0,5u | F5–F8 | 0,5u | F9–F12 || Druck Rollen Pause
    k.push(key("escape", "Esc", 0, y));
    for (var i = 0; i < 12; i++)
        k.push(key("f" + (i + 1), "F" + (i + 1), 2 + i + Math.floor(i / 4) * 0.5, y));
    k.push(key("print", "Druck", NAV_X, y));
    k.push(key("scroll_lock", "Rollen", NAV_X + 1, y));
    k.push(key("pause", "Pause", NAV_X + 2, y));
    // Zahlenreihe
    y = 1.5;
    k = k.concat(row(["dead_circumflex", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "ssharp", "dead_acute"],
                     ["^", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "ß", "´"], 0, y,
                     ["°", "!", "\"", "§", "$", "%", "&", "/", "(", ")", "=", "?", "`"],
                     ["", "", "²", "³", "", "", "", "{", "[", "]", "}", "\\", ""]));
    k.push(key("backspace", "⌫", 13, y, 2));
    k.push(key("insert", "Einfg", NAV_X, y));
    k.push(key("home", "Pos1", NAV_X + 1, y));
    k.push(key("prior", "Bild↑", NAV_X + 2, y));
    k.push(key("num_lock", "Num", NUM_X, y, 1, { noPick: true }));
    k.push(key("kp_divide", "/", NUM_X + 1, y));
    k.push(key("kp_multiply", "*", NUM_X + 2, y));
    k.push(key("kp_subtract", "-", NUM_X + 3, y));
    // Tab-Reihe
    y = 2.5;
    k.push(key("tab", "Tab", 0, y, 1.5));
    k = k.concat(row(["q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "udiaeresis", "plus"],
                     ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "Ü", "+"], 1.5, y,
                     ["", "", "", "", "", "", "", "", "", "", "", "*"],
                     ["@", "", "€", "", "", "", "", "", "", "", "", "~"]));
    k.push(key("return", "Enter", 13.5, y, 1.5, { h: 2, iso: true, lowerX: 13.75, lowerW: 1.25 }));
    k.push(key("delete", "Entf", NAV_X, y));
    k.push(key("end", "Ende", NAV_X + 1, y));
    k.push(key("next", "Bild↓", NAV_X + 2, y));
    k.push(key("kp_7", "7", NUM_X, y, 1, { alt: "Pos1" }));
    k.push(key("kp_8", "8", NUM_X + 1, y, 1, { alt: "↑" }));
    k.push(key("kp_9", "9", NUM_X + 2, y, 1, { alt: "Bild↑" }));
    k.push(key("kp_add", "+", NUM_X + 3, y, 1, { h: 2 }));
    // Grundreihe
    y = 3.5;
    k.push(key("caps_lock", "Feststell", 0, y, 1.75, { noPick: true }));
    k = k.concat(row(["a", "s", "d", "f", "g", "h", "j", "k", "l", "odiaeresis", "adiaeresis", "numbersign"],
                     ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ö", "Ä", "#"], 1.75, y,
                     ["", "", "", "", "", "", "", "", "", "", "", "'"], null));
    k.push(key("kp_4", "4", NUM_X, y, 1, { alt: "←" }));
    k.push(key("kp_5", "5", NUM_X + 1, y));
    k.push(key("kp_6", "6", NUM_X + 2, y, 1, { alt: "→" }));
    // Shift-Reihe
    y = 4.5;
    k.push(key("shift_l", "Shift", 0, y, 1.25, { mod: 1 }));
    k.push(key("less", "<", 1.25, y, 1, { sub: ">", alt: "|" }));
    k = k.concat(row(["y", "x", "c", "v", "b", "n", "m", "comma", "period", "minus"],
                     ["Y", "X", "C", "V", "B", "N", "M", ",", ".", "-"], 2.25, y,
                     ["", "", "", "", "", "", "", ";", ":", "_"],
                     ["", "", "", "", "", "", "µ", "", "", ""]));
    k.push(key("shift_r", "Shift", 12.25, y, 2.75, { mod: 1 }));
    k.push(key("up", "↑", NAV_X + 1, y));
    k.push(key("kp_1", "1", NUM_X, y, 1, { alt: "Ende" }));
    k.push(key("kp_2", "2", NUM_X + 1, y, 1, { alt: "↓" }));
    k.push(key("kp_3", "3", NUM_X + 2, y, 1, { alt: "Bild↓" }));
    k.push(key("kp_enter", "Enter", NUM_X + 3, y, 1, { h: 2 }));
    // Untere Reihe
    y = 5.5;
    k.push(key("control_l", "Strg", 0, y, 1.25, { mod: 4 }));
    k.push(key("super_l", "Super", 1.25, y, 1.25, { mod: 64 }));
    k.push(key("alt_l", "Alt", 2.5, y, 1.25, { mod: 8 }));
    k.push(key("space", "", 3.75, y, 6.25));
    k.push(key("iso_level3_shift", "AltGr", 10, y, 1.25, { noPick: true }));
    k.push(key("super_r", "Super", 11.25, y, 1.25, { mod: 64 }));
    k.push(key("menu", "Menü", 12.5, y, 1.25));
    k.push(key("control_r", "Strg", 13.75, y, 1.25, { mod: 4 }));
    k.push(key("left", "←", NAV_X, y));
    k.push(key("down", "↓", NAV_X + 1, y));
    k.push(key("right", "→", NAV_X + 2, y));
    k.push(key("kp_0", "0", NUM_X, y, 2, { alt: "Einfg" }));
    k.push(key("kp_decimal", ",", NUM_X + 2, y, 1, { alt: "Entf" }));
    _keys = k;
    return k;
}

var _ids = null;

// Menge aller IDs auf der Tastatur (fuer "sitzt nirgends")
function onBoard(id) {
    if (!_ids) {
        _ids = {};
        var all = keys();
        for (var i = 0; i < all.length; i++)
            _ids[all[i].id] = true;
    }
    return _ids[id] === true || ALIAS[id] !== undefined;
}

// Medienknoepfe im Gehaeuse (oben rechts ueber dem Ziffernblock), Lautstaerke als Walze
var MEDIA = [
    { id: "xf86audiomicmute", icon: "mic_off", title: "Mikro stumm" },
    { id: "xf86audiomute", icon: "volume_off", title: "Stumm" },
    { id: "xf86audioprev", icon: "skip_previous", title: "Zurück" },
    { id: "xf86audioplay", icon: "play_pause", title: "Play/Pause" },
    { id: "xf86audionext", icon: "skip_next", title: "Weiter" },
    { id: "xf86monbrightnessdown", icon: "brightness_low", title: "Dunkler" },
    { id: "xf86monbrightnessup", icon: "brightness_high", title: "Heller" }
];
var ROLLER = ["xf86audiolowervolume", "xf86audioraisevolume"];

var MOUSE = ["mouse:272", "mouse:273", "mouse:274", "mouse_up", "mouse_down"];
var MOUSE_NAMES = {
    "mouse:272": "Linksklick", "mouse:273": "Rechtsklick", "mouse:274": "Mittelklick",
    mouse_up: "Rad ↑", mouse_down: "Rad ↓"
};

function isMouse(id) {
    return id.indexOf("mouse") === 0;
}

function isMedia(id) {
    if (ROLLER.indexOf(id) >= 0)
        return true;
    for (var i = 0; i < MEDIA.length; i++)
        if (MEDIA[i].id === id)
            return true;
    return false;
}
