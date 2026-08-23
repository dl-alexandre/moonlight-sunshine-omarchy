import importlib.machinery
import importlib.util
import io
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


LOADER = importlib.machinery.SourceFileLoader(
    "moonlight_sunshine",
    "bin/omarchy-moonlight-sunshine",
)
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
MODULE = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(MODULE)


class HardeningTests(unittest.TestCase):
    def test_discovery_command_output_is_bounded(self):
        output, timed_out, truncated = MODULE.run_bounded(
            [sys.executable, "-c", 'import sys; sys.stdout.write("x" * 1000000)'],
            timeout=5,
            max_bytes=4096,
        )
        self.assertEqual(len(output.encode()), 4096)
        self.assertFalse(timed_out)
        self.assertTrue(truncated)

    def test_discovery_rows_and_snapshot_are_bounded(self):
        avahi = "\n".join(
            f"= eth0 IPv4 host-{index} _nvstream._tcp local\n"
            " hostname = [host.local]\n"
            f" address = [192.168.1.{index % 255}]\n"
            " port = [47989]\n"
            for index in range(100)
        )
        self.assertLessEqual(len(MODULE.parse_avahi(avahi)), MODULE.MAX_DISCOVERY_RECORDS)

        output = io.BytesIO()
        original_stdout = sys.stdout
        try:
            sys.stdout = SimpleNamespace(buffer=output)
            MODULE.emit_json({"hosts": [{"name": "x" * 1000}] * 1000})
        finally:
            sys.stdout = original_stdout
        payload = output.getvalue()
        self.assertLessEqual(len(payload), MODULE.MAX_SNAPSHOT_BYTES + 1)
        json.loads(payload)

    def test_config_write_is_private_atomic_and_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            original_path = MODULE.CONFIG_PATH
            MODULE.CONFIG_PATH = Path(directory) / "moonlight-sunshine" / "hosts.json"
            try:
                MODULE.save_config({"activeProfile": "LAN", "profiles": {"LAN": {"hosts": {}}}})
                mode = os.stat(MODULE.CONFIG_PATH).st_mode & 0o777
                self.assertEqual(mode, 0o600)
                self.assertRaises(
                    RuntimeError,
                    MODULE.save_config,
                    {"large": "x" * MODULE.MAX_CONFIG_BYTES},
                )
                self.assertEqual(list(MODULE.CONFIG_PATH.parent.glob("*.tmp")), [])
            finally:
                MODULE.CONFIG_PATH = original_path

    def test_config_read_is_bounded_without_path_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            original_path = MODULE.CONFIG_PATH
            MODULE.CONFIG_PATH = Path(directory) / "moonlight-sunshine" / "hosts.json"
            try:
                with mock.patch.object(Path, "exists", side_effect=AssertionError), mock.patch.object(
                    Path, "stat", side_effect=AssertionError
                ):
                    config = MODULE.load_config()
                self.assertEqual(config["activeProfile"], "LAN")

                MODULE.CONFIG_PATH.parent.mkdir()
                MODULE.CONFIG_PATH.write_bytes(b"x" * (MODULE.MAX_CONFIG_BYTES + 1))
                with mock.patch.object(
                    MODULE.os,
                    "fstat",
                    return_value=SimpleNamespace(st_mode=stat.S_IFREG, st_size=0),
                ), self.assertRaisesRegex(RuntimeError, "exceeds"):
                    MODULE.load_config()
            finally:
                MODULE.CONFIG_PATH = original_path

    def test_config_read_rejects_symlinks_and_special_files(self):
        with tempfile.TemporaryDirectory() as directory:
            original_path = MODULE.CONFIG_PATH
            config_path = Path(directory) / "moonlight-sunshine" / "hosts.json"
            MODULE.CONFIG_PATH = config_path
            try:
                config_path.parent.mkdir()
                target = config_path.parent / "real-hosts.json"
                target.write_text('{"profiles":{"LAN":{"hosts":{}}}}', encoding="utf-8")
                config_path.symlink_to(target)
                with self.assertRaisesRegex(RuntimeError, "Cannot read"):
                    MODULE.load_config()

                config_path.unlink()
                fifo_path = config_path.parent / "hosts.fifo"
                os.mkfifo(fifo_path)
                MODULE.CONFIG_PATH = fifo_path
                with self.assertRaisesRegex(RuntimeError, "regular file"):
                    MODULE.load_config()
            finally:
                MODULE.CONFIG_PATH = original_path


if __name__ == "__main__":
    unittest.main()
