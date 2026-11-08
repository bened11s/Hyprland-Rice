#!/usr/bin/env python3
"""Wetter fuer das Desktop-Widget (Plugin `weather`), Daten von open-meteo.com.

Kein API-Key noetig. Der Ort kommt aus der IP (ipinfo.io) oder ist fest
eingestellt:

    python3 -I weather.py get [--force]     JSON auf stdout (aus dem Cache, wenn frisch)
    python3 -I weather.py ort <name>        Ort festlegen (Suche ueber open-meteo)
    python3 -I weather.py ort auto          wieder aus der IP
    python3 -I weather.py ort               zeigt den eingestellten Ort

Ausgabe von `get` (eine Zeile JSON):

    { ok, stale, error, updated (ISO), place, lat, lon,
      current: { temp, feels, humidity, wind, precip, code, day, text, icon },
      today:   { min, max, sunrise, sunset, rain (max. %), uv },
      hours:   [{ time "HH:MM", temp, code, rain, day, icon }]   naechste 24 h
      days:    [{ date "YYYY-MM-DD", weekday "Mo", code, min, max, rain, text, icon }]  7 Tage }

`icon` ist ein Material-Symbols-Name, `text` die deutsche Beschreibung.
Bei einem Netzfehler kommt der letzte Stand mit `stale: true`.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

HOME = Path.home()
CACHE = HOME / ".cache/dynamic-island/plugins/weather/weather.json"
STATE = HOME / ".local/state/dynamic-island/plugins/weather/location.json"
LOC_CACHE = HOME / ".cache/dynamic-island/plugins/weather/iplocation.json"

# Frisch genug: open-meteo rechnet viertelstuendlich neu
MAX_AGE = 15 * 60
# Die IP-Ortung aendert sich selten – einmal am Tag reicht
LOC_MAX_AGE = 24 * 3600
TIMEOUT = 10
AGENT = "dynamic-island-weather/1.0"

WEEKDAYS = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

# WMO-Wettercodes -> (Text, Symbol Tag, Symbol Nacht)
CODES: dict[int, tuple[str, str, str]] = {
    0: ("Klar", "clear_day", "clear_night"),
    1: ("Überwiegend klar", "partly_cloudy_day", "partly_cloudy_night"),
    2: ("Teils bewölkt", "partly_cloudy_day", "partly_cloudy_night"),
    3: ("Bedeckt", "cloud", "cloud"),
    45: ("Nebel", "foggy", "foggy"),
    48: ("Reifnebel", "foggy", "foggy"),
    51: ("Leichter Niesel", "rainy_light", "rainy_light"),
    53: ("Niesel", "rainy_light", "rainy_light"),
    55: ("Starker Niesel", "rainy", "rainy"),
    56: ("Gefrierender Niesel", "weather_mix", "weather_mix"),
    57: ("Gefrierender Niesel", "weather_mix", "weather_mix"),
    61: ("Leichter Regen", "rainy_light", "rainy_light"),
    63: ("Regen", "rainy", "rainy"),
    65: ("Starkregen", "rainy_heavy", "rainy_heavy"),
    66: ("Gefrierender Regen", "weather_mix", "weather_mix"),
    67: ("Gefrierender Regen", "weather_mix", "weather_mix"),
    71: ("Leichter Schnee", "weather_snowy", "weather_snowy"),
    73: ("Schnee", "weather_snowy", "weather_snowy"),
    75: ("Starker Schnee", "snowing_heavy", "snowing_heavy"),
    77: ("Schneegriesel", "weather_snowy", "weather_snowy"),
    80: ("Regenschauer", "rainy_light", "rainy_light"),
    81: ("Regenschauer", "rainy", "rainy"),
    82: ("Heftige Schauer", "rainy_heavy", "rainy_heavy"),
    85: ("Schneeschauer", "weather_snowy", "weather_snowy"),
    86: ("Schneeschauer", "snowing_heavy", "snowing_heavy"),
    95: ("Gewitter", "thunderstorm", "thunderstorm"),
    96: ("Gewitter mit Hagel", "thunderstorm", "thunderstorm"),
    99: ("Gewitter mit Hagel", "thunderstorm", "thunderstorm"),
}


def describe(code: int, day: bool = True) -> tuple[str, str]:
    text, icon_day, icon_night = CODES.get(code, ("Unbekannt", "question_mark", "question_mark"))
    return text, icon_day if day else icon_night


def fetch(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read().decode())


def read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False))
    os.replace(tmp, path)


def location() -> dict:
    """{ name, lat, lon } – fest eingestellt oder aus der IP."""
    fixed = read_json(STATE)
    if fixed and "lat" in fixed:
        return fixed
    cached = read_json(LOC_CACHE)
    if cached and time.time() - cached.get("at", 0) < LOC_MAX_AGE:
        return cached
    try:
        info = fetch("https://ipinfo.io/json")
        lat, lon = (float(x) for x in info["loc"].split(","))
        loc = {"name": info.get("city", ""), "lat": lat, "lon": lon, "at": time.time()}
    except Exception:
        if cached:
            return cached
        raise
    write_json(LOC_CACHE, loc)
    return loc


def build(raw: dict, loc: dict) -> dict:
    cur = raw["current"]
    day = bool(cur.get("is_day", 1))
    text, icon = describe(int(cur["weather_code"]), day)

    daily = raw["daily"]
    days = []
    for i, date in enumerate(daily["time"]):
        code = int(daily["weather_code"][i])
        dtext, dicon = describe(code)
        days.append(
            {
                "date": date,
                "weekday": WEEKDAYS[datetime.fromisoformat(date).weekday()],
                "code": code,
                "min": round(daily["temperature_2m_min"][i]),
                "max": round(daily["temperature_2m_max"][i]),
                "rain": daily["precipitation_probability_max"][i] or 0,
                "text": dtext,
                "icon": dicon,
            }
        )

    # Stunden ab jetzt (die API liefert ab Mitternacht)
    hourly = raw["hourly"]
    now = cur["time"][:13]
    start = next((i for i, t in enumerate(hourly["time"]) if t[:13] >= now), 0)
    hours = []
    for i in range(start, min(start + 24, len(hourly["time"]))):
        hcode = int(hourly["weather_code"][i])
        hday = bool(hourly["is_day"][i])
        hours.append(
            {
                "time": hourly["time"][i][11:16],
                "temp": round(hourly["temperature_2m"][i]),
                "code": hcode,
                "rain": hourly["precipitation_probability"][i] or 0,
                "day": hday,
                "icon": describe(hcode, hday)[1],
            }
        )

    return {
        "ok": True,
        "stale": False,
        "error": "",
        "updated": datetime.now().astimezone().isoformat(timespec="seconds"),
        "place": loc.get("name", ""),
        "lat": loc["lat"],
        "lon": loc["lon"],
        "current": {
            "temp": round(cur["temperature_2m"]),
            "feels": round(cur["apparent_temperature"]),
            "humidity": cur["relative_humidity_2m"],
            "wind": round(cur["wind_speed_10m"]),
            "precip": cur["precipitation"],
            "code": int(cur["weather_code"]),
            "day": day,
            "text": text,
            "icon": icon,
        },
        "today": {
            "min": days[0]["min"],
            "max": days[0]["max"],
            "sunrise": daily["sunrise"][0][11:16],
            "sunset": daily["sunset"][0][11:16],
            "rain": days[0]["rain"],
            "uv": daily["uv_index_max"][0],
        },
        "hours": hours,
        "days": days,
    }


def get(force: bool) -> dict:
    cached = read_json(CACHE)
    loc_key = json.dumps(read_json(STATE) or "auto")
    if (
        not force
        and cached
        and cached.get("locKey") == loc_key
        and time.time() - cached.get("at", 0) < MAX_AGE
    ):
        return cached["data"]
    try:
        loc = location()
        params = {
            "latitude": loc["lat"],
            "longitude": loc["lon"],
            "current": "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,"
            "weather_code,wind_speed_10m,precipitation",
            "hourly": "temperature_2m,weather_code,precipitation_probability,is_day",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,"
            "precipitation_probability_max,uv_index_max",
            "timezone": "auto",
            "forecast_days": 7,
        }
        raw = fetch("https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(params))
        data = build(raw, loc)
    except Exception as e:
        if cached:
            data = dict(cached["data"], stale=True, error=str(e))
            return data
        return {"ok": False, "stale": False, "error": str(e)}
    write_json(CACHE, {"at": time.time(), "locKey": loc_key, "data": data})
    return data


def set_place(name: str) -> dict:
    if name in ("", "auto"):
        STATE.unlink(missing_ok=True)
        return {"ok": True, "message": "Ort: automatisch (IP)"}
    q = urllib.parse.urlencode({"name": name, "count": 1, "language": "de", "format": "json"})
    res = fetch("https://geocoding-api.open-meteo.com/v1/search?" + q).get("results") or []
    if not res:
        return {"ok": False, "message": f'Ort "{name}" nicht gefunden'}
    r = res[0]
    loc = {"name": r["name"], "lat": r["latitude"], "lon": r["longitude"]}
    write_json(STATE, loc)
    where = ", ".join(x for x in (r.get("admin1"), r.get("country")) if x)
    return {"ok": True, "message": f"Ort: {r['name']} ({where})"}


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "get"
    if cmd == "get":
        out = get("--force" in argv)
    elif cmd == "ort":
        if len(argv) == 2:
            fixed = read_json(STATE)
            out = {"ok": True, "message": f"Ort: {fixed['name']}" if fixed else "Ort: automatisch (IP)"}
        else:
            try:
                out = set_place(" ".join(argv[2:]).strip())
            except Exception as e:
                out = {"ok": False, "message": str(e)}
    else:
        print(__doc__, file=sys.stderr)
        return 2
    print(json.dumps(out, ensure_ascii=False))
    return 0 if out.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
