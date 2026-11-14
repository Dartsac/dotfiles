"""./install, run against a throwaway repository of made-up packages, with an
empty home directory and a PATH holding only stow, the system tools and the
made-up tools a test installs. Then the repository's own manifests."""
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
INSTALL = REPO / "install"
PLATFORM = {"Darwin": "macos", "Linux": "linux"}[platform.system()]
HINTS = {"macos": "brew install {}", "linux": "sudo apt install {}"}


def dependency(command, required=True):
    return {"command": command, "required": required, "hint": {p: h.format(command) for p, h in HINTS.items()}}


@unittest.skipUnless(shutil.which("stow"), "needs stow")
class InstallTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve()
        self.repo = root / "dotfiles"
        self.home = root / "home"
        self.tools = root / "tools"
        for path in (self.repo, self.home, self.tools):
            path.mkdir()
        shutil.copy2(INSTALL, self.repo / "install")
        stow = shutil.which("stow")
        self.path = os.pathsep.join([str(self.tools), os.path.dirname(stow), "/usr/bin", "/bin"])

    def package(self, name, files, declared=True, **manifest):
        """A package with the given files (path -> text), and a manifest from the
        given fields when declared."""
        for path, text in files.items():
            target = self.repo / name / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        if declared:
            manifest.setdefault("description", f"{name} things")
            manifest.setdefault("role", "core")
            manifest.setdefault("platforms", ["macos", "linux"])
            manifest.setdefault("dependencies", [])
            (self.repo / name / "README.package.json").write_text(json.dumps(manifest))

    def install_tool(self, command):
        tool = self.tools / command
        tool.write_text("#!/bin/sh\n")
        tool.chmod(0o755)

    def links(self):
        """The links in the home directory (Apple's python3 may leave caches there too)."""
        return sorted(str(p.relative_to(self.home)) for p in self.home.rglob("*") if p.is_symlink())

    def install(self, *args):
        env = {"HOME": str(self.home), "PATH": self.path}
        return subprocess.run([str(self.repo / "install"), *args], cwd=self.home, env=env, capture_output=True, text=True)

    def test_without_arguments_lists_offered_packages_with_description_and_platforms(self):
        self.package("alpha", {".config/alpha/alpharc": ""}, description="Alpha's prompt", platforms=["macos", "linux"])
        self.package("beta", {".config/beta/rc": ""}, description="Beta's keys", role="optional", platforms=["macos"])
        self.package("own", {".own/settings": ""}, description="The owner's agent", role="owner")

        result = self.install()

        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        alpha = next(line for line in lines if line.split()[:1] == ["alpha"])
        self.assertIn("Alpha's prompt", alpha)
        self.assertIn("macOS, Linux", alpha)
        beta = next(line for line in lines if line.split()[:1] == ["beta"])
        self.assertIn("Beta's keys", beta)
        self.assertIn("macOS", beta)
        self.assertNotIn("Linux", beta)
        self.assertIn("optional", beta)
        self.assertNotIn("The owner's agent", result.stdout)
        owner = next(line for line in lines if "own" in line.split())
        self.assertIn("not offered", owner)
        self.assertEqual(self.links(), [])

    def test_stows_a_package_into_an_empty_home_without_linking_the_shared_directories(self):
        self.package("alpha", {".config/alpha/alpharc": "alpha\n", ".local/share/alpha/data": "data\n"})

        result = self.install("alpha")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for shared in (".config", ".local", ".local/share"):
            self.assertFalse((self.home / shared).is_symlink(), shared)
        self.assertEqual((self.home / ".config/alpha/alpharc").read_text(), "alpha\n")
        self.assertEqual((self.home / ".local/share/alpha/data").read_text(), "data\n")
        self.assertFalse((self.home / "README.package.json").exists())

    def test_names_each_missing_dependency_with_its_hint_for_this_platform_and_stows_anyway(self):
        deps = [dependency("alpha-tool"), dependency("alpha-extra", required=False), dependency("alpha-present")]
        self.package("alpha", {".config/alpha/alpharc": ""}, dependencies=deps)
        self.install_tool("alpha-present")

        result = self.install("alpha")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.home / ".config/alpha/alpharc").exists())
        tool = next(line for line in result.stdout.splitlines() if "alpha-tool" in line)
        self.assertIn(HINTS[PLATFORM].format("alpha-tool"), tool)
        self.assertIn("required", tool)
        extra = next(line for line in result.stdout.splitlines() if "alpha-extra" in line)
        self.assertIn(HINTS[PLATFORM].format("alpha-extra"), extra)
        self.assertIn("optional", extra)
        self.assertNotIn("alpha-present", result.stdout)

    def test_refuses_an_owner_package_and_stows_nothing(self):
        self.package("alpha", {".config/alpha/alpharc": ""})
        self.package("own", {".own/agent/settings": ""}, role="owner")

        result = self.install("alpha", "own")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("own", result.stderr)
        self.assertIn("--force", result.stderr)
        self.assertEqual(self.links(), [])

    def test_stows_an_owner_package_with_force_using_its_stow_flags(self):
        self.package("own", {".own/agent/settings": "s\n"}, role="owner", stow_flags=["--no-folding"])

        result = self.install("--force", "own")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.home / ".own/agent").is_symlink())
        self.assertTrue((self.home / ".own/agent/settings").is_symlink())

    def test_stows_a_platform_path_only_on_its_platforms(self):
        other = next(p for p in HINTS if p != PLATFORM)
        files = {".config/{0}/rc": "", "Library/Application Support/{0}/rc": ""}
        self.package("here", {k.format("here"): v for k, v in files.items()}, platform_paths={"Library": [PLATFORM]})
        self.package("there", {k.format("there"): v for k, v in files.items()}, platform_paths={"Library": [other]})

        result = self.install("here", "there")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.home / ".config/here/rc").exists())
        self.assertTrue((self.home / ".config/there/rc").exists())
        self.assertTrue((self.home / "Library/Application Support/here/rc").exists())
        self.assertFalse((self.home / "Library/Application Support/there").exists())

    def test_names_a_file_the_tool_reads_instead_of_the_package_and_leaves_it(self):
        other = next(p for p in HINTS if p != PLATFORM)
        self.package("alpha", {".config/alpha/alpharc": ""},
                     overridden_by={"Library/alpha/alpharc": [PLATFORM], "Library/alpha/elsewhere": [other],
                                    "Library/alpha/absent": [PLATFORM]})
        for name in ("alpharc", "elsewhere"):
            (self.home / "Library/alpha").mkdir(parents=True, exist_ok=True)
            (self.home / "Library/alpha" / name).write_text("mine\n")

        result = self.install("alpha")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.home / ".config/alpha/alpharc").exists())
        named = [line for line in result.stdout.splitlines() if "Library/alpha/" in line]
        self.assertEqual(len(named), 1, result.stdout)
        self.assertIn("~/Library/alpha/alpharc", named[0])
        self.assertEqual((self.home / "Library/alpha/alpharc").read_text(), "mine\n")

    def test_stops_with_stows_message_and_keeps_a_real_file_where_a_link_would_go(self):
        self.package("alpha", {".config/alpha/alpharc": "tracked\n"})
        mine = self.home / ".config/alpha/alpharc"
        mine.parent.mkdir(parents=True)
        mine.write_text("mine\n")

        result = self.install("alpha")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("alpharc", result.stderr)
        self.assertFalse(mine.is_symlink())
        self.assertEqual(mine.read_text(), "mine\n")

    def test_says_how_to_get_stow_when_it_is_missing(self):
        self.package("alpha", {".config/alpha/alpharc": ""})
        self.path = os.pathsep.join([str(self.tools), "/usr/bin", "/bin"])
        if shutil.which("stow", path=self.path):
            self.skipTest("stow is a system tool here")

        result = self.install("alpha")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(HINTS[PLATFORM].format("stow"), result.stderr)
        self.assertEqual(self.links(), [])

    def test_never_links_the_manifest_even_with_a_stow_global_ignore_list(self):
        # A global ignore list replaces stow's defaults, which skip README.*.
        (self.home / ".stow-global-ignore").write_text("\\.DS_Store\n")
        self.package("alpha", {".config/alpha/alpharc": ""})

        result = self.install("alpha")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.links(), [".config/alpha"])

    def test_skips_finders_ds_store_files_instead_of_stopping_on_them(self):
        self.package("alpha", {".config/alpha/alpharc": "", ".config/.DS_Store": "", ".DS_Store": ""})
        (self.home / ".config").mkdir()
        (self.home / ".config/.DS_Store").write_text("mine\n")

        result = self.install("alpha")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.links(), [".config/alpha"])
        self.assertEqual((self.home / ".config/.DS_Store").read_text(), "mine\n")

    def test_refuses_a_manifest_with_an_unknown_role(self):
        self.package("alpha", {".config/alpha/alpharc": ""}, role="ownr")

        result = self.install("alpha")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("alpha/README.package.json", result.stderr)
        self.assertIn("ownr", result.stderr)
        self.assertEqual(self.links(), [])

    def test_refuses_a_directory_that_declares_no_package(self):
        self.package("alpha", {".config/alpha/alpharc": ""})
        self.package("bare", {".config/bare/rc": ""}, declared=False)

        result = self.install("alpha", "bare", "nothing")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("bare", result.stderr)
        self.assertIn("nothing", result.stderr)
        self.assertEqual(self.links(), [])


