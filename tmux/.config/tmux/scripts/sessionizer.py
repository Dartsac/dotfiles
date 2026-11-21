#!/usr/bin/env python3
"""The sessionizer: pick a project, then open or switch to its tmux session.

  sessionizer.py               pick a project with fzf
  sessionizer.py <directory>   open that directory's session
  sessionizer.py --list        print the projects it offers

It offers the folders ~/.config/tmux/projects.local.txt lists, a local
override (git ignores it; projects.local.example.txt shows its shape). Without
one, it offers the subfolders of the common code folders that exist
(COMMON_CODE_FOLDERS).
herdr's sessionizer (scripts/project-picker.py in the herdr package) offers
the same list in the same fzf: it imports projects() and choose() from here.
A session is named after its folder, with each . and : turned into _: tmux
reads them in a target as a pane and a window (Neovim's
lua/config/multiplexer.lua names the sessions it makes the same way). Outside
tmux it attaches to the session; inside, it switches the client to it.
"""

import argparse
import glob
import os
import re
from pathlib import Path, PurePath
import shutil
import subprocess
import sys

# The common code folders, whose subfolders are offered when no local
# override lists projects.
COMMON_CODE_FOLDERS = ["repos", "projects", "code", "src"]
OVERRIDE = ".config/tmux/projects.local.txt"
# An override line that ends in a depth.
WITH_DEPTH = re.compile(r"(.*\S)\s+(\d+)")
# Tab and Shift-Tab move down and up, as Ctrl-j/k do: a picker that picks one
# item has nothing for Tab to select. Passed on the command line: a popup that
# a multiplexer key opens need not have fish's FZF_DEFAULT_OPTS.
MOVE_WITH_TAB = "--bind=tab:down,btab:up"


def subfolders(path):
    try:
        return [child for child in path.iterdir() if child.is_dir()]
    except OSError:
        return []


def folders_below(path, depth):
    """The folders exactly `depth` levels below `path` (0: path itself)."""
    level = [path] if path.is_dir() else []
    for _ in range(depth):
        level = [child for folder in level for child in subfolders(folder)]
    return level


def expand(pattern, home):
    """A path as the override writes it: ~ is the home folder, and a relative
    path starts there."""
    if pattern == "~" or pattern.startswith("~/"):
        pattern = pattern[2:]
    return str(home / pattern)


def read_override(text, home):
    """The override's (folder, depth) pairs and the patterns it excludes.
    A line is a folder, then optionally how many levels below it its
    projects are (1 when not given; 0 offers the folder itself). A line that
    starts with ! names folders to leave out. * matches any name; # starts a
    comment line."""
    roots, excluded = [], []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("!"):
            excluded.append(expand(line[1:].strip(), home))
            continue
        with_depth = WITH_DEPTH.fullmatch(line)
        folder, depth = (with_depth[1], int(with_depth[2])) if with_depth else (line, 1)
        for root in sorted(glob.glob(expand(folder, home))):
            roots.append((Path(root), depth))
    return roots, excluded


def projects(home):
    """The folders the sessionizer offers, sorted."""
    override = home / OVERRIDE
    if override.is_file():
        roots, excluded = read_override(override.read_text(), home)
    else:
        roots, excluded = [(home / name, 1) for name in COMMON_CODE_FOLDERS], []
    found = {str(folder) for root, depth in roots for folder in folders_below(root, depth)}
    return sorted(path for path in found if not any(map(PurePath(path).match, excluded)))


def say(message):
    """Inside tmux on its status line, which outlasts the popup; else as
    error output."""
    if os.environ.get("TMUX"):
        subprocess.run(["tmux", "display-message", message])
    else:
        print(message, file=sys.stderr)


def choose(candidates, prompt="Project> ", preview=True):
    """The candidate chosen in fzf, or None when cancelled. `preview` shows
    each candidate's folder tree: candidates that are not folders turn it off."""
    command = ["fzf", "--read0", "--print0", "--no-multi", "--no-expect", "--no-print-query", MOVE_WITH_TAB,
               f"--prompt={prompt}"]
    if preview and shutil.which("tree"):
        # fzf quotes {} for the shell, spaces included.
        command += ["--preview", "tree -L 2 -I 'node_modules|vendor|.git' -- {}"]
    result = subprocess.run(command, input="\0".join(candidates) + "\0", stdout=subprocess.PIPE, text=True)
    if result.returncode in (1, 130):  # no match, or cancelled
        return None
    result.check_returncode()
    selected = result.stdout.split("\0")[0]
    if selected not in candidates:
        raise RuntimeError("fzf returned an unexpected project selection.")
    return selected


def open_session(directory):
    # Absolute, so that `.` is named after its folder; symlinks are kept.
    path = Path(os.path.abspath(os.path.expanduser(directory)))
    if not path.is_dir():
        raise RuntimeError(f"not a folder: {directory}")
    name = re.sub(r"[.:]", "_", path.name) or "root"
    new_session = ["tmux", "new-session", "-s", name, "-c", str(path)]
    if not os.environ.get("TMUX"):
        os.execvp("tmux", new_session + ["-A"])
    target = f"={name}"
    if subprocess.run(["tmux", "has-session", "-t", target], capture_output=True).returncode != 0:
        subprocess.run(new_session + ["-d"], check=True)
    subprocess.run(["tmux", "switch-client", "-t", target], check=True)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("directory", nargs="?", help="open this folder's session without asking")
    parser.add_argument("--list", action="store_true", help="print the projects it offers")
    args = parser.parse_args(argv)
    home = Path.home()
    if args.list:
        for project in projects(home):
            print(project)
        return 0
    selected = args.directory
    if not selected:
        candidates = projects(home)
        if not candidates:
            if (home / OVERRIDE).is_file():
                say(f"sessionizer: no projects: ~/{OVERRIDE} lists no folder that exists")
            else:
                folders = ", ".join(f"~/{name}" for name in COMMON_CODE_FOLDERS)
                say(f"sessionizer: no projects: none of {folders} has a folder in it; list yours in ~/{OVERRIDE}")
            return 0
        if not shutil.which("fzf"):
            say("sessionizer: fzf is not installed: install it to pick a project")
            return 1
        selected = choose(candidates)
        if not selected:
            return 0
    open_session(selected)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        say(f"sessionizer: {error}")
        sys.exit(1)
