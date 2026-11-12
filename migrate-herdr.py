#!/usr/bin/env python3
"""Check Herdr directory-symlink migration; use --apply only with all servers stopped.

Run outside Herdr: python3 ~/dotfiles/migrate-herdr.py --apply
Never stops a server, deletes session state, changes plugins, or commits files.
"""
import argparse
import datetime
import filecmp
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

NAMES = ("herdr", "herdr-automatic-rename")
REPO = Path(__file__).resolve().parent


def sessions(binary):
    result = subprocess.run([binary, "session", "list", "--json"],
                            capture_output=True, text=True, check=True)
    rows = json.loads(result.stdout)["sessions"]
    if not isinstance(rows, list) or any(not isinstance(r.get("running"), bool) for r in rows):
        raise RuntimeError("Unexpected session status; cannot establish that servers are stopped")
    return rows


def relocated_link(src, dst, source, target):
    """Preserve the referent, not the relative link text from its old location."""
    try:
        referent = src.resolve(strict=True)
    except (OSError, RuntimeError) as error:
        raise RuntimeError(f"Broken or cyclic symlink; resolve before migration: {src}") from error
    try:
        # Local state moves with the config tree. Point into its new location,
        # not the original directory that will become the rollback backup.
        referent = target.resolve() / referent.relative_to(source.resolve())
    except ValueError:
        pass  # External referents stay external, at the same physical location.
    return os.path.relpath(referent, dst.parent.resolve())


def plan(source, target):
    """List copies without following source directory links or overwriting files."""
    copies = []
    if source.is_symlink():
        if source.resolve() != target.resolve():
            raise RuntimeError(f"Unexpected directory symlink: {source}")
        return copies
    if not source.is_dir() or not target.is_dir():
        raise RuntimeError(f"Missing source or package directory: {source}, {target}")
    for root, dirs, files in os.walk(source, followlinks=False):
        for name in dirs + files:
            src = Path(root) / name
            dst = target / src.relative_to(source)
            if stat.S_ISSOCK(src.lstat().st_mode):
                continue  # Stale sockets must be recreated by Herdr, not copied.
            if src.is_symlink():
                if dst.exists() and src.resolve() == dst.resolve():
                    continue  # Existing Stow link, including links to whole directories.
                if os.path.lexists(dst):
                    raise RuntimeError(f"Conflicting link: {src} -> {dst}")
                relocated_link(src, dst, source, target)  # Reject broken/cyclic links before writes.
                copies.append((src, dst))
            elif src.is_dir():
                if os.path.lexists(dst) and (not dst.is_dir() or dst.is_symlink()):
                    raise RuntimeError(f"Conflicting directory: {dst}")
            elif src.is_file():
                if os.path.lexists(dst):
                    if dst.is_symlink() or not dst.is_file() or not filecmp.cmp(src, dst, shallow=False):
                        raise RuntimeError(f"Different files; refusing to overwrite: {src}, {dst}")
                else:
                    copies.append((src, dst))
            else:
                raise RuntimeError(f"Unsupported special file: {src}")
    return copies


def agent_paths(config):
    """Check saved agent path references, without changing conversation data."""
    saved = [config / "session.json"] + sorted((config / "sessions").glob("*/session.json"))
    paths = set()
    for path in saved:
        if not path.exists():
            continue
        stack = [json.loads(path.read_text())]
        while stack:
            item = stack.pop()
            if isinstance(item, dict):
                ref = item.get("agent_session")
                if isinstance(ref, dict) and ref.get("kind") == "path":
                    value = Path(ref["value"]).expanduser()
                    if not value.is_file():
                        raise RuntimeError(f"Missing agent session referenced by {path}: {value}")
                    paths.add(value)
                stack.extend(item.values())
            elif isinstance(item, list):
                stack.extend(item)
    return sorted(paths)


def check_ignored(copies, repo):
    # Do not accidentally expose runtime data, plugin checkouts, or secrets to Git.
    if not copies:
        return
    names = [str(dst.relative_to(repo)) for _, dst in copies]
    result = subprocess.run(["git", "check-ignore", "--stdin", "-z"], cwd=repo,
                            input="\0".join(names) + "\0", text=True, capture_output=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr)
    ignored = set(result.stdout.rstrip("\0").split("\0"))
    missing = [name for name in names if name not in ignored]
    if missing:
        raise RuntimeError("Add ignore rules before migrating local files:\n" + "\n".join(missing[:20]))


