//! Make a `look.json` from handwritten fastfetch files.

use std::collections::HashMap;
use std::path::Path;
use std::sync::LazyLock;

use di_common::fsutil::read_text;
use di_common::pyjson::{text_of, truthy};
use regex::Regex;
use serde_json::{Map, Value, json};

use crate::diff::{diff, row_patch};
use crate::markup::{ESC_RE, PARAMS_RE, TAG_RE, encode, py_space, triplets};
use crate::{Res, SIZES, default_title, fail, look_dir, other};

static TRAILING_COMMA_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r",(\s*[\]}])").unwrap());

/// Removes `//` and `/* */` outside of strings, and commas before `]` and `}`.
pub fn strip_jsonc(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let (mut i, n) = (0, bytes.len());
    let mut in_string = false;
    while i < n {
        let c = bytes[i];
        if in_string {
            out.push(c);
            if c == b'\\' && i + 1 < n {
                out.push(bytes[i + 1]);
                i += 2;
                continue;
            }
            if c == b'"' {
                in_string = false;
            }
            i += 1;
        } else if c == b'"' {
            in_string = true;
            out.push(c);
            i += 1;
        } else if bytes[i..].starts_with(b"//") {
            while i < n && bytes[i] != b'\n' {
                i += 1;
            }
        } else if bytes[i..].starts_with(b"/*") {
            i = text[i + 2..].find("*/").map_or(n, |end| i + 2 + end + 2);
        } else {
            out.push(c);
            i += 1;
        }
    }
    let joined = String::from_utf8_lossy(&out);
    TRAILING_COMMA_RE.replace_all(&joined, "$1").into_owned()
}

pub fn load_jsonc(path: &Path) -> Res<Value> {
    let text = read_text(path)?;
    serde_json::from_str(&strip_jsonc(&text)).or_else(|e| {
        let name = path.file_name().unwrap_or_default().to_string_lossy();
        fail(format!(
            "{name}: kein gueltiges JSONC ({e}, Zeile {})",
            e.line()
        ))
    })
}

fn role_of(path: &[String]) -> Option<&'static str> {
    let path: Vec<&str> = path.iter().map(String::as_str).collect();
    match path.as_slice() {
        ["display", "color", "keys"] => Some("primary"),
        ["display", "color", "separator"] => Some("accent"),
        ["display", "bar", "color", "elapsed"] => Some("highlight"),
        ["display", "bar", "color", "total"] => Some("muted"),
        _ => None,
    }
}

/// How often each colour appears, in order of first appearance, and the roles.
#[derive(Default)]
struct Colors {
    counts: Vec<(String, u64)>,
    roles: HashMap<&'static str, String>,
}

impl Colors {
    fn count(&mut self, hex: String) {
        match self.counts.iter_mut().find(|(h, _)| *h == hex) {
            Some((_, n)) => *n += 1,
            None => self.counts.push((hex, 1)),
        }
    }

    fn collect(&mut self, value: &Value, path: &mut Vec<String>) {
        match value {
            Value::Object(map) => {
                for (k, v) in map {
                    path.push(k.clone());
                    self.collect(v, path);
                    path.pop();
                }
            }
            Value::Array(items) => {
                for (i, v) in items.iter().enumerate() {
                    path.push(i.to_string());
                    self.collect(v, path);
                    path.pop();
                }
            }
            Value::String(s) => {
                let mut found: Vec<&str> = ESC_RE
                    .captures_iter(s)
                    .map(|c| c.get(1).unwrap().as_str())
                    .collect();
                let color_path = path.iter().any(|p| p.to_lowercase().contains("color"));
                if color_path && PARAMS_RE.is_match(s) {
                    found.push(s);
                    if let Some(role) = role_of(path) {
                        for hex in triplets(s) {
                            self.roles.entry(role).or_insert(hex);
                        }
                    }
                }
                for params in found {
                    for hex in triplets(params) {
                        self.count(hex);
                    }
                }
            }
            _ => {}
        }
    }
}

