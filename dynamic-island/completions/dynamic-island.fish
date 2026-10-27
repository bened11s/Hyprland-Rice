set -l seen '__fish_seen_subcommand_from'
set -l has_opt '__fish_contains_opt'

set -l commands shell toggle scheme screenshot record clipboard emoji wallpaper resizer plugin
set -l not_seen "not $seen $commands"

# Disable file completions
complete -c dynamic-island -f

# Add help for any command
complete -c dynamic-island -s 'h' -l 'help' -d 'Show help'

# Subcommands
complete -c dynamic-island -n $not_seen -a 'shell' -d 'Start the shell or message it'
complete -c dynamic-island -n $not_seen -a 'toggle' -d 'Toggle a special workspace'
complete -c dynamic-island -n $not_seen -a 'scheme' -d 'Manage the colour scheme'
complete -c dynamic-island -n $not_seen -a 'screenshot' -d 'Take a screenshot'
complete -c dynamic-island -n $not_seen -a 'record' -d 'Start a screen recording'
complete -c dynamic-island -n $not_seen -a 'clipboard' -d 'Open clipboard history'
complete -c dynamic-island -n $not_seen -a 'emoji' -d 'Emoji/glyph utilities'
complete -c dynamic-island -n $not_seen -a 'wallpaper' -d 'Manage the wallpaper'
complete -c dynamic-island -n $not_seen -a 'resizer' -d 'Window resizer'
complete -c dynamic-island -n $not_seen -a 'plugin' -d 'Manage shell plugins'

# Shell
set -l commands mpris drawers wallpaper notifs
set -l not_seen "$seen shell && not $seen $commands"
complete -c dynamic-island -n $not_seen -s 'd' -l 'daemon' -d 'Start the shell detached'
complete -c dynamic-island -n $not_seen -s 's' -l 'show' -d 'Print all IPC commands'
complete -c dynamic-island -n $not_seen -s 'l' -l 'log' -d 'Print the shell log'
complete -c dynamic-island -n $not_seen -l 'log-rules' -d 'Log rules to apply'
complete -c dynamic-island -n $not_seen -a 'mpris' -d 'Mpris control'
complete -c dynamic-island -n $not_seen -a 'drawers' -d 'Toggle drawers'
complete -c dynamic-island -n $not_seen -a 'wallpaper' -d 'Wallpaper control (for internal use)'
complete -c dynamic-island -n $not_seen -a 'notifs' -d 'Notification control'

set -l commands getActive play pause playPause stop next previous list
set -l not_seen "$seen shell && $seen mpris && not $seen $commands"
complete -c dynamic-island -n $not_seen -a 'play' -d 'Play media'
complete -c dynamic-island -n $not_seen -a 'pause' -d 'Pause media'
complete -c dynamic-island -n $not_seen -a 'playPause' -d 'Play/pause media'
complete -c dynamic-island -n $not_seen -a 'next' -d 'Skip to next song'
complete -c dynamic-island -n $not_seen -a 'previous' -d 'Go to previous song'
complete -c dynamic-island -n $not_seen -a 'stop' -d 'Stop media'
complete -c dynamic-island -n $not_seen -a 'list' -d 'List media players'
complete -c dynamic-island -n $not_seen -a 'getActive' -d 'Get a property from the active MPRIS player'

set -l commands trackTitle trackArtist trackAlbum position length identity
set -l not_seen "$seen shell && $seen mpris && $seen getActive && not $seen $commands"
complete -c dynamic-island -n $not_seen -a 'trackTitle' -d 'Track title'
complete -c dynamic-island -n $not_seen -a 'trackArtist' -d 'Track artist'
complete -c dynamic-island -n $not_seen -a 'trackAlbum' -d 'Track album'
complete -c dynamic-island -n $not_seen -a 'position' -d 'Track position'
complete -c dynamic-island -n $not_seen -a 'length' -d 'Track length'
complete -c dynamic-island -n $not_seen -a 'identity' -d 'Player identity'

set -l commands list toggle
set -l not_seen "$seen shell && $seen drawers && not $seen $commands"
complete -c dynamic-island -n $not_seen -a 'list' -d 'List togglable drawers'
complete -c dynamic-island -n $not_seen -a 'toggle' -d 'Toggle a drawer'

set -l commands (dynamic-island shell drawers list 2> /dev/null)
complete -c dynamic-island -n "$seen shell && $seen drawers && $seen toggle && not $seen $commands" -a "$commands" -d 'drawer'

