#!/usr/bin/env python3
"""`ke` for herdr: stop the session's server and forget its saved layout, so
the next `herdr` starts empty, like tmux's kill-server. herdr's recovery
snapshots in session-snapshots/ are kept.

Targets the session this runs in (a herdr pane's own), else the default one.
It detaches before stopping: run from a herdr pane, the stop ends the shell
that started it.
"""

import json
import os
from pathlib import Path
import subprocess
import sys


def session(binary, name):
    listing = subprocess.run([binary, "session", "list", "--json"], check=True,
                             capture_output=True, text=True).stdout
    for entry in json.loads(listing)["sessions"]:
        if entry["name"] == name if name else entry["default"]:
            return entry
    raise RuntimeError(f"no herdr session named {name!r}")


def main():
    binary = os.environ.get("HERDR_BIN_PATH") or "herdr"
    name = os.environ.get("HERDR_SESSION")
    target = session(binary, name)
    saved = Path(target["session_dir"]) / "session.json"

    if os.fork():
        return 0  # The calling shell continues (until the server stops it).
    os.setsid()
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)

    if target["running"]:
        # Returns once the server is down; fails (keeping the layout) otherwise.
        subprocess.run([binary, "server", "stop"], check=True)
    saved.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"ke: {error}", file=sys.stderr)
        sys.exit(1)
