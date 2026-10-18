"""Theme-Modus und Palette an KDE/Qt und laufende Kitty-Fenster weitergeben."""
from pathlib import Path
import json
import configparser
import os
import signal
import subprocess

def main():
    home = Path.home()
    state = home / '.local/state/dynamic-island'
    scheme = json.loads((state / 'scheme.json').read_text())
    mode = scheme['mode']
    # Breeze ist bereits installiert. Keine Verweise auf fehlendes adw-gtk3.
    subprocess.run(['gsettings', 'set', 'org.gnome.desktop.interface', 'gtk-theme', 'Breeze'], check=True)
    subprocess.run(['gsettings', 'set', 'org.gnome.desktop.interface', 'color-scheme', 'prefer-' + mode], check=True)
    for version in ('gtk-3.0', 'gtk-4.0'):
        settings = home / '.config' / version / 'settings.ini'
        parser = configparser.ConfigParser(interpolation=None)
        parser.optionxform = str
        parser.read(settings)
        if not parser.has_section('Settings'):
            parser.add_section('Settings')
        parser['Settings']['gtk-theme-name'] = 'Breeze'
        parser['Settings']['gtk-application-prefer-dark-theme'] = str(mode == 'dark').lower()
        parser['Settings']['gtk-icon-theme-name'] = 'breeze-dark' if mode == 'dark' else 'breeze'
        settings.parent.mkdir(parents=True, exist_ok=True)
        with settings.open('w') as stream:
            parser.write(stream)
    source = home / '.config/qtengine/dynamic-island.colors'
    destination = home / '.local/share/color-schemes/DynamicIsland.colors'
    destination.parent.mkdir(parents=True, exist_ok=True)
    content = source.read_text().replace('Name=Dynamic Island', 'Name=DynamicIsland')
    destination.write_text(content)
    # Gleicher Dateiname, neue Farben: auch erneutes Anwenden muss KDE benachrichtigen.
    subprocess.run(['kwriteconfig6', '--file', 'kdeglobals', '--group', 'General',
                    '--key', 'ColorScheme', 'DynamicIsland-updating'], check=True)
    subprocess.run(['plasma-apply-colorscheme', 'DynamicIsland'], check=True, timeout=15)
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid == os.getuid() and (proc / 'comm').read_text().strip() == 'kitty':
                os.kill(int(proc.name), signal.SIGUSR1)
        except (OSError, ProcessLookupError):
            pass

if __name__ == '__main__':
    main()
