.pragma library

// Datenmodell des Looks-Editors: look.json bearbeiten, ohne looks.py zu fragen.
// Gleiche Regeln wie dort (siehe Kopf von looks.py):
//   rows[i] = { m: Modul | "break", sizes: { SIZE: false | Patch | {"=": Wert} } }
//   Patch mischt sich rekursiv in m, null loescht einen Schluessel.
// Alle Funktionen geben neue Objekte zurueck und lassen die Eingabe in Ruhe –
// so bleibt jede Aenderung eine Zuweisung (Bindungen feuern).
//
// Markup in Texten: <@name> Palettenfarbe, <#rrggbb>, <b> <i> <d> <u>,
// </> zuruecksetzen, mehrere mit Leerzeichen (<b @primary>), << = "<".

var SIZES = ["config", "compact", "mini"];

function clone(v) {
    return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
}

function isObj(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function equal(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
}

// ---- Patches ----

function merge(base, patch) {
    if (!isObj(base) || !isObj(patch))
        return clone(patch);
    const out = clone(base);
    for (const k in patch) {
        const v = patch[k];
        if (v === null)
            delete out[k];
        else if (isObj(v) && isObj(out[k]))
            out[k] = merge(out[k], v);
        else
            out[k] = clone(v);
    }
    return out;
}

function diff(base, target) {
    const p = {};
    for (const k in base)
        if (!(k in target))
            p[k] = null;
    for (const k in target) {
        const v = target[k];
        if (!(k in base))
            p[k] = clone(v);
        else if (isObj(v) && isObj(base[k])) {
            const d = diff(base[k], v);
            if (Object.keys(d).length)
                p[k] = d;
        } else if (!equal(v, base[k]))
            p[k] = clone(v);
    }
    return p;
}

// ---- Zeilen ----

// Modul der Zeile in SIZE oder null, wenn sie dort fehlt
function rowValue(row, size) {
    const s = (row.sizes || {})[size];
    if (s === false)
        return null;
    if (s === undefined || s === null)
        return clone(row.m);
    if (isObj(s) && "=" in s)
        return clone(s["="]);
    if (isObj(row.m) && isObj(s))
        return merge(row.m, s);
    return null;
}

function present(row, size) {
    return (row.sizes || {})[size] !== false;
}

function rowPatch(m, v) {
    if (equal(m, v))
        return undefined;
    if (isObj(m) && isObj(v) && !("=" in v))
        return diff(m, v);
    return { "=": clone(v) };
}

function withSizes(row, sizes) {
    const out = { m: clone(row.m) };
    const keys = Object.keys(sizes).filter(k => sizes[k] !== undefined);
    if (keys.length) {
        out.sizes = {};
        for (const k of keys)
            out.sizes[k] = sizes[k];
    }
    return out;
}

// Zeile in SIZE zeigen/verstecken. Beim Zeigen erbt sie wieder von m.
function setPresent(row, size, on) {
    const sizes = clone(row.sizes || {});
    if (on) {
        if (sizes[size] === false)
            delete sizes[size];
    } else {
        sizes[size] = false;
    }
    return withSizes(row, sizes);
}

// Wert der Zeile in SIZE ersetzen.
//   scope "size": nur diese Groesse (Patch gegen m)
//   scope "all":  die geaenderten Felder in allen Groessen (in m, und aus
//                 den Patches der Groessen entfernt, damit sie erben)
function setRow(row, size, value, scope) {
    if (scope !== "all") {
        const sizes = clone(row.sizes || {});
        const p = rowPatch(row.m, value);
        if (p === undefined)
            delete sizes[size];
        else
            sizes[size] = p;
        return withSizes(row, sizes);
    }
    const old = rowValue(row, size);
    if (!isObj(old) || !isObj(value) || !isObj(row.m)) {
        // "break" <-> Modul: ganze Zeile tauschen
        return { m: clone(value) };
    }
    const d = diff(old, value);
    const m = merge(row.m, d);
    const sizes = {};
    for (const k in (row.sizes || {})) {
        let s = row.sizes[k];
        if (s === false) {
            sizes[k] = false;
            continue;
        }
        if (isObj(s) && "=" in s) {
            sizes[k] = { "=": merge(s["="], d) };
            continue;
        }
        s = clone(s);
        for (const f in d)
            delete s[f];
        if (Object.keys(s).length)
            sizes[k] = s;
    }
    return withSizes({ m: m }, sizes);
}

// Feld einer Zeile in SIZE setzen (value undefined/null = Feld entfernen)
function setField(row, size, field, value, scope) {
    const cur = rowValue(row, size) ?? clone(row.m);
    if (!isObj(cur))
        return row;
    const next = clone(cur);
    if (value === undefined || value === null)
        delete next[field];
    else
        next[field] = value;
    return setRow(row, size, next, scope);
}

// ---- Look ----

function withRows(look, rows) {
    const out = clone(look);
    out.rows = rows;
    return out;
}

function replaceRow(look, index, row) {
    const rows = look.rows.slice();
    rows[index] = row;
    return withRows(look, rows);
}

// Neue Zeile hinter index (-1 = vorne); sichtbar nur in den Groessen `only`
// (leer/undefined = in allen)
function addRow(look, index, module, only) {
    const row = { m: clone(module) };
    if (only && only.length) {
        row.sizes = {};
        for (const s of SIZES)
            if (!only.includes(s))
                row.sizes[s] = false;
    }
    const rows = look.rows.slice();
    rows.splice(index + 1, 0, row);
    return withRows(look, rows);
}

function removeRow(look, index) {
    const rows = look.rows.slice();
    rows.splice(index, 1);
    return withRows(look, rows);
}

function moveRow(look, from, to) {
    if (from === to || from < 0 || to < 0 || from >= look.rows.length || to >= look.rows.length)
        return look;
    const rows = look.rows.slice();
    const r = rows.splice(from, 1)[0];
    rows.splice(to, 0, r);
    return withRows(look, rows);
}

// Indizes der Zeilen, die in SIZE vorkommen (Reihenfolge der Ausgabe)
function rowsIn(look, size) {
    const out = [];
    for (let i = 0; i < look.rows.length; i++)
        if (present(look.rows[i], size))
            out.push(i);
    return out;
}

// Wirksame display-Einstellungen etc. einer Groesse (ohne modules)
function sizeConf(look, size) {
    const sz = (look.sizes || {})[size] || {};
    return merge(look.base, sz.patch || {});
}

// Feld unter base (Pfad als Array) fuer SIZE setzen: config aendert base,
// die anderen Groessen bekommen einen Patch (gleich base = Patch weg)
function setConf(look, size, path, value) {
    const out = clone(look);
    out.sizes = out.sizes || {};
    if (size === "config") {
        let o = out.base;
        for (let i = 0; i < path.length - 1; i++) {
            if (!isObj(o[path[i]]))
                o[path[i]] = {};
            o = o[path[i]];
        }
        if (value === undefined || value === null)
            delete o[path[path.length - 1]];
        else
            o[path[path.length - 1]] = clone(value);
        return out;
    }
    const target = sizeConf(look, size);
    let o = target;
    for (let i = 0; i < path.length - 1; i++) {
        if (!isObj(o[path[i]]))
            o[path[i]] = {};
        o = o[path[i]];
    }
    if (value === undefined || value === null)
        delete o[path[path.length - 1]];
    else
        o[path[path.length - 1]] = clone(value);
    const p = diff(out.base, target);
    const sz = clone(out.sizes[size] || {});
    if (Object.keys(p).length)
        sz.patch = p;
    else
        delete sz.patch;
    out.sizes[size] = sz;
    return out;
}

function getPath(obj, path) {
    let o = obj;
    for (const k of path) {
        if (o === null || o === undefined)
            return undefined;
        o = o[k];
    }
    return o;
}

// ---- Palette ----

// Farbe umbenennen: auch alle Verweise (<@alt>, "@alt" in Farbfeldern)
function renamePalette(look, from, to) {
    if (from === to || !(from in look.palette) || to in look.palette || !/^[A-Za-z][A-Za-z0-9_-]{0,31}$/.test(to))
        return look;
    const re = new RegExp("@" + from.replace(/[-]/g, "\\-") + "(?![A-Za-z0-9_-])", "g");
    const walk = v => {
        if (typeof v === "string")
            return v.replace(re, "@" + to);
        if (Array.isArray(v))
            return v.map(walk);
        if (isObj(v)) {
            const o = {};
            for (const k in v)
                o[k] = walk(v[k]);
            return o;
        }
        return v;
    };
    const out = walk(clone(look));
    const pal = {};
    for (const k in look.palette)
        pal[k === from ? to : k] = look.palette[k];
    out.palette = pal;
    return out;
}

// Wird die Farbe noch benutzt? (vor dem Loeschen fragen)
function paletteUses(look, name) {
    const re = new RegExp("@" + name.replace(/[-]/g, "\\-") + "(?![A-Za-z0-9_-])");
    const copy = clone(look);
    delete copy.palette;
    return re.test(JSON.stringify(copy));
}

// ---- Markup ----

var TAG = /<<|<([^<>]*)>/g;

function emptyStyle() {
    return { color: "", bold: false, italic: false, dim: false, underline: false, extra: [] };
}

// Markup -> [{text, color, bold, italic, dim, underline, extra}]
// color: "@name", "#rrggbb" oder "" (Standard); extra: unbekannte Teile
function parse(markup) {
    const segs = [];
    let st = emptyStyle();
    let buf = "";
    let pos = 0;
    const flush = () => {
        if (buf.length) {
            segs.push(Object.assign({ text: buf }, clone(st)));
            buf = "";
        }
    };
    TAG.lastIndex = 0;
    let m;
    while ((m = TAG.exec(markup)) !== null) {
        buf += markup.slice(pos, m.index);
        pos = TAG.lastIndex;
        if (m[0] === "<<") {
            buf += "<";
            continue;
        }
        flush();
        for (const part of m[1].split(/\s+/).filter(p => p)) {
            if (part === "/")
                st = emptyStyle();
            else if (part === "b")
                st.bold = true;
            else if (part === "i")
                st.italic = true;
            else if (part === "d")
                st.dim = true;
            else if (part === "u")
                st.underline = true;
            else if (part[0] === "@" || part[0] === "#")
                st.color = part;
            else
                st.extra.push(part);
        }
    }
    buf += markup.slice(pos);
    flush();
    return segs;
}

function styleParts(s) {
    const parts = [];
    if (s.bold)
        parts.push("b");
    if (s.italic)
        parts.push("i");
    if (s.dim)
        parts.push("d");
    if (s.underline)
        parts.push("u");
    for (const e of (s.extra || []))
        parts.push(e);
    if (s.color)
        parts.push(s.color);
    return parts;
}

// Segmente -> Markup (jedes gestylte Segment mit eigenem Tag und </>)
function format(segs) {
    let out = "";
    for (const s of segs) {
        const text = String(s.text ?? "").replace(/</g, "<<");
        const parts = styleParts(s);
        out += parts.length ? `<${parts.join(" ")}>${text}</>` : text;
    }
    return out;
}

// Sichtbarer Text ohne Tags
function plain(markup) {
    return String(markup ?? "").replace(TAG, (m0) => m0 === "<<" ? "<" : "");
}

// Breite in Zellen (Nerd-Glyphen = 1, CJK/Emoji = 2) – wie looks.py
function cellWidth(text) {
    let w = 0;
    for (const ch of String(text)) {
        const c = ch.codePointAt(0);
        if ((c >= 0x0300 && c <= 0x036f) || c === 0x200d || (c >= 0xfe00 && c <= 0xfe0f))
            continue;
        const wide = (c >= 0x1100 && c <= 0x115f) || (c >= 0x2e80 && c <= 0xa4cf) || (c >= 0xac00 && c <= 0xd7a3)
            || (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe30 && c <= 0xfe4f) || (c >= 0xff00 && c <= 0xff60)
            || (c >= 0xffe0 && c <= 0xffe6) || (c >= 0x1f300 && c <= 0x1faff) || (c >= 0x20000 && c <= 0x3fffd);
        w += wide ? 2 : 1;
    }
    return w;
}

function resolveColor(color, palette, fallback) {
    if (!color)
        return fallback ?? "";
    if (color[0] === "@")
        return (palette || {})[color.slice(1)] ?? fallback ?? "";
    return color;
}

function escapeHtml(t) {
    return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/ /g, "&nbsp;");
}

