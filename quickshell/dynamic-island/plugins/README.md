# Plugins

A plugin is a folder `plugins/<id>/` next to `shell.qml`. The shell picks up
new folders on its own (no restart); folders starting with `_` or `.` are
skipped (`_example/` is the template for `dynamic-island plugin new`).

```
plugins/
  terminal/
    plugin.json     manifest (required)
    Main.qml        service, runs while the plugin is enabled (optional)
    Tile.qml        quick settings tile (optional, any number)
    Section.qml     section in one of the shell's views (optional, one per view)
```

Core: `modules/services/plugins/Plugins.qml` (singleton) + `PluginHost.qml`
(one per plugin). Per-machine state: `~/.config/dynamic-island/plugins.json`
(not in Git, like `shell.json`).

## Manifest `plugin.json`

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | `a-z 0-9 -`, max. 48 characters, **same as the folder name** |
| `name` | yes | display name |
| `api` | yes | plugin API the plugin needs (currently `1`; higher ones are not loaded) |
| `version` | – | semver-like, compared on import |
| `description`, `author`, `homepage` | – | text for the plugin manager |
| `icon` | – | Material Symbols name (default `extension`) |
| `defaultEnabled` | – | on, unless `plugins.json` says otherwise. Imported plugins still start out **off**. |
| `main` | – | QML file of the service (relative) |
| `settings` | – | settings, see below |
| `tiles` | – | quick settings tiles, see below |
| `panels` | – | sections in the shell's views (so far: wallpaper picker), see below |
| `pages` | – | own pages in the settings window, see below |
| `widgets` | – | desktop widgets (types for the per-wallpaper scenes), see below |
| `keybinds` | – | Hyprland keybinds while the plugin is enabled, see below |
| `files` | – | files outside the plugin folder that belong to it (for export/import) |
| `migrateFrom` | – | group in `shell.json` whose values are taken over once (`enabled: false` there = plugin stays off) |
| `parent` | – | component of another plugin, see below |
| `components` | – | submenu for its own components: `{ "title", "icon", "desc" }` |
| `builtin` | – | part of the shell: only on/off in the manager, `plugin remove` only with `--force` |

Schema for editors: `plugins/plugin.schema.json` (`"$schema": "../plugin.schema.json"`).

### `settings`

Same fields as `Config.meta`, plus `default` (required – the type of the
default decides the control):

```json
"settings": {
    "theme":   { "default": true, "title": "Follow theme", "desc": "…" },
    "style":   { "default": "short", "options": ["short", "long"], "title": "Style" },
    "size":    { "default": 12, "min": 8, "max": 32, "step": 1, "unit": " px", "title": "Size" },
    "looks":   { "default": true, "title": "…", "requires": "theme" }
}
```

`editor` (`"quick"`, `"desktop"`) puts a built-in editor into the row instead
of the control (that's how `desktop` shows its scenes block).

`requires` without a dot refers to a setting of the same plugin, with a dot to
a shell setting (`"bar.battery"`) or another plugin (`"plugin:<id>.<key>"`);
as an object `{ "theme": true }` for a specific value.

In the menu, every enabled plugin with settings shows up as its own group
`plugin:<id>` under "Plugins".

### `tiles`

```json
"tiles": {
    "status": { "label": "Status", "icon": "bolt", "kind": "pill", "component": "Tile.qml" }
}
```

`kind`: `pill` (2 columns), `circle` (1), `wide` (full width). In the grid the
tile is called `<plugin>.<tile>` and, once the plugin is enabled, shows up in
the tile editor under "Hidden". Component contract: see "Tiles" below.

### `panels`

```json
"panels": {
    "wallpaper": { "component": "Section.qml", "icon": "travel_explore" }
}
```

Adds a section to one of the shell's views, at most one per view per plugin.
The only view so far: `wallpaper`, the notch's wallpaper picker (expands below
the local row and the style row). `icon` (default: plugin icon) becomes a
button in its search bar. If the plugin has a service (`main`), the section
only appears once it is running. Component contract: "Sections" below.

