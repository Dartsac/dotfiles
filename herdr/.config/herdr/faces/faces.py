#!/usr/bin/env python3
"""Faces: a little character beside every agent and workspace in Herdr's sidebar.

The character shows the agent's state by what it is doing: awake at a prompt
when ready, asleep when idle, busy (and animated) while working, waving when it
needs you, pleased when done. A space with no agent in it shows the character
with a blank screen. Only the character has the state's color (gray when
empty or asleep); every line of text has its workspace's color (identity.py),
and so does Bit, which is text.

Ready is this plugin's own state. Herdr calls an agent idle as soon as it is
neither working nor waiting to be seen; here it stays ready until it has gone
ten minutes (`faces.py awake <minutes>`) without being given work, and only
then falls asleep.
It works for every agent Herdr lists, whatever harness runs it, because it only
reads Herdr's own state.

    faces.py run            keep the faces up to date (Herdr starts this; see herdr-plugin.toml)
    faces.py pick           choose the character in a picker (bound to prefix i)
    faces.py set <choice>   choose it from the command line: byte, wisp, bit or mixed
    faces.py awake <min>    how long an agent stays ready after its last work (0: never)
    faces.py show           print the current choice and every character's faces
    faces.py rules          print the tokens and their color rules, as config.base.toml must have them

`run` is one long-lived process per Herdr server. It reads the session about
once a second (every 0.4s while an agent is working, to step the animation) and
sets these tokens, which the sidebar rows show:

    face     line 1  the character, then the task or the workspace's name; a
                     worktree space's name is its job (space_name)
    detail   line 2  workspace and agent; for a workspace, its branch,
                     ahead/behind counts and changed files; for a worktree
                     space, its progress or "merged · remove?" (progress_text)
    note     line 3  the agent's activity, when it says more than the face
    alert    line 3  instead of note, in bold, when the activity needs you
    tree1-6  then    a Pi parent's subagents, one per line, as a tree:
                     `├── <face> reviewer`, from its child1-6 tokens, and
                     their own subagents one level deeper: `│   └── <face> scout`

Lines 2 and 3 are this plugin's work only so that they can start under the
name: Herdr indents them by a fixed two cells, so each begins with blank cells
that make up the difference.

Herdr runs it at startup and again on agent and focus events; a second copy
sees the first one's lock and exits, so a copy that died is replaced the next
time anything happens.

Working agent and workspace faces animate on the same frame clock. Other
rows stay still. Herdr logs workspace metadata updates, but its existing
server-log writer caps the file at 5 MiB; no extra rotation is needed.
"""
import fcntl
import hashlib
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, os.pardir, "scripts")]
from characters import CHARACTERS, CHOICES, DEFAULT_CHOICE, FACE_LABELS, FACES, STATES, character_for, face, indent  # noqa: E402
import identity  # noqa: E402
from identity import TitleColors  # noqa: E402

PLUGIN_ID = "dotfiles.faces"
SOURCE = "dotfiles:faces"
TOKEN = "face"
DETAIL, NOTE, ALERT = "detail", "note", "alert"
# The dotfiles Pi reporter's children of a parent ("<state> <name>", "sub
# <state> <name>" for a subagent's own subagent, or "more <n>"), and the tree
# lines drawn from them. pi-extension/children.mjs TREE_ROWS and
# config.base.toml's rows match this count.
CHILDREN = tuple("child%d" % n for n in range(1, 7))
TREE = tuple("tree%d" % n for n in range(1, 7))
BRANCH, LAST = "├── ", "└── "
SUB = "sub "                 # a row one level deeper, under the subagent above it (children.mjs SUB)
TRUNK, GAP = "│   ", "    "   # before a deeper row: its subagent has a row after it, or not
QUIET = ("Ready", "Working", "Finished")   # activities the face already shows
NEEDS_YOU = ("Waiting for you", "60s", "Failed", "not done")   # activities shown in bold
BUSY = ("working", "blocked")             # being given work, or in the middle of it
AWAKE_MINUTES = 10           # an idle agent stays ready this long after its last work
GIT_SECONDS = 4              # between looks at each workspace's branch and each worktree's progress
FRAME_SECONDS = 0.4          # one animation step
IDLE_SECONDS = 1.0           # between looks when nothing is working
# How long a face outlives a dead updater, and how often it is sent again so
# that it never expires under a live one. Unchanged workspace tokens are
# renewed rarely; animation updates only the face, not git/detail tokens.
TTL_MS = {"pane": 300_000, "workspace": 86_400_000}
REFRESH_SECONDS = {"pane": 60, "workspace": 6 * 3600}
VALUE_LIMIT = 80             # Herdr cuts token values here
GIVE_UP_AFTER = 5            # failed reads in a row: the server has gone


