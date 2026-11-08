import hashlib
import json
import os
import tempfile
from pathlib import Path
from typing import Any

from dynamic_island.utils.io import warn

config_dir: Path = Path(os.getenv("XDG_CONFIG_HOME", Path.home() / ".config"))
data_dir: Path = Path(os.getenv("XDG_DATA_HOME", Path.home() / ".local/share"))
state_dir: Path = Path(os.getenv("XDG_STATE_HOME", Path.home() / ".local/state"))
cache_dir: Path = Path(os.getenv("XDG_CACHE_HOME", Path.home() / ".cache"))
pictures_dir: Path = Path(os.getenv("XDG_PICTURES_DIR", Path.home() / "Pictures"))
videos_dir: Path = Path(os.getenv("XDG_VIDEOS_DIR", Path.home() / "Videos"))

# Alles unter dem eigenen Namen – keine geteilten Verzeichnisse mit anderen Shells
c_config_dir: Path = config_dir / "dynamic-island"
c_data_dir: Path = data_dir / "dynamic-island"
c_state_dir: Path = state_dir / "dynamic-island"
c_cache_dir: Path = cache_dir / "dynamic-island"

user_config_path: Path = c_config_dir / "cli.json"
cli_data_dir: Path = Path(__file__).parent.parent / "data"
templates_dir: Path = cli_data_dir / "templates"
user_templates_dir: Path = c_config_dir / "templates"
theme_dir: Path = c_state_dir / "theme"

scheme_path: Path = c_state_dir / "scheme.json"
scheme_data_dir: Path = cli_data_dir / "schemes"
scheme_cache_dir: Path = c_cache_dir / "schemes"

wallpapers_dir: Path = Path(os.getenv("DYNAMIC_ISLAND_WALLPAPERS_DIR", pictures_dir / "Wallpapers"))
wallpaper_path_path: Path = c_state_dir / "wallpaper/path.txt"
wallpaper_link_path: Path = c_state_dir / "wallpaper/current"
wallpaper_thumbnail_path: Path = c_state_dir / "wallpaper/thumbnail.jpg"
# Fest gewaehlter Stil (Material-Variante) je Wallpaper; fehlt ein Bild, rechnet
# "smart" ihn aus dem Bild aus
wallpaper_variants_path: Path = c_state_dir / "wallpaper/variants.json"
wallpapers_cache_dir: Path = c_cache_dir / "wallpapers"

screenshots_dir: Path = Path(os.getenv("DYNAMIC_ISLAND_SCREENSHOTS_DIR", pictures_dir / "Screenshots"))
screenshots_cache_dir: Path = c_cache_dir / "screenshots"

recordings_dir: Path = Path(os.getenv("DYNAMIC_ISLAND_RECORDINGS_DIR", videos_dir / "Recordings"))
recording_path: Path = c_state_dir / "record/recording.mp4"
recording_notif_path: Path = c_state_dir / "record/notifid.txt"


# Pfad -> [Groesse, mtime_ns, Hash] fuer grosse Dateien (siehe compute_hash)
hash_index_path: Path = c_cache_dir / "hashes.json"
HASH_INDEX_MIN = 1 << 20


def compute_hash(path: Path | str) -> str:
    """sha256 des Inhalts; Name der Cache-Ordner je Bild.

    Grosse Dateien (Wallpaper bis 40 MB) merkt sich ein Index nach Groesse und
    Aenderungszeit: die Vorschau beim Blaettern hashte sonst jedes Mal das
    ganze Original (~10 ms bei 16 MB), obwohl alles andere aus dem Cache kommt.
    """
    st = os.stat(path)
    key = str(Path(path).resolve())
    index = None
    if st.st_size >= HASH_INDEX_MIN:
        try:
            index = json.loads(hash_index_path.read_text())
        except (IOError, json.JSONDecodeError):
            index = {}
        hit = index.get(key)
        if hit and hit[0] == st.st_size and hit[1] == st.st_mtime_ns:
            return hit[2]

    sha = hashlib.sha256()
    with open(path, "rb", buffering=0) as f:
        while chunk := f.read(1 << 20):
            sha.update(chunk)
    digest = sha.hexdigest()

    if index is not None:
        index[key] = [st.st_size, st.st_mtime_ns, digest]
        hash_index_path.parent.mkdir(parents=True, exist_ok=True)
        atomic_dump(hash_index_path, index)

    return digest


def atomic_write(path: Path, content: str) -> bool:
    """Schreibt nur, wenn sich der Inhalt aendert; True = geschrieben.

    Gleicher Inhalt bleibt unangetastet: jede geschriebene Datei weckt ihre
    Watcher (Hyprland laedt bei scheme/current.lua die ganze Config neu,
    Quickshell faerbt bei scheme.json alles um) - bei einem Wallpaperwechsel
    mit festem Schema wuerde das sonst ohne jede Farbaenderung passieren.
    """
    try:
        if path.read_text() == content:
            return False
    except (OSError, UnicodeDecodeError):
        pass

    path.parent.mkdir(parents=True, exist_ok=True)
    f = tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False)
    try:
        with f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(f.name, path)
    except BaseException:
        os.unlink(f.name)
        raise
    return True


def atomic_dump(path: Path, content: dict[str, Any]) -> bool:
    return atomic_write(path, json.dumps(content))


def get_config() -> dict[str, Any]:
    try:
        return json.loads(user_config_path.read_text())
    except json.JSONDecodeError:
        warn("failed to parse config, invalid JSON")
    except FileNotFoundError:
        pass
    return {}
