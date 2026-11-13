"""theme-sync's guards against theme package colors in git, run against
throwaway repositories with a made-up palette (never the paid one)."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

THEME_SYNC = Path(__file__).resolve().parents[1] / "theme-sync"
# Made-up "package" colors. Greys and free Dracula colors are public.
PALETTE = {"pro": {"orange": "#c0ffee", "cyan": "#0a1b2c", "number": "#123456", "white": "#333333", "foreground": "#f8f8f2"}}
# Made-up values from the package's other theme files, outside the palette.
OTHER_VALUES = ["#beefed", "#444444", "#ff79c6"]


class ThemeSyncGuardTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name) / "home"
        self.repo = Path(temp.name) / "repo"
        palette = self.home / ".local/share/theme-sync/palette.json"
        palette.parent.mkdir(parents=True)
        palette.write_text(json.dumps({"package": "dracula-pro-test", "variants": PALETTE, "other_values": OTHER_VALUES}))
        self.repo.mkdir()
        self.env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.home),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.com",
        }
        self.git("init", "-q", "-b", "main")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, env=self.env, check=True, capture_output=True, text=True).stdout.strip()

    def commit(self, files, message="change"):
        for name, text in files.items():
            path = self.repo / name
            if text is None:
                self.git("rm", "-q", name)
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            self.git("add", name)
        self.git("commit", "-q", "--no-verify", "-m", message)
        return self.git("rev-parse", "HEAD")

    def theme_sync(self, *args):
        return subprocess.run([str(THEME_SYNC), *args], cwd=self.repo, env=self.env, capture_output=True, text=True)

    def test_history_check_names_each_commit_and_file_holding_a_package_color(self):
        leaked = self.commit({"herdr/config.toml": 'accent = "#C0FFEE"\n', "README.md": "hello\n"})
        removed = self.commit({"herdr/config.toml": None})
        self.git("checkout", "-q", "-b", "side")
        side = self.commit({"tmux/colors.conf": "set -g fg 0a1b2c\n"})
        self.git("checkout", "-q", "main")

        result = self.theme_sync("--check-history")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(f"{leaked[:12]} herdr/config.toml", result.stdout)
        self.assertIn(f"{side[:12]} tmux/colors.conf", result.stdout)
        self.assertNotIn(removed[:12], result.stdout)
        self.assertNotIn("README.md", result.stdout)
        for value in ("c0ffee", "0a1b2c"):
            self.assertNotIn(value, (result.stdout + result.stderr).lower())


    def test_history_check_passes_when_only_public_colors_and_numbers_appear(self):
        self.commit({"colors.conf": "fg = #F8F8F2\nbg = #333333\nport = 123456\nplaceholder = {{removed}}\n"})

        result = self.theme_sync("--check-history")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


    def test_history_check_refuses_to_pass_without_an_installed_palette(self):
        self.commit({"colors.conf": "accent = #c0ffee\n"})
        (self.home / ".local/share/theme-sync/palette.json").unlink()

        result = self.theme_sync("--check-history")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("palette.json", result.stderr)


    def test_staged_check_refuses_a_package_color_but_not_a_free_dracula_one(self):
        self.commit({"README.md": "hello\n"})
        (self.repo / "colors.conf").write_text("fg = #f8f8f2\nport = 123456\n")
        self.git("add", "colors.conf")
        self.assertEqual(self.theme_sync("--check-staged").returncode, 0)

        (self.repo / "colors.conf").write_text("fg = #f8f8f2\naccent = #C0FFEE\n")
        self.git("add", "colors.conf")
        result = self.theme_sync("--check-staged")

        self.assertEqual(result.returncode, 1)
        self.assertIn("colors.conf:2: use {{orange}}", result.stdout)


    def test_history_check_also_names_values_from_the_package_outside_its_palette(self):
        leaked = self.commit({"fish/lean.fish": "set -g tide_color BEEFED\nset -g grey 444444\nset -g pink ff79c6\n"})

        result = self.theme_sync("--check-history")

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(f"{leaked[:12]} fish/lean.fish", result.stdout)
        self.assertNotIn("beefed", result.stdout.lower())

    def test_staged_check_refuses_a_value_from_the_package_outside_its_palette(self):
        self.commit({"README.md": "hello\n"})
        (self.repo / "lean.fish").write_text("set -g tide_color beefed\n")
        self.git("add", "lean.fish")

        result = self.theme_sync("--check-staged")

        self.assertEqual(result.returncode, 1)
        self.assertIn("lean.fish:1:", result.stdout)


if __name__ == "__main__":
    unittest.main()
