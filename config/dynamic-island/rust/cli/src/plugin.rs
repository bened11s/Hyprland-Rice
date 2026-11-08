//! Manage the plugins of the shell: list, on/off, import and export.
//!
//! A plugin is a folder `<shell>/plugins/<id>/` with `plugin.json` (format in
//! `quickshell/dynamic-island/plugins/README.md`). The shell finds new folders by
//! itself and watches `plugins.json`, so the CLI does not have to tell it anything.
//!
//! `<id>-<version>.dip` is a tar.gz with `dip.json` (package head), `plugin/...`
//! (the folder) and optionally `files/<n>[/...]` (external files of `manifest.files`).
//! `<id>-settings.json` holds setting values only.

use std::cmp::Ordering;
use std::collections::BTreeSet;
use std::ffi::OsStr;
use std::fs::{self, File};
use std::io::{self, BufRead, IsTerminal, Read, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Component, Path, PathBuf};
use std::time::{Duration, UNIX_EPOCH};

use chrono::Local;
use clap::{Args, Parser, Subcommand};
use di_common::fsutil::{copy_tree, copy2, move_path, resolve, walk_sorted};
use di_common::hash::compute_hash;
use di_common::paths;
use di_common::pyjson::{self, dumps, text_of, truthy};
use flate2::Compression;
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use serde_json::{Map, Value, json};
use tar::{Archive, Builder, EntryType, Header};
use tempfile::TempDir;

const API_VERSION: i64 = 1;
const PACKAGE_FORMAT: &str = "dynamic-island-plugin";
const SETTINGS_FORMAT: &str = "dynamic-island-plugin-settings";
const FORMAT_VERSION: i64 = 1;
/// Editor and runtime leftovers stay out of packages.
const SKIP_NAMES: [&str; 4] = ["__pycache__", ".qmlls.ini", ".git", ".DS_Store"];
const MAX_MEMBERS: usize = 5000;
const MAX_BYTES: u64 = 512 * 1024 * 1024;

#[derive(Parser)]
#[command(
    name = "plugin",
    disable_help_flag = true,
    disable_help_subcommand = true
)]
pub struct Cli {
    #[command(subcommand)]
    pub action: Action,
}

#[derive(Subcommand)]
pub enum Action {
    List {
        #[arg(long)]
        json: bool,
    },
    Info {
        id: String,
        #[arg(long)]
        json: bool,
    },
    Enable {
        id: String,
        #[arg(long)]
        json: bool,
    },
    Disable {
        id: String,
        #[arg(long)]
        json: bool,
    },
    Validate {
        path: String,
        #[arg(long)]
        json: bool,
    },
    Export(ExportArgs),
    Import(ImportArgs),
    Remove(RemoveArgs),
    New(NewArgs),
}

#[derive(Args)]
pub struct ExportArgs {
    id: String,
    #[arg(long)]
    json: bool,
    #[arg(short, long)]
    output: Option<String>,
    #[arg(long)]
    no_settings: bool,
    #[arg(long)]
    no_files: bool,
    #[arg(long)]
    skip_optional: bool,
    #[arg(long)]
    settings_only: bool,
}

#[derive(Args)]
pub struct ImportArgs {
    file: String,
    #[arg(long)]
    json: bool,
    #[arg(short, long)]
    yes: bool,
    #[arg(long)]
    enable: bool,
    #[arg(long)]
    files: bool,
    #[arg(long)]
    settings: bool,
    #[arg(long)]
    no_settings: bool,
    #[arg(long)]
    force: bool,
    #[arg(long)]
    overwrite_files: bool,
    #[arg(long)]
    parent: Option<String>,
}

#[derive(Args)]
pub struct RemoveArgs {
    id: String,
    #[arg(long)]
    json: bool,
    #[arg(short, long)]
    yes: bool,
    #[arg(long)]
    keep_settings: bool,
    #[arg(long)]
    force: bool,
}

#[derive(Args)]
pub struct NewArgs {
    id: String,
    #[arg(long)]
    json: bool,
    #[arg(long)]
    name: Option<String>,
    #[arg(long)]
    author: Option<String>,
}

fn is_tilde_user(path: &str) -> bool {
    path.starts_with('~') && path != "~" && !path.starts_with("~/")
}

impl Action {
    /// `~other/...` needs the password database, Python does that for us.
    pub fn uses_tilde_user(&self) -> bool {
        match self {
            Self::Validate { path, .. } => is_tilde_user(path),
            Self::Export(a) => a.output.as_deref().is_some_and(is_tilde_user),
            Self::Import(a) => is_tilde_user(&a.file),
            _ => false,
        }
    }

    fn json(&self) -> bool {
        match self {
            Self::List { json }
            | Self::Info { json, .. }
            | Self::Enable { json, .. }
            | Self::Disable { json, .. }
            | Self::Validate { json, .. } => *json,
            Self::Export(a) => a.json,
            Self::Import(a) => a.json,
            Self::Remove(a) => a.json,
            Self::New(a) => a.json,
        }
    }
}

/// A problem the user is told about. Everything else is a bug or the file system.
#[derive(Debug)]
struct PluginError(String);

impl From<io::Error> for PluginError {
    fn from(e: io::Error) -> Self {
        Self(e.to_string())
    }
}

impl From<serde_json::Error> for PluginError {
    fn from(e: serde_json::Error) -> Self {
        Self(e.to_string())
    }
}

impl From<tempfile::PersistError> for PluginError {
    fn from(e: tempfile::PersistError) -> Self {
        Self(e.error.to_string())
    }
}

fn fail<T>(message: impl Into<String>) -> Result<T, PluginError> {
    Err(PluginError(message.into()))
}

type Outcome = Result<Option<Value>, PluginError>;

pub fn run(action: &Action) -> i32 {
    let json = action.json();
    let result = match action {
        Action::List { json } => list(*json),
        Action::Info { id, json } => info(id, *json),
        Action::Enable { id, .. } => set_enabled(id, true),
        Action::Disable { id, .. } => set_enabled(id, false),
        Action::Validate { path, .. } => validate(path),
        Action::Export(args) => export(args),
        Action::Import(args) => import(args),
        Action::Remove(args) => remove(args),
        Action::New(args) => new(args),
    };
    match result {
        Ok(Some(value)) => {
            emit(&value, json);
            0
        }
        Ok(None) => 0,
        Err(PluginError(message)) => {
            emit(&json!({"ok": false, "message": message}), json);
            1
        }
    }
}

fn emit(result: &Value, json: bool) {
    if json {
        println!("{}", dumps(result, pyjson::UNICODE));
    } else if !result.get("ok").is_none_or(truthy) {
        eprintln!(
            "Fehler: {}",
            result.get("message").map(text_of).unwrap_or_default()
        );
    } else if let Some(message) = result.get("message").filter(|m| truthy(m)) {
        println!("{}", text_of(message));
    }
}

