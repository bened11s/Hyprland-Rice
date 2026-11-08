.pragma library
// ASCII-Bonsai nach cbonsai (https://gitlab.com/jallbrit/cbonsai, GPL-3) –
// derselbe Algorithmus in JS: rekursive Aeste mit Lebensdauer, je Typ eigene
// Zufallsschritte und Zeichen. Ergebnis ist keine fertige Grafik, sondern die
// Liste der Zeichen-Operationen in Wachstumsreihenfolge – das Widget kann sie
// so nacheinander aufdecken (Wachsen) oder alle auf einmal setzen.
//
//   grow({ cols, rows, life, multiplier, leaves, pot, seed })
//   -> { ops: [{ x, y, s, k }], cols, rows, potRows }
// k = Farbklasse: "wood", "woodDark", "leaf", "leafDark", "pot", "potDark"

const TRUNK = 0, SHOOT_LEFT = 1, SHOOT_RIGHT = 2, DYING = 3, DEAD = 4;

// Kleiner deterministischer Zufall (mulberry32), damit ein Seed denselben
// Baum ergibt (z.B. ueber Neustarts hinweg derselbe Tagesbaum)
function rng(seed) {
    let a = seed >>> 0;
    return function () {
        a = (a + 0x6D2B79F5) >>> 0;
        let t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

const POTS = {
    schale: [
        ":___________./~~~\\.___________:",
        " \\                           / ",
        "  \\_________________________/  ",
        "  (_)                     (_)  "
    ],
    klein: [
        "(---./~~~\\.---)",
        " (           ) ",
        "  (_________)  "
    ],
    ohne: []
};

function grow(cfg) {
    const R = rng(cfg.seed ?? Date.now());
    const rand = n => Math.floor(R() * n);
    const cols = cfg.cols, rows = cfg.rows;
    const multiplier = cfg.multiplier ?? 5;
    const lifeStart = cfg.life ?? 32;
    const leaves = cfg.leaves ?? "&";
    const pot = POTS[cfg.pot] ?? POTS.schale;
    const ops = [];

    // Topf unten mittig
    const potTop = rows - pot.length;
    const potLeft = Math.floor((cols - (pot[0]?.length ?? 0)) / 2);
    for (let i = 0; i < pot.length; i++) {
        const line = pot[i];
        for (let j = 0; j < line.length; j++) {
            const ch = line[j];
            if (ch === " ")
                continue;
            // Die Erde (~) in der Oeffnung dunkler als der Rand
            const k = ch === "~" || ch === "." ? "woodDark" : (i === 0 ? "pot" : "potDark");
            ops.push({ x: potLeft + j, y: potTop + i, s: ch, k: k, base: true });
        }
    }

    const maxY = (pot.length ? potTop : rows) - 1;
    let shootCounter = rand(2);

    function deltas(type, life, age) {
        let dx = 0, dy = 0, dice;
        switch (type) {
        case TRUNK:
            if (age <= 2 || life < 4) {
                dy = 0;
                dx = rand(3) - 1;
            } else if (age < multiplier * 3) {
                dy = age % Math.max(1, Math.floor(multiplier * 0.5)) === 0 ? -1 : 0;
                dice = rand(6);
                dx = [-2, -1, -1, 0, 1, 1][dice] ?? 2;
            } else {
                dy = rand(10) > 2 ? -1 : 0;
                dx = rand(3) - 1;
            }
            break;
        case SHOOT_LEFT:
        case SHOOT_RIGHT:
            dice = rand(10);
            dy = dice <= 1 ? -1 : dice <= 7 ? 0 : 1;
            dice = rand(10);
            dx = dice <= 1 ? -2 : dice <= 5 ? -1 : dice <= 8 ? 0 : 1;
            if (type === SHOOT_RIGHT)
                dx = -dx;
            break;
        case DYING:
            dice = rand(10);
            dy = dice <= 1 ? -1 : dice <= 8 ? 0 : 1;
            dx = [-3, -2, -2, -1, -1, -1, 0, 0, 0, 1, 1, 1, 2, 2, 3][rand(15)];
            break;
        case DEAD:
            dice = rand(10);
            dy = dice <= 2 ? -1 : dice <= 6 ? 0 : 1;
            dx = rand(3) - 1;
            break;
        }
        return [dx, dy];
    }

    function chars(type, life, dx, dy) {
        if (life < 4 || type === DYING || type === DEAD)
            return leaves;
        switch (type) {
        case TRUNK:
            if (dy === 0) return "/~";
            if (dx < 0) return "\\|";
            if (dx === 0) return "/|\\";
            return "|/";
        case SHOOT_LEFT:
            if (dy > 0) return "\\";
            if (dy === 0) return "\\_";
            if (dx < 0) return "\\|";
            if (dx === 0) return "/|\\";
            return "/";
        case SHOOT_RIGHT:
            if (dy > 0) return "/";
            if (dy === 0) return "_/";
            if (dx < 0) return "\\|";
            if (dx === 0) return "/|\\";
            return "/";
        }
        return "?";
    }

    function colour(type) {
        if (type === TRUNK || type === SHOOT_LEFT || type === SHOOT_RIGHT)
            return rand(2) ? "wood" : "woodDark";
        if (type === DYING)
            return rand(10) ? "leafDark" : "leaf";
        return rand(3) ? "leafDark" : "leaf";
    }

    let shootCooldown = multiplier;
    let budget = 6000; // Notbremse

    function branch(y, x, type, life) {
        while (life > 0 && budget-- > 0) {
            life--;
            const age = lifeStart - life;
            let [dx, dy] = deltas(type, life, age);
            if (dy > 0 && y > maxY - 2)
                dy--;

            if (life < 3) {
                branch(y, x, DEAD, life);
            } else if (type === TRUNK && life < multiplier + 2) {
                branch(y, x, DYING, life);
            } else if ((type === SHOOT_LEFT || type === SHOOT_RIGHT) && life < multiplier + 2) {
                branch(y, x, DYING, life);
            } else if (type === TRUNK && (rand(3) === 0 || life % multiplier === 0)) {
                if (rand(8) === 0 && life > 7) {
                    shootCooldown = multiplier * 2;
                    branch(y, x, TRUNK, life + rand(5) - 2);
                } else if (shootCooldown <= 0) {
                    shootCooldown = multiplier * 2;
                    shootCounter++;
                    branch(y, x, shootCounter % 2 ? SHOOT_LEFT : SHOOT_RIGHT, life + multiplier);
                }
            }
            shootCooldown--;

            x += dx;
            y += dy;
            const s = chars(type, life, dx, dy);
            const k = colour(type);
            if (y >= 0 && y <= maxY && x >= 0 && x + s.length <= cols)
                ops.push({ x: x, y: y, s: s, k: k });
        }
    }

    branch(maxY, Math.floor(cols / 2), TRUNK, lifeStart);
    return { ops: ops, cols: cols, rows: rows, potRows: pot.length };
}
