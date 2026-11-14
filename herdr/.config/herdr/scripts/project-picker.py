#!/usr/bin/env python3
"""herdr counterpart to ~/.local/bin/tmux-sessionizer.sh.

Inside herdr (Ctrl-t Ctrl-f, or plain Ctrl-f in fish) it opens or focuses the
chosen project's workspace in the current session. Outside herdr it refuses
unless --default-session or --attach names the default session explicitly.
--list only prints candidate directories. An optional directory skips fzf.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

from herdr_cli import herdr_binary


def subdirectories(path):
    try:
        return [child for child in path.iterdir() if child.is_dir()]
    except OSError:
        return []


def projects(home):
    candidates = []
    for root in (home / "repos", home / ".config"):
        candidates.extend(subdirectories(root))
    for app in subdirectories(home / "work/applications"):
        candidates.extend(path for path in subdirectories(app)
                          if path.name not in {"investigations", "exports", "reference"})
        candidates.extend(subdirectories(app / "investigations"))
    for group in subdirectories(home / "work/cross-application"):
        candidates.extend(subdirectories(group))
    candidates.extend(path for path in (home / "work", home / "work/shared/scripts",
                                       home / "Documents/vault", home / "dotfiles/pi")
                      if path.is_dir())
    return sorted({str(path) for path in candidates})


def choose_project(candidates):
    if not candidates:
        raise RuntimeError("No project directories found.")
    command = ["fzf", "--read0", "--print0", "--no-multi", "--no-expect",
               "--no-print-query", "--prompt=Herdr project> "]
    if shutil.which("tree"):
        # fzf shell-quotes {} before interpolation, including paths with spaces.
        command += ["--preview", "tree -L 2 -I 'node_modules|vendor|.git' -- {}"]
    result = subprocess.run(command, input="\0".join(candidates) + "\0",
                            stdout=subprocess.PIPE, text=True)
    if result.returncode in (1, 130):  # No match or user cancellation.
        return None
    result.check_returncode()
    selected = result.stdout.removesuffix("\0")
    if selected not in candidates:
        raise RuntimeError("fzf returned an unexpected project selection.")
    return selected


def herdr(binary, *args):
    result = subprocess.run([binary, *args], check=True, capture_output=True, text=True)
    if not result.stdout.strip():
        return None  # e.g. `workspace report-metadata` prints nothing on success.
    response = json.loads(result.stdout)
    if "error" in response:
        raise RuntimeError(str(response["error"]))
    return response["result"]


def same_directory(value, path):
    return bool(value) and Path(value).expanduser().resolve() == path


def open_project(selected, binary):
    """Focus the project's workspace, creating it if needed.

    Returns (workspace id, the new workspace's root pane id or None).
    """
    path = Path(selected).expanduser().resolve(strict=True)
    if not path.is_dir():
        raise RuntimeError(f"Not a directory: {path}")
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
    if match:
        workspace_id = match["workspace_id"]
        herdr(binary, "workspace", "focus", workspace_id)
    else:
        # The server can retain a symlink in its inherited PWD. Fish keeps
        # that logical path when it matches cwd, so set both explicitly.
        created = herdr(binary, "workspace", "create", "--cwd", str(path),
                        "--env", f"PWD={path}",
                        "--label", path.name.replace(".", "_") or "root", "--focus")
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
                             "unless the workspace was just created")
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
    workspace_id, root_pane = open_project(selected, binary)
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