/// For aligning: the module type, for `custom` also the first visible character
/// (header, section, line and status line all start differently).
fn signature(module: &Value) -> Res<String> {
    if let Value::String(s) = module {
        return Ok(s.clone());
    }
    let Some(map) = module.as_object() else {
        return other("Modul ist kein Objekt");
    };
    let mut kind = map.get("type").map_or_else(|| "?".to_owned(), text_of);
    if kind == "custom" {
        let format = map.get("format").map_or_else(String::new, text_of);
        let text = TAG_RE.replace_all(&format, "");
        let first: String = text.trim_matches(py_space).chars().take(1).collect();
        kind = format!("{kind}:{first}");
    }
    Ok(kind)
}

struct Row {
    module: Value,
    values: HashMap<&'static str, Value>,
}

pub fn import_files(lid: &str, title: Option<Value>) -> Res<Value> {
    let dir = look_dir(lid)?;
    let mut raw: HashMap<&str, Value> = HashMap::new();
    for size in SIZES {
        let path = dir.join(format!("{size}.jsonc"));
        if path.is_file() {
            raw.insert(size, load_jsonc(&path)?);
        }
    }
    let Some(config) = raw.get("config").cloned() else {
        return fail(format!("{lid}: config.jsonc fehlt"));
    };
    for size in SIZES {
        raw.entry(size).or_insert_with(|| config.clone());
    }

    let mut colors = Colors::default();
    for size in SIZES {
        colors.collect(&raw[size], &mut Vec::new());
    }
    let mut palette = Map::new();
    let mut names: HashMap<String, String> = HashMap::new();
    for role in ["primary", "accent", "highlight", "muted"] {
        if let Some(hex) = colors.roles.get(role)
            && !names.contains_key(hex)
        {
            names.insert(hex.clone(), role.to_owned());
            palette.insert(role.to_owned(), json!(hex));
        }
    }
    // Stable, so ties stay in order of first appearance.
    let mut ranked = colors.counts.clone();
    ranked.sort_by_key(|(_, n)| std::cmp::Reverse(*n));
    let mut extra = 1;
    for (hex, _) in ranked {
        if !names.contains_key(&hex) {
            let name = if extra == 1 {
                "extra".to_owned()
            } else {
                format!("extra{extra}")
            };
            extra += 1;
            names.insert(hex.clone(), name.clone());
            palette.insert(name, json!(hex));
        }
    }

    let mut encoded: HashMap<&str, Map<String, Value>> = HashMap::new();
    let mut modules: HashMap<&str, Vec<Value>> = HashMap::new();
    for size in SIZES {
        let Value::Object(mut map) = encode(&raw[size], &names) else {
            return other("Konfiguration ist kein Objekt");
        };
        let list = match map.shift_remove("modules") {
            None => Vec::new(),
            Some(Value::Array(list)) => list,
            Some(_) => return other("modules ist keine Liste"),
        };
        modules.insert(size, list);
        encoded.insert(size, map);
    }
    let base = encoded["config"].clone();

    // Align the rows across the sizes, each size keeps its order.
    let mut rows: Vec<Row> = modules["config"]
        .iter()
        .map(|m| Row {
            module: m.clone(),
            values: HashMap::from([("config", m.clone())]),
        })
        .collect();
    for size in ["compact", "mini"] {
        let seq = &modules[size];
        let a = rows
            .iter()
            .map(|r| signature(&r.module))
            .collect::<Res<Vec<_>>>()?;
        let b = seq.iter().map(signature).collect::<Res<Vec<_>>>()?;
        let mut old = rows.into_iter();
        let mut merged = Vec::new();
        for op in opcodes(&a, &b) {
            if op.equal {
                for k in 0..op.i2 - op.i1 {
                    let mut row = old.next().unwrap();
                    row.values.insert(size, seq[op.j1 + k].clone());
                    merged.push(row);
                }
            } else {
                merged.extend(old.by_ref().take(op.i2 - op.i1));
                merged.extend(seq[op.j1..op.j2].iter().map(|m| Row {
                    module: m.clone(),
                    values: HashMap::from([(size, m.clone())]),
                }));
            }
        }
        rows = merged;
    }

    let mut out_rows = Vec::new();
    for row in rows {
        let mut sizes = Map::new();
        for size in SIZES {
            match row.values.get(size) {
                None => {
                    sizes.insert(size.to_owned(), json!(false));
                }
                Some(value) => {
                    if let Some(patch) = row_patch(&row.module, value) {
                        sizes.insert(size.to_owned(), patch);
                    }
                }
            }
        }
        let mut out = Map::new();
        out.insert("m".to_owned(), row.module);
        if !sizes.is_empty() {
            out.insert("sizes".to_owned(), Value::Object(sizes));
        }
        out_rows.push(Value::Object(out));
    }

    let mut size_patches = Map::new();
    for size in SIZES {
        let patch = diff(&base, &encoded[size]);
        let entry = if size != "config" && !patch.is_empty() {
            json!({"patch": patch})
        } else {
            json!({})
        };
        size_patches.insert(size.to_owned(), entry);
    }
    let title = title
        .filter(truthy)
        .unwrap_or_else(|| json!(default_title(lid)));
    Ok(json!({
        "version": 1, "title": title, "palette": palette, "base": base, "sizes": size_patches, "rows": out_rows,
    }))
}