### `pages`

```json
"pages": {
    "looks": { "title": "Looks bearbeiten", "icon": "palette", "component": "LooksPage.qml" }
}
```

A page of its own in the settings window: it shows up as a row with an arrow
in the plugin's settings group (a plugin without settings gets it as a
sidebar entry instead) and takes the whole area instead of the row cards;
the group stays highlighted and the header gets a back arrow. `title` goes
through `I18n.tr`, `icon` defaults to the plugin icon. If the plugin has a
service (`main`), the page only appears once it is running (the terminal
plugin's editor talks to looks.py through `plugin.main`). While the search
field is in use the window shows the search results instead; the page comes
back when the search is cleared.

The component is loaded through `plugin.url(component)` (so a `plugins
reload` rebuilds it) and receives:

| Property | Meaning |
|---|---|
| `plugin` | plugin context, as for tiles (`required property var plugin`) |
| `args` | object from `SettingsState.openPage` (`{}` when opened from the sidebar); set again on every jump, also while the page is open – react in `onArgsChanged` |

Jumping there from anywhere in the shell:

```qml
SettingsState.openPage(Plugins.pageSection("terminal/looks"), { look: "miku" })
```

opens the window on the focused screen and selects the page (`"@plugins"`,
`"@wallpapers"` and plain groups like `"bar"` work too). From the command
line: `qs -c dynamic-island ipc call settings page "@page:terminal/looks"`.
Reference: `plugins/terminal/LooksPage.qml`.

### `widgets`

Desktop widgets that can be placed in the scenes
(`~/.config/dynamic-island/scenes.json`, see
`modules/services/desktop/Scenes.qml`). They only appear while the `desktop`
plugin is enabled – so build a widget pack as a component
(`"parent": "desktop"`, see below). Per type:

```json
"widgets": {
    "matrix": {
        "title": "Matrix",
        "desc": "Falling characters as a GPU shader",
        "icon": "code",
        "component": "MatrixWidget.qml",
        "size": [30, 20],
        "options": {
            "speed": { "title": "Speed", "values": ["slow", "medium", "fast"], "default": "medium" },
            "trails": { "title": "Trails", "bool": true, "default": true }
        }
    }
}
```

`desc` = one line for the widget picker ("Widget" bar or right-click while
editing). `size` = rough size in base units (16 px at 1440p) for automatic
placement; `options` show up as chips in the edit bar (`values` = choice,
`bool` = switch) and end up in `opts`. Every widget gets color and accent
automatically.

The component receives from the host (`modules/desktop/WidgetHost.qml`):

| Property | Meaning |
|---|---|
| `unit` | base unit in px (16 · monitor height/1440 · widget size) |
| `active` | `false` = desktop covered (windows, fullscreen, game mode): compute nothing, animate nothing |
| `editing` | edit mode is running |
| `opts` | options from the scene, defaults already filled in |
| `color`, `accent` | text color and accent |
| `fps` | (declare optionally) cap for your own animations, setting `fps` of the `desktop` plugin |
| `plugin` | (declare optionally) plugin context, like for tiles |

The widget sets its own size via `implicitWidth`/`implicitHeight`. Rules:
continuous motion only via a `Timer` driven by `fps` (an `Animation` would run
at the monitor's refresh rate), stop everything when `active: false`, demand
services (`Cava.demand`, `Lyrics.demand`) only while `active`. `opts` arrives
as a new object on every change to the widget (moving it, too) – only do
expensive recomputation when the content actually changed. Examples:
`desktop/widgets/`, `matrix/`, `bonsai/`, `tui/`.

### `keybinds`

```json
"keybinds": {
    "open":    { "keys": "SUPER + ALT + W", "title": "Wallhaven search", "group": "Werkzeuge", "ipc": "open" },
    "arrange": { "keys": "SUPER + ALT + D", "title": "Arrange desktop widgets", "exec": "qs -c dynamic-island ipc call desktop toggle" }
}
```

The shell binds them as soon as the plugin is enabled and removes them again
when it is disabled – in Hyprland and in the overview (SUPER+K). The action is
exactly one of `ipc` (calls `ipc(cmd, arg)` on the main object, `arg` defaults
to `"_"`) or `exec` (shell command). `keys` is only the default: in the
overview every bind can be rebound or disabled (stored in
`~/.config/dynamic-island/keybinds.json` under `plugin:<id>.<bind>`).
`group` (default: plugin name) = group in the overview, `title` = row; neither
may contain `|`. Both go through `I18n.tr`, and the shell's own group names
are German source strings – `"Werkzeuge"` joins the built-in "Tools" group.
Optional `release`, `repeating`, `locked` as with `hl.bind`.

Under the hood: `modules/services/hypr/Keybinds.qml` writes all plugin and
custom binds including changes to `~/.local/state/dynamic-island/keybinds.lua`,
`hypr/hyprland.lua` applies the file with `sync_keybinds()` (when the config
loads and live via `hyprctl eval`). Only Hypr profiles with
`keybinds_from_shell = true` (simple) use them.

### `parent` – components

```json
{ "id": "bonsai", "parent": "desktop", "widgets": { … } }
```

A component is a perfectly normal plugin (own folder, own `.dip`, own switch)
that belongs to another one:

- It only runs while its plugin is enabled. If it is on but the plugin is
  off, it shows "Waiting" (`status: "blocked"`).
- In the manager it isn't listed at the top but in its plugin's submenu
  (button on that plugin's card, title from `components.title`). Importing
  there only accepts packages with a matching `parent`
  (`plugin import --parent <id>`).
- One level only: a plugin that has a `parent` itself can't have components.
  If the plugin is missing, the component stays off and is listed at the top
  with a notice.

That's how the desktop widgets are built: `desktop/` provides the layer and
clock/visualizer/lyrics, `bonsai/`, `matrix/`, `tui/` are components.

### `files`

```json
"files": [
    { "path": "~/.config/fish/functions/fastfetch.fish" },
    { "path": "~/.config/fastfetch", "optional": true, "note": "Looks + images" }
]
```

Only paths under `~/`. Folders are taken along completely. The shell itself
never touches these files – they only exist for `export`/`import`.

## Main.qml

```qml
import QtQuick
import Quickshell
import qs.modules.services.config     // all of the shell's qs.* modules work

QtObject {
    required property var plugin       // context, see below

    // optional: launcher actions (">" in the launcher), same format as LauncherActions
    readonly property var actions: [
        { name: "Do something", desc: "…", icon: "bolt", run: () => console.log("hi") }
    ]

    // optional: qs -c dynamic-island ipc call plugins call <id> <cmd> <arg>
    function ipc(cmd: string, arg: string): string { return "ok"; }

    // optional: only on a real disable (not on shell exit/reload).
    // Undo anything visible outside the plugin here (files, modes …).
    // The object is destroyed right afterwards – don't start anything
    // asynchronous that still needs it (Quickshell.execDetached is fine).
    function onDisable(): void {}
}
```

The root can be any type (`QtObject`, `Scope`, `Item` …). The object is
created when the plugin is enabled and destroyed when it is disabled. Attach
non-visual children to a `QtObject` as `property FileView x: FileView {}`
(or use `Scope` as the root).

### Context `plugin`

| | |
|---|---|
| `id`, `name`, `version`, `dir`, `manifest`, `enabled` | info |
| `settings` | current values (`{ key: value }`), new object on every change → bindable |
| `setting(key)` / `set(key, value)` | read / write (ends up in `plugins.json`) |
| `main` | the object from `main` while it is running (otherwise `null`) – that's how tiles and sections reach the service |
| `url(rel)` | path of a file in the plugin folder (`.qml` with `?v=<load time>` appended, so Qt doesn't serve a stale version from its component cache after changes – always use this URL for `Loader.setSource`/`Qt.createComponent`) |
| `statePath(rel)`, `cachePath(rel)` | `~/.local/state/dynamic-island/plugins/<id>/…`, `~/.cache/…` (not created) |
| `log(msg)` | `console.info` with a prefix |

## Tiles

Easiest with the ready-made `QuickTile` widget (looks like the built-in
tiles: active = whole tile in the accent color, below 150 px only the icon):

```qml
import qs.modules.widgets

QuickTile {
    id: tile
    active: tile.plugin.settings.lamp === true     // tile in accent color
    subtitle: tile.active ? "On" : "Off"
    icon: tile.active ? "lightbulb" : "light_off"  // optional, otherwise from the manifest
    onToggled: tile.plugin.set("lamp", !tile.active)
}
```

Quick settings load the file from `tiles.<id>.component` with `plugin`
(context) as the initial value and then set `tileId` if the root has that
property. A custom root item works too, it then needs
`required property var plugin`.

`QuickTile`: `plugin`, `tileId`, `meta` (read-only: manifest entry), `icon`
(default meta.icon → plugin icon), `title` (default meta.label), `subtitle`,
`active`, `accent`/`onAccent` (default primary/fgPrimary), `tapEnabled`
(false = your own TapHandler); read-only: `compact` (width < 150), `fg`,
`fgDim`, `controlColor`, `controlHover` (for your own buttons); signal
`toggled()`; children are placed on the tile. Height 54, the grid decides the
width. If the file doesn't load, a fallback tile "Tile failed to load" is
shown instead (reason in the log).

**Imports:** plugin QML can import every `qs.*` module the shell already
loads itself (config, widgets, services/…, `qs` for Colors/Appearance). A
module that isn't imported anywhere in the shell counts as "not installed".
Files in the plugin folder do **not** see each other as types ("X is not a
type" – the shell loads them through its `qs:` scheme, which has no directory
import). So load a second QML file of the plugin by path:
`Loader { Component.onCompleted: setSource(plugin.url("List.qml"), { value: 1 }) }`
and hook up bindings in `onLoaded` (that's what `plugins/wallhaven/Section.qml`
does with `WallhavenList.qml`).

**New files:** files added to the plugin folder after the shell started are
only seen after a restart (`dynamic-island shell -k`, `-d`) – "File not found"
in the log even though the file is there. Imported plugins aren't affected,
they are complete before they get enabled.

## Sections

A section (manifest `panels.<view>`) is an `Item` that the view loads when it
expands and destroys again when it collapses – so while collapsed there's no
section, no timers, no processes. Anything that should survive collapsing
(search text, results) belongs in the service (`plugin.main`). Reference:
`plugins/wallhaven/Section.qml`.

```qml
Item {
    id: section

    required property var plugin        // context, see above
    required property var host          // what the view offers, see below

    implicitHeight: 190                 // how far the card grows

    // keyboard focus arrives – may already be the case on creation
    readonly property bool focused: section.host.focused
    onFocusedChanged: if (focused) input.forceActiveFocus()
    Component.onCompleted: if (focused) input.forceActiveFocus()

    TextInput {
        id: input
        Keys.onEscapePressed: section.host.close()
        Keys.onUpPressed: section.host.leaveFocus()
        Keys.onDownPressed: section.host.leaveFocus()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
                section.host.toggle();
                event.accepted = true;
            }
        }
    }
}
```

View `wallpaper` (`modules/launcher/WallpaperPanel.qml`): at most one section
is open; which one is remembered in `LauncherState.wallpaperSection` (plugin
id, survives closing the picker). Open/close via the button in the search
bar, Ctrl+W (opens the first, then the next, closes after the last) and
`LauncherState.showWallpaperSection(screen, id)` or `toggleWallpaperSection`
(opens the picker with the section expanded and keyboard focus in it – that's
what the Wallhaven plugin's `ipc("open")` does). The keyboard belongs either
to the local row or to the section; Up/Down switch. The section handles the
keys in its own search field.

`host` of the wallpaper picker:

| | |
|---|---|
| `listHeight`, `imageWidth` | dimensions of the local row (carousel height, tile width) |
| `focused` | the section has the keyboard → focus the search field, show your own preview |
| `currentPath` | path of the selected image in the local row (`""` without images), bindable – for sections that show something about that image (the terminal plugin's look preview) |
| `takeFocus()` | the section wants the keyboard (click/scroll on a tile) |
| `leaveFocus()` | keyboard back to the local row (Up/Down) |
| `toggle()` | Ctrl+W: next section or close |
| `close()` | close the picker (Esc) |
| `cycleStyle(delta)` | Ctrl+Left/Right: style of the selected local image |
| `moveBy(delta)` | move the selection of the local row (for sections without a list of their own, e.g. Left/Right in the terminal section) |

Background preview: `Wallpapers.preview(path)` like the local row,
`Wallpapers.previewThumb(path)` for a small image (only scaled up, not decoded
at screen size). When the section loses the keyboard, the view restores the
local row's preview itself; when the picker closes, the local row takes the
preview back. So a section never calls `Wallpapers.stopPreview()` itself – at
most the service does in `onDisable()`, if the background is currently
showing one of its images. When the section sets a wallpaper, it closes the
picker with `LauncherState.close()` (or `host.close()`).

## Exchange formats

### Plugin package `<id>-<version>.dip`

tar.gz containing:

```
dip.json          package header
plugin/…          the plugin folder (without __pycache__, .qmlls.ini, .git)
files/<n>[/…]     external files from manifest.files (folders as a subtree)
```

`dip.json`:

```json
{
  "format": "dynamic-island-plugin",
  "formatVersion": 1,
  "plugin": { "id": "terminal", "name": "Terminal-Looks", "version": "1.0.0", "api": 1 },
  "created": "2026-10-22T11:44:48+02:00",
  "generator": "dynamic-island plugin export (hostname)",
  "enabled": true,
  "settings": { "theme": true, "folderLooks": true },
  "files": [ { "path": "~/.config/starship.toml", "archive": "files/9", "type": "file", "optional": false } ],
  "checksums": { "plugin/plugin.json": "<sha256>", "files/9": "<sha256>" }
}
```

Checked on import: only relative paths under `dip.json`/`plugin/`/`files/`,
only files and folders (no links/devices), ≤ 5000 entries, ≤ 512 MB, every
file with a matching SHA-256, manifest by the same rules as in the shell,
target paths only under `~/`.

### Settings `<id>-settings.json`

```json
{
  "format": "dynamic-island-plugin-settings",
  "formatVersion": 1,
  "plugin": { "id": "terminal", "version": "1.0.0" },
  "created": "…",
  "settings": { "theme": false }
}
```

Unknown keys are ignored on import.

## CLI

```
dynamic-island plugin list                     ● on  ○ off  ✗ broken, components with └ below
dynamic-island plugin info <id>
dynamic-island plugin enable|disable <id>
dynamic-island plugin new <id> [--name N]      from plugins/_example
dynamic-island plugin validate <folder|.dip>
dynamic-island plugin export <id> [-o path] [--no-settings] [--no-files] [--skip-optional]
dynamic-island plugin export <id> --settings-only [-o path]
dynamic-island plugin import <file.dip|.json> [--enable] [--files] [--settings|--no-settings]
                                               [--force] [--overwrite-files] [--parent <id>] [-y]
dynamic-island plugin remove <id> [--keep-settings] [--force] [-y]
```

Every command supports `--json` (one line `{ ok, message, … }`, that's how the
shell calls them). The default export target is `~/Downloads`.

Import rules: foreign code never runs without asking – a freshly imported
plugin is off unless you pass `--enable`. The same or an older version over
an installed one only with `--force`. Bundled settings only apply if none
are stored for the plugin yet (`--settings` forces them). External files only
with `--files`; existing files that differ are kept unless you pass
`--overwrite-files`. Replaced plugins/files go to
`~/.cache/dynamic-island/plugin-backups/`.

## IPC

```
qs -c dynamic-island ipc call plugins list
qs -c dynamic-island ipc call plugins enable|disable|toggle|reload <id>
qs -c dynamic-island ipc call plugins rescan
qs -c dynamic-island ipc call plugins call <id> <cmd> <arg>
```
