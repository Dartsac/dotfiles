#!/usr/bin/env python3
"""tmux.conf's automatic-rename-format, on disposable tmux servers only (never
the user's)."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FORMAT = re.search(r"^set -g automatic-rename-format '(.*)'$", (ROOT / "tmux.conf").read_text(), re.M).group(1)


class WindowNameTest(unittest.TestCase):
    def setUp(self):
        self.name = f"window-name-test-{os.getpid()}"
        self.directory = Path(tempfile.mkdtemp(prefix="window-name-test-")) / "dotfiles"
        self.directory.mkdir()
        self.addCleanup(subprocess.run, ["rm", "-rf", str(self.directory.parent)])
        self.tmux("-f", "/dev/null", "new-session", "-d", "-c", str(self.directory), "cat")
        socket = self.tmux("display-message", "-p", "#{socket_path}")
        self.addCleanup(Path(socket).unlink, missing_ok=True)  # kill-server leaves it
        self.addCleanup(self.tmux, "kill-server")  # by exact name only

    def tmux(self, *args):
        return subprocess.run(["tmux", "-L", self.name, *args], capture_output=True, text=True).stdout.rstrip("\n")

    def window_name(self, title):
        """What tmux names the window (on its own schedule) for pane `title`."""
        self.tmux("select-pane", "-T", title)
        return self.tmux("display-message", "-p", FORMAT)

    def test_pi_titles(self):
        cases = {
            "π - dotfiles": "π",  # only the directory: just the symbol
            "π - work - dotfiles": "π - work",  # the directory suffix goes
            "π - mysession": "π - mysession",  # no directory suffix: kept whole
            "π - elsewhere": "π - elsewhere",  # another directory: kept whole
            "π - work - elsewhere": "π - work - elsewhere",
            "π": "π",
            "vim": "cat",  # not Pi: the command
        }
        for title, name in cases.items():
            with self.subTest(title):
                self.assertEqual(self.window_name(title), name)


if __name__ == "__main__":
    unittest.main()
