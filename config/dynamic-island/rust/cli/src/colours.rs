//! `dynamic-island scheme` and `dynamic-island wallpaper`.
//!
//! Everything except the colour calculation itself runs here. Whatever is not in
//! the cache yet goes to `bin/dynamic-island-colours` (Python), see there for why.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use clap::{Args, Parser, Subcommand};
use di_common::fsutil::{atomic_dump, read_text, resolve};
use di_common::hash::compute_hash;
use di_common::paths;
use di_common::pyjson::{self, dumps, text_of};
use serde_json::{Map, Value, json};

use crate::hypr;
use crate::theme;

pub const VARIANTS: [&str; 9] = [
    "tonalspot",
    "vibrant",
    "expressive",
    "fidelity",
    "fruitsalad",
    "monochrome",
    "neutral",
    "rainbow",
    "content",
];
/// `VERSION` in `colourfulness.py`, older `smart.json` files are computed again.
const SMART_VERSION: u64 = 2;

pub type Res<T> = Result<T, String>;

// ---- Command line --------------------------------------------------------------

#[derive(Parser)]
#[command(
    name = "scheme",
    disable_help_flag = true,
    disable_help_subcommand = true
)]
pub struct SchemeCli {
    #[command(subcommand)]
    action: SchemeAction,
}

#[derive(Subcommand)]
enum SchemeAction {
    List(ListArgs),
    Get(GetArgs),
    Set(SetArgs),
}

#[derive(Args)]
struct ListArgs {
    #[arg(short, long)]
    names: bool,
    #[arg(short, long)]
    flavours: bool,
    #[arg(short, long)]
    modes: bool,
    #[arg(short, long)]
    variants: bool,
}

#[derive(Args)]
struct GetArgs {
    #[arg(short, long)]
    name: bool,
    #[arg(short, long)]
    flavour: bool,
    #[arg(short, long)]
    mode: bool,
    #[arg(short, long)]
    variant: bool,
}

#[derive(Args)]
struct SetArgs {
    #[arg(long)]
    notify: bool,
    #[arg(short, long)]
    random: bool,
    #[arg(short, long)]
    name: Option<String>,
    #[arg(short, long)]
    flavour: Option<String>,
    #[arg(short, long)]
    mode: Option<String>,
    #[arg(short, long)]
    variant: Option<String>,
}

#[derive(Parser)]
#[command(name = "wallpaper", disable_help_flag = true)]
pub struct WallpaperCli {
    #[arg(short, long, num_args = 0..=1)]
    print: Option<Option<String>>,
    #[arg(short, long, num_args = 0..=1)]
    random: Option<Option<String>>,
    #[arg(short, long)]
    file: Option<String>,
    #[arg(short = 'n', long)]
    no_filter: bool,
    #[arg(short = 'N', long)]
    no_smart: bool,
    #[arg(short, long)]
    variant: Option<String>,
    #[arg(long = "for")]
    target: Option<String>,
}

impl SchemeCli {
    /// Choices that argparse checks. A wrong one goes to Python for its error message.
    pub fn is_valid(&self) -> bool {
        let SchemeAction::Set(args) = &self.action else {
            return true;
        };
        args.name
            .as_ref()
            .is_none_or(|n| scheme_names().is_ok_and(|names| names.contains(n)))
            && args
                .mode
                .as_deref()
                .is_none_or(|m| m == "dark" || m == "light")
            && args
                .variant
                .as_deref()
                .is_none_or(|v| VARIANTS.contains(&v))
    }
}

impl WallpaperCli {
    pub fn is_valid(&self) -> bool {
        self.variant
            .as_deref()
            .is_none_or(|v| v == "auto" || VARIANTS.contains(&v))
    }
}

// ---- Paths ---------------------------------------------------------------------

fn data_dir() -> PathBuf {
    // <root>/bin/dynamic-island and <root>/src/dynamic_island/data
    let cli = resolve(&crate::python_cli());
    let root = cli
        .parent()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .unwrap_or_default();
    root.join("src/dynamic_island/data")
}

pub fn templates_dir() -> PathBuf {
    data_dir().join("templates")
}

fn scheme_data_dir() -> PathBuf {
    data_dir().join("schemes")
}

fn scheme_path() -> PathBuf {
    paths::c_state_dir().join("scheme.json")
}

