.pragma library

// Gesetzliche Feiertage in Deutschland, je Bundesland (Kuerzel wie NW, BY).
//
//   holidays(2026, "NW")  -> { "2026-01-01": "Neujahr", ... }
//   upcoming(new Date(), "NW", 3) -> [{ date: Date, key, name, days }]   days = Tage ab heute
//   isoWeek(date)         -> Kalenderwoche nach ISO 8601
//   key(date)             -> "YYYY-MM-DD" (lokale Zeit)
//
// Mariae Himmelfahrt gilt in Bayern nur in Gemeinden mit katholischer
// Mehrheit – hier nur fuer das Saarland gefuehrt.

function pad(n) {
    return n < 10 ? "0" + n : String(n);
}

function key(d) {
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
}

// Ostersonntag (gregorianisch, Anonymer Algorithmus)
function easter(year) {
    const a = year % 19;
    const b = Math.floor(year / 100);
    const c = year % 100;
    const d = Math.floor(b / 4);
    const e = b % 4;
    const f = Math.floor((b + 8) / 25);
    const g = Math.floor((b - f + 1) / 3);
    const h = (19 * a + b - d - g + 15) % 30;
    const i = Math.floor(c / 4);
    const k = c % 4;
    const l = (32 + 2 * e + 2 * i - h - k) % 7;
    const m = Math.floor((a + 11 * h + 22 * l) / 451);
    const month = Math.floor((h + l - 7 * m + 114) / 31);
    const day = ((h + l - 7 * m + 114) % 31) + 1;
    return new Date(year, month - 1, day);
}

function plus(d, days) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + days);
}

const cache = {};

function holidays(year, state) {
    if (!state || state === "aus")
        return {};
    const ck = year + state;
    if (cache[ck])
        return cache[ck];

    const out = {};
    const add = (d, name, states) => {
        if (!states || states.indexOf(state) >= 0)
            out[key(d)] = name;
    };
    const fixed = (m, day) => new Date(year, m - 1, day);
    const e = easter(year);

    add(fixed(1, 1), "Neujahr");
    add(fixed(1, 6), "Heilige Drei Könige", ["BW", "BY", "ST"]);
    add(fixed(3, 8), "Frauentag", ["BE", "MV"]);
    add(plus(e, -2), "Karfreitag");
    add(e, "Ostersonntag", ["BB"]);
    add(plus(e, 1), "Ostermontag");
    add(fixed(5, 1), "Tag der Arbeit");
    add(plus(e, 39), "Christi Himmelfahrt");
    add(plus(e, 49), "Pfingstsonntag", ["BB"]);
    add(plus(e, 50), "Pfingstmontag");
    add(plus(e, 60), "Fronleichnam", ["BW", "BY", "HE", "NW", "RP", "SL"]);
    add(fixed(8, 15), "Mariä Himmelfahrt", ["SL"]);
    add(fixed(9, 20), "Weltkindertag", ["TH"]);
    add(fixed(10, 3), "Tag der Deutschen Einheit");
    add(fixed(10, 31), "Reformationstag", ["BB", "HB", "HH", "MV", "NI", "SH", "SN", "ST", "TH"]);
    add(fixed(11, 1), "Allerheiligen", ["BW", "BY", "NW", "RP", "SL"]);
    // Buss- und Bettag: Mittwoch vor dem 23. November
    const nov23 = fixed(11, 23);
    add(plus(nov23, -(((nov23.getDay() + 7 - 3) % 7) || 7)), "Buß- und Bettag", ["SN"]);
    add(fixed(12, 25), "1. Weihnachtstag");
    add(fixed(12, 26), "2. Weihnachtstag");

    cache[ck] = out;
    return out;
}

// Die naechsten `count` Feiertage ab `from` (heute eingeschlossen)
function upcoming(from, state, count) {
    const today = new Date(from.getFullYear(), from.getMonth(), from.getDate());
    const out = [];
    for (let y = today.getFullYear(); y <= today.getFullYear() + 1 && out.length < count; y++) {
        const map = holidays(y, state);
        const keys = Object.keys(map).sort();
        for (let i = 0; i < keys.length && out.length < count; i++) {
            const p = keys[i].split("-");
            const d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]));
            if (d >= today)
                out.push({ date: d, key: keys[i], name: map[keys[i]], days: Math.round((d - today) / 86400000) });
        }
    }
    return out;
}

function isoWeek(date) {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    const day = d.getUTCDay() || 7;
    d.setUTCDate(d.getUTCDate() + 4 - day);
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
    return Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
}
