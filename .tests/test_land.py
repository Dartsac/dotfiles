"""./land, run in a throwaway clone of a throwaway origin, with a made-up `gh`
on PATH that answers for GitHub's runs. Each step stops the run when it cannot
finish: nothing after a refused step may happen, least of all a deletion."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

LAND = Path(__file__).resolve().parents[1] / "land"
# `gh run list` prints the file `runs`, after running the file `on-list` when
# there is one (what happens on GitHub while the runs go). `gh run watch`
# finishes every run the way the file `watched` says.
GH = """#!{python}
import json, os, subprocess, sys
root = {root!r}
with open(os.path.join(root, "gh-calls"), "a") as calls:
    calls.write(" ".join(sys.argv[1:]) + "\\n")
runs = os.path.join(root, "runs")
if sys.argv[1:3] == ["run", "list"]:
    hook = os.path.join(root, "on-list")
    if os.path.exists(hook):
        subprocess.run(["sh", hook], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.remove(hook)
    sys.stdout.write(open(runs).read())
elif sys.argv[1:3] == ["run", "watch"]:
    conclusion = open(os.path.join(root, "watched")).read().strip()
    finished = [dict(run, status="completed", conclusion=conclusion) for run in json.load(open(runs))]
    json.dump(finished, open(runs, "w"))
    sys.exit(0 if conclusion == "success" else 1)
"""


def a_run(name="standalone", number=7, status="completed", conclusion="success"):
    return {"databaseId": number, "name": name, "status": status, "conclusion": conclusion}


class LandTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        tools = self.root / "tools"
        tools.mkdir()
        (tools / "gh").write_text(GH.format(python=sys.executable, root=str(self.root)))
        (tools / "gh").chmod(0o755)
        self.env = {
            "PATH": os.pathsep.join([str(tools), os.environ["PATH"]]),
            "HOME": str(self.root / "home"),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "Test",
            "GIT_AUTHOR_EMAIL": "test@example.com",
            "GIT_COMMITTER_NAME": "Test",
            "GIT_COMMITTER_EMAIL": "test@example.com",
        }
        self.origin = self.root / "origin.git"
        self.checkout = self.root / "checkout"
        self.git("init", "-q", "--bare", "-b", "main", str(self.origin), cwd=self.root)
        self.git("clone", "-q", str(self.origin), str(self.checkout), cwd=self.root)
        self.commit("README.md", "hello\n")
        self.git("push", "-q", "origin", "main")
        # The work: a branch one commit ahead of main, with this checkout back on main.
        self.git("switch", "-q", "-c", "work")
        self.work = self.commit("work.txt", "work\n")
        self.git("switch", "-q", "main")
        self.runs(a_run())

    def git(self, *args, cwd=None):
        return subprocess.run(["git", *args], cwd=cwd or self.checkout, env=self.env, check=True,
                              capture_output=True, text=True).stdout.strip()

    def commit(self, name, text, cwd=None):
        folder = cwd or self.checkout
        (folder / name).write_text(text)
        self.git("add", name, cwd=folder)
        self.git("commit", "-q", "-m", f"add {name}", cwd=folder)
        return self.git("rev-parse", "HEAD", cwd=folder)

    def runs(self, *runs, watched="success"):
        (self.root / "runs").write_text(json.dumps(list(runs)))
        (self.root / "watched").write_text(watched)

    def land(self, *args, cwd=None):
        return subprocess.run([sys.executable, str(LAND), *args], cwd=cwd or self.checkout, env=self.env,
                              capture_output=True, text=True)

    def on_origin(self, branch):
        """The commit origin has for `branch`, or None."""
        listed = self.git("ls-remote", "origin", f"refs/heads/{branch}")
        return listed.split()[0] if listed else None

    def here(self, branch):
        """The commit this clone has for `branch`, or None."""
        found = subprocess.run(["git", "rev-parse", "-q", "--verify", f"refs/heads/{branch}"], cwd=self.checkout,
                               env=self.env, capture_output=True, text=True)
        return found.stdout.strip() or None

    def another_session(self):
        """Another clone with a commit on main that the work does not hold:
        the clone, and the commit it has yet to push."""
        other = self.root / "other"
        self.git("clone", "-q", str(self.origin), str(other), cwd=self.root)
        return other, self.commit("other.txt", "other\n", cwd=other)

    def fail_unless_nothing_landed(self, result, says, main):
        """./land stopped saying `says`: main is where it was, here and on
        origin, and the work's branch is still in both places."""
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(says, result.stderr)
        self.assertEqual(self.on_origin("main"), main)
        self.assertEqual(self.here("work"), self.work)
        self.assertEqual(self.on_origin("work"), self.work)

    def test_lands_a_branch_whose_runs_are_green_and_deletes_it(self):
        result = self.land("work")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.on_origin("main"), self.work)
        self.assertEqual(self.here("main"), self.work)
        self.assertIsNone(self.on_origin("work"))
        self.assertIsNone(self.here("work"))
        # It asked for the runs of the commit it pushed.
        calls = (self.root / "gh-calls").read_text()
        self.assertIn(f"--branch work --commit {self.work}", calls)

    def test_waits_for_a_run_that_is_still_going(self):
        self.runs(a_run(status="in_progress", conclusion=""))

        result = self.land("work")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("run watch 7", (self.root / "gh-calls").read_text())
        self.assertEqual(self.on_origin("main"), self.work)

    def test_a_red_run_stops_it_and_names_the_run(self):
        main = self.on_origin("main")
        self.runs(a_run("lint", 6), a_run(status="in_progress", conclusion=""), watched="failure")

        result = self.land("work")

        self.fail_unless_nothing_landed(result, "gh run view 7 --log-failed", main)
        self.assertEqual(self.here("main"), main)

    def test_main_moving_while_the_runs_go_stops_it_and_keeps_the_branch(self):
        # Another session lands while GitHub runs this branch's checks.
        other, landed = self.another_session()
        (self.root / "on-list").write_text(f'git -C "{other}" push -q origin main\n')
        main = self.here("main")

        result = self.land("work")

        self.fail_unless_nothing_landed(result, "main has moved", landed)
        self.assertEqual(self.here("main"), main)

    def test_refuses_a_branch_that_does_not_hold_main_before_pushing_it(self):
        other, landed = self.another_session()
        self.git("push", "-q", "origin", "main", cwd=other)

        result = self.land("work")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("main has moved", result.stderr)
        self.assertIn("rebase work", result.stderr)
        self.assertEqual(self.on_origin("main"), landed)
        self.assertIsNone(self.on_origin("work"))
        self.assertFalse((self.root / "gh-calls").exists(), "it waited for runs of a branch it refused")

    def test_stops_while_the_main_checkout_is_on_another_branch(self):
        main = self.on_origin("main")
        self.git("switch", "-q", "work")

        result = self.land("work")

        self.fail_unless_nothing_landed(result, "the main checkout is on work", main)

    def test_the_push_step_alone_refuses_a_branch_main_does_not_hold(self):
        main = self.on_origin("main")
        self.git("push", "-q", "origin", "work")

        result = self.land("--push", "work")

        self.fail_unless_nothing_landed(result, "main does not hold work", main)

    def test_the_steps_run_one_at_a_time(self):
        main = self.on_origin("main")

        self.assertEqual(self.land("--green", "work").returncode, 0)
        self.assertEqual((self.on_origin("work"), self.on_origin("main"), self.here("main")), (self.work, main, main))
        self.assertEqual(self.land("--merge", "work").returncode, 0)
        self.assertEqual((self.on_origin("work"), self.on_origin("main"), self.here("main")), (self.work, main, self.work))
        self.assertEqual(self.land("--push", "work").returncode, 0)
        self.assertEqual((self.on_origin("work"), self.on_origin("main"), self.here("work")), (None, self.work, None))

    def test_green_replaces_what_it_pushed_before_a_rebase(self):
        self.assertEqual(self.land("--green", "work").returncode, 0)
        self.git("switch", "-q", "work")
        self.git("commit", "-q", "--amend", "-m", "the work, rebased")
        rebased = self.git("rev-parse", "HEAD")
        self.git("switch", "-q", "main")

        result = self.land("--green", "work")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotEqual(rebased, self.work)
        self.assertEqual(self.on_origin("work"), rebased)

    def test_green_refuses_to_replace_a_branch_this_clone_did_not_push(self):
        # Another clone's work, under the name this one was about to use.
        other, theirs = self.another_session()
        self.git("push", "-q", "origin", "main:refs/heads/work", cwd=other)

        result = self.land("--green", "work")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("origin's work", result.stderr)
        self.assertEqual(self.on_origin("work"), theirs)
        self.assertFalse((self.root / "gh-calls").exists())

    def test_the_merge_step_alone_refuses_a_commit_added_since_the_green_run(self):
        main = self.on_origin("main")
        self.assertEqual(self.land("--green", "work").returncode, 0)
        self.git("switch", "-q", "work")
        self.commit("more.txt", "more\n")
        self.git("switch", "-q", "main")

        result = self.land("--merge", "work")

        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("./land --green work", result.stderr)
        self.assertEqual((self.here("main"), self.on_origin("main")), (main, main))

    def test_the_merge_step_alone_refuses_a_branch_whose_runs_are_not_green(self):
        main = self.on_origin("main")
        self.git("push", "-q", "origin", "work")
        self.runs(a_run(conclusion="failure"))

        result = self.land("--merge", "work")

        self.fail_unless_nothing_landed(result, "gh run view 7 --log-failed", main)
        self.assertEqual(self.here("main"), main)

    def test_a_refused_push_of_main_keeps_the_branch(self):
        self.assertEqual(self.land("--green", "work").returncode, 0)
        self.assertEqual(self.land("--merge", "work").returncode, 0)
        # Another session lands first: origin's main now holds what this one's lacks.
        other, landed = self.another_session()
        self.git("push", "-q", "origin", "main", cwd=other)

        result = self.land("--push", "work")

        self.fail_unless_nothing_landed(result, "git push", landed)

    def test_the_push_step_keeps_a_pushed_branch_that_holds_something_else(self):
        # The name given to --push is another clone's branch, not this work's.
        other, theirs = self.another_session()
        self.git("push", "-q", "origin", "main:refs/heads/their-job", cwd=other)
        self.assertEqual(self.land("--green", "work").returncode, 0)
        self.assertEqual(self.land("--merge", "work").returncode, 0)

        result = self.land("--push", "--as", "their-job", "work")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.on_origin("main"), self.work)
        self.assertEqual(self.on_origin("their-job"), theirs)
        self.assertIn("kept: origin's their-job", result.stdout)

    def test_keeps_a_branch_a_worktree_is_on_and_gives_gits_reason(self):
        worktree = self.root / "worktree"
        self.git("worktree", "add", "-q", "-b", "job", str(worktree), "main")
        job = self.commit("job.txt", "job\n", cwd=worktree)

        result = self.land("job", cwd=worktree)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.on_origin("main"), job)
        self.assertIsNone(self.on_origin("job"))
        self.assertEqual(self.here("job"), job)
        kept = next(line for line in result.stdout.splitlines() if line.startswith("kept: job"))
        self.assertRegex(kept, "(?i)worktree|checked out")

    def test_refuses_what_is_not_a_branch_here(self):
        for given in ("HEAD", self.work, "no-such-branch"):
            with self.subTest(given=given):
                result = self.land(given)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn("no such branch", result.stderr)
        self.assertIsNone(self.on_origin("HEAD"))
        self.assertFalse((self.root / "gh-calls").exists())

    def test_lands_a_worktrees_own_branch_under_another_name_and_keeps_it(self):
        worktree = self.root / "worktree"
        self.git("worktree", "add", "-q", "-b", "worktree/quiet-river", str(worktree), "main")
        job = self.commit("job.txt", "job\n", cwd=worktree)

        result = self.land("--as", "the-job", "worktree/quiet-river", cwd=worktree)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("--branch the-job", (self.root / "gh-calls").read_text())
        self.assertEqual(self.on_origin("main"), job)
        self.assertEqual(self.here("main"), job)  # fast-forwarded in the main checkout, from the worktree
        self.assertIsNone(self.on_origin("the-job"))
        self.assertIsNone(self.on_origin("worktree/quiet-river"))
        self.assertEqual(self.here("worktree/quiet-river"), job)

    def test_refuses_to_land_main_itself(self):
        result = self.land("main")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("main", result.stderr)
        self.assertFalse((self.root / "gh-calls").exists())


if __name__ == "__main__":
    unittest.main()
