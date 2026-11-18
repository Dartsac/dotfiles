"""The standalone check's own parts.

Its machine: git there never reaches the user's credentials. Its checks clone
public repositories (TPM's plugins, Neovim's), and a credential helper set
outside HOME, such as the macOS keychain in Homebrew's or Xcode's gitconfig,
would otherwise run for them.

Its run(): a command that runs out of time fails and names what is still
running, so a hang says what it is waiting for.

Its fish check: fish's first start leaves nothing running in the machine,
which the check removes once it is done."""
import importlib.util
import os
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
        self.machine = standalone.Machine(root, root / "dotfiles", [{"command": "git"}], {"git"})
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


@unittest.skipUnless(shutil.which("ps") and shutil.which("pkill"), "needs ps and pkill")
class RunTest(unittest.TestCase):
    def test_a_command_that_runs_out_of_time_names_what_is_still_running(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        home = Path(temp.name).resolve() / "home"
        home.mkdir()
        # A server the command starts and leaves, as tmux's is: no child of
        # the command, and waiting on a child of its own.
        server = home / "server.sh"
        server.write_text("trap 'kill $child' TERM\nsleep 301 &\nchild=$!\nwait\n")
        self.addCleanup(subprocess.run, ["pkill", "-f", str(server)], capture_output=True)
        env = {"HOME": str(home), "PATH": os.environ["PATH"]}

        with self.assertRaises(standalone.Failed) as failed:
            standalone.run(["sh", "-c", f'(sh "{server}" >/dev/null 2>&1 &); exec sleep 302'], env, home,
                           "a stuck command", timeout=2)

        message = str(failed.exception)
        self.assertIn("a stuck command: still running after 2s", message)
        self.assertIn("sleep 302", message)  # the command itself
        self.assertIn("sleep 301", message)  # what the server it started waits on


@unittest.skipUnless(shutil.which("fish") and shutil.which("stow") and shutil.which("pgrep"),
                     "needs fish, stow and pgrep")
class FishFirstStartTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(temp.cleanup)
        cls.clone = Path(temp.name).resolve() / "dotfiles"
        standalone.copy_tree(cls.clone)

    def test_starts_nothing_that_outlives_it(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve()
        # Before the folder goes: anything the check left running there.
        self.addCleanup(subprocess.run, ["pkill", "-f", str(root)], capture_output=True)
        manifest = standalone.manifests()["fish"]
        required = [d for d in manifest["dependencies"] if d["required"]]
        machine = standalone.Machine(root, self.clone, required, {d["command"] for d in required})
        self.assertEqual(machine.install("fish").returncode, 0)

        standalone.check_fish_first_start(machine, "fish's first start", machine.env)

        # fish reads the man pages into completions on its first start, in a
        # process it leaves running: one that outlives the check writes into
        # the machine while it is removed. It is done, or never started.
        running = subprocess.run(["pgrep", "-fl", str(root)], capture_output=True, text=True).stdout
        self.assertEqual(running, "", "still running in the machine as the check ends")
        generated = machine.home / ".cache/fish/generated_completions"
        made = len(list(generated.iterdir())) if generated.exists() else 0
        self.assertEqual(made, 0, "fish read the man pages into completions on its first start")

if __name__ == "__main__":
    unittest.main()