# ---- what the sidebar should show ------------------------------------------
def fit(glyphs, name):
    return (glyphs + " " + name)[:VALUE_LIMIT].rstrip()


def status_of(entry, awake=frozenset()):
    """The state to show. `awake` holds the panes whose idle agents are still ready."""
    status = entry.get("agent_status")
    if status == "idle" and entry.get("pane_id") in awake:
        return "ready"
    return status if status in STATES else "unknown"


def agents_by_workspace(snapshot, awake=frozenset()):
    found = {}
    for agent in snapshot.get("agents") or []:
        found.setdefault(agent.get("workspace_id"), []).append((status_of(agent, awake), agent.get("agent") or ""))
    return found


def workspace_status(workspace, agents):
    """Herdr's roll-up of the workspace's agents; an idle one is ready while any agent in it is."""
    status = status_of(workspace)
    return "ready" if status == "idle" and any(s == "ready" for s, _ in agents or ()) else status


def workspace_character(workspace, agents, choice):
    """(the character a workspace wears, which of its FACES it shows).

    It wears the character of an agent in the workspace's state; with no
    agent, the one an agent of no known kind would get, with its empty face."""
    if not agents:
        return character_for(choice, ""), "empty"
    status = workspace_status(workspace, agents)
    return character_for(choice, next((k for s, k in agents if s == status), agents[0][1])), status


class Awake:
    """Which agents are still awake: at work, or first seen, less than a while ago.

    Keeps the time each agent was last seen busy, in a file, so that a
    restarted updater does not wake everyone up. An agent seen for the first
    time counts from then."""

    def __init__(self, path, now=time.time):
        self.path, self.now = path, now
        try:
            with open(path) as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = {}
        self.rested = {k: v for k, v in data.items() if isinstance(v, (int, float))} if isinstance(data, dict) else {}

    def update(self, snapshot, seconds):
        """The panes whose agents stopped work less than `seconds` ago."""
        now = self.now()
        rested = {a["pane_id"]: self.rested.get(a["pane_id"], now)
                  for a in snapshot.get("agents") or [] if a.get("agent_status") not in BUSY}
        if rested != self.rested:               # only when an agent starts, stops, arrives or leaves
            self.rested = rested
            try:
                with open(self.path + ".tmp", "w") as f:
                    json.dump(rested, f)
                os.replace(self.path + ".tmp", self.path)
            except OSError:
                pass
        return frozenset(pane for pane, since in rested.items() if now - since < seconds)


WORKTREE_BRANCH_PREFIX = "worktree/"   # before the branch name of a worktree Herdr creates
PANE_NUMBERS = "123456789ABCDEFGHJKMNPQRSTVWXYZ0"   # Herdr's pane ids: "<workspace>:p<n>", n counting up in these digits


def linked_checkout(workspace):
    """A worktree space's checkout folder, or None for any other space."""
    worktree = workspace.get("worktree") or {}
    return worktree.get("checkout_path") if worktree.get("is_linked_worktree") else None


