//! `compute_hash` of `paths.py`, including the index shared with the Python CLI.

use std::fs::{self, File};
use std::io;
use std::os::unix::fs::MetadataExt;
use std::path::Path;

use serde_json::{Map, Value, json};
use sha2::{Digest, Sha256};

use crate::fsutil::{atomic_dump, resolve};
use crate::paths::hash_index_path;

/// Below this size hashing is cheap, nothing is remembered.
const INDEX_MIN: u64 = 1 << 20;

fn sha256_of(path: &Path) -> io::Result<String> {
    let mut hasher = Sha256::new();
    io::copy(&mut File::open(path)?, &mut hasher)?;
    Ok(hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect())
}

/// sha256 of the content. Large files (wallpapers of up to 40 MB) are remembered
/// by size and modification time.
pub fn compute_hash(path: &Path) -> io::Result<String> {
    let metadata = fs::metadata(path)?;
    if metadata.size() < INDEX_MIN {
        return sha256_of(path);
    }

    let key = resolve(path).to_string_lossy().into_owned();
    let size = metadata.size();
    let mtime_ns = i128::from(metadata.mtime()) * 1_000_000_000 + i128::from(metadata.mtime_nsec());
    let index_path = hash_index_path();
    let mut index: Map<String, Value> = fs::read_to_string(&index_path)
        .ok()
        .and_then(|text| serde_json::from_str(&text).ok())
        .unwrap_or_default();

    if let Some(Value::Array(hit)) = index.get(&key)
        && hit.first().and_then(Value::as_u64) == Some(size)
        && hit.get(1).and_then(Value::as_i64).map(i128::from) == Some(mtime_ns)
        && let Some(digest) = hit.get(2).and_then(Value::as_str)
    {
        return Ok(digest.to_owned());
    }

    let digest = sha256_of(path)?;
    let mtime = i64::try_from(mtime_ns).unwrap_or(i64::MAX);
    index.insert(key, json!([size, mtime, digest]));
    atomic_dump(&index_path, &Value::Object(index))?;
    Ok(digest)
}
