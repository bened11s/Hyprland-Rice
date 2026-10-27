import os
import subprocess
from argparse import Namespace

from dynamic_island.utils.paths import c_cache_dir, get_config

# Name der Quickshell-Config (~/.config/quickshell/<name>).
# Ueber cli.json aenderbar:  {"shell": {"name": "..."}}
SHELL_NAME: str = get_config().get("shell", {}).get("name", "dynamic-island")

# glibc-Heap fuer die Shell: grosse Puffer (decodierte Wallpaper, Cover) per
# mmap holen, damit sie beim Freigeben sofort ans System zurueckgehen – mit
# der dynamischen Schwelle blieben sie im Heap und der RSS auf dem Hoechststand.
# Weniger Arenen, weil Quickshell ~45 Threads hat, die kaum parallel allozieren.
SHELL_ENV: dict[str, str] = {
    "MALLOC_ARENA_MAX": "2",
    "MALLOC_MMAP_THRESHOLD_": "1048576",
}


class Command:
    args: Namespace

    def __init__(self, args: Namespace) -> None:
        self.args = args

    def run(self) -> None:
        if self.args.show:
            # Print the ipc
            self.print_ipc()
        elif self.args.log:
            # Print the log
            self.print_log()
        elif self.args.kill:
            # Kill the shell
            self.shell("kill")
        elif self.args.message:
            # Send a message
            self.message(*self.args.message)
        else:
            # Start the shell
            args = ["qs", "-c", SHELL_NAME, "-n"]
            if self.args.log_rules:
                args.extend(["--log-rules", self.args.log_rules])
            env = os.environ | SHELL_ENV
            if self.args.daemon:
                # Selbst abkoppeln statt `qs -d`: im Daemon-Modus kommen
                # zusaetzliche Variablen (SHELL_ENV) beim gestarteten qs nicht
                # an – nachgemessen 2026-10-21
                subprocess.Popen(
                    args,
                    env=env,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
            else:
                shell = subprocess.Popen(args, stdout=subprocess.PIPE, universal_newlines=True, env=env)

                # Ensure stdout is not None for the type checker
                if shell.stdout:
                    for line in shell.stdout:
                        if self.filter_log(line):
                            print(line, end="")

    def shell(self, *args: str) -> str:
        return subprocess.check_output(["qs", "-c", SHELL_NAME, *args], text=True)

    def filter_log(self, line: str) -> bool:
        return f"Cannot open: file://{c_cache_dir}/imagecache/" not in line

    def print_ipc(self) -> None:
        print(self.shell("ipc", "show"), end="")

    def print_log(self) -> None:
        if self.args.log_rules:
            log = self.shell("log", "-r", self.args.log_rules)
        else:
            log = self.shell("log")
        # FIXME: remove when logging rules are added/warning is removed
        for line in log.splitlines():
            if self.filter_log(line):
                print(line)

    def message(self, *args: list[str]) -> None:
        print(self.shell("ipc", "call", *args), end="")
