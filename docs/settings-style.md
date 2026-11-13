# Stil des Einstellungsfensters (dynamic-island)

Stand 2026-11-10, Commits debaace → 4887139. Vorbild ist die Einstellungs-App
von Caelestia: ruhig, eine Spalte, wenige Bedienelemente. Diese Datei sammelt
die Regeln aus dem Umbau, damit weitere Seiten (Plugin-Seiten, Editoren,
Menüs der Notch) nach demselben Muster geprüft und angepasst werden können.

Code: `config/quickshell/dynamic-island/modules/settings/`.

## Was der User nicht will (Anti-KI-Look)

- Chip-/Pillen-Wolken (z. B. eine Pille je Auflösung) → Dropdown.
- Pillen mit Symbol + Text für jede Aktion → seltene Aktionen ins ⋮-Menü.
- Bedienhinweise („Ziehen ordnet an, Klick wählt“), Erklär-Fußtexte, Dateipfade als Text.
- Untertitel, die den Titel wiederholen; Überschriften, die so heißen wie die Seite.
- ALL-CAPS, letterSpacing-Deko, Zähler ohne Nutzen (Zeilenzahlen in der Leiste, „4 Plugins · 3 aktiv“).
- Dauerhaft sichtbare Leisten für Zustände, die selten sind („Keine ausstehenden Änderungen“).
- Menüs in der Notch/im Launcher, die aus den Einstellungen heraus aufgehen –
  Unterseiten gehören ins Fenster (Bibliothek `@wallpapers`, Farben `@colors`).
- Rohwerte und ASCII-Umlaute in der Anzeige („leicht“, „Staebchen“) – Optionen
  beginnen groß (SettingsRow.optionLabel) bzw. bekommen `meta.labels`.

Geblieben sind: Untertitel, die Optionen oder Verhalten erklären, Fehler,
Lösch-Rückfragen, Live-Status.

## Aufbau des Fensters

- **Leiste links** (300 px, schmal < 820 px Fensterbreite: 64-px-Symbolspalte):
  oben die Suche, darunter Kategorien in Gruppen (`SettingsCard.sidebarGroups`).
  Eintrag 54 px: Symbol in 38-px-Kreis + Titel 13 px + Unterzeile 11 px.
  Einträge einer Gruppe 2 px aneinander, Radius außen 20 / innen 6, Grund
  `alpha(fgSurface, 0.04)`, gewählt `alpha(primary, 0.18)` mit gefülltem
  primary-Kreis. 12 px zwischen Gruppen.
- **Kopf**: Zurück-Pfeil (nur Unterseiten), Seitentitel 24 px Medium, rechts ⋮
  (shell.json öffnen, Alles zurücksetzen…) und Schließen. Die Fläche zum
  Verschieben des Fensters (SettingsWindow) beginnt rechts vom Pfeil.
- **Inhalt**: eine Spalte, max. 760 px, mittig. Nur die Tastatur
  (`fullEditors`: keybinds) nimmt die volle Breite.
- **Gruppe** (GroupCard): Überschrift 13 px DemiBold `fgSurfaceVariant` *über*
  einem Container (`radius 16`, `alpha(fgSurface, 0.04)`, kein Rand), 8 px
  Abstand; 22 px zwischen Gruppen. Zeilen im Container durch 1-px-Linien
  `alpha(outline, 0.15)`, links/rechts 16 px eingerückt.
- **Zeile** (SettingsRow): 50 px, mit Untertitel 60 px. Titel 13 px, Untertitel
  11 px. Rechts genau ein Bedienelement. Geänderter Wert = kleiner primary-Punkt
  hinter dem Titel, Zurücksetzen-Symbol erscheint beim Hovern.
- **Selbstzeichnende Editoren** (`bareEditors`: system, monitors, keybinds,
  wallpaperhero) stehen ohne Container/Überschrift und bauen ihre eigenen
  Container im selben Stil.

## Bausteine

