//! Folder looks for fastfetch, the editor of the terminal plugin.
//!
//! Each operation writes exactly one JSON line to stdout: `{"ok": true, ...}` or
//! `{"ok": false, "error": "..."}`. The operations are listed in `looks.py`.
//!
//! Generated files have to match the Python version byte for byte, because
//! `look.json` keeps their sha256 under `generated`. A different byte would make
//! every look show up as edited by hand.

mod diff;
mod import;
mod markup;
mod palette;
mod preview;
mod unicode_table;

use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::LazyLock;

use di_common::fsutil::{copy2, read_text};
use di_common::paths;
use di_common::pyjson::{self, dumps, text_of, truthy};
use regex::Regex;
use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};

pub const SIZES: [&str; 3] = ["config", "compact", "mini"];

static ID_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-z0-9][a-z0-9._-]{0,63}\n?\z").unwrap());
static NAME_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z][A-Za-z0-9_-]{0,31}\n?\z").unwrap());
static HEX_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^#[0-9a-fA-F]{6}\n?\z").unwrap());
static COLOR_ARG_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^#?[0-9a-fA-F]{6}\n?\z").unwrap());
static SCHEME_HEX_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[0-9a-fA-F]{6}\n?\z").unwrap());
static STEM_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[^A-Za-z0-9._-]+").unwrap());

/// What goes wrong. `Fail` is meant for the user, `Other` matches an unexpected
/// Python exception: `op_list` only catches `Fail`, so the difference is visible.
#[derive(Debug)]
pub enum Error {
    Fail(String),
    Other(String),
}

pub type Res<T> = Result<T, Error>;

pub fn fail<T>(message: impl Into<String>) -> Res<T> {
    Err(Error::Fail(message.into()))
}

pub fn other<T>(message: impl Into<String>) -> Res<T> {
    Err(Error::Other(message.into()))
}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Self::Other(e.to_string())
    }
}

impl From<serde_json::Error> for Error {
    fn from(e: serde_json::Error) -> Self {
        Self::Other(e.to_string())
    }
}

// ---- Paths ------------------------------------------------------------------

fn env_path(name: &str, default: impl FnOnce() -> PathBuf) -> PathBuf {
    match std::env::var_os(name) {
        Some(value) if !value.is_empty() => paths::normalise(Path::new(&value)),
        _ => default(),
    }
}

pub fn fastfetch_dir() -> PathBuf {
    env_path("DYNAMIC_ISLAND_FASTFETCH_DIR", || {
        paths::home().join(".config/fastfetch")
    })
}

pub fn state_dir() -> PathBuf {
    env_path("DYNAMIC_ISLAND_STATE_DIR", || {
        paths::home().join(".local/state/dynamic-island")
    })
}

pub fn look_dir(lid: &str) -> Res<PathBuf> {
    if lid == "miku" {
        return Ok(fastfetch_dir());
    }
    if !ID_RE.is_match(lid) || lid == "pictures" || lid == ".orig" {
        return fail(format!("ungueltige Look-ID: {lid}"));
    }
    Ok(fastfetch_dir().join(lid))
}

fn cards_dir(lid: &str) -> Res<PathBuf> {
    if lid == "miku" {
        return Ok(fastfetch_dir().join("Pictures/tactical"));
    }
    Ok(look_dir(lid)?.join("Pictures"))
}

fn sorted_by_lowercase_name(mut items: Vec<PathBuf>) -> Vec<PathBuf> {
    let name = |p: &PathBuf| {
        p.file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default()
    };
    items.sort_by_key(|p| (name(p).to_lowercase(), name(p)));
    items
}

fn children(dir: &Path) -> Res<Vec<PathBuf>> {
    let mut out = Vec::new();
    for entry in fs::read_dir(dir)? {
        out.push(entry?.path());
    }
    Ok(out)
}

fn look_ids() -> Res<Vec<String>> {
    let root = fastfetch_dir();
    let mut ids = Vec::new();
    if root.join("config.jsonc").is_file() {
        ids.push("miku".to_owned());
    }
    if root.is_dir() {
        for dir in sorted_by_lowercase_name(children(&root)?) {
            let name = dir
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            if dir.is_dir()
                && name != "Pictures"
                && !name.starts_with('.')
                && (dir.join("config.jsonc").is_file() || dir.join("look.json").is_file())
            {
                ids.push(name);
            }
        }
    }
    Ok(ids)
}

