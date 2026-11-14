#!/usr/bin/env python3
"""The standalone check: each package works alone on a fresh machine.

  python3 .tests/standalone.py              check every package below
  python3 .tests/standalone.py eza ...      check the named packages
  python3 .tests/standalone.py --list       name the packages it checks

For each package it copies this working tree as a fresh clone would see it
(tracked and untracked files, not ignored ones), makes an empty home
directory, runs `./install <package>` with a clean environment whose PATH
holds the system tools, stow, and only the package's declared dependencies,
then starts the tool non-interactively (a full-screen tool, such as lazygit,
or an interactive shell, in a terminal of its own, where the check types the
keys that quit it). Any exit status other than 0, and any error output,
fails the check.

Then, for each declared dependency, it runs `./install <package>` again into
another empty home without that dependency on PATH, and checks that ./install
names it with its hint for this platform and still stows the package.

A package with optional dependencies may also be started on a machine that
has only its required ones: the tool must still start cleanly.

The dependencies must be installed where this runs: they are taken from PATH.
"""

import fcntl
import json
import os
import platform
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MANIFEST = "README.package.json"
PLATFORM = {"Darwin": "macos", "Linux": "linux"}[platform.system()]
SYSTEM_PATH = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
COLOR_CODE = re.compile(r"\x1b\[[0-9;]*m")
# direnv reports each file and `use` it loads as error output. Some versions
# (2.37.1) print these even when DIRENV_LOG_FORMAT is empty, so they are
# expected rather than silenced.
DIRENV_REPORTS = re.compile(r"direnv: (loading|using|export) ")
# run_in_terminal: the terminal's rows and columns, how long without output
# means the tool has finished drawing, and how long it may run in all.
TERMINAL_SIZE = (40, 160)
TERMINAL_QUIET = 1.5
TERMINAL_TIMEOUT = 20
# What a tool writes to a terminal besides text: colors, cursor moves, modes,
# and queries and titles (OSC and DCS strings, which end in BEL or ESC \).
TERMINAL_CODE = re.compile(r"\x1b(\[[0-?]*[ -/]*[@-~]|[\]P][^\x07\x1b]*(\x07|\x1b\\)|[()][0-9A-B]|[=>])")
# A full-screen tool asks the terminal to report mouse clicks with the first,
# and draws white text with the second.
MOUSE_REPORTING_ON = "\x1b[?1000h"
WHITE_TEXT = "\x1b[37m"
# What any terminal answers, and the check's terminal too: a Primary Device
# Attributes query (as a VT220 would) and a cursor position query (the top
# left corner). fish 4 asks both as it starts and waits up to 10 seconds for
# the first answer, then warns as error output.
TERMINAL_REPLIES = [(re.compile(rb"\x1b\[0?c"), b"\x1b[?62;22c"), (re.compile(rb"\x1b\[6n"), b"\x1b[1;1R")]
# Where Homebrew installs itself: Apple Silicon, Intel Macs, Linux.
HOMEBREW_PREFIXES = ["/opt/homebrew", "/usr/local", "/home/linuxbrew/.linuxbrew"]
# Tide's prompt character in the free Dracula theme's green (#50FA7B), as fish
# draws it in a terminal that shows 24-bit color.
DRACULA_PROMPT_CHARACTER = (re.compile("\x1b\\[38;2;80;250;123m[^\x1b]*❯".encode()),
                            "Tide prompt character in Dracula green")