fn scheme_cache_dir() -> PathBuf {
    paths::c_cache_dir().join("schemes")
}

fn wallpapers_cache_dir() -> PathBuf {
    paths::c_cache_dir().join("wallpapers")
}

fn wallpaper_state(name: &str) -> PathBuf {
    paths::c_state_dir().join("wallpaper").join(name)
}

fn wallpapers_dir() -> PathBuf {
    let pictures = std::env::var_os("XDG_PICTURES_DIR")
        .map_or_else(|| paths::home().join("Pictures"), PathBuf::from);
    paths::override_or("WALLPAPERS_DIR", || pictures.join("Wallpapers"))
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// Names in directory order, like `Path.iterdir()`.
fn entries(dir: &Path, keep: impl Fn(&Path) -> bool) -> Res<Vec<String>> {
    let mut out = Vec::new();
    for entry in fs::read_dir(dir).map_err(|e| format!("{}: {e}", dir.display()))? {
        let path = entry.map_err(err)?.path();
        if keep(&path)
            && let Some(name) = path.file_name()
        {
            out.push(name.to_string_lossy().into_owned());
        }
    }
    Ok(out)
}

fn scheme_names() -> Res<Vec<String>> {
    let mut names = entries(&scheme_data_dir(), Path::is_dir)?;
    names.push("dynamic".to_owned());
    Ok(names)
}

fn flavours_of(name: &str) -> Res<Vec<String>> {
    if name == "dynamic" {
        return Ok(vec!["default".to_owned(), "hard".to_owned()]);
    }
    entries(&scheme_data_dir().join(name), Path::is_dir)
}

fn modes_of(name: &str, flavour: &str) -> Res<Vec<String>> {
    if name == "dynamic" {
        return Ok(vec!["light".to_owned(), "dark".to_owned()]);
    }
    let stems = entries(&scheme_data_dir().join(name).join(flavour), Path::is_file)?;
    Ok(stems
        .into_iter()
        .map(|s| {
            Path::new(&s)
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned()
        })
        .collect())
}

/// `str(list_of_strings)`
fn list_repr(items: &[String]) -> String {
    let parts: Vec<String> = items.iter().map(|s| format!("'{s}'")).collect();
    format!("[{}]", parts.join(", "))
}

fn notify(summary: &str, body: &str) -> Res<()> {
    let output = Command::new("notify-send")
        .args(["-a", "dynamic-island", "-u", "critical", summary, body])
        .output()
        .map_err(err)?;
    if !output.status.success() {
        return Err("notify-send gescheitert".to_owned());
    }
    Ok(())
}

// ---- The colour calculator --------------------------------------------------------

fn engine(args: &[&str]) -> Res<String> {
    let path = crate::python_cli().with_file_name("dynamic-island-colours");
    let output = Command::new(&path)
        .args(args)
        .output()
        .map_err(|e| format!("{}: {e}", path.display()))?;
    if !output.status.success() {
        return Err(format!(
            "Farbrechner: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout)
        .trim_end_matches('\n')
        .to_owned())
}

fn path_arg(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

fn get_thumb(wall: &Path, cache: &Path) -> Res<PathBuf> {
    let thumb = cache.join("thumbnail.jpg");
    if !thumb.exists() {
        engine(&["thumb", &path_arg(wall), &path_arg(cache)])?;
    }
    Ok(thumb)
}

fn convert_gif(wall: &Path) -> Res<PathBuf> {
    let hash = compute_hash(wall).map_err(err)?;
    let output = wallpapers_cache_dir().join(hash).join("first_frame.png");
    if !output.exists() {
        engine(&["gif", &path_arg(wall)])?;
    }
    Ok(output)
}

fn is_gif(wall: &Path) -> bool {
    wall.extension()
        .is_some_and(|e| e.to_string_lossy().eq_ignore_ascii_case("gif"))
}

fn get_smart_opts(wall: &Path, cache: &Path) -> Res<Value> {
    if let Ok(text) = read_text(&cache.join("smart.json"))
        && let Ok(opts) = serde_json::from_str::<Value>(&text)
        && opts.get("version").and_then(Value::as_u64) == Some(SMART_VERSION)
    {
        return Ok(opts);
    }
    serde_json::from_str(&engine(&["smart", &path_arg(wall), &path_arg(cache)])?).map_err(err)
}

/// Why a calculation failed: a missing image means "no wallpaper set".
enum ColourError {
    NoImage,
    Other(String),
}

fn colours_for_image(
    image: &Path,
    variant: &str,
    flavour: &str,
    mode: &str,
) -> Result<Map<String, Value>, ColourError> {
    let hash = compute_hash(image).map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            ColourError::NoImage
        } else {
            ColourError::Other(e.to_string())
        }
    })?;
    let cache = scheme_cache_dir()
        .join(hash)
        .join(variant)
        .join(flavour)
        .join(format!("{mode}.json"));
    if let Ok(text) = fs::read_to_string(&cache)
        && let Ok(Value::Object(colours)) = serde_json::from_str(&text)
    {
        return Ok(colours);
    }
    let text = engine(&["colours", &path_arg(image), variant, flavour, mode])
        .map_err(ColourError::Other)?;
    match serde_json::from_str(&text) {
        Ok(Value::Object(colours)) => Ok(colours),
        _ => Err(ColourError::Other("Farbrechner: keine Farben".to_owned())),
    }
}

// ---- Scheme ------------------------------------------------------------------------

fn read_colours_from_file(path: &Path) -> Res<Map<String, Value>> {
    let text = read_text(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut colours = Map::new();
    for line in text.lines().filter(|l| !l.is_empty()) {
        let parts: Vec<&str> = line.split(' ').collect();
        let [key, value] = parts.as_slice() else {
            return Err(format!("{}: ungueltige Zeile: {line}", path.display()));
        };
        colours.insert(key.trim().to_owned(), json!(value.trim()));
    }
    Ok(colours)
}

pub struct Scheme {
    pub name: String,
    pub flavour: String,
    pub mode: String,
    pub variant: String,
    pub colours: Map<String, Value>,
    notify: bool,
}

impl Scheme {
    fn colours_path(&self) -> PathBuf {
        scheme_data_dir()
            .join(&self.name)
            .join(&self.flavour)
            .join(format!("{}.txt", self.mode))
    }

    fn load() -> Res<Self> {
        let parsed = read_text(&scheme_path())
            .ok()
            .and_then(|text| serde_json::from_str::<Value>(&text).ok());
        let Some(data) = parsed else {
            let mut scheme = Self {
                name: "catppuccin".to_owned(),
                flavour: "mocha".to_owned(),
                mode: "dark".to_owned(),
                variant: "tonalspot".to_owned(),
                colours: Map::new(),
                notify: false,
            };
            scheme.colours = read_colours_from_file(&scheme.colours_path())?;
            scheme.save()?;
            return Ok(scheme);
        };
        let field = |key: &str| {
            data.get(key)
                .map(text_of)
                .ok_or_else(|| format!("scheme.json: {key} fehlt"))
        };
        let colours = data
            .get("colours")
            .and_then(Value::as_object)
            .cloned()
            .ok_or("scheme.json: colours fehlt")?;
        Ok(Self {
            name: field("name")?,
            flavour: field("flavour")?,
            mode: field("mode")?,
            variant: field("variant")?,
            colours,
            notify: false,
        })
    }

    fn save(&self) -> Res<()> {
        let path = scheme_path();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(err)?;
        }
        let doc = json!({
            "name": self.name, "flavour": self.flavour, "mode": self.mode, "variant": self.variant,
            "colours": self.colours,
        });
        atomic_dump(&path, &doc).map_err(err)?;
        Ok(())
    }

    fn update_colours(&mut self) -> Res<()> {
        if self.name != "dynamic" {
            self.colours = read_colours_from_file(&self.colours_path())?;
            return Ok(());
        }
        let thumbnail = wallpaper_state("thumbnail.jpg");
        match colours_for_image(&thumbnail, &self.variant, &self.flavour, &self.mode) {
            Ok(colours) => {
                self.colours = colours;
                Ok(())
            }
            Err(ColourError::NoImage) => {
                let message = "No wallpaper set. Please set a wallpaper via `dynamic-island wallpaper` before setting a dynamic scheme.";
                if self.notify {
                    notify("Unable to set dynamic scheme", message)?;
                }
                Err(message.to_owned())
            }
            Err(ColourError::Other(message)) => Err(message),
        }
    }

    fn set_name(&mut self, name: &str) -> Res<bool> {
        if name == self.name {
            return Ok(false);
        }
        let names = scheme_names()?;
        if !names.iter().any(|n| n == name) {
            if self.notify {
                let body = format!(
                    "\"{name}\" is not a valid scheme.\nValid schemes are: {}",
                    list_repr(&names)
                );
                notify("Unable to set scheme", &body)?;
            }
            return Err(format!("Invalid scheme name: {name}"));
        }
        self.name = name.to_owned();
        let flavours = flavours_of(&self.name)?;
        if !flavours.contains(&self.flavour) {
            self.flavour = flavours.first().cloned().ok_or("Schema ohne Flavour")?;
        }
        let modes = modes_of(&self.name, &self.flavour)?;
        if !modes.contains(&self.mode) {
            self.mode = modes.first().cloned().ok_or("Schema ohne Modus")?;
        }
        Ok(true)
    }

    fn set_flavour(&mut self, flavour: &str) -> Res<bool> {
        if flavour == self.flavour {
            return Ok(false);
        }
        let flavours = flavours_of(&self.name)?;
        if !flavours.iter().any(|f| f == flavour) {
            if self.notify {
                let body = format!(
                    "\"{flavour}\" is not a valid flavour of scheme \"{}\".\nValid flavours are: {}",
                    self.name,
                    list_repr(&flavours)
                );
                notify("Unable to set scheme flavour", &body)?;
            }
            return Err(format!(
                "Invalid scheme flavour: \"{flavour}\". Valid flavours: {}",
                list_repr(&flavours)
            ));
        }
        self.flavour = flavour.to_owned();
        let modes = modes_of(&self.name, &self.flavour)?;
        if !modes.contains(&self.mode) {
            self.mode = modes.first().cloned().ok_or("Schema ohne Modus")?;
        }
        Ok(true)
    }

    fn set_mode(&mut self, mode: &str) -> Res<bool> {
        if mode == self.mode {
            return Ok(false);
        }
        let modes = modes_of(&self.name, &self.flavour)?;
        if !modes.iter().any(|m| m == mode) {
            if self.notify {
                let body = format!(
                    "Scheme \"{} {}\" does not have a {mode} mode.",
                    self.name, self.flavour
                );
                notify("Unable to set scheme mode", &body)?;
            }
            return Err(format!(
                "Invalid scheme mode: \"{mode}\". Valid modes: {}",
                list_repr(&modes)
            ));
        }
        self.mode = mode.to_owned();
        Ok(true)
    }

    fn set_variant(&mut self, variant: &str) -> bool {
        if variant == self.variant {
            return false;
        }
        self.variant = variant.to_owned();
        true
    }

    /// The end of `with scheme.batch()`: colours once for the finished state, one write.
    fn finish_batch(&mut self, stale: bool) -> Res<()> {
        if stale {
            self.update_colours()?;
            self.save()?;
        }
        Ok(())
    }

    fn describe(&self) -> Res<String> {
        let mut lines = Vec::new();
        for (name, colour) in &self.colours {
            let c = text_of(colour);
            let channel = |range: std::ops::Range<usize>| {
                c.get(range)
                    .and_then(|p| u8::from_str_radix(p, 16).ok())
                    .ok_or_else(|| format!("ungueltige Farbe {c}"))
            };
            lines.push(format!(
                "{name}: \x1b[38;2;{};{};{}m{c}\x1b[0m",
                channel(0..2)?,
                channel(2..4)?,
                channel(4..6)?
            ));
        }
        Ok(format!(
            "Current scheme:\n    Name: {}\n    Flavour: {}\n    Mode: {}\n    Variant: {}\n    Colours:\n        {}",
            self.name,
            self.flavour,
            self.mode,
            self.variant,
            lines.join("\n        ")
        ))
    }
}

fn random_index(len: usize) -> Res<usize> {
    use std::io::Read;
    if len == 0 {
        return Err("Nichts zur Auswahl".to_owned());
    }
    let mut bytes = [0u8; 8];
    fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut bytes))
        .map_err(err)?;
    let value = u64::from_ne_bytes(bytes);
    usize::try_from(value % len as u64).map_err(err)
}