set -l commands list get set
set -l not_seen "$seen shell && $seen wallpaper && not $seen $commands"
complete -c dynamic-island -n $not_seen -a 'list' -d 'List wallpapers'
complete -c dynamic-island -n $not_seen -a 'get' -d 'Get current wallpaper path'
complete -c dynamic-island -n $not_seen -a 'set' -d 'Change wallpaper'
complete -c dynamic-island -n "$seen shell && $seen wallpaper && $seen set" -F

complete -c dynamic-island -n "$seen shell && $seen notifs && not $seen clear" -a 'clear' -d 'Clear popup notifications'

# Toggles
set -l commands communication music specialws sysmon todo
complete -c dynamic-island -n "$seen toggle && not $seen drawers && not $seen $commands" -a "$commands" -d 'toggle'

# Scheme
set -l commands list get set
set -l not_seen "$seen scheme && not $seen $commands"
complete -c dynamic-island -n $not_seen -a 'list' -d 'List available schemes'
complete -c dynamic-island -n $not_seen -a 'get' -d 'Get scheme properties'
complete -c dynamic-island -n $not_seen -a 'set' -d 'Set the current scheme'

complete -c dynamic-island -n "$seen scheme && $seen list" -s 'n' -l 'names' -d 'List scheme names'
complete -c dynamic-island -n "$seen scheme && $seen list" -s 'f' -l 'flavours' -d 'List scheme flavours'
complete -c dynamic-island -n "$seen scheme && $seen list" -s 'm' -l 'modes' -d 'List scheme modes'
complete -c dynamic-island -n "$seen scheme && $seen list" -s 'v' -l 'variants' -d 'List scheme variants'

complete -c dynamic-island -n "$seen scheme && $seen get" -s 'n' -l 'name' -d 'Get scheme name'
complete -c dynamic-island -n "$seen scheme && $seen get" -s 'f' -l 'flavour' -d 'Get scheme flavour'
complete -c dynamic-island -n "$seen scheme && $seen get" -s 'm' -l 'mode' -d 'Get scheme mode'
complete -c dynamic-island -n "$seen scheme && $seen get" -s 'v' -l 'variant' -d 'Get scheme variant'

complete -c dynamic-island -n "$seen scheme && $seen set" -l 'notify' -d 'Send a notification on error'
complete -c dynamic-island -n "$seen scheme && $seen set" -s 'r' -l 'random' -d 'Switch to a random scheme'
complete -c dynamic-island -n "$seen scheme && $seen set" -s 'n' -l 'name' -d 'Set scheme name' -a "$(dynamic-island scheme list -n)" -r
complete -c dynamic-island -n "$seen scheme && $seen set" -s 'f' -l 'flavour' -d 'Set scheme flavour' -a "$(dynamic-island scheme list -f)" -r
complete -c dynamic-island -n "$seen scheme && $seen set" -s 'm' -l 'mode' -d 'Set scheme mode' -a "$(dynamic-island scheme list -m)" -r
complete -c dynamic-island -n "$seen scheme && $seen set" -s 'v' -l 'variant' -d 'Set scheme variant' -a "$(dynamic-island scheme list -v)" -r

# Screenshot
complete -c dynamic-island -n "$seen screenshot" -s 'r' -l 'region' -d 'Capture region'
complete -c dynamic-island -n "$seen screenshot" -s 'e' -l 'edit' -d 'In swappy oeffnen'
complete -c dynamic-island -n "$seen screenshot" -s 'f' -l 'freeze' -d 'Freeze while selecting region'

# Record
complete -c dynamic-island -n "$seen record" -s 'r' -l 'region' -d 'Capture region'
complete -c dynamic-island -n "$seen record" -s 's' -l 'sound' -d 'Capture sound'
complete -c dynamic-island -n "$seen record" -s 'c' -l 'clipboard' -d 'Copy recording path to clipboard'

# Clipboard
complete -c dynamic-island -n "$seen clipboard" -s 'd' -l 'delete' -d 'Delete from cliboard history'

# Wallpaper
complete -c dynamic-island -n "$seen wallpaper" -s 'p' -l 'print' -d 'Print the scheme for a wallpaper' -rF
complete -c dynamic-island -n "$seen wallpaper" -s 'r' -l 'random' -d 'Switch to a random wallpaper' -rF
complete -c dynamic-island -n "$seen wallpaper" -s 'f' -l 'file' -d 'The file to switch to' -rF
complete -c dynamic-island -n "$seen wallpaper" -s 'n' -l 'no-filter' -d 'Do not filter by size'
complete -c dynamic-island -n "$seen wallpaper" -s 'v' -l 'variant' -d 'Pin the scheme variant for a wallpaper' -xa 'auto tonalspot vibrant expressive fidelity fruitsalad monochrome neutral rainbow content'
complete -c dynamic-island -n "$seen wallpaper" -l 'for' -d 'Wallpaper the variant applies to' -rF
complete -c dynamic-island -n "$seen wallpaper" -s 't' -l 'threshold' -d 'The threshold to filter by' -r
complete -c dynamic-island -n "$seen wallpaper" -s 'N' -l 'no-smart' -d 'Disable smart mode switching'

