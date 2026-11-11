#!/usr/bin/env python3
"""Install the dotfiles Herdr reporter without editing Herdr-managed files.

Only updates local Pi resource settings and a discovery symlink. Existing Pi
sessions keep running unchanged until the owner chooses /reload or restarts.
"""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import tempfile


def install(agent_dir, extension):
    agent_dir = Path(agent_dir).expanduser().resolve()
    extension = Path(extension).resolve(strict=True)
    settings = agent_dir / "settings.json"
    data = json.loads(settings.read_text()) if settings.exists() else {}
    resources = data.get("extensions", [])
    if not isinstance(resources, list) or not all(isinstance(item, str) for item in resources):
        raise ValueError("Pi settings.extensions must be a string array")
    link = agent_dir / "extensions/dotfiles-herdr"
    if os.path.lexists(link) and (not link.is_symlink() or link.resolve() != extension):
        raise ValueError(f"Refusing to replace existing extension: {link}")
    link.parent.mkdir(parents=True, exist_ok=True)
    if not os.path.lexists(link):
        link.symlink_to(extension, target_is_directory=True)
    exclusion = "-extensions/herdr-agent-state.ts"
    if exclusion not in resources:
        data["extensions"] = [*resources, exclusion]
        if settings.exists():
            backup = settings.with_name(f"settings.json.before-herdr-supervision-{datetime.now():%Y%m%d-%H%M%S-%f}")
            shutil.copy2(settings, backup)
        fd, temporary = tempfile.mkstemp(dir=agent_dir, prefix=".settings-herdr-", text=True)
        try:
            with os.fdopen(fd, "w") as handle:
                json.dump(data, handle, indent=2)
                handle.write("\n")
            os.replace(temporary, settings)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    return link


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-dir", type=Path, default=Path.home() / ".pi/agent")
    args = parser.parse_args()
    extension = Path(__file__).resolve().parents[1] / "pi-extension"
    print(f"Installed {install(args.agent_dir, extension)}")
    print("Apply with /reload in each idle Pi session. Running sessions were not restarted.")


if __name__ == "__main__":
    main()
