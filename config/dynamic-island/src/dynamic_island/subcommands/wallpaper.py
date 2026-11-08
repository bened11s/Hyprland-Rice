import json
from argparse import Namespace

from dynamic_island.utils.wallpaper import (
    apply_wall_variant,
    get_colours_for_wall,
    get_wallpaper,
    set_random,
    set_wall_variant,
    set_wallpaper,
)


class Command:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def run(self) -> None:
        # Stil je Bild: mit -f gilt er fuer das neue Bild, sonst fuer --for
        # bzw. das aktuelle. "auto" nimmt die feste Wahl wieder zurueck.
        if self.args.variant:
            variant = None if self.args.variant == "auto" else self.args.variant
            if self.args.file:
                set_wall_variant(self.args.file, variant)
            else:
                apply_wall_variant(variant, self.args.target)
                return

        if self.args.print:
            print(json.dumps(get_colours_for_wall(self.args.print, self.args.no_smart)))
        elif self.args.file:
            set_wallpaper(self.args.file, self.args.no_smart)
        elif self.args.random:
            set_random(self.args)
        else:
            print(get_wallpaper() or "No wallpaper set")
