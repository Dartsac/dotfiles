"""theme-sync's guards against theme package colors in git, and the pre-commit
hook it installs, run against throwaway repositories with a made-up palette
(never the paid one)."""
from importlib.machinery import SourceFileLoader
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

THEME_SYNC = Path(__file__).resolve().parents[1] / "theme-sync"
# Made-up "package" colors. Greys and free Dracula colors are public.
PALETTE = {"pro": {"orange": "#c0ffee", "cyan": "#0a1b2c", "number": "#123456", "white": "#333333", "foreground": "#f8f8f2"}}
# Made-up values from the package's other theme files, outside the palette.
OTHER_VALUES = ["#beefed", "#444444", "#ff79c6"]
# A test file that fails, for commits the hook must refuse.
FAILING_TEST = "import unittest\nclass T(unittest.TestCase):\n    def test_it(self):\n        self.fail('broken on purpose')\n"
# macOS's own Python is 3.9: it has no tomllib, which came with 3.11.
SYSTEM_PYTHON_LACKS_TOMLLIB = os.access("/usr/bin/python3", os.X_OK) and subprocess.run(
    ["/usr/bin/python3", "-c", "import tomllib"], capture_output=True).returncode != 0


def load_theme_sync():
    """theme-sync as a module."""
    loader = SourceFileLoader("theme_sync", str(THEME_SYNC))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(module)
    return module


class ThrowawayRepo(unittest.TestCase):
    """A git repository and home directory in a temporary directory, with a made-up palette installed."""

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
        self.stage(files)
        self.git("commit", "-q", "--no-verify", "-m", message)
        return self.git("rev-parse", "HEAD")

    def stage(self, files):
        """Write and stage each file; a None text removes it."""
        for name, text in files.items():
            path = self.repo / name
            if text is None:
                self.git("rm", "-q", name)
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            self.git("add", name)

    def theme_sync(self, *args):
        return subprocess.run([str(THEME_SYNC), *args], cwd=self.repo, env=self.env, capture_output=True, text=True)


class ThemeSyncGuardTest(ThrowawayRepo):
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


    def write_palette_from_before_other_values(self):
        palette = self.home / ".local/share/theme-sync/palette.json"
        palette.write_text(json.dumps({"package": "dracula-pro-test", "variants": PALETTE}))

    def test_history_check_refuses_to_pass_on_a_palette_that_lacks_the_packages_other_values(self):
        self.commit({"README.md": "hello\n"})
        self.write_palette_from_before_other_values()

        result = self.theme_sync("--check-history")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("run theme-sync", result.stderr)

    def test_staged_check_still_guards_on_such_a_palette_and_says_to_run_theme_sync(self):
        self.commit({"README.md": "hello\n"})
        self.write_palette_from_before_other_values()
        (self.repo / "colors.conf").write_text("port = 123456\n")
        self.git("add", "colors.conf")
        clean = self.theme_sync("--check-staged")
        self.assertEqual(clean.returncode, 0)
        self.assertIn("run theme-sync", clean.stderr)

        (self.repo / "colors.conf").write_text("accent = #c0ffee\n")
        self.git("add", "colors.conf")

        self.assertEqual(self.theme_sync("--check-staged").returncode, 1)


class GhosttyVariantTest(unittest.TestCase):
    """The Dracula PRO variant theme-sync fills templates with: the one Ghostty
    uses, named by the last `theme =` line of its config or, read after it, of
    the local override."""

    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.theme_sync = load_theme_sync()
        self.theme_sync.GHOSTTY = Path(temp.name)
        (self.theme_sync.GHOSTTY / "config").write_text(
            "theme = Dracula\nconfig-file = ?config.local.ghostty\nfont-size = 14\n")

    def test_the_free_theme_alone_leaves_the_pro_variant(self):
        self.assertEqual(self.theme_sync.ghostty_variant(), "pro")

    def test_the_local_override_names_the_variant(self):
        (self.theme_sync.GHOSTTY / "config.local.ghostty").write_text(
            "theme = Dracula-Van-Helsing\n# theme = Dracula-Buffy\n")
        self.assertEqual(self.theme_sync.ghostty_variant(), "van-helsing")


