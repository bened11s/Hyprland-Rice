import json
from argparse import Namespace

from dynamic_island.utils.scheme import (
    Scheme,
    get_scheme,
    get_scheme_flavours,
    get_scheme_modes,
    get_scheme_names,
    scheme_variants,
)
from dynamic_island.utils.theme import apply_colours
from dynamic_island.utils.wallpaper import get_wallpaper, set_wall_variant


class Set:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def run(self) -> None:
        scheme = get_scheme()

        if self.args.notify:
            scheme.notify = True

        if self.args.random:
            scheme.set_random()
            apply_colours(scheme.colours, scheme.mode)
        elif self.args.name or self.args.flavour or self.args.mode or self.args.variant:
            with scheme.batch():
                if self.args.name:
                    scheme.name = self.args.name
                if self.args.flavour:
                    scheme.flavour = self.args.flavour
                if self.args.mode:
                    scheme.mode = self.args.mode
                if self.args.variant:
                    scheme.variant = self.args.variant
            apply_colours(scheme.colours, scheme.mode)

            # Beim dynamischen Schema haengt der Stil am Wallpaper: merken,
            # damit er beim naechsten Wechsel auf dieses Bild wiederkommt
            if self.args.variant and scheme.name == "dynamic" and (wall := get_wallpaper()):
                set_wall_variant(wall, self.args.variant)
        else:
            print("No args given. Use --name, --flavour, --mode, --variant or --random to set a scheme")


class Get:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def run(self) -> None:
        scheme = get_scheme()

        if self.args.name or self.args.flavour or self.args.mode or self.args.variant:
            if self.args.name:
                print(scheme.name)
            if self.args.flavour:
                print(scheme.flavour)
            if self.args.mode:
                print(scheme.mode)
            if self.args.variant:
                print(scheme.variant)
        else:
            print(scheme)


class List:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def run(self) -> None:
        multiple = [self.args.names, self.args.flavours, self.args.modes, self.args.variants].count(True) > 1

        if self.args.names or self.args.flavours or self.args.modes or self.args.variants:
            if self.args.names:
                if multiple:
                    print("Names:", *get_scheme_names())
                else:
                    print("\n".join(get_scheme_names()))
            if self.args.flavours:
                if multiple:
                    print("Flavours:", *get_scheme_flavours())
                else:
                    print("\n".join(get_scheme_flavours()))
            if self.args.modes:
                if multiple:
                    print("Modes:", *get_scheme_modes())
                else:
                    print("\n".join(get_scheme_modes()))
            if self.args.variants:
                if multiple:
                    print("Variants:", *scheme_variants)
                else:
                    print("\n".join(scheme_variants))
        else:
            current_scheme = get_scheme()
            schemes = {}
            for scheme in get_scheme_names():
                schemes[scheme] = {}
                for flavour in get_scheme_flavours(scheme):
                    s = Scheme(
                        {
                            "name": scheme,
                            "flavour": flavour,
                            "mode": current_scheme.mode,
                            "variant": current_scheme.variant,
                            "colours": current_scheme.colours,
                        }
                    )
                    modes = get_scheme_modes(scheme, flavour)
                    # Ein Schema ohne lesbare Modus-Datei (z.B. haengender
                    # Symlink nach einem frischen Klon) hat die ganze Liste
                    # abstuerzen lassen - lieber ueberspringen.
                    if not modes:
                        continue
                    if s.mode not in modes:
                        s._mode = modes[0]
                    try:
                        s._update_colours()
                        schemes[scheme][flavour] = s.colours
                    except ValueError:
                        pass

            print(json.dumps(schemes))
