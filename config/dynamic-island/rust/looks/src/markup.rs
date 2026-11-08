//! Colours in texts: ANSI escapes in fastfetch files, markup in `look.json`.

use std::collections::HashMap;
use std::sync::LazyLock;

use regex::Regex;
use serde_json::{Map, Value};

use crate::{Res, fail};

pub static ESC_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\x1b\[([0-9;]*)m").unwrap());
pub static PARAMS_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(\d+;)*(38|48);2;\d+;\d+;\d+(;\d+)*\n?\z").unwrap());
pub static TAG_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"<<|<([^<>]*)>").unwrap());
static PART_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(/|b|d|i|u|\d+|(bg)?@[A-Za-z][A-Za-z0-9_-]*|(bg)?#[0-9a-fA-F]{6})\n?\z").unwrap()
});

/// `str.split()`: Python also splits on the control characters 0x1c to 0x1f.
pub fn py_split(text: &str) -> Vec<&str> {
    text.split(py_space).filter(|p| !p.is_empty()).collect()
}

pub fn py_space(c: char) -> bool {
    c.is_whitespace() || ('\u{1c}'..='\u{1f}').contains(&c)
}

pub fn hexc(rgb: &[u64]) -> String {
    format!("#{:02x}{:02x}{:02x}", rgb[0], rgb[1], rgb[2])
}

fn rgb_of(hex: &str) -> Vec<u64> {
    let hex = hex.trim_start_matches('#');
    (0..3)
        .map(|k| {
            hex.get(k * 2..k * 2 + 2)
                .and_then(|p| u64::from_str_radix(p, 16).ok())
                .unwrap_or(0)
        })
        .collect()
}

pub fn rgb_to_unit(hex: &str) -> Vec<f64> {
    #[allow(clippy::cast_precision_loss)]
    rgb_of(hex).into_iter().map(|x| x as f64 / 255.0).collect()
}

fn parse_nums(params: &str) -> Vec<u64> {
    params
        .split(';')
        .map(|x| {
            x.trim()
                .parse()
                .unwrap_or(if x.is_empty() { 0 } else { u64::MAX })
        })
        .collect()
}

/// `"1;38;2;r;g;b"` becomes `["b", "@primary"]`, `names` maps `#hex` to the palette name.
fn params_to_parts(params: &str, names: &HashMap<String, String>) -> Vec<String> {
    if params.is_empty() {
        return Vec::new();
    }
    let nums = parse_nums(params);
    let mut parts = Vec::new();
    let mut k = 0;
    while k < nums.len() {
        let v = nums[k];
        if (v == 38 || v == 48) && k + 4 < nums.len() && nums[k + 1] == 2 {
            let hex = hexc(&nums[k + 2..k + 5]);
            let reference = names.get(&hex).map_or(hex, |name| format!("@{name}"));
            parts.push(format!("{}{reference}", if v == 48 { "bg" } else { "" }));
            k += 5;
        } else {
            parts.push(match v {
                0 => "/".to_owned(),
                1 => "b".to_owned(),
                2 => "d".to_owned(),
                3 => "i".to_owned(),
                4 => "u".to_owned(),
                other => other.to_string(),
            });
            k += 1;
        }
    }
    parts
}

fn parts_to_params(parts: &[&str], palette: &Map<String, Value>) -> Res<String> {
    let mut out = Vec::new();
    for part in parts {
        let part = part.trim_end_matches('\n');
        let bg = part.starts_with("bg") && part[2..].starts_with(['@', '#']);
        let mut q = if bg {
            part[2..].to_owned()
        } else {
            part.to_owned()
        };
        if let Some(name) = q.strip_prefix('@') {
            let Some(color) = palette.get(name) else {
                return fail(format!("unbekannte Palettenfarbe: {q}"));
            };
            q = di_common::pyjson::text_of(color);
        }
        if q.starts_with('#') {
            let rgb: Vec<String> = rgb_of(&q).iter().map(ToString::to_string).collect();
            out.push(format!(
                "{};2;{}",
                if bg { "48" } else { "38" },
                rgb.join(";")
            ));
        } else if let Some(code) = ["/", "b", "d", "i", "u"].iter().position(|m| *m == q) {
            out.push(code.to_string());
        } else if q.chars().next().is_some_and(char::is_numeric) && q.chars().all(char::is_numeric)
        {
            out.push(q);
        } else {
            return fail(format!("unbekanntes Markup: <{part}>"));
        }
    }
    Ok(out.join(";"))
}