fn confirm(yes: bool, question: &str) -> Result<bool, PluginError> {
    if yes {
        return Ok(true);
    }
    if !io::stdin().is_terminal() {
        return fail("Nicht interaktiv: mit --yes bestaetigen");
    }
    print!("{question} [j/N] ");
    io::stdout().flush()?;
    let mut answer = String::new();
    io::stdin().lock().read_line(&mut answer)?;
    Ok(matches!(
        answer.trim().to_lowercase().as_str(),
        "j" | "ja" | "y" | "yes"
    ))
}

// ---- Paths and state --------------------------------------------------------

fn plugins_dir() -> PathBuf {
    paths::override_or("PLUGINS_DIR", || {
        paths::config_dir().join("quickshell/dynamic-island/plugins")
    })
}

fn state_path() -> PathBuf {
    paths::override_or("PLUGINS_FILE", || {
        paths::c_config_dir().join("plugins.json")
    })
}

fn backups_dir() -> PathBuf {
    paths::c_cache_dir().join("plugin-backups")
}

struct State {
    enabled: Map<String, Value>,
    settings: Map<String, Value>,
}

fn read_state() -> Result<State, PluginError> {
    let path = state_path();
    let data = match fs::read_to_string(&path) {
        Ok(text) => serde_json::from_str::<Value>(&text)
            .map_err(|e| PluginError(format!("{} ist kein gueltiges JSON: {e}", path.display())))?,
        Err(e) if e.kind() == io::ErrorKind::NotFound => json!({}),
        Err(e) => return Err(e.into()),
    };
    let Some(data) = data.as_object() else {
        return fail(format!("{} ist kein Objekt", path.display()));
    };
    let group = |key: &str| match data.get(key) {
        None => Ok(Map::new()),
        Some(Value::Object(map)) => Ok(map.clone()),
        Some(_) => fail(format!("{}: {key} ist kein Objekt", path.display())),
    };
    Ok(State {
        enabled: group("enabled")?,
        settings: group("settings")?,
    })
}

fn write_state(state: &State) -> Result<(), PluginError> {
    let path = state_path();
    let parent = path.parent().unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    let doc = json!({"format": 1, "enabled": state.enabled, "settings": state.settings});
    let mut tmp = tempfile::Builder::new()
        .prefix(".plugins-")
        .tempfile_in(parent)?;
    tmp.write_all(dumps(&doc, pyjson::pretty(2)).as_bytes())?;
    tmp.write_all(b"\n")?;
    // mkstemp creates 0600, keep it readable like shell.json
    tmp.as_file()
        .set_permissions(fs::Permissions::from_mode(0o644))?;
    tmp.persist(&path)?;
    Ok(())
}

// ---- Manifests --------------------------------------------------------------

/// `^[a-z0-9][a-z0-9-]{0,47}$`
fn id_ok(id: &str) -> bool {
    id.len() <= 48 && slug_ok(id, |c| c.is_ascii_lowercase() || c.is_ascii_digit())
}

/// `^<first>[a-z0-9-]*$`
fn slug_ok(text: &str, first: impl Fn(char) -> bool) -> bool {
    let mut chars = text.chars();
    chars.next().is_some_and(first)
        && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
}

fn lower_first(c: char) -> bool {
    c.is_ascii_lowercase()
}

fn lower_or_digit_first(c: char) -> bool {
    c.is_ascii_lowercase() || c.is_ascii_digit()
}

/// `^[A-Za-z][A-Za-z0-9_]*$`
fn key_ok(key: &str) -> bool {
    let mut chars = key.chars();
    chars.next().is_some_and(|c| c.is_ascii_alphabetic())
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

/// `~/...` resolved, everything outside of `$HOME` is forbidden.
fn home_path(spec: &str) -> Result<PathBuf, PluginError> {
    let Some(rest) = spec.strip_prefix("~/") else {
        return fail(format!("\"{spec}\" muss mit ~/ beginnen"));
    };
    let home = resolve(&paths::home());
    let target = resolve(&home.join(rest));
    if !target.starts_with(&home) {
        return fail(format!("\"{spec}\" zeigt aus dem Home-Ordner heraus"));
    }
    Ok(target)
}

fn object_or_empty<'a>(
    m: &'a Map<String, Value>,
    key: &str,
    empty: &'a Map<String, Value>,
) -> Option<&'a Map<String, Value>> {
    match m.get(key) {
        None => Some(empty),
        Some(Value::Object(map)) => Some(map),
        Some(_) => None,
    }
}

fn component_of(item: &Value) -> Option<&str> {
    item.as_object()?
        .get("component")?
        .as_str()
        .filter(|c| !c.contains(".."))
}

/// Same rules as `PluginHost.check()` in the shell. Empty means fine.
fn check_manifest(manifest: &Value, folder: Option<&str>) -> String {
    let Some(m) = manifest.as_object() else {
        return "Manifest ist kein Objekt".to_owned();
    };
    let Some(pid) = m.get("id").and_then(Value::as_str).filter(|id| id_ok(id)) else {
        return "id: nur a-z, 0-9 und -, hoechstens 48 Zeichen".to_owned();
    };
    if let Some(folder) = folder
        && pid != folder
    {
        return format!("id \"{pid}\" passt nicht zum Ordnernamen \"{folder}\"");
    }
    if m.get("name")
        .and_then(Value::as_str)
        .is_none_or(str::is_empty)
    {
        return "name fehlt".to_owned();
    }
    let Some(api) = m.get("api").and_then(Value::as_i64) else {
        return "api fehlt (Zahl)".to_owned();
    };
    if api > API_VERSION {
        return format!("braucht Plugin-API {api}, diese Shell kann {API_VERSION}");
    }
    if let Some(parent) = m.get("parent").filter(|p| !p.is_null())
        && !parent.as_str().is_some_and(|p| id_ok(p) && p != pid)
    {
        return "parent: id eines anderen Plugins erwartet".to_owned();
    }
    if let Some(main) = m.get("main").filter(|v| !v.is_null())
        && !main
            .as_str()
            .is_some_and(|p| !p.contains("..") && !p.starts_with('/'))
    {
        return "main: relativer Pfad im Plugin-Ordner erwartet".to_owned();
    }
    let empty = Map::new();
    let Some(settings) = object_or_empty(m, "settings", &empty) else {
        return "settings muss ein Objekt sein".to_owned();
    };
    for (key, spec) in settings {
        if !key_ok(key) {
            return format!("settings.{key}: ungueltiger Schluessel");
        }
        if !spec.as_object().is_some_and(|s| s.contains_key("default")) {
            return format!("settings.{key}: \"default\" fehlt");
        }
    }
    let Some(tiles) = object_or_empty(m, "tiles", &empty) else {
        return "tiles muss ein Objekt sein".to_owned();
    };
    for (id, tile) in tiles {
        if !slug_ok(id, lower_or_digit_first) || component_of(tile).is_none() {
            return format!("tiles.{id}: id oder component ungueltig");
        }
    }
    let Some(panels) = object_or_empty(m, "panels", &empty) else {
        return "panels muss ein Objekt sein".to_owned();
    };
    for (name, panel) in panels {
        if !slug_ok(name, lower_first) || component_of(panel).is_none() {
            return format!("panels.{name}: Ansicht oder component ungueltig");
        }
    }
    let Some(widgets) = object_or_empty(m, "widgets", &empty) else {
        return "widgets muss ein Objekt sein".to_owned();
    };
    for (kind, widget) in widgets {
        if !slug_ok(kind, lower_first) || component_of(widget).is_none() {
            return format!("widgets.{kind}: Typ oder component ungueltig");
        }
    }
    let Some(keybinds) = object_or_empty(m, "keybinds", &empty) else {
        return "keybinds muss ein Objekt sein".to_owned();
    };
    for (id, bind) in keybinds {
        let problem = check_keybind(id, bind);
        if !problem.is_empty() {
            return problem;
        }
    }
    let files = match m.get("files") {
        None => &Vec::new(),
        Some(Value::Array(files)) => files,
        Some(_) => return "files muss eine Liste sein".to_owned(),
    };
    for entry in files {
        let Some(path) = entry
            .as_object()
            .and_then(|e| e.get("path"))
            .and_then(Value::as_str)
        else {
            return "files: Eintraege brauchen path".to_owned();
        };
        if let Err(PluginError(e)) = home_path(path) {
            return format!("files: {e}");
        }
    }
    String::new()
}

