//! Write the colours into the apps, see `utils/theme.py`.
//!
//! A failing app must not stop the others: `logged` writes the error to stderr and
//! carries on, like the `log_exception` decorator.

use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::Write;
use std::os::unix::fs::{FileTypeExt, OpenOptionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use di_common::fsutil::{atomic_write, read_text};
use di_common::paths;
use di_common::pyjson::{self, dumps, text_of, truthy};
use serde_json::{Map, Value, json};

use crate::colours::{Res, Scheme, templates_dir};
use crate::hypr::is_lua_config;

type Colours = Map<String, Value>;

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

fn logged(name: &str, action: impl FnOnce() -> Res<()>) {
    if let Err(e) = action() {
        eprintln!("\x1b[31m:: Error: exception during \"{name}()\": {e}\x1b[0m");
    }
}

fn config_dir() -> PathBuf {
    paths::config_dir()
}

fn data_home() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map_or_else(|| paths::home().join(".local/share"), PathBuf::from)
}

fn write(path: &Path, content: &str) -> Res<bool> {
    atomic_write(path, content).map_err(|e| format!("{}: {e}", path.display()))
}

fn template(name: &str) -> Res<String> {
    let path = templates_dir().join(name);
    read_text(&path).map_err(|e| format!("{}: {e}", path.display()))
}

pub fn get_config() -> Value {
    let path = paths::c_config_dir().join("cli.json");
    let Ok(text) = read_text(&path) else {
        return json!({});
    };
    match serde_json::from_str(&text) {
        Ok(config) => config,
        Err(_) => {
            println!("\x1b[33m:: Warning: failed to parse config, invalid JSON\x1b[0m");
            json!({})
        }
    }
}

// ---- Generate --------------------------------------------------------------------

fn gen_conf(colours: &Colours) -> String {
    colours
        .iter()
        .map(|(n, c)| format!("${n} = {}\n", text_of(c)))
        .collect()
}

fn gen_lua(colours: &Colours) -> String {
    let body: String = colours
        .iter()
        .map(|(n, c)| format!("  {n} = \"{}\",\n", text_of(c)))
        .collect();
    format!("return {{\n{body}}}")
}

fn gen_scss(colours: &Colours) -> String {
    colours
        .iter()
        .map(|(n, c)| format!("${n}: #{};\n", text_of(c)))
        .collect()
}

fn gen_replace(colours: &Colours, name: &str, hash: bool) -> Res<String> {
    let mut text = template(name)?;
    for (key, colour) in colours {
        let colour = text_of(colour);
        let value = if hash { format!("#{colour}") } else { colour };
        text = text.replace(&format!("{{{{ ${key} }}}}"), &value);
    }
    Ok(text)
}

/// The forms of one colour for `{{ name.form }}`, see `utils/colour.py`.
struct Colour {
    hex: [String; 4],
    rgb: [u8; 4],
}

impl Colour {
    fn parse(code: &str) -> Res<Self> {
        let mut padded = code.to_owned();
        while padded.chars().count() < 8 {
            padded.push('f');
        }
        let chars: Vec<char> = padded.chars().collect();
        let hex: [String; 4] = std::array::from_fn(|i| chars[i * 2..i * 2 + 2].iter().collect());
        let mut rgb = [0u8; 4];
        for (value, part) in rgb.iter_mut().zip(&hex) {
            *value =
                u8::from_str_radix(part, 16).map_err(|_| format!("ungueltige Farbe: {code}"))?;
        }
        Ok(Self { hex, rgb })
    }

    fn form(&self, form: &str) -> Option<String> {
        let list = |n: usize, sep: &str| {
            self.rgb[..n]
                .iter()
                .map(u8::to_string)
                .collect::<Vec<_>>()
                .join(sep)
        };
        match form {
            "hex" => Some(self.hex[..3].concat()),
            "hexalpha" => Some(self.hex.concat()),
            "rgb" => Some(format!("rgb({})", list(3, ","))),
            "rgbalpha" => Some(format!("rgba({})", list(4, ","))),
            "ansi" => Some(list(3, ";")),
            _ => None,
        }
    }
}