def creation_order(pane_id):
    """A pane's place in the order its workspace got its panes (unknown ids last).

    Herdr numbers a pane when it is created in a workspace, or moved into it,
    and never gives a number out twice."""
    digits = (pane_id or "").rpartition(":p")[2]
    if not digits or any(digit not in PANE_NUMBERS for digit in digits):
        return float("inf")
    number = 0
    for digit in digits:
        number = number * len(PANE_NUMBERS) + PANE_NUMBERS.index(digit) + 1
    return number


def space_name(workspace, snapshot, git_line):
    """The name on a space's line 1. A worktree space is named after its job,
    after the area the project picker made it for (`herdr/sidebar-names`)."""
    label = workspace.get("label") or ""
    checkout = linked_checkout(workspace)
    # Herdr labels a worktree space after its checkout's folder; any other label is the owner's own.
    if not checkout or label != os.path.basename(checkout.rstrip("/")):
        return label
    area = (workspace.get("tokens") or {}).get("area")
    job = job_name(workspace, snapshot, git_line, checkout, label)
    return f"{area}/{job}" if area else job


def job_name(workspace, snapshot, git_line, checkout, label):
    """A worktree space's job: its first agent's task, else its branch without Herdr's prefix."""
    agents = [a for a in snapshot.get("agents") or [] if a.get("workspace_id") == workspace["workspace_id"]]
    if agents:
        first = min(agents, key=lambda a: creation_order(a.get("pane_id")))
        task = (first.get("tokens") or {}).get("topic")
        if task:
            return task
    return branch_of(git_line(checkout)).removeprefix(WORKTREE_BRANCH_PREFIX) or label


def wanted(snapshot, choice, frame, awake=frozenset(), git_line=lambda folder: None):
    """({("pane"|"workspace", id): text or None}, is any agent working).

    None clears the token: the pane has a face but no agent any more.
    `git_line` gives a folder's branch line (git_line below), for the name of
    a worktree space whose first agent has no task yet."""
    tabs = {t["tab_id"]: t.get("label") or "" for t in snapshot.get("tabs") or []}
    want, working = {}, False
    for agent in snapshot.get("agents") or []:
        status = status_of(agent, awake)
        kind = agent.get("agent") or ""
        name = (agent.get("tokens") or {}).get("topic") or tabs.get(agent.get("tab_id")) or kind or "agent"
        want[("pane", agent["pane_id"])] = fit(face(character_for(choice, kind), status, frame), name)
        working = working or status == "working"
    for pane in snapshot.get("panes") or []:
        if TOKEN in (pane.get("tokens") or {}) and ("pane", pane["pane_id"]) not in want:
            want[("pane", pane["pane_id"])] = None
    by_workspace = agents_by_workspace(snapshot, awake)
    for workspace in snapshot.get("workspaces") or []:
        agents = by_workspace.get(workspace["workspace_id"])
        character, which = workspace_character(workspace, agents, choice)
        # Use the agent frame clock so the working face moves in both panels.
        want[("workspace", workspace["workspace_id"])] = fit(face(character, which, frame), space_name(workspace, snapshot, git_line))
        working = working or which == "working"
    return want, working


def folder_of(workspace, snapshot):
    """Where a workspace's repository is looked for: a worktree space's checkout, else its project, else its first pane's folder."""
    folder = linked_checkout(workspace) or (workspace.get("tokens") or {}).get("project_path")
    if folder:
        return folder
    for pane in snapshot.get("panes") or []:
        if pane.get("workspace_id") == workspace["workspace_id"] and (pane.get("cwd") or pane.get("foreground_cwd")):
            return pane.get("cwd") or pane.get("foreground_cwd")
    return None


def progress_text(progress, changes):
    """What a worktree space's line 2 says before its changed files: "↑3", or
    "merged · remove?" once its work has landed and no file is changed. None
    with no commit ahead of main."""
    ahead, landed = progress
    if landed and not changes:
        return "merged · remove?"
    return "↑%d" % ahead if ahead else None


