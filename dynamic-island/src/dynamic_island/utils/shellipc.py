import subprocess

from dynamic_island.utils.paths import get_config


def shell_call(*args: str) -> bool:
    """`qs -c <shell> ipc call …` – True, wenn die laufende Shell den Aufruf
    angenommen hat (sonst laeuft sie nicht oder kennt ihn nicht)."""
    name = get_config().get("shell", {}).get("name", "dynamic-island")
    try:
        res = subprocess.run(["qs", "-c", name, "ipc", "call", *args], capture_output=True, timeout=3)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return res.returncode == 0
