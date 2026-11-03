import argparse
import sys

from dynamic_island.subcommands import (
    clipboard,
    emoji,
    plugin,
    record,
    resizer,
    scheme,
    screenshot,
    shell,
    toggle,
    wallpaper,
)
from dynamic_island.utils.paths import wallpapers_dir
from dynamic_island.utils.scheme import get_scheme_names, scheme_variants
from dynamic_island.utils.wallpaper import get_wallpaper


def parse_args() -> tuple[argparse.ArgumentParser, argparse.Namespace]:
    parser = argparse.ArgumentParser(
        prog="dynamic-island", description="Steuerung fuer den Dynamic-Island-Rice (Shell, Farben, Wallpaper, Aufnahmen)"
    )

    # Add subcommand parsers
    command_parser = parser.add_subparsers(
        title="subcommands", description="valid subcommands", metavar="COMMAND", help="the subcommand to run"
    )

    # Create parser for shell opts
    shell_parser = command_parser.add_parser("shell", help="start or message the shell")
    shell_parser.set_defaults(cls=shell.Command)
    shell_parser.add_argument("message", nargs="*", help="a message to send to the shell")
    shell_parser.add_argument("-d", "--daemon", action="store_true", help="start the shell detached")
    shell_parser.add_argument("-s", "--show", action="store_true", help="print all shell IPC commands")
    shell_parser.add_argument("-l", "--log", action="store_true", help="print the shell log")
    shell_parser.add_argument("-k", "--kill", action="store_true", help="kill the shell")
    shell_parser.add_argument("--log-rules", metavar="RULES", help="log rules to apply")

    # Create parser for toggle opts
    toggle_parser = command_parser.add_parser("toggle", help="toggle a special workspace")
    toggle_parser.set_defaults(cls=toggle.Command)
    toggle_parser.add_argument("workspace", help="the workspace to toggle")

    # Create parser for scheme opts
    scheme_parser = command_parser.add_parser("scheme", help="manage the colour scheme")
    scheme_command_parser = scheme_parser.add_subparsers(title="subcommands")

    list_parser = scheme_command_parser.add_parser("list", help="list available schemes")
    list_parser.set_defaults(cls=scheme.List)
    list_parser.add_argument("-n", "--names", action="store_true", help="list scheme names")
    list_parser.add_argument("-f", "--flavours", action="store_true", help="list scheme flavours")
    list_parser.add_argument("-m", "--modes", action="store_true", help="list scheme modes")
    list_parser.add_argument("-v", "--variants", action="store_true", help="list scheme variants")

    get_parser = scheme_command_parser.add_parser("get", help="get scheme properties")
    get_parser.set_defaults(cls=scheme.Get)
    get_parser.add_argument("-n", "--name", action="store_true", help="print the current scheme name")
    get_parser.add_argument("-f", "--flavour", action="store_true", help="print the current scheme flavour")
    get_parser.add_argument("-m", "--mode", action="store_true", help="print the current scheme mode")
    get_parser.add_argument("-v", "--variant", action="store_true", help="print the current scheme variant")

    set_parser = scheme_command_parser.add_parser("set", help="set the current scheme")
    set_parser.set_defaults(cls=scheme.Set)
    set_parser.add_argument("--notify", action="store_true", help="send a notification on error")
    set_parser.add_argument("-r", "--random", action="store_true", help="switch to a random scheme")
    set_parser.add_argument("-n", "--name", choices=get_scheme_names(), help="the name of the scheme to switch to")
    set_parser.add_argument("-f", "--flavour", help="the flavour to switch to")
    set_parser.add_argument("-m", "--mode", choices=["dark", "light"], help="the mode to switch to")
    set_parser.add_argument("-v", "--variant", choices=scheme_variants, help="the variant to switch to")

    # Create parser for screenshot opts
    screenshot_parser = command_parser.add_parser("screenshot", help="take a screenshot")
    screenshot_parser.set_defaults(cls=screenshot.Command)
    screenshot_parser.add_argument("-r", "--region", nargs="?", const="slurp", help="take a screenshot of a region")
    screenshot_parser.add_argument(
        "-f", "--freeze", action="store_true", help="freeze the screen while selecting a region"
    )
    screenshot_parser.add_argument(
        "-e", "--edit", action="store_true", help="open the screenshot in swappy instead of copying it"
    )
    screenshot_parser.add_argument("-o", "--ocr", action="store_true", help="copy the text of a region (OCR)")
    screenshot_parser.add_argument("-q", "--qr", action="store_true", help="read a QR code in a region")
    screenshot_parser.add_argument(
        "-s", "--slurp", action="store_true", help="always select with slurp, not the shell overlay"
    )

    # Create parser for record opts
    record_parser = command_parser.add_parser("record", help="start a screen recording")
    record_parser.set_defaults(cls=record.Command)
    record_parser.add_argument("-r", "--region", nargs="?", const="slurp", help="record a region")
    record_parser.add_argument("-s", "--sound", action="store_true", help="record audio")
    record_parser.add_argument("-p", "--pause", action="store_true", help="pause/resume the recording")
    record_parser.add_argument("-c", "--clipboard", action="store_true", help="copy recording path to clipboard")

    # Create parser for clipboard opts
    clipboard_parser = command_parser.add_parser("clipboard", help="open clipboard history")
    clipboard_parser.set_defaults(cls=clipboard.Command)
    clipboard_parser.add_argument("-d", "--delete", action="store_true", help="delete from clipboard history")

    # Create parser for emoji-picker opts
    emoji_parser = command_parser.add_parser("emoji", help="emoji/glyph utilities")
    emoji_parser.set_defaults(cls=emoji.Command)
    emoji_parser.add_argument("-p", "--picker", action="store_true", help="open the emoji/glyph picker")
    emoji_parser.add_argument("-f", "--fetch", action="store_true", help="fetch emoji/glyph data from remote")

    # Create parser for plugin opts
    plugin_parser = command_parser.add_parser("plugin", help="manage shell plugins (list, import, export)")
    plugin_command_parser = plugin_parser.add_subparsers(title="subcommands", metavar="ACTION")

    def plugin_cmd(name: str, cls, help: str) -> argparse.ArgumentParser:
        p = plugin_command_parser.add_parser(name, help=help)
        p.set_defaults(cls=cls)
        p.add_argument("--json", action="store_true", help="print the result as JSON")
        return p

    plugin_cmd("list", plugin.List, "list installed plugins")
    plugin_cmd("info", plugin.Info, "show a plugin's manifest, settings and files").add_argument("id")
    plugin_cmd("enable", plugin.Enable, "turn a plugin on").add_argument("id")
    plugin_cmd("disable", plugin.Disable, "turn a plugin off").add_argument("id")
    plugin_cmd("validate", plugin.Validate, "check a plugin folder or .dip package").add_argument("path")

    p = plugin_cmd("export", plugin.Export, "export a plugin as .dip package (or its settings as JSON)")
    p.add_argument("id")
    p.add_argument("-o", "--output", metavar="PATH", help="target file or folder (default ~/Downloads)")
    p.add_argument("--no-settings", action="store_true", help="leave the current settings out")
    p.add_argument("--no-files", action="store_true", help="leave the external files (manifest.files) out")
    p.add_argument("--skip-optional", action="store_true", help="leave optional external files out")
    p.add_argument("--settings-only", action="store_true", help="export only the settings as JSON")

    p = plugin_cmd("import", plugin.Import, "import a .dip package or a settings JSON")
    p.add_argument("file")
    p.add_argument("-y", "--yes", action="store_true", help="do not ask")
    p.add_argument("--enable", action="store_true", help="turn the plugin on after importing")
    p.add_argument("--files", action="store_true", help="install the bundled external files")
    p.add_argument("--settings", action="store_true", help="overwrite existing settings with the bundled ones")
    p.add_argument("--no-settings", action="store_true", help="ignore bundled settings")
    p.add_argument("--force", action="store_true", help="replace an installed same/newer version")
    p.add_argument("--overwrite-files", action="store_true", help="replace differing external files (old ones are backed up)")
    p.add_argument("--parent", metavar="ID", help="only accept components of this plugin (manifest parent)")

    p = plugin_cmd("remove", plugin.Remove, "remove a plugin (moved to a backup folder)")
    p.add_argument("id")
    p.add_argument("-y", "--yes", action="store_true", help="do not ask")
    p.add_argument("--keep-settings", action="store_true", help="keep its settings in plugins.json")
    p.add_argument("--force", action="store_true", help="also remove a builtin plugin")

    p = plugin_cmd("new", plugin.New, "create a new plugin from the template")
    p.add_argument("id")
    p.add_argument("--name", help="display name")
    p.add_argument("--author", help="author")

    # Create parser for wallpaper opts
    wallpaper_parser = command_parser.add_parser("wallpaper", help="manage the wallpaper")
    wallpaper_parser.set_defaults(cls=wallpaper.Command)
    wallpaper_parser.add_argument(
        "-p", "--print", nargs="?", const=get_wallpaper(), metavar="PATH", help="print the scheme for a wallpaper"
    )
    wallpaper_parser.add_argument(
        "-r", "--random", nargs="?", const=wallpapers_dir, metavar="DIR", help="switch to a random wallpaper"
    )
    wallpaper_parser.add_argument("-f", "--file", help="the path to the wallpaper to switch to")
    wallpaper_parser.add_argument("-n", "--no-filter", action="store_true", help="do not filter by size")
    wallpaper_parser.add_argument(
        "-t",
        "--threshold",
        default=0.8,
        help="the minimum percentage of the largest monitor size the image must be greater than to be selected",
    )
    wallpaper_parser.add_argument(
        "-N",
        "--no-smart",
        action="store_true",
        help="do not automatically change the scheme mode based on wallpaper colour",
    )
    wallpaper_parser.add_argument(
        "-v",
        "--variant",
        choices=["auto", *scheme_variants],
        help="pin the scheme variant for a wallpaper (auto = derive it from the image)",
    )
    wallpaper_parser.add_argument(
        "--for", dest="target", metavar="PATH", help="the wallpaper --variant applies to (default: current)"
    )

    # Create parser for resizer opts
    resizer_parser = command_parser.add_parser("resizer", help="window resizer daemon")
    resizer_parser.set_defaults(cls=resizer.Command)
    resizer_parser.add_argument("-d", "--daemon", action="store_true", help="start the resizer daemon")
    resizer_parser.add_argument(
        "pattern",
        nargs="?",
        help="pattern to match against windows ('active' for current window only, 'pip' for quick pip mode)",
    )
    resizer_parser.add_argument(
        "match_type",
        nargs="?",
        metavar="match_type",
        choices=["titleContains", "titleExact", "titleRegex", "initialTitle"],
        help="type of pattern matching (titleContains,titleExact,titleRegex,initialTitle)",
    )
    resizer_parser.add_argument("width", nargs="?", help="width to resize to")
    resizer_parser.add_argument("height", nargs="?", help="height to resize to")
    resizer_parser.add_argument("actions", nargs="?", help="comma-separated actions to apply (float,center,pip)")

    return parser, parser.parse_args()

