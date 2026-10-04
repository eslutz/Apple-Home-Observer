import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = (Path(__file__).resolve().parents[1] / "script/rollback-on-mini.sh").read_text()
SELECTOR = re.search(r"<<'SELECT'\n(.*?)\nSELECT", SCRIPT, re.S).group(1)

class RollbackSelectionTests(unittest.TestCase):
    def run_selector(self, root):
        return subprocess.run([sys.executable, "-", str(root)], input=SELECTOR, text=True, capture_output=True)

    def records(self, root):
        old = root / "ffffffff-ffff-ffff-ffff-ffffffffffff"
        new = root / "00000000-0000-0000-0000-000000000001"
        old.mkdir(); new.mkdir()
        for record in (old, new):
            (record / "previous_app").write_text("1")
            (record / "previous_agent").write_text("0")
            (record / "AppleHomeObserver.app").mkdir()
        os.utime(old, (100, 100)); os.utime(new, (200, 200))
        return old, new

    def test_legacy_uses_install_time_not_uuid_sort_order(self):
        with tempfile.TemporaryDirectory(prefix="deployment proof ") as directory:
            root = Path(directory); _, new = self.records(root)
            result = self.run_selector(root)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.strip(), str(new))

    def test_pointer_identifies_last_successful_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); old, _ = self.records(root)
            (root / "latest").write_text(old.name + "\n")
            result = self.run_selector(root)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.strip(), str(old))

    def test_invalid_pointer_fails_without_choosing_another_record(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.records(root)
            (root / "latest").write_text("../outside")
            self.assertNotEqual(self.run_selector(root).returncode, 0)

    def test_symlink_predecessor_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); old, _ = self.records(root)
            link = root / "00000000-0000-0000-0000-000000000002"
            link.symlink_to(old, target_is_directory=True)
            (root / "latest").write_text(link.name)
            self.assertNotEqual(self.run_selector(root).returncode, 0)

    def test_incomplete_record_cannot_remove_the_installed_app(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); _, new = self.records(root)
            broken = root / "00000000-0000-0000-0000-000000000003"
            broken.mkdir()
            self.assertEqual(self.run_selector(root).stdout.strip(), str(new))
            (root / "latest").write_text(broken.name)
            self.assertNotEqual(self.run_selector(root).returncode, 0)
