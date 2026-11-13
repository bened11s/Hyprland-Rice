# Einrichtung fuer Benedikt

Quelle: https://github.com/Gamecat-HD/Hyprland-Rice.git
Stand: 78d5afb9541cbf72a8f586d37b72d0e117eb7071

- Verlinkt nach ~/.config; vorheriger Stand unter ~/backups/hyprland-rice-20261018-112908.
- Lua-Konfiguration beim naechsten Hyprland-Login; laufende hyprlang-Sitzung nutzt die kompatible hyprland.conf und legacy-rice.conf.
- eDP-1: Full HD, 60 Hz; HDMI-A-1: hoechste Aufloesung, rechts, Skalierung 1.
- Deutsche Tastatur; Kitty, Firefox, Kate, Dolphin.
- Profilumschalter auf simple begrenzt: andere Shells sind nicht mitgeliefert.
- Auf ausdruecklichen Wunsch jetzt globaler Theme-Abgleich fuer GTK 3/4, KDE/Qt und Kitty. Kein automatisches Discord-/Browser-Policy-Umschreiben, keine Papierkorb-Loeschung, kein suspend-then-hibernate.
- Python-Abhaengigkeit materialyoucolor im isolierten ~/.local/share/dynamic-island/venv (mit System-Pillow).
- Wallpaper aus der bisherigen Einrichtung; das Quellrepo enthaelt derzeit keine Bilddateien.
- KDE-Polkit-Agent bleibt als bewaehrter Passwortdialog erhalten. Die Shell kann deshalb eine harmlose Warnung ueber ihren zweiten Polkit-Agenten ausgeben.
- HDMI-Ruckler: cursor.no_hardware_cursors dauerhaft in simple.lua und legacy-rice.conf aktiviert. Vorher tausende Cursor-Blit-/Framebufferfehler, seit Test keine neuen; AMD bleibt primaer, NVIDIA bleibt HDMI-Ausgabe.
- Wallpaper-Auswahl nutzt ~/Pictures/Wallpapers (aktuell Tokyo-Night.jpg und wallhaven-856dlk_1920x1080.png); Wallhaven ist gesetzt.
- Shell auf beiden Monitoren mit echter Tastatureingabe und Screenshots getestet: Kitty-Suche, Wallpaper-Suche/Anwenden beider Bilder, Themes, Steuerung, Benachrichtigungen, System, Medien, Einstellungen. Icon-Fallback in ResultItem.qml fuer Quickshell 0.3.2 korrigiert. Aktueller Test ohne Clipboard-Timeouts, Delegate-/JS-/Icon-Ladefehler; Qt-Textinput-Fokuswarnungen bleiben vorhanden.
- Testdaten: /tmp/opencode/rice-shell-both/summary.json und Screenshots; Backup vor Fix ~/backups/rice-shell-fix-20261018-114825.

## Bedienung

Super allein: App-Menue; Super+Leertaste: Fuzzel.
Super+Q oder Super+Enter: Kitty; Super+W: Firefox; Super+E: Dolphin; Super+P: Kate.
Super+A: Steuerung; Super+N: Benachrichtigungen; Super+I: System; Super+X: Power-Menue.
Super+L: sperren; Super+V: Zwischenablage; Super+Shift+S: Bereichsfoto.

## UI-/Workspace-/Theme-Fix 18.10.

- App-Icons im Launcher auf 26x26 begrenzt. Fehlende App-Icons verwenden das Material-Symbol `apps`, niemals einen Desktop-Iconnamen als Ligatur. Zeilen clippen ihre Inhalte.
- Zehn lokale Workspaces je Bildschirm: eDP 1–10, HDMI 11–20. Beide Leisten verwenden feste Monitor-Offsets, nicht wechselnde Fuenfergruppen. Klick auf den bereits aktiven Workspace bleibt dort; Scratchpad weiter per Super+S.
- Super+1…0 waehlt den lokalen Workspace; Super+Shift+1…0 oder Super+Alt+1…0 verschiebt das Fenster ohne Fokuswechsel. Aktuelle hyprlang-Sitzung verwendet workspace.py + legacy-workspaces.conf, Lua dieselbe Zuordnung.
- Shell-Flaechen: 90 Prozent Deckkraft, ueber Einstellungen anpassbar. Normale Fenster 96/90 Prozent (aktiv/inaktiv); Kitty-Hintergrund 88 Prozent.
- SystemStats liest ausschliesslich echte GTX-1650-Werte ueber nvidia-stats.py/nvidia-smi (nur bei sichtbarer Statistik, mit Timeout). 4 GB VRAM bestaetigt. Das aendert **nicht** die primaere AMD-Render-GPU.
- Theme-Synchronisierung: cli.json enableGtk/enableQt + scripts/sync-desktop-theme.py. Beide GTK-settings.ini, GSettings, KDE-Farbschema DynamicIsland und Kitty-Palette werden angepasst; alte GTK-/Qt-Defaults sind damit absichtlich ueberholt. Andere Apps koennen weiterhin eigene Themes erzwingen.
- Kitty inkludiert ~/.local/state/dynamic-island/theme/kitty.conf; laufende Kitty-Fenster laden nach Themewechsel per SIGUSR1 neu. Hyprland-Palette wird fuer beide Parser erzeugt und fuer Legacy-Borders eingebunden.
- Hell/Dunkel-Rundlauf getestet; abschliessend dunkel. Echte Launcher-Suche und GTX-Ansicht auf beiden Monitoren per Screenshot geprueft; Workspace-Helfer fuer 1/2/10 und 11/12/20 getestet (kein bestandener physischer Tastentest behauptet).
- Tests/Screenshots: /tmp/opencode/rice-ui-fix-test. Vollbackup vor diesen Aenderungen: ~/backups/rice-ui-theme-20261018-115814 (repo, globale betroffene Dateien, global-files.json und gnome-interface.dconf). Der urspruengliche restore.py-Rueckweg deckt diese spaeteren globalen Theme-Aenderungen **nicht** ab.

Pruefen: `hypr-profile status`, `hyprctl configerrors`, `qs -c dynamic-island log`.
Shell neu starten: `hypr-profile shell-restart`.

## Updates

Lokale Anpassungen sind absichtlich nicht committed. Vor Updates `git diff` lesen.
Nicht blind das Upstream-Installationsskript ausfuehren: es aktiviert globale Theme-Aenderungen.

## Rueckkehr

`python ~/Hyprland-Rice/restore.py` stellt die gesicherten Konfigurationen wieder her,
ohne die neue Einrichtung zu loeschen. Danach abmelden und Hyprland erneut waehlen.
Offene Arbeiten vorher speichern. Nachtraegliche Aenderungen an wiederhergestellten
Konfigurationen werden vorher ebenfalls gesichert.