/// `str.capitalize`
fn capitalize(word: &str) -> String {
    let mut chars = word.chars();
    chars.next().map_or_else(String::new, |first| {
        first
            .to_uppercase()
            .chain(chars.flat_map(char::to_lowercase))
            .collect()
    })
}

pub fn default_title(lid: &str) -> String {
    if lid == "miku" {
        return "Vocaloid".to_owned();
    }
    lid.replace('_', "-")
        .split('-')
        .map(capitalize)
        .collect::<Vec<_>>()
        .join(" ")
}

// ---- Access like the Python dict methods --------------------------------------

/// `x.get(key)`, an error if `x` is no object, like the AttributeError in Python.
pub fn get<'a>(value: &'a Value, key: &str) -> Res<Option<&'a Value>> {
    match value {
        Value::Object(map) => Ok(map.get(key)),
        _ => other(format!("kein Objekt beim Zugriff auf {key}")),
    }
}

/// `(look.get("sizes") or {}).get(size) or {}` and the same again for any key below.
pub fn nested<'a>(value: &'a Value, keys: &[&str]) -> Res<Option<&'a Value>> {
    let mut current = value;
    for key in keys {
        match get(current, key)?.filter(|v| truthy(v)) {
            Some(next) => current = next,
            None => return Ok(None),
        }
    }
    Ok(Some(current))
}

fn is_raw(look: &Value, size: &str) -> Res<bool> {
    Ok(nested(look, &["sizes", size, "raw"])?.is_some())
}

// ---- Validate and build --------------------------------------------------------

/// `x == 1` of Python: true, 1 and 1.0 all count.
fn equals_one(value: Option<&Value>) -> bool {
    match value {
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64() == Some(1.0),
        _ => false,
    }
}

fn validate(look: &Value) -> Res<()> {
    let Some(map) = look.as_object().filter(|m| equals_one(m.get("version"))) else {
        return fail("look.json: version 1 erwartet");
    };
    let Some(palette) = map.get("palette").and_then(Value::as_object) else {
        return fail("look.json: palette fehlt");
    };
    for (key, value) in palette {
        let text = text_of(value);
        if !NAME_RE.is_match(key) || !HEX_RE.is_match(&text) {
            return fail(format!("Palette: ungueltiger Eintrag {key}={text}"));
        }
    }
    let (Some(_), Some(rows)) = (
        map.get("base").and_then(Value::as_object),
        map.get("rows").and_then(Value::as_array),
    ) else {
        return fail("look.json: base/rows fehlen");
    };
    for row in rows {
        let module = row.as_object().and_then(|r| r.get("m"));
        if !module.is_some_and(|m| m.is_object() || m.is_string()) {
            return fail("look.json: Zeile ohne m");
        }
    }
    Ok(())
}

/// The fastfetch configuration (as an object) for one size.
pub fn build(look: &Value, size: &str) -> Res<Value> {
    validate(look)?;
    let patch = nested(look, &["sizes", size, "patch"])?
        .cloned()
        .unwrap_or_else(|| json!({}));
    let mut conf = diff::merge(&look["base"], &patch);
    let Some(map) = conf.as_object_mut() else {
        return other("base ist kein Objekt");
    };
    map.shift_remove("modules");
    let mut modules = Vec::new();
    if let Some(rows) = look["rows"].as_array() {
        for row in rows {
            if let Some(value) = diff::row_value(row, size)? {
                modules.push(value);
            }
        }
    }
    map.insert("modules".to_owned(), Value::Array(modules));
    let Some(palette) = look["palette"].as_object() else {
        return other("palette ist kein Objekt");
    };
    markup::decode(&conf, palette)
}

/// Like the handwritten files: blocks indented, modules on one line each.
fn dump(conf: &Value, header: &str) -> Res<String> {
    let Some(map) = conf.as_object() else {
        return other("Konfiguration ist kein Objekt");
    };
    let modules: Vec<String> = map
        .get("modules")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .map(|m| format!("        {}", dumps(m, pyjson::UNICODE)))
        .collect();
    let block = format!("    \"modules\": [\n{}\n    ]", modules.join(",\n"));
    let mut head = map.clone();
    head.shift_remove("modules");
    if head.is_empty() {
        return Ok(format!("{header}{{\n{block}\n}}\n"));
    }
    let text = dumps(
        &Value::Object(head),
        pyjson::Style {
            indent: Some(4),
            ensure_ascii: false,
        },
    );
    let cut = text.len() - 2;
    Ok(format!("{header}{},\n{block}\n}}\n", &text[..cut]))
}