class RootScriptsTest(unittest.TestCase):
    """A root script or a test file added without its wiring: nothing else
    fails. `land` went unlinted until its ruff.toml entry was noticed missing."""

    def setUp(self):
        self.repo = THEME_SYNC.parent
        self.scripts = sorted(path.name for path in self.repo.iterdir() if path.is_file()
                              and path.read_bytes()[:64].startswith(b"#!") and b"python" in path.read_bytes()[:64])

    def test_every_root_python_script_is_linted_and_tested_by_the_hook(self):
        self.assertIn("install", self.scripts)
        ruff = (self.repo / "ruff.toml").read_text()
        named = re.search(r"^scripts='([^']*)'$", load_theme_sync().HOOK, re.MULTILINE)
        self.assertTrue(named, "the pre-commit hook has no scripts='...' line")
        for script in self.scripts:
            with self.subTest(script=script):
                self.assertIn(f'"{script}"', ruff, "ruff.toml's extend-include does not name it")
                self.assertIn(script, named.group(1).split("|"), "the pre-commit hook's scripts do not name it")

    def test_every_test_file_runs_in_ci_and_in_linux_sh(self):
        tests = sorted(path.name for path in (self.repo / ".tests").glob("test_*.py"))
        self.assertIn("test_install.py", tests)
        for runner in (".github/workflows/standalone.yml", ".tests/linux.sh"):
            text = (self.repo / runner).read_text()
            for test in tests:
                with self.subTest(runner=runner, test=test):
                    self.assertIn(f".tests/{test}", text)