/// `str.strip()`
fn py_strip(text: &str) -> &str {
    text.trim_matches(|c: char| c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c))
}

/// Replaces `{{ name.form }}`: atomic pairs without `{{` or `}}` inside, on one line.
fn fill_dot_fields(text: &str, colours: &BTreeMap<String, Colour>) -> String {
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < text.len() {
        let rest = &text[i..];
        if rest.starts_with("{{")
            && let Some(len) = field_length(&rest[2..])
        {
            let inner = &rest[2..2 + len];
            let whole = &rest[..len + 4];
            let parts: Vec<&str> = py_strip(inner).split('.').collect();
            let value = match parts.as_slice() {
                [name, form] => colours.get(*name).and_then(|c| c.form(form)),
                _ => None,
            };
            out.push_str(value.as_deref().unwrap_or(whole));
            i += whole.len();
            continue;
        }
        let ch = rest.chars().next().unwrap_or(' ');
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

/// Length up to the closing `}}`, None if another `{{` or a line break comes first.
fn field_length(text: &str) -> Option<usize> {
    let mut pos = 0;
    loop {
        let rest = &text[pos..];
        if rest.starts_with("}}") {
            return Some(pos);
        }
        if rest.starts_with("{{") {
            return None;
        }
        let ch = rest.chars().next()?;
        if ch == '\n' {
            return None;
        }
        pos += ch.len_utf8();
    }
}

/// Replaces `{{ mode }}` with any amount of whitespace, line breaks included.
fn fill_mode(text: &str, mode: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find("{{") {
        out.push_str(&rest[..start]);
        let after = &rest[start + 2..];
        let inner = after.trim_start();
        if let Some(tail) = inner.strip_prefix("mode") {
            let tail = tail.trim_start();
            if let Some(end) = tail.strip_prefix("}}") {
                out.push_str(mode);
                rest = end;
                continue;
            }
        }
        out.push('{');
        rest = &rest[start + 1..];
    }
    out.push_str(rest);
    out
}

fn gen_replace_dynamic(colours: &Colours, path: &Path, mode: &str) -> Res<String> {
    let mut parsed = BTreeMap::new();
    for (name, code) in colours {
        parsed.insert(name.clone(), Colour::parse(&text_of(code))?);
    }
    let text = read_text(path).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(fill_mode(&fill_dot_fields(&text, &parsed), mode))
}

fn hex_to_ansi(colours: &Colours, name: &str, codes: &str) -> Res<String> {
    let c = colours
        .get(name)
        .map(text_of)
        .ok_or_else(|| format!("Farbe fehlt: {name}"))?;
    let part = |range: std::ops::Range<usize>| c.get(range).unwrap_or("");
    Ok(format!(
        "\x1b]{codes};rgb:{}/{}/{}\x1b\\",
        part(0..2),
        part(2..4),
        part(4..6)
    ))
}

/// 10 foreground, 11 background, 12 cursor, 17 selection, 4;n the palette.
fn gen_sequences(colours: &Colours) -> Res<String> {
    let mut out = String::new();
    for (name, codes) in [
        ("onSurface", "10"),
        ("surface", "11"),
        ("secondary", "12"),
        ("secondary", "17"),
    ] {
        out.push_str(&hex_to_ansi(colours, name, codes)?);
    }
    for i in 0..16 {
        out.push_str(&hex_to_ansi(
            colours,
            &format!("term{i}"),
            &format!("4;{i}"),
        )?);
    }
    for (name, codes) in [
        ("primary", "4;16"),
        ("secondary", "4;17"),
        ("tertiary", "4;18"),
    ] {
        out.push_str(&hex_to_ansi(colours, name, codes)?);
    }
    Ok(out)
}

// ---- Apply ------------------------------------------------------------------------

fn apply_terms(sequences: &str) -> Res<()> {
    let state = paths::c_state_dir().join("sequences.txt");
    if let Some(parent) = state.parent() {
        fs::create_dir_all(parent).map_err(err)?;
    }
    fs::write(&state, sequences).map_err(err)?;

    for entry in fs::read_dir("/dev/pts").map_err(err)? {
        let entry = entry.map_err(err)?;
        let name = entry.file_name();
        if !name.to_string_lossy().bytes().all(|b| b.is_ascii_digit()) {
            continue;
        }
        if !entry.file_type().is_ok_and(|t| t.is_char_device()) {
            continue;
        }
        // Non-blocking: a busy terminal must not hold up the theme change.
        let opened = File::options()
            .write(true)
            .custom_flags(libc::O_NONBLOCK | libc::O_NOCTTY)
            .open(entry.path());
        if let Ok(mut terminal) = opened {
            let _ = terminal.write_all(sequences.as_bytes());
        }
    }
    Ok(())
}

fn signal(program: &str) -> Res<()> {
    Command::new("killall")
        .args(["-USR2", program])
        .stderr(Stdio::null())
        .status()
        .map_err(err)?;
    Ok(())
}

fn apply_discord(scss: &str) -> Res<()> {
    let tmp = tempfile::Builder::new()
        .suffix("w")
        .tempdir()
        .map_err(err)?;
    fs::write(tmp.path().join("_colours.scss"), scss).map_err(err)?;
    let output = Command::new("sass")
        .arg("-I")
        .arg(tmp.path())
        .arg(templates_dir().join("discord.scss"))
        .stderr(Stdio::inherit())
        .output()
        .map_err(err)?;
    if !output.status.success() {
        return Err(format!("sass endete mit {}", output.status));
    }
    let css = String::from_utf8(output.stdout).map_err(err)?;
    for client in [
        "Equicord",
        "Vencord",
        "BetterDiscord",
        "equibop",
        "vesktop",
        "legcord",
    ] {
        write(
            &config_dir()
                .join(client)
                .join("themes/dynamic-island.theme.css"),
            &css,
        )?;
    }
    Ok(())
}

fn hue_colour(r: u32, g: u32, b: u32, brightness: u32, pale: bool) -> &'static str {
    if b > r && b > g {
        let r_ratio = r * 100 / b;
        let g_ratio = g * 100 / b;
        if r_ratio > 70 && g_ratio > 70 {
            if r.abs_diff(g) < 15 {
                "blue"
            } else if r > g {
                "violet"
            } else {
                "cyan"
            }
        } else if r_ratio > 60 && r > g {
            "violet"
        } else if g_ratio > 60 && g > r {
            "cyan"
        } else {
            "blue"
        }
    } else if r > g && r > b {
        if g > b + 30 {
            let rg_ratio = g * 100 / r;
            if pale {
                if rg_ratio > 70 && brightness < 220 {
                    "palebrown"
                } else {
                    "paleorange"
                }
            } else if rg_ratio > 70 && brightness < 180 {
                "brown"
            } else {
                "orange"
            }
        } else if b > g + 20 || pale {
            "pink"
        } else {
            "red"
        }
    } else if g > r && g > b {
        if r > b + 30 { "yellow" } else { "green" }
    } else {
        "grey"
    }
}

/// Folder icon colour from the primary colour, by hue and saturation.
fn sync_papirus_colors(hex: &str) -> Res<()> {
    let found = Command::new("which")
        .arg("papirus-folders")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
    if !found.is_ok_and(|s| s.success()) {
        return Ok(());
    }
    let home = paths::home();
    let themes = [
        PathBuf::from("/usr/share/icons/Papirus"),
        PathBuf::from("/usr/share/icons/Papirus-Dark"),
        home.join(".local/share/icons/Papirus"),
        home.join(".icons/Papirus"),
    ];
    if !themes.iter().any(|p| p.exists()) {
        return Ok(());
    }
    let channel = |range: std::ops::Range<usize>| {
        hex.get(range)
            .and_then(|p| u32::from_str_radix(p, 16).ok())
            .ok_or_else(|| format!("ungueltige Farbe {hex}"))
    };
    let (r, g, b) = (channel(0..2)?, channel(2..4)?, channel(4..6)?);
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let saturation = ((max - min) * 100).checked_div(max).unwrap_or(0);
    let colour = if saturation < 20 {
        if max < 85 {
            "black"
        } else if max < 170 {
            "grey"
        } else {
            "white"
        }
    } else {
        hue_colour(r, g, b, max, saturation < 60 && max > 180)
    };
    let mut command = Command::new("sudo");
    command
        .args(["-n", "papirus-folders", "-C", colour, "-u"])
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    // SAFETY: setsid only touches the child between fork and exec, nothing else runs there.
    unsafe {
        command.pre_exec(|| {
            libc::setsid();
            Ok(())
        });
    }
    let _ = command.spawn();
    Ok(())
}

fn capitalize(word: &str) -> String {
    let mut chars = word.chars();
    chars.next().map_or_else(String::new, |first| {
        first
            .to_uppercase()
            .chain(chars.flat_map(char::to_lowercase))
            .collect()
    })
}

fn apply_gtk(colours: &Colours, mode: &str, icon_theme: Option<&str>) -> Res<()> {
    let gtk = gen_replace(colours, "gtk.css", true)?;
    let thunar = gen_replace(colours, "thunar.css", true)?;
    for version in ["gtk-3.0", "gtk-4.0"] {
        let dir = config_dir().join(version);
        write(&dir.join("gtk.css"), &gtk)?;
        write(&dir.join("thunar.css"), &thunar)?;
    }
    let icons = icon_theme.map_or_else(
        || format!("Papirus-{}", capitalize(mode)),
        ToOwned::to_owned,
    );
    for (key, value) in [
        ("gtk-theme", "'adw-gtk3-dark'".to_owned()),
        ("color-scheme", format!("'prefer-{mode}'")),
        ("icon-theme", format!("'{icons}'")),
    ] {
        Command::new("dconf")
            .args(["write", &format!("/org/gnome/desktop/interface/{key}")])
            .arg(value)
            .status()
            .map_err(err)?;
    }
    sync_papirus_colors(
        &colours
            .get("primary")
            .map(text_of)
            .ok_or("Farbe fehlt: primary")?,
    )
}

fn apply_qt(colours: &Colours, mode: &str, icon_theme: Option<&str>) -> Res<()> {
    write(
        &config_dir().join("qtengine/dynamic-island.colors"),
        &gen_replace(colours, &format!("qt{mode}.colors"), true)?,
    )?;
    let name = capitalize(mode);
    let mut config = template("qtengine.json")?.replace("{{ $mode }}", &name);
    if let Some(icons) = icon_theme {
        config = config.replace(
            &format!("\"iconTheme\": \"Papirus-{name}\""),
            &format!("\"iconTheme\": \"{icons}\""),
        );
    }
    write(&config_dir().join("qtengine/config.json"), &config)?;
    Ok(())
}

/// `shutil.which`
fn which(program: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|path| {
        std::env::split_paths(&path).any(|dir| {
            use std::os::unix::fs::PermissionsExt;
            fs::metadata(dir.join(program))
                .is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        })
    })
}