fn choose(items: &[String]) -> Res<String> {
    Ok(items[random_index(items.len())?].clone())
}

// ---- scheme ------------------------------------------------------------------------

pub fn run_scheme(cli: &SchemeCli) -> Res<()> {
    match &cli.action {
        SchemeAction::Get(args) => scheme_get(args),
        SchemeAction::List(args) => scheme_list(args),
        SchemeAction::Set(args) => scheme_set(args),
    }
}

fn scheme_get(args: &GetArgs) -> Res<()> {
    let scheme = Scheme::load()?;
    if !(args.name || args.flavour || args.mode || args.variant) {
        println!("{}", scheme.describe()?);
        return Ok(());
    }
    for (wanted, value) in [
        (args.name, &scheme.name),
        (args.flavour, &scheme.flavour),
        (args.mode, &scheme.mode),
        (args.variant, &scheme.variant),
    ] {
        if wanted {
            println!("{value}");
        }
    }
    Ok(())
}

fn scheme_list(args: &ListArgs) -> Res<()> {
    let wanted = [args.names, args.flavours, args.modes, args.variants];
    if wanted.contains(&true) {
        let multiple = wanted.iter().filter(|w| **w).count() > 1;
        let show = |label: &str, items: Vec<String>| {
            if multiple {
                println!("{label}: {}", items.join(" "));
            } else {
                println!("{}", items.join("\n"));
            }
        };
        if args.names {
            show("Names", scheme_names()?);
        }
        if args.flavours {
            let scheme = Scheme::load()?;
            show("Flavours", flavours_of(&scheme.name)?);
        }
        if args.modes {
            let scheme = Scheme::load()?;
            show("Modes", modes_of(&scheme.name, &scheme.flavour)?);
        }
        if args.variants {
            show(
                "Variants",
                VARIANTS.iter().map(ToString::to_string).collect(),
            );
        }
        return Ok(());
    }

    let current = Scheme::load()?;
    let mut schemes = Map::new();
    for name in scheme_names()? {
        let mut flavours = Map::new();
        for flavour in flavours_of(&name)? {
            let modes = modes_of(&name, &flavour)?;
            // A scheme without a readable mode file (a dangling symlink after a
            // fresh clone) used to crash the whole list, better skip it.
            if modes.is_empty() {
                continue;
            }
            let mode = if modes.contains(&current.mode) {
                current.mode.clone()
            } else {
                modes[0].clone()
            };
            if name == "dynamic" {
                // The flavour does not count here: `get_colours_for_image()` uses the current scheme.
                let thumbnail = wallpaper_state("thumbnail.jpg");
                match colours_for_image(
                    &thumbnail,
                    &current.variant,
                    &current.flavour,
                    &current.mode,
                ) {
                    Ok(colours) => {
                        flavours.insert(flavour, Value::Object(colours));
                    }
                    Err(ColourError::NoImage) => {}
                    Err(ColourError::Other(message)) => return Err(message),
                }
            } else {
                let path = scheme_data_dir()
                    .join(&name)
                    .join(&flavour)
                    .join(format!("{mode}.txt"));
                if let Ok(colours) = read_colours_from_file(&path) {
                    flavours.insert(flavour, Value::Object(colours));
                }
            }
        }
        schemes.insert(name, Value::Object(flavours));
    }
    println!("{}", dumps(&Value::Object(schemes), pyjson::DEFAULT));
    Ok(())
}