fn check_keybind(id: &str, bind: &Value) -> String {
    let Some(bind) = bind
        .as_object()
        .filter(|_| slug_ok(id, lower_or_digit_first))
    else {
        return format!("keybinds.{id}: id ungueltig");
    };
    if bind
        .get("keys")
        .and_then(Value::as_str)
        .is_none_or(|k| k.trim().is_empty())
    {
        return format!("keybinds.{id}: keys fehlt");
    }
    if !bind
        .get("title")
        .and_then(Value::as_str)
        .is_some_and(|t| !t.is_empty() && !t.contains('|'))
    {
        return format!("keybinds.{id}: title fehlt oder enthaelt |");
    }
    if let Some(group) = bind.get("group").filter(|g| !g.is_null())
        && !group
            .as_str()
            .is_some_and(|g| !g.is_empty() && !g.contains('|'))
    {
        return format!("keybinds.{id}: group darf kein | enthalten");
    }
    let is_text = |key: &str| bind.get(key).is_some_and(Value::is_string);
    if is_text("ipc") == is_text("exec") {
        return format!("keybinds.{id}: genau eins von ipc oder exec");
    }
    String::new()
}

/// `Path.name`
fn folder_name(folder: &Path) -> String {
    match folder.components().next_back() {
        Some(Component::Normal(name)) => name.to_string_lossy().into_owned(),
        Some(Component::ParentDir) => "..".to_owned(),
        _ => String::new(),
    }
}

fn load_manifest(folder: &Path) -> Result<Value, String> {
    let text = match fs::read_to_string(folder.join("plugin.json")) {
        Ok(text) => text,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Err("plugin.json fehlt".to_owned()),
        Err(e) => return Err(format!("plugin.json: {e}")),
    };
    let manifest: Value = serde_json::from_str(&text)
        .map_err(|e| format!("plugin.json ist kein gueltiges JSON: {e}"))?;
    let problem = check_manifest(&manifest, Some(&folder_name(folder)));
    if problem.is_empty() {
        Ok(manifest)
    } else {
        Err(problem)
    }
}

struct Installed {
    id: String,
    manifest: Result<Value, String>,
}

fn installed() -> Result<Vec<Installed>, PluginError> {
    let dir = plugins_dir();
    if !dir.is_dir() {
        return Ok(Vec::new());
    }
    let mut folders: Vec<PathBuf> = fs::read_dir(&dir)?
        .map(|e| e.map(|e| e.path()))
        .collect::<Result<_, _>>()?;
    folders.sort();
    Ok(folders
        .into_iter()
        .filter(|f| {
            f.is_dir()
                && !f
                    .file_name()
                    .is_some_and(|n| n.to_string_lossy().starts_with(['_', '.']))
        })
        .map(|f| Installed {
            id: folder_name(&f),
            manifest: load_manifest(&f),
        })
        .collect())
}

fn is_enabled(state: &State, pid: &str, manifest: Option<&Value>) -> bool {
    match state.enabled.get(pid).filter(|v| !v.is_null()) {
        Some(on) => truthy(on),
        None => manifest
            .and_then(|m| m.get("defaultEnabled"))
            .is_some_and(truthy),
    }
}

fn require(pid: &str) -> Result<(PathBuf, Value), PluginError> {
    let folder = plugins_dir().join(pid);
    if !id_ok(pid) || !folder.is_dir() {
        return fail(format!("Plugin \"{pid}\" gibt es nicht"));
    }
    match load_manifest(&folder) {
        Ok(manifest) => Ok((folder, manifest)),
        Err(problem) => fail(format!("{pid}: {problem}")),
    }
}

fn field<'a>(m: &'a Value, key: &str) -> &'a Value {
    m.get(key).unwrap_or(&Value::Null)
}

fn text_field(m: &Value, key: &str) -> String {
    text_of(field(m, key))
}

/// `m.get("version", default)`
fn version_of(m: &Value, default: &str) -> Value {
    m.get("version").cloned().unwrap_or_else(|| json!(default))
}

#[derive(PartialEq)]
enum VersionPart {
    Number(u128),
    Text(String),
}

fn version_parts(version: &str) -> Vec<VersionPart> {
    version
        .split(['.', '+', '-'])
        .map(|p| match p.parse::<u128>() {
            Ok(n) if !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()) => {
                VersionPart::Number(n)
            }
            _ => VersionPart::Text(p.to_owned()),
        })
        .collect()
}

/// Tuple comparison. None if a number meets text, Python stops with an error there.
fn compare_versions(a: &str, b: &str) -> Option<Ordering> {
    let (a, b) = (version_parts(a), version_parts(b));
    for (x, y) in a.iter().zip(&b) {
        let order = match (x, y) {
            (VersionPart::Number(x), VersionPart::Number(y)) => x.cmp(y),
            (VersionPart::Text(x), VersionPart::Text(y)) => x.cmp(y),
            _ => return None,
        };
        if order != Ordering::Equal {
            return Some(order);
        }
    }
    Some(a.len().cmp(&b.len()))
}

/// Moves `path` to the backup folder, returns where it went.
fn backup(path: &Path, label: &str) -> Result<PathBuf, PluginError> {
    let dir = backups_dir();
    fs::create_dir_all(&dir)?;
    let mut name = format!("{label}-{}", Local::now().format("%Y%m%d-%H%M%S"));
    let mut n = 1;
    while fs::symlink_metadata(dir.join(&name)).is_ok() {
        name = format!("{name}-{n}");
        n += 1;
    }
    let target = dir.join(name);
    move_path(path, &target)?;
    Ok(target)
}

// ---- list / info / enable / disable / validate -------------------------------

