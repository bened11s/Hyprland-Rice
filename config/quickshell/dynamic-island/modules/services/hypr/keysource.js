.pragma library

// Was ein Bind der Hypr-Config tut, gelesen aus ihrem Quelltext.
//
// hypr/hyprland.lua schreibt beim Laden je beschriebenem Bind
// "<ref>\t<datei>\t<zeile>" nach ~/.local/state/dynamic-island/
// keybinds-origin.tsv (die Aktion selbst ist in Lua ein undurchsichtiges
// userdata). Hier wird an dieser Stelle der Aufruf `bind(keys, aktion, …)`
// gesucht und sein zweites Argument als Text herausgeschnitten.
//
// Rein funktional, damit es ohne Quickshell testbar ist (node).

// Ausgabe von HyprBinds' origin-Prozess: erst die TSV-Zeilen, dann je Datei
// "\x1e<pfad>\n<inhalt>".
// -> { refs: { <ref>: { file, line } }, files: { <pfad>: <inhalt> } }
function parseOrigins(text) {
    const blocks = String(text).split("\x1e");
    const refs = {};
    for (const row of blocks[0].split("\n")) {
        const cols = row.split("\t");
        if (cols.length < 3 || cols[0] === "")
            continue;
        refs[cols[0]] = { file: cols[1], line: parseInt(cols[2], 10) || 0 };
    }
    const files = {};
    for (const block of blocks.slice(1)) {
        const nl = block.indexOf("\n");
        if (nl < 0)
            continue;
        files[block.slice(0, nl)] = block.slice(nl + 1);
    }
    return { refs, files };
}

// Ende einer langen Lua-Klammer "[==[" ab pos (pos zeigt auf "["), sonst -1
function longBracketLevel(src, pos) {
    if (src[pos] !== "[")
        return -1;
    let i = pos + 1;
    while (src[i] === "=")
        i++;
    return src[i] === "[" ? i - pos - 1 : -1;
}

// Argumente des Aufrufs, dessen "(" bei `open` steht, als Quelltext.
// Beachtet Klammern, Strings, lange Strings und Kommentare.
function callArgs(src, open) {
    const args = [];
    let depth = 0;
    let start = open + 1;
    let i = open + 1;
    while (i < src.length) {
        const c = src[i];
        if (c === "-" && src[i + 1] === "-") {
            const level = longBracketLevel(src, i + 2);
            if (level >= 0) {
                const end = src.indexOf("]" + "=".repeat(level) + "]", i);
                i = end < 0 ? src.length : end + level + 2;
            } else {
                const end = src.indexOf("\n", i);
                i = end < 0 ? src.length : end + 1;
            }
            continue;
        }
        if (c === '"' || c === "'") {
            i++;
            while (i < src.length && src[i] !== c) {
                if (src[i] === "\\")
                    i++;
                i++;
            }
            i++;
            continue;
        }
        if (c === "[") {
            const level = longBracketLevel(src, i);
            if (level >= 0) {
                const end = src.indexOf("]" + "=".repeat(level) + "]", i);
                i = end < 0 ? src.length : end + level + 2;
                continue;
            }
        }
        if (c === "(" || c === "{" || c === "[") {
            depth++;
        } else if (c === ")" || c === "}" || c === "]") {
            if (depth === 0) {
                args.push(src.slice(start, i));
                return args.map(a => a.trim()).filter((a, n) => a !== "" || n > 0);
            }
            depth--;
        } else if (c === "," && depth === 0) {
            args.push(src.slice(start, i));
            start = i + 1;
        }
        i++;
    }
    return null;
}

// Gemeinsame Einrueckung entfernen (mehrzeilige Shell-Skripte in [[ ]])
function dedent(text) {
    const lines = text.replace(/^\n+|\s+$/g, "").split("\n");
    let indent = Infinity;
    for (const l of lines)
        if (l.trim() !== "")
            indent = Math.min(indent, l.match(/^[\t ]*/)[0].length);
    return lines.map(l => l.slice(indent === Infinity ? 0 : indent)).join("\n");
}

// Lua-Stringliteral -> Inhalt, sonst null (Ausdruck wie cfg.terminal)
function luaLiteral(expr) {
    const e = expr.trim();
    const quoted = e.match(/^(["'])((?:\\[\s\S]|(?!\1)[\s\S])*)\1$/);
    if (quoted)
        return quoted[2].replace(/\\(["'\\])/g, "$1").replace(/\\n/g, "\n");
    const level = longBracketLevel(e, 0);
    if (level >= 0) {
        const close = "]" + "=".repeat(level) + "]";
        if (e.endsWith(close))
            return dedent(e.slice(level + 2, e.length - close.length));
    }
    return null;
}

// Kurze Form einer Aktion fuer die Anzeige:
// { kind: "exec"|"global"|"dispatch"|"lua", text, source }
//   exec      hl.dsp.exec_cmd(...)  -> der Befehl (Literal) bzw. der Ausdruck
//   global    hl.dsp.global("x")    -> "x"
//   dispatch  hl.dsp.window.close() -> "window.close()"
//   lua       alles andere (eigene Funktionen wie wsaction("focus", i))
function describeAction(source) {
    const src = source.trim();
    const call = src.match(/^hl\.dsp\.([\w.]+)\s*\(/);
    if (call) {
        const args = callArgs(src, call[0].length - 1) ?? [];
        if (call[1] === "exec_cmd" && args.length > 0) {
            // Verkettete Befehle ("a" .. cfg.x .. "b") bleiben als Ausdruck
            const literal = luaLiteral(args[0]);
            return { kind: "exec", text: literal ?? args[0], source: src };
        }
        if (call[1] === "global" && args.length > 0)
            return { kind: "global", text: luaLiteral(args[0]) ?? args[0], source: src };
        return { kind: "dispatch", text: src.slice("hl.dsp.".length).replace(/\s+/g, " "), source: src };
    }
    return { kind: "lua", text: src.replace(/\s+/g, " "), source: src };
}

// Aufruf eines Binds ab Zeile `line` (1-basiert). Lua meldet bei
// mehrzeiligen Aufrufen die Zeile der oeffnenden Klammer; zur Sicherheit
// auch ein paar Zeilen davor suchen.
// -> { keys, action: describeAction(...) } | null
function actionAt(content, line) {
    if (!content || !(line > 0))
        return null;
    const lines = String(content).split("\n");
    const offsets = [0];
    for (let n = 0; n < lines.length; n++)
        offsets.push(offsets[n] + lines[n].length + 1);
    const pattern = /\b(?:bind|bind_described)\s*\(/g;
    for (let back = 0; back < 4 && line - 1 - back >= 0; back++) {
        const n = line - 1 - back;
        pattern.lastIndex = 0;
        const m = pattern.exec(lines[n]);
        if (!m)
            continue;
        const open = offsets[n] + m.index + m[0].length - 1;
        const args = callArgs(String(content), open);
        if (!args || args.length < 2)
            return null;
        return { keys: luaLiteral(args[0]) ?? args[0], action: describeAction(args[1]) };
    }
    return null;
}
