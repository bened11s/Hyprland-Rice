//! `json.dumps` of Python, byte for byte.

use std::fmt::Write;

use serde_json::{Number, Value};

/// Options of `json.dumps`.
#[derive(Clone, Copy)]
pub struct Style {
    pub indent: Option<usize>,
    pub ensure_ascii: bool,
}

/// `json.dumps(value)`
pub const DEFAULT: Style = Style {
    indent: None,
    ensure_ascii: true,
};
/// `json.dumps(value, ensure_ascii=False)`
pub const UNICODE: Style = Style {
    indent: None,
    ensure_ascii: false,
};

/// `json.dumps(value, indent=n, ensure_ascii=False)`
#[must_use]
pub const fn pretty(indent: usize) -> Style {
    Style {
        indent: Some(indent),
        ensure_ascii: false,
    }
}

#[must_use]
pub fn dumps(value: &Value, style: Style) -> String {
    let mut out = String::new();
    write_value(&mut out, value, style, 0);
    out
}

fn newline(out: &mut String, style: Style, depth: usize) {
    if let Some(indent) = style.indent {
        out.push('\n');
        out.extend(std::iter::repeat_n(' ', indent * depth));
    }
}

fn separator(style: Style) -> &'static str {
    if style.indent.is_some() { "," } else { ", " }
}

fn write_value(out: &mut String, value: &Value, style: Style, depth: usize) {
    match value {
        Value::Null => out.push_str("null"),
        Value::Bool(true) => out.push_str("true"),
        Value::Bool(false) => out.push_str("false"),
        Value::Number(n) => out.push_str(&number(n)),
        Value::String(s) => write_string(out, s, style.ensure_ascii),
        Value::Array(items) if items.is_empty() => out.push_str("[]"),
        Value::Array(items) => {
            out.push('[');
            for (i, item) in items.iter().enumerate() {
                if i > 0 {
                    out.push_str(separator(style));
                }
                newline(out, style, depth + 1);
                write_value(out, item, style, depth + 1);
            }
            newline(out, style, depth);
            out.push(']');
        }
        Value::Object(map) if map.is_empty() => out.push_str("{}"),
        Value::Object(map) => {
            out.push('{');
            for (i, (key, item)) in map.iter().enumerate() {
                if i > 0 {
                    out.push_str(separator(style));
                }
                newline(out, style, depth + 1);
                write_string(out, key, style.ensure_ascii);
                out.push_str(": ");
                write_value(out, item, style, depth + 1);
            }
            newline(out, style, depth);
            out.push('}');
        }
    }
}

fn number(n: &Number) -> String {
    match n.as_f64() {
        Some(f) if n.is_f64() => float_repr(f),
        _ => n.to_string(),
    }
}

/// `repr(float)`: the shortest digits, in exponent form below 1e-4 and from 1e16 on.
#[must_use]
pub fn float_repr(f: f64) -> String {
    if f.is_nan() {
        return "NaN".to_owned();
    }
    if f.is_infinite() {
        return if f > 0.0 {
            "Infinity".to_owned()
        } else {
            "-Infinity".to_owned()
        };
    }
    let sci = format!("{f:e}");
    let (mantissa, exp) = sci.split_once('e').unwrap_or((&sci, "0"));
    let exp: i32 = exp.parse().unwrap_or(0);
    if (-4..16).contains(&exp) {
        let plain = format!("{f}");
        return if plain.contains('.') {
            plain
        } else {
            format!("{plain}.0")
        };
    }
    let sign = if exp < 0 { '-' } else { '+' };
    format!("{mantissa}e{sign}{:02}", exp.abs())
}

fn write_string(out: &mut String, text: &str, ensure_ascii: bool) {
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            c if u32::from(c) < 0x20 => push_escaped(out, u32::from(c)),
            c if ensure_ascii && !c.is_ascii() => {
                let mut units = [0u16; 2];
                for unit in c.encode_utf16(&mut units) {
                    push_escaped(out, u32::from(*unit));
                }
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn push_escaped(out: &mut String, unit: u32) {
    let _ = write!(out, "\\u{unit:04x}");
}

/// What `str(value)` gives for the values that turn up in practice.
#[must_use]
pub fn text_of(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Null => "None".to_owned(),
        Value::Bool(true) => "True".to_owned(),
        Value::Bool(false) => "False".to_owned(),
        other => dumps(other, UNICODE),
    }
}

/// Truthiness of a Python value.
#[must_use]
pub fn truthy(value: &Value) -> bool {
    match value {
        Value::Null => false,
        Value::Bool(b) => *b,
        Value::Number(n) => n.as_f64() != Some(0.0),
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => !a.is_empty(),
        Value::Object(o) => !o.is_empty(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn matches_python_separators() {
        let value = json!({"a": [1, 2.5], "b": {}, "c": []});
        assert_eq!(
            dumps(&value, UNICODE),
            r#"{"a": [1, 2.5], "b": {}, "c": []}"#
        );
        assert_eq!(
            dumps(&value, pretty(2)),
            "{\n  \"a\": [\n    1,\n    2.5\n  ],\n  \"b\": {},\n  \"c\": []\n}"
        );
    }

    #[test]
    fn escapes_like_python() {
        let expected = "\"\\u00e4\\ud83c\\udfb5\\n\\u0001\"";
        assert_eq!(dumps(&json!("ä🎵\n\u{1}"), DEFAULT), expected);
        assert_eq!(dumps(&json!("ä🎵\u{7f}"), UNICODE), "\"ä🎵\u{7f}\"");
    }

    #[test]
    fn floats_like_python_repr() {
        for (value, text) in [
            (1.0, "1.0"),
            (0.1, "0.1"),
            (1e16, "1e+16"),
            (1e15, "1000000000000000.0"),
            (0.0001, "0.0001"),
            (0.00001, "1e-05"),
            (1.5e-7, "1.5e-07"),
            (-2.5e100, "-2.5e+100"),
        ] {
            assert_eq!(float_repr(value), text);
        }
    }
}