| Zweck | Baustein |
|---|---|
| Auswahl aus mehreren Werten | `SettingsDropdown { options; current; labelOf; fontOf; onPicked }` |
| Seltene Aktionen | `SettingsMenuButton { entries: [{ text, icon, current?, danger?, enabled?, action }, { separator: true }] }` |
| Aufklappliste (intern) | `SettingsMenu` – Controls-Popup in der Overlay-Ebene, nie abgeschnitten |
| An/Aus | `SettingsSwitch` 40×22 (`primary` an, `alpha(fgSurface, 0.18)` aus) |
| Zahl | Regler; Mausrad nur direkt auf dem Regler, nie auf der ganzen Zeile |
| Unterseite | Zeile oder Knopf mit `chevron_right`, Seite öffnet im Fenster |
| An/Aus mit Unterseite | meta `sub: "<seite>"` an einer Bool-Einstellung: Schalter → ›, Tap auf den Schalter schaltet, Rest der Zeile öffnet die Unterseite (`SettingsRow.hasSub`); Titel in `SettingsCard.pageTitles`, Zurück/Leiste über `subParents` |
| Textfeld | `account/AccountField` (Höhe 30, `radius 8`, `alpha(fgSurface, 0.06)`, Fokus-Rand primary); speichert über `editingFinished` (Enter/Fokusverlust), kein extra Speichern-Knopf |
| Aktion in Zeilen | Textknopf Höhe 30, `radius 8`, `alpha(fgSurface, 0.08)`; Hauptaktion `primary`/`fgPrimary` |
| Große Aktionen (Hero) | tonaler Knopf Höhe 48, `radius 24`, `alpha(primary, 0.14)` |
| Gefährlich | Eintrag `danger` im ⋮ + Rückfrage (Inline-Leiste oder Zeile „Wirklich …?“) |

Reihenfolge rechts in Listenzeilen mit mehreren Elementen (Plugins):
**Schalter → ⋮ → ›**. Fehlt ein Element, bleibt sein Platz frei, damit die
Spalten fluchten.

## Inhalt und Ordnung

- Kategorien in `SettingsCard.categories` (Schlüssel, Titel, Unterzeile, Symbol,
  Abschnitte). Neue shell.json-Abschnitte ohne Kategorie landen unter Info.
- Einzelne Einstellungen ordnet `Config.meta` (`modules/services/config/Config.qml`):
  `group` = Überschrift, `page` = andere Seite (auch virtuelle wie `region`,
  Titel in `SettingsCard.pageTitles`). Reihenfolge = Reihenfolge in meta.
  Neue Einstellung: Vorgabe im Adapter + meta-Eintrag mit `group`.
- Überschriften nutzen `partTitle()` (Abschnittstitel), nicht `sectionTitle()` –
  Kategorie-Schlüssel wie `lock`/`battery` heißen genauso wie Abschnitte.
- Notch-Einstellungen (inkl. Insel/Notch-Layout) stehen auf eigener Seite.
- Schrift: Rubik (Vorgabe wie Caelestia, `appearance.font`). Texte nehmen immer
  `Config.font`, große Ziffern/Titel der Widgets `Config.displayFont` – keine
  Schriftnamen fest im QML (Ausnahme: Material Symbols, Monospace).
- Symbole: Material Symbols Outlined. Vorher prüfen, ob es die Ligatur gibt
  (`notch` z. B. nicht). Gewählte Symbole werden gefüllt – außer die, die
  gefüllt zum Klumpen werden (monitor, keyboard).
- Texte: `I18n.tr("Deutsch")`, Eintrag in `i18n/en.js`, Prüfung `python i18n/check.py`.

## Arbeitsweise

- In einem Git-Worktree arbeiten (`git worktree add -b … ~/Projekte/…`), nicht
  live in `~/.config` – jede gespeicherte Datei lädt die Shell neu.
- Neue QML-Dateien/Ordner: nach dem Merge `dynamic-island shell -k; dynamic-island shell -d`.
- Neue Inline-`component X:` mit Zugriff auf ids der Datei scheitern in der
  laufenden Shell („X is not a type“) → eigene Datei mit `required property`.
