#!/usr/bin/env python3
"""The standalone check: each package works alone on a fresh machine.

  python3 .tests/standalone.py              check every package below
  python3 .tests/standalone.py eza ...      check the named packages
  python3 .tests/standalone.py --list       name the packages it checks

For each package it copies this working tree as a fresh clone would see it
(tracked and untracked files, not ignored ones), makes an empty home
directory, runs `./install <package>` with a clean environment whose PATH
holds the system tools, stow, and only the package's declared dependencies,
then starts the tool non-interactively. Any exit status other than 0, and any
error output, fails the check.

Then, for each declared dependency, it runs `./install <package>` again into
another empty home without that dependency on PATH, and checks that ./install
names it with its hint for this platform and still stows the package.

The dependencies must be installed where this runs: they are taken from PATH.
"""

import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MANIFEST = "README.package.json"
PLATFORM = {"Darwin": "macos", "Linux": "linux"}[platform.system()]
SYSTEM_PATH = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]


class Failed(Exception):
    pass


def run(args, env, cwd, what):
    """Run a command; fail on a non-zero exit or any error output."""
    result = subprocess.run(args, env=env, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0 or result.stderr.strip():
        raise Failed(f"{what}: exit {result.returncode}\n{result.stdout}{result.stderr}".rstrip())
    return result.stdout


# Each check starts the package's tool on the machine and raises Failed when
# it does not start cleanly or ignores the package's config.

def check_direnv(machine):
    project = machine.home / "project"
    project.mkdir()
    (project / ".envrc").write_text("use project_bins\n")
    env = dict(machine.env, DIRENV_LOG_FORMAT="")
    run(["direnv", "allow", str(project)], env, machine.home, "direnv allow")
    path = run(["direnv", "exec", str(project), "sh", "-c", 'printf %s "$PATH"'], env, machine.home, "direnv exec")
    tail = path.split(":")[-2:]
    if not (tail[0].endswith("/project/bin") and tail[1].endswith("/project/node_modules/.bin")):
        raise Failed(f"direnv did not load direnvrc's use_project_bins; PATH ends {tail}")


def check_eza(machine):
    folder = machine.home / "listing"
    folder.mkdir()
    (folder / "diagram.puml").write_text("")
    listing = run(["eza", "--icons=always", "--color=always", str(folder)], machine.env, machine.home, "eza")
    if "\uf1c1" not in listing:
        raise Failed(f"eza did not read theme.yml: no document icon for diagram.puml in {listing!r}")


CHECKS = {"direnv": check_direnv, "eza": check_eza}


def manifests():
    return {p.parent.name: json.loads(p.read_text()) for p in sorted(REPO.glob(f"*/{MANIFEST}"))}


def copy_tree(clone):
    """This working tree as a fresh clone would see it."""
    listed = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                            cwd=REPO, check=True, capture_output=True).stdout.decode()
    for name in filter(None, listed.split("\0")):
        source, target = REPO / name, clone / name
        if not source.is_symlink() and not source.exists():
            continue  # deleted but not yet staged
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_symlink():
            os.symlink(os.readlink(source), target)
        else:
            shutil.copy2(source, target)


def link_commands(folder, commands):
    """A folder of links to each command as found on this PATH."""
    folder.mkdir(parents=True)
    for command in commands:
        found = shutil.which(command)
        if not found:
            raise Failed(f"{command} is not installed here, so the check cannot run")
        os.symlink(found, folder / command)


def system_tools(folder, hidden):
    """A folder of links to the system's tools, except the hidden ones (on Linux
    a package manager installs dependencies among the system tools)."""
    folder.mkdir(parents=True)
    for directory in SYSTEM_PATH:
        if not os.path.isdir(directory):
            continue
        for entry in os.scandir(directory):
            target = folder / entry.name
            if entry.name in hidden or os.path.lexists(target):
                continue
            if os.access(entry.path, os.X_OK) and not entry.is_dir():
                os.symlink(entry.path, target)


class Machine:
    """A fresh machine in a temporary directory: a copy of the clone, an empty
    home, and a PATH of the system tools, stow, and the given commands."""

    def __init__(self, root, clone, commands, hidden):
        self.home = root / "home"
        self.home.mkdir()
        (root / "tmp").mkdir()
        system_tools(root / "system", hidden)
        link_commands(root / "deps", ["stow", *commands])
        self.clone = clone
        self.env = {
            "HOME": str(self.home),
            "PATH": os.pathsep.join([str(root / "deps"), str(root / "system")]),
            "USER": os.environ.get("USER", "adopter"),
            "LOGNAME": os.environ.get("USER", "adopter"),
            "TMPDIR": str(root / "tmp"),
        }

    def install(self, package):
        return subprocess.run([str(self.clone / "install"), package], env=self.env, cwd=self.home,
                              capture_output=True, text=True)

    def links(self):
        return [p for p in self.home.rglob("*") if p.is_symlink()]


def check(package, manifest, clone, hidden):
    commands = [d["command"] for d in manifest["dependencies"]]
    with tempfile.TemporaryDirectory() as temp:
        machine = Machine(Path(temp).resolve(), clone, commands, hidden)
        # With every dependency present, ./install has nothing to report.
        reported = run([str(clone / "install"), package], machine.env, machine.home, f"./install {package}")
        if reported.strip():
            raise Failed(f"./install {package} reported, with every dependency installed:\n{reported}".rstrip())
        for shared in (".config", "Library", "Library/Application Support"):
            if (machine.home / shared).is_symlink():
                raise Failed(f"./install {package} linked ~/{shared} into the clone")
        CHECKS[package](machine)

    for dependency in manifest["dependencies"]:
        missing = dependency["command"]
        with tempfile.TemporaryDirectory() as temp:
            others = [c for c in commands if c != missing]
            machine = Machine(Path(temp).resolve(), clone, others, hidden)
            result = machine.install(package)
            output = result.stdout + result.stderr
            line = next((l for l in output.splitlines() if missing in l and dependency["hint"][PLATFORM] in l), None)
            if result.returncode != 0 or line is None:
                raise Failed(f"./install {package} without {missing}: exit {result.returncode}; "
                             f"expected {missing} named with its hint\n{output}".rstrip())
            if not machine.links():
                raise Failed(f"./install {package} without {missing} stowed nothing")


def main(args):
    known = manifests()
    if args == ["--list"]:
        print("\n".join(name for name in CHECKS if PLATFORM in known[name]["platforms"]))
        return 0
    packages = args or [name for name in CHECKS if PLATFORM in known[name]["platforms"]]
    unknown = [name for name in packages if name not in CHECKS]
    if unknown:
        print(f"no standalone check for: {', '.join(unknown)}", file=sys.stderr)
        return 2
    # Every declared dependency is hidden from the system tools, so each
    # package sees only its own.
    hidden = {d["command"] for m in known.values() for d in m["dependencies"]}
    failures = 0
    with tempfile.TemporaryDirectory() as temp:
        clone = Path(temp).resolve() / "dotfiles"
        copy_tree(clone)
        for package in packages:
            try:
                check(package, known[package], clone, hidden)
                print(f"ok    {package}")
            except Failed as failure:
                failures += 1
                print(f"FAIL  {package}: {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