// ---- difflib.SequenceMatcher(None, a, b, autojunk=False) ----------------------

pub struct Opcode {
    pub equal: bool,
    pub i1: usize,
    pub i2: usize,
    pub j1: usize,
    pub j2: usize,
}

fn longest_match(
    a: &[String],
    b2j: &HashMap<&str, Vec<usize>>,
    (alo, ahi, blo, bhi): (usize, usize, usize, usize),
) -> (usize, usize, usize) {
    let (mut besti, mut bestj, mut bestsize) = (alo, blo, 0);
    let mut j2len: HashMap<usize, usize> = HashMap::new();
    for (i, item) in a.iter().enumerate().take(ahi).skip(alo) {
        let mut next: HashMap<usize, usize> = HashMap::new();
        if let Some(indices) = b2j.get(item.as_str()) {
            for &j in indices {
                if j < blo {
                    continue;
                }
                if j >= bhi {
                    break;
                }
                let k = j
                    .checked_sub(1)
                    .and_then(|p| j2len.get(&p))
                    .copied()
                    .unwrap_or(0)
                    + 1;
                next.insert(j, k);
                if k > bestsize {
                    (besti, bestj, bestsize) = (i + 1 - k, j + 1 - k, k);
                }
            }
        }
        j2len = next;
    }
    (besti, bestj, bestsize)
}

/// Same order as Python: it decides which of several equally long matches wins.
pub fn opcodes(a: &[String], b: &[String]) -> Vec<Opcode> {
    let mut b2j: HashMap<&str, Vec<usize>> = HashMap::new();
    for (j, item) in b.iter().enumerate() {
        b2j.entry(item.as_str()).or_default().push(j);
    }
    let mut queue = vec![(0, a.len(), 0, b.len())];
    let mut blocks = Vec::new();
    while let Some(range) = queue.pop() {
        let (alo, ahi, blo, bhi) = range;
        let (i, j, k) = longest_match(a, &b2j, range);
        if k > 0 {
            blocks.push((i, j, k));
            if alo < i && blo < j {
                queue.push((alo, i, blo, j));
            }
            if i + k < ahi && j + k < bhi {
                queue.push((i + k, ahi, j + k, bhi));
            }
        }
    }
    blocks.sort_unstable();

    let mut collapsed: Vec<(usize, usize, usize)> = Vec::new();
    for (i, j, k) in blocks {
        match collapsed.last_mut() {
            Some(last) if last.0 + last.2 == i && last.1 + last.2 == j => last.2 += k,
            _ => collapsed.push((i, j, k)),
        }
    }
    collapsed.push((a.len(), b.len(), 0));

    let mut out = Vec::new();
    let (mut i, mut j) = (0, 0);
    for (ai, bj, size) in collapsed {
        if i < ai || j < bj {
            out.push(Opcode {
                equal: false,
                i1: i,
                i2: ai,
                j1: j,
                j2: bj,
            });
        }
        (i, j) = (ai + size, bj + size);
        if size > 0 {
            out.push(Opcode {
                equal: true,
                i1: ai,
                i2: i,
                j1: bj,
                j2: j,
            });
        }
    }
    out
}