- Screenshots ohne Desktop-Eingriff: `docs/settings-shot/shot.sh <seite> <bild.png> [b h]`
  (Grenzen stehen im Skript). Live: `qs -c dynamic-island ipc call settings page <seite>`
  + `grim -o <monitor>`, danach `… settings close`. Nicht öffnen, wenn ein
  Vollbild-Spiel läuft (das Fenster nimmt den Fokus).

## Nach diesem Stil umgebaut (2026-11-10, Branch notch-desktop-style)

- Notch: jede Anzeige schaltbar (`Config.notch.*`, Gruppen Eingeklappt/
  Aufgeklappt/Seiten), Kalender ohne Versalien, Benachrichtigungen mit
  Schalter statt Pillen, Power-Menü einfarbig in Seitenbreite.
- Desktop-Editor: Leiste = Szene-Dropdown, „Widget hinzufügen“, ⋮, Abbrechen,
  Fertig; Optionsfeld als Zeilen mit Schalter/Dropdown/Tupfern/Segment.
  Popups außerhalb des Felds sperren Widgets darunter über `menuOpen`
  (SettingsDropdown/SettingsMenuButton, `above` für Leisten unten).
- Sperrbildschirm-Editor wie der Desktop-Editor; Launcher-Suchfelder ohne
  Zähler/Hinweise; Steuerungs-Kacheln mit reserviertem Platz rechts
  (`trailing`), gemeinsames `TileMenu` für VPN/No Sleep/Energie.
- Symbole, die einen Zustand beschreiben, bleiben (Nicht-stören-Glocke,
  Aufnahme-Modus/-Ton). Kein FILL-Umschalten als Auswahl: bedtime/lock
  rendern gefüllt mit Löchern.
- Screenshots: `docs/notch-shot/shot.sh <zustand>`, `docs/desktop-shot/shot.sh`,
  `docs/lock-shot/shot.sh`.

## Konto-Seite (2026-11-13)

- `AccountEditor` (bareEditor): Kopf mit Profilbild (Klick ändert), Anzeigename
  und Login wie die Info-Seite; darunter Profil (Bild, Anzeigename) und
  Sicherheit (Passwort klappt auf). Was der Kopf zeigt, steht nicht noch
  einmal als Zeile (kein „Benutzername“).
- Notch-Seiten: Zeilen unter „Seiten“ schalten die ganze Karte, › öffnet die
  Teile (`notch-media|control|notifications|system`).

## Noch nicht nach diesem Stil geprüft

- Plugin-Seiten und Plugin-Gruppen (z. B. Terminal-Looks-Editor, Desktop-Widgets
  „Auf dem Desktop anordnen“ als Pille mit Symbol).
- Editoren: VPN, Klänge, Sperrbildschirm-Anordnung, Desktop-Szene,
  Schnelleinstellungen-Kacheleditor („Zurücksetzen“-Pille), Akkuverlauf
  (Zeitraum-Chips 24 h/3 Tage/7 Tage/Alles), Tastenkürzel-Seite.
- Stil-Chip-Reihen in Wallpaper- und Theme-Auswahl (je Symbol + Text);
  ein Dropdown braucht dort eine Masken-Region in `Bar.qml`.
- Helligkeit/Lautstärke-Regler (`LevelSlider`, `OsdSlider`): bei hohem Wert
  eine voll helle Pille.
- WLAN-/Bluetooth-Unterpanels (eigene Menüzeilen, unübersetzte Köpfe).
- Jede Editor-Datei hat eigene Kopien von Toggle/ActionButton/Chip – Kandidat
  zum Zusammenlegen. Textfelder: `Field` (VpnEditor) und `KbField` könnten
  `AccountField` nehmen.
- `StylePreview.qml` (Vorschaubilder für Uhr-/Workspace-/Visualiser-Stil) hat
  seit den Dropdowns keinen Verwender mehr.
- Transparenz (`appearance.transparency`) wirkt ohne Blur hinter den Pillen.
- Nie live geklickt: Dropdowns, ⋮-Menüs, Farben-Seite, Zurück-Pfeil.
