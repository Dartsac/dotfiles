"""The herdr binary for project-picker.py and stop-fresh.py, which import it
from this folder."""
import os


def herdr_binary():
    """HERDR_BIN_PATH, or plain "herdr" (subprocess finds it on PATH) when that
    path is stale: a running server keeps it across an update. Same rule as
    herdr-bin.sh and Neovim's config/multiplexer.lua: only an executable
    regular file counts."""
    configured = os.environ.get("HERDR_BIN_PATH")
    if configured and os.path.isfile(configured) and os.access(configured, os.X_OK):
        return configured
    return "herdr"