# Emoji
complete -c dynamic-island -n "$seen emoji" -s 'p' -l 'picker' -d 'Open emoji/glyph picker'
complete -c dynamic-island -n "$seen emoji" -s 'f' -l 'fetch' -d 'Fetch emoji/glyph data from remote'

# Resizer
complete -c dynamic-island -n "$seen resizer" -s 'd' -l 'daemon' -d 'Start in daemon mode'
complete -c dynamic-island -n "$seen resizer" -a 'pip' -d 'Quick pip mode'
complete -c dynamic-island -n "$seen resizer" -a 'active' -d 'Select the active window'



# Plugin
set -l plugin_actions list info enable disable validate export import remove new
set -l plugin_ids "(path basename ~/.config/quickshell/dynamic-island/plugins/*/ | string match -rv '^[_.]')"
complete -c dynamic-island -n "$seen plugin && not $seen $plugin_actions" -a 'list' -d 'List plugins'
complete -c dynamic-island -n "$seen plugin && not $seen $plugin_actions" -a 'info' -d 'Show a plugin'
complete -c dynamic-island -n "$seen plugin && not $seen $plugin_actions" -a 'enable' -d 'Turn a plugin on'
complete -c dynamic-island -n "$seen plugin && not $seen $plugin_actions" -a 'disable' -d 'Turn a plugin off'
complete -c dynamic-island -n "$seen plugin && not $seen $plugin_actions" -a 'validate' -d 'Check a folder or .dip'
complete -c dynamic-island -n "$seen plugin && not $seen $plugin_actions" -a 'export' -d 'Export as .dip'
complete -c dynamic-island -n "$seen plugin && not $seen $plugin_actions" -a 'import' -d 'Import .dip or settings JSON'
complete -c dynamic-island -n "$seen plugin && not $seen $plugin_actions" -a 'remove' -d 'Remove a plugin'
complete -c dynamic-island -n "$seen plugin && not $seen $plugin_actions" -a 'new' -d 'Create from template'
complete -c dynamic-island -n "$seen plugin && $seen info enable disable export remove" -a "$plugin_ids"
complete -c dynamic-island -n "$seen plugin && $seen import validate" -F
complete -c dynamic-island -n "$seen plugin" -l 'json' -d 'JSON output'
complete -c dynamic-island -n "$seen plugin && $seen export" -s 'o' -l 'output' -d 'Target file or folder' -rF
complete -c dynamic-island -n "$seen plugin && $seen export" -l 'no-settings' -d 'Leave settings out'
complete -c dynamic-island -n "$seen plugin && $seen export" -l 'no-files' -d 'Leave external files out'
complete -c dynamic-island -n "$seen plugin && $seen export" -l 'skip-optional' -d 'Leave optional files out'
complete -c dynamic-island -n "$seen plugin && $seen export" -l 'settings-only' -d 'Only the settings as JSON'
complete -c dynamic-island -n "$seen plugin && $seen import remove" -s 'y' -l 'yes' -d 'Do not ask'
complete -c dynamic-island -n "$seen plugin && $seen import" -l 'enable' -d 'Turn on after import'
complete -c dynamic-island -n "$seen plugin && $seen import" -l 'files' -d 'Install bundled files'
complete -c dynamic-island -n "$seen plugin && $seen import" -l 'settings' -d 'Overwrite settings'
complete -c dynamic-island -n "$seen plugin && $seen import" -l 'no-settings' -d 'Ignore bundled settings'
complete -c dynamic-island -n "$seen plugin && $seen import" -l 'force' -d 'Replace same/newer version'
complete -c dynamic-island -n "$seen plugin && $seen import" -l 'overwrite-files' -d 'Replace differing files'
complete -c dynamic-island -n "$seen plugin && $seen import" -l 'parent' -x -d 'Only components of this plugin'
complete -c dynamic-island -n "$seen plugin && $seen remove" -l 'force' -d 'Also remove builtin plugin'
complete -c dynamic-island -n "$seen plugin && $seen remove" -l 'keep-settings' -d 'Keep settings'
complete -c dynamic-island -n "$seen plugin && $seen new" -l 'name' -d 'Display name' -r
complete -c dynamic-island -n "$seen plugin && $seen new" -l 'author' -d 'Author' -r