def space_and_folder(agent, labels, snapshot):
    """An agent's space, and the first folder below the space's project folder
    that the agent works in (`dotfiles/herdr`): the space alone at the project
    folder, outside it, or in a space with no project folder."""
    label = labels.get(agent.get("workspace_id")) or ""
    workspace = next((w for w in snapshot.get("workspaces") or [] if w["workspace_id"] == agent.get("workspace_id")), {})
    project = (workspace.get("tokens") or {}).get("project_path")
    folder = agent.get("foreground_cwd") or agent.get("cwd")
    if not (label and project and folder):
        return label
    project, folder = os.path.normpath(project), os.path.normpath(folder)
    if not folder.startswith(project + os.sep):
        return label
    return f"{label}/{folder[len(project) + 1:].split(os.sep)[0]}"


def described(snapshot, choice, git_line, awake=frozenset(), progress_of=lambda checkout: None):
    """{("pane"|"workspace", id): {"detail": text or None, "note": text or None, "alert": text or None}}: lines 2 and 3.

    Line 2 of a space is its branch (`git_line` gives a folder's), then its
    changed files. A worktree space has its progress in place of the branch
    (`progress_of` gives a checkout's worktree_progress), once that is read.
    Line 3 is the activity: `alert` when it needs you, otherwise `note`.
    Each starts with the blank cells that put it under the name. None clears a
    token that is set and no longer wanted; a token that is neither is left out."""
    def under(character, text):
        return (indent(character) + text)[:VALUE_LIMIT].rstrip() if text else None

    def lines(have, **want):
        return {token: text for token, text in want.items() if text is not None or token in have}

    labels = {w["workspace_id"]: w.get("label") or "" for w in snapshot.get("workspaces") or []}
    out = {}
    for agent in snapshot.get("agents") or []:
        tokens, kind = agent.get("tokens") or {}, agent.get("agent") or ""
        character = character_for(choice, kind)
        where = " · ".join(part for part in (space_and_folder(agent, labels, snapshot), kind) if part)
        activity = tokens.get("activity") or ""
        activity = under(character, "" if activity in QUIET else activity)
        urgent = bool(activity) and any(words in activity for words in NEEDS_YOU)
        out[("pane", agent["pane_id"])] = lines(tokens, detail=under(character, where),
                                               note=None if urgent else activity, alert=activity if urgent else None)
    for pane in snapshot.get("panes") or []:
        if ("pane", pane["pane_id"]) not in out:                 # no agent here any more
            out[("pane", pane["pane_id"])] = lines(pane.get("tokens") or {}, detail=None, note=None, alert=None)
    by_workspace = agents_by_workspace(snapshot, awake)
    for workspace in snapshot.get("workspaces") or []:
        tokens = workspace.get("tokens") or {}
        character, _ = workspace_character(workspace, by_workspace.get(workspace["workspace_id"]), choice)
        changes, checkout = tokens.get("changes"), linked_checkout(workspace)
        progress = progress_of(checkout) if checkout else None
        if progress is not None:
            first = progress_text(progress, changes)
        else:
            folder = folder_of(workspace, snapshot)
            first = git_line(folder) if folder else None
        git = " · ".join(part for part in (first, changes) if part)
        out[("workspace", workspace["workspace_id"])] = lines(tokens, detail=under(character, git))
    return {key: value for key, value in out.items() if value}


def depth_of(row):
    """(is it a subagent's own subagent, the row without its depth mark)."""
    return (True, row[len(SUB):]) if row.startswith(SUB) else (False, row)