struct Row {
    id: String,
    name: String,
    version: Value,
    enabled: bool,
    valid: bool,
    problem: String,
    parent: Value,
}

fn list(json_output: bool) -> Outcome {
    let state = read_state()?;
    let rows: Vec<Row> = installed()?
        .into_iter()
        .map(|p| {
            let manifest = p.manifest.as_ref().ok();
            Row {
                name: manifest.map_or_else(|| p.id.clone(), |m| text_field(m, "name")),
                version: manifest.map_or_else(|| json!("?"), |m| version_of(m, "?")),
                enabled: is_enabled(&state, &p.id, manifest),
                valid: manifest.is_some(),
                problem: p.manifest.as_ref().err().cloned().unwrap_or_default(),
                parent: manifest
                    .and_then(|m| m.get("parent"))
                    .cloned()
                    .unwrap_or_else(|| json!("")),
                id: p.id,
            }
        })
        .collect();

    if json_output {
        let plugins: Vec<Value> = rows
            .iter()
            .map(|r| {
                json!({
                    "id": r.id, "name": r.name, "version": r.version, "enabled": r.enabled,
                    "valid": r.valid, "problem": r.problem, "parent": r.parent,
                })
            })
            .collect();
        let count = plugins.len();
        return Ok(Some(
            json!({"ok": true, "message": format!("{count} Plugins"), "plugins": plugins}),
        ));
    }
    if rows.is_empty() {
        println!("Keine Plugins in {}", plugins_dir().display());
    }
    // Components (manifest `parent`) indented below their plugin. If the parent
    // is missing they stay on top with a note.
    let ids: BTreeSet<&str> = rows
        .iter()
        .filter(|r| r.valid && !truthy(&r.parent))
        .map(|r| r.id.as_str())
        .collect();
    let in_ids = |parent: &Value| parent.as_str().is_some_and(|p| ids.contains(p));
    let show = |r: &Row, indent: &str| {
        let mark = if !r.valid {
            "✗"
        } else if r.enabled {
            "●"
        } else {
            "○"
        };
        let mut extra = if r.problem.is_empty() {
            String::new()
        } else {
            format!("  ({})", r.problem)
        };
        if truthy(&r.parent) && !in_ids(&r.parent) {
            extra.push_str(&format!("  (gehoert zu {}, fehlt)", text_of(&r.parent)));
        }
        let width = 20 - indent.chars().count();
        println!(
            "{indent}{mark} {:<width$} {:<10} {}{extra}",
            r.id,
            text_of(&r.version),
            r.name
        );
    };
    for r in &rows {
        if in_ids(&r.parent) {
            continue;
        }
        show(r, "");
        for c in &rows {
            if c.parent.as_str() == Some(&r.id) && ids.contains(r.id.as_str()) {
                show(c, "  └ ");
            }
        }
    }
    Ok(None)
}

fn info(id: &str, json_output: bool) -> Outcome {
    let (folder, m) = require(id)?;
    let state = read_state()?;
    let pid = text_field(&m, "id");
    let enabled = is_enabled(&state, &pid, Some(&m));
    let settings = state
        .settings
        .get(&pid)
        .cloned()
        .unwrap_or_else(|| json!({}));
    if json_output {
        return Ok(Some(json!({
            "ok": true, "message": "", "id": pid, "manifest": m, "enabled": enabled,
            "settings": settings, "dir": folder.to_string_lossy(),
        })));
    }
    let word = if enabled { "an" } else { "aus" };
    println!(
        "{} ({pid}) {}  –  {word}",
        text_field(&m, "name"),
        text_of(&version_of(&m, "?"))
    );
    if let Some(description) = m.get("description").filter(|d| truthy(d)) {
        println!("  {}", text_of(description));
    }
    println!("  Ordner: {}", folder.display());
    if let Some(specs) = m.get("settings").and_then(Value::as_object) {
        for (key, spec) in specs {
            let value = settings.get(key).unwrap_or_else(|| field(spec, "default"));
            let title = spec.get("title").map(text_of).unwrap_or_default();
            println!("  {key} = {}   ({title})", dumps(value, pyjson::DEFAULT));
        }
    }
    if let Some(files) = m.get("files").and_then(Value::as_array) {
        for entry in files {
            let path = text_field(entry, "path");
            let note = if home_path(&path)?.exists() {
                ""
            } else {
                "  (fehlt)"
            };
            println!("  Datei {path}{note}");
        }
    }
    Ok(None)
}

fn set_enabled(id: &str, on: bool) -> Outcome {
    let (_, m) = require(id)?;
    let mut state = read_state()?;
    let pid = text_field(&m, "id");
    state.enabled.insert(pid.clone(), json!(on));
    write_state(&state)?;
    let word = if on { "an" } else { "aus" };
    let message = format!("{}: {word}", text_field(&m, "name"));
    Ok(Some(
        json!({"ok": true, "message": message, "id": pid, "enabled": on}),
    ))
}

fn validate(path: &str) -> Outcome {
    let path = paths::expand_user(path);
    if path.is_dir() {
        let m = load_manifest(&path).map_err(PluginError)?;
        let mut parts = vec![m.get("main").cloned().unwrap_or(Value::Null)];
        for group in ["tiles", "panels"] {
            if let Some(items) = m.get(group).and_then(Value::as_object) {
                parts.extend(items.values().map(|item| field(item, "component").clone()));
            }
        }
        for rel in parts.iter().filter(|r| truthy(r)) {
            let rel = text_of(rel);
            if !path.join(&rel).is_file() {
                return fail(format!("{rel} fehlt im Plugin-Ordner"));
            }
        }
        let id = text_field(&m, "id");
        let message = format!("{id} {}: in Ordnung", text_of(&version_of(&m, "?")));
        return Ok(Some(json!({"ok": true, "message": message, "id": id})));
    }
    let package = Package::open(&path)?;
    let plugin = field(&package.head, "plugin");
    let id = text_field(plugin, "id");
    let message = format!(
        "{id} {}: Paket in Ordnung",
        text_of(&version_of(plugin, "?"))
    );
    Ok(Some(json!({"ok": true, "message": message, "id": id})))
}

// ---- Export -----------------------------------------------------------------

fn now_iso() -> String {
    Local::now().format("%Y-%m-%dT%H:%M:%S%:z").to_string()
}

fn hostname() -> String {
    let mut buffer = [0u8; 256];
    // SAFETY: the buffer is valid for its length, and gethostname writes at most that.
    let result = unsafe { libc::gethostname(buffer.as_mut_ptr().cast(), buffer.len()) };
    if result != 0 {
        return String::new();
    }
    let end = buffer.iter().position(|b| *b == 0).unwrap_or(buffer.len());
    String::from_utf8_lossy(&buffer[..end]).into_owned()
}

fn skipped_name(rel: &Path) -> bool {
    rel.components().any(|c| {
        c.as_os_str()
            .to_str()
            .is_some_and(|n| SKIP_NAMES.contains(&n))
    })
}

