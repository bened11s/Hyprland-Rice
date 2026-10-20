import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("telemetry", Path(__file__).with_name("telemetry.py"))
t = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t)
HEADER = "fps,frametime,cpu_load,gpu_load,gpu_vram_used,ram_used\n"
DATA = "60,16.67,25,80,1.5,5.25\n"


class TelemetryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.env = patch.dict(os.environ, {"XDG_RUNTIME_DIR": str(self.root)})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.session = t.runtime_root() / "game-test"
        self.session.mkdir(parents=True)
        self.log = self.session / "game.csv"
        self.log.write_text("os,cpu,gpu\nLinux,CPU,GPU\n" + HEADER + DATA)
        self.proc = self.root / "proc"
        self.pid = self.proc / "42"
        (self.pid / "fd").mkdir(parents=True)
        (self.pid / "environ").write_bytes(b"NOX_PERF_SESSION=" + os.fsencode(self.session) + b"\0")
        (self.pid / "fd" / "9").symlink_to(self.log)

    def snapshot(self, cls="steam_app_123"):
        return t.snapshot(42, cls, "Game", self.proc)

    def test_real_record(self):
        data = self.snapshot()["metrics"]
        self.assertEqual(data["fps"], 60)
        self.assertEqual(data["gpu_vram_used"], 1.5)
        self.assertIsNone(data["cpu_temp"])

    def test_partial_record_ignored(self):
        with self.log.open("a") as f:
            f.write("999,1,1,")
        self.assertEqual(self.snapshot()["metrics"]["fps"], 60)

    def test_stale(self):
        os.utime(self.log, (0, 0))
        self.assertIsNone(self.snapshot()["metrics"])

    def test_no_other_game_fallback(self):
        (self.pid / "fd" / "9").unlink()
        self.assertIsNone(self.snapshot()["metrics"])

    def test_ambiguous(self):
        other = self.session / "other.csv"
        other.write_text(HEADER + DATA)
        (self.pid / "fd" / "10").symlink_to(other)
        self.assertIsNone(self.snapshot()["metrics"])
        self.assertIn("nicht eindeutig", self.snapshot()["status"])

    def test_not_a_game(self):
        (self.pid / "environ").write_bytes(b"")
        self.assertFalse(self.snapshot("kitty")["game"])

    def test_registered_nonsteam_game(self):
        self.assertTrue(self.snapshot("my-native-game")["game"])

    def make_automatic(self):
        with (self.pid / "environ").open("ab") as f:
            f.write(b"NOX_PERF_AUTO=1\0")

    def test_auto_minecraft(self):
        self.make_automatic()
        data = self.snapshot("Minecraft* 1.21.8")
        self.assertTrue(data["game"])
        self.assertEqual(data["metrics"]["fps"], 60)

    def test_auto_native_game(self):
        self.make_automatic()
        self.assertTrue(self.snapshot("glxgears")["game"])

    def test_auto_launchers_not_games(self):
        self.make_automatic()
        for cls in ["steam", "steamwebhelper", "ModrinthApp", "com.modrinth.ModrinthApp"]:
            self.assertFalse(self.snapshot(cls)["game"])
            self.assertIsNone(self.snapshot(cls)["metrics"])

    def test_auto_helpers_without_renderer(self):
        self.make_automatic()
        (self.pid / "fd" / "9").unlink()
        self.assertFalse(self.snapshot("kitty")["game"])
        self.assertTrue(self.snapshot("Minecraft")["game"])

    def test_known_minecraft_without_session(self):
        (self.pid / "environ").write_bytes(b"")
        self.assertTrue(self.snapshot("Minecraft 1.21")["game"])

    def test_auto_launcher_mode(self):
        with patch.object(t.shutil, "which", return_value="/usr/bin/mangohud"), \
                patch.object(t, "launcher_running", return_value=False), \
                patch.object(t.os, "execvp") as execvp:
            t.launch(["/usr/bin/ModrinthApp"], automatic=True)
            self.assertEqual(os.environ["NOX_PERF_AUTO"], "1")
            execvp.assert_called_once_with("mangohud", ["mangohud", "/usr/bin/ModrinthApp"])

    def test_running_launcher_not_reconfigured(self):
        with patch.object(t.shutil, "which", return_value="/usr/bin/mangohud"), \
                patch.object(t, "launcher_running", return_value=True), \
                patch.object(t.os, "execv") as execv, patch.object(t.os, "execvp") as execvp:
            t.launch(["/usr/bin/steam", "steam://open/main"], automatic=True)
            execv.assert_called_once_with("/usr/bin/steam", ["/usr/bin/steam", "steam://open/main"])
            execvp.assert_not_called()

    def test_launcher_still_starts_without_mangohud(self):
        with patch.object(t.shutil, "which", return_value=None), patch.object(t.os, "execv") as execv:
            t.launch(["/usr/bin/steam"], automatic=True)
            execv.assert_called_once_with("/usr/bin/steam", ["/usr/bin/steam"])

    def test_unregistered_steam(self):
        (self.pid / "environ").write_bytes(b"")
        data = self.snapshot()
        self.assertTrue(data["game"])
        self.assertIsNone(data["metrics"])

    def test_arbitrary_path_rejected(self):
        (self.pid / "environ").write_bytes(b"NOX_PERF_SESSION=/etc\0")
        self.assertIsNone(t.session_for(42, self.proc))

    def test_invalid(self):
        for value in ["NaN", "inf", "-1", "garbage"]:
            self.log.write_text(HEADER + f"{value},16,1,1,1,1\n")
            self.assertIsNone(t.read_metrics(self.log))

    def test_large_log_bounded(self):
        self.log.write_text(HEADER + DATA * 10000)
        self.assertEqual(t.read_metrics(self.log)["fps"], 60)

    def test_reordered_header(self):
        self.log.write_text("frametime,gpu_load,fps\n12.5,90,80\n")
        self.assertEqual(t.read_metrics(self.log)["fps"], 80)

    def test_summary_not_used(self):
        (self.pid / "fd" / "9").unlink()
        (self.pid / "fd" / "10").symlink_to(self.session / "test_summary.csv")
        self.assertFalse(t.sources_for(42, self.session, self.proc))

    def test_missing_process(self):
        self.assertFalse(t.snapshot(9999, "kitty", "", self.proc)["game"])

    def test_launch_preserves_argv_and_options(self):
        with patch.dict(os.environ, {"MANGOHUD_CONFIG": "fps_limit=120", "__NV_PRIME_RENDER_OFFLOAD": "1"}), \
                patch.object(t.shutil, "which", return_value="/usr/bin/mangohud"), \
                patch.object(t.os, "execvp") as execvp:
            t.launch(["/a game/run", "argument with spaces", "$(not-a-shell)"])
            execvp.assert_called_once_with("mangohud", ["mangohud", "/a game/run", "argument with spaces", "$(not-a-shell)"])
            self.assertTrue(os.environ["MANGOHUD_CONFIG"].startswith("fps_limit=120,"))
            self.assertIn("log_interval=500", os.environ["MANGOHUD_CONFIG"])
            self.assertEqual(os.environ["__NV_PRIME_RENDER_OFFLOAD"], "1")

    def test_gamescope_child(self):
        (self.pid / "fd" / "9").unlink()
        child = self.proc / "43"
        (child / "fd").mkdir(parents=True)
        (child / "environ").write_bytes((self.pid / "environ").read_bytes())
        (child / "fd" / "8").symlink_to(self.log)
        task = self.pid / "task" / "42"
        task.mkdir(parents=True)
        (task / "children").write_text("43")
        self.assertEqual(self.snapshot("gamescope")["metrics"]["fps"], 60)


if __name__ == "__main__":
    unittest.main()