# The commands that act on tmux (or herdr, the owner's multiplexer).
MULTIPLEXER_SHORTCUTS = ["ke", "ks", "tls", "a", "d", "dev", "sessionizer"]
# nvim-treesitter reports each step of a parser install as error output
# ("[nvim-treesitter/install/lua]: Compiling parser"); its errors read
# "[nvim-treesitter/install/lua] error: ..." and are not matched.
TREESITTER_REPORTS = re.compile(r"\[nvim-treesitter(/install/[\w-]+)?\]: ")
# vim-searchindex maps * and # with `silent! map <unique>`, which meets
# Neovim's own visual * and # mappings. Nothing is shown and nothing is
# broken, but v:errmsg keeps the message.
SEARCHINDEX_MAPPING = re.compile(r"E227: Mapping already exists for [#*]$")
# Neovim's first start clones every plugin and builds every parser; a later
# start only loads them.
NVIM_FIRST_START_TIMEOUT = 900
NVIM_START_TIMEOUT = 60
# Runs in Neovim once it has started (check_nvim). It finishes startup as a
# terminal would (a headless Neovim has no UIEnter, so lazy.nvim's VeryLazy
# plugins never load on their own), on a first start waits for
# nvim-treesitter's summary of its parser install, opens the Markdown note
# $NVIM_CHECK_NOTE, and writes what it finds to $NVIM_CHECK_REPORT.
NVIM_PROBE = r"""
local function probe()
	local function messages()
		return vim.fn.execute("messages")
	end
	local report = {}
	vim.api.nvim_exec_autocmds("UIEnter", {})
	report.very_lazy = vim.wait(30000, function()
		return vim.g.did_very_lazy == true
	end, 50)
	-- The install starts as nvim-treesitter loads; wait for its summary only once
	-- it has begun.
	local started = vim.env.NVIM_CHECK_PARSERS_MS and report.very_lazy and vim.wait(tonumber(vim.env.NVIM_CHECK_START_MS), function()
		return messages():find("[nvim-treesitter/install/", 1, true) ~= nil
	end, 500)
	if started then
		vim.wait(tonumber(vim.env.NVIM_CHECK_PARSERS_MS), function()
			return messages():find("Installed %d+/%d+ languages") ~= nil
		end, 500)
	end
	local installed, total = messages():match("Installed (%d+)/(%d+) languages")
	report.parsers_installed, report.parsers_total = tonumber(installed) or 0, tonumber(total) or 0
	report.python_parser = vim.treesitter.language.add("python") == true
	report.colors_name = vim.g.colors_name or vim.NIL

	local plugins = require("lazy.core.config").plugins
	local has_errors = require("lazy.core.plugin").has_errors
	report.missing, report.failed, report.loaded = {}, {}, {}
	for name, plugin in pairs(plugins) do
		if not plugin._.installed then
			table.insert(report.missing, name)
		end
		if has_errors(plugin) then
			table.insert(report.failed, name)
		end
		if plugin._.loaded then
			table.insert(report.loaded, name)
		end
	end

	vim.cmd.edit(vim.fn.fnameescape(vim.env.NVIM_CHECK_NOTE))
	vim.wait(2000) -- for anything opening the note starts later to report
	report.obsidian_loaded = plugins["obsidian.nvim"]._.loaded ~= nil
	report.vault_keys = vim.fn.maparg("<leader>dn", "n") ~= ""

	report.errmsg = vim.v.errmsg
	report.messages = messages()
	local file = assert(io.open(vim.env.NVIM_CHECK_REPORT, "w"))
	file:write(vim.json.encode(report))
	file:close()
end

-- A probe that fails must still end Neovim, with a status the check sees.
local ok, err = xpcall(probe, debug.traceback)
if not ok then
	io.stderr:write("probe: " .. err .. "\n")
	vim.cmd("cquit! 3")
end
vim.cmd("qall!")
"""


class Failed(Exception):
    pass


def fail_unless_clean(what, status, output, error_output, reports=None):
    """Fail on a non-zero exit status or any error output, apart from the
    lines `reports` matches."""
    lines = COLOR_CODE.sub("", error_output).splitlines()
    errors = [line for line in lines if line.strip() and not (reports and reports.match(line))]
    if status != 0 or errors:
        raise Failed(f"{what}: exit {status}\n{output}{error_output}".rstrip())