def trees(snapshot, choice, frame):
    """({("pane", id): {"tree1": text or None, ...}}, is any child working): each parent's children.

    Lines start under the parent's name, like line 2. A child wears the
    character a subagent gets under the choice, in its own state; the rest of
    the line has the parent's color. A subagent's own subagents hang one level
    deeper under it. None clears a line that is set and no longer wanted; a
    line that is neither is left out."""
    out, working = {}, False
    for pane in snapshot.get("panes") or []:
        tokens = pane.get("tokens") or {}
        rows = [tokens.get(name) for name in CHILDREN] if pane.get("agent") else []
        rows = [depth_of(row) for row in rows if row]
        character = character_for(choice, pane.get("agent") or "")
        child = character_for(choice, "subagent")
        lines = {}
        for n, (deeper, row) in enumerate(rows):
            state, _, name = row.partition(" ")
            deeper_after = [d for d, _ in rows[n + 1:]]
            subagent_after = False in deeper_after      # a subagent row, or `+N more`, is still to come
            # A row is the last of its group when no row of its depth follows
            # before one shallower. A deeper row carries its subagent's trunk
            # down while a subagent row is still to come.
            if deeper:
                branch = (TRUNK if subagent_after else GAP) + (BRANCH if deeper_after[:1] == [True] else LAST)
            else:
                branch = BRANCH if subagent_after else LAST
            shown = "+%s more" % name if state == "more" else face(child, state, frame) + " " + name
            lines[TREE[n]] = (indent(character) + branch + shown)[:VALUE_LIMIT].rstrip()
            working = working or state == "working"
        for name in TREE:
            if name not in lines and name in tokens:
                lines[name] = None
        if lines:
            out[("pane", pane["pane_id"])] = lines
    return out, working


# ---- branches ---------------------------------------------------------------
def git_reader(folder, timeout):
    """git(*args) in a folder: its output, or None when it fails. Never takes a lock."""
    def git(*args):
        done = subprocess.run(["git", "--no-optional-locks", "-C", folder, *args], capture_output=True, text=True,
                              timeout=timeout, stdin=subprocess.DEVNULL)
        return done.stdout.strip() if done.returncode == 0 else None
    return git


def git_line(folder, timeout=3.0):
    """"main ↑1 ↓2" for the repository a folder is in, or None if it is in none.

    Herdr's API does not carry the branch it shows, so this reads it. It only
    reads refs: no working-tree scan, and never index.lock."""
    git = git_reader(folder, timeout)
    branch = git("symbolic-ref", "--short", "-q", "HEAD") or git("rev-parse", "--short", "HEAD")   # a branch, else a detached commit
    if not branch:
        return None
    counts = (git("rev-list", "--left-right", "--count", "HEAD...@{upstream}") or "").split()
    ahead, behind = (int(counts[0]), int(counts[1])) if len(counts) == 2 and all(c.isdigit() for c in counts) else (0, 0)
    return " ".join([branch] + ["↑%d" % ahead] * (ahead > 0) + ["↓%d" % behind] * (behind > 0))


MAIN_BRANCH = "main"         # where worktree work lands (docs/adr/0004)
# How a branch's reflog names a commit made on it ("commit: <subject>",
# "commit (amend): ..."); a rebase, merge, reset or pull makes none of its own.
OWN_COMMITS = ("commit", "cherry-pick", "revert")


def worktree_progress(checkout, timeout=3.0):
    """(commits on a worktree's branch that main does not have, has its work landed on main).

    Its work has landed when the branch is part of main (no commit of it is
    missing from main) and its reflog records a commit made on it. A fresh
    branch is part of main too, even after it catches up with main by a
    rebase or fast-forward, but has no work of its own.

    None outside a repository, or in one with no main branch. Reads refs
    and the branch's reflog only, like git_line."""
    git = git_reader(checkout, timeout)
    ahead = git("rev-list", "--count", MAIN_BRANCH + "..HEAD")
    if ahead is None:
        return None
    if int(ahead):
        return int(ahead), False
    branch = git("symbolic-ref", "-q", "HEAD")
    history = (git("log", "--walk-reflogs", "--format=%gs", branch) or "").splitlines() if branch else []
    return 0, any(entry.startswith(OWN_COMMITS) for entry in history)


