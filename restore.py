"""Bewusster manueller Rueckweg, keine Loeschungen und kein automatisches Logout."""
from pathlib import Path
import datetime
import json
import shutil

home = Path.home()
backup = home / 'backups/hyprland-rice-20261018-112908'
if input('Gesicherte Konfigurationen wiederherstellen? [ja/NEIN] ') != 'ja':
    raise SystemExit('Abgebrochen.')
saved = home / 'backups' / ('rice-vor-rueckkehr-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))
manifest = json.loads((backup / 'manifest.json').read_text())
manifest.setdefault('.config/systemd/user/hyprland-session.target', False)
for rel, existed in manifest.items():
    target = home / rel
    if target.exists() or target.is_symlink():
        dst = saved / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(target), str(dst))
    if not existed:
        continue
    source = backup / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        target.symlink_to(source.readlink())
    elif source.is_dir():
        shutil.copytree(source, target, symlinks=True)
    else:
        shutil.copy2(source, target)
print('Wiederhergestellt. Aktuelle Dateien gesichert:', saved)
print('Arbeiten speichern, dann abmelden und Hyprland neu starten.')
