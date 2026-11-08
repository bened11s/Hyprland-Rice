//! Patches between objects, with the comparison rules of Python.

use serde_json::{Map, Value, json};

use crate::{Res, fail, get};

fn number_of(value: &Value) -> Option<f64> {
    match value {
        Value::Bool(b) => Some(f64::from(u8::from(*b))),
        Value::Number(n) => n.as_f64(),
        _ => None,
    }
}

/// `a == b` of Python: `1 == 1.0 == True`, and key order does not matter.
pub fn py_eq(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Null, Value::Null) => true,
        (Value::String(x), Value::String(y)) => x == y,
        (Value::Array(x), Value::Array(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(p, q)| py_eq(p, q))
        }
        (Value::Object(x), Value::Object(y)) => {
            x.len() == y.len() && x.iter().all(|(k, p)| y.get(k).is_some_and(|q| py_eq(p, q)))
        }
        _ => matches!((number_of(a), number_of(b)), (Some(x), Some(y)) if x == y),
    }
}

/// `type(a) is type(b)`
fn same_type(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => x.is_f64() == y.is_f64(),
        _ => std::mem::discriminant(a) == std::mem::discriminant(b),
    }
}

pub fn merge(base: &Value, patch: &Value) -> Value {
    let (Value::Object(base), Value::Object(patch)) = (base, patch) else {
        return patch.clone();
    };
    let mut out = base.clone();
    for (k, v) in patch {
        if v.is_null() {
            out.shift_remove(k);
        } else if let (Value::Object(_), Some(old @ Value::Object(_))) = (v, out.get(k)) {
            let merged = merge(old, v);
            out.insert(k.clone(), merged);
        } else {
            out.insert(k.clone(), v.clone());
        }
    }
    Value::Object(out)
}

/// The patch with `merge(base, patch) == target`, both objects.
pub fn diff(base: &Map<String, Value>, target: &Map<String, Value>) -> Map<String, Value> {
    let mut patch = Map::new();
    for k in base.keys() {
        if !target.contains_key(k) {
            patch.insert(k.clone(), Value::Null);
        }
    }
    for (k, v) in target {
        match base.get(k) {
            None => {
                patch.insert(k.clone(), v.clone());
            }
            Some(Value::Object(old)) if v.is_object() => {
                let d = diff(old, v.as_object().unwrap());
                if !d.is_empty() {
                    patch.insert(k.clone(), Value::Object(d));
                }
            }
            Some(old) => {
                if !py_eq(v, old) || !same_type(v, old) {
                    patch.insert(k.clone(), v.clone());
                }
            }
        }
    }
    patch
}

/// The module of a row in `size`, or None if it is missing there.
pub fn row_value(row: &Value, size: &str) -> Res<Option<Value>> {
    let sizes = get(row, "sizes")?.filter(|s| di_common::pyjson::truthy(s));
    let entry = match sizes {
        Some(sizes) => get(sizes, size)?,
        None => None,
    };
    let module = &row["m"];
    match entry {
        Some(Value::Bool(false)) => Ok(None),
        None | Some(Value::Null) => Ok(Some(module.clone())),
        Some(Value::Object(patch)) => {
            if let Some(whole) = patch.get("=") {
                return Ok(Some(whole.clone()));
            }
            if module.is_object() {
                return Ok(Some(merge(module, entry.unwrap())));
            }
            fail("ungueltiger Zeilen-Patch")
        }
        Some(_) => fail("ungueltiger Zeilen-Patch"),
    }
}

pub fn row_patch(module: &Value, value: &Value) -> Option<Value> {
    if py_eq(value, module) {
        return None;
    }
    if let (Value::Object(m), Value::Object(v)) = (module, value)
        && !v.contains_key("=")
    {
        return Some(Value::Object(diff(m, v)));
    }
    Some(json!({"=": value}))
}