fn scheme_set(args: &SetArgs) -> Res<()> {
    let mut scheme = Scheme::load()?;
    scheme.notify = args.notify;

    if args.random {
        scheme.name = choose(&scheme_names()?)?;
        scheme.flavour = choose(&flavours_of(&scheme.name)?)?;
        scheme.mode = choose(&modes_of(&scheme.name, &scheme.flavour)?)?;
        scheme.update_colours()?;
        scheme.save()?;
        return theme::apply_colours(&scheme.colours, &scheme.mode, &scheme);
    }
    if args.name.is_none()
        && args.flavour.is_none()
        && args.mode.is_none()
        && args.variant.is_none()
    {
        println!(
            "No args given. Use --name, --flavour, --mode, --variant or --random to set a scheme"
        );
        return Ok(());
    }

    let mut stale = false;
    if let Some(name) = &args.name {
        stale |= scheme.set_name(name)?;
    }
    if let Some(flavour) = &args.flavour {
        stale |= scheme.set_flavour(flavour)?;
    }
    if let Some(mode) = &args.mode {
        stale |= scheme.set_mode(mode)?;
    }
    if let Some(variant) = &args.variant {
        stale |= scheme.set_variant(variant);
    }
    scheme.finish_batch(stale)?;
    theme::apply_colours(&scheme.colours, &scheme.mode, &scheme)?;

    // In the dynamic scheme the style belongs to the wallpaper: remember it, so
    // it comes back the next time this image is set.
    if let Some(variant) = &args.variant
        && scheme.name == "dynamic"
        && let Some(wall) = get_wallpaper().filter(|w| !w.is_empty())
    {
        set_wall_variant(Path::new(&wall), Some(variant))?;
    }
    Ok(())
}

