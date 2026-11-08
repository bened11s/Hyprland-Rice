//! Render with fastfetch and turn the ANSI output into coloured segments.

use std::io::{Read, Write};
use std::process::{Command, Output, Stdio};
use std::sync::LazyLock;
use std::thread;
use std::time::{Duration, Instant};

use di_common::fsutil::universal_newlines;
use di_common::pyjson::{self, dumps};
use regex::Regex;
use serde_json::{Map, Value, json};

use crate::import::load_jsonc;
use crate::markup::hexc;
use crate::unicode_table::{is_wide, is_zero_width};
use crate::{Res, fail, last_line, look_dir, other, state_dir};

static SGR_ANY: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\x1b\[([0-9;?]*)([A-Za-z])").unwrap());

const ANSI16: [&str; 16] = [
    "#000000", "#cd3131", "#0dbc79", "#e5e510", "#2472c8", "#bc3fbc", "#11a8cd", "#e5e5e5",
    "#666666", "#f14c4c", "#23d18b", "#f5f543", "#3b8eea", "#d670d6", "#29b8db", "#ffffff",
];

/// Text budget next to the card, from `fish/functions/fastfetch.fish`.
fn budget(size: &str) -> (u64, usize) {
    match size {
        "config" => (64, 23),
        "compact" => (50, 19),
        _ => (32, 7),
    }
}

fn cell_width(text: &str) -> u64 {
    text.chars()
        .filter(|c| !is_zero_width(*c))
        .map(|c| if is_wide(c) { 2 } else { 1 })
        .sum()
}

fn xterm256(n: u64) -> String {
    if n < 16 {
        return ANSI16[usize::try_from(n).unwrap_or(0)].to_owned();
    }
    if n < 232 {
        let n = n - 16;
        let level = [0, 95, 135, 175, 215, 255];
        let at = |v: u64| level[usize::try_from(v).unwrap_or(0)];
        return hexc(&[at(n / 36), at((n / 6) % 6), at(n % 6)]);
    }
    let grey = 8 + (n - 232) * 10;
    hexc(&[grey, grey, grey])
}

#[derive(Clone, Default, PartialEq)]
struct Style {
    fg: String,
    bg: String,
    bold: bool,
    italic: bool,
    dim: bool,
    underline: bool,
}

impl Style {
    fn apply(&mut self, params: &str) {
        let params = if params.is_empty() { "0" } else { params };
        let nums: Vec<u64> = params
            .split(';')
            .map(|x| {
                if x.bytes().all(|b| b.is_ascii_digit()) {
                    x.parse().unwrap_or(0)
                } else {
                    0
                }
            })
            .collect();
        let mut k = 0;
        while k < nums.len() {
            let v = nums[k];
            match v {
                0 => *self = Self::default(),
                1 => self.bold = true,
                2 => self.dim = true,
                3 => self.italic = true,
                4 => self.underline = true,
                22 => (self.bold, self.dim) = (false, false),
                23 => self.italic = false,
                24 => self.underline = false,
                39 => self.fg.clear(),
                49 => self.bg.clear(),
                38 | 48 if k + 4 < nums.len() && nums[k + 1] == 2 => {
                    self.set_color(v == 38, hexc(&nums[k + 2..k + 5]));
                    k += 4;
                }
                38 | 48 if k + 2 < nums.len() && nums[k + 1] == 5 => {
                    self.set_color(v == 38, xterm256(nums[k + 2]));
                    k += 2;
                }
                30..=37 => self.fg = ANSI16[usize::try_from(v - 30).unwrap_or(0)].to_owned(),
                90..=97 => self.fg = ANSI16[usize::try_from(v - 82).unwrap_or(0)].to_owned(),
                40..=47 => self.bg = ANSI16[usize::try_from(v - 40).unwrap_or(0)].to_owned(),
                100..=107 => self.bg = ANSI16[usize::try_from(v - 92).unwrap_or(0)].to_owned(),
                _ => {}
            }
            k += 1;
        }
    }

    fn set_color(&mut self, foreground: bool, color: String) {
        if foreground {
            self.fg = color;
        } else {
            self.bg = color;
        }
    }

    fn segment(&self, text: &str) -> Value {
        let mut seg = Map::new();
        seg.insert("t".to_owned(), json!(text));
        if !self.fg.is_empty() {
            seg.insert("fg".to_owned(), json!(self.fg));
        }
        if !self.bg.is_empty() {
            seg.insert("bg".to_owned(), json!(self.bg));
        }
        for (key, on) in [
            ("b", self.bold),
            ("i", self.italic),
            ("d", self.dim),
            ("u", self.underline),
        ] {
            if on {
                seg.insert(key.to_owned(), json!(true));
            }
        }
        Value::Object(seg)
    }
}

/// ANSI output to lines of segments `{t, fg, bg, b, i, d, u}`.
fn ansi_lines(text: &str) -> Vec<Vec<(Style, String)>> {
    let mut lines = Vec::new();
    let mut style = Style::default();
    for raw in text.split('\n') {
        let mut segments: Vec<(Style, String)> = Vec::new();
        let push = |segments: &mut Vec<(Style, String)>, style: &Style, piece: &str| {
            if piece.is_empty() {
                return;
            }
            match segments.last_mut() {
                Some((last, text)) if last == style => text.push_str(piece),
                _ => segments.push((style.clone(), piece.to_owned())),
            }
        };
        let mut pos = 0;
        for caps in SGR_ANY.captures_iter(raw) {
            let whole = caps.get(0).unwrap();
            push(&mut segments, &style, &raw[pos..whole.start()]);
            pos = whole.end();
            if &caps[2] == "m" {
                style.apply(&caps[1]);
            }
        }
        push(&mut segments, &style, &raw[pos..]);
        lines.push(segments);
    }
    while lines.last().is_some_and(Vec::is_empty) {
        lines.pop();
    }
    lines
}

/// Runs a program, None if it does not finish in time.
pub fn run_with_timeout(command: &mut Command, seconds: u64) -> Res<Option<Output>> {
    let mut child = command
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let mut out_pipe = child.stdout.take();
    let mut err_pipe = child.stderr.take();
    let out_reader = thread::spawn(move || {
        let mut data = Vec::new();
        if let Some(pipe) = out_pipe.as_mut() {
            let _ = pipe.read_to_end(&mut data);
        }
        data
    });
    let err_reader = thread::spawn(move || {
        let mut data = Vec::new();
        if let Some(pipe) = err_pipe.as_mut() {
            let _ = pipe.read_to_end(&mut data);
        }
        data
    });
    let deadline = Instant::now() + Duration::from_secs(seconds);
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Ok(None);
        }
        thread::sleep(Duration::from_millis(2));
    };
    let stdout = out_reader.join().unwrap_or_default();
    let stderr = err_reader.join().unwrap_or_default();
    Ok(Some(Output {
        status,
        stdout,
        stderr,
    }))
}