def branch_of(line):
    """The branch (or detached commit) a git_line starts with; "" for no line."""
    return (line or "").split(" ")[0]


class GitWatch:
    """Reads each watched folder's branch, and each worktree checkout's progress, every few seconds, off the animation's thread."""

    def __init__(self, read=git_line, seconds=GIT_SECONDS, read_progress=worktree_progress):
        self.read, self.read_progress, self.seconds = read, read_progress, seconds
        self.folders, self.checkouts, self.new = frozenset(), frozenset(), threading.Event()
        self.lines, self.progress_at = {}, {}
        threading.Thread(target=self.keep_looking, daemon=True).start()

    def watch(self, folders, checkouts=()):
        folders, checkouts = frozenset(folders), frozenset(checkouts)
        fresh = (folders - self.folders) or (checkouts - self.checkouts)
        self.folders, self.checkouts = folders, checkouts
        if fresh:
            self.new.set()                  # do not make a new workspace wait for the next round

    def line(self, folder):
        return self.lines.get(folder)

    def progress(self, checkout):
        return self.progress_at.get(checkout)

    def look(self):
        self.lines = self.read_all(self.read, self.folders, self.lines)
        self.progress_at = self.read_all(self.read_progress, self.checkouts, self.progress_at)

    @staticmethod
    def read_all(read, folders, was):
        now = {}
        for folder in folders:
            try:
                now[folder] = read(folder)
            except (OSError, subprocess.SubprocessError, ValueError):
                now[folder] = was.get(folder)      # slow or failing just now: keep what was there
        return now

    def keep_looking(self):
        while True:
            self.new.clear()
            self.look()
            self.new.wait(self.seconds)


# ---- talking to Herdr -------------------------------------------------------
class HerdrError(Exception):
    pass


def call(socket_path, method, params, timeout=2.0):
    """One request over Herdr's socket: a line of JSON out, a line of JSON back."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(socket_path)
        sock.sendall((json.dumps({"id": PLUGIN_ID, "method": method, "params": params}) + "\n").encode())
        body = b""
        while b"\n" not in body:
            chunk = sock.recv(65536)
            if not chunk:
                raise OSError("Herdr closed the connection without answering " + method)
            body += chunk
    response = json.loads(body.split(b"\n", 1)[0])
    if response.get("error"):
        raise HerdrError("%s: %s" % (method, json.dumps(response["error"])))
    return response.get("result") or {}


def report(socket_path, key, tokens):
    """Set some of one pane's or workspace's tokens; a value of None clears that token."""
    kind, target = key
    params = {kind + "_id": target, "source": SOURCE, "tokens": tokens}
    if any(text is not None for text in tokens.values()):
        params["ttl_ms"] = TTL_MS[kind]
    call(socket_path, kind + ".report_metadata", params)


# ---- the choice -------------------------------------------------------------
def write_setting(config_dir, name, text):
    """Replace the file `name` in the config folder in one step."""
    os.makedirs(config_dir, exist_ok=True)
    tmp = os.path.join(config_dir, name + ".tmp")
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, os.path.join(config_dir, name))


def read_choice(config_dir):
    try:
        with open(os.path.join(config_dir, "character")) as f:
            choice = f.read().strip()
    except OSError:
        return DEFAULT_CHOICE
    return choice if choice in CHOICES else DEFAULT_CHOICE


def write_choice(config_dir, choice):
    if choice not in CHOICES:
        raise SystemExit("faces: choose one of: " + ", ".join(CHOICES))
    write_setting(config_dir, "character", choice + "\n")


def read_minutes(config_dir):
    """How long an idle agent stays ready after its last work. 0: it sleeps at once."""
    try:
        with open(os.path.join(config_dir, "awake-minutes")) as f:
            minutes = float(f.read().strip())
    except (OSError, ValueError):
        return AWAKE_MINUTES
    return minutes if 0 <= minutes < float("inf") else AWAKE_MINUTES


def write_minutes(config_dir, text):
    try:
        minutes = float(text)
    except ValueError:
        minutes = -1
    if not 0 <= minutes < float("inf"):
        raise SystemExit("faces: awake takes a number of minutes, 0 or more")
    write_setting(config_dir, "awake-minutes", "%g\n" % minutes)


def config_dir():
    """The plugin's config folder. Herdr passes it to plugin commands; the picker asks Herdr."""
    known = os.environ.get("HERDR_PLUGIN_CONFIG_DIR")
    if known:
        return known
    from herdr_cli import herdr_binary
    found = subprocess.run([herdr_binary(), "plugin", "config-dir", PLUGIN_ID], capture_output=True, text=True)
    if found.returncode != 0 or not found.stdout.strip():
        raise SystemExit("faces: the plugin is not linked (herdr plugin link ~/.config/herdr/faces)")
    return found.stdout.strip()