// ---- Wallpaper ---------------------------------------------------------------------

fn get_wallpaper() -> Option<String> {
    read_text(&wallpaper_state("path.txt")).ok()
}

fn is_valid_image(path: &Path) -> bool {
    path.is_file()
        && path
            .extension()
            .and_then(|e| e.to_str())
            .is_some_and(|e| ["jpg", "jpeg", "png", "webp", "tif", "tiff", "gif"].contains(&e))
}

fn wall_variants() -> Map<String, Value> {
    read_text(&wallpaper_state("variants.json"))
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        .and_then(|v| v.as_object().cloned())
        .unwrap_or_default()
}

fn wall_key(wall: &Path) -> String {
    resolve(wall).to_string_lossy().into_owned()
}

fn get_wall_variant(wall: &Path) -> Option<String> {
    wall_variants().get(&wall_key(wall)).map(text_of)
}

fn set_wall_variant(wall: &Path, variant: Option<&str>) -> Res<()> {
    let mut variants = wall_variants();
    let key = wall_key(wall);
    match variant {
        Some(variant) => {
            variants.insert(key, json!(variant));
        }
        None => {
            variants.shift_remove(&key);
        }
    }
    let mut sorted: Vec<(String, Value)> = variants.into_iter().collect();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    let path = wallpaper_state("variants.json");
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(err)?;
    }
    atomic_dump(&path, &Value::Object(sorted.into_iter().collect())).map_err(err)?;
    Ok(())
}

