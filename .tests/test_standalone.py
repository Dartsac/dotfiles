"""The standalone check's machine: git there never reaches the user's
credentials. Its checks clone public repositories (TPM's plugins, Neovim's),
and a credential helper set outside HOME, such as the macOS keychain in
Homebrew's or Xcode's gitconfig, would otherwise run for them."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("standalone", REPO / ".tests/standalone.py")
standalone = importlib.util.module_from_spec(spec)
spec.loader.exec_module(standalone)


@unittest.skipUnless(shutil.which("git") and shutil.which("stow"), "needs git and stow")
class MachineGitTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve()
        self.machine = standalone.Machine(root, root / "dotfiles", ["git"], {"git"})
        # A helper of the machine's own, as any config file could name one.
        self.called = root / "helper-called"
        (self.machine.home / ".gitconfig").write_text(
            f"[credential]\n\thelper = \"!f() {{ echo \\\"$1\\\" >> '{self.called}'; }}; f\"\n")

    def git(self, *args, **options):
        # A session of its own: no controlling terminal for git to prompt on.
        return subprocess.run(["git", *args], env=self.machine.env, cwd=self.machine.home, capture_output=True,
                              text=True, start_new_session=True, **options)

    def helpers(self):
        """The credential helpers git would run, read without running any: an
        empty value clears those before it (git-config(1), credential.helper)."""
        helpers = []
        for value in self.git("config", "--get-all", "credential.helper").stdout.splitlines():
            if value:
                helpers.append(value)
            else:
                helpers.clear()
        return helpers

    def test_git_has_no_credential_helper(self):
        self.assertEqual(self.helpers(), [])

    def test_a_credential_request_runs_no_helper_and_asks_nothing(self):
        # Checked first, so that a helper never runs here, even when one is set.
        self.assertEqual(self.helpers(), [])
        result = self.git("credential", "fill", input="protocol=https\nhost=example.invalid\n\n", timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("terminal prompts disabled", result.stderr)
        self.assertFalse(self.called.exists(), "git ran a credential helper")


if __name__ == "__main__":
    unittest.main()