fn export_target(args: &ExportArgs, default_name: &str) -> PathBuf {
    match &args.output {
        Some(output) => {
            let out = paths::expand_user(output);
            if out.is_dir() || output.ends_with('/') {
                out.join(default_name)
            } else {
                out
            }
        }
        None => paths::home().join("Downloads").join(default_name),
    }
}

fn human(size: u64) -> String {
    #[allow(clippy::cast_precision_loss)]
    let mut n = size as f64;
    for unit in ["B", "KB", "MB", "GB"] {
        if n < 1024.0 || unit == "GB" {
            return if unit == "B" {
                format!("{n:.0} {unit}")
            } else {
                format!("{n:.1} {unit}")
            };
        }
        n /= 1024.0;
    }
    unreachable!("the last unit always returns")
}

fn export(args: &ExportArgs) -> Outcome {
    let (folder, m) = require(&args.id)?;
    let pid = text_field(&m, "id");
    let version = version_of(&m, "0");
    let version_text = text_of(&version);
    let state = read_state()?;
    let settings = state.settings.get(&pid).cloned();

    if args.settings_only {
        let out = export_target(args, &format!("{pid}-settings.json"));
        let doc = json!({
            "format": SETTINGS_FORMAT, "formatVersion": FORMAT_VERSION,
            "plugin": {"id": pid, "version": version}, "created": now_iso(),
            "settings": settings.filter(truthy).unwrap_or_else(|| json!({})),
        });
        fs::write(&out, dumps(&doc, pyjson::pretty(2)) + "\n")?;
        let message = format!("Einstellungen exportiert: {}", out.display());
        return Ok(Some(
            json!({"ok": true, "message": message, "path": out.to_string_lossy()}),
        ));
    }

    let out = export_target(args, &format!("{pid}-{version_text}.dip"));
    let mut head = Map::new();
    head.insert("format".into(), json!(PACKAGE_FORMAT));
    head.insert("formatVersion".into(), json!(FORMAT_VERSION));
    head.insert(
        "plugin".into(),
        json!({"id": pid, "name": field(&m, "name"), "version": version, "api": field(&m, "api")}),
    );
    head.insert("created".into(), json!(now_iso()));
    head.insert(
        "generator".into(),
        json!(format!("dynamic-island plugin export ({})", hostname())),
    );
    head.insert("enabled".into(), json!(is_enabled(&state, &pid, Some(&m))));
    let mut file_entries = Vec::new();

    // First collect everything (name in the archive, source), then write.
    let mut members: Vec<(String, PathBuf)> = Vec::new();
    for src in walk_sorted(&folder)? {
        let rel = src.strip_prefix(&folder).unwrap_or(&src).to_path_buf();
        if skipped_name(&rel) || src.extension() == Some(OsStr::new("dip")) {
            continue;
        }
        if src.is_symlink() {
            return fail(format!(
                "Symlink im Plugin-Ordner wird nicht exportiert: {}",
                rel.display()
            ));
        }
        if src.is_file() {
            members.push((format!("plugin/{}", rel.display()), src));
        }
    }

    let mut skipped = Vec::new();
    if !args.no_files
        && let Some(files) = m.get("files").and_then(Value::as_array)
    {
        for (n, entry) in files.iter().enumerate() {
            let spec = text_field(entry, "path");
            let path = home_path(&spec)?;
            let optional = entry.get("optional").is_some_and(truthy);
            if !path.exists() || (optional && args.skip_optional) {
                skipped.push(spec);
                continue;
            }
            let arc = format!("files/{n}");
            let is_dir = path.is_dir();
            file_entries.push(json!({
                "path": spec, "archive": arc, "type": if is_dir { "dir" } else { "file" }, "optional": optional,
            }));
            if is_dir {
                for src in walk_sorted(&path)? {
                    let rel = src.strip_prefix(&path).unwrap_or(&src).to_path_buf();
                    if src.is_file() && !skipped_name(&rel) {
                        members.push((format!("{arc}/{}", rel.display()), src));
                    }
                }
            } else {
                members.push((arc, path));
            }
        }
    }

    let mut checksums = Map::new();
    for (arc, src) in &members {
        checksums.insert(arc.clone(), json!(compute_hash(src)?));
    }
    head.insert("files".into(), json!(file_entries));
    head.insert("checksums".into(), Value::Object(checksums));
    if !args.no_settings
        && let Some(settings) = settings.filter(truthy)
    {
        head.insert("settings".into(), settings);
    }

    let parent = out.parent().unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    let tmp = tempfile::Builder::new()
        .prefix(".dip-")
        .tempfile_in(parent)?;
    write_package(tmp.as_file(), &Value::Object(head), &members)?;
    tmp.persist(&out)?;

    let size = fs::metadata(&out)?.len();
    let mut message = format!(
        "Exportiert: {} ({}, {} Dateien)",
        out.display(),
        human(size),
        members.len()
    );
    if !skipped.is_empty() {
        message.push_str(&format!("; nicht dabei: {}", skipped.join(", ")));
    }
    Ok(Some(json!({
        "ok": true, "message": message, "path": out.to_string_lossy(), "size": size, "skipped": skipped,
    })))
}

fn is_executable(path: &Path) -> bool {
    let Ok(c_path) = std::ffi::CString::new(path.as_os_str().as_encoded_bytes()) else {
        return false;
    };
    // SAFETY: the pointer is a valid C string for the duration of the call.
    unsafe { libc::access(c_path.as_ptr(), libc::X_OK) == 0 }
}

fn write_package(
    file: &File,
    head: &Value,
    members: &[(String, PathBuf)],
) -> Result<(), PluginError> {
    let mut tar = Builder::new(GzEncoder::new(file, Compression::default()));
    let data = dumps(head, pyjson::pretty(2)).into_bytes();
    let mut header = Header::new_gnu();
    header.set_size(data.len() as u64);
    header.set_mtime(Local::now().timestamp().max(0).unsigned_abs());
    header.set_mode(0o644);
    header.set_entry_type(EntryType::Regular);
    tar.append_data(&mut header, "dip.json", data.as_slice())?;

    for (arc, src) in members {
        let metadata = fs::symlink_metadata(src)?;
        let mut header = Header::new_gnu();
        header.set_uid(0);
        header.set_gid(0);
        header.set_mtime(metadata.mtime().max(0).unsigned_abs());
        header.set_mode(if is_executable(src) { 0o755 } else { 0o644 });
        if metadata.is_symlink() {
            // Like tarfile.gettarinfo: the link stays a link, and the import refuses it.
            header.set_entry_type(EntryType::Symlink);
            header.set_size(0);
            tar.append_link(&mut header, arc, fs::read_link(src)?)?;
        } else {
            header.set_entry_type(EntryType::Regular);
            header.set_size(metadata.size());
            tar.append_data(&mut header, arc, File::open(src)?)?;
        }
    }
    tar.into_inner()?.finish()?;
    Ok(())
}

// ---- Import -----------------------------------------------------------------

