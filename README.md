# Hyprland-Rice — Dynamic Island

Meine Hyprland-Konfiguration mit eigener Quickshell-Oberflaeche
("dynamic-island"): Leiste mit Notch, Medien-Karte, Wallpaper- und
Theme-Auswahl, WLAN-Einstellungen — dazu die CLI `dynamic-island`
(Farbschemata, Wallpaper, Screenshots, Aufnahmen).

Der aktuelle persoenliche Shell-Stand (Notch, volle Deckkraft, fuenf
Workspaces je Monitor) liegt als `dynamic-island/shell.example.json` bei.
Bei einer neuen Einrichtung kann diese Datei als `shell.json` im selben
Ordner uebernommen werden. Die aktive `shell.json` bleibt lokal und wird
nicht durch Git-Updates ueberschrieben.

## Installieren

```sh
git clone https://github.com/Gamecat-HD/Hyprland-Rice.git
cd Hyprland-Rice
./dynamic-island/install.sh --install-deps
```

Das Skript verteilt `hypr/`, `quickshell/dynamic-island/` und
`dynamic-island/` nach `~/.config` — standardmaessig als Symlinks, damit ein
`git pull` im Klon sofort gilt. Was dort schon liegt, wandert vorher nach
`~/backups/`, nichts wird geloescht.

Dabei landen auch die mitgelieferten Wallpaper in `~/Pictures/Wallpapers`
(vorhandene Dateien bleiben unangetastet). Es sind nur die eigenen — die grosse
Sammlung, aus der der Rest des Ordners stammt, liegt unter
`github.com/krishna4a6av/Wallpapers` und laesst sich bei Bedarf daneben klonen.

Danach:

```sh
hyprctl reload            # Hyprland liest die neue Config
dynamic-island shell -d   # Shell starten
```

Wo der Klon liegt, ist egal. Wer den Klon lieber *als* `~/.config` haben will,
kann das auch — dann faellt das Verteilen weg.

## Erste Schritte nach der Installation

Die Config ist auf meinen Rechner zugeschnitten. Ein paar Stellen musst du
fast sicher anpassen. Durch die Symlinks ist `~/.config/hypr` derselbe Ordner
wie `hypr/` im Klon — egal wo du bearbeitest, es ist dieselbe Datei.
Nach jeder Aenderung: `hyprctl reload`. Tippfehler meldet Hyprland oben als
rote Leiste.

### 1. Monitore (wichtigster Punkt)

Erst nachschauen, wie deine Bildschirme heissen:

```sh
hyprctl monitors    # Namen wie HDMI-A-1, DP-1, eDP-1 + moegliche Aufloesungen
```

In `hypr/hyprland.lua` stehen oben meine drei (`HDMI-A-1` links, `DP-2`
rechts, `eDP-1` = Laptop). Trag dort deine Namen, Aufloesung, Hz-Zahl und
Position ein, ueberzaehlige Bloecke loeschen. Beispiel fuer einen Monitor:

```lua
hl.monitor({
    output   = "DP-1",            -- Name aus `hyprctl monitors`
    mode     = "1920x1080@144",   -- oder "preferred"
    position = "0x0",
    scale    = 1,
})
```

Dann in `hypr/profiles/simple.lua` bei `wsMonitorOffset` dieselben Namen
eintragen. Jeder Monitor bekommt seine eigenen Workspaces 1–10; der erste
hat Offset `0`, ein zweiter `10`. Bei nur einem Monitor:

```lua
wsMonitorOffset = {
    ["DP-1"] = 0,
},
```

### 2. Tastatur

`kbLayout = "de"` in `hypr/profiles/simple.lua` — fuer US-Tastatur `"us"`.

### 3. Programme

Ganz oben in `hypr/profiles/simple.lua` (Block `cfg`) steht, welche Apps die
Tastenkuerzel starten: `kitty` (Terminal), `zen-browser`, `codium` (Editor),
`dolphin` (Dateien), `pavucontrol` (Audio), `fuzzel` (Launcher). Was du nicht
installiert hast, entweder installieren oder durch dein Programm ersetzen —
sonst passiert beim Kuerzel einfach nichts.

## Tastenkuerzel

`SUPER` ist die Windows-Taste. Gilt fuer das Profil `simple`.