def apply(home, repo, entries, agent_files):
    backup = home / ".local/state/dotfiles-backups" / datetime.datetime.now().strftime("herdr-%Y%m%d-%H%M%S-%f")
    backup.mkdir(parents=True, mode=0o700)
    created = []
    moved = []
    manifest = {"repo": str(repo), "directories": [], "agent_backups": []}
    # Save rollback instructions before moving anything. The original directories
    # themselves become the authoritative backup, including all session state.
    for src, dst, _ in entries:
        if not src.is_symlink():
            manifest["directories"].append({"source": str(src), "target": str(dst), "backup": str(backup / src.name)})
    (backup / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    try:
        for index, path in enumerate(agent_files):
            dest = backup / "agent-sessions" / str(index) / path.name
            dest.parent.mkdir(parents=True, mode=0o700)
            shutil.copy2(path, dest)
            if not filecmp.cmp(path, dest, shallow=False):
                raise RuntimeError(f"Agent backup verification failed: {path}")
            manifest["agent_backups"].append({"source": str(path), "backup": str(dest)})
        (backup / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        for src, dst, copies in entries:
            if src.is_symlink():
                continue
            for old, new in copies:
                parents = []
                parent = new.parent
                while not parent.exists():
                    parents.append(parent)
                    parent = parent.parent
                for parent in reversed(parents):
                    parent.mkdir()
                    created.append(parent)
                created.append(new)
                if old.is_symlink():
                    new.symlink_to(relocated_link(old, new, src, dst))
                else:
                    shutil.copy2(old, new)
                    if not filecmp.cmp(old, new, shallow=False):
                        raise RuntimeError(f"Copy verification failed: {new}")
            saved = backup / src.name
            src.rename(saved)
            moved.append((src, saved))
            src.symlink_to(os.path.relpath(dst, src.parent), target_is_directory=True)
        for src, dst, _ in entries:
            if not src.is_symlink() or src.resolve() != dst.resolve():
                raise RuntimeError(f"Directory link verification failed: {src}")
        for _, _, copies in entries:
            for _, new in copies:
                if new.is_symlink():
                    new.resolve(strict=True)
        agent_paths(home / ".config/herdr")
    except BaseException:
        for src, saved in reversed(moved):
            if src.is_symlink():
                src.unlink()
            saved.rename(src)
        for path in reversed(created):
            if path.is_dir() and not path.is_symlink():
                path.rmdir()
            elif os.path.lexists(path):
                path.unlink()
        raise
    print(f"Migration complete. Original directories and agent backups: {backup}")
    print("Rollback, with ALL Herdr servers stopped: unlink each config directory link,")
    print("then move its original directory back from this backup (see manifest.json).")
    print("Keep newer local/session files before rolling back. Do not restore old agent transcripts blindly.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="migrate only after all Herdr servers are stopped")
    args = parser.parse_args()
    home = Path.home()
    binary = os.environ.get("HERDR_BIN_PATH", "herdr")
    if not shutil.which(binary):
        binary = "herdr"
    running = [row["name"] for row in sessions(binary) if row["running"]]
    print("Running Herdr sessions:", ", ".join(running) or "none")
    if args.apply and (running or os.environ.get("HERDR_SOCKET_PATH")):
        raise RuntimeError("Run outside Herdr, after stopping ALL listed sessions. Nothing migrated.")
    entries = []
    for name in NAMES:
        source = home / ".config" / name
        target = REPO / "herdr/.config" / name
        copies = plan(source, target)
        check_ignored(copies, REPO)
        entries.append((source, target, copies))
        print(f"{source} -> {target}: {len(copies)} local files/links to preserve")
    agents = agent_paths(home / ".config/herdr")
    print(f"Verified {len(agents)} saved agent conversation paths; these will also be backed up.")
    print("Layouts and resume references are preserved; running processes do not survive a server stop.")
    if args.apply:
        if any(row["running"] for row in sessions(binary)):
            raise RuntimeError("A server started during checks; refusing migration")
        apply(home, REPO, entries, agents)
    else:
        print("CHECK ONLY: no files changed. Run again with --apply outside Herdr after all servers stop.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Migration refused/failed: {error}", file=sys.stderr)
        sys.exit(1)
