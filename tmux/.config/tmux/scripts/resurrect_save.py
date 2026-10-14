#!/usr/bin/env python3
"""Run tmux-resurrect saves and restores one at a time per backup directory,
each save into a file of its own, and point `last` only at complete saves.

resurrect names a save after the local second it runs in, so two saves in the
same second (or in a second that repeats, when the clocks go back) share one
file. Overlapping, they interleave it and a restore duplicates panes; one
after the other, the second finds the file equal to `last` and deletes it,
leaving `last` dangling. Here each save gets a name no existing save has
(tmux-shim/date). A restore reads `last` several times over, so a save during
one changes what it restores.

Every save and restore goes through here (tmux.conf):
  resurrect_save.py [quiet]   save now (prefix C-s)
  resurrect_save.py restore   restore `last` (prefix C-r)
  resurrect_save.py auto      autosave when due (a status-right job)
  resurrect_save.py install   add that job where continuum added its own

Nothing runs resurrect's save.sh or restore.sh directly. resurrect binds no
keys (@resurrect-save and @resurrect-restore are empty) and continuum's own
autosave is off (@continuum-save-interval 0): both would otherwise go back to
the raw scripts for the duration of every config reload, because resurrect
resets its keys and script paths whenever it loads. (continuum's auto-restore,
@continuum-restore, would bypass this too; it is off.)

The lock lives in the backup directory, so tmux servers sharing it are
serialized too. Each save writes into the directory it locked, and only from
the server it was asked of, not a replacement started on the same socket
since. An autosave that finds the lock held skips its turn: a save or a
restore is under way.

A wrapper that dies mid-save or mid-restore doesn't release the lock early:
the lock file records resurrect's process, and the next save or restore waits
for it.

save.sh itself never links `last` (see tmux-shim/ln): it links even a save it
failed to write in full (a full disk, a file-size limit). (If it ever does, its
call changed: the save fails, with a message, and `last` is put back.) The
wrapper links a save once it is complete and from the same server throughout,
and only then prunes old saves (resurrect's own pruning, which runs first, could delete
`last`'s target and is off). Every tmux command save.sh and restore.sh run goes
to the server asked, or nowhere (tmux-shim/tmux).
"""
import contextlib
import fcntl
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
SCRIPTS = os.path.join(HERE, os.pardir, "plugins", "tmux-resurrect", "scripts")
SAVE = os.path.join(SCRIPTS, "save.sh")
RESTORE = os.path.join(SCRIPTS, "restore.sh")
SHIM = os.path.join(HERE, "tmux-shim")
AUTO = f"#({os.path.join(HERE, 'resurrect_save.py')} auto)"
CONTINUUM_JOB = "/tmux-continuum/scripts/continuum_save.sh)"
INTERVAL = "@resurrect-autosave-interval"  # minutes; 0 disables
LAST = "@continuum-save-last-timestamp"  # continuum's: it delays the first save
FIELDS = {"grouped_session": 5, "pane": 11, "window": 8, "state": 3}  # save.sh's line formats


def tmux_run(*args):
    return subprocess.run(["tmux", *args], capture_output=True, text=True)


def tmux(*args):
    return tmux_run(*args).stdout.rstrip("\n")


class Unreachable(Exception):
    pass


def server_id():
    """The server's pid and start time, which a replacement on the same
    socket doesn't share; None if there's no server."""
    result = tmux_run("display-message", "-p", "#{pid}:#{start_time}")
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def backup_dir(server):
    """resurrect's own resolution of @resurrect-dir (default, ~ and $HOME).
    Only with `server` reachable: without one, resurrect falls back to its
    default directory and saves an empty environment there."""
    if server_id() != server:
        raise Unreachable
    out = subprocess.run(["bash", "-c", 'source "$1/helpers.sh" && resurrect_dir', "-", SCRIPTS],
                         capture_output=True, text=True, check=True).stdout.strip()
    if server_id() != server:  # it may have read another server's, or the default
        raise Unreachable
    os.makedirs(out, exist_ok=True)
    return out


def locked(directory, name):
    fd = os.open(os.path.join(directory, name), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    return os.fdopen(fd, "r+")


def serialized(server, run, wait=True):
    """run(directory, lock fd) under the backup directory's lock, once a save
    or restore whose wrapper died has finished (settle). Without `wait`,
    skip (0) if the lock is held."""
    while True:
        directory = backup_dir(server)
        with locked(directory, ".save-lock") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | (0 if wait else fcntl.LOCK_NB))
            except BlockingIOError:
                return 0
            settle(lock.fileno())
            # After every wait: the server may have gone away or been replaced
            # (raises), or @resurrect-dir changed, in which case this belongs
            # under the new directory's lock.
            if backup_dir(server) == directory:
                try:
                    return run(directory, lock.fileno())
                finally:
                    write_record(lock.fileno(), pid=None)


