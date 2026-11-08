#!/usr/bin/env python3
"""Gibt das sh-Skript aus der `command:`-Zeile einer QML-Datei aus."""

import json
import re
import sys

line = next(l for l in open(sys.argv[1]) if '["sh", "-c", "command -v' in l)
print(json.loads(re.search(r'"sh", "-c", ("(?:[^"\\]|\\.)*")', line).group(1)))
