#!/usr/bin/env python3
"""scripts/resurrect_save.py against real tmux-resurrect/continuum scripts, on
disposable tmux servers only (never the user's)."""
import fcntl
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / "scripts/resurrect_save.py"
PLUGINS = ROOT / "plugins"
sys.path.insert(0, str(ROOT / "scripts"))
sys.dont_write_bytecode = True  # no __pycache__ in scripts/
import resurrect_save  # noqa: E402


def align_second(margin=0.05):
    """Sleep to just after the start of a second."""
    time.sleep(1 - time.time() % 1 + margin)


class Server:
    def __init__(self, test, name, directory, panes=1):
        self.name = f"resurrect-save-test-{os.getpid()}-{name}"
        self.directory = directory
        self.start()
        self.socket = self.tmux(["display-message", "-p", "#{socket_path}"])
        test.addCleanup(Path(self.socket).unlink, missing_ok=True)  # kill-server leaves it
        test.addCleanup(self.tmux, ["kill-server"])
        for _ in range(panes - 1):
            self.tmux(["split-window", "-d"])
        # resurrect falls back to a default directory under HOME/XDG_DATA_HOME
        # when it can't read @resurrect-dir: keep that inside the test too.
        self.env = {**os.environ, "TMUX": f"{self.socket},0,0", "HOME": str(directory / "home"),
                    "XDG_DATA_HOME": str(directory / "home/share")}

    def start(self):
        self.tmux(["-f", "/dev/null", "new-session", "-d", "-x", "80", "-y", "24"])
        self.tmux(["set-option", "-g", "@resurrect-dir", str(self.directory)])

    def restart(self):
        """Replace the server with a new one (one pane) on the same socket."""
        self.tmux(["kill-server"])
        self.start()

    def tmux(self, args):
        return subprocess.run(["tmux", "-L", self.name, *args], capture_output=True, text=True).stdout.strip()

    def wrapper(self, *args, **kwargs):
        return subprocess.Popen([sys.executable, str(WRAPPER), *args], env=self.env, **kwargs)


class ResurrectSaveTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="resurrect-save-test-"))
        self.addCleanup(subprocess.run, ["rm", "-rf", str(self.dir)])

    def saves(self, directory=None):
        directory = directory or self.dir
        return {p.name: sum(1 for line in p.read_text().splitlines() if line.startswith("pane\t"))
                for p in sorted(directory.glob("tmux_resurrect_*.txt"))}

    def assert_last_valid(self, directory=None):
        last = (directory or self.dir) / "last"
        self.assertTrue(last.is_symlink())
        self.assertTrue(last.exists(), f"last -> {os.readlink(last)} is dangling")

    def test_reload_never_runs_resurrects_save_directly(self):
        # A reload re-runs resurrect.tmux, which resets the save and restore
        # routes; the config restores them only afterwards. Within that
        # interval, neither key nor continuum's autosave may reach resurrect's
        # scripts.
        t = Server(self, "reload", self.dir)
        for option, value in (("@resurrect-save", " "), ("@resurrect-restore", " "),
                              ("@continuum-save-interval", "0"), ("@continuum-save-last-timestamp", "0")):
            t.tmux(["set-option", "-g", option, value])
        t.tmux(["bind-key", "C-s", "run-shell", str(WRAPPER)])
        t.tmux(["bind-key", "C-r", "run-shell", f"{WRAPPER} restore"])
        subprocess.run(["bash", str(PLUGINS / "tmux-resurrect/resurrect.tmux")], env=t.env, check=True)
        self.assertIn("tmux-resurrect/scripts/save.sh", t.tmux(["show-option", "-gqv", "@resurrect-save-script-path"]))
        key = lambda key: t.tmux(["list-keys", "-T", "prefix", key]).split(None, 4)[-1]
        self.assertEqual(key("C-s"), f"run-shell {WRAPPER}")
        self.assertEqual(key("C-r"), f'run-shell "{WRAPPER} restore"')
        result = subprocess.run(["bash", str(PLUGINS / "tmux-continuum/scripts/continuum_save.sh")], env=t.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        time.sleep(1)  # continuum starts its save in the background
        self.assertEqual(self.saves(), {})

    def test_servers_sharing_a_directory_take_turns(self):
        one, two = Server(self, "one", self.dir, panes=1), Server(self, "two", self.dir, panes=2)
        align_second()
        workers = [one.wrapper("quiet"), two.wrapper("quiet")]
        self.assertEqual([w.wait(timeout=30) for w in workers], [0, 0])
        saves = self.saves()
        self.assertEqual(sorted(saves.values()), [1, 2], saves)  # two saves, neither interleaved
        self.assert_last_valid()

    def wait_until(self, done, interval=0.01, timeout=10):
        deadline = time.time() + timeout
        while not done():
            self.assertLess(time.time(), deadline)
            time.sleep(interval)

    def in_wrapper(self, t, code, *args, timeout=20):
        """Run `code` with the wrapper imported as resurrect_save, against t."""
        code = "import sys; sys.dont_write_bytecode = True; sys.path.insert(0, sys.argv[1]); " \
               "import resurrect_save; " + code
        return subprocess.run([sys.executable, "-c", code, str(ROOT / "scripts"), *args], env=t.env,
                              capture_output=True, text=True, timeout=timeout)

    def pause(self, t, hook, run):
        """Start the wrapper with `run` and wait until it reaches resurrect's
        `hook`, which then holds on (for at most 10s) until released. Returns
        the wrapper and a function that releases the hook."""
        paused, release = self.dir / "paused", self.dir / "release"
        paused.unlink(missing_ok=True)
        release.unlink(missing_ok=True)
        self.addCleanup(release.touch)
        q = lambda path: shlex.quote(str(path))
        t.tmux(["set-option", "-g", f"@resurrect-hook-{hook}",
                f"touch {q(paused)}; for _ in $(seq 500); do [ -e {q(release)} ] && break; sleep 0.02; done; true"])
        wrapper = t.wrapper(*run, start_new_session=True, stderr=subprocess.DEVNULL)  # restore: "no current client"
        self.wait_until(paused.exists)
        t.tmux(["set-option", "-gu", f"@resurrect-hook-{hook}"])
        return wrapper, release.touch

    def orphan_save(self, t, directory=None):
        """Start a save, pause it in a hook (its snapshot taken, as in a slow
        save) and kill only its wrapper there. Returns the orphaned save's
        pid and a function that lets it finish."""
        directory = directory or self.dir
        wrapper, release = self.pause(t, "post-save-layout", ["quiet"])
        pid = json.loads((directory / ".save-lock").read_text())["pid"]
        self.assertTrue(resurrect_save.running(pid))
        os.kill(wrapper.pid, signal.SIGKILL)
        wrapper.wait()
        return pid, release

    def wait_exit(self, pid):
        self.wait_until(lambda: not resurrect_save.running(pid))

    def test_wrapper_killed_mid_save_still_holds_off_the_next(self):
        t = Server(self, "killed", self.dir, panes=1)
        align_second()
        pid, release = self.orphan_save(t)
        t.tmux(["split-window", "-d"])  # the second save differs
        second = t.wrapper("quiet")
        time.sleep(0.3)  # starts while the orphaned save still runs
        self.assertIsNone(second.poll())
        release()
        self.assertEqual(second.wait(timeout=30), 0)
        saves = self.saves()
        self.assertEqual(list(saves.values()), [1, 2], saves)  # in that order, in distinct seconds
        self.assertEqual(os.readlink(self.dir / "last"), list(saves)[-1])
        self.assert_last_valid()

    def test_orphaned_save_finished_before_the_next_starts(self):
        # The record still names the orphaned save, which has exited: it
        # finished within this very second, so the next save must not.
        t = Server(self, "finished", self.dir)
        for _ in range(5):
            align_second()
            pid, release = self.orphan_save(t)
            release()
            self.wait_exit(pid)
            if time.strftime("tmux_resurrect_%Y%m%dT%H%M%S.txt") in self.saves() and time.time() % 1 < 0.7:
                break  # still the orphan's second, with time to spare
            for save in self.dir.glob("tmux_resurrect_*.txt"):
                save.unlink()
        else:
            self.fail("the orphaned save never finished within its own second")
        orphaned = self.saves()
        second = t.wrapper("quiet")
        self.assertEqual(second.wait(timeout=30), 0)
        self.assertEqual(len(self.saves()), 2, self.saves())  # its own file, not the orphan's
        self.assertNotIn(os.readlink(self.dir / "last"), orphaned)
        self.assert_last_valid()

    def test_directory_changed_while_waiting_saves_under_the_new_lock(self):
        old, new = self.dir / "old", self.dir / "new"
        old.mkdir()
        new.mkdir()
        t = Server(self, "moved", old)
        pid, release = self.orphan_save(t, old)
        with open(new / ".save-lock", "a+") as held:
            fcntl.flock(held, fcntl.LOCK_EX)  # another save in the new directory
            second = t.wrapper("quiet")

            def held_by_second():
                with open(old / ".save-lock") as probe:
                    try:
                        fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except BlockingIOError:
                        return True
                return False
            self.wait_until(held_by_second)  # the second save holds the old lock, waiting on the orphan
            t.tmux(["set-option", "-g", "@resurrect-dir", str(new)])
            release()
            self.wait_exit(pid)
            time.sleep(1.5)  # past its wait for a fresh second
            self.assertIsNone(second.poll())  # queued for the new directory's lock
            self.assertEqual(self.saves(new), {})
        self.assertEqual(second.wait(timeout=30), 0)
        self.assertEqual(list(self.saves(new).values()), [1])
        self.assert_last_valid(new)

    def test_server_replaced_while_queued(self):
        # A save asked of one server must not save a replacement started on
        # the same socket while it waited, nor even run save.sh against it:
        # save hooks act on the server (pane-clarity's edits its options).
        t = Server(self, "replaced", self.dir, panes=2)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        saved = self.saves()
        ran = self.dir / "hook-ran"
        with open(self.dir / ".save-lock", "a+") as held:
            fcntl.flock(held, fcntl.LOCK_EX)  # another save in progress
            queued = t.wrapper("quiet")
            time.sleep(1)  # past its first check, waiting
            self.assertIsNone(queued.poll())
            t.restart()
            t.tmux(["set-option", "-g", "@resurrect-hook-post-save-layout", f"touch {shlex.quote(str(ran))}"])
        self.assertEqual(queued.wait(timeout=20), 1)
        self.assertFalse(ran.exists())
        self.assertEqual(self.saves(), saved)
        self.assert_last_valid()

    def test_server_replaced_mid_save(self):
        # Nor a save during which the server was replaced: its hooks read the
        # server too (pane-clarity's rewrites the save's layouts from it).
        t = Server(self, "swapped", self.dir, panes=2)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        saved = self.saves()
        t.tmux(["split-window", "-d"])  # the next save differs
        save, release = self.pause(t, "post-save-layout", ["quiet"])
        t.restart()
        release()
        self.assertEqual(save.wait(timeout=20), 1)
        self.assertEqual(self.saves(), saved)
        self.assert_last_valid()

    def cut_saves(self, t, cut):
        """Have the post-save-layout hook (run just before save.sh would link
        `last`) cut each save short with `cut`, an expression of its `data`."""
        t.tmux(["set-option", "-g", "@resurrect-hook-post-save-layout", shlex.join(
            [sys.executable, "-c", f"import sys, pathlib; f = pathlib.Path(sys.argv[1]); data = f.read_bytes(); "
                                   f"f.write_bytes({cut})"])])

    def test_pruning_never_deletes_lasts_target(self):
        # resurrect prunes saves past 30 days (keeping the 5 newest) before
        # the wrapper decides on `last`, which may point at an older save
        # (resurrect documents choosing one to restore).
        t = Server(self, "prune", self.dir)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        content = (self.dir / "last").read_bytes()
        for save in self.dir.glob("tmux_resurrect_*.txt"):
            save.unlink()
        aged = self.aged_copies(content, range(36, 42), stamp="202609{:02}T000000")  # 36 to 41 days old
        (self.dir / "last").unlink()
        (self.dir / "last").symlink_to(aged[41])
        t.tmux(["split-window", "-d"])  # the next saves differ
        self.cut_saves(t, "data[:len(data) // 2]")
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 1)
        self.assertEqual(os.readlink(self.dir / "last"), aged[41])
        self.assert_last_valid()
        self.assertEqual(set(self.saves()), set(aged.values()))
        # A complete save does prune, as resurrect would: then `last` is it.
        t.tmux(["set-option", "-gu", "@resurrect-hook-post-save-layout"])
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        self.assert_last_valid()
        self.assertEqual(set(self.saves()), {os.readlink(self.dir / "last")} | {aged[d] for d in range(36, 40)})

    def aged_copies(self, content, ages, stamp="202608{:02}T000000"):
        """Saves with `content`, each `ages` days old; returns {age: name}."""
        names = {}
        for i, days in enumerate(ages):
            path = self.dir / f"tmux_resurrect_{stamp.format(i + 1)}.txt"
            path.write_bytes(content)
            then = time.time() - days * 86400
            os.utime(path, (then, then))
            names[days] = path.name
        return names

    def test_pruning_leaves_symlinks_and_their_targets(self):
        t = Server(self, "prune-links", self.dir)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        content = (self.dir / "last").read_bytes()
        self.aged_copies(content, range(36, 41))
        elsewhere = Path(tempfile.mkdtemp(prefix="resurrect-save-test-elsewhere-"))
        self.addCleanup(subprocess.run, ["rm", "-rf", str(elsewhere)])
        external = elsewhere / "old.txt"
        external.write_bytes(content)
        then = time.time() - 60 * 86400
        os.utime(external, (then, then))
        link = self.dir / "tmux_resurrect_20260701T000000.txt"
        link.symlink_to(external)
        t.tmux(["split-window", "-d"])  # the next save differs
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        self.assertTrue(external.exists())
        self.assertTrue(link.is_symlink() and link.exists())
        self.assert_last_valid()

    def test_rejected_save_prunes_nothing(self):
        # Rejected because its server was replaced mid-save: the replacement's
        # pruning setting (or anything else of it) must not apply.
        t = Server(self, "prune-swapped", self.dir)
        t.tmux(["set-option", "-g", "@resurrect-delete-backup-after", "365"])
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        content = (self.dir / "last").read_bytes()
        aged = self.aged_copies(content, [1, 2, 3, 4, 64, 65])
        t.tmux(["split-window", "-d"])  # the next save differs
        save, release = self.pause(t, "post-save-layout", ["quiet"])
        t.restart()  # resurrect's default: 30 days
        release()
        self.assertEqual(save.wait(timeout=20), 1)
        self.assertTrue(set(aged.values()) <= set(self.saves()), self.saves())
        self.assert_last_valid()

    def test_failed_save_prunes_nothing(self):
        # The same server and setting throughout: only the failure keeps the
        # saves pruning would otherwise delete (as the next good save does).
        t = Server(self, "prune-failed", self.dir)
        t.tmux(["set-option", "-g", "@resurrect-delete-backup-after", "30"])
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        content = (self.dir / "last").read_bytes()
        aged = self.aged_copies(content, [1, 2, 3, 4, 64, 65])
        before = set(self.saves())
        t.tmux(["split-window", "-d"])  # the next save differs
        self.cut_saves(t, "data[:data.rindex(b'state')]")
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 1)
        self.assertEqual(set(self.saves()), before)
        t.tmux(["set-option", "-gu", "@resurrect-hook-post-save-layout"])
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        self.assertEqual(before - set(self.saves()), {aged[64], aged[65]})
        self.assert_last_valid()

    def test_save_prunes_by_the_setting_it_started_with(self):
        # A good save on the same server: changing the setting mid-save
        # applies from the next save on, not to this one's pruning.
        t = Server(self, "prune-changed", self.dir)
        t.tmux(["set-option", "-g", "@resurrect-delete-backup-after", "365"])
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        content = (self.dir / "last").read_bytes()
        aged = self.aged_copies(content, [1, 2, 3, 4, 64, 65])
        t.tmux(["split-window", "-d"])  # the next save differs
        save, release = self.pause(t, "post-save-layout", ["quiet"])
        t.tmux(["set-option", "-g", "@resurrect-delete-backup-after", "30"])
        release()
        self.assertEqual(save.wait(timeout=20), 0)
        self.assertTrue(set(aged.values()) <= set(self.saves()), self.saves())
        before = set(self.saves())
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        self.assertEqual(before - set(self.saves()), {aged[64], aged[65]})
        self.assert_last_valid()

    def test_guard_never_marks_a_replacement(self):
        # The marker that admits a save's or restore's commands to a server
        # must never be set on a replacement, however late it's installed.
        t = Server(self, "guard", self.dir)
        old = t.tmux(["display-message", "-p", "#{pid}:#{start_time}"])
        t.restart()
        result = self.in_wrapper(t, "resurrect_save.guard(sys.argv[2])", old, timeout=10)
        self.assertIn("Unreachable", result.stderr)
        self.assertEqual(t.tmux(["show-option", "-gqv", "@resurrect-save-server-" + old.replace(":", "-")]), "")

    def test_save_never_reuses_an_existing_name(self):
        # Local time repeats (the clocks going back, a writer in another time
        # zone): saves already named for the coming seconds must survive.
        t = Server(self, "names", self.dir)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        content = (self.dir / "last").read_bytes()
        now = int(time.time())
        for second in range(now, now + 10):
            path = self.dir / time.strftime("tmux_resurrect_%Y%m%dT%H%M%S.txt", time.localtime(second))
            if not path.exists():
                path.write_bytes(content)
        existing = {path.name: path.read_bytes() for path in self.dir.glob("tmux_resurrect_*.txt")}
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        for name, data in existing.items():  # each untouched, whether or not the new save matched it
            self.assertTrue((self.dir / name).exists(), f"{name} was deleted")
            self.assertEqual((self.dir / name).read_bytes(), data, f"{name} was overwritten")
        self.assert_last_valid()

    def test_save_that_links_last_itself_fails_and_keeps_last(self):
        # tmux-shim/ln catches save.sh's exact `ln -fs NAME DIR/last`. If an
        # update changes that call, the real ln links each save unchecked
        # (and the wrapper, hearing of no link, would delete it under `last`).
        t = Server(self, "relinked", self.dir)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        old = os.readlink(self.dir / "last")
        changed = Path(tempfile.mkdtemp(prefix="resurrect-save-test-plugin-")) / "tmux-resurrect"
        self.addCleanup(shutil.rmtree, changed.parent)
        shutil.copytree(PLUGINS / "tmux-resurrect", changed, ignore=shutil.ignore_patterns(".git", "video"))
        save = changed / "scripts/save.sh"
        self.assertIn('ln -fs "$(basename', save.read_text())
        save.write_text(save.read_text().replace('ln -fs "$(basename', 'ln -sf "$(basename'))
        t.tmux(["split-window", "-d"])  # the next save differs
        result = self.in_wrapper(t, "resurrect_save.SAVE = sys.argv[2]; sys.exit(resurrect_save.main(['quiet']))",
                                 str(save))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("tmux-shim/ln", result.stderr)
        self.assertEqual(os.readlink(self.dir / "last"), old)
        self.assertEqual(set(self.saves()), {old})
        self.assert_last_valid()

    def test_incomplete_save_is_never_linked(self):
        # save.sh carries on past a failed write (a full disk, a file-size
        # limit), exits 0 and links what it wrote. Here its post-save-layout
        # hook, which runs just before that link, cuts the save short the way
        # a failed write would: mid-line, or without the final state line.
        t = Server(self, "short", self.dir)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        saved = self.saves()
        save = PLUGINS / "tmux-resurrect/scripts/save.sh"
        cuts = {"mid-line": "data[:len(data) // 2]", "no state line": "data[:data.rindex(b'state')]"}
        for name, cut in cuts.items():
            with self.subTest(name):
                t.tmux(["split-window", "-d"])  # the next save differs
                self.cut_saves(t, cut)
                self.assertEqual(t.wrapper("quiet").wait(timeout=20), 1)
                self.assertEqual(self.saves(), saved)
                self.assert_last_valid()
                # resurrect alone links the cut-short save: what the wrapper prevents.
                time.sleep(1)
                result = subprocess.run(["bash", str(save), "quiet"], env=t.env, capture_output=True, timeout=20)
                self.assertEqual(result.returncode, 0)
                self.assertFalse(resurrect_save.complete(self.dir / "last"))
                (self.dir / "last").unlink()
                (self.dir / "last").symlink_to(list(saved)[0])
                for extra in set(self.saves()) - set(saved):
                    (self.dir / extra).unlink()

    def test_autosave_during_restore_leaves_last_alone(self):
        # A restore reads `last` again and again; a save in between changes
        # what it restores.
        t = Server(self, "restoring", self.dir)
        saved = self.restore_setup(t)
        restoring, release = self.pause(t, "pre-restore-all", ["restore"])
        t.tmux(["set-option", "-g", "@resurrect-autosave-interval", "1"])
        t.tmux(["set-option", "-g", "@continuum-save-last-timestamp", str(int(time.time()) - 61)])
        auto = subprocess.run([sys.executable, str(WRAPPER), "auto"], env=t.env, capture_output=True, timeout=10)
        self.assertEqual(auto.returncode, 0)
        server = t.tmux(["display-message", "-p", "#{pid}:#{start_time}"])
        self.wait_until(lambda: subprocess.run(["pgrep", "-f", f"resurrect_save.py autosave {server}"],  # finished
                                               capture_output=True).returncode != 0, interval=0.05)
        self.assertEqual(self.saves(), saved)
        release()
        self.assertEqual(restoring.wait(timeout=30), 0)
        self.assertEqual(len(t.tmux(["list-panes", "-t", "work"]).splitlines()), 2)

    def restore_setup(self, t):
        """A save of session "work" (two panes), then "work" closed."""
        t.tmux(["new-session", "-d", "-s", "work", "-x", "80", "-y", "24"])
        t.tmux(["split-window", "-d", "-t", "work"])
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        t.tmux(["kill-session", "-t", "work"])
        return self.saves()

    def test_server_replaced_while_restore_queued(self):
        # Like a save, a restore asked of one server must not run against a
        # replacement on the same socket: not restore into it, nor run its hooks.
        t = Server(self, "restore-replaced", self.dir)
        saved = self.restore_setup(t)
        ran = self.dir / "hook-ran"
        with open(self.dir / ".save-lock", "a+") as held:
            fcntl.flock(held, fcntl.LOCK_EX)  # a save in progress
            queued = t.wrapper("restore", stderr=subprocess.DEVNULL)
            time.sleep(1)  # past its first check, waiting
            self.assertIsNone(queued.poll())
            t.restart()
            t.tmux(["set-option", "-g", "@resurrect-hook-pre-restore-all", f"touch {shlex.quote(str(ran))}"])
        self.assertEqual(queued.wait(timeout=20), 1)
        self.assertFalse(ran.exists())
        self.assertEqual(t.tmux(["list-sessions", "-F", "#{session_name}"]), "0")
        self.assertEqual(self.saves(), saved)

    def test_server_replaced_mid_restore(self):
        # Once a restore is under way, no further command may reach a
        # replacement on the same socket: restore.sh replaces existing panes.
        t = Server(self, "restore-swapped", self.dir, panes=2)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        restoring, release = self.pause(t, "pre-restore-all", ["restore"])
        t.restart()
        panes = t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"])
        release()
        self.assertEqual(restoring.wait(timeout=20), 1)
        self.assertEqual(t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"]), panes)

    def test_restore_wrapper_killed_still_holds_off_saves(self):
        t = Server(self, "restore-killed", self.dir)
        saved = self.restore_setup(t)
        restoring, release = self.pause(t, "pre-restore-all", ["restore"])
        pid = json.loads((self.dir / ".save-lock").read_text())["pid"]
        self.assertTrue(resurrect_save.running(pid))
        os.kill(restoring.pid, signal.SIGKILL)
        restoring.wait()
        autosave = t.wrapper("quiet")  # as an autosave would, or C-s
        time.sleep(1.5)
        self.assertIsNone(autosave.poll())  # waiting for the orphaned restore
        self.assertEqual(self.saves(), saved)
        release()
        self.wait_exit(pid)
        self.assertEqual(len(t.tmux(["list-panes", "-t", "work"]).splitlines()), 2)  # restored from `last`
        self.assertEqual(autosave.wait(timeout=20), 0)  # then saved
        self.assert_last_valid()

    def test_shim_pins_the_locked_directory(self):
        # @resurrect-dir changing after the wrapper's last check must not
        # move the save away from the directory it locked.
        t = Server(self, "pinned", self.dir)
        elsewhere = self.dir / "elsewhere"
        t.tmux(["set-option", "-g", "@resurrect-dir", str(elsewhere)])
        shimmed = {**t.env, "PATH": f"{resurrect_save.SHIM}:{os.environ['PATH']}",
                   "RESURRECT_SAVE_TMUX": shutil.which("tmux"), "RESURRECT_SAVE_DIR": str(self.dir)}
        subprocess.run(["bash", str(PLUGINS / "tmux-resurrect/scripts/save.sh"), "quiet"], env=shimmed,
                       start_new_session=True, check=True, capture_output=True, timeout=20)
        self.assertEqual(list(self.saves().values()), [1])
        self.assert_last_valid()
        self.assertFalse(elsewhere.exists())

    def test_server_gone_while_queued(self):
        t = Server(self, "queued", self.dir)
        with open(self.dir / ".save-lock", "a+") as held:
            fcntl.flock(held, fcntl.LOCK_EX)  # another save in progress
            queued = t.wrapper("quiet")
            time.sleep(1)  # past its first reachability check, waiting
            self.assertIsNone(queued.poll())
            t.tmux(["kill-server"])
        self.assertEqual(queued.wait(timeout=20), 1)
        self.assertEqual([p.name for p in self.dir.rglob("*") if p.is_file()], [".save-lock"])

    def test_shim_stops_a_save_whose_server_goes_away(self):
        # Past the wrapper's last check, only the shim stands between a
        # vanished server and resurrect saving an empty environment.
        t = Server(self, "vanish", self.dir)
        t.tmux(["kill-server"])
        save = PLUGINS / "tmux-resurrect/scripts/save.sh"
        real = shutil.which("tmux")
        shimmed = {**t.env, "PATH": f"{resurrect_save.SHIM}:{os.environ['PATH']}", "RESURRECT_SAVE_TMUX": real}
        result = subprocess.run(["bash", str(save), "quiet"], env=shimmed, start_new_session=True,
                                capture_output=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual([p for p in self.dir.rglob("*") if p.is_file()], [])
        # Unshimmed, resurrect does save an empty environment (in its default
        # directory, here under the test's HOME): what the shim prevents.
        subprocess.run(["bash", str(save), "quiet"], env=t.env, capture_output=True, timeout=20)
        written = [p for p in self.dir.rglob("tmux_resurrect_*.txt")]
        self.assertEqual([p.stat().st_size for p in written], [0])

    def test_lost_record_still_keeps_saves_apart(self):
        # Whatever happens to the record (a crash, a deleted lock file), the
        # next save must not share the previous save's second.
        t = Server(self, "record", self.dir)
        for damage in (b"", b"{garbage"):
            align_second()
            self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
            lock = self.dir / ".save-lock"
            self.assertEqual(lock.stat().st_size, resurrect_save.RECORD)  # replaced in place, never truncated
            lock.write_bytes(damage)
            t.tmux(["split-window", "-d"])  # the next save differs
            self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
            self.assert_last_valid()
        self.assertEqual(list(self.saves().values()), [1, 2, 3])

    def test_auto_saves_only_when_due(self):
        t = Server(self, "auto", self.dir)
        run = lambda: subprocess.run([sys.executable, str(WRAPPER), "auto"], env=t.env, capture_output=True,
                                     text=True, timeout=10)
        last = lambda: t.tmux(["show-option", "-gqv", "@continuum-save-last-timestamp"])
        self.assertEqual(run().stdout, "")  # no interval: off
        self.assertEqual(last(), "")
        t.tmux(["set-option", "-g", "@resurrect-autosave-interval", "1"])
        self.assertEqual(run().stdout, "")  # first load: only starts the clock
        self.assertTrue(last())
        time.sleep(1.5)
        self.assertEqual(self.saves(), {})
        t.tmux(["set-option", "-g", "@continuum-save-last-timestamp", str(int(time.time()) - 61)])
        self.assertEqual(run().stdout, "")
        self.wait_until((self.dir / "last").exists, interval=0.1)
        self.assertEqual(len(self.saves()), 1)
        self.assertGreaterEqual(int(last()), int(time.time()) - 10)
        lock = self.dir / ".save-lock"
        self.wait_until(lambda: not json.loads(lock.read_text() or "{}").get("pid"), interval=0.05)  # it runs on

    def test_no_save_without_a_reachable_server(self):
        t = Server(self, "gone", self.dir)
        t.tmux(["kill-server"])
        result = subprocess.run([sys.executable, str(WRAPPER), "quiet"], env=t.env, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        auto = subprocess.run([sys.executable, str(WRAPPER), "auto"], env=t.env, capture_output=True, timeout=10)
        self.assertEqual((auto.returncode, auto.stdout), (0, b""))
        written = [p for p in self.dir.rglob("*") if p.is_file()]
        self.assertEqual(written, [])

    def test_install_only_where_continuum_autosaves(self):
        t = Server(self, "install", self.dir)
        install = lambda: subprocess.run([sys.executable, str(WRAPPER), "install"], env=t.env, check=True)
        status = lambda: t.tmux(["show-option", "-gqv", "status-right"])
        t.tmux(["set-option", "-g", "status-right", " #h "])
        install()
        self.assertEqual(status(), "#h")  # another server's: continuum added nothing
        job = f"#({PLUGINS}/tmux-continuum/scripts/continuum_save.sh) #h "
        t.tmux(["set-option", "-g", "status-right", job])
        install()
        install()
        self.assertEqual(status(), (resurrect_save.AUTO + job).strip())


if __name__ == "__main__":
    unittest.main(verbosity=2)
