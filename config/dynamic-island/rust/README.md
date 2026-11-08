# Rust-Helfer

Rust-Fassungen von Shell-Helfern, die vorher in Python liefen. Die QML-Dateien
starten das Binary aus `~/.local/bin`, wenn es dort liegt, sonst das Python-Skript.
Beide sprechen dasselbe Protokoll. `install.sh` baut und installiert die Binaries.

| Binary | Python-Fassung | Aufrufer |
|---|---|---|
| `dynamic-island-idle` | `modules/services/idle/idlehelper.py` | `Idle.qml` |
| `dynamic-island-bluetooth-agent` | `modules/services/bluetooth/agent.py` | `BluetoothService.qml` |
| `dynamic-island-looks` | `plugins/terminal/looks.py` | `plugins/terminal/Main.qml` |

`dynamic-island-rs` ist das neue Frontend von `dynamic-island`. Es macht `plugin`,
`scheme` und `wallpaper` selbst. Alles andere, jede Hilfe und jede Eingabe, die es
nicht versteht, reicht es unveraendert an `bin/dynamic-island` (Python) weiter. Es
muss neben diesem Skript liegen, und `~/.local/bin/dynamic-island` muss ein Symlink
bleiben: `Themes.qml` findet darueber die Farbschemata.

## Warum die Farbrechnung in Python bleibt

Neue Bilder rechnet weiter `bin/dynamic-island-colours` mit PIL, dem C++-Quantisierer
von materialyoucolor und dessen Farbregeln. Alles aus dem Cache laeuft ohne Python.
Gemessen am 2026-11-06 mit der Crate `material-colors` 0.5:

- Vorschaubild zu Palette: bei 0 von 80 echten Vorschaubildern gleich, im Schnitt
  gut 8 von 128 gemeinsamen Farben.
- Palette zu Farben: 3,7 % von 42.244 Farben anders, teils um den vollen Kanalwert.
  `tonalspot`, `vibrant` und `neutral` stimmen, die anderen sechs Stile nicht.

Ein Nachbau wuerde also fast jedes Wallpaper anders einfaerben.

## Zurueck zu Python

Binary loeschen und die Shell neu starten, fuer die CLI den Symlink umstellen:

```sh
rm ~/.local/bin/dynamic-island-idle ~/.local/bin/dynamic-island-bluetooth-agent ~/.local/bin/dynamic-island-looks
ln -sfn ~/.config/dynamic-island/bin/dynamic-island ~/.local/bin/dynamic-island
```

## Vergleichstests

`compare/` laesst beide Fassungen dieselben Szenarien gegen nachgebaute Dienste
(logind, BlueZ) durchlaufen und vergleicht die Protokolle. Alles laeuft in einer
`bwrap`-Sandbox ohne Zugriff auf Hyprland, Shell, echte Busse, Terminals und Netz.
Ein Lauf dauert rund anderthalb Minuten, weil die Wartezeiten echt sind.

```sh
cargo build --release
compare/run.sh            # Python gegen Rust
compare/run.sh baseline   # Python gegen sich selbst: Sind die Protokolle stabil?
compare/run.sh fallback   # die echten QML-Befehle, mit und ohne Binary im PATH
compare/run.sh plugin     # dynamic-island plugin, auch mit boesartigen Paketen
compare/run.sh looks      # Terminal-Looks, mit Zufallsdaten und deinen echten Looks
compare/run.sh colours    # scheme und wallpaper, alle Schemata, deine echten Wallpaper
```
