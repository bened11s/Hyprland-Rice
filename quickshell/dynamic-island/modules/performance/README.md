# Spiel-Performance

**Schnelleinstellungen → Spiel-Performance:** gesamte Leiste ein/aus.
Der Regler-Knopf rechts öffnet **Einstellungen → Spiel-Performance**.
Alle Optionen werden in `~/.config/dynamic-island/shell.json` gespeichert.
Standard: aus, nur Spiele, FPS/Frametime/CPU/GPU/Titel/Messstatus.
Die Messwerte stehen **direkt in der Dynamic Island, links neben der Uhr**:
Musikcover → Performance → Uhr → KI-Symbol. Es gibt kein separates Overlay-Fenster.
Die Island wächst in die Breite; bei vielen Werten scrollt die Performance-Zeile
horizontal, statt unter die Uhr umzubrechen. Beim Öffnen der Menüs macht
die Live-Zeile dem normalen Menü Platz und kehrt beim Schließen zurück.
Position, Hintergrund und Rundung kommen von der Island; einstellbar sind
Messwerte, Schriftgröße, Breite, Kompaktheit und Sichtbarkeit über Vollbild.

## Automatisch: Steam und Minecraft/Modrinth

**Keine Startoptionen pro Spiel nötig.** Steam und Modrinth vollständig beenden
und danach wie gewohnt über das App-Menü oder `steam` / `ModrinthApp` öffnen.
Auch Super+G nutzt denselben Steam-Startweg. Bereits laufende Launcher oder
Spiele werden nicht beendet und lassen sich nicht nachträglich instrumentieren.

- `~/.local/bin/steam` → bestehender `steam-clean` (dessen NVIDIA-Bereinigung
  bleibt erhalten) → `nox-game-launcher /usr/bin/steam`.
- Die lokale Modrinth-Desktopdatei und `~/.local/bin/ModrinthApp` verwenden
  `nox-game-launcher /usr/bin/ModrinthApp`. Die Spielprozesse erben MangoHud,
  somit auch Minecrafts Java/LWJGL/OpenGL-Renderer.
- Launcher und ihre Weboberflächen gelten nicht als Spiele. Andere geerbte
  Hilfsprozesse ohne eigene Render-Messdaten werden ebenfalls nicht angezeigt.
- Nur diese Launcher und ihre Kinder werden instrumentiert, nicht die gesamte
  Desktop-Sitzung. Kein globales LD_PRELOAD, keine Änderung der Modrinth-Datenbank
  und keine Änderung einzelner Minecraft-Instanzen/Steam-Startoptionen.
- Ein direkter Aufruf von `/usr/bin/steam` oder `/usr/bin/ModrinthApp` umgeht die
  Anbindung; der Start über die eingerichteten Menüs/Kürzel ist der normale Weg.
- Notausstieg vor einem **frischen** Launcherstart:
  `NOX_PERF_DISABLE=1 steam` bzw. `NOX_PERF_DISABLE=1 ModrinthApp`.
  Bereits geladene MangoHud-Layer verschwinden erst beim Beenden der Prozesse.
- Bestehende Single-Instance-Launcher werden nur normal angesprochen; ihre
  Umgebung wird nicht verändert. Nach Entfernen des MangoHud-Pakets starten
  die Launcher weiter, dann ohne Telemetrie.

Ein Java/LWJGL-Test mit den vorhandenen Modrinth-Bibliotheken bestätigt echte
OpenGL-FPS über die geerbte Launcher-Umgebung. Ein vollständiger Minecraft- und
Steam/Proton-Spielstart nach Launcher-Neustart ist noch vom Nutzer zu testen.

## Andere Startwege (optional)

Für andere Launcher oder direkt gestartete Spiele bleibt der manuelle Wrapper
verfügbar. Eine alte Steam-Startoption kann entfernt werden, ist aber nicht
schädlich und wird nicht automatisch überschrieben:

```sh
nox-game-performance %command%
```

Vorhandene Umgebungsvariablen **beibehalten**, z. B.:

```sh
__NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only nox-game-performance %command% -javaagent:ZombieBuddy.jar --
```

Außerhalb von Steam: `nox-game-performance /pfad/zum/spiel [Argumente]` oder
`nox-game-launcher /pfad/zum/launcher [Argumente]` für dessen künftige Kinder.
Danach das Spiel neu starten. Es werden keine globalen MangoHud-Einstellungen geändert.
Nicht bei Spielen einsetzen, deren Anti-Cheat/Hersteller MangoHud verbietet.
Flatpak/Container benötigen einen dort erreichbaren Wrapper und MangoHud-Layer;
Sandbox-Integration ist nicht automatisch eingerichtet. 32-Bit-Spiele brauchen
zusätzlich den passenden 32-Bit-MangoHud-Layer.

## Messung und Grenzen

- MangoHud misst das instrumentierte Spiel, nicht Hyprlands Render-FPS oder Monitor-Hz.
- CSV-Quelle wird über **offene Dateideskriptoren des fokussierten Prozesses**
  zugeordnet, niemals anhand des neuesten Dateinamens. Bei mehreren Renderern
  erscheint ein Hinweis statt FPS des falschen Spiels. Bei Gamescope werden
  bis zu 64 untergeordnete Prozesse derselben Sitzung untersucht.
- Native/OpenGL- und Vulkan-Spiele sowie kompatible Proton-Spiele über MangoHud.
  Nicht unterstützte APIs, Sandboxen oder geschützte Prozesse liefern keine FPS.
- Die geloggten FPS/Frametimes sind Momentaufnahmen, kein 1%-Low/Benchmark.
  Beim Pausieren können MangoHud-Logger weiterhin den zuletzt gemessenen Frame
  wiederholen. Aus einem weitergeschriebenen Log ist kein Render-Stillstand ableitbar.
- CPU/RAM beziehen sich auf das **gesamte System**, GPU/VRAM auf die gemessene GPU.
  Ohne Spieltelemetrie werden CPU/GPU/RAM aus dem vorhandenen Systemdienst ergänzt
  (2-s-Takt; GPU dort in dieser Installation bevorzugt NVIDIA).
- Nicht verfügbare Werte erscheinen als `—`, keine erfundenen FPS.
- Telemetrie: 2 Stichproben/s, im benutzereigenen RAM-Laufzeitverzeichnis
  `$XDG_RUNTIME_DIR/dynamic-island-performance/game-*` (0700).
  Kleine CSVs wachsen während des Spiels; sie verschwinden mit Abmeldung/Neustart.
  MangoHud hält während des Loggens zusätzlich seine Benchmark-Stichproben im RAM.
  Keine Netzwerkaufrufe/Uploads und keine permanenten Benchmark-Dateien.
- Abschalten stoppt Quickshell-Abfragen und blendet die Leiste aus. Der im Spiel
  geladene MangoHud-Layer loggt bis Spielende weiter. Um auch das abzustellen,
  Launcher mit `NOX_PERF_DISABLE=1` neu starten bzw. den manuellen Wrapper entfernen.
- Die Performance-Zeile folgt dem Fokusmonitor innerhalb der vorhandenen Island.
  Die Island behält Hover/Gesten/Menüs und reserviert keinen zusätzlichen Platz.
  Bei „Über Vollbild zeigen“ wird nur die betreffende Bar auf die Overlay-Layer
  angehoben; nach Ausblenden wird sie wieder zur normalen Top-Layer.

Tests: `python3 -m unittest discover -s ~/.config/quickshell/dynamic-island/modules/performance -p 'test_*.py'`.
Layouttest: `qs -p ~/.config/quickshell/dynamic-island/performance-test.qml`.
