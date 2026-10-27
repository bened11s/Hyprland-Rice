import subprocess
import time
from argparse import Namespace
from datetime import datetime
from pathlib import Path

from dynamic_island.utils import hypr
from dynamic_island.utils.notify import notify, notify_detached
from dynamic_island.utils.shellipc import shell_call
from dynamic_island.utils.paths import screenshots_cache_dir, screenshots_dir


class Command:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def run(self) -> None:
        # Bereich, Text oder Code: das Overlay der Shell (Standbild, Fenster
        # einrasten, OCR/QR). Nur ohne laufende Shell (oder mit --slurp, oder
        # mit fester Geometrie) wie frueher ueber slurp.
        overlay = self.args.region == "slurp" or self.args.ocr or self.args.qr
        if overlay and not self.args.slurp:
            mode = "ocr" if self.args.ocr else "qr" if self.args.qr else "edit" if self.args.edit else "region"
            if shell_call("screenshot", mode):
                return
        if self.args.ocr or self.args.qr:
            notify("-i", "dialog-error", "Screenshot", "OCR/QR needs the running shell")
            return
        if self.args.region:
            self.region()
        else:
            self.fullscreen()

    def select_region(self) -> str | None:
        """Region per slurp waehlen. Mit --freeze friert hyprpicker den Bildschirm
        ein, solange die Auswahl laeuft."""
        freezer = None
        if self.args.freeze:
            freezer = subprocess.Popen(["hyprpicker", "-r", "-z"], start_new_session=True)
            time.sleep(0.2)  # dem Standbild Zeit geben, sich aufzubauen

        try:
            region = subprocess.run(["slurp"], capture_output=True, text=True).stdout.strip()
        finally:
            if freezer:
                freezer.terminate()

        return region or None

    def region(self) -> None:
        region = self.args.region
        if region == "slurp":
            region = self.select_region()
            if not region:
                return  # abgebrochen

        sc_data = subprocess.check_output(["grim", "-l", "0", "-g", region.strip(), "-"])
        self.deliver(sc_data)

    def fullscreen(self) -> None:
        cmd = ["grim"]
        focused_monitor = next(monitor for monitor in hypr.message("monitors") if monitor["focused"])
        if focused_monitor:
            cmd += ["-o", focused_monitor["name"]]
        cmd += ["-"]
        self.deliver(subprocess.check_output(cmd))

    def deliver(self, sc_data: bytes) -> None:
        """Mit --edit direkt in swappy, sonst in die Zwischenablage plus
        Benachrichtigung mit Open/Save."""
        if self.args.edit:
            swappy = subprocess.Popen(["swappy", "-f", "-"], stdin=subprocess.PIPE, start_new_session=True)
            if swappy.stdin:
                swappy.stdin.write(sc_data)
                swappy.stdin.close()
            return

        subprocess.run(["wl-copy"], input=sc_data)

        dest: Path = screenshots_cache_dir / datetime.now().strftime("%Y%m%d%H%M%S")
        screenshots_cache_dir.mkdir(exist_ok=True, parents=True)
        dest.write_bytes(sc_data)

        def edit() -> None:
            subprocess.Popen(["swappy", "-f", dest], start_new_session=True)

        def save() -> None:
            new_dest = (screenshots_dir / dest.name).with_suffix(".png")
            new_dest.parent.mkdir(exist_ok=True, parents=True)
            dest.rename(new_dest)
            notify("-i", str(new_dest), "-h", f"STRING:image-path:{new_dest}", "Screenshot saved", str(new_dest))

        # Knoepfe brauchen notify-send --wait; das wartet abgekoppelt, damit
        # der Tastendruck nicht haengt
        notify_detached(
            [
                "-i",
                str(dest),
                "-h",
                f"STRING:image-path:{dest}",
                "-h",
                "boolean:x-dynamic-island-preview:true",
                "Screenshot copied",
                "",
            ],
            {"default": ("", edit), "save": ("Save", save), "edit": ("Edit", edit)},
        )
