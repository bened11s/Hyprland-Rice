//! The same places as `dynamic_island/utils/paths.py`.

use std::ffi::OsString;
use std::path::{Path, PathBuf};

fn env_or(name: &str, default: impl FnOnce() -> PathBuf) -> PathBuf {
    std::env::var_os(name).map_or_else(default, PathBuf::from)
}

#[must_use]
pub fn home() -> PathBuf {
    std::env::home_dir().unwrap_or_else(|| PathBuf::from("/"))
}

#[must_use]
pub fn config_dir() -> PathBuf {
    env_or("XDG_CONFIG_HOME", || home().join(".config"))
}

#[must_use]
pub fn state_dir() -> PathBuf {
    env_or("XDG_STATE_HOME", || home().join(".local/state"))
}

#[must_use]
pub fn cache_dir() -> PathBuf {
    env_or("XDG_CACHE_HOME", || home().join(".cache"))
}

#[must_use]
pub fn c_config_dir() -> PathBuf {
    config_dir().join("dynamic-island")
}

#[must_use]
pub fn c_state_dir() -> PathBuf {
    state_dir().join("dynamic-island")
}

#[must_use]
pub fn c_cache_dir() -> PathBuf {
    cache_dir().join("dynamic-island")
}

#[must_use]
pub fn hash_index_path() -> PathBuf {
    c_cache_dir().join("hashes.json")
}

/// What `pathlib` does to a path it gets: no `//`, no `/./`, no trailing slash.
#[must_use]
pub fn normalise(path: &Path) -> PathBuf {
    path.components().collect()
}

/// `Path(x).expanduser()` for `~` and `~/...`.
#[must_use]
pub fn expand_user(path: &str) -> PathBuf {
    if path == "~" {
        home()
    } else if let Some(rest) = path.strip_prefix("~/") {
        home().join(rest.trim_start_matches('/'))
    } else {
        PathBuf::from(path)
    }
}

/// `DYNAMIC_ISLAND_<name>` or a default.
#[must_use]
pub fn override_or(name: &str, default: impl FnOnce() -> PathBuf) -> PathBuf {
    let var: OsString = format!("DYNAMIC_ISLAND_{name}").into();
    std::env::var_os(var).map_or_else(default, |value| normalise(Path::new(&value)))
}
