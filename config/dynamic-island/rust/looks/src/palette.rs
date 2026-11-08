//! Colour suggestions from an image.
//!
//! Strong, bright colours win: wallpapers are often dark, and the text has to stay
//! readable on the terminal background.

use std::process::Command;
use std::sync::LazyLock;

use di_common::paths;
use regex::Regex;
use serde_json::{Map, Value, json};

use crate::markup::{hexc, rgb_to_unit};
use crate::preview::run_with_timeout;
use crate::{Res, fail, last_line, other};

static LINE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\s*(\d+):.*?#([0-9A-Fa-f]{6})").unwrap());

#[derive(Clone)]
struct Color {
    n: f64,
    h: f64,
    s: f64,
    v: f64,
}

/// `colorsys.rgb_to_hsv`
fn rgb_to_hsv(r: f64, g: f64, b: f64) -> (f64, f64, f64) {
    let maxc = r.max(g).max(b);
    let minc = r.min(g).min(b);
    if minc == maxc {
        return (0.0, 0.0, maxc);
    }
    let range = maxc - minc;
    let s = range / maxc;
    let rc = (maxc - r) / range;
    let gc = (maxc - g) / range;
    let bc = (maxc - b) / range;
    let h = if r == maxc {
        bc - gc
    } else if g == maxc {
        2.0 + rc - bc
    } else {
        4.0 + gc - rc
    };
    ((h / 6.0).rem_euclid(1.0), s, maxc)
}

/// `colorsys.hsv_to_rgb`
fn hsv_to_rgb(h: f64, s: f64, v: f64) -> [f64; 3] {
    if s == 0.0 {
        return [v, v, v];
    }
    let i = (h * 6.0).trunc();
    let f = h * 6.0 - i;
    let p = v * (1.0 - s);
    let q = v * (1.0 - s * f);
    let t = v * (1.0 - s * (1.0 - f));
    #[allow(clippy::cast_possible_truncation)]
    match (i as i64).rem_euclid(6) {
        0 => [v, t, p],
        1 => [q, v, p],
        2 => [p, v, t],
        3 => [p, q, v],
        4 => [t, p, v],
        _ => [v, p, q],
    }
}

/// `round(x * 255)`: Python rounds halves to the even number, `round_ties_even` does the same.
fn channels(rgb: [f64; 3]) -> String {
    #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let values = rgb.map(|x| (x * 255.0).round_ties_even() as u64);
    hexc(&values)
}

/// Brightens colours that are too dark, the hue stays.
fn lift(c: &Color, v_min: f64) -> String {
    channels(hsv_to_rgb(c.h, c.s, c.v.max(v_min)))
}

fn hue_dist(a: &Color, b: &Color) -> f64 {
    let d = (a.h - b.h).abs();
    d.min(1.0 - d)
}

/// `max(items, key=...)`: the first of several equal ones wins.
fn best<'a>(items: &[&'a Color], key: impl Fn(&Color) -> f64) -> Option<&'a Color> {
    let mut winner: Option<(&Color, f64)> = None;
    for item in items {
        let score = key(item);
        if winner.is_none_or(|(_, top)| score > top) {
            winner = Some((item, score));
        }
    }
    winner.map(|(c, _)| c)
}

pub fn palette_from_image(image: &str, count: i64) -> Res<Value> {
    let src = paths::expand_user(image);
    if !src.is_file() {
        return fail(format!("Bild fehlt: {image}"));
    }
    let mut magick = Command::new("magick");
    magick.arg(&src).args([
        "-resize",
        "200x200",
        "-colors",
        "24",
        "-format",
        "%c",
        "histogram:info:-",
    ]);
    let Some(output) = run_with_timeout(&mut magick, 60)? else {
        return other("magick antwortet nicht");
    };
    if !output.status.success() {
        return fail(format!(
            "magick: {}",
            last_line(&String::from_utf8_lossy(&output.stderr))
        ));
    }

    let mut cols = Vec::new();
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        if let Some(caps) = LINE_RE.captures(line) {
            let hex = format!("#{}", caps[2].to_lowercase());
            let unit = rgb_to_unit(&hex);
            let (h, s, v) = rgb_to_hsv(unit[0], unit[1], unit[2]);
            cols.push(Color {
                n: caps[1].parse().unwrap_or(0.0),
                h,
                s,
                v,
            });
        }
    }
    if cols.is_empty() {
        return fail("keine Farben gefunden");
    }
    let total: f64 = cols.iter().map(|c| c.n).sum();
    let vivid = |c: &Color| (c.n / total).powf(0.35) * c.s.powf(1.5) * (0.3 + c.v);

    // Stable and descending, like sorted(reverse=True).
    let mut ranked: Vec<&Color> = cols.iter().collect();
    ranked.sort_by(|a, b| {
        vivid(b)
            .partial_cmp(&vivid(a))
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let mut roles = Map::new();
    let primary = ranked[0];
    roles.insert("primary".to_owned(), json!(lift(primary, 0.85)));

    let others: Vec<&Color> = ranked[1..].iter().copied().filter(|c| c.s > 0.25).collect();
    if let Some(accent) = best(&others, |c| vivid(c) * (0.2 + hue_dist(c, primary))) {
        roles.insert("accent".to_owned(), json!(lift(accent, 0.8)));
        let rest: Vec<&Color> = others
            .iter()
            .copied()
            .filter(|c| !std::ptr::eq(*c, accent))
            .collect();
        let third = best(&rest, |c| {
            vivid(c) * (0.2 + hue_dist(c, primary).min(hue_dist(c, accent)))
        });
        if let Some(third) = third {
            roles.insert("highlight".to_owned(), json!(lift(third, 0.85)));
        }
    }
    let mut greys = cols.clone();
    greys.sort_by(|a, b| {
        a.s.partial_cmp(&b.s)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(b.n.partial_cmp(&a.n).unwrap_or(std::cmp::Ordering::Equal))
    });
    let grey = &greys[0];
    let v = grey.v.clamp(0.5, 0.7);
    roles.insert(
        "muted".to_owned(),
        json!(channels(hsv_to_rgb(grey.h, grey.s.min(0.15), v))),
    );

    let mut out: Vec<String> = Vec::new();
    let role_colors = roles
        .values()
        .filter_map(Value::as_str)
        .map(ToOwned::to_owned);
    for color in role_colors.chain(ranked.iter().map(|c| lift(c, 0.6))) {
        if !out.contains(&color) {
            out.push(color);
        }
    }
    let limit = count.max(i64::try_from(roles.len()).unwrap_or(0));
    out.truncate(usize::try_from(limit).unwrap_or(0));
    Ok(json!({"roles": roles, "colors": out}))
}