fn apply_wall_variant(variant: Option<&str>, target: Option<&str>) -> Res<()> {
    let current = get_wallpaper().filter(|c| !c.is_empty());
    let chosen = target
        .map(ToOwned::to_owned)
        .or_else(|| current.clone())
        .unwrap_or_default();
    let wall = resolve(Path::new(&chosen));
    set_wall_variant(&wall, variant)?;

    if current.is_none_or(|c| resolve(Path::new(&c)) != wall) {
        return Ok(());
    }
    let mut scheme = Scheme::load()?;
    if scheme.name != "dynamic" {
        return Ok(());
    }
    let new_variant = match variant {
        Some(variant) => variant.to_owned(),
        None => {
            let wall_cache = if is_gif(&wall) {
                convert_gif(&wall)?
            } else {
                wall.clone()
            };
            let hash = compute_hash(&wall_cache).map_err(err)?;
            let opts = get_smart_opts(&wall_cache, &wallpapers_cache_dir().join(hash))?;
            opts.get("variant")
                .map(text_of)
                .ok_or("smart.json: variant fehlt")?
        }
    };
    if scheme.set_variant(&new_variant) {
        scheme.update_colours()?;
        scheme.save()?;
    }
    theme::apply_colours(&scheme.colours, &scheme.mode, &scheme)
}

fn colours_for_wall(wall: &str, no_smart: bool) -> Res<Value> {
    let wall = PathBuf::from(wall);
    let scheme = Scheme::load()?;
    let pinned = get_wall_variant(&wall);

    // Like set_wallpaper: for GIFs the cache belongs to the first frame.
    let wall = if is_gif(&wall) {
        convert_gif(&wall)?
    } else {
        wall
    };
    let cache = wallpapers_cache_dir().join(compute_hash(&wall).map_err(err)?);

    let (mut mode, mut variant) = (scheme.mode.clone(), scheme.variant.clone());
    if !no_smart {
        let opts = get_smart_opts(&wall, &cache)?;
        mode = opts
            .get("mode")
            .map(text_of)
            .ok_or("smart.json: mode fehlt")?;
        variant = opts
            .get("variant")
            .map(text_of)
            .ok_or("smart.json: variant fehlt")?;
    }
    let is_pinned = pinned.is_some();
    let variant = pinned.filter(|p| !p.is_empty()).unwrap_or(variant);
    let thumb = get_thumb(&wall, &cache)?;
    let colours =
        colours_for_image(&thumb, &variant, &scheme.flavour, &mode).map_err(|e| match e {
            ColourError::NoImage => "Vorschaubild fehlt".to_owned(),
            ColourError::Other(message) => message,
        })?;
    Ok(json!({
        "name": "dynamic", "flavour": scheme.flavour, "mode": mode, "variant": variant,
        "pinned": is_pinned, "colours": colours,
    }))
}