function segHtml(text, color, bold, italic, dim, underline) {
    let h = escapeHtml(text);
    if (underline)
        h = `<u>${h}</u>`;
    if (italic)
        h = `<i>${h}</i>`;
    if (bold)
        h = `<b>${h}</b>`;
    if (color)
        h = `<font color="${color}">${h}</font>`;
    else if (dim)
        h = `<font color="#80808080">${h}</font>`;
    return h;
}

// Markup -> Rich Text fuer ein QML-Text (textFormat: Text.StyledText)
function html(markup, palette, defaultColor) {
    return parse(String(markup ?? "")).map(s =>
        segHtml(s.text, resolveColor(s.color, palette, defaultColor), s.bold, s.italic, s.dim, s.underline)).join("");
}

// Vorschau-Zeilen aus `looks.py preview` -> ein Rich-Text-Block
function previewHtml(lines, defaultColor) {
    return lines.map(l => l.map(s => segHtml(s.t, s.fg || defaultColor || "", s.b, s.i, s.d, s.u)).join("") || "&nbsp;")
        .join("<br>");
}

// ---- Keys ----

// Uebliche Key-Breite einer Groesse (die Keys sind von Hand aufgefuellt)
function keyWidth(look, size) {
    const counts = {};
    for (const i of rowsIn(look, size)) {
        const v = rowValue(look.rows[i], size);
        if (isObj(v) && typeof v.key === "string") {
            const w = cellWidth(plain(v.key));
            counts[w] = (counts[w] || 0) + 1;
        }
    }
    let best = 0, n = 0;
    for (const w in counts)
        if (counts[w] > n) {
            n = counts[w];
            best = Number(w);
        }
    return best;
}

