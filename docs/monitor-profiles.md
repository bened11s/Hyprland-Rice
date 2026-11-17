# Bildschirm-Profile

Gespeicherte Monitor-Anordnungen („Nur Laptop", „Docked", „Präsentation", …),
die sich mit einem Klick oder Tastenkürzel wiederherstellen lassen.

## Wo sie liegen – und warum nicht im Repo

```
${XDG_STATE_HOME:-~/.local/state}/dynamic-island/monitor-profiles.json
```

Die Datei gehört **pro Benutzer und Rechner**. Anschlussnamen (`desc:…`),
Modelle, Auflösungen und Skalierung sind bei jedem anders – im gemeinsamen
Repo wären fremde Profile nur Ballast und würden beim Anwenden auf nicht
vorhandene Monitore zeigen. Deshalb ist die Ablage bewusst nicht getrackt.

Ein Profil merkt sich **alle** Monitore, die beim Speichern angeschlossen
waren (auch ausgeschaltete). Beim Anwenden kommen Monitore, die inzwischen
zusätzlich hängen, zurück auf ihre Vorgabe (bevorzugter Modus, automatische
Position).

## Bedienung

**Einstellungen → Monitore → Profile**

- `+` öffnet ein Namensfeld; Enter speichert die aktuelle Anordnung
  (Esc bricht ab).
- Klick auf einen Namen wendet das Profil an. Wie überall auf der Seite gilt
  danach die Rückfrage „Einstellungen behalten?" – 15 Sekunden Zeit, sonst
  dreht Hyprland zurück.
- Der Punkt links markiert das Profil, dessen Anschlüsse genau zur aktuellen
  Verkabelung passen. Oben steht „passt: <Name>".
- Papierkorb: erster Klick fragt nach (Symbol wird rot), zweiter löscht.

**Tastenkürzel** (Profil `simple`)

| Kürzel | Wirkung |
|---|---|
| `SUPER + ALT + M` | nächstes Profil durchschalten |
| `SUPER + ALT + SHIFT + M` | aktuelle Anordnung speichern (fragt den Namen per fuzzel) |

**Kommandozeile**

```sh
monitor-profile list          # Profile, * = passt zur Verkabelung
monitor-profile save "Docked" # aktuelle Anordnung speichern
monitor-profile apply "Docked"
monitor-profile delete "Docked"
monitor-profile match         # Name des passenden Profils (leer = keins)
monitor-profile next
```

Das Skript liegt unter `~/.config/hypr/scripts/monitor-profile`; `install.sh`
verlinkt es zusätzlich nach `~/.local/bin/monitor-profile`.

## Wie angewendet wird

Alles läuft über die Shell (`qs -c dynamic-island ipc call monitorprofiles …`)
und damit über denselben Weg wie die Seite: `hyprctl eval` mit
`hl.monitor({…})`, danach Eintrag in `~/.config/hypr/monitors.lua`
(vorher `.bak`). Ein Profil bleibt also auch nach Logout/Neustart aktiv.

`apply` von der Kommandozeile behält sofort – ohne 15-Sekunden-Frage, weil
dort niemand die Rückfrage sehen würde. Im Zweifel: `hyprctl reload` lädt
`monitors.lua` erneut, die Datei davor sichert `monitors.lua.bak`.

Läuft die Shell nicht, meldet das Skript das und tut nichts. Grund: ohne
Shell gäbe es keine Rückfrage und kein saubere Schreiben von `monitors.lua`
mit erhaltenen Workspace-Zuordnungen.