fn replace_symlink(link: &Path, target: &Path) -> Res<()> {
    if let Some(parent) = link.parent() {
        fs::create_dir_all(parent).map_err(err)?;
    }
    match fs::remove_file(link) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e.to_string()),
    }
    std::os::unix::fs::symlink(target, link).map_err(err)
}

fn set_wallpaper(wall: &str, no_smart: bool) -> Res<()> {
    let wall = resolve(Path::new(wall));
    if !is_valid_image(&wall) {
        return Err(format!("\"{}\" is not a valid image", wall.display()));
    }
    // A GIF's first frame is only for the thumbnail.
    let wall_cache = if is_gif(&wall) {
        convert_gif(&wall)?
    } else {
        wall.clone()
    };

    let path_file = wallpaper_state("path.txt");
    if let Some(parent) = path_file.parent() {
        fs::create_dir_all(parent).map_err(err)?;
    }
    fs::write(&path_file, wall.to_string_lossy().as_bytes()).map_err(err)?;
    replace_symlink(&wallpaper_state("current"), &wall)?;

    let cache = wallpapers_cache_dir().join(compute_hash(&wall_cache).map_err(err)?);
    let thumb = get_thumb(&wall_cache, &cache)?;
    replace_symlink(&wallpaper_state("thumbnail.jpg"), &thumb)?;

    let mut scheme = Scheme::load()?;

    // In one batch: scheme.json is written once, with the finished state, instead
    // of up to three times (mode, variant, colours), and the shell recolours once.
    if scheme.name == "dynamic" {
        let pinned = get_wall_variant(&wall).filter(|p| !p.is_empty());
        if !no_smart {
            let opts = get_smart_opts(&wall_cache, &cache)?;
            let mode = opts
                .get("mode")
                .map(text_of)
                .ok_or("smart.json: mode fehlt")?;
            let auto = opts
                .get("variant")
                .map(text_of)
                .ok_or("smart.json: variant fehlt")?;
            scheme.set_mode(&mode)?;
            scheme.set_variant(pinned.as_deref().unwrap_or(&auto));
        } else if let Some(pinned) = &pinned {
            scheme.set_variant(pinned);
        }
    }
    scheme.finish_batch(true)?;
    theme::apply_colours(&scheme.colours, &scheme.mode, &scheme)?;

    let config = theme::get_config();
    if let Some(hook) = config
        .get("wallpaper")
        .and_then(|w| w.get("postHook"))
        .filter(|h| di_common::pyjson::truthy(h))
    {
        let mut command = Command::new("/bin/sh");
        command
            .arg("-c")
            .arg(text_of(hook))
            .stderr(std::process::Stdio::null());
        command
            .env("WALLPAPER_PATH", &wall)
            .env("THUMBNAIL_PATH", &thumb);
        scheme.hook_env(&mut command);
        let _ = command.status();
    }
    Ok(())
}

impl Scheme {
    pub fn hook_env(&self, command: &mut Command) {
        command
            .env("SCHEME_NAME", &self.name)
            .env("SCHEME_FLAVOUR", &self.flavour)
            .env("SCHEME_MODE", &self.mode)
            .env("SCHEME_VARIANT", &self.variant)
            .env(
                "SCHEME_COLOURS",
                dumps(&Value::Object(self.colours.clone()), pyjson::DEFAULT),
            );
    }
}

fn collect_images(dir: &Path, out: &mut Vec<PathBuf>) -> Res<()> {
    for entry in fs::read_dir(dir).map_err(err)? {
        let entry = entry.map_err(err)?;
        let path = entry.path();
        if entry.file_type().map_err(err)?.is_dir() {
            collect_images(&path, out)?;
        } else if is_valid_image(&path) {
            out.push(path);
        }
    }
    Ok(())
}