def guard(server):
    """Mark `server` with the option tmux-shim/tmux requires of every command;
    return its name and the server's @resurrect-delete-backup-after. The
    server sets the option only if it is `server` (checked within the same
    command, so it never reaches a replacement), and keeps it: another save
    or restore on it (into another directory) may be using it."""
    identity = server.replace(":", "-")
    name = "@resurrect-save-server-" + identity
    tmux("if-shell", "-F", f"#{{==:#{{pid}}-#{{start_time}},{identity}}}", f"set-option -g {name} 1")
    result = tmux_run("show-option", "-gv", name, ";", "show-option", "-gqv", "@resurrect-delete-backup-after")
    if result.returncode != 0:
        raise Unreachable
    return name, (result.stdout.splitlines() + ["", ""])[1]


def running(pid):
    """Whether `pid` is still a resurrect save or restore (not a reused pid)."""
    if not pid:
        return False
    command = subprocess.run(["ps", "-o", "command=", "-p", str(pid)], capture_output=True, text=True).stdout
    return any(f"tmux-resurrect/scripts/{script}" in command for script in ("save.sh", "restore.sh"))


# The lock file holds one fixed-size record, replaced by a single positioned
# write and never truncated: a process killed at any point leaves the old
# record or the new one, never none (and the lock's inode never changes).
RECORD = 256


def write_record(fd, **fields):  # unbuffered: also runs in the forked child
    os.pwrite(fd, json.dumps(fields).encode().ljust(RECORD), 0)


def read_record(fd):
    """The record, or None if missing or unreadable: then assume the worst
    (a lock file recreated just after a save is as empty as a new one)."""
    raw = os.pread(fd, RECORD * 2, 0)
    try:
        record = json.loads(raw)
        return record if isinstance(record, dict) else None
    except ValueError:
        return None


def shimmed(directory, guard, **extra):
    """save.sh/restore.sh's environment: tmux-shim first on PATH. Its tmux
    sends every command to the server `guard` marks or nowhere, pins @resurrect-dir to
    `directory` (the one locked, whatever the option says by then), turns off
    resurrect's pruning, and stops the process group if the server goes away
    or is replaced, before resurrect saves an empty environment or restores
    into another server. Its ln leaves `last` to us; its date names the save."""
    return {**os.environ, "PATH": SHIM + os.pathsep + os.environ.get("PATH", ""),
            "RESURRECT_SAVE_TMUX": shutil.which("tmux") or "tmux", "RESURRECT_SAVE_DIR": directory,
            "RESURRECT_SAVE_GUARD": guard, **extra}


def stamp(directory):
    """resurrect's local-time stamp for a new save: the current second's, or
    the first later one no save in `directory` is named for."""
    second = int(time.time())
    while True:
        name = time.strftime("%Y%m%dT%H%M%S", time.localtime(second))
        if not os.path.lexists(os.path.join(directory, f"tmux_resurrect_{name}.txt")):
            return name
        second += 1


def prune(directory, days):
    """resurrect's pruning (save.sh's remove_old_backups), but never of
    `last`'s target: delete saves older than `days` (the requested server's
    @resurrect-delete-backup-after), keeping at least the 5 newest. Like
    resurrect's (find -type f), it leaves symlinks, and what they point at."""
    try:
        days = int(days or 30)
    except ValueError:
        return
    target = os.path.realpath(os.path.join(directory, "last"))
    saves = [os.path.join(directory, name) for name in os.listdir(directory)
             if name.startswith("tmux_resurrect_") and name.endswith(".txt")]
    saves = sorted((path for path in saves if os.path.isfile(path) and not os.path.islink(path)),
                   key=os.path.getmtime, reverse=True)
    for path in saves[5:]:
        if os.path.realpath(path) != target and time.time() - os.path.getmtime(path) >= (days + 1) * 86400:
            os.unlink(path)  # find -mtime +days


