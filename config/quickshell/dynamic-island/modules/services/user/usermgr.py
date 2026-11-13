#!/usr/bin/env python3
"""Konto des angemeldeten Users fuer modules/services/user/User.qml.

Eine JSON-Zeile je Aufruf ({"ok": ...}).

  info            {"user", "name", "face"} – Login, Anzeigename (GECOS), ~/.face
  pick            Bildauswahl (kdialog, sonst zenity) -> {"path": ""|pfad}
  face <pfad>     quadratisch auf 512 px zuschneiden -> ~/.face, dazu
                  AccountsService SetIconFile (Login-Bildschirm)
  name <name>     AccountsService SetRealName
  password        neues Passwort als erste Zeile auf stdin -> SHA-512-Hash
                  (openssl) -> AccountsService SetPassword; polkit fragt das
                  aktuelle Passwort ab (auth_admin)

AccountsService: Bild und Name gehen ohne Passwort (change-own-user-data),
das Passwort nur ueber den polkit-Dialog. Das Passwort steht nie in argv.
"""

import json
import os
import pwd
import shutil
import subprocess
import sys
from pathlib import Path

FACE = Path(os.environ.get("DYNAMIC_ISLAND_FACE") or Path.home() / ".face")
BUS = ["busctl", "--system", "--timeout=300", "call", "org.freedesktop.Accounts",
       f"/org/freedesktop/Accounts/User{os.getuid()}", "org.freedesktop.Accounts.User"]


def out(**data) -> None:
    print(json.dumps({"ok": True, **data}, ensure_ascii=False), flush=True)


def fail(msg: str) -> None:
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False), flush=True)
    sys.exit(0)


def accounts(method: str, sig: str, *args: str) -> str:
    """AccountsService aufrufen; "" bei Erfolg, sonst die Fehlermeldung."""
    res = subprocess.run(BUS + [method, sig, *args], capture_output=True, text=True)
    if res.returncode == 0:
        return ""
    err = res.stderr.strip()
    # polkit-Dialog abgebrochen oder falsches Passwort
    if "NotAuthorized" in err or "not authorized" in err.lower() or "PermissionDenied" in err:
        return "Nicht berechtigt"
    return err or f"{method} fehlgeschlagen"


def op_info(_args):
    entry = pwd.getpwuid(os.getuid())
    name = entry.pw_gecos.split(",")[0].strip()
    out(user=entry.pw_name, name=name or entry.pw_name, face=str(FACE) if FACE.is_file() else "")


def op_pick(_args):
    start = str(Path.home() / "Pictures") if (Path.home() / "Pictures").is_dir() else str(Path.home())
    filters = "*.png *.jpg *.jpeg *.webp *.gif *.bmp"
    if shutil.which("kdialog"):
        cmd = ["kdialog", "--title", "Profilbild wählen", "--getopenfilename", start, f"Bilder ({filters})"]
    elif shutil.which("zenity"):
        cmd = ["zenity", "--file-selection", "--title=Profilbild wählen", f"--file-filter=Bilder | {filters}"]
    else:
        fail("Kein Dateidialog (kdialog oder zenity)")
    res = subprocess.run(cmd, capture_output=True, text=True)
    out(path=res.stdout.strip() if res.returncode == 0 else "")


def op_face(args):
    src = args[0] if args else ""
    if src.startswith("file://"):
        from urllib.parse import unquote
        src = unquote(src[7:])
    if not Path(src).is_file():
        fail("Datei nicht gefunden")
    # Erst in eine Nachbardatei, dann ersetzen: ein kaputtes Bild laesst das alte stehen
    tmp = FACE.with_name(FACE.name + ".tmp")
    res = subprocess.run(["magick", f"{src}[0]", "-auto-orient", "-resize", "512x512^",
                          "-gravity", "center", "-extent", "512x512", "-strip", f"png:{tmp}"],
                         capture_output=True, text=True)
    if res.returncode != 0 or not tmp.is_file():
        tmp.unlink(missing_ok=True)
        fail("Kein lesbares Bild")
    os.replace(tmp, FACE)
    # Login-Bildschirm; ohne AccountsService bleibt es beim ~/.face
    warn = accounts("SetIconFile", "s", str(FACE))
    out(face=str(FACE), warning=warn)


def op_name(args):
    name = " ".join(args).strip()
    if not name:
        fail("Name ist leer")
    if len(name) > 64 or any(c in name for c in ":,\n\r"):
        fail("Name darf keine Doppelpunkte oder Kommas enthalten")
    err = accounts("SetRealName", "s", name)
    if err:
        fail(err)
    out(name=name)


def op_password(_args):
    password = sys.stdin.readline().rstrip("\n")
    if not password:
        fail("Passwort ist leer")
    res = subprocess.run(["openssl", "passwd", "-6", "-stdin"], input=password + "\n",
                         capture_output=True, text=True)
    hashed = res.stdout.strip()
    if res.returncode != 0 or not hashed.startswith("$6$"):
        fail("Hash fehlgeschlagen")
    err = accounts("SetPassword", "ss", hashed, "")
    if err:
        fail(err)
    out()


OPS = {"info": op_info, "pick": op_pick, "face": op_face, "name": op_name, "password": op_password}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in OPS:
        fail("Aufruf: usermgr.py info|pick|face <pfad>|name <name>|password")
    OPS[sys.argv[1]](sys.argv[2:])
