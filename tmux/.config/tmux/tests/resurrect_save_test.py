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
        self.control = Path(tempfile.mkdtemp(prefix="resurrect-save-control-"))  # outside the backup directory
        self.addCleanup(subprocess.run, ["rm", "-rf", str(self.control)])

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
        paused, release = self.control / "paused", self.control / "release"
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

    @staticmethod
    def drop(kind, nth):
        """A cut_saves expression: the save without its `nth` `kind` record."""
        lines = "data.splitlines(True)"
        return (f"b''.join(l for i, l in enumerate({lines}) if i != "
                f"[i for i, l in enumerate({lines}) if l.startswith(b'{kind}\\t')][{nth}])")

    def grouped_setup(self, t):
        """Three panes, two windows and a grouped session (whose panes and
        windows resurrect doesn't save: it records the session instead)."""
        t.tmux(["split-window", "-d"])
        t.tmux(["split-window", "-d"])
        t.tmux(["new-window", "-d"])
        t.tmux(["new-session", "-d", "-t", t.tmux(["display-message", "-p", "#{session_name}"]), "-s", "twin"])

    def test_save_with_grouped_sessions_is_linked(self):
        t = Server(self, "grouped", self.dir)
        self.grouped_setup(t)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        self.assert_last_valid()
        text = (self.dir / "last").read_text()
        self.assertEqual([line.split("\t")[1] for line in text.splitlines() if line.startswith("grouped_session")], ["twin"])

    def test_save_missing_a_record_is_never_linked(self):
        # Each part of a save is a separate write: one that fails (a full
        # disk) loses its records, and the parts after it can still succeed,
        # state line and all. Here the post-save-layout hook drops one record.
        t = Server(self, "records", self.dir)
        self.grouped_setup(t)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        saved = self.saves()
        good = (self.dir / "last").read_bytes()
        for kind, nth in (("pane", 1), ("window", 0), ("grouped_session", 0)):
            with self.subTest(kind):
                t.tmux(["split-window", "-d"])  # the next save differs
                self.cut_saves(t, self.drop(kind, nth))
                self.assertEqual(t.wrapper("quiet").wait(timeout=20), 1)
                self.assertEqual(self.saves(), saved)
                self.assert_last_valid()
                # What the file's shape alone would have let through.
                cut = self.dir / "cut.txt"
                subprocess.run([sys.executable, "-c", f"import pathlib; data = pathlib.Path('{self.dir}/last').read_bytes(); "
                                f"pathlib.Path('{cut}').write_bytes({self.drop(kind, nth)})"], check=True)
                self.assertTrue(resurrect_save.complete(cut))
                self.assertLess(len(cut.read_bytes()), len(good))
                cut.unlink()

    def test_save_the_shim_cannot_check_fails_loudly(self):
        # tmux-shim/tmux no longer recognizing save.sh's lists (after a
        # tmux-resurrect update, say) looks like this: no copies of them.
        t = Server(self, "unchecked", self.dir)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        saved = self.saves()
        t.tmux(["split-window", "-d"])
        # (resurrect appends the save's path to the hook: `:` takes it.)
        t.tmux(["set-option", "-g", "@resurrect-hook-post-save-layout", 'rm -f "$RESURRECT_SAVE_RECORDS"/*; :'])
        wrapper = t.wrapper("quiet", stderr=subprocess.PIPE, text=True)
        _, error = wrapper.communicate(timeout=20)
        self.assertEqual(wrapper.returncode, 1)
        self.assertIn("tmux-shim/tmux no longer sees save.sh's pane and window lists", error)
        self.assertEqual(self.saves(), saved)
        self.assert_last_valid()

    def test_shim_never_keeps_a_list_copy_cut_short_as_a_whole_one(self):
        # A copy cut short (a full disk) would require too little of the save:
        # it stays .partial, which the wrapper rejects.
        records = self.dir / "records"
        records.mkdir()
        fake = self.dir / "fake-tmux"
        fake.write_text("#!/bin/sh\necho guard\nfor i in $(seq 2000); do printf 'pane\\tmain\\t1\\t1\\t:*\\t%s\\n' $i; done\n")
        fake.chmod(0o755)
        env = {**os.environ, "RESURRECT_SAVE_TMUX": str(fake), "RESURRECT_SAVE_GUARD": "@guard",
               "RESURRECT_SAVE_RECORDS": str(records)}
        shim = ROOT / "scripts/tmux-shim/tmux"
        subprocess.run(["bash", "-c", 'ulimit -f 8; "$0" list-panes -a -F "pane$(printf "\\t")x"', str(shim)],
                       env=env, capture_output=True, timeout=20)
        self.assertEqual(sorted(p.name for p in records.iterdir()), ["panes.partial"])
        self.assertFalse(resurrect_save.holds_every_record(self.dir / "any", records))

    def test_a_list_copy_not_written_in_full_is_never_trusted(self):
        # Even beside a .partial whose rename failed, a short copy is rejected.
        records = self.dir / "records"
        records.mkdir()
        save = self.dir / "save.txt"
        save.write_text("pane\tmain\t0\t1\t:*\t0\tt\t:/\t1\tsh\t:\nwindow\tmain\t0\t:sh\t1\t:*\tlayout\t:\nstate\tmain\t\n")
        (records / "panes").write_text("pane\tmain\t0\t1\t:*\t0\tt\t:/\t1\tsh\t1\t0\n")
        (records / "windows").write_text("window\tmain\t0\t:sh\t1\t:*\tlayout\n")
        self.assertTrue(resurrect_save.holds_every_record(save, records))
        (records / "panes.partial").write_text("pane\tmain\t0\t1\t:*\t0\tt\t:/\t1\tsh\t1\t0\npane\tmain\t0")
        self.assertFalse(resurrect_save.holds_every_record(save, records))

    def settled(self, t):
        """Wait for the window's name to follow its shell, which starts after
        the server: until then each save differs from the one before."""
        name = lambda: t.tmux(["display-message", "-p", "#{==:#{window_name},#{pane_current_command}}"]) == "1"
        self.wait_until(name)

    def test_unchanged_save_succeeds(self):
        t = Server(self, "unchanged-ok", self.dir, panes=2)
        self.settled(t)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        saved = self.saves()
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)  # deleted by save.sh as unchanged
        self.assertEqual(self.saves(), saved)
        self.assert_last_valid()

    def test_unchanged_save_missing_records_fails_and_prunes_nothing(self):
        # save.sh deletes a save no different from `last`'s, and links
        # nothing. A new window whose records were lost makes it look so.
        t = Server(self, "unchanged", self.dir)
        self.settled(t)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        last = os.readlink(self.dir / "last")
        old = self.aged_copies((self.dir / "last").read_bytes(), [60, 61, 62, 63, 64, 65])  # prunable
        session = t.tmux(["display-message", "-p", "#{session_name}"])
        window = t.tmux(["new-window", "-d", "-P", "-F", "#{window_index}"])
        lost = (f"pane\t{session}\t{window}\t", f"window\t{session}\t{window}\t")
        self.cut_saves(t, f"b''.join(l for l in data.splitlines(True) if not l.decode().startswith({lost!r}))")
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 1)
        self.assertEqual(os.readlink(self.dir / "last"), last)
        self.assertTrue(all((self.dir / name).exists() for name in old.values()))

    def test_unchanged_save_the_shim_cannot_check_fails_loudly(self):
        t = Server(self, "unchanged-unchecked", self.dir)
        self.settled(t)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        t.tmux(["set-option", "-g", "@resurrect-hook-post-save-layout", 'rm -f "$RESURRECT_SAVE_RECORDS"/*; :'])
        wrapper = t.wrapper("quiet", stderr=subprocess.PIPE, text=True)
        _, error = wrapper.communicate(timeout=20)
        self.assertEqual(wrapper.returncode, 1)
        self.assertIn("tmux-shim/tmux no longer sees save.sh's pane and window lists", error)

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
        # And all of the run stops, the spinner included: its TERM trap runs
        # tmux, which stops the group again (rerunning that trap forever, in
        # Bash 5.3). Nothing about that is kept in the backup directory, so
        # neither an earlier stopped run nor a directory that can't be
        # written to changes it.
        t = Server(self, "restore-swapped", self.dir, panes=2)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        for run in ("first", "again", "read-only directory"):
            with self.subTest(run):
                restoring, release = self.pause(t, "pre-restore-all", ["restore"])
                group = json.loads((self.dir / ".save-lock").read_text())["pid"]  # leads the run's group
                # A regression leaves the group running: end it after the test either way.
                self.addCleanup(lambda group=group: subprocess.run(["pkill", "-KILL", "-g", str(group)]))
                if run == "read-only directory":
                    self.dir.chmod(0o500)
                    self.addCleanup(self.dir.chmod, 0o700)
                t.restart()
                t.tmux(["split-window", "-d"])
                panes = t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"])
                release()
                self.assertEqual(restoring.wait(timeout=20), 1)
                self.assertEqual(t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"]), panes)
                alive = lambda: subprocess.run(["pgrep", "-g", str(group)], capture_output=True).returncode == 0
                self.wait_until(lambda: not alive(), timeout=5)
                self.dir.chmod(0o700)

    def test_restore_whose_wrapper_died_still_ends_its_group(self):
        # The leader then has no wrapper to finish it: it ends the group itself.
        t = Server(self, "restore-orphaned", self.dir, panes=2)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        restoring, release = self.pause(t, "pre-restore-all", ["restore"])
        group = json.loads((self.dir / ".save-lock").read_text())["pid"]
        self.addCleanup(lambda: subprocess.run(["pkill", "-KILL", "-g", str(group)]))
        os.kill(restoring.pid, signal.SIGKILL)
        restoring.wait()
        t.restart()
        panes = t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"])
        release()
        alive = lambda: subprocess.run(["pgrep", "-g", str(group)], capture_output=True).returncode == 0
        self.wait_until(lambda: not alive(), timeout=5)
        self.assertEqual(t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"]), panes)

    def delayed_spinner(self, t, message):
        """Put a tmux first on t's PATH (the wrapper's real tmux, then) that,
        once `arm` exists, holds the spinner's last call (its TERM trap's
        `message`) until `release` exists. save.sh exports SPINNER_PID after
        starting the spinner: only its own calls have it. Returns (arm, held,
        release)."""
        tools = self.control / "tools"
        tools.mkdir()
        arm, held, release = (self.control / name for name in ("arm", "held", "release-spinner"))
        q = lambda path: shlex.quote(str(path))
        (tools / "tmux").write_text(
            "#!/bin/sh\n"
            f'case " $* " in *" {message} "*) if [ -e {q(arm)} ] && [ -z "$SPINNER_PID" ]; then\n'
            f"  touch {q(held)}; i=0\n"
            f"  while [ ! -e {q(release)} ] && [ $i -lt 1500 ]; do sleep 0.01; i=$((i + 1)); done\n"
            "fi ;; esac\n"
            f'exec {q(shutil.which("tmux"))} "$@"\n')
        (tools / "tmux").chmod(0o700)
        t.env["PATH"] = f"{tools}{os.pathsep}{t.env['PATH']}"
        self.addCleanup(release.touch)
        return arm, held, release

    LATE_SPINNERS = ((["restore"], "post-restore-all", "Tmux restore complete!"),
                     ([], "post-save-all", "Tmux environment saved!"))

    def late_spinner(self, run, hook, message):
        """A server, and `run` on it (a restore, or a save with a spinner)
        whose hook `hook` leaves a background job (`tail -f` of the spinner's
        script: not a spinner for only naming it) and whose spinner's last
        call is held (delayed_spinner). Returns the server, the wrapper, the
        run's group, the job's pid, `last` before, and the release file."""
        shutil.rmtree(self.control / "tools", ignore_errors=True)
        t = Server(self, f"late-spinner-{len(run)}", self.dir, panes=2)
        self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
        previous = os.readlink(self.dir / "last")
        t.tmux(["rename-window", "changed"])  # a new save, not one found unchanged
        arm, held, release = self.delayed_spinner(t, message)
        background = self.control / "background"
        background.unlink(missing_ok=True)
        t.tmux(["set-option", "-g", f"@resurrect-hook-{hook}",
                f"tail -f {shlex.quote(resurrect_save.SPINNER)} >/dev/null 2>&1 & "
                f"echo $! > {shlex.quote(str(background))}"])
        for path in (arm, held, release):
            path.unlink(missing_ok=True)
        wrapper, resume = self.pause(t, "pre-restore-all" if run else "post-save-layout", run)
        group = json.loads((self.dir / ".save-lock").read_text())["pid"]
        self.addCleanup(lambda: subprocess.run(["pkill", "-KILL", "-g", str(group)]))
        arm.touch()
        resume()
        self.wait_until(held.exists)
        time.sleep(0.5)
        self.assertIsNone(wrapper.poll(), "the run ended before its spinner")
        job = int(background.read_text())
        self.addCleanup(lambda: subprocess.run(["kill", "-KILL", str(job)], stderr=subprocess.DEVNULL))
        t.tmux(["set-option", "-gu", f"@resurrect-hook-{hook}"])  # no untracked jobs from later runs
        return t, wrapper, group, job, previous, release

    def assert_only_job_left(self, group, job):
        members = subprocess.run(["pgrep", "-g", str(group)], capture_output=True, text=True).stdout.split()
        self.assertEqual(members, [str(job)])  # the spinner and its calls gone, the hook's job kept

    def test_successful_run_waits_for_its_spinner(self):
        # resurrect stops its spinner without waiting, and the spinner's trap
        # then makes a last tmux call: the run lasts until that ends. By then
        # the server can be replaced. That call then fails, and must neither
        # stop the group (left looping in Bash 5.3, and taking a hook's
        # background job with it) nor fail the run, whose part is done.
        for run, hook, message in self.LATE_SPINNERS:
            with self.subTest(" ".join(run) or "manual save"):
                t, wrapper, group, job, previous, release = self.late_spinner(run, hook, message)
                t.restart()
                panes = t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"])
                started = time.monotonic()
                release.touch()
                self.assertEqual(wrapper.wait(timeout=20), 0)
                self.assertLess(time.monotonic() - started, 3, "the spinner had to be killed")
                self.assert_only_job_left(group, job)
                self.assertEqual(t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"]), panes)
                if not run:
                    self.assertNotEqual(os.readlink(self.dir / "last"), previous)
                    self.assert_last_valid()

    def test_spinner_still_running_is_killed_with_its_calls(self):
        # Its last call never returns (a hung server, say): after 5s the
        # spinner is killed, and with it everything that call started
        # (tmux-shim/tmux's tmux client and tail, here a held one), which
        # would otherwise keep the run's output open. Nothing else is.
        for run, hook, message in self.LATE_SPINNERS:
            with self.subTest(" ".join(run) or "manual save"):
                t, wrapper, group, job, previous, release = self.late_spinner(run, hook, message)
                self.assertEqual(wrapper.wait(timeout=20), 0)
                self.assert_only_job_left(group, job)
                if not run:
                    self.assertNotEqual(os.readlink(self.dir / "last"), previous)
                    self.assert_last_valid()

    def test_spinner_whose_wrapper_died_is_finished_by_the_next_run(self):
        # The wrapper dies after the leader has ended: while it waits for the
        # spinner, or in the middle of killing it (here: exiting just after
        # its first stop or kill). The lock record still names the leader,
        # whose id the spinner's group keeps: the next run finishes the job,
        # at once for a spinner left stopped.
        interrupt = ("import os, signal, sys; kill = os.kill\n"
                     "def cut(pid, signum):\n"
                     "    kill(pid, signum)\n"
                     "    if signum == getattr(signal, sys.argv[2]): os._exit(9)\n"
                     "os.kill = cut; resurrect_save.spinner_finished(int(sys.argv[3]), timeout=0)")
        for (run, hook, message), cut in [(late, cut) for late in self.LATE_SPINNERS
                                          for cut in ("waiting", "SIGSTOP", "SIGKILL")]:
            with self.subTest(" ".join(run) or "manual save", cut=cut):
                t, wrapper, group, job, _, _ = self.late_spinner(run, hook, message)
                self.assertFalse(resurrect_save.running(group))  # the leader has ended
                os.kill(wrapper.pid, signal.SIGKILL)
                wrapper.wait()
                if cut != "waiting":
                    self.assertEqual(self.in_wrapper(t, interrupt, cut, str(group)).returncode, 9)
                    self.assertTrue(resurrect_save.spinners(group), "nothing left to recover")
                started = time.monotonic()
                self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
                if cut != "waiting":
                    self.assertLess(time.monotonic() - started, 3, "a stopped spinner was waited for")
                self.assert_only_job_left(group, job)
                self.assertEqual(json.loads((self.dir / ".save-lock").read_text())["pid"], None)
                self.assert_last_valid()

    def test_interrupted_wrapper_leaves_its_run_to_the_next(self):
        # SIGINT raises (KeyboardInterrupt), so the wrapper's own cleanup can
        # run, but its run carries on: its record must stay, as when killed.
        record = lambda: json.loads((self.dir / ".save-lock").read_text())["pid"]
        with self.subTest("restore under way"):
            t = Server(self, "interrupted-restore", self.dir, panes=2)
            self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
            restoring, release = self.pause(t, "pre-restore-all", ["restore"])
            group = record()
            self.addCleanup(lambda: subprocess.run(["pkill", "-KILL", "-g", str(group)]))
            restoring.send_signal(signal.SIGINT)
            restoring.wait(timeout=10)
            self.assertEqual(record(), group)
            successor = t.wrapper("quiet")
            time.sleep(1)
            self.assertIsNone(successor.poll(), "a save ran while the restore was still reading last")
            release()
            self.assertEqual(successor.wait(timeout=20), 0)
            self.assertFalse(subprocess.run(["pgrep", "-g", str(group)], capture_output=True).stdout)
            self.assertEqual(record(), None)
        with self.subTest("spinner being killed"):
            run, hook, message = self.LATE_SPINNERS[0]
            t, wrapper, group, job, _, _ = self.late_spinner(run, hook, message)
            wrapper.send_signal(signal.SIGINT)
            wrapper.wait(timeout=10)
            self.assertEqual(record(), group)
            for pid, _ in resurrect_save.spinners(group):
                os.kill(pid, signal.SIGSTOP)  # as kill_tree's first step
            self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
            self.assert_only_job_left(group, job)
            self.assertEqual(record(), None)

    def test_a_hook_naming_the_spinner_is_not_one(self):
        # Neither waited for (a quiet save starts no spinner) nor let past a
        # guarded tmux failure: only bash running the spinner's script is one.
        t = Server(self, "spinner-named", self.dir, panes=2)
        q = lambda path: shlex.quote(str(path))
        with self.subTest("background job"):
            background = self.control / "background"
            t.tmux(["set-option", "-g", "@resurrect-hook-post-save-all",
                    f"tail -f {q(resurrect_save.SPINNER)} >/dev/null 2>&1 & echo $! > {q(background)}"])
            started = time.monotonic()
            self.assertEqual(t.wrapper("quiet").wait(timeout=20), 0)
            self.assertLess(time.monotonic() - started, 3, "the job was taken for a spinner")
            job = int(background.read_text())
            self.addCleanup(lambda: subprocess.run(["kill", "-KILL", str(job)], stderr=subprocess.DEVNULL))
            os.kill(job, 0)  # still running
            t.tmux(["set-option", "-gu", "@resurrect-hook-post-save-all"])
        with self.subTest("guarded failure"):
            paused, release, continued = (self.control / name for name in ("paused", "release", "continued"))
            t.tmux(["set-option", "-g", "@resurrect-hook-pre-restore-all",
                    f"sh -c 'touch {paused}; i=0; while [ ! -e {release} ] && [ $i -lt 1000 ]; do sleep 0.01; "
                    f"i=$((i + 1)); done; tmux display-message check; touch {continued}' hook {q(resurrect_save.SPINNER)}"])
            self.addCleanup(release.touch)
            restoring = t.wrapper("restore", start_new_session=True, stderr=subprocess.DEVNULL)
            self.wait_until(paused.exists)
            group = json.loads((self.dir / ".save-lock").read_text())["pid"]
            self.addCleanup(lambda: subprocess.run(["pkill", "-KILL", "-g", str(group)]))
            t.restart()
            panes = t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"])
            release.touch()
            self.assertEqual(restoring.wait(timeout=20), 1)
            self.assertFalse(continued.exists(), "the hook carried on past its failed tmux call")
            self.assertEqual(t.tmux(["list-panes", "-a", "-F", "#{pane_id} #{pane_pid}"]), panes)

    def test_settle_ends_a_stopped_leader_left_behind(self):
        # A leader stops itself (its script ended by a signal) for its wrapper
        # to end the group; if that wrapper dies first, the next run does it.
        scripts = self.control / "tmux-resurrect/scripts"
        scripts.mkdir(parents=True)
        (scripts / "save.sh").write_text("sleep 60 &\nkill -TERM $$\n")
        leader = subprocess.Popen(resurrect_save.led(str(scripts / "save.sh")), start_new_session=True)
        self.addCleanup(lambda: subprocess.run(["pkill", "-KILL", "-g", str(leader.pid)]))
        _, status = os.waitpid(leader.pid, os.WUNTRACED)  # what the wrapper would see
        self.assertTrue(os.WIFSTOPPED(status))
        leader.returncode = 0  # reaped below by settle's kill; not by Popen
        with open(self.control / "lock", "w+") as lock:
            resurrect_save.write_record(lock.fileno(), pid=leader.pid)
            resurrect_save.settle(lock.fileno())  # returns once the group is gone
        self.assertNotEqual(subprocess.run(["pgrep", "-g", str(leader.pid)], capture_output=True).returncode, 0)
        os.waitpid(leader.pid, 0)

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