def complete(path):
    """Whether save.sh wrote a save in full. It carries on past a failed
    write, and its last write is the state line: a save cut short lacks it,
    or ends mid-line."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return False
    lines = data.decode(errors="replace").split("\n")
    if lines.pop() != "":
        return False
    kinds = [line.split("\t", 1)[0] for line in lines]
    return (kinds[-1:] == ["state"] and kinds.count("state") == 1 and "pane" in kinds and "window" in kinds
            and all(kind in FIELDS and line.count("\t") + 1 >= FIELDS[kind] for kind, line in zip(kinds, lines)))


def link_last(directory, name):
    temporary = os.path.join(directory, f".last-{os.getpid()}")
    with contextlib.suppress(FileNotFoundError):
        os.unlink(temporary)
    os.symlink(name, temporary)
    os.replace(temporary, os.path.join(directory, "last"))  # atomic: never a missing `last`


def target(directory):
    """What `last` points at, or None."""
    try:
        return os.readlink(os.path.join(directory, "last"))
    except OSError:
        return None


def warn(message):
    """To stderr, which an autosave discards, and to the attached client."""
    print(message, file=sys.stderr)
    tmux_run("display-message", message)


def save(args, server, wait=True):
    return serialized(server, lambda directory, fd: save_locked(args, server, directory, fd), wait)


def recording(fd):
    """A preexec_fn recording the child in the lock file before exec, while it
    still shares the lock (the fd closes on exec): a wrapper killed at any
    point leaves either no save or restore, or a recorded one."""
    return lambda: write_record(fd, pid=os.getpid())


def settle(fd):
    """Wait for a save or restore whose wrapper died: the lock file still
    names its process. (A record lost to a deleted or tampered lock file
    names none; then the save's own file, named for no existing save, still
    keeps it apart.)"""
    pid = (read_record(fd) or {}).get("pid")
    while running(pid):
        time.sleep(0.05)


def save_locked(args, server, directory, fd):
    marker, days = guard(server)

    before = set(os.listdir(directory))
    previous = target(directory)
    links, link_fd = os.pipe()  # tmux-shim/ln writes there the save to link
    env = shimmed(directory, marker, RESURRECT_SAVE_LINK_FD=str(link_fd), RESURRECT_SAVE_STAMP=stamp(directory))
    child = subprocess.Popen(["bash", SAVE, *args], env=env, start_new_session=True,
                             preexec_fn=recording(fd), pass_fds=(link_fd,))
    os.close(link_fd)
    status = child.wait()
    os.set_blocking(links, False)  # a hook's background process may hold it open
    try:
        requested = os.read(links, 65536).decode().split()
    except BlockingIOError:
        requested = []
    os.close(links)

    new = {name for name in set(os.listdir(directory)) - before if name.startswith("tmux_resurrect_")}
    linked = None
    if status == 0 and requested:
        name = requested[-1]
        if name in new and complete(os.path.join(directory, name)) and server_id() == server:
            link_last(directory, name)
            linked = name
        else:
            status = 1
    elif not requested and target(directory) != previous:
        # save.sh linked `last` itself: its call no longer matches tmux-shim/ln
        # (after a tmux-resurrect update, say), and would from now on link
        # every save unchecked. Undo that, and fail loudly every time.
        if previous is None:
            os.unlink(os.path.join(directory, "last"))
        else:
            link_last(directory, previous)
        warn("resurrect_save.py: save.sh links `last` itself; tmux-shim/ln needs updating. Save discarded.")
        status = 1
    for name in new - {linked}:  # partial, or from a server replaced mid-save
        os.unlink(os.path.join(directory, name))
    if not status:  # not after a rejected save (from a server replaced mid-save, say)
        prune(directory, days)
    return 1 if status else 0


def restore(server):
    """restore.sh under the save lock, so no save changes `last` while it
    reads it. Like a save, the restore is recorded in the lock file: if its
    wrapper dies, the next save or restore still waits for it."""
    def run(directory, fd):
        status = subprocess.run(["bash", RESTORE], env=shimmed(directory, guard(server)[0]), start_new_session=True,
                                preexec_fn=recording(fd)).returncode
        return 1 if status else 0
    return serialized(server, run)


def due():
    """Whether the autosave interval has passed (False without a server)."""
    minutes, last = (tmux("display-message", "-p", f"#{{{INTERVAL}}} #{{{LAST}}}").split() + ["", ""])[:2]
    try:
        return int(minutes) > 0 and (not last or time.time() >= int(last) + int(minutes) * 60)
    except ValueError:
        return False


def auto(server):
    """Start a background save when the interval has passed (main checks it
    first). Prints nothing: this is a status-right job."""
    with locked(backup_dir(server), ".autosave-lock") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0  # another client's job is deciding
        if not due():  # another job just saved
            return 0
        first = not tmux("show-option", "-gqv", LAST)
        tmux("set-option", "-g", LAST, str(int(time.time())))
        if first:
            return 0  # first load: leave time to restore before saving
    subprocess.Popen([sys.executable, os.path.realpath(__file__), "autosave", server], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return 0


def install():
    """Autosave only where continuum would: it adds its job to status-right
    only on the sole tmux server, so saves from other environments don't
    overwrite this one's."""
    status = tmux("show-option", "-gqv", "status-right")
    if CONTINUUM_JOB in status and AUTO not in status:
        tmux("set-option", "-g", "status-right", AUTO + status)
    return 0


def main(argv):
    if argv == ["install"]:
        return install()
    background = argv[:1] in (["auto"], ["autosave"])
    try:
        if argv[:1] == ["autosave"]:  # from auto(): that server's, unless a save is under way
            return save(["quiet"], argv[1], wait=False)
        if argv == ["auto"] and not due():  # the common case: one tmux call
            return 0
        server = server_id()
        if server is None:
            raise Unreachable
        if argv == ["auto"]:
            return auto(server)
        if argv == ["restore"]:
            return restore(server)
        return save(argv, server)
    except Unreachable:
        return 0 if background else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