def run(args, env, cwd, what, reports=None, timeout=None):
    """Run a command; fail on a non-zero exit or any error output, or when it
    runs longer than `timeout` seconds. A tool that reports its normal
    progress as error output names those lines in `reports`."""
    try:
        result = subprocess.run(args, env=env, cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True, text=True,
                                timeout=timeout)
    except subprocess.TimeoutExpired as expired:
        # What it had written so far: text or bytes, depending on the Python.
        written = [text if isinstance(text, str) else (text or b"").decode(errors="replace")
                   for text in (expired.stdout, expired.stderr)]
        raise Failed(f"{what}: still running after {timeout}s\n{''.join(w[-3000:] for w in written)}".rstrip())
    fail_unless_clean(what, result.returncode, result.stdout, result.stderr, reports)
    return result.stdout


def run_in_terminal(args, env, cwd, what, keys, wait_for=None):
    """Run a full-screen tool in a terminal of its own: once it has drawn its
    screen and gone quiet, type `keys`, which must make it exit. A tool that
    goes quiet before its screen is complete (fish draws Tide's prompt once a
    background job has worked it out) names in `wait_for` what the screen must
    hold first: a pattern and what it stands for. The terminal answers the
    queries in TERMINAL_REPLIES. Fail on a non-zero exit, any error output, or
    a screen that never holds it; return what it drew on the terminal."""
    leader, follower = pty.openpty()
    fcntl.ioctl(follower, termios.TIOCSWINSZ, struct.pack("HHHH", *TERMINAL_SIZE, 0, 0))

    def own_terminal():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    drawn, typed = b"", False
    answered = [0] * len(TERMINAL_REPLIES)
    deadline = time.monotonic() + TERMINAL_TIMEOUT
    # Error output goes to a file, apart from the screen. A file never fills
    # up and blocks the tool, as an unread pipe would.
    with tempfile.TemporaryFile() as error_file:
        process = subprocess.Popen(args, env=env, cwd=cwd, stdin=follower, stdout=follower, stderr=error_file,
                                   preexec_fn=own_terminal)
        os.close(follower)
        try:
            while process.poll() is None and time.monotonic() < deadline:
                ready, _, _ = select.select([leader], [], [], TERMINAL_QUIET)
                if ready:
                    try:
                        drawn += os.read(leader, 65536)
                    except OSError:  # the tool closed the terminal
                        break
                    for i, (query, reply) in enumerate(TERMINAL_REPLIES):
                        asked = len(query.findall(drawn))
                        if asked > answered[i]:
                            os.write(leader, reply * (asked - answered[i]))
                            answered[i] = asked
                elif drawn and not typed and (wait_for is None or wait_for[0].search(drawn)):
                    os.write(leader, keys)
                    typed = True
            status = process.wait(timeout=max(0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            status = None
        finally:
            os.close(leader)
        error_file.seek(0)
        error_output = error_file.read().decode(errors="replace")
    screen = drawn.decode(errors="replace")
    text = TERMINAL_CODE.sub("", screen)
    if status is None and not typed and wait_for:
        raise Failed(f"{what}: no {wait_for[1]} after {TERMINAL_TIMEOUT}s; the terminal showed:\n"
                     f"{text}{error_output}".rstrip())
    if status is None:
        raise Failed(f"{what}: still running after {TERMINAL_TIMEOUT}s\n{text}{error_output}".rstrip())
    fail_unless_clean(what, status, text, error_output)
    return screen


# Each check starts the package's tool on the machine and raises Failed when
# it does not start cleanly or ignores the package's config.

def check_direnv(machine):
    project = machine.home / "project"
    project.mkdir()
    (project / ".envrc").write_text("use project_bins\n")
    run(["direnv", "allow", str(project)], machine.env, machine.home, "direnv allow", DIRENV_REPORTS)
    path = run(["direnv", "exec", str(project), "sh", "-c", 'printf %s "$PATH"'], machine.env, machine.home,
               "direnv exec", DIRENV_REPORTS)
    tail = path.split(":")[-2:]
    if not (tail[0].endswith("/project/bin") and tail[1].endswith("/project/node_modules/.bin")):
        raise Failed(f"direnv did not load direnvrc's use_project_bins; PATH ends {tail}")


def check_eza(machine):
    folder = machine.home / "listing"
    folder.mkdir()
    (folder / "diagram.puml").write_text("")
    # eza applies theme.yml only when it colors its output.
    listing = run(["eza", "--icons=always", "--color=always", str(folder)], machine.env, machine.home, "eza")
    if "\uf1c1" not in listing:
        raise Failed(f"eza did not read theme.yml: no document icon for diagram.puml in {listing!r}")


def check_fish_first_start(machine, what, env):
    """Start fish as a terminal does, an interactive login shell, on a day
    it greets the user; once Tide's prompt is drawn in free Dracula colors,
    type `exit`. Fail on any error output, a prompt that never comes, or a
    greeting without the user's name."""
    (machine.home / ".config/fish/fish_greeting_last_run").write_text("2000-01-01\n")
    terminal = dict(env, TERM="xterm-256color", COLORTERM="truecolor")
    screen = run_in_terminal(["fish", "--login"], terminal, machine.home, what, keys=b"exit\r",
                             wait_for=DRACULA_PROMPT_CHARACTER)
    text = TERMINAL_CODE.sub("", screen)
    greeting = f"hello, {env['USER']}"
    if greeting not in text:
        raise Failed(f"{what}: the greeting does not say {greeting!r}; the terminal showed:\n{text}".rstrip())


def forgetting_fish_state(check):
    """fish keeps its settings (Tide's among them) and the greeting's date in
    ~/.config/fish, which is the clone: remove what a check left there, so the
    next machine starts fresh."""
    def checked(machine):
        folder = machine.clone / "fish/.config/fish"
        before = set(folder.rglob("*"))
        try:
            check(machine)
        finally:
            for path in sorted(set(folder.rglob("*")) - before, reverse=True):
                if path.is_dir() and not path.is_symlink():
                    path.rmdir()
                else:
                    path.unlink()
    return checked


def fail_unless_fish_only_says(machine, env, command, expected, what):
    """Run `command` in an interactive fish. It must fail, saying one line of
    error output that holds `expected`, and nothing else. Not a login shell:
    on macOS a login fish adds the real /usr/local/bin and /usr/bin
    (/etc/paths) to PATH, and a command run here must find only the machine's
    own tools."""
    result = subprocess.run(["fish", "--interactive", "--command", command], env=env, cwd=machine.home,
                            stdin=subprocess.DEVNULL, capture_output=True, text=True)
    lines = result.stderr.strip().splitlines()
    if result.returncode == 0 or result.stdout or len(lines) != 1 or expected not in lines[0]:
        raise Failed(f"{what}: exit {result.returncode}; expected one line holding {expected!r}\n"
                     f"{result.stdout}{result.stderr}".rstrip())


@forgetting_fish_state
def check_fish(machine):
    check_fish_first_start(machine, "fish's first start", machine.env)
    output = run(["fish", "--login", "--interactive", "--command",
                  "printf 'brew=%s\\n' (command -s brew); functions ls | string match -q '*eza *'; and echo ls=eza; "
                  "set -q VIRTUAL_ENV_DISABLE_PROMPT; and echo virtualenv=tide; true"],
                 machine.env, machine.home, "fish --login --interactive")
    homebrew = next((p for p in HOMEBREW_PREFIXES if os.access(f"{p}/bin/brew", os.X_OK)), None)
    if homebrew and f"brew={homebrew}/bin/brew" not in output.splitlines():
        raise Failed(f"fish did not put Homebrew ({homebrew}) on PATH:\n{output}".rstrip())
    if "ls=eza" not in output.splitlines():
        raise Failed("fish did not alias ls to eza with eza installed")
    # Otherwise a Python virtualenv puts its own name before Tide's prompt,
    # which already shows it.
    if "virtualenv=tide" not in output.splitlines():
        raise Failed("fish's first start did not leave a virtualenv's name to Tide (VIRTUAL_ENV_DISABLE_PROMPT)")
    # tmux is installed, but its sessionizer script is not part of this package.
    fail_unless_fish_only_says(machine, machine.env, "sessionizer", "tmux-sessionizer.sh",
                               "fish's sessionizer with tmux but no sessionizer script")


@forgetting_fish_state
def check_fish_with_required_only(machine):
    """Without tmux, herdr or Homebrew (HOMEBREW_PREFIX, which fish takes
    from its environment as a nested shell would, names a folder without it,
    so no Homebrew tool joins PATH), nor the optional tools: fish starts
    cleanly, and each multiplexer shortcut says in one line that no
    multiplexer is installed."""
    env = dict(machine.env, HOMEBREW_PREFIX=str(machine.root / "no-homebrew"))
    check_fish_first_start(machine, "fish's first start with only fish", env)
    for shortcut in MULTIPLEXER_SHORTCUTS:
        fail_unless_fish_only_says(machine, env, shortcut, "no multiplexer installed",
                                   f"fish's {shortcut} without tmux or herdr")


def check_lazygit(machine):
    config = machine.home / ".config/lazygit"
    folder = run(["lazygit", "--print-config-dir"], machine.env, machine.home, "lazygit --print-config-dir")
    if folder.strip() != str(config):
        raise Failed(f"lazygit reads its config from {folder.strip()}, not {config}")
    project = machine.home / "project"
    project.mkdir()
    run(["git", "init", "-q", str(project)], machine.env, machine.home, "git init")

    def package_files():
        return set(machine.clone.glob("lazygit/**/*"))

    stowed = package_files()
    terminal = dict(machine.env, TERM="xterm-256color")
    screen = run_in_terminal(["lazygit"], terminal, project, "lazygit", keys=b"q")
    # config.yml leaves the mouse to the terminal and draws text in white.
    # Without it lazygit turns mouse reporting on and uses the terminal's own
    # text color.
    if MOUSE_REPORTING_ON in screen:
        raise Failed("lazygit ignored config.yml: it turned on mouse reporting (gui.mouseEvents: false)")
    if WHITE_TEXT not in screen:
        raise Failed("lazygit ignored config.yml: no white text (gui.theme.defaultFgColor: white)")
    # A lazygit that kept its state beside its config would write it through
    # the stowed link into the clone.
    written = sorted(package_files() - stowed)
    if written:
        raise Failed(f"lazygit wrote into the clone: {[str(p.relative_to(machine.clone)) for p in written]}")


def start_nvim(machine, what, note, first_start=False, builds_parsers=False):
    """Start Neovim with NVIM_PROBE, which opens `note`; fail on any error it
    reports. A first start installs every plugin, and where the machine can
    build Treesitter parsers, the probe waits for them. Return the probe's
    report."""
    probe, report_file = machine.root / "probe.lua", machine.root / "report.json"
    probe.write_text(NVIM_PROBE)
    env = dict(machine.env, NVIM_CHECK_REPORT=str(report_file), NVIM_CHECK_NOTE=str(note))
    timeout = NVIM_FIRST_START_TIMEOUT if first_start else NVIM_START_TIMEOUT
    if builds_parsers:
        env["NVIM_CHECK_START_MS"] = str(NVIM_START_TIMEOUT * 1000)
        env["NVIM_CHECK_PARSERS_MS"] = str((NVIM_FIRST_START_TIMEOUT - NVIM_START_TIMEOUT) * 1000)
    run(["nvim", "--headless", "-c", f"lua vim.schedule(function() dofile([[{probe}]]) end)"], env, machine.home,
        what, TREESITTER_REPORTS, timeout=timeout)
    report = json.loads(report_file.read_text())
    errors = [line for line in report["messages"].splitlines() if re.search(r"\bE\d+:|[Ee]rror", line)]
    errmsg = "" if SEARCHINDEX_MAPPING.match(report["errmsg"]) else report["errmsg"]
    if errmsg or errors:
        raise Failed(f"{what} reported errors:\n" + "\n".join([errmsg, *errors]).strip())
    if report["colors_name"] != "dracula":
        raise Failed(f"{what}: the colorscheme is {report['colors_name']}, not the free Dracula theme")
    return report


def fail_unless_plugins_ready(what, report):
    if report["missing"] or report["failed"]:
        raise Failed(f"{what} did not install {sorted(report['missing'])}; "
                     f"failed to install or build {sorted(report['failed'])}")
    lazy_loaded = {"which-key.nvim", "lualine.nvim", "gitsigns.nvim"}
    if not report["very_lazy"] or not lazy_loaded <= set(report["loaded"]):
        raise Failed(f"{what} did not load its plugins once started: loaded {sorted(report['loaded'])}")


def check_nvim(machine):
    lockfile = machine.clone / "nvim/.config/nvim/lazy-lock.json"
    locked = lockfile.read_text()
    note = machine.home / "note.md"
    note.write_text("# A note\n\nSee [[Elsewhere]].\n")

    report = start_nvim(machine, "nvim's first start", note, first_start=True, builds_parsers=True)
    fail_unless_plugins_ready("nvim's first start", report)
    installed, total = report["parsers_installed"], report["parsers_total"]
    if not total or installed != total or not report["python_parser"]:
        raise Failed(f"nvim's first start did not install every Treesitter parser: installed {installed} of {total}")
    if report["obsidian_loaded"] or report["vault_keys"]:
        raise Failed("nvim set up Obsidian (obsidian.nvim or the vault keys) with no vault configured")
    if lockfile.read_text() != locked:
        raise Failed("nvim's first start changed lazy-lock.json in the clone")

    # A local override that names a vault: a note in it gets obsidian.nvim.
    vault = machine.home / "notes"
    (vault / ".obsidian").mkdir(parents=True)
    (vault / "Note.md").write_text("# Note\n")
    override = machine.clone / "nvim/.config/nvim/lua/config/local.lua"
    override.write_text(f"vim.g.obsidian_vault = [[{vault}]]\n")
    try:
        report = start_nvim(machine, "nvim with a local override naming a vault", vault / "Note.md")
    finally:
        override.unlink()
    if not (report["obsidian_loaded"] and report["vault_keys"]):
        raise Failed("nvim ignored the vault the local override names: no obsidian.nvim or vault keys for its note")


def check_nvim_with_required_only(machine):
    """Without ripgrep, curl, the tree-sitter CLI or a C compiler: plugins
    still install, no parser is built, and nothing reports an error."""
    what = "nvim's first start with only its required dependencies"
    note = machine.home / "note.md"
    note.write_text("# A note\n")
    report = start_nvim(machine, what, note, first_start=True)
    fail_unless_plugins_ready(what, report)


CHECKS = {"direnv": check_direnv, "eza": check_eza, "fish": check_fish, "lazygit": check_lazygit,
          "nvim": check_nvim}
# For a package with optional dependencies: its tool on a machine that has
# only the required ones.
REQUIRED_ONLY_CHECKS = {"fish": check_fish_with_required_only, "nvim": check_nvim_with_required_only}


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
        self.root = root
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
            # A tmux that a check reaches by mistake talks to a server of the
            # machine's own, never to this user's.
            "TMUX_TMPDIR": str(root / "tmp"),
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

    if package in REQUIRED_ONLY_CHECKS:
        required = [d["command"] for d in manifest["dependencies"] if d["required"]]
        with tempfile.TemporaryDirectory() as temp:
            machine = Machine(Path(temp).resolve(), clone, required, hidden)
            result = machine.install(package)
            if result.returncode != 0:
                raise Failed(f"./install {package} with only its required dependencies: exit {result.returncode}\n"
                             f"{result.stdout}{result.stderr}".rstrip())
            REQUIRED_ONLY_CHECKS[package](machine)

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
