#!/usr/bin/env python3
"""herdr's sessionizer, the counterpart of tmux's, offering the same projects
in the same fzf: the folders ~/.config/tmux/projects.local.txt lists, or else
the common code folders' subfolders (tmux/.config/tmux/scripts/sessionizer.py).

Inside herdr (Ctrl-t Ctrl-f, or plain Ctrl-f in fish) it opens or focuses the
chosen project's workspace in the current session. A folder in a main checkout
whose main space is open gets no workspace of its own: the picker offers that
main space, at a tab in the picked folder, or a new worktree space. While none
is open, the main space opens, named for the repository, in the picked folder.
A new worktree space asks for its job's name, which names its branch (the
folder's area typed in first: `herdr-`; Enter alone leaves the name to Herdr),
branches from the repository's default branch (origin's HEAD), names the
folder's area (its first folder below the checkout) and opens there, or in the
deepest of those folders the new checkout has. Outside herdr
it refuses unless --default-session or --attach names the default session
explicitly.
--list only prints candidate directories. An optional directory skips fzf.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

from herdr_cli import herdr_binary

# tmux's sessionizer, in this clone: this file is
# <clone>/herdr/.config/herdr/scripts/project-picker.py.
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "tmux/.config/tmux/scripts"))
from sessionizer import choose, projects  # noqa: E402


def choose_project(candidates):
    if not candidates:
        raise RuntimeError("No project directories found.")
    return choose(candidates, prompt="Herdr project> ")


class HerdrError(RuntimeError):
    """An error Herdr answered with; `code` names it (e.g. not_git_worktree)."""

    def __init__(self, error):
        super().__init__(error.get("message", str(error)))
        self.code = error.get("code")


def herdr(binary, *args):
    result = subprocess.run([binary, *args], capture_output=True, text=True)
    if result.returncode:
        # Herdr prints an API error as JSON on stderr, and exits with 1.
        try:
            error = json.loads(result.stderr)["error"]
        except (ValueError, KeyError, TypeError):
            result.check_returncode()
        raise HerdrError(error)
    if not result.stdout.strip():
        return None  # e.g. `workspace report-metadata` prints nothing on success.
    return json.loads(result.stdout)["result"]


def same_directory(value, path):
    return bool(value) and Path(value).expanduser().resolve() == path


def resolved_folder(selected):
    path = Path(selected).expanduser().resolve(strict=True)
    if not path.is_dir():
        raise RuntimeError(f"Not a directory: {path}")
    return path


def find_main_checkout(path, binary):
    """The main checkout that holds `path`, as Herdr knows it: (its main
    space's id, None while none is open; the repo's name; the checkout's
    folder). None outside one: outside git, in a linked worktree, or in a
    repository whose worktrees git cannot list."""
    try:
        listing = herdr(binary, "worktree", "list", "--cwd", str(path))
    except HerdrError as error:
        # Outside git, or in a repository whose worktrees git cannot list: no
        # main checkout to speak of. Any other error stands: worktree_busy
        # passes, and opening the folder meanwhile could make a second main space.
        if error.code in ("not_git_worktree", "worktree_list_failed"):
            return None
        raise
    checkouts = {Path(checkout["path"]).resolve(): checkout for checkout in listing["worktrees"]}
    holding = [root for root in checkouts if path.is_relative_to(root)]
    if not holding:
        return None
    # The deepest: a linked worktree can sit inside the main checkout.
    checkout = checkouts[max(holding, key=lambda root: len(root.parts))]
    if checkout["is_linked_worktree"]:
        return None
    return checkout.get("open_workspace_id"), listing["source"]["repo_name"], Path(checkout["path"]).resolve()


def default_branch(checkout):
    """The repository's default branch, origin's HEAD, when there is a local
    branch of that name; else None, and Herdr branches from the main checkout's
    HEAD, which another session may have on a branch of its own."""
    found = subprocess.run(["git", "-C", str(checkout), "rev-parse", "--abbrev-ref", "origin/HEAD"],
                           capture_output=True, text=True)
    name = found.stdout.strip().removeprefix("origin/") if found.returncode == 0 else ""
    if name and subprocess.run(["git", "-C", str(checkout), "rev-parse", "--verify", "-q", f"refs/heads/{name}"],
                               capture_output=True).returncode == 0:
        return name
    return None


def job_branch(text):
    """The branch a typed job name makes: lowercase words joined by hyphens
    (`Sidebar Inbox` is `sidebar-inbox`); "" for nothing usable."""
    return re.sub(r"[^a-z0-9/._]+", "-", text.lower()).strip("-/.")


def ask_job_name(area):
    """The new worktree space's job, as a branch name: "" leaves the name to
    Herdr, None when cancelled. A folder's area is typed in already
    (`herdr-`), as a job is named for its area and its task."""
    found = subprocess.run(["fzf", "--print-query", "--no-info", "--prompt=job name (Enter alone: Herdr names it)> ",
                            f"--query={area + '-' if area else ''}"], input="", stdout=subprocess.PIPE, text=True)
    if found.returncode not in (0, 1):            # 1: nothing to match, the query printed; 130: Esc
        return None
    branch = job_branch(found.stdout.split("\n")[0])
    return "" if branch == area else branch      # the area alone names no job


def new_worktree_space(path, main_space_id, checkout, binary):
    """A worktree space from the main space, for the folder `path` of its
    checkout, on a branch named for its job: (its workspace id, its root pane
    id), or None when the name was not given."""
    below = path.relative_to(checkout)
    branch = ask_job_name(below.parts[0] if below.parts else "")
    if branch is None:
        return None
    base = default_branch(checkout)
    created = herdr(binary, "worktree", "create", "--workspace", main_space_id, *(["--branch", branch] if branch else []),
                    *(["--base", base] if base else []), "--focus")
    workspace_id, root_pane = created["workspace"]["workspace_id"], created["root_pane"]["pane_id"]
    if below.parts:
        herdr(binary, "workspace", "report-metadata", workspace_id, "--source", "project-picker",
              "--token", f"area={below.parts[0]}")
        # The deepest of those folders the new checkout has: git keeps no empty or ignored one.
        made = Path(created["worktree"]["path"])
        there = next((made / part for part in [below, *below.parents] if (made / part).is_dir()), made)
        herdr(binary, "pane", "run", root_pane, f"cd {shlex.quote(str(there))}")
    return workspace_id, root_pane


GO_TO_MAIN_SPACE = "Go to the main space"
NEW_WORKTREE_SPACE = "New worktree space"


def go_to_main_space(path, main_space_id, checkout, binary):
    """Focus the main space. For a folder below its root, focus a tab there:
    one with a pane in that folder, else a new one, whose root pane is
    returned. (workspace id, root pane id or None)."""
    if path == checkout:
        herdr(binary, "workspace", "focus", main_space_id)
        return main_space_id, None
    panes = herdr(binary, "api", "snapshot")["snapshot"]["panes"]
    there = next((pane["tab_id"] for pane in panes if pane.get("workspace_id") == main_space_id
                  and any(same_directory(pane.get(key), path) for key in ("cwd", "foreground_cwd"))), None)
    if there:
        herdr(binary, "tab", "focus", there)
        return main_space_id, None
    # The server can retain a symlink in its inherited PWD: set it, as for a new workspace.
    created = herdr(binary, "tab", "create", "--workspace", main_space_id, "--cwd", str(path),
                    "--env", f"PWD={path}", "--focus")
    return main_space_id, created["root_pane"]["pane_id"]


def open_folder(selected, binary):
    """Open the folder the picker was given: its checkout's main space or a new
    worktree space when that main space is open; the main space, named for the
    repository, when none is; else its own workspace.

    Returns (workspace id, the root pane id of a new workspace, worktree space
    or main-space tab, else None), or None when the question was cancelled.
    """
    path = resolved_folder(selected)
    found = find_main_checkout(path, binary)
    if not found:
        return open_project(path, binary)
    main_space_id, repo_name, checkout = found
    if not main_space_id:
        # The checkout's main space, whichever of its folders comes first:
        # named for the repository, its project the checkout, opened in `path`.
        return open_project(path, binary, project=checkout, label=repo_name)
    # Only a terminal can answer (Ctrl-f's popup, fish); Neovim's <leader>Tc
    # cannot, and gets the main space.
    choice = GO_TO_MAIN_SPACE
    if sys.stdin.isatty():
        choice = choose([GO_TO_MAIN_SPACE, NEW_WORKTREE_SPACE], prompt=f"{repo_name}> ", preview=False)
    if choice == NEW_WORKTREE_SPACE:
        return new_worktree_space(path, main_space_id, checkout, binary)
    if choice == GO_TO_MAIN_SPACE:
        return go_to_main_space(path, main_space_id, checkout, binary)
    return None


def open_project(selected, binary, project=None, label=None):
    """Focus the project's workspace, creating it if needed: in the folder
    `selected`, with the project folder `project` (the folder itself unless
    given) and the label `label` (the project folder's name unless given).

    Returns (workspace id, the new workspace's root pane id or None).
    """
    folder = resolved_folder(selected)
    path = project or folder
    snapshot = herdr(binary, "api", "snapshot")["snapshot"]
    workspaces = snapshot["workspaces"]

    # Remember project roots in workspace metadata, so cd/renames do not make
    # duplicate workspaces. Full paths also distinguish same-named projects.
    match = next((workspace for workspace in workspaces
                  if same_directory(workspace.get("tokens", {}).get("project_path"), path)), None)
    tagged = match is not None
    if not tagged:
        # Adopt existing manually created workspaces using their pane directory.
        untagged = {workspace["workspace_id"]: workspace for workspace in workspaces
                    if not workspace.get("tokens", {}).get("project_path")}
        match = next((untagged[pane["workspace_id"]] for pane in snapshot["panes"]
                      if pane["workspace_id"] in untagged
                      and same_directory(pane.get("cwd") or pane.get("foreground_cwd"), path)), None)

    root_pane = None
    if match and tagged and folder != path:
        # The project's space, from a folder below its root: a tab there.
        return go_to_main_space(folder, match["workspace_id"], path, binary)
    if match:
        workspace_id = match["workspace_id"]
        herdr(binary, "workspace", "focus", workspace_id)
    else:
        # The server can retain a symlink in its inherited PWD. Fish keeps
        # that logical path when it matches cwd, so set both explicitly.
        created = herdr(binary, "workspace", "create", "--cwd", str(folder),
                        "--env", f"PWD={folder}",
                        "--label", label or path.name.replace(".", "_") or "root", "--focus")
        workspace_id = created["workspace"]["workspace_id"]
        root_pane = created["root_pane"]["pane_id"]
    if not tagged:
        herdr(binary, "workspace", "report-metadata", workspace_id,
              "--source", "project-picker", "--token", f"project_path={path}")
    return workspace_id, root_pane


def server_running(binary):
    status = subprocess.run([binary, "workspace", "list"], capture_output=True)
    return status.returncode == 0


def ensure_default_server(binary):
    """Start the default session's server headless, as `herdr` itself would."""
    if server_running(binary):
        return
    subprocess.Popen([binary, "server"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)
    deadline = time.monotonic() + 10
    while not server_running(binary):
        if time.monotonic() > deadline:
            raise RuntimeError("the herdr server did not start within 10 seconds.")
        time.sleep(0.1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?")
    parser.add_argument("--list", action="store_true", help="list projects without contacting Herdr")
    parser.add_argument("--default-session", action="store_true",
                        help="outside herdr, use the default session, starting its server if needed")
    parser.add_argument("--attach", action="store_true",
                        help="like --default-session, then attach to it (outside herdr only)")
    parser.add_argument("--json", action="store_true",
                        help='print {"workspace_id", "root_pane_id"}; root_pane_id is null '
                             "unless the workspace, worktree space or main-space tab was just created; "
                             "nothing when the question is cancelled")
    args = parser.parse_args()
    if args.list:
        print("\n".join(projects(Path.home())))
        return 0
    binary = herdr_binary()
    # Herdr panes and custom commands receive their own server's socket. Never
    # silently target the default session from another terminal (e.g. tmux).
    inside = bool(os.environ.get("HERDR_SOCKET_PATH"))
    if not inside and not (args.default_session or args.attach):
        raise RuntimeError("Run this picker inside Herdr, or pass --attach.")
    selected = args.directory or choose_project(projects(Path.home()))
    if not selected:
        return 0
    if not inside:
        ensure_default_server(binary)
    opened = open_folder(selected, binary)
    if not opened:
        return 0
    workspace_id, root_pane = opened
    if args.json:
        print(json.dumps({"workspace_id": workspace_id, "root_pane_id": root_pane}))
    if args.attach and not inside:
        sys.stdout.flush()
        os.execvp(binary, [binary])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Herdr project picker: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        if sys.stdin.isatty():
            input("Press Enter to close...")
        sys.exit(1)