// Key auf Breite auffuellen (Markup bleibt; nur Leerzeichen hinten)
function padKey(key, width) {
    const w = cellWidth(plain(key));
    return w >= width ? key : key + " ".repeat(width - w);
}

// ---- Module zum Hinzufuegen ----

// type, Titel (deutsch, fuer I18n.tr), Vorgabe fuer key/format
var MODULES = [
    { type: "custom", title: "Eigener Text", format: "<@primary>Text</>" },
    { type: "break", title: "Leerzeile" },
    { type: "title", title: "Benutzer@Rechner", key: "User", format: "{user-name}@{host-name}" },
    { type: "os", title: "System", key: "OS", format: "{pretty-name}" },
    { type: "kernel", title: "Kernel", key: "Kernel", format: "{release}" },
    { type: "uptime", title: "Laufzeit", key: "Uptime" },
    { type: "packages", title: "Pakete", key: "Packages", format: "{all}" },
    { type: "wm", title: "Fenstermanager", key: "WM", format: "{pretty-name}" },
    { type: "de", title: "Desktop", key: "DE" },
    { type: "shell", title: "Shell", key: "Shell", format: "{pretty-name} {version}" },
    { type: "terminal", title: "Terminal", key: "Terminal", format: "{pretty-name}" },
    { type: "terminalfont", title: "Terminal-Schrift", key: "Font" },
    { type: "cpu", title: "Prozessor", key: "CPU", format: "{name}" },
    { type: "gpu", title: "Grafikkarte", key: "GPU", format: "{name}", hideType: "integrated" },
    { type: "memory", title: "Arbeitsspeicher", key: "RAM", format: "{percentage-bar} {used} / {total}" },
    { type: "swap", title: "Auslagerung", key: "Swap" },
    { type: "disk", title: "Festplatte", key: "Disk", format: "{size-percentage-bar} {size-used} / {size-total}", folders: "/" },
    { type: "display", title: "Bildschirme", key: "Display" },
    { type: "localip", title: "Lokale IP", key: "IP" },
    { type: "battery", title: "Akku", key: "Battery" },
    { type: "media", title: "Musik", key: "Music", format: "{combined:-40}" },
    { type: "datetime", title: "Datum und Uhrzeit", key: "Time" },
    { type: "locale", title: "Sprache", key: "Locale" },
    { type: "theme", title: "Theme", key: "Theme" },
    { type: "icons", title: "Symbole", key: "Icons" },
    { type: "font", title: "Schrift", key: "Font" },
    { type: "cursor", title: "Mauszeiger", key: "Cursor" },
    { type: "command", title: "Befehl", key: "Cmd", text: "echo hallo" },
    { type: "colors", title: "Farbbalken", symbol: "block" }
];