fn apply_chromium(colours: &Colours) -> Res<()> {
    let surface = colours
        .get("surface")
        .map(text_of)
        .ok_or("Farbe fehlt: surface")?;
    for (program, dir) in [
        ("chromium", "/etc/chromium/policies/managed"),
        ("brave", "/etc/brave/policies/managed"),
        ("google-chrome-stable", "/etc/opt/chrome/policies/managed"),
    ] {
        if !which(program) {
            continue;
        }
        let dir = Path::new(dir);
        if !dir.is_dir() {
            Command::new("sudo")
                .args(["-n", "mkdir", "-p"])
                .arg(dir)
                .stderr(Stdio::null())
                .status()
                .map_err(err)?;
        }
        if !dir.is_dir() {
            println!("Unable to create {} directory", dir.display());
            continue;
        }
        let policy =
            json!({"BrowserThemeColor": format!("#{surface}"), "BrowserColorScheme": "device"});
        let mut tee = Command::new("sudo")
            .args(["-n", "tee"])
            .arg(dir.join("dynamic-island.json"))
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(err)?;
        if let Some(stdin) = tee.stdin.as_mut() {
            stdin
                .write_all(dumps(&policy, pyjson::DEFAULT).as_bytes())
                .map_err(err)?;
        }
        tee.wait().map_err(err)?;
        Command::new(program)
            .args(["--refresh-platform-policy", "--no-startup-window"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map_err(err)?;
    }
    Ok(())
}

fn apply_user_templates(colours: &Colours, mode: &str) -> Res<()> {
    let dir = paths::c_config_dir().join("templates");
    if !dir.is_dir() {
        return Ok(());
    }
    let theme_dir = paths::c_state_dir().join("theme");
    for entry in fs::read_dir(&dir).map_err(err)? {
        let path = entry.map_err(err)?.path();
        if path.is_file() {
            write(
                &theme_dir.join(path.file_name().unwrap_or_default()),
                &gen_replace_dynamic(colours, &path, mode)?,
            )?;
        }
    }
    Ok(())
}

/// Colours and mode as they are in `scheme.json` now. Two quick changes run as two
/// processes, and whoever gets the lock second is not necessarily the newer one, so
/// after waiting the state on disk counts. That way the last change always wins.
fn latest_scheme(colours: &Colours, mode: &str) -> (Colours, String) {
    let path = paths::c_state_dir().join("scheme.json");
    let on_disk = read_text(&path)
        .ok()
        .and_then(|text| serde_json::from_str::<Value>(&text).ok())
        .and_then(|data| {
            Some((
                data.get("colours")?.as_object()?.clone(),
                text_of(data.get("mode")?),
            ))
        });
    on_disk.unwrap_or_else(|| (colours.clone(), mode.to_owned()))
}

pub fn apply_colours(colours: &Colours, mode: &str, scheme: &Scheme) -> Res<()> {
    // A lock serialises parallel runs. The second one waits and then applies the
    // newest state. The file stays: a deleted lock file locks out nobody.
    let state = paths::c_state_dir();
    fs::create_dir_all(&state).map_err(err)?;
    let lock = File::options()
        .append(true)
        .create(true)
        .open(state.join("theme.lock"))
        .map_err(err)?;
    use std::os::fd::AsRawFd;
    // SAFETY: the descriptor stays valid, `lock` lives until the end of this function.
    if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX) } != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }

    let (colours, mode) = latest_scheme(colours, mode);
    let colours = &colours;
    let mode = mode.as_str();

    let config = get_config();
    let empty = json!({});
    let cfg = config.get("theme").unwrap_or(&empty);
    let check = |key: &str| cfg.get(key).is_none_or(truthy);

    if check("enableTerm") {
        let sequences = gen_sequences(colours)?;
        logged("apply_terms", || apply_terms(&sequences));
    }
    if check("enableHypr") {
        let lua = is_lua_config();
        let text = if lua {
            gen_lua(colours)
        } else {
            gen_conf(colours)
        };
        logged("apply_hypr", || {
            // Python asks Hyprland once, the answer stays the same for this process.
            let ext = if lua { "lua" } else { "conf" };
            write(
                &config_dir().join(format!("hypr/scheme/current.{ext}")),
                &text,
            )
            .map(drop)
        });
    }
    if check("enableHyprlock") {
        logged("apply_hyprlock", || {
            write(
                &config_dir().join("hypr/scheme/hyprlock.conf"),
                &gen_replace(colours, "hyprlock.conf", false)?,
            )
            .map(drop)
        });
    }
    if check("enableDiscord") {
        let scss = gen_scss(colours);
        logged("apply_discord", || apply_discord(&scss));
    }
    if check("enableSpicetify") {
        logged("apply_spicetify", || {
            let text = gen_replace(colours, &format!("spicetify-{mode}.ini"), false)?;
            write(
                &config_dir().join("spicetify/Themes/dynamic-island/color.ini"),
                &text,
            )
            .map(drop)
        });
    }
    if check("enablePandora") {
        logged("apply_pandora", || {
            let text = gen_replace(colours, "pandora.json", true)?.replace("{{ $mode }}", mode);
            write(
                &data_home().join("PandoraLauncher/themes/dynamic-island.json"),
                &text,
            )
            .map(drop)
        });
    }
    if check("enableFuzzel") {
        logged("apply_fuzzel", || {
            write(
                &config_dir().join("fuzzel/fuzzel.ini"),
                &gen_replace(colours, "fuzzel.ini", false)?,
            )
            .map(drop)
        });
    }
    if check("enableBtop") {
        logged("apply_btop", || {
            if write(
                &config_dir().join("btop/themes/dynamic-island.theme"),
                &gen_replace(colours, "btop.theme", true)?,
            )? {
                signal("btop")?;
            }
            Ok(())
        });
    }
    if check("enableNvtop") {
        logged("apply_nvtop", || {
            write(
                &config_dir().join("nvtop/nvtop.colors"),
                &gen_replace(colours, "nvtop.colors", true)?,
            )
            .map(drop)
        });
    }
    if check("enableHtop") {
        logged("apply_htop", || {
            if write(
                &config_dir().join("htop/htoprc"),
                &gen_replace(colours, "htop.theme", true)?,
            )? {
                signal("htop")?;
            }
            Ok(())
        });
    }
    let icon_theme = cfg
        .get(format!("iconTheme{}", capitalize(mode)))
        .filter(|v| truthy(v))
        .or_else(|| cfg.get("iconTheme").filter(|v| truthy(v)))
        .map(text_of);
    if check("enableGtk") {
        logged("apply_gtk", || {
            apply_gtk(colours, mode, icon_theme.as_deref())
        });
    }
    if check("enableQt") {
        logged("apply_qt", || {
            apply_qt(colours, mode, icon_theme.as_deref())
        });
    }
    if check("enableWarp") {
        logged("apply_warp", || {
            let warp_mode = if mode == "dark" { "darker" } else { "lighter" };
            let text =
                gen_replace(colours, "warp.yaml", true)?.replace("{{ $warp_mode }}", warp_mode);
            write(
                &data_home().join("warp-terminal/themes/dynamic-island.yaml"),
                &text,
            )
            .map(drop)
        });
    }
    if check("enableChromium") {
        logged("apply_chromium", || apply_chromium(colours));
    }
    if check("enableZed") {
        // No logging here in Python either, a failure ends the run.
        let path = config_dir().join("zed/themes/dynamic-island.json");
        // Zed's file watcher does not see changes through symlinks.
        if path.is_symlink() {
            fs::remove_file(&path).map_err(err)?;
        }
        write(
            &path,
            &gen_replace_dynamic(colours, &templates_dir().join("zed.json"), mode)?,
        )?;
    }
    if check("enableCava") {
        logged("apply_cava", || {
            if write(
                &config_dir().join("cava/config"),
                &gen_replace(colours, "cava.conf", true)?,
            )? {
                signal("cava")?;
            }
            Ok(())
        });
    }
    logged("apply_user_templates", || {
        apply_user_templates(colours, mode)
    });

    if let Some(hook) = cfg.get("postHook").filter(|h| truthy(h)) {
        let mut command = Command::new("/bin/sh");
        command.arg("-c").arg(text_of(hook)).stderr(Stdio::null());
        scheme.hook_env(&mut command);
        let _ = command.status();
    }
    Ok(())
}