fn get_wallpapers(directory: &Path, no_filter: bool) -> Res<Vec<PathBuf>> {
    if !directory.is_dir() {
        return Ok(Vec::new());
    }
    let mut walls = Vec::new();
    collect_images(directory, &mut walls)?;
    if no_filter {
        return Ok(walls);
    }
    let monitors = hypr::message("monitors")?;
    let list = monitors.as_array().ok_or("Hyprland: keine Monitorliste")?;
    let smallest = |key: &str| {
        list.iter()
            .filter_map(|m| m.get(key)?.as_f64())
            .reduce(f64::min)
    };
    let (Some(width), Some(height)) = (smallest("width"), smallest("height")) else {
        return Err("Hyprland: keine Monitore".to_owned());
    };
    let threshold = 0.8;
    let mut kept = Vec::new();
    for wall in walls {
        let size = imagesize::size(&wall).map_err(|e| format!("{}: {e}", wall.display()))?;
        #[allow(clippy::cast_precision_loss)]
        if size.width as f64 >= width * threshold && size.height as f64 >= height * threshold {
            kept.push(wall);
        }
    }
    Ok(kept)
}

fn set_random(directory: &Path, no_filter: bool, no_smart: bool) -> Res<()> {
    let mut wallpapers = get_wallpapers(directory, no_filter)?;
    if wallpapers.is_empty() {
        return Err("No valid wallpapers found".to_owned());
    }
    if let Some(last) = get_wallpaper() {
        let last = PathBuf::from(last);
        wallpapers.retain(|w| *w != last);
    }
    let index = random_index(wallpapers.len())?;
    set_wallpaper(&wallpapers[index].to_string_lossy(), no_smart)
}

pub fn run_wallpaper(cli: &WallpaperCli) -> Res<()> {
    // Style per image: with -f it applies to the new image, otherwise to --for or
    // the current one. "auto" takes the fixed choice back.
    if let Some(chosen) = &cli.variant {
        let variant = (chosen != "auto").then_some(chosen.as_str());
        if let Some(file) = &cli.file {
            set_wall_variant(Path::new(file), variant)?;
        } else {
            return apply_wall_variant(variant, cli.target.as_deref());
        }
    }

    let print_target = match &cli.print {
        Some(Some(path)) => Some(path.clone()),
        Some(None) => get_wallpaper(),
        None => None,
    };
    if let Some(path) = print_target.filter(|p| !p.is_empty()) {
        println!(
            "{}",
            dumps(&colours_for_wall(&path, cli.no_smart)?, pyjson::DEFAULT)
        );
    } else if let Some(file) = &cli.file {
        set_wallpaper(file, cli.no_smart)?;
    } else if let Some(random) = &cli.random {
        let directory = random.as_ref().map_or_else(wallpapers_dir, PathBuf::from);
        set_random(&directory, cli.no_filter, cli.no_smart)?;
    } else {
        println!(
            "{}",
            get_wallpaper()
                .filter(|w| !w.is_empty())
                .as_deref()
                .unwrap_or("No wallpaper set")
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smart_version_matches_python() {
        let source = include_str!("../../../src/dynamic_island/utils/colourfulness.py");
        assert!(source.contains(&format!("\nVERSION = {SMART_VERSION}\n")));
    }

    /// Set `SIZES_FILE` to lines of `width<TAB>height<TAB>path` from PIL.
    #[test]
    #[ignore = "needs a list of real images"]
    fn image_sizes_match_pil() {
        let list = fs::read_to_string(std::env::var("SIZES_FILE").unwrap()).unwrap();
        for line in list.lines() {
            let parts: Vec<&str> = line.split('\t').collect();
            let size = imagesize::size(parts[2]).unwrap();
            assert_eq!(
                (
                    size.width.to_string().as_str(),
                    size.height.to_string().as_str()
                ),
                (parts[0], parts[1]),
                "{}",
                parts[2]
            );
        }
    }

    #[test]
    fn variants_match_python() {
        let source = include_str!("../../../src/dynamic_island/utils/scheme.py");
        let mut pos = source.find("scheme_variants = [").unwrap();
        for variant in VARIANTS {
            pos += source[pos..].find(&format!("\"{variant}\"")).unwrap();
        }
    }
}