/// A checked `.dip` package, unpacked into a temporary folder.
struct Package {
    dir: TempDir,
    head: Value,
    manifest: Value,
}

fn open_archive(path: &Path) -> io::Result<Archive<GzDecoder<File>>> {
    Ok(Archive::new(GzDecoder::new(File::open(path)?)))
}

fn entry_name(raw: &[u8]) -> String {
    String::from_utf8_lossy(raw).into_owned()
}

/// Path parts as `PurePosixPath` sees them.
fn name_parts(name: &str) -> Vec<&str> {
    name.split('/')
        .filter(|p| !p.is_empty() && *p != ".")
        .collect()
}

fn is_regular(kind: EntryType, name: &str) -> bool {
    matches!(
        kind,
        EntryType::Regular | EntryType::Continuous | EntryType::GNUSparse
    ) && !name.ends_with('/')
}

fn is_directory(kind: EntryType, name: &str) -> bool {
    // Old tar files mark folders as regular files with a trailing slash.
    kind == EntryType::Directory || (kind == EntryType::Regular && name.ends_with('/'))
}

impl Package {
    fn open(path: &Path) -> Result<Self, PluginError> {
        if !path.is_file() {
            return fail(format!("{} gibt es nicht", path.display()));
        }
        Self::check_members(path)?;
        let dir = tempfile::Builder::new().prefix("dip-").tempdir()?;
        Self::unpack(path, dir.path())?;
        let root = dir.path();

        let head: Value = fs::read_to_string(root.join("dip.json"))
            .map_err(|e| e.to_string())
            .and_then(|text| serde_json::from_str(&text).map_err(|e| e.to_string()))
            .map_err(|e| PluginError(format!("dip.json fehlt oder ist kaputt: {e}")))?;
        if !head.is_object() {
            return fail("dip.json fehlt oder ist kaputt: kein Objekt");
        }
        if head.get("format").and_then(Value::as_str) != Some(PACKAGE_FORMAT) {
            return fail("dip.json: unbekanntes format");
        }
        let format_version = head
            .get("formatVersion")
            .unwrap_or(&json!(0))
            .as_f64()
            .unwrap_or(0.0);
        #[allow(clippy::cast_precision_loss)]
        if format_version > FORMAT_VERSION as f64 {
            return fail(format!(
                "Paketformat {} ist neuer als diese CLI ({FORMAT_VERSION})",
                text_field(&head, "formatVersion")
            ));
        }

        // Checksums: every file has to be listed and has to match.
        let empty = Map::new();
        let sums = head
            .get("checksums")
            .and_then(Value::as_object)
            .unwrap_or(&empty);
        for file in walk_sorted(root)? {
            let arc = file
                .strip_prefix(root)
                .unwrap_or(&file)
                .to_string_lossy()
                .into_owned();
            if file.is_file() && arc != "dip.json" {
                let Some(expected) = sums.get(&arc) else {
                    return fail(format!("{arc} fehlt in den Pruefsummen"));
                };
                if expected.as_str() != Some(compute_hash(&file)?.as_str()) {
                    return fail(format!("Pruefsumme stimmt nicht: {arc}"));
                }
            }
        }
        for arc in sums.keys() {
            if !root.join(arc).is_file() {
                return fail(format!("{arc} fehlt im Paket"));
            }
        }

        let manifest: Value = fs::read_to_string(root.join("plugin/plugin.json"))
            .map_err(|e| e.to_string())
            .and_then(|text| serde_json::from_str(&text).map_err(|e| e.to_string()))
            .map_err(|e| PluginError(format!("plugin/plugin.json fehlt oder ist kaputt: {e}")))?;
        let problem = check_manifest(&manifest, None);
        if !problem.is_empty() {
            return fail(format!("Manifest: {problem}"));
        }
        let head_id = head.get("plugin").and_then(|p| p.get("id"));
        if head_id != manifest.get("id") {
            return fail("dip.json und plugin.json nennen verschiedene ids");
        }
        if let Some(files) = head.get("files").and_then(Value::as_array) {
            for entry in files {
                home_path(&entry.get("path").map(text_of).unwrap_or_default())?;
                let archive = entry.get("archive").map_or_else(|| "-".to_owned(), text_of);
                if !root.join(&archive).exists() {
                    return fail(format!(
                        "Datei fuer {} fehlt im Paket",
                        text_field(entry, "path")
                    ));
                }
            }
        }
        Ok(Self {
            dir,
            head,
            manifest,
        })
    }

    /// Looks at all names before anything lands on disk.
    fn check_members(path: &Path) -> Result<(), PluginError> {
        let broken = |e: io::Error| PluginError(format!("Kein .dip-Paket (tar.gz erwartet): {e}"));
        let mut archive = open_archive(path).map_err(broken)?;
        let mut found = Vec::new();
        for entry in archive.entries().map_err(broken)? {
            let entry = entry.map_err(broken)?;
            found.push((
                entry_name(&entry.path_bytes()),
                entry.header().entry_type(),
                entry.size(),
            ));
        }
        if found.len() > MAX_MEMBERS {
            return fail("Paket hat zu viele Dateien");
        }
        let mut total = 0u64;
        for (name, kind, size) in found {
            let parts = name_parts(&name);
            // "tar -C dir ." writes an entry "." for the root
            if is_directory(kind, &name) && parts.is_empty() {
                continue;
            }
            if name.starts_with('/') || parts.contains(&"..") {
                return fail(format!(
                    "Unsicherer Pfad im Paket: {}",
                    name.trim_end_matches('/')
                ));
            }
            if !is_regular(kind, &name) && !is_directory(kind, &name) {
                return fail(format!("Nur Dateien und Ordner erlaubt, nicht: {name}"));
            }
            if !parts
                .first()
                .is_some_and(|p| ["dip.json", "plugin", "files"].contains(p))
            {
                return fail(format!(
                    "Unerwarteter Eintrag im Paket: {}",
                    name.trim_end_matches('/')
                ));
            }
            total += size;
        }
        if total > MAX_BYTES {
            return fail("Paket ist entpackt groesser als 512 MB");
        }
        Ok(())
    }

    /// Like `tar.extractall(filter="data")`, the names are checked by now.
    fn unpack(path: &Path, root: &Path) -> Result<(), PluginError> {
        let mut archive = open_archive(path)?;
        for entry in archive.entries()? {
            let mut entry = entry?;
            let name = entry_name(&entry.path_bytes());
            let target = root.join(name_parts(&name).join("/"));
            let kind = entry.header().entry_type();
            if is_directory(kind, &name) {
                fs::create_dir_all(&target)?;
                continue;
            }
            if let Some(parent) = target.parent() {
                fs::create_dir_all(parent)?;
            }
            let mode = entry.header().mode()? & 0o755;
            let mode = (if mode & 0o100 == 0 {
                mode & !0o111
            } else {
                mode
            }) | 0o600;
            let mtime = pax_mtime(&mut entry)
                .or_else(|| entry.header().mtime().ok().map(Duration::from_secs));
            let mut file = File::options()
                .write(true)
                .create(true)
                .truncate(true)
                .mode(mode)
                .open(&target)?;
            io::copy(&mut entry, &mut file)?;
            file.set_permissions(fs::Permissions::from_mode(mode))?;
            if let Some(mtime) = mtime {
                file.set_modified(UNIX_EPOCH + mtime)?;
            }
        }
        Ok(())
    }

