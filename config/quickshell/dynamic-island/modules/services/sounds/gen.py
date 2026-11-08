#!/usr/bin/env python3
"""Erzeugt die Systemklaenge der Shell (modules/services/sounds/sounds/*.wav).

Eigene Synthese statt Klangthema, entspannt und tief: weiche "Pops" (Sinus,
der in wenigen ms nach unten rutscht – wie eine Blase) und "Thocks" wie bei
einer guten mechanischen Tastatur (gedaempfter Anschlag + tiefer
Resonanzkoerper). Alles unter ca. 3 kHz, nichts Schrilles.
Nur Standardbibliothek, 48 kHz mono 16 bit. Neu erzeugen:

    python3 -I modules/services/sounds/gen.py
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 48000
OUT = Path(__file__).resolve().parent / "sounds"


def env(i: int, n: int, attack: float, decay: float) -> float:
    """Kurzer Anstieg, exponentielles Abklingen (decay = Zeitkonstante in s)."""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    tail = min(1.0, (n - i) / (0.006 * RATE))      # Knackschutz am Ende
    return a * math.exp(-t / decay) * tail


def pop(f0: float, f1: float, dur: float = 0.12, drop: float = 0.018,
        decay: float = 0.035, attack: float = 0.0015) -> list[float]:
    """Blasen-Pop: Ton faellt in `drop` s von f0 auf f1, dazu leise Oktave."""
    n = int(dur * RATE)
    out, ph = [], 0.0
    for i in range(n):
        t = i / RATE
        f = f1 + (f0 - f1) * math.exp(-t / drop)
        ph += 2 * math.pi * f / RATE
        out.append(env(i, n, attack, decay) * (math.sin(ph) + 0.12 * math.sin(2 * ph)))
    return out


def noise(dur: float, cutoff: float, decay: float, seed: int, attack: float = 0.0005) -> list[float]:
    """Rauschstoss durch zwei Tiefpaesse (weich, ohne Zischen)."""
    rng = random.Random(seed)
    n = int(dur * RATE)
    a = math.exp(-2 * math.pi * cutoff / RATE)
    y1 = y2 = 0.0
    out = []
    for i in range(n):
        y1 = (1 - a) * rng.uniform(-1, 1) + a * y1
        y2 = (1 - a) * y1 + a * y2
        out.append(env(i, n, attack, decay) * y2 * 4)
    return out


def thock(body: float = 190.0, click: float = 2200.0, seed: int = 1, weight: float = 1.0) -> list[float]:
    """Tastenanschlag: gedaempfter Klick + Koerper (zwei Moden, leicht fallend)."""
    dur = 0.13
    n = int(dur * RATE)
    out, p1, p2 = [], 0.0, 0.0
    for i in range(n):
        t = i / RATE
        f = body * (1 + 0.25 * math.exp(-t / 0.008))
        p1 += 2 * math.pi * f / RATE
        p2 += 2 * math.pi * f * 2.3 / RATE
        b = math.exp(-t / 0.028) * math.sin(p1) + 0.35 * math.exp(-t / 0.012) * math.sin(p2)
        out.append(env(i, n, 0.001, 1.0) * b * weight)
    c = noise(dur, click, 0.006, seed)
    return [x + 0.55 * y for x, y in zip(out, c)]


def mix(*parts: tuple[float, float, list[float]]) -> list[float]:
    """(start in s, Pegel, Signal) uebereinanderlegen."""
    end = max(int(s * RATE) + len(sig) for s, _g, sig in parts)
    out = [0.0] * end
    for s, g, sig in parts:
        o = int(s * RATE)
        for i, v in enumerate(sig):
            out[o + i] += g * v
    return out


def lowpass(sig: list[float], cutoff: float) -> list[float]:
    a = math.exp(-2 * math.pi * cutoff / RATE)
    y, out = 0.0, []
    for v in sig:
        y = (1 - a) * v + a * y
        out.append(y)
    return out


def room(sig: list[float], amount: float = 0.12) -> list[float]:
    """Etwas Raum: zwei kurze, gedaempfte Reflexionen."""
    out = sig + [0.0] * int(0.06 * RATE)
    dark = lowpass(sig, 1800)
    for delay, g in ((0.017, amount), (0.031, amount * 0.6)):
        d = int(delay * RATE)
        for i, v in enumerate(dark):
            out[i + d] += g * v
    return out


def write(name: str, sig: list[float], peak: float = 0.6) -> None:
    sig = lowpass(sig, 3200)
    m = max(1e-9, max(abs(v) for v in sig))
    data = b"".join(struct.pack("<h", int(max(-1, min(1, v * peak / m)) * 32767)) for v in sig)
    OUT.mkdir(exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def main() -> None:
    # Neue Nachricht: zwei weiche Pops, der zweite eine Quarte hoeher
    write("message", room(mix(
        (0.00, 1.0, pop(620, 330, decay=0.04)),
        (0.09, 0.85, pop(820, 440, decay=0.05)),
    )), peak=0.55)

    # Screenshot: Taste runter und wieder hoch (zwei Thocks, der zweite leiser)
    write("shutter", room(mix(
        (0.00, 1.0, thock(185, 2400, seed=1)),
        (0.075, 0.55, thock(230, 2800, seed=2)),
    ), 0.1), peak=0.6)

    # Ladekabel an: Pop tief -> hoeher
    write("plug", room(mix(
        (0.00, 0.9, pop(480, 260, decay=0.04)),
        (0.08, 1.0, pop(700, 390, decay=0.055)),
    )), peak=0.5)

    # Ladekabel ab: hoeher -> tief, etwas gedaempfter
    write("unplug", room(lowpass(mix(
        (0.00, 0.9, pop(700, 390, decay=0.04)),
        (0.08, 1.0, pop(460, 230, decay=0.06)),
    ), 2200)), peak=0.45)

    # Sperren: satter, tiefer Thock mit einem Pop nach unten darunter
    write("lock", room(mix(
        (0.00, 1.0, thock(150, 1800, seed=3, weight=1.3)),
        (0.00, 0.6, pop(360, 160, dur=0.16, drop=0.03, decay=0.06)),
    ), 0.14), peak=0.6)

    # Entsperren: leichter Thock, dann ein Pop nach oben gesetzt
    write("unlock", room(mix(
        (0.00, 0.7, thock(210, 2400, seed=4)),
        (0.06, 1.0, pop(560, 420, decay=0.05)),
    )), peak=0.5)

    # Bluetooth verbunden: zwei weiche Pops nach oben, dazu ein leiser Thock
    write("connect", room(mix(
        (0.00, 0.5, thock(200, 2000, seed=5, weight=0.8)),
        (0.02, 0.9, pop(420, 300, decay=0.045)),
        (0.10, 1.0, pop(630, 470, decay=0.06)),
    )), peak=0.5)

    # Bluetooth getrennt: dieselben Pops nach unten, gedaempft
    write("disconnect", room(lowpass(mix(
        (0.00, 0.9, pop(630, 470, decay=0.04)),
        (0.10, 1.0, pop(400, 250, decay=0.06)),
    ), 2000)), peak=0.42)


if __name__ == "__main__":
    main()
