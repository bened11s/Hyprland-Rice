import os
import subprocess
from collections.abc import Callable


def notify(*args: str) -> str:
    return subprocess.check_output(["notify-send", "-a", "dynamic-island", *args], text=True).strip()


def notify_detached(args: list[str], actions: dict[str, tuple[str, Callable[[], None]]]) -> None:
    """notify-send mit Knoepfen ({key: (Beschriftung, Funktion)}). Wartet in
    einem abgekoppelten Enkelprozess auf die Antwort (notify-send --wait) und
    ruft dort die Funktion auf; der Aufrufer kehrt sofort zurueck."""
    if os.fork() != 0:
        return
    os.setsid()
    if os.fork() != 0:
        os._exit(0)
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    try:
        cmd = ["notify-send", "-a", "dynamic-island", "--wait"]
        cmd += [f"--action={key}={label}" for key, (label, _fn) in actions.items()]
        res = subprocess.run(cmd + args, capture_output=True, text=True)
        lines = res.stdout.strip().splitlines()
        chosen = lines[-1] if lines else ""
        if chosen in actions:
            actions[chosen][1]()
    finally:
        os._exit(0)


def close_notification(id: str) -> None:
    subprocess.run(
        [
            "gdbus",
            "call",
            "--session",
            "--dest=org.freedesktop.Notifications",
            "--object-path=/org/freedesktop/Notifications",
            "--method=org.freedesktop.Notifications.CloseNotification",
            id,
        ],
        stdout=subprocess.DEVNULL,
    )