// Nerd-Font-Symbole je Modul (Material Design, wie in den bestehenden Looks)
var ICONS = {
    title: "\u{f0004}",
    os: "\u{f08c7}",
    kernel: "\u{f048b}",
    uptime: "\u{f13ab}",
    packages: "\u{f03d7}",
    wm: "\u{f056e}",
    shell: "\u{f018d}",
    terminal: "\u{f011b}",
    cpu: "\u{f0ee0}",
    gpu: "\u{f035b}",
    memory: "\u{f061a}",
    disk: "\u{f02ca}",
    media: "\u{f0388}",
    de: "\u{f0379}",
    terminalfont: "\u{f0b34}",
    swap: "\u{f04c5}",
    display: "\u{f0379}",
    localip: "\u{f0317}",
    battery: "\u{f0079}",
    datetime: "\u{f00f0}",
    locale: "\u{f05ca}",
    theme: "\u{f03d8}",
    icons: "\u{f02e9}",
    font: "\u{f0b34}",
    cursor: "\u{f01bf}",
    command: "\u{f018d}"
};

// Neues Modul aus dem Katalog, Key im Stil der anderen Keys der Groesse:
// gleicher Einzug, Symbol davor, wenn die anderen eins haben, Grossbuchstaben,
// wenn die anderen gross sind, aufgefuellt auf die uebliche Breite
function makeModule(type, look, size) {
    const def = MODULES.find(m => m.type === type);
    if (!def || type === "break")
        return "break";
    const m = { type: type };
    for (const k in def)
        if (k !== "type" && k !== "title")
            m[k] = def[k];
    if (typeof m.key === "string") {
        const keys = rowsIn(look, size).map(i => rowValue(look.rows[i], size))
            .filter(v => isObj(v) && typeof v.key === "string").map(v => plain(v.key));
        const indent = keys.length ? keys[0].match(/^ */)[0] : "";
        const words = keys.map(k => k.trim().replace(/^[^\x00-\x7f]+\s+/u, "")).filter(k => /[A-Za-z]/.test(k));
        const upper = words.length > 0 && words.filter(k => k === k.toUpperCase()).length * 2 > words.length;
        const iconed = keys.length > 0 && keys.filter(k => /^\s*[^\x00-\x7f]\s/u.test(k)).length * 2 > keys.length;
        let key = upper ? m.key.toUpperCase() : m.key;
        if (iconed && ICONS[type])
            key = ICONS[type] + " " + key;
        m.key = padKey(indent + key, keyWidth(look, size));
    }
    return m;
}