fn header_for(look: &Value, size: &str) -> Res<String> {
    let title = get(look, "title")?.map(text_of).unwrap_or_default();
    Ok(format!(
        "// {title} · {size} – erzeugt aus look.json (Terminal-Looks-Editor).\n\
         // Aenderungen hier gehen beim naechsten Speichern verloren; eigene Datei: im Editor \"Eigene Datei\".\n"
    ))
}

fn sha(text: &str) -> String {
    Sha256::digest(text.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn write_atomic(path: &Path, text: &str) -> Res<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(".tmp");
    let tmp = path.with_file_name(name);
    fs::write(&tmp, text)?;
    fs::rename(&tmp, path)?;
    Ok(())
}

fn backup_originals(dir: &Path) -> Res<()> {
    let orig = dir.join(".orig");
    if fs::symlink_metadata(&orig).is_ok() {
        return Ok(());
    }
    fs::create_dir(&orig)?;
    for size in SIZES {
        let name = format!("{size}.jsonc");
        let path = dir.join(&name);
        if path.is_file() {
            copy2(&path, &orig.join(&name))?;
        }
    }
    Ok(())
}

fn render_files(lid: &str, look: &mut Value, force: bool) -> Res<Vec<String>> {
    let dir = look_dir(lid)?;
    let mut generated: Map<String, Value> = get(look, "generated")?
        .filter(|g| truthy(g))
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let mut conflicts = Vec::new();
    let mut texts = Vec::new();
    for size in SIZES {
        if is_raw(look, size)? {
            continue;
        }
        let path = dir.join(format!("{size}.jsonc"));
        if path.is_file()
            && !force
            && let Some(known) = generated.get(size).filter(|g| truthy(g))
            && known.as_str() != Some(sha(&read_text(&path)?).as_str())
        {
            conflicts.push(format!("{size}.jsonc"));
        }
        texts.push((size, dump(&build(look, size)?, &header_for(look, size)?)?));
    }
    if !conflicts.is_empty() {
        return fail(format!(
            "von Hand geaendert seit dem letzten Speichern: {} (als eigene Datei uebernehmen oder mit --force ueberschreiben)",
            conflicts.join(", ")
        ));
    }
    let mut written = Vec::new();
    for (size, text) in texts {
        write_atomic(&dir.join(format!("{size}.jsonc")), &text)?;
        generated.insert(size.to_owned(), json!(sha(&text)));
        written.push(size.to_owned());
    }
    if let Some(map) = look.as_object_mut() {
        map.insert("generated".to_owned(), Value::Object(generated));
    }
    Ok(written)
}

fn read_look(lid: &str) -> Res<(Value, bool)> {
    let path = look_dir(lid)?.join("look.json");
    if path.is_file() {
        return match serde_json::from_str(&read_text(&path)?) {
            Ok(look) => Ok((look, true)),
            Err(e) => fail(format!("look.json kaputt: {e}")),
        };
    }
    Ok((import::import_files(lid, None)?, false))
}

fn write_look(lid: &str, look: &Value) -> Res<()> {
    write_atomic(
        &look_dir(lid)?.join("look.json"),
        &(dumps(look, pyjson::pretty(2)) + "\n"),
    )
}

fn save(lid: &str, look: &mut Value, mut force: bool) -> Res<Value> {
    validate(look)?;
    let dir = look_dir(lid)?;
    if !dir.join("look.json").is_file() {
        if dir.is_dir() {
            backup_originals(&dir)?;
        } else {
            fs::create_dir_all(&dir)?;
        }
        // First save: the handwork is replaced on purpose.
        force = true;
    }
    let written = render_files(lid, look, force)?;
    write_look(lid, look)?;
    Ok(json!({"written": written, "generated": look["generated"]}))
}

// ---- Cards ----------------------------------------------------------------------

fn card_list(lid: &str) -> Res<Vec<Value>> {
    let dir = cards_dir(lid)?;
    if !dir.is_dir() {
        return Ok(Vec::new());
    }
    let cards: Vec<PathBuf> = children(&dir)?
        .into_iter()
        .filter(|p| {
            p.file_name()
                .is_some_and(|n| n.to_string_lossy().ends_with(".png"))
        })
        .collect();
    Ok(sorted_by_lowercase_name(cards)
        .into_iter()
        .map(|p| json!({"name": p.file_name().map(|n| n.to_string_lossy().into_owned()), "path": p.to_string_lossy()}))
        .collect())
}

fn resolve_color(spec: &str, palette: &Value) -> Res<String> {
    if let Some(name) = spec.strip_prefix('@') {
        return match palette.get(name) {
            Some(color) => Ok(text_of(color)),
            None => fail(format!("unbekannte Palettenfarbe: {spec}")),
        };
    }
    if COLOR_ARG_RE.is_match(spec) {
        return Ok(format!("#{}", spec.trim_start_matches('#')));
    }
    fail(format!("ungueltige Farbe: {spec}"))
}

/// `(stderr.strip().splitlines() or ["Fehler"])[-1]`
pub fn last_line(text: &str) -> String {
    text.trim().lines().last().unwrap_or("Fehler").to_owned()
}

fn card_make(lid: &str, image: &str, color: &str) -> Res<Value> {
    let src = paths::expand_user(image);
    if !src.is_file() {
        return fail(format!("Bild fehlt: {image}"));
    }
    let (look, _) = read_look(lid)?;
    let Some(palette) = look.get("palette") else {
        return other("KeyError: 'palette'");
    };
    let spec = if !color.is_empty() {
        color
    } else if palette.get("primary").is_some() {
        "@primary"
    } else {
        "#ffffff"
    };
    let col = resolve_color(spec, palette)?;
    let dir = cards_dir(lid)?;
    fs::create_dir_all(&dir)?;
    let stem = src
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default();
    let cleaned = STEM_RE.replace_all(&stem, "-");
    let cleaned = cleaned.trim_matches('-');
    let stem = if cleaned.is_empty() { "karte" } else { cleaned };
    let mut out = dir.join(format!("{stem}.png"));
    let mut n = 2;
    while out.exists() {
        out = dir.join(format!("{stem}-{n}.png"));
        n += 1;
    }
    let out_name = out
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let tmp = out.with_file_name(format!("{out_name}.tmp.png"));
    // Like fish/functions/__fastfetch_card.fish
    let mut magick = Command::new("magick");
    magick.arg(&src).args([
        "-resize", "600x800^", "-gravity", "center", "-extent", "600x800",
    ]);
    magick.args([
        "(",
        "-size",
        "600x800",
        "xc:none",
        "-fill",
        "white",
        "-draw",
        "roundrectangle 0,0 599,799 30,30",
        ")",
    ]);
    magick.args(["-compose", "DstIn", "-composite", "-compose", "over"]);
    magick.args([
        "-fill",
        "none",
        "-stroke",
        &col,
        "-strokewidth",
        "5",
        "-draw",
        "roundrectangle 3,3 596,796 28,28",
    ]);
    magick.arg(&tmp);
    let result = preview::run_with_timeout(&mut magick, 60)?;
    let Some(result) = result else {
        return other("magick antwortet nicht");
    };
    if !result.status.success() || !tmp.is_file() {
        let _ = fs::remove_file(&tmp);
        return fail(format!(
            "magick: {}",
            last_line(&String::from_utf8_lossy(&result.stderr))
        ));
    }
    fs::rename(&tmp, &out)?;
    Ok(json!({"name": out_name, "path": out.to_string_lossy()}))
}

fn trash(path: &Path) -> Res<()> {
    let result = Command::new("gio").arg("trash").arg(path).output()?;
    if !result.status.success() {
        let text = String::from_utf8_lossy(&result.stderr);
        let text = text.trim();
        return fail(format!(
            "Papierkorb: {}",
            if text.is_empty() { "Fehler" } else { text }
        ));
    }
    Ok(())
}

fn scheme_palette() -> Res<Value> {
    let path = state_dir().join("scheme.json");
    let data: Value = match read_text(&path)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
    {
        Some(data) => data,
        None => return fail("scheme.json fehlt"),
    };
    let empty = json!({});
    let colours = get(&data, "colours")?
        .filter(|c| truthy(c))
        .unwrap_or(&empty);
    let mut out = Map::new();
    for (name, key) in [
        ("primary", "primary"),
        ("accent", "tertiary"),
        ("highlight", "secondary"),
        ("muted", "outline"),
    ] {
        let text = get(colours, key)?.map(text_of).unwrap_or_default();
        if SCHEME_HEX_RE.is_match(&text) {
            out.insert(name.to_owned(), json!(format!("#{}", text.to_lowercase())));
        }
    }
    Ok(Value::Object(out))
}

// ---- Operations --------------------------------------------------------------------

fn op_list() -> Res<Value> {
    let mut out = Vec::new();
    for lid in look_ids()? {
        let dir = look_dir(&lid)?;
        let managed = dir.join("look.json").is_file();
        let (palette, title, raw, error) = match read_look(&lid) {
            Ok((look, _)) => {
                let Some(palette) = get(&look, "palette")? else {
                    return other("KeyError: 'palette'");
                };
                let title = get(&look, "title")?
                    .filter(|t| truthy(t))
                    .cloned()
                    .unwrap_or_else(|| json!(default_title(&lid)));
                let mut raw = Vec::new();
                for size in SIZES {
                    if is_raw(&look, size)? {
                        raw.push(size);
                    }
                }
                (palette.clone(), title, raw, String::new())
            }
            Err(Error::Fail(message)) => {
                (json!({}), json!(default_title(&lid)), Vec::new(), message)
            }
            Err(e) => return Err(e),
        };
        let cards = card_list(&lid)?;
        out.push(json!({
            "id": lid, "title": title, "dir": dir.to_string_lossy(), "managed": managed, "palette": palette,
            "raw": raw, "cards": cards.len(),
            "card": cards.first().map_or_else(|| json!(""), |c| c["path"].clone()), "error": error,
        }));
    }
    Ok(json!({"looks": out}))
}

/// Arguments as `looks.py` splits them.
struct Args {
    op: String,
    positional: Vec<String>,
    from: Option<String>,
    title: Option<String>,
    json: Option<String>,
    text: Option<String>,
    raw: Option<String>,
    flags: Vec<String>,
}

fn parse_args(argv: Vec<String>) -> Res<Args> {
    let mut argv = argv.into_iter();
    let Some(op) = argv.next() else {
        return fail("Operation fehlt");
    };
    let mut args = Args {
        op,
        positional: Vec::new(),
        from: None,
        title: None,
        json: None,
        text: None,
        raw: None,
        flags: Vec::new(),
    };
    while let Some(arg) = argv.next() {
        let slot = match arg.as_str() {
            "--from" => Some(&mut args.from),
            "--title" => Some(&mut args.title),
            "--json" => Some(&mut args.json),
            "--text" => Some(&mut args.text),
            "--raw" => Some(&mut args.raw),
            _ => None,
        };
        if let Some(slot) = slot {
            let Some(value) = argv.next() else {
                return fail(format!("{arg}: Wert fehlt"));
            };
            *slot = Some(value);
        } else if arg.starts_with("--") {
            args.flags.push(arg);
        } else {
            args.positional.push(arg);
        }
    }
    Ok(args)
}

fn stdin_text() -> Res<String> {
    let mut text = String::new();
    std::io::stdin().read_to_string(&mut text)?;
    Ok(text)
}

impl Args {
    fn need(&self, n: usize) -> Res<()> {
        if self.positional.len() < n {
            return fail(format!("{}: zu wenige Argumente", self.op));
        }
        Ok(())
    }

    fn size_arg(&self, k: usize) -> Res<&str> {
        self.need(k + 1)?;
        let size = self.positional[k].as_str();
        if !SIZES.contains(&size) {
            return fail(format!("unbekannte Groesse: {size}"));
        }
        Ok(size)
    }

    fn json_in(&self) -> Res<Value> {
        let text = match &self.json {
            Some(text) => text.clone(),
            None => stdin_text()?,
        };
        serde_json::from_str(&text).or_else(|e| fail(format!("Eingabe ist kein JSON: {e}")))
    }

    fn flag(&self, name: &str) -> bool {
        self.flags.iter().any(|f| f == name)
    }
}

/// `(look.get("generated") or {}).pop(size, None)`
fn forget_generated(look: &mut Value, size: &str) -> Res<()> {
    if get(look, "generated")?.is_some_and(truthy) {
        match look["generated"].as_object_mut() {
            Some(generated) => {
                generated.shift_remove(size);
            }
            None => return other("generated ist kein Objekt"),
        }
    }
    Ok(())
}

fn op_new(args: &Args) -> Res<Value> {
    args.need(1)?;
    let lid = &args.positional[0];
    let src = args
        .from
        .as_deref()
        .filter(|s| !s.is_empty())
        .unwrap_or("miku");
    let dir = look_dir(lid)?;
    if lid == "miku" || dir.exists() {
        return fail(format!("Look gibt es schon: {lid}"));
    }
    let (mut look, _) = read_look(src)?;
    let title = args
        .title
        .clone()
        .filter(|t| !t.is_empty())
        .unwrap_or_else(|| default_title(lid));
    let Some(map) = look.as_object_mut() else {
        return other("Look ist kein Objekt");
    };
    map.insert("title".to_owned(), json!(title));
    map.shift_remove("generated");
    fs::create_dir_all(&dir)?;
    fs::create_dir(dir.join("Pictures"))?;
    for size in SIZES {
        if is_raw(&look, size)? {
            let name = format!("{size}.jsonc");
            copy2(&look_dir(src)?.join(&name), &dir.join(&name))?;
        }
    }
    render_files(lid, &mut look, true)?;
    write_look(lid, &look)?;
    Ok(json!({"id": lid}))
}

fn op_raw_set(args: &Args) -> Res<Value> {
    let size = args.size_arg(1)?;
    let text = match &args.text {
        Some(text) => text.clone(),
        None => stdin_text()?,
    };
    let conf: Value = match serde_json::from_str(&import::strip_jsonc(&text)) {
        Ok(conf) => conf,
        Err(e) => return fail(format!("kein gueltiges JSONC ({e}, Zeile {})", e.line())),
    };
    if !conf.is_object() {
        return fail("JSONC muss ein Objekt sein");
    }
    let lid = &args.positional[0];
    let (mut look, managed) = read_look(lid)?;
    if !managed {
        backup_originals(&look_dir(lid)?)?;
    }
    let Some(map) = look.as_object_mut() else {
        return other("Look ist kein Objekt");
    };
    let sizes = map.entry("sizes").or_insert_with(|| json!({}));
    let Some(sizes) = sizes.as_object_mut() else {
        return other("sizes ist kein Objekt");
    };
    let entry = sizes.entry(size).or_insert_with(|| json!({}));
    let Some(entry) = entry.as_object_mut() else {
        return other("Groesse ist kein Objekt");
    };
    entry.insert("raw".to_owned(), json!(true));
    let body = if text.ends_with('\n') {
        text.clone()
    } else {
        format!("{text}\n")
    };
    write_atomic(&look_dir(lid)?.join(format!("{size}.jsonc")), &body)?;
    forget_generated(&mut look, size)?;
    if !managed {
        render_files(lid, &mut look, true)?;
    }
    write_look(lid, &look)?;
    Ok(json!({"preview": preview::preview_conf(&conf, size)?}))
}

fn op_raw_off(args: &Args) -> Res<Value> {
    let size = args.size_arg(1)?;
    let lid = &args.positional[0];
    let (mut look, _) = read_look(lid)?;
    if args.flag("--adopt") {
        let title = get(&look, "title")?.filter(|t| truthy(t)).cloned();
        let mut fresh = import::import_files(lid, title)?;
        let mut sizes = Map::new();
        for s in SIZES {
            let mut entry = fresh["sizes"]
                .get(s)
                .filter(|e| truthy(e))
                .and_then(Value::as_object)
                .cloned()
                .unwrap_or_default();
            if s != size && is_raw(&look, s)? {
                entry.insert("raw".to_owned(), json!(true));
            }
            sizes.insert(s.to_owned(), Value::Object(entry));
        }
        fresh["sizes"] = Value::Object(sizes);
        look = fresh;
    } else if nested(&look, &["sizes", size])?.is_some() {
        match look["sizes"][size].as_object_mut() {
            Some(entry) => {
                entry.shift_remove("raw");
            }
            None => return other("Groesse ist kein Objekt"),
        }
    }
    forget_generated(&mut look, size)?;
    render_files(lid, &mut look, true)?;
    write_look(lid, &look)?;
    Ok(json!({"look": look}))
}

fn run(argv: Vec<String>) -> Res<Value> {
    let args = parse_args(argv)?;
    let pos = &args.positional;
    match args.op.as_str() {
        "list" => op_list(),
        "get" => {
            args.need(1)?;
            let (look, managed) = read_look(&pos[0])?;
            Ok(json!({"look": look, "managed": managed}))
        }
        "save" => {
            args.need(1)?;
            let mut look = args.json_in()?;
            save(&pos[0], &mut look, args.flag("--force"))
        }
        "import" => {
            args.need(1)?;
            look_dir(&pos[0])?;
            let mut look = import::import_files(&pos[0], None)?;
            save(&pos[0], &mut look, true)
        }
        "preview" => {
            let size = args.size_arg(0)?;
            if let Some(lid) = args.raw.as_deref().filter(|r| !r.is_empty()) {
                return preview::preview_raw(lid, size);
            }
            preview::preview_conf(&build(&args.json_in()?, size)?, size)
        }
        "check" => {
            args.need(1)?;
            let (look, _) = read_look(&pos[0])?;
            let mut sizes = Map::new();
            for size in SIZES {
                let p = if is_raw(&look, size)? {
                    preview::preview_raw(&pos[0], size)?
                } else {
                    preview::preview_conf(&build(&look, size)?, size)?
                };
                sizes.insert(
                    size.to_owned(),
                    json!({
                        "width": p["width"], "height": p["height"], "budget": p["budget"],
                        "overflow": p["overflow"], "tooTall": p["tooTall"],
                    }),
                );
            }
            Ok(json!({"sizes": sizes}))
        }
        "new" => op_new(&args),
        "delete" => {
            args.need(1)?;
            if pos[0] == "miku" {
                return fail("der Vocaloid-Look laesst sich nicht loeschen");
            }
            let dir = look_dir(&pos[0])?;
            if !dir.is_dir() {
                return fail(format!("Look fehlt: {}", pos[0]));
            }
            trash(&dir)?;
            Ok(json!({}))
        }
        "cards" => {
            args.need(1)?;
            look_dir(&pos[0])?;
            Ok(json!({"cards": card_list(&pos[0])?}))
        }
        "card-make" => {
            args.need(2)?;
            card_make(&pos[0], &pos[1], pos.get(2).map_or("", String::as_str))
        }
        "card-remove" => {
            args.need(2)?;
            let name = &pos[1];
            if name.contains('/') || name.starts_with('.') {
                return fail(format!("ungueltiger Name: {name}"));
            }
            let path = cards_dir(&pos[0])?.join(name);
            if !path.is_file() {
                return fail(format!("Karte fehlt: {name}"));
            }
            trash(&path)?;
            Ok(json!({}))
        }
        "raw-get" => {
            let size = args.size_arg(1)?;
            let path = look_dir(&pos[0])?.join(format!("{size}.jsonc"));
            let text = if path.is_file() {
                read_text(&path)?
            } else {
                String::new()
            };
            Ok(json!({"text": text}))
        }
        "raw-set" => op_raw_set(&args),
        "raw-off" => op_raw_off(&args),
        "palette" => {
            args.need(1)?;
            let count = match pos.get(1) {
                Some(text) => text
                    .trim()
                    .parse::<i64>()
                    .or_else(|e| other(format!("ValueError: {e}")))?,
                None => 8,
            };
            palette::palette_from_image(&pos[0], count)
        }
        "scheme-palette" => Ok(json!({"palette": scheme_palette()?})),
        op => fail(format!("unbekannte Operation: {op}")),
    }
}

fn main() {
    let argv: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    let answer = match run(argv) {
        Ok(Value::Object(result)) => {
            let mut out = Map::new();
            out.insert("ok".to_owned(), json!(true));
            out.extend(result);
            Value::Object(out)
        }
        Ok(_) => json!({"ok": true}),
        Err(Error::Fail(message)) => json!({"ok": false, "error": message}),
        Err(Error::Other(message)) => json!({"ok": false, "error": format!("Ausnahme: {message}")}),
    };
    println!("{}", dumps(&answer, pyjson::UNICODE));
}