class ManifestsTest(unittest.TestCase):
    """The repository's own dependency manifests, checked before CI sees them."""

    def setUp(self):
        self.manifests = {p.parent.name: json.loads(p.read_text()) for p in sorted(REPO.glob("*/README.package.json"))}

    def test_every_manifest_is_complete_for_each_platform_it_lists(self):
        self.assertTrue(self.manifests)
        for name, manifest in self.manifests.items():
            with self.subTest(package=name):
                self.assertIn(manifest["role"], ("core", "optional", "owner"))
                self.assertTrue(manifest["description"].strip())
                platforms = manifest["platforms"]
                self.assertTrue(platforms and set(platforms) <= {"macos", "linux"}, platforms)
                if manifest["role"] == "core":
                    self.assertEqual(sorted(platforms), ["linux", "macos"], "a core package is promised on both")
                for field in ("platform_paths", "overridden_by"):
                    for path, path_platforms in manifest.get(field, {}).items():
                        self.assertTrue(path_platforms and set(path_platforms) <= set(platforms), f"{field}: {path}")
                for dep in manifest["dependencies"]:
                    self.assertIsInstance(dep["required"], bool, dep["command"])
                    for platform_name in platforms:
                        self.assertTrue(dep["hint"].get(platform_name, "").strip(), f"{dep['command']}: no {platform_name} hint")

    def test_every_offered_package_has_a_standalone_check(self):
        spec = importlib.util.spec_from_file_location("standalone", REPO / ".tests/standalone.py")
        standalone = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(standalone)
        offered = {name for name, manifest in self.manifests.items() if manifest["role"] in ("core", "optional")}

        self.assertEqual(sorted(standalone.CHECKS), sorted(offered))


if __name__ == "__main__":
    unittest.main()