fn to_markup(text: &str, names: &HashMap<String, String>) -> String {
    let mut res = String::new();
    let mut pos = 0;
    for caps in ESC_RE.captures_iter(text) {
        let whole = caps.get(0).unwrap();
        res.push_str(&text[pos..whole.start()].replace('<', "<<"));
        res.push('<');
        res.push_str(&params_to_parts(&caps[1], names).join(" "));
        res.push('>');
        pos = whole.end();
    }
    res.push_str(&text[pos..].replace('<', "<<"));
    res
}

fn from_markup(text: &str, palette: &Map<String, Value>) -> Res<String> {
    let mut res = String::new();
    let mut pos = 0;
    for caps in TAG_RE.captures_iter(text) {
        let whole = caps.get(0).unwrap();
        res.push_str(&text[pos..whole.start()]);
        pos = whole.end();
        if whole.as_str() == "<<" {
            res.push('<');
            continue;
        }
        let inner = py_split(&caps[1]);
        if !inner.iter().all(|p| PART_RE.is_match(p)) {
            return fail(format!("unbekanntes Markup: {}", whole.as_str()));
        }
        res.push_str("\x1b[");
        res.push_str(&parts_to_params(&inner, palette)?);
        res.push('m');
    }
    res.push_str(&text[pos..]);
    Ok(res)
}

fn has_color(key: &str) -> bool {
    key.to_lowercase().contains("color")
}

/// fastfetch values to the form of `look.json`: markup and palette names.
pub fn encode(value: &Value, names: &HashMap<String, String>) -> Value {
    fn walk(value: &Value, names: &HashMap<String, String>, color: bool) -> Value {
        match value {
            Value::Object(map) => Value::Object(
                map.iter()
                    .map(|(k, v)| (k.clone(), walk(v, names, color || has_color(k))))
                    .collect(),
            ),
            Value::Array(items) => {
                Value::Array(items.iter().map(|v| walk(v, names, color)).collect())
            }
            Value::String(s) if color && PARAMS_RE.is_match(s) => {
                Value::String(params_to_parts(s, names).join(" "))
            }
            Value::String(s) => Value::String(to_markup(s, names)),
            other => other.clone(),
        }
    }
    walk(value, names, false)
}

/// `p.lstrip("bg")[:1] in "@#"`: the empty string counts as contained, so a plain `b` does too.
fn looks_like_color(part: &str) -> bool {
    part.trim_start_matches(['b', 'g'])
        .chars()
        .next()
        .is_none_or(|c| c == '@' || c == '#')
}

/// The form of `look.json` to fastfetch values.
pub fn decode(value: &Value, palette: &Map<String, Value>) -> Res<Value> {
    fn walk(value: &Value, palette: &Map<String, Value>, color: bool) -> Res<Value> {
        match value {
            Value::Object(map) => {
                let mut out = Map::new();
                for (k, v) in map {
                    out.insert(k.clone(), walk(v, palette, color || has_color(k))?);
                }
                Ok(Value::Object(out))
            }
            Value::Array(items) => Ok(Value::Array(
                items
                    .iter()
                    .map(|v| walk(v, palette, color))
                    .collect::<Res<_>>()?,
            )),
            Value::String(s) => {
                let parts = py_split(s);
                if color
                    && !s.is_empty()
                    && parts.iter().all(|p| PART_RE.is_match(p))
                    && parts.iter().any(|p| looks_like_color(p))
                {
                    return Ok(Value::String(parts_to_params(&parts, palette)?));
                }
                Ok(Value::String(from_markup(s, palette)?))
            }
            other => Ok(other.clone()),
        }
    }
    walk(value, palette, false)
}

pub fn triplets(params: &str) -> Vec<String> {
    let nums = parse_nums(params);
    let mut out = Vec::new();
    let mut k = 0;
    while k < nums.len() {
        if (nums[k] == 38 || nums[k] == 48) && k + 4 < nums.len() && nums[k + 1] == 2 {
            out.push(hexc(&nums[k + 2..k + 5]));
            k += 5;
        } else {
            k += 1;
        }
    }
    out
}
