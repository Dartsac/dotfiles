#!/usr/bin/env python3
"""Herdr popup counterpart to ~/.local/bin/tmux-sessionizer.sh.

Run from Herdr with Ctrl-t Ctrl-f. --list only prints candidate directories.
An optional directory argument skips fzf. No tmux commands are used.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def subdirectories(path):
    try:
        return [child for child in path.iterdir() if child.is_dir()]
    except OSError:
        return []


def projects(home):
    candidates = []
    for root in (home / "repos", home / ".config",
                 home / "dotfiles/lazygit/Library/Application Support"):
        candidates.extend(subdirectories(root))
    for app in subdirectories(home / "work/applications"):
        candidates.extend(path for path in subdirectories(app)
                          if path.name not in {"investigations", "exports", "reference"})
        candidates.extend(subdirectories(app / "investigations"))
    for group in subdirectories(home / "work/cross-application"):
        candidates.extend(subdirectories(group))
    candidates.extend(path for path in (home / "work", home / "work/shared/scripts",
                                       home / "Documents/vault") if path.is_dir())
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
    response = json.loads(result.stdout)
    if "error" in response:
        raise RuntimeError(str(response["error"]))
    return response["result"]


def same_directory(value, path):
    return bool(value) and Path(value).expanduser().resolve() == path


def open_project(selected, binary):
    path = Path(selected).expanduser().resolve(strict=True)
    if not path.is_dir():
        raise RuntimeError(f"Not a directory: {path}")
    snapshot = herdr(binary, "api", "snapshot")["snapshot"]
    workspaces = snapshot["workspaces"]

    # Remember project roots in workspace metadata, so cd/renames do not make
    # duplicate workspaces. Full paths also distinguish same-named projects.
    match = next((workspace for workspace in workspaces
                  if same_directory(workspace.get("tokens", {}).get("project_path"), path)), None)
    if match is None:
        # Adopt existing manually created workspaces using their pane directory.
        untagged = {workspace["workspace_id"]: workspace for workspace in workspaces
                    if not workspace.get("tokens", {}).get("project_path")}
        match = next((untagged[pane["workspace_id"]] for pane in snapshot["panes"]
                      if pane["workspace_id"] in untagged
                      and same_directory(pane.get("cwd") or pane.get("foreground_cwd"), path)), None)

    if match:
        workspace_id = match["workspace_id"]
        herdr(binary, "workspace", "focus", workspace_id)
    else:
        created = herdr(binary, "workspace", "create", "--cwd", str(path),
                        "--label", path.name.replace(".", "_") or "root", "--focus")
        workspace_id = created["workspace"]["workspace_id"]
    herdr(binary, "workspace", "report-metadata", workspace_id,
          "--source", "project-picker", "--token", f"project_path={path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?")
    parser.add_argument("--list", action="store_true", help="list projects without contacting Herdr")
    args = parser.parse_args()
    if args.list:
        print("\n".join(projects(Path.home())))
        return 0
    # Custom-command popups receive the owning server socket explicitly.
    # Never silently target the default session from a normal terminal.
    if not os.environ.get("HERDR_SOCKET_PATH"):
        raise RuntimeError("Run this picker inside Herdr using Ctrl-t Ctrl-f.")
    selected = args.directory or choose_project(projects(Path.home()))
    if selected:
        open_project(selected, os.environ.get("HERDR_BIN_PATH") or "herdr")
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