# ---- run --------------------------------------------------------------------
def session_key(socket_path):
    """A short name for the Herdr session a socket belongs to."""
    return hashlib.sha1(socket_path.encode()).hexdigest()[:12]


def log(state_dir, message):
    path = os.path.join(state_dir, "faces.log")
    try:
        if os.path.exists(path) and os.path.getsize(path) > 100_000:
            os.replace(path, path + ".1")
        with open(path, "a") as f:
            f.write("%s pid %d: %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), os.getpid(), message))
    except OSError:
        pass


def run(socket_path, config, state_dir, sleep=time.sleep, clock=time.monotonic, git=None, now=time.time):
    os.makedirs(state_dir, exist_ok=True)
    # One updater per server: sessions have their own sockets and share this folder.
    with open(os.path.join(state_dir, "run-%s.lock" % session_key(socket_path)), "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return 0                            # another copy is already at work
        return keep_current(socket_path, config, state_dir, sleep, clock, git or GitWatch(), now)


def keep_current(socket_path, config, state_dir, sleep, clock, git, now=time.time):
    log(state_dir, "started for " + socket_path)
    sent, frame, failures, last_socket_id = {}, 0, 0, None
    # Sessions can reuse workspace and pane ids: keep separate files per socket.
    session = session_key(socket_path)
    colors = TitleColors(os.path.join(config, "workspace-colors-%s.json" % session))
    awake = Awake(os.path.join(state_dir, "awake-%s.json" % session), now)
    renewed = {kind: clock() for kind in REFRESH_SECONDS}
    while True:
        started = clock()
        try:
            # A restarted server makes a new socket file and holds none of the tokens sent to the old one.
            socket_file = os.stat(socket_path)
            socket_id = (socket_file.st_ino, socket_file.st_ctime_ns)
            if socket_id != last_socket_id:
                last_socket_id, sent = socket_id, {}
            snapshot = call(socket_path, "session.snapshot", {})["snapshot"]
            failures = 0
        except (OSError, ValueError, KeyError, HerdrError) as error:
            failures += 1
            if failures >= GIVE_UP_AFTER:
                log(state_dir, "stopping, Herdr is not answering: %s" % error)
                return 0
            sleep(IDLE_SECONDS)
            continue
        choice = read_choice(config)
        up = awake.update(snapshot, read_minutes(config) * 60)
        faces, working = wanted(snapshot, choice, frame, up, git.line)
        workspaces = snapshot.get("workspaces") or []
        git.watch(filter(None, (folder_of(w, snapshot) for w in workspaces)), filter(None, map(linked_checkout, workspaces)))
        want = {key: {TOKEN: text} for key, text in faces.items()}
        branches, children_working = trees(snapshot, choice, frame)
        working = working or children_working
        for key, lines in list(described(snapshot, choice, git.line, up, git.progress).items()) + list(branches.items()):
            want.setdefault(key, {}).update(lines)
        want = identity.apply(snapshot, want, colors.assign(workspaces))
        due = {kind for kind, since in renewed.items() if clock() - since >= REFRESH_SECONDS[kind]}   # renew before the deadline
        for kind in due:
            renewed[kind] = clock()
        for key, tokens in want.items():
            have = sent.get(key, {})
            changed = {token: text for token, text in tokens.items()
                       if token not in have or have[token] != text or (key[0] in due and text is not None)}
            if not changed:
                continue
            try:
                report(socket_path, key, changed)
                sent[key] = dict(have, **changed)
            except (OSError, ValueError, HerdrError) as error:   # e.g. the pane closed a moment ago
                sent.pop(key, None)
                log(state_dir, "could not set %s %s: %s" % (key[0], key[1], error))
        for key in [k for k in sent if k not in want]:
            del sent[key]
        if working:
            frame += 1
        sleep(max(0.05, (FRAME_SECONDS if working else IDLE_SECONDS) - (clock() - started)))


# ---- choosing ---------------------------------------------------------------
def legend():
    """What the faces in each row of the table are, in their order."""
    return "faces: " + ", ".join(FACE_LABELS[which] for which in FACES)


def table():
    """One line per choice: every face, as it will look in the sidebar."""
    lines = []
    for choice in CHOICES:
        if choice == "mixed":
            shown = "  ".join(face(c, "working") for c in ("byte", "wisp"))
            lines.append((choice, "Mixed", shown, "Byte for Pi, Wisp for every other agent"))
            continue
        c = CHARACTERS[choice]
        lines.append((choice, c["title"], "  ".join(face(choice, s) for s in FACES), c["about"]))
    return lines


def pick(config):
    current = read_choice(config)
    rows = ["%s\t%s %-6s %s   %s" % (key, "●" if key == current else " ", title, faces, about) for key, title, faces, about in table()]
    if shutil.which("fzf"):
        picked = subprocess.run(
            ["fzf", "--delimiter=\t", "--with-nth=2..", "--reverse", "--no-info", "--no-sort", "--prompt=sidebar character > ",
             "--header=%s   (● is the current one)" % legend()],
            input="\n".join(rows), stdout=subprocess.PIPE, text=True)   # fzf draws on the terminal itself
        if picked.returncode != 0 or not picked.stdout.strip():
            return 0                             # Esc: leave it as it is
        choice = picked.stdout.split("\t", 1)[0]
    else:
        for number, row in enumerate(rows, 1):
            print("%d) %s" % (number, row.split("\t", 1)[1]))
        answer = input("number > ").strip()
        if not answer.isdigit() or not 1 <= int(answer) <= len(rows):
            return 0
        choice = CHOICES[int(answer) - 1]
    write_choice(config, choice)
    return 0


def main(argv):
    command = argv[1] if len(argv) > 1 else "run"
    if command == "run":
        socket_path = os.environ.get("HERDR_SOCKET_PATH")
        state_dir = os.environ.get("HERDR_PLUGIN_STATE_DIR")
        if not socket_path or not state_dir:
            raise SystemExit("faces: run is started by Herdr (it needs HERDR_SOCKET_PATH and HERDR_PLUGIN_STATE_DIR)")
        return run(socket_path, config_dir(), state_dir)
    if command == "pick":
        return pick(config_dir())
    if command == "set" and len(argv) == 3:
        write_choice(config_dir(), argv[2])
        return 0
    if command == "awake" and len(argv) == 3:
        write_minutes(config_dir(), argv[2])
        return 0
    if command == "show":
        current = read_choice(config_dir())
        for key, title, faces, about in table():
            print("%s %-6s %s   %s" % ("●" if key == current else " ", title, faces, about))
        print("ready for %g minutes after an agent's last work, then asleep" % read_minutes(config_dir()))
        return 0
    if command == "rules":
        # The same workspace color on every line; Spaces has the first two.
        print("\n\n".join(identity.rules(token) for token in ("$face", "$detail", "$note", "$alert") + tuple("$" + t for t in TREE)))
        return 0
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