    fn plugin_dir(&self) -> PathBuf {
        self.dir.path().join("plugin")
    }
}

/// Python's tarfile stores the modification time with fractions in a PAX header.
fn pax_mtime<R: Read>(entry: &mut tar::Entry<'_, R>) -> Option<Duration> {
    let extensions = entry.pax_extensions().ok()??;
    for extension in extensions.flatten() {
        if extension.key() == Ok("mtime") {
            return extension
                .value()
                .ok()?
                .parse::<f64>()
                .ok()
                .and_then(|s| Duration::try_from_secs_f64(s).ok());
        }
    }
    None
}

fn import(args: &ImportArgs) -> Outcome {
    let path = paths::expand_user(&args.file);
    if path.extension() == Some(OsStr::new("json")) {
        return import_settings(args, &path);
    }
    let package = Package::open(&path)?;
    let m = &package.manifest;
    let pid = text_field(m, "id");
    let name = text_field(m, "name");
    let version = version_of(m, "0");
    let version_text = text_of(&version);

    // Import from the submenu of a plugin: only its components
    if let Some(want) = args.parent.as_deref().filter(|w| !w.is_empty())
        && m.get("parent").and_then(Value::as_str) != Some(want)
    {
        let belongs = match m.get("parent").filter(|p| truthy(p)) {
            Some(parent) => format!(" (gehoert zu \"{}\")", text_of(parent)),
            None => " (eigenstaendiges Plugin)".to_owned(),
        };
        return fail(format!(
            "{name} ist keine Komponente von \"{want}\"{belongs} – oben in der Plugin-Verwaltung importieren"
        ));
    }

    let dir = plugins_dir();
    let target = dir.join(&pid);
    let old = if target.is_dir() {
        load_manifest(&target).ok()
    } else {
        None
    };
    let old_version = old.as_ref().map(|o| text_of(&version_of(o, "0")));

    if target.exists()
        && !args.force
        && let Some(old_version) = &old_version
    {
        let Some(order) = compare_versions(old_version, &version_text) else {
            return fail(format!(
                "Versionen {old_version} und {version_text} lassen sich nicht vergleichen; --force ueberschreibt"
            ));
        };
        if order != Ordering::Less {
            return fail(format!(
                "{name} {old_version} ist schon installiert (Paket: {version_text}); --force ueberschreibt"
            ));
        }
    }

    let files: Vec<Value> = package
        .head
        .get("files")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if !args.json {
        print_import_summary(args, m, &files, &pid, &version_text, old_version.as_deref());
    }
    if !confirm(args.yes, "Importieren?")? {
        return Ok(Some(json!({"ok": false, "message": "Abgebrochen"})));
    }

    // Swap: the old plugin goes to the backups, the new one takes its place.
    fs::create_dir_all(&dir)?;
    let staged = tempfile::Builder::new()
        .prefix(&format!(".{pid}-"))
        .tempdir_in(&dir)?;
    let staged_path = staged.keep();
    fs::remove_dir_all(&staged_path)?;
    let result = (|| {
        copy_tree(&package.plugin_dir(), &staged_path, &[])?;
        let saved = if target.exists() {
            Some(backup(&target, &format!("plugin-{pid}"))?)
        } else {
            None
        };
        fs::rename(&staged_path, &target)?;
        Ok::<_, PluginError>(saved)
    })();
    let saved = match result {
        Ok(saved) => saved,
        Err(e) => {
            let _ = fs::remove_dir_all(&staged_path);
            return Err(e);
        }
    };

    let (installed_files, kept) = if args.files {
        install_files(args, &package, &files)?
    } else {
        (Vec::new(), Vec::new())
    };

    let mut state = read_state()?;
    let first = !state.enabled.contains_key(&pid);
    if args.enable {
        state.enabled.insert(pid.clone(), json!(true));
    } else if first {
        // Foreign code never runs without being asked: freshly imported means off.
        state.enabled.insert(pid.clone(), json!(false));
    }
    let mut applied = false;
    if let Some(settings) = package.head.get("settings").filter(|s| truthy(s))
        && !args.no_settings
        && (args.settings || !state.settings.contains_key(&pid))
    {
        state.settings.insert(pid.clone(), settings.clone());
        applied = true;
    }
    write_state(&state)?;

    let enabled = state.enabled.get(&pid).cloned().unwrap_or(Value::Null);
    let mut message = format!(
        "{name} {version_text} importiert{}",
        if truthy(&enabled) {
            " und eingeschaltet"
        } else {
            " (aus)"
        }
    );
    if applied {
        message.push_str(", Einstellungen uebernommen");
    }
    if !installed_files.is_empty() {
        message.push_str(&format!(
            ", {} Datei(en) installiert",
            installed_files.len()
        ));
    }
    if !kept.is_empty() {
        message.push_str(&format!(
            ", {} abweichende Dateien behalten (--overwrite-files ersetzt sie)",
            kept.len()
        ));
    }
    Ok(Some(json!({
        "ok": true, "message": message, "id": pid, "version": version, "enabled": enabled,
        "settingsApplied": applied, "files": installed_files, "keptFiles": kept,
        "backup": saved.map(|s| s.to_string_lossy().into_owned()),
    })))
}

fn print_import_summary(
    args: &ImportArgs,
    m: &Value,
    files: &[Value],
    pid: &str,
    version: &str,
    old_version: Option<&str>,
) {
    let replaces = old_version.map_or_else(String::new, |o| format!(", ersetzt {o}"));
    println!("{} ({pid}) {version}{replaces}", text_field(m, "name"));
    if m.get("main").is_some_and(truthy) || m.get("tiles").is_some_and(truthy) {
        println!(
            "  Enthaelt QML-Code, der in der Shell laeuft – nur aus vertrauenswuerdiger Quelle!"
        );
    }
    let commands: Vec<String> = m
        .get("keybinds")
        .and_then(Value::as_object)
        .into_iter()
        .flat_map(|binds| binds.values())
        .filter_map(|b| b.get("exec").map(text_of))
        .collect();
    if !commands.is_empty() {
        println!("  Tastenkuerzel mit Shell-Befehlen (laufen erst, wenn das Plugin an ist):");
        for command in commands {
            println!("    {command}");
        }
    }
    if !files.is_empty() {
        let verb = if args.files {
            "werden installiert"
        } else {
            "liegen bei (mit --files installieren)"
        };
        println!("  {} externe Dateien {verb}:", files.len());
        for file in files {
            println!("    {}", text_field(file, "path"));
        }
    }
}

