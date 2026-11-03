class Colour:
    _rgb_vals: tuple[int, ...]
    _hex_vals: tuple[str, ...]

    def __init__(self, hex: str):
        hex = hex.ljust(8, "f")
        self._hex_vals = tuple(hex[i : i + 2] for i in range(0, 7, 2))
        self._rgb_vals = tuple(int(h, 16) for h in self._hex_vals)

    @property
    def hex(self) -> str:
        return "".join(self._hex_vals[:-1])

    @property
    def hexalpha(self) -> str:
        return "".join(self._hex_vals)

    @property
    def rgb(self) -> str:
        return f"rgb({','.join(map(str, self._rgb_vals[:-1]))})"

    @property
    def rgbalpha(self) -> str:
        return f"rgba({','.join(map(str, self._rgb_vals))})"

    @property
    def ansi(self) -> str:
        # "r;g;b" fuer Truecolor-Sequenzen (38;2;{{ x.ansi }}), z. B. fastfetch
        return ";".join(map(str, self._rgb_vals[:-1]))


def get_dynamic_colours(colours: dict[str, str]) -> dict[str, Colour]:
    return {name: Colour(code) for name, code in colours.items()}