class PreCommitHookTest(ThrowawayRepo):
    """The hook theme-sync installs, run by a real commit in a copy of the repository layout."""

    def setUp(self):
        super().setUp()
        shutil.copy2(THEME_SYNC, self.repo / "theme-sync")
        # The rules the hook's ruff goes by. Without them a ruff that is
        # installed here applies its own defaults, which fault the sample files
        # below before the hook reaches the tests it is asked about.
        shutil.copy2(THEME_SYNC.parent / "ruff.toml", self.repo / "ruff.toml")
        hook = self.repo / ".git/hooks/pre-commit"
        hook.write_text(load_theme_sync().HOOK)
        hook.chmod(0o755)
        self.commit({"README.md": "hello\n"})

    def commit_with_hook(self, files):
        self.stage(files)
        return subprocess.run(["git", "commit", "-q", "-m", "change"], cwd=self.repo, env=self.env, capture_output=True, text=True)

    def test_hook_refuses_a_commit_when_a_test_in_the_hidden_test_directory_fails(self):
        result = self.commit_with_hook({".tests/test_example.py": FAILING_TEST})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("broken on purpose", result.stdout + result.stderr)

    def test_hook_lets_a_commit_through_when_the_hidden_test_directory_passes(self):
        passing = "import unittest\nclass T(unittest.TestCase):\n    def test_it(self):\n        pass\n"

        result = self.commit_with_hook({".tests/test_example.py": passing})

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_hook_runs_the_root_tests_when_the_install_script_is_staged(self):
        self.commit({".tests/test_example.py": FAILING_TEST})

        result = self.commit_with_hook({"install": "#!/usr/bin/env python3\n"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("broken on purpose", result.stdout + result.stderr)

    def test_hook_lints_the_land_script_and_runs_the_root_tests_when_it_is_staged(self):
        seen = self.fake_ruff(0)
        self.commit({".tests/test_example.py": FAILING_TEST})

        result = self.commit_with_hook({"land": "#!/usr/bin/env python3\n"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("broken on purpose", result.stdout + result.stderr)
        self.assertEqual(seen.read_text().split(), ["check", "--quiet", "land"])

    def test_hook_runs_the_root_tests_when_a_package_manifest_is_staged(self):
        self.commit({".tests/test_example.py": FAILING_TEST})

        result = self.commit_with_hook({"alpha/README.package.json": "{}\n"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("broken on purpose", result.stdout + result.stderr)

    def fake_ruff(self, exit_code):
        """Put a stand-in `ruff` first on PATH: it records its arguments, reports a problem and ends as told."""
        folder, seen = self.home / "bin", self.home / "ruff-arguments"
        folder.mkdir()
        ruff = folder / "ruff"
        ruff.write_text(f'#!/bin/sh\necho "$@" > "{seen}"\necho "F401 imported but unused"\nexit {exit_code}\n')
        ruff.chmod(0o755)
        self.env["PATH"] = f"{folder}{os.pathsep}{self.env['PATH']}"
        return seen

    def test_hook_refuses_a_commit_of_python_that_ruff_faults(self):
        seen = self.fake_ruff(1)

        result = self.commit_with_hook({"alpha/tool.py": "import os\n", "install": "#!/usr/bin/env python3\n", "notes.txt": "x\n"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("F401 imported but unused", result.stdout + result.stderr)
        self.assertEqual(seen.read_text().split(), ["check", "--quiet", "alpha/tool.py", "install"],
                         "the staged Python, root scripts included, and nothing else")

    def test_hook_lets_a_commit_of_python_through_when_ruff_passes_it(self):
        self.fake_ruff(0)

        result = self.commit_with_hook({"alpha/tool.py": "import os\n"})

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_hook_does_not_run_ruff_when_no_python_is_staged(self):
        seen = self.fake_ruff(1)

        result = self.commit_with_hook({"notes.txt": "x\n", "alpha/tool.py.md": "x\n"})

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(seen.exists())

    @unittest.skipIf(shutil.which("ruff", path="/usr/bin:/bin"), "needs a PATH without ruff")
    def test_hook_lets_a_commit_of_python_through_where_ruff_is_not_installed(self):
        self.env["PATH"] = "/usr/bin:/bin"

        result = self.commit_with_hook({"alpha/tool.py": "import os\n"})

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("node"), "needs node")
    def test_hook_runs_the_pi_extension_runner_from_the_hidden_test_directory(self):
        runner = "console.error('runner ran with ' + process.argv.slice(2).join(' '));\nprocess.exit(1);\n"

        result = self.commit_with_hook({".tests/pi-extensions.mjs": runner})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runner ran with --staged", result.stderr)

    def local_herdr_test(self, name, text):
        """A Herdr test as the owner's checkout has it: on disk, never in git."""
        path = self.repo / "herdr/.config/herdr/tests" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_hook_runs_herdrs_python_tests_when_a_herdr_file_is_staged(self):
        self.local_herdr_test("example_test.py", FAILING_TEST)

        result = self.commit_with_hook({"herdr/.config/herdr/faces/faces.py": "\n"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("broken on purpose", result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("node"), "needs node")
    def test_hook_runs_herdrs_node_tests_when_its_pi_extension_is_staged(self):
        self.local_herdr_test("example_test.py", FAILING_TEST)  # the Python tests are for the rest of Herdr
        self.local_herdr_test("example.test.mjs", "throw new Error('node test broken on purpose');\n")

        result = self.commit_with_hook({"herdr/.config/herdr/pi-extension/index.js": "\n"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("node test broken on purpose", result.stdout + result.stderr)
        self.assertNotIn("broken on purpose", (result.stdout + result.stderr).replace("node test broken on purpose", ""))

    def test_hook_runs_herdrs_tests_outside_the_commits_git_environment(self):
        # Herdr's tests make git repositories of their own; the commit's index must not reach them.
        self.local_herdr_test("example_test.py", "import os, unittest\nclass T(unittest.TestCase):\n    def test_it(self):\n"
                              "        self.assertNotIn('GIT_INDEX_FILE', os.environ)\n")

        result = self.commit_with_hook({"herdr/.config/herdr/faces/faces.py": "\n"})

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_hook_lints_herdrs_tests_which_no_other_lint_run_sees(self):
        seen = self.fake_ruff(1)
        self.local_herdr_test("example_test.py", "import os\n")
        self.local_herdr_test("notes.txt", "x\n")

        result = self.commit_with_hook({"herdr/.config/herdr/config.base.toml": "\n"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("F401 imported but unused", result.stdout + result.stderr)
        self.assertEqual(seen.read_text().split(), ["check", "--quiet", "herdr/.config/herdr/tests/example_test.py"])

    @unittest.skipUnless(SYSTEM_PYTHON_LACKS_TOMLLIB, "needs a /usr/bin/python3 older than 3.11, as macOS has")
    def test_hook_refuses_a_herdr_test_that_the_systems_python_cannot_load(self):
        # A commit from a GUI client runs Herdr's tests with /usr/bin/python3, where this one is an import error.
        self.local_herdr_test("example_test.py", "import tomllib, unittest\nclass T(unittest.TestCase):\n    def test_it(self):\n"
                              "        tomllib.loads('')\n")

        result = self.commit_with_hook({"herdr/.config/herdr/faces/faces.py": "\n"})

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("/usr/bin/python3 cannot load a Herdr test", result.stdout + result.stderr)
        self.assertIn("No module named 'tomllib'", result.stdout + result.stderr)

    def test_hook_lets_a_herdr_commit_through_in_a_checkout_without_herdrs_tests(self):
        result = self.commit_with_hook({"herdr/.config/herdr/faces/faces.py": "\n", "herdr/.config/herdr/pi-extension/index.js": "\n"})

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
