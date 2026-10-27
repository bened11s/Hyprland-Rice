import json
import os
import random
import subprocess
from argparse import Namespace
from pathlib import Path
from typing import cast

# PIL und materialyoucolor erst bei Bedarf laden: die Vorschau (`-p`) laeuft bei
# jedem Blaettern in der Auswahl, meist komplett aus dem Cache, und braucht
# beides dann gar nicht (PIL allein kostete ~20 ms Startzeit)
from dynamic_island.utils.colourfulness import VERSION as SMART_VERSION
from dynamic_island.utils.colourfulness import analyse
from dynamic_island.utils.hypr import message
from dynamic_island.utils.material import get_colours_for_image
from dynamic_island.utils.paths import (
    compute_hash,
    get_config,
    wallpaper_link_path,
    atomic_dump,
    wallpaper_path_path,
    wallpaper_thumbnail_path,
    wallpaper_variants_path,
    wallpapers_cache_dir,
)
from dynamic_island.utils.scheme import Scheme, get_scheme
from dynamic_island.utils.theme import apply_colours


def is_valid_image(path: Path) -> bool:
    return path.is_file() and path.suffix in [".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".gif"]


def check_wall(wall: Path, filter_size: tuple[int, int], threshold: float) -> bool:
    from PIL import Image

    with Image.open(wall) as img:
        width, height = img.size
        return width >= filter_size[0] * threshold and height >= filter_size[1] * threshold


def get_wallpaper() -> str | None:
    try:
        return wallpaper_path_path.read_text()
    except IOError:
        return None


# ---- Stil je Wallpaper ----
# Ein im Menue gewaehlter Stil gilt nur fuer das Bild, auf dem er gewaehlt wurde:
# Schluessel ist der absolute Pfad. Bilder ohne Eintrag bekommen den Stil, den
# get_smart_opts aus der Farbigkeit ableitet ("auto").
def get_wall_variants() -> dict[str, str]:
    try:
        data = json.loads(wallpaper_variants_path.read_text())
        return data if isinstance(data, dict) else {}
    except (IOError, json.JSONDecodeError):
        return {}


def get_wall_variant(wall: Path | str) -> str | None:
    return get_wall_variants().get(str(Path(wall).resolve()))


def set_wall_variant(wall: Path | str, variant: str | None) -> None:
    variants = get_wall_variants()
    key = str(Path(wall).resolve())
    if variant is None:
        variants.pop(key, None)
    else:
        variants[key] = variant
    wallpaper_variants_path.parent.mkdir(parents=True, exist_ok=True)
    atomic_dump(wallpaper_variants_path, dict(sorted(variants.items())))


def apply_wall_variant(variant: str | None, wall: Path | str | None = None) -> None:
    """Stil fuer ein Bild festlegen (None = wieder automatisch).

    Ist das Bild das aktuelle und haengt das Schema am Wallpaper, faerbt es
    gleich um; sonst wirkt der Stil erst beim naechsten Setzen des Bilds.
    """
    current = get_wallpaper()
    wall = Path(wall or current or "").resolve()
    set_wall_variant(wall, variant)

    if not current or Path(current).resolve() != wall:
        return
    scheme = get_scheme()
    if scheme.name != "dynamic":
        return
    if variant is None:
        wall_cache = convert_gif(wall) if wall.suffix.lower() == ".gif" else wall
        variant = get_smart_opts(wall_cache, wallpapers_cache_dir / compute_hash(wall_cache))["variant"]
    scheme.variant = variant
    apply_colours(scheme.colours, scheme.mode)


def get_wallpapers(args: Namespace) -> list[Path]:
    directory = Path(args.random)
    if not directory.is_dir():
        return []

    walls = [f for f in directory.rglob("*") if is_valid_image(f)]

    if args.no_filter:
        return walls

    monitors = cast(list[dict[str, int]], message("monitors"))
    filter_size = min(m["width"] for m in monitors), min(m["height"] for m in monitors)

    return [f for f in walls if check_wall(f, filter_size, args.threshold)]


def get_thumb(wall: Path, cache: Path) -> Path:
    thumb = cache / "thumbnail.jpg"

    if not thumb.exists():
        from PIL import Image

        with Image.open(wall) as img:
            # JPEGs gleich verkleinert dekodieren (libjpeg kann 1/2..1/8):
            # ein 4K-Bild braucht so einen Bruchteil der Zeit
            img.draft("RGB", (256, 256))
            img = img.convert("RGB")
            img.thumbnail((128, 128), Image.Resampling.NEAREST)
            thumb.parent.mkdir(parents=True, exist_ok=True)
            img.save(thumb, "JPEG")

    return thumb


def get_smart_opts(wall: Path, cache: Path) -> dict:
    """Stil und Modus, die "smart" fuer ein Bild waehlt (colourfulness.analyse).

    smart.json haelt das Ergebnis samt Merkmalen; Eintraege einer aelteren
    Analyse-Version werden neu berechnet.
    """
    opts_cache = cache / "smart.json"

    try:
        opts = json.loads(opts_cache.read_text())
        if opts.get("version") == SMART_VERSION:
            return opts
    except (IOError, json.JSONDecodeError):
        pass

    opts = analyse(get_thumb(wall, cache))

    opts_cache.parent.mkdir(parents=True, exist_ok=True)
    atomic_dump(opts_cache, opts)

    return opts


def get_colours_for_wall(wall: Path | str, no_smart: bool) -> dict:
    wall = Path(wall)
    scheme = get_scheme()
    pinned = get_wall_variant(wall)

    # Wie set_wallpaper: bei GIFs haengt der Cache am ersten Einzelbild, sonst
    # lagen fuer dasselbe GIF zwei Cache-Ordner mit eigener Analyse herum
    if wall.suffix.lower() == ".gif":
        wall = convert_gif(wall)
    cache = wallpapers_cache_dir / compute_hash(wall)

    name = "dynamic"

    mode, variant = scheme.mode, scheme.variant
    if not no_smart:
        smart_opts = get_smart_opts(wall, cache)
        mode, variant = smart_opts["mode"], smart_opts["variant"]
    scheme = Scheme(
        {
            "name": name,
            "flavour": scheme.flavour,
            "mode": mode,
            "variant": pinned or variant,
            "colours": scheme.colours,
        }
    )

    return {
        "name": name,
        "flavour": scheme.flavour,
        "mode": scheme.mode,
        "variant": scheme.variant,
        "pinned": pinned is not None,
        "colours": get_colours_for_image(get_thumb(wall, cache), scheme),
    }


def convert_gif(wall: Path) -> Path:
    cache = wallpapers_cache_dir / compute_hash(wall)
    output_path = cache / "first_frame.png"

    if not output_path.exists():
        from PIL import Image

        output_path.parent.mkdir(parents=True, exist_ok=True)
        with Image.open(wall) as img:
            try:
                img.seek(0)
            except EOFError:
                pass

            img = img.convert("RGB")
            img.save(output_path, "PNG")

    return output_path


def set_wallpaper(wall: Path, no_smart: bool) -> None:
    # Make path absolute
    wall = Path(wall).resolve()

    if not is_valid_image(wall):
        raise ValueError(f'"{wall}" is not a valid image')

    # Use gif's 1st frame for thumb only
    wall_cache = convert_gif(wall) if wall.suffix.lower() == ".gif" else wall

    # Update files
    wallpaper_path_path.parent.mkdir(parents=True, exist_ok=True)
    wallpaper_path_path.write_text(str(wall))
    wallpaper_link_path.parent.mkdir(parents=True, exist_ok=True)
    wallpaper_link_path.unlink(missing_ok=True)
    wallpaper_link_path.symlink_to(wall)

    cache = wallpapers_cache_dir / compute_hash(wall_cache)

    # Generate thumbnail or get from cache
    thumb = get_thumb(wall_cache, cache)
    wallpaper_thumbnail_path.parent.mkdir(parents=True, exist_ok=True)
    wallpaper_thumbnail_path.unlink(missing_ok=True)
    wallpaper_thumbnail_path.symlink_to(thumb)

    scheme = get_scheme()

    # Change mode and variant based on wallpaper colour. Im Batch, damit
    # scheme.json nur einmal mit dem fertigen Stand geschrieben wird statt bis
    # zu dreimal (Modus, Variante, Farben) - jedes Mal faerbt sich die Shell um.
    with scheme.batch():
        # Ein fest gewaehlter Stil des Bilds schlaegt den ausgerechneten
        if scheme.name == "dynamic":
            pinned = get_wall_variant(wall)
            if not no_smart:
                smart_opts = get_smart_opts(wall_cache, cache)
                scheme.mode = smart_opts["mode"]
                scheme.variant = pinned or smart_opts["variant"]
            elif pinned:
                scheme.variant = pinned

        # Update colours
        scheme.update_colours()
    apply_colours(scheme.colours, scheme.mode)

    # Run custom post-hook if configured
    cfg = get_config().get("wallpaper", {})
    if post_hook := cfg.get("postHook"):
        subprocess.run(
            post_hook,
            shell=True,
            env={
                **os.environ,
                "WALLPAPER_PATH": str(wall),
                "SCHEME_NAME": scheme.name,
                "SCHEME_FLAVOUR": scheme.flavour,
                "SCHEME_MODE": scheme.mode,
                "SCHEME_VARIANT": scheme.variant,
                "SCHEME_COLOURS": json.dumps(scheme.colours),
                "THUMBNAIL_PATH": str(thumb),
            },
            stderr=subprocess.DEVNULL,
        )


def set_random(args: Namespace) -> None:
    wallpapers = get_wallpapers(args)

    if not wallpapers:
        raise ValueError("No valid wallpapers found")

    try:
        last_wall = wallpaper_path_path.read_text()
        wallpapers.remove(Path(last_wall))

        if not wallpapers:
            raise ValueError("Only valid wallpaper is current")
    except (FileNotFoundError, ValueError):
        pass

    set_wallpaper(random.choice(wallpapers), args.no_smart)
