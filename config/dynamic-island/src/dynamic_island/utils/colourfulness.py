"""Bildanalyse fuer "smart": welcher Material-Stil und welcher Modus zu einem
Wallpaper passen.

Frueher mass das hier nur, wie bunt ein Bild insgesamt ist (Hasler-Suesstrunk
ueber jeden Pixel in reinem Python), und kannte drei Stufen: neutral, content,
tonalspot. Jetzt arbeitet es auf der quantisierten Palette (Celebi, C++-Teil
von materialyoucolor, ~7 ms fuer das 128-px-Vorschaubild) und schaut neben
der Farbigkeit auch auf die Farbtoene: wie viele getrennte Farbfamilien es
gibt, wie weit die zwei groessten auseinanderliegen und wie hell das Bild ist.

Die Grenzen sind an den eigenen Wallpapern eingestellt (2026-10-22, 68 Bilder),
nicht an einer Norm. Ein fest gewaehlter Stil je Bild (variants.json) schlaegt
das hier ohnehin.
"""

from pathlib import Path

# Bei jeder Aenderung an Merkmalen oder Grenzen hochzaehlen: smart.json traegt
# die Version, aeltere Eintraege werden dann neu berechnet.
VERSION = 2

# Unter dieser HCT-Chroma zaehlt eine Farbe als grau
CHROMATIC = 15
# Farbtonkreis in 24 Faecher a 15 Grad; ein Fach gehoert zu einer Familie, wenn
# es mindestens so viel vom bunten Anteil traegt
HUE_BINS = 24
BIN_MIN = 0.03


def _families(colours: list[tuple[float, float, float]]) -> list[tuple[float, float]]:
    """Farbfamilien als [(Anteil, Farbton)], groesste zuerst.

    colours: (Gewicht, Farbton, Chroma) je Palettenfarbe. Kraeftige Farben
    zaehlen mehr (bis 1,5x), damit ein kleiner Neon-Akzent nicht im
    Grauschleier untergeht. Benachbarte belegte Faecher bilden eine Familie.
    """
    bins = [0.0] * HUE_BINS
    width = 360 / HUE_BINS
    for weight, hue, chroma in colours:
        if chroma >= CHROMATIC:
            bins[int(hue // width) % HUE_BINS] += weight * min(chroma / 40, 1.5)

    total = sum(bins)
    if not total:
        return []
    share = [b / total for b in bins]
    on = [s >= BIN_MIN for s in share]
    if all(on):
        return [(1.0, 0.0)]

    # Bei einem leeren Fach anfangen, damit keine Familie ueber 0 Grad zerfaellt
    start = on.index(False)
    families = []
    amount = centre = 0.0
    for k in range(1, HUE_BINS + 1):
        i = (start + k) % HUE_BINS
        if on[i]:
            # Faecher hinter dem Startpunkt um 360 Grad weiterzaehlen, damit der
            # Mittelwert einer Familie um 0 Grad nicht bei 180 landet
            pos = i if i > start else i + HUE_BINS
            amount += share[i]
            centre += share[i] * pos
        elif amount:
            families.append((amount, (centre / amount * width) % 360))
            amount = centre = 0.0
    return sorted(families, reverse=True)


def _hue_distance(a: float, b: float) -> float:
    d = abs(a - b) % 360
    return min(d, 360 - d)


def classify(chroma: float, chromatic: float, tone: float, families: list[tuple[float, float]]) -> str:
    """Stil aus den Merkmalen. Reihenfolge = Vorrang."""
    big = [f for f in families if f[0] >= 0.15]
    several = [f for f in families if f[0] >= 0.08]

    # Kaum Farbe: grau bleibt grau
    if chroma < 3 and chromatic < 0.03:
        return "monochrome"
    if chroma < 7:
        return "neutral"
    # Gedaempft: die Palette soll nah am Bild bleiben statt aufzudrehen
    if chroma < 12:
        return "content"
    # Viele getrennte Farbtoene
    if len(several) >= 3:
        return "rainbow" if chroma >= 20 else "fruitsalad"
    # Zwei kraeftige Gegenpole (Neon pink/tuerkis usw.)
    if len(big) >= 2 and big[1][0] >= 0.2 and _hue_distance(big[0][1], big[1][1]) >= 75:
        return "expressive"
    # Hell und bunt: verspielt
    if tone >= 60:
        return "fruitsalad"
    if chroma >= 40:
        return "vibrant"
    # Ein Farbton beherrscht das Bild: genau den treffen
    if big and big[0][0] >= 0.85 and chroma >= 20:
        return "fidelity"
    return "tonalspot"


def analyse(thumb: Path | str) -> dict:
    """Stil, Modus und die Merkmale dahinter fuer ein Vorschaubild."""
    from materialyoucolor.hct import Hct
    from materialyoucolor.quantize import ImageQuantizeCelebi
    from materialyoucolor.utils.color_utils import argb_from_rgb

    palette = ImageQuantizeCelebi(str(thumb), 1, 128)
    total = sum(palette.values()) or 1

    colours = []
    chroma = chromatic = 0.0
    red = green = blue = 0.0
    for argb, count in palette.items():
        weight = count / total
        hct = Hct.from_int(argb)
        colours.append((weight, hct.hue, hct.chroma))
        chroma += hct.chroma * weight
        if hct.chroma >= CHROMATIC:
            chromatic += weight
        red += ((argb >> 16) & 0xFF) * weight
        green += ((argb >> 8) & 0xFF) * weight
        blue += (argb & 0xFF) * weight

    # Modus wie bisher aus der Durchschnittsfarbe (frueher: Bild auf 1x1 skaliert)
    tone = Hct.from_int(argb_from_rgb(round(red), round(green), round(blue))).tone
    families = _families(colours)

    return {
        "version": VERSION,
        "variant": classify(chroma, chromatic, tone, families),
        "mode": "light" if tone > 60 else "dark",
        "chroma": round(chroma, 1),
        "chromatic": round(chromatic, 2),
        "tone": round(tone),
        "families": [[round(share, 2), round(hue)] for share, hue in families[:4]],
    }