| Kuerzel | Was passiert |
| --- | --- |
| `SUPER` (allein) | App-Menue der Shell |
| `SUPER + Space` | fuzzel-Launcher |
| `SUPER + Q` | Terminal |
| `SUPER + W` | Browser |
| `SUPER + E` | Dateimanager |
| `SUPER + P` | Editor |
| `SUPER + C` | Fenster schliessen |
| `SUPER + F` / `SUPER + ALT + F` | Vollbild / maximieren |
| `SUPER + ALT + Space` | Fenster schwebend (floating) |
| `SUPER + Pfeiltasten` | Fokus wechseln |
| `SUPER + SHIFT + Pfeiltasten` | Fenster verschieben |
| `SUPER + linke Maustaste` / `rechte` | Fenster ziehen / Groesse aendern |
| `SUPER + 1…0` | Workspace 1–10 (des Monitors unter dem Fokus) |
| `SUPER + ALT + 1…0` | Fenster auf Workspace 1–10 schieben |
| `CTRL + SUPER + ←/→` | vorheriger / naechster Workspace |
| `SUPER + S` | Scratchpad-Workspace ein/aus |
| `SUPER + M` | Spotify-Workspace |
| `SUPER + D` | Discord-Workspace |
| `CTRL + SHIFT + Esc` | Systemmonitor |
| `SUPER + A` / `N` / `I` / `X` | Steuerung / Benachrichtigungen / System / Power |
| `SUPER + L` | Bildschirm sperren |
| `SUPER + V` | Zwischenablage-Verlauf |
| `SUPER + .` | Emoji-Picker |
| `Druck` / `SUPER + SHIFT + S` | Screenshot ganzer Bildschirm / Bereich |
| `SUPER + SHIFT + C` | Farbpipette |
| `CTRL + ALT + R` | Bildschirmaufnahme starten/stoppen |
| `SUPER + SHIFT + W` | zufaelliges Wallpaper |
| `CTRL + SUPER + ALT + R` | Shell (Leiste) neu starten |

Alle Kuerzel stehen unten in `hypr/profiles/simple.lua` unter `Keybinds` —
dort kannst du sie auch aendern.

## Updates holen

```sh
cd Hyprland-Rice   # dein Klon
git pull
hyprctl reload
```

Hast du selbst Dateien geaendert (z. B. die Monitore), kann `git pull`
meckern. Dann so:

```sh
git stash && git pull && git stash pop
```

Pushen geht nicht, das Repo ist fuer andere nur lesbar. Wenn du deine
Aenderungen selbst auf GitHub sichern willst: oben rechts auf **Fork**, dann
deinen Fork klonen.

## Fixes

Die Eingriffe, die nicht direkt im Rice-Stand von Gamecat-HD stecken, haben
je einen Namen. Im Repo sind sie als **Tag** gesetzt (`git tag -l` listet sie
auf), damit sich der Stand jederzeit wiederfinden laesst.

| Name | Tag | Was |
|---|---|---|
| **island-perf-bar-entfernt** | `island-perf-bar-entfernt` | Die Leistungsanzeige (FPS-Leiste) in der Dynamic Island ist komplett weg - im Code, in der Konfiguration und in den Helfer-Skripten. Sie lief auf allen vier Monitoren und liess die Shell rund um die Uhr mit 120 Frames/s neu zeichnen. Auch die Helfer `nox-game-launcher` und `nox-game-performance` sind entfernt, die Steam-/Modrinth-Wrapper starten die Spiele wieder direkt. |
| **island-gpu-last** | `island-gpu-last` | Der GPU-Ausschlag beim Oeffnen der Insel. Ursache war nicht die Animation, sondern der Visualizer: er liess alle vier Monitore mit 30 Hz Cava neu zeichnen. Jetzt laeuft er nur auf dem Monitor im Fokus, die Balken der anderen stehen still. Die Animation der Pegel laeuft ausserdem nur noch beim Wechsel zwischen Ruhebogen und Pegeln, nicht bei jeder Aktualisierung. Dazu: `hostScreen` kommt jetzt aus `bar.modelData` (vorher war es bei drei von vier Panels `null`). Messung: GPU-Last beim Oeffnen 23,1 % -> 11,3 %, Shell-Frames 120/s -> 25/s. |
| **island-start-auf-igpu** | `island-start-auf-igpu` | `dynamic-island shell` startet die Shell jetzt wie der Autostart auf der iGPU (Mesa) statt auf der NVIDIA - die dGPU bleibt fuer die Spiele frei. |

Zwei Dinge sind dabei aufgefallen, die man wissen sollte:

* **Der Sperrbildschirm blockiert die Insel.** `hypridle` sperrt nach
  Leerlauf; das hyprlock-Fenster liegt dann ueber der Insel und faengt den
  Hover ab - die Insel geht nicht mehr auf, bis man entsperrt.
* **Ein Bein mit dem Compositor:** Die Shell rendert auf der iGPU, Hyprland
  auf der NVIDIA, und Qt meldet bei jedem Commit den *vollen* Monitor als
  beschaedigt. Jeder Commit der Shell kostet damit einen Vollbild-Render des
  Monitors durch den Compositor. Deshalb ist die Zahl der Commits die
  massgebliche Groesse - nicht die Dauer einer Animation.

## Wenn was nicht geht

* **Keine Leiste / kein Wallpaper:** `hypr-profile status` zeigt, was laeuft.
  Meistens hilft `hypr-profile simple` oder `CTRL + SUPER + ALT + R`.
* **Profil-Umschalter:** `CTRL + SUPER + SHIFT + P` schaltet zwischen
  `caelestia`, `simple` und `shell2` durch. Die anderen beiden sind meine
  Bastel-Profile und brauchen Shells, die nicht im Repo sind — fuer dich ist
  nur `simple` sinnvoll. Aus Versehen gewechselt? `hypr-profile simple`.
* **Fehler in `simple.lua`:** Dann springt Hyprland automatisch auf das
  Profil `caelestia` zurueck (Fenster gehen, Leiste fehlt). Fehler beheben,
  danach `hypr-profile simple`.
* **Bildschirm teilen (Discord, OBS) geht nicht:** Hyprland startet beim
  Login `hyprland-session.target`. Die Datei fehlt bei dir noch, einmal
  anlegen:

  ```sh
  mkdir -p ~/.config/systemd/user
  cat > ~/.config/systemd/user/hyprland-session.target <<'EOF'
  [Unit]
  Description=Hyprland session
  BindsTo=graphical-session.target
  Before=graphical-session.target
  Wants=graphical-session-pre.target
  After=graphical-session-pre.target
  EOF
  systemctl --user daemon-reload
  ```

  Danach einmal ab- und wieder anmelden.
* **Was fehlt sonst?** `./dynamic-island/install.sh --check`

### Optionen

| Option | Wirkung |
| --- | --- |
| `--install-deps` | fehlende Pakete per `paru`/`yay` mitinstallieren |
| `--copy` | kopieren statt verlinken (nach `git pull` erneut ausfuehren) |
| `--check` | nur pruefen, nichts aendern |
| `--dry-run` | zeigen, was passieren wuerde |
| `-y` | ohne Rueckfrage durchlaufen |

## Voraussetzungen

Hyprland **mit Lua-Konfiguration** (getestet mit 0.56) — die Config ist
`hypr/hyprland.lua`, keine `hyprland.conf`. Dazu Quickshell (getestet mit
0.3.1), Python mit `pillow` und `materialyoucolor`, die Material-Symbols-
Schrift und die ueblichen Wayland-Werkzeuge.

Mehrere Anzeigen haengen an Systemdiensten, mit denen die Shell ueber DBus
redet: **NetworkManager** (WLAN), **bluez** (Bluetooth), **upower** (Akku) und
**power-profiles-daemon** (Energieprofile). Optional sind `cava` (Balken im
Medien-Player), `ddcutil` (Helligkeit ueber DDC/CI), `nordvpn` und `warp-cli`
(waehlbare Anbieter der VPN-Kachel) —
ohne sie faellt nur die jeweilige Einzelheit aus.

Benachrichtigungen bringt die Shell selbst mit; ein zweiter Daemon (mako, dunst,
swaync) muss aus sein, sonst belegt er den DBus-Namen.

`./dynamic-island/install.sh --check` sagt, was davon fehlt.

## Profile

`~/.config/hypr/profile` entscheidet, welches Profil Hyprland laedt:

* `simple` — diese Rice mit der dynamic-island-Shell
* `caelestia` — die volle Config mit der Caelestia-Shell (die liegt nicht in
  diesem Repo)
* `shell2` — Testprofil fuer eine neue Shell (liegt ebenfalls nicht hier)

Umschalten: `hypr-profile toggle` oder `CTRL + SUPER + SHIFT + P`.

## Hinweis

Das Installationsskript wurde mit KI erstellt und fasst dein System an
(Symlinks, Verzeichnisse, Farbschema-Dateien fuer GTK/Qt/btop/Discord).
Lies es durch, bevor du es laufen laesst.
