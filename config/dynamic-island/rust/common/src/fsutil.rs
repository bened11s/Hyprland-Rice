//! File operations with the behaviour of `pathlib`, `shutil` and `atomic_write`.

use std::fs::{self, File};
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt, symlink};
use std::path::{Component, Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::pyjson;

/// `Path.resolve()`: follows symlinks, a missing tail stays as it is.
#[must_use]
pub fn resolve(path: &Path) -> PathBuf {
    let absolute = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir().unwrap_or_default().join(path)
    };
    let mut pending: Vec<std::ffi::OsString> = absolute
        .components()
        .rev()
        .filter_map(component_name)
        .collect();
    let mut out = PathBuf::from("/");
    let mut links_left = 40;
    while let Some(part) = pending.pop() {
        if part == ".." {
            out.pop();
            continue;
        }
        out.push(&part);
        if links_left == 0 {
            continue;
        }
        if let Ok(target) = fs::read_link(&out) {
            links_left -= 1;
            out.pop();
            if target.is_absolute() {
                out = PathBuf::from("/");
            }
            pending.extend(target.components().rev().filter_map(component_name));
        }
    }
    out
}

fn component_name(component: Component<'_>) -> Option<std::ffi::OsString> {
    match component {
        Component::Normal(name) => Some(name.to_owned()),
        Component::ParentDir => Some("..".into()),
        _ => None,
    }
}

/// Text mode of Python: `\\r\\n` and `\\r` turn into `\\n`.
#[must_use]
pub fn universal_newlines(text: &str) -> String {
    if text.contains('\r') {
        text.replace("\r\n", "\n").replace('\r', "\n")
    } else {
        text.to_owned()
    }
}

/// `Path.read_text()`
pub fn read_text(path: &Path) -> io::Result<String> {
    Ok(universal_newlines(&fs::read_to_string(path)?))
}

/// `atomic_write` of `paths.py`: writes only when the content changes, so watchers
/// stay asleep. True if written. The file ends up with mode 0600, like before.
pub fn atomic_write(path: &Path, content: &str) -> io::Result<bool> {
    if read_text(path).is_ok_and(|old| old == content) {
        return Ok(false);
    }
    let parent = path.parent().unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    let mut tmp = tempfile::NamedTempFile::new_in(parent)?;
    tmp.write_all(content.as_bytes())?;
    tmp.as_file().sync_all()?;
    tmp.persist(path).map_err(|e| e.error)?;
    Ok(true)
}

/// `atomic_dump` of `paths.py`.
pub fn atomic_dump(path: &Path, content: &serde_json::Value) -> io::Result<bool> {
    atomic_write(path, &pyjson::dumps(content, pyjson::DEFAULT))
}

fn modified(metadata: &fs::Metadata) -> SystemTime {
    let seconds = metadata.mtime().max(0).unsigned_abs();
    let nanos = u32::try_from(metadata.mtime_nsec()).unwrap_or(0);
    UNIX_EPOCH + Duration::new(seconds, nanos)
}

/// `shutil.copy2`: content, mode and modification time.
pub fn copy2(src: &Path, dest: &Path) -> io::Result<()> {
    fs::copy(src, dest)?;
    let metadata = fs::metadata(src)?;
    File::options()
        .write(true)
        .open(dest)?
        .set_modified(modified(&metadata))
}

/// `shutil.copytree` that follows symlinks, leaving out names in `skip`.
pub fn copy_tree(src: &Path, dest: &Path, skip: &[&str]) -> io::Result<()> {
    fs::create_dir_all(dest)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let name = entry.file_name();
        if name.to_str().is_some_and(|n| skip.contains(&n)) {
            continue;
        }
        let (from, to) = (entry.path(), dest.join(&name));
        if from.is_dir() {
            copy_tree(&from, &to, skip)?;
        } else {
            copy2(&from, &to)?;
        }
    }
    let metadata = fs::metadata(src)?;
    fs::set_permissions(dest, metadata.permissions())?;
    Ok(())
}

/// `shutil.move`: rename, across file systems copy and delete. Symlinks stay symlinks.
pub fn move_path(src: &Path, dest: &Path) -> io::Result<()> {
    match fs::rename(src, dest) {
        Err(e) if e.raw_os_error() == Some(libc::EXDEV) => {
            copy_keeping_links(src, dest)?;
            if fs::symlink_metadata(src)?.is_dir() {
                fs::remove_dir_all(src)
            } else {
                fs::remove_file(src)
            }
        }
        other => other,
    }
}

fn copy_keeping_links(src: &Path, dest: &Path) -> io::Result<()> {
    let metadata = fs::symlink_metadata(src)?;
    if metadata.is_symlink() {
        return symlink(fs::read_link(src)?, dest);
    }
    if !metadata.is_dir() {
        return copy2(src, dest);
    }
    fs::create_dir_all(dest)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        copy_keeping_links(&entry.path(), &dest.join(entry.file_name()))?;
    }
    fs::set_permissions(dest, metadata.permissions())
}

/// `Path.rglob("*")` sorted like `sorted()`: symlinked folders are not entered.
pub fn walk_sorted(root: &Path) -> io::Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        for entry in fs::read_dir(&dir)? {
            let entry = entry?;
            let path = entry.path();
            if entry.file_type()?.is_dir() {
                stack.push(path.clone());
            }
            out.push(path);
        }
    }
    // PathBuf compares by component, like pathlib
    out.sort();
    Ok(out)
}
