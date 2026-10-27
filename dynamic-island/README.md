# dynamic-island

The CLI for the rice (Quickshell config `~/.config/quickshell/dynamic-island`).

Derived from [caelestia-cli](https://github.com/caelestia-dots/cli) 1.1.2 (GPL-3.0-only),
but standalone: its own paths, its own name, no dotfiles management (`install`/`update`)
and no dependency on someone else's shell.

## Setup

```bash
./install.sh --install-deps    # packages, symlinks, directories, color scheme
./install.sh --check           # only check
./install.sh -y                # don't ask
```

The script first warns that it was **made with AI**, lists what it touches
and asks for confirmation (default: no).

Idempotent: running it several times does no harm. Real files are backed up
to `~/backups/dynamic-island-install-<date>/` before they are replaced by symlinks.

## Usage

```
dynamic-island shell -d            # start the shell (qs -c dynamic-island)
dynamic-island shell launcher toggle   # send IPC to the shell
dynamic-island wallpaper -f IMAGE  # set wallpaper + Material You scheme
dynamic-island wallpaper -r        # random wallpaper from ~/Pictures/Wallpapers
dynamic-island scheme set -n nord -m dark
dynamic-island screenshot [-r] [-f] [-e]   # region / frozen / open in swappy
dynamic-island record [-s] [-r]    # start/stop recording (sound / region)
dynamic-island clipboard [-d]      # cliphist via fuzzel
dynamic-island emoji -p            # emoji/glyph picker
dynamic-island toggle specialws|music|communication|sysmon|todo
dynamic-island resizer -d          # window resizer daemon
```

## Layout

| Purpose | Path |
|---|---|
| Code | `~/.config/dynamic-island/src/dynamic_island/` |
| Helper scripts | `~/.config/dynamic-island/scripts/` → `~/.local/bin/{hypr-profile,theme-set}` |
| Launcher script | `~/.config/dynamic-island/bin/dynamic-island` → `~/.local/bin/dynamic-island` |
| User config | `~/.config/dynamic-island/cli.json` |
| Custom templates | `~/.config/dynamic-island/templates/` |
| State (scheme, wallpaper, recording) | `~/.local/state/dynamic-island/` |
| Cache (thumbnails, schemes, screenshots) | `~/.cache/dynamic-island/` |

No `pip install` needed – the launcher script adds `src/` to `sys.path`. Changes
to the code take effect immediately.

## Dependencies

Python: `materialyoucolor`, `pillow`. External: `grim`, `slurp`, `swappy`, `hyprpicker`,
`wl-clipboard`, `cliphist`, `fuzzel`, `gpu-screen-recorder`, `dart-sass`, `dconf`,
`libnotify`, `hyprctl`, `qs` (Quickshell).

## Differences from caelestia-cli

- `install`/`update` and the whole dotfiles management (`utils/dots/`, `utils/version.py`) removed.
- `screenshot -r` uses `slurp` for region selection; `-f` freezes the screen
  via `hyprpicker -r -z`.
- New flag `screenshot -e/--edit`: opens the shot directly in `swappy`.
- Shell name as a constant in `subcommands/shell.py`, changeable via `cli.json → shell.name`.
- Theming switches in `cli.json`: `fuzzel` and `chromium` are off (the first overwrites
  the entire `fuzzel.ini`, the second writes to `/etc` via `sudo`).
