#!/usr/bin/python
"""Super+Ziffer: lokale Arbeitsflaeche des fokussierten Monitors."""
import json
import subprocess
import sys

OFFSETS = {'eDP-1': 0, 'HDMI-A-1': 10, 'DVI-I-1': 20, 'DVI-I-2': 30}

def target_for(monitor, number):
    if not 1 <= number <= 5:
        raise ValueError('Workspace muss 1 bis 5 sein')
    return OFFSETS.get(monitor, 0) + number

def main():
    action, number = sys.argv[1], int(sys.argv[2])
    if action not in ('focus', 'move'):
        raise ValueError('Unbekannte Aktion')
    monitors = json.loads(subprocess.check_output(['hyprctl', 'monitors', '-j']))
    monitor = (next(m for m in monitors if m['name'] == sys.argv[3])
               if len(sys.argv) > 3 else next(m for m in monitors if m['focused']))
    target = target_for(monitor['name'], number)
    dispatcher = 'workspace' if action == 'focus' else 'movetoworkspacesilent'
    subprocess.run(['hyprctl', 'dispatch', dispatcher, str(target)], check=True)

if __name__ == '__main__':
    main()
