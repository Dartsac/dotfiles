"""The standalone check's own parts.

Its machine: git there never reaches the user's credentials. Its checks clone
public repositories (TPM's plugins, Neovim's), and a credential helper set
outside HOME, such as the macOS keychain in Homebrew's or Xcode's gitconfig,
would otherwise run for them.

Its run(): a command that runs out of time fails and names what is still
running, so a hang says what it is waiting for.

Its fish check: fish's first start leaves nothing running in the machine,
which the check removes once it is done."""
import contextlib
import importlib.util
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from unittest import mock

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


def running_in(folder):
    """The processes with `folder`, or a path in it, among their arguments,
    also as an option's value (--directory=<path>): pid to arguments. A path
    that only begins or ends with the folder's name is not one."""
    listed = subprocess.run(["ps", "-axww", "-o", "pid=,args="], capture_output=True, text=True, check=True).stdout

    def names_it(word):
        return word == str(folder) or word.startswith(f"{folder}{os.sep}")
    return {int(pid): args for pid, _, args in (line.strip().partition(" ") for line in listed.splitlines())
            if any(names_it(word) for word in re.split(r"[\s=]", args))}


def remove_once_nothing_runs(folder, wait=5):
    """End every process running in `folder`, with TERM, then KILL, waiting
    up to `wait` seconds after each, and remove the folder once none is
    left. While one is, the folder stays, and this fails naming it: a folder
    is removed only once nothing writes into it."""
    for sent in (signal.SIGTERM, signal.SIGKILL):
        for pid in running_in(folder):
            with contextlib.suppress(ProcessLookupError):
                os.kill(pid, sent)
        deadline = time.monotonic() + wait
        while running_in(folder) and time.monotonic() < deadline:
            time.sleep(0.1)
        if not running_in(folder):
            shutil.rmtree(folder)
            return
    raise AssertionError(f"still running in {folder}, which stays:\n" + "\n".join(running_in(folder).values()))


@unittest.skipUnless(shutil.which("ps"), "needs ps")
class RemoveOnceNothingRunsTest(unittest.TestCase):
    def start(self, *args):
        """A shell that waits until it is ended, with `args` as its own."""
        process = subprocess.Popen(["sh", "-c", "while :; do sleep 1; done", "waits", *args], start_new_session=True)
        self.addCleanup(self.end_session, process)
        return process

    @staticmethod
    def end_session(process):
        """End the process and its sleep, which names no folder: the whole
        session it leads."""
        # PermissionError: macOS's, for a session only zombies are left in.
        with contextlib.suppress(ProcessLookupError, PermissionError):
            os.killpg(process.pid, signal.SIGKILL)
        process.wait()

    def setUp(self):
        self.folder = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, self.folder, ignore_errors=True)

    def test_ends_what_runs_in_the_folder_and_nothing_else(self):
        inside = [self.start(f"{self.folder}/wait.sh"), self.start(str(self.folder)),
                  self.start(f"--directory={self.folder}/cache")]
        outside = [self.start(f"{self.folder}-beside/wait.sh"), self.start(f"/elsewhere{self.folder}/wait.sh")]

        remove_once_nothing_runs(self.folder)

        self.assertFalse(self.folder.exists())
        for process in inside:
            self.assertIsNotNone(process.wait(timeout=5), process.args)
        for process in outside:
            self.assertIsNone(process.poll(), f"ended a process outside the folder: {process.args}")

    def test_keeps_a_folder_something_still_runs_in(self):
        self.start(f"{self.folder}/wait.sh")

        # As a process that no signal ends in time.
        with mock.patch.object(os, "kill"), self.assertRaises(AssertionError) as failed:
            remove_once_nothing_runs(self.folder, wait=0.2)

        self.assertIn(f"{self.folder}/wait.sh", str(failed.exception))
        self.assertTrue(self.folder.exists())


@unittest.skipUnless(shutil.which("fish") and shutil.which("stow") and shutil.which("ps"), "needs fish, stow and ps")
class FishFirstStartTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(temp.cleanup)
        cls.clone = Path(temp.name).resolve() / "dotfiles"
        standalone.copy_tree(cls.clone)

    def test_starts_nothing_that_outlives_it(self):
        root = Path(tempfile.mkdtemp()).resolve()
        # Anything the check left running there ends before the folder goes.
        self.addCleanup(remove_once_nothing_runs, root)
        manifest = standalone.manifests()["fish"]
        required = [d for d in manifest["dependencies"] if d["required"]]
        machine = standalone.Machine(root, self.clone, required, {d["command"] for d in required})
        self.assertEqual(machine.install("fish").returncode, 0)

        standalone.check_fish_first_start(machine, "fish's first start", machine.env)

        # fish reads the man pages into completions on its first start, in a
        # process it leaves running: one that outlives the check writes into
        # the machine while it is removed. It is done, or never started.
        self.assertEqual(running_in(root), {}, "still running in the machine as the check ends")
        generated = machine.home / ".cache/fish/generated_completions"
        made = len(list(generated.iterdir())) if generated.exists() else 0
        self.assertEqual(made, 0, "fish read the man pages into completions on its first start")


if __name__ == "__main__":
    unittest.main()