fn run_fastfetch(conf: &Value) -> Res<String> {
    let mut file = tempfile::Builder::new().suffix(".jsonc").tempfile()?;
    file.write_all(dumps(conf, pyjson::UNICODE).as_bytes())?;
    file.flush()?;
    let mut command = Command::new("fastfetch");
    command
        .arg("-c")
        .arg(file.path())
        .args(["--logo", "none", "--pipe", "false"])
        .env("COLUMNS", "400");
    let output = match run_with_timeout(&mut command, 15) {
        Ok(Some(output)) => output,
        Ok(None) => return fail("fastfetch antwortet nicht"),
        Err(crate::Error::Other(_)) if command_missing() => {
            return fail("fastfetch nicht gefunden");
        }
        Err(e) => return Err(e),
    };
    let stdout = match String::from_utf8(output.stdout) {
        Ok(text) => universal_newlines(&text),
        Err(e) => return other(format!("fastfetch: {e}")),
    };
    if !output.status.success() && stdout.is_empty() {
        return fail(format!(
            "fastfetch: {}",
            last_line(&String::from_utf8_lossy(&output.stderr))
        ));
    }
    Ok(stdout)
}

fn command_missing() -> bool {
    std::env::var_os("PATH")
        .is_none_or(|path| !std::env::split_paths(&path).any(|dir| dir.join("fastfetch").is_file()))
}

pub fn preview_conf(conf: &Value, size: &str) -> Res<Value> {
    let Some(map) = conf.as_object() else {
        return other("Konfiguration ist kein Objekt");
    };
    let mut conf = map.clone();
    conf.insert("logo".to_owned(), json!({"type": "none"}));
    let lines = ansi_lines(&run_fastfetch(&Value::Object(conf))?);
    let (cols, rows) = budget(size);
    let widths: Vec<u64> = lines
        .iter()
        .map(|l| l.iter().map(|(_, t)| cell_width(t)).sum())
        .collect();
    let overflow: Vec<usize> = widths
        .iter()
        .enumerate()
        .filter(|(_, w)| **w > cols)
        .map(|(i, _)| i)
        .collect();
    let segments: Vec<Value> = lines
        .iter()
        .map(|l| Value::Array(l.iter().map(|(s, t)| s.segment(t)).collect()))
        .collect();
    Ok(json!({
        "size": size, "lines": segments, "width": widths.iter().max().copied().unwrap_or(0),
        "height": lines.len(), "budget": {"cols": cols, "rows": rows},
        "overflow": overflow, "tooTall": lines.len() > rows,
    }))
}

/// A file the way the terminal reads it. `scheme` means the templates rendered
/// from the colour scheme (`templates/fastfetch*.jsonc`).
pub fn preview_raw(lid: &str, size: &str) -> Res<Value> {
    if lid == "scheme" {
        let name = if size == "config" {
            "fastfetch.jsonc".to_owned()
        } else {
            format!("fastfetch-{size}.jsonc")
        };
        let path = state_dir().join("theme").join(name);
        if !path.is_file() {
            return fail("Schema-fastfetch fehlt (noch kein Theme gerendert)");
        }
        return preview_conf(&load_jsonc(&path)?, size);
    }
    let path = look_dir(lid)?.join(format!("{size}.jsonc"));
    if !path.is_file() {
        return fail(format!("{lid}: {size}.jsonc fehlt"));
    }
    preview_conf(&load_jsonc(&path)?, size)
}