fn file_pairs(src: &Path, dest: &Path) -> io::Result<Vec<(PathBuf, PathBuf)>> {
    if src.is_file() {
        return Ok(vec![(src.to_path_buf(), dest.to_path_buf())]);
    }
    let mut pairs = Vec::new();
    for s in walk_sorted(src)? {
        if s.is_file() {
            let rel = s.strip_prefix(src).unwrap_or(&s).to_path_buf();
            pairs.push((s, dest.join(rel)));
        }
    }
    Ok(pairs)
}

fn install_files(
    args: &ImportArgs,
    package: &Package,
    files: &[Value],
) -> Result<(Vec<String>, Vec<String>), PluginError> {
    let (mut done, mut kept) = (Vec::new(), Vec::new());
    for entry in files {
        let Some(archive) = entry.get("archive") else {
            return fail("files: Eintrag ohne archive");
        };
        let src = package.dir.path().join(text_of(archive));
        let dest = home_path(&entry.get("path").map(text_of).unwrap_or_default())?;
        for (s, d) in file_pairs(&src, &dest)? {
            if d.is_file() && compute_hash(&d)? == compute_hash(&s)? {
                continue;
            }
            if d.exists() || d.is_symlink() {
                if !args.overwrite_files {
                    kept.push(d.to_string_lossy().into_owned());
                    continue;
                }
                backup(&d, &format!("file-{}", folder_name(&d)))?;
            }
            if let Some(parent) = d.parent() {
                fs::create_dir_all(parent)?;
            }
            copy2(&s, &d)?;
            done.push(d.to_string_lossy().into_owned());
        }
    }
    Ok((done, kept))
}

fn import_settings(args: &ImportArgs, path: &Path) -> Outcome {
    let doc: Value = fs::read_to_string(path)
        .map_err(|e| e.to_string())
        .and_then(|text| serde_json::from_str(&text).map_err(|e| e.to_string()))
        .map_err(|e| PluginError(format!("{}: {e}", path.display())))?;
    if doc.get("format").and_then(Value::as_str) != Some(SETTINGS_FORMAT) {
        return fail(format!(
            "{}: kein Einstellungs-Export (format \"{SETTINGS_FORMAT}\" erwartet)",
            path.display()
        ));
    }
    let pid = doc
        .get("plugin")
        .and_then(|p| p.get("id"))
        .map(text_of)
        .unwrap_or_default();
    let (_, m) = require(&pid)?;
    let name = text_field(&m, "name");
    let empty = Map::new();
    let spec = m
        .get("settings")
        .and_then(Value::as_object)
        .unwrap_or(&empty);
    let given = doc
        .get("settings")
        .and_then(Value::as_object)
        .unwrap_or(&empty);
    let values: Map<String, Value> = given
        .iter()
        .filter(|(k, _)| spec.contains_key(*k))
        .map(|(k, v)| (k.clone(), v.clone()))
        .collect();
    let dropped: BTreeSet<&String> = given.keys().filter(|k| !spec.contains_key(*k)).collect();
    if !confirm(args.yes, &format!("Einstellungen fuer {name} ersetzen?"))? {
        return Ok(Some(json!({"ok": false, "message": "Abgebrochen"})));
    }
    let count = values.len();
    let mut state = read_state()?;
    state.settings.insert(pid.clone(), Value::Object(values));
    write_state(&state)?;
    let mut message = format!("Einstellungen fuer {name} uebernommen ({count} Werte)");
    if !dropped.is_empty() {
        let names: Vec<&str> = dropped.iter().map(|s| s.as_str()).collect();
        message.push_str(&format!("; unbekannt und ignoriert: {}", names.join(", ")));
    }
    Ok(Some(
        json!({"ok": true, "message": message, "id": pid, "settingsApplied": true}),
    ))
}

// ---- remove / new ------------------------------------------------------------

fn remove(args: &RemoveArgs) -> Outcome {
    let pid = &args.id;
    let folder = plugins_dir().join(pid);
    if !id_ok(pid) || !folder.is_dir() {
        return fail(format!("Plugin \"{pid}\" gibt es nicht"));
    }
    if let Ok(m) = load_manifest(&folder)
        && m.get("builtin").is_some_and(truthy)
        && !args.force
    {
        return fail(format!(
            "{} gehoert zur Shell (builtin) – nur ausschalten, oder --force",
            text_field(&m, "name")
        ));
    }
    let question = format!(
        "{pid} entfernen (der Ordner wandert in {})?",
        backups_dir().display()
    );
    if !confirm(args.yes, &question)? {
        return Ok(Some(json!({"ok": false, "message": "Abgebrochen"})));
    }
    let saved = backup(&folder, &format!("plugin-{pid}"))?;
    if !args.keep_settings {
        let mut state = read_state()?;
        state.enabled.shift_remove(pid);
        state.settings.shift_remove(pid);
        write_state(&state)?;
    }
    let message = format!("{pid} entfernt, Sicherung: {}", saved.display());
    Ok(Some(
        json!({"ok": true, "message": message, "id": pid, "backup": saved.to_string_lossy()}),
    ))
}

/// `str.title()` for ids: upper case after everything that is not a letter.
fn title_case(text: &str) -> String {
    let mut after_letter = false;
    text.chars()
        .map(|c| {
            let out = if after_letter {
                c
            } else {
                c.to_ascii_uppercase()
            };
            after_letter = c.is_ascii_alphabetic();
            out
        })
        .collect()
}

fn new(args: &NewArgs) -> Outcome {
    let pid = &args.id;
    if !id_ok(pid) {
        return fail("id: nur a-z, 0-9 und -, hoechstens 48 Zeichen");
    }
    let template = plugins_dir().join("_example");
    let target = plugins_dir().join(pid);
    if target.exists() {
        return fail(format!("{} gibt es schon", target.display()));
    }
    if !template.is_dir() {
        return fail(format!("Vorlage {} fehlt", template.display()));
    }
    let name = args
        .name
        .clone()
        .filter(|n| !n.is_empty())
        .unwrap_or_else(|| title_case(&pid.replace('-', " ")));
    copy_tree(&template, &target, &SKIP_NAMES)?;
    let manifest_path = target.join("plugin.json");
    let mut m: Map<String, Value> = serde_json::from_str(&fs::read_to_string(&manifest_path)?)?;
    m.insert("id".into(), json!(pid));
    m.insert("name".into(), json!(name));
    m.insert("version".into(), json!("0.1.0"));
    m.insert("defaultEnabled".into(), json!(false));
    if let Some(author) = args.author.as_deref().filter(|a| !a.is_empty()) {
        m.insert("author".into(), json!(author));
    }
    fs::write(
        &manifest_path,
        dumps(&Value::Object(m), pyjson::pretty(4)) + "\n",
    )?;
    let message = format!(
        "Neues Plugin angelegt: {} (aus; einschalten: dynamic-island plugin enable {pid})",
        target.display()
    );
    Ok(Some(
        json!({"ok": true, "message": message, "id": pid, "dir": target.to_string_lossy()}),
    ))
}
