#!/usr/bin/env python3
"""Herdr from your phone: an SSH server for this Mac that only the tailnet reaches.

    python3 ~/.config/herdr/phone/phone.py setup        install or refresh everything, then check it
    python3 ~/.config/herdr/phone/phone.py status       check every part; say how to connect
    python3 ~/.config/herdr/phone/phone.py add-key [KEY]
                                                        let a phone in by its public key
                                                        (without KEY: the one on the clipboard)
    python3 ~/.config/herdr/phone/phone.py keys         the phones let in
    python3 ~/.config/herdr/phone/phone.py remove-key FINGERPRINT|COMMENT
    python3 ~/.config/herdr/phone/phone.py kick         end every phone session now (a lost phone)
    python3 ~/.config/herdr/phone/phone.py push         phone alerts: show the setting
    python3 ~/.config/herdr/phone/phone.py push moshi [TOKEN]    ... through Moshi (TOKEN: else the clipboard's)
    python3 ~/.config/herdr/phone/phone.py push ntfy [URL [ACCESS_TOKEN]]
                                                        ... through ntfy (without URL: a new private topic)
    python3 ~/.config/herdr/phone/phone.py push away MINUTES
    python3 ~/.config/herdr/phone/phone.py push test | off
    python3 ~/.config/herdr/phone/phone.py uninstall    stop and remove the LaunchAgents; keys stay
    python3 ~/.config/herdr/phone/phone.py serve        the server itself (its LaunchAgent runs this)

The server is macOS's own OpenSSH (/usr/sbin/sshd), run as you by a
LaunchAgent, on this Mac's Tailscale addresses and port 2222 only: no other
network reaches it. It takes keys only, from its own list (add-key), and logs
in only you. A second LaunchAgent keeps the Mac awake while it is on power, or
it would sleep an hour after you leave it. The herdr README, "From your
phone", says why and how.
"""
import argparse
import datetime
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import alert  # noqa: E402
from alert import herdr_binary  # noqa: E402

PORT = 2222
LABELS = {"ssh": "dotfiles.herdr-phone.ssh", "awake": "dotfiles.herdr-phone.awake"}
PLUGIN_ID = "dotfiles.phone"
SSHD = "/usr/sbin/sshd"
SSH_KEYGEN = "/usr/bin/ssh-keygen"
SFTP_SERVER = "/usr/libexec/sftp-server"
CAFFEINATE = "/usr/bin/caffeinate"
PYTHON = "/usr/bin/python3"  # macOS's own, as launchd finds it: Homebrew's moves between versions
TAILSCALE = ("/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale",
             "/Applications/Tailscale.app/Contents/MacOS/Tailscale")
# Tailscale gives a node addresses from these ranges only. The server binds no
# other address, whatever `tailscale ip` says.
TAILNET = (ipaddress.ip_network("100.64.0.0/10"), ipaddress.ip_network("fd7a:115c:a1e0::/48"))
# Homebrew's mosh-server, which phone/mosh-server runs.
MOSH_REAL = ("/opt/homebrew/bin/mosh-server", "/usr/local/bin/mosh-server")
# How long a mosh-server waits for a phone that has gone (killed app, new
# connection): then it exits, and the Herdr client it ran goes with it.
MOSH_TIMEOUT = 86400
LOG_LIMIT = 1_000_000
POLL = 5
KEY_TYPES = ("ssh-ed25519", "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521",
             "sk-ssh-ed25519@openssh.com", "sk-ecdsa-sha2-nistp256@openssh.com", "ssh-rsa")
KEY_LINE = re.compile(r"^(?P<type>[a-z0-9@.-]+) (?P<blob>[A-Za-z0-9+/]+={0,3})(?: (?P<comment>.*))?$")


class Paths:
    """Where everything lives. Fixed under HOME, not XDG: launchd's environment
    has no XDG variables, and the server and this command must agree."""

    def __init__(self, home):
        self.home = Path(home)
        self.keys = self.home / ".ssh/herdr-phone"
        self.host_key = self.keys / "host_ed25519_key"
        self.authorized = self.keys / "authorized_keys"
        self.state = self.home / ".local/state/herdr-phone"
        self.config = self.state / "sshd_config"
        self.pid = self.state / "sshd.pid"
        self.log = self.state / "ssh.log"
        self.crash = self.state / "serve-crash.log"
        self.lock = self.state / "serve.lock"
        self.agents = self.home / "Library/LaunchAgents"
        # The live copy, through stow's link: a worktree's copy would vanish with it.
        self.script = self.home / ".config/herdr/phone/phone.py"
        self.plugin = self.home / ".config/herdr/phone"
        # Ahead of Homebrew's on the PATH of a login shell and of a phone app's
        # probe (Moshi puts ~/.local/bin first).
        self.mosh_link = self.home / ".local/bin/mosh-server"
        self.mosh_wrapper = self.plugin / "mosh-server"

    def plist(self, name):
        return self.agents / f"{LABELS[name]}.plist"


def run(args, **kwargs):
    """subprocess.run that never raises for a missing or hung program."""
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 20)
    try:
        return subprocess.run(args, **kwargs)
    except (OSError, subprocess.SubprocessError) as error:
        return subprocess.CompletedProcess(args, 127, "", str(error))


# --- Tailscale -------------------------------------------------------------

def tailscale_binary():
    for candidate in TAILSCALE:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return shutil.which("tailscale")


def in_tailnet(address):
    return any(address in network for network in TAILNET if address.version == network.version)


def interface_addresses(ifconfig_output):
    """Every address an interface holds now, from `ifconfig` output."""
    found = set()
    for line in ifconfig_output.splitlines():
        words = line.split()
        if len(words) >= 2 and words[0] in ("inet", "inet6"):
            try:
                found.add(ipaddress.ip_address(words[1].split("%")[0]))
            except ValueError:
                pass
    return found


class Addresses:
    """This Mac's Tailscale addresses that an interface holds now: the ones the
    server can bind. `ifconfig` is read at every call (a few milliseconds);
    `tailscale ip` only when the tailnet addresses on the interfaces change."""

    def __init__(self, runner=None):
        self.run = runner or run
        self.held = None
        self.wanted = []

    def __call__(self):
        held = {a for a in interface_addresses(self.run(["/sbin/ifconfig"]).stdout) if in_tailnet(a)}
        if held != self.held:
            self.held = held
            self.wanted = []
            binary = tailscale_binary()
            if binary:
                result = self.run([binary, "ip"])
                if result.returncode == 0:
                    for word in result.stdout.split():
                        try:
                            address = ipaddress.ip_address(word)
                        except ValueError:
                            continue
                        if in_tailnet(address):
                            self.wanted.append(address)
        return [a for a in self.wanted if a in held]


def tailscale_status():
    binary = tailscale_binary()
    if not binary:
        return None
    result = run([binary, "status", "--json"])
    try:
        return json.loads(result.stdout) if result.returncode == 0 else None
    except ValueError:
        return None


# --- the server --------------------------------------------------------------

def listen(address, port=PORT):
    return f"[{address}]:{port}" if address.version == 6 else f"{address}:{port}"


def sshd_config(paths, user, addresses, port=PORT):
    """The server's whole config, written fresh at every start and never edited."""
    if not addresses:
        raise ValueError("no address to listen on")  # sshd would take every address
    return "\n".join([
        "# Written by phone.py serve at every start, from sshd_config() in phone.py:",
        "# edit that, not this. Run as you (not root), sshd can only log you in, and",
        "# only with a key: it has no PAM, so no passwords.",
        *(f"ListenAddress {listen(a, port)}" for a in addresses),
        f'HostKey "{paths.host_key}"',
        f'AuthorizedKeysFile "{paths.authorized}"',
        f'PidFile "{paths.pid}"',
        f"AllowUsers {user}",
        "AuthenticationMethods publickey",
        "PubkeyAuthentication yes",
        "PasswordAuthentication no",
        "KbdInteractiveAuthentication no",
        "HostbasedAuthentication no",
        "UsePAM no",
        "PermitRootLogin no",
        "MaxAuthTries 3",
        "LoginGraceTime 30",
        # A phone that is gone (pocket, flight mode) is dropped after two
        # minutes, and the Herdr client it left attached exits.
        "ClientAliveInterval 30",
        "ClientAliveCountMax 4",
        # Forwarding only from the phone to this Mac's own ports (a dev server
        # in the phone's browser); nothing listens for the phone here.
        "AllowTcpForwarding local",
        "PermitOpen localhost:* 127.0.0.1:* [::1]:*",
        "AllowAgentForwarding no",
        "AllowStreamLocalForwarding no",
        "X11Forwarding no",
        "PermitTunnel no",
        "PermitUserRC no",
        "PermitUserEnvironment no",
        "PrintMotd no",
        "PrintLastLog no",
        # The phone's Herdr client runs on this Mac: its sounds would play here.
        f"SetEnv LANG=en_US.UTF-8 HERDR_DISABLE_SOUND=1 MOSH_SERVER_NETWORK_TMOUT={MOSH_TIMEOUT}",
        f'Subsystem sftp "{SFTP_SERVER}"',
        # Each login names the key it used.
        "LogLevel VERBOSE",
        "",
    ])


class Log:
    def __init__(self, path):
        self.path = path
        self.file = None
        self.open()

    def open(self):
        if self.file:
            self.file.close()
        self.file = open(self.path, "a", buffering=1)

    def rotate(self):
        """At a start of sshd, which takes the file with it: one older copy is kept."""
        if self.path.exists() and self.path.stat().st_size > LOG_LIMIT:
            os.replace(self.path, self.path.with_suffix(".log.old"))
            self.open()

    def __call__(self, message):
        self.file.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S} phone.py: {message}\n")


def stop_child(child):
    """The listener only: each phone's session is a process of its own and stays."""
    if child.poll() is None:
        child.terminate()
        try:
            child.wait(5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()


def serve(paths, user, addresses=None, port=PORT, sleep=time.sleep, sshd=SSHD, poll=POLL):
    """Run sshd on this Mac's tailnet addresses while it has them; start it again
    when they change. Returns on SIGTERM (launchd stopping the job)."""
    import fcntl
    paths.state.mkdir(parents=True, exist_ok=True)
    lock = open(paths.lock, "w")
    log = Log(paths.log)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("another phone.py serve is running; this one stops")
        log.file.close()
        lock.close()
        return 0
    addresses = addresses or Addresses()
    child = None

    def stop(signum, frame):
        raise SystemExit(0)

    previous = {number: signal.signal(number, stop) for number in (signal.SIGTERM, signal.SIGINT)}
    waiting = None
    try:
        while True:
            now = addresses()
            if not now:
                if waiting != "tailnet":
                    log("waiting for this Mac's Tailscale addresses (Tailscale off or signed out?)")
                    waiting = "tailnet"
                sleep(poll)
                continue
            paths.config.write_text(sshd_config(paths, user, now, port))
            check = run([sshd, "-t", "-f", str(paths.config)])
            if check.returncode != 0:
                problem = (check.stderr or check.stdout).strip()
                if waiting != problem:
                    log(f"sshd refuses its config: {problem} (phone.py setup makes the host key)")
                    waiting = problem
                sleep(60)
                continue
            waiting = None
            log.rotate()
            child = subprocess.Popen([sshd, "-D", "-e", "-f", str(paths.config)],
                                     stdin=subprocess.DEVNULL, stdout=log.file, stderr=log.file)
            log(f"sshd {child.pid} listening on {', '.join(map(str, now))} port {port}")
            changed = False
            while child.poll() is None:
                sleep(poll)
                if addresses() != now:
                    changed = True
                    log("this Mac's Tailscale addresses changed: starting sshd again")
                    stop_child(child)
            if not changed:
                log(f"sshd exited with status {child.returncode}; starting it again in 10s")
                sleep(10)
            child = None
    finally:
        if child is not None:
            stop_child(child)
            log("stopped")
        for number, handler in previous.items():
            signal.signal(number, handler)
        log.file.close()
        lock.close()


# --- keys --------------------------------------------------------------------

class BadKey(ValueError):
    pass


def fingerprint(line, keygen=SSH_KEYGEN):
    """(bits, SHA256 fingerprint, type) of one public key line, from ssh-keygen."""
    with tempfile.NamedTemporaryFile("w", suffix=".pub", delete=False) as f:
        f.write(line + "\n")
    try:
        result = run([keygen, "-l", "-f", f.name])
    finally:
        os.unlink(f.name)
    words = result.stdout.split()
    if result.returncode != 0 or len(words) < 2:
        raise BadKey("ssh-keygen cannot read that key")
    kind = words[-1].strip("()") if words[-1].startswith("(") else ""
    return int(words[0]), words[1], kind


def parse_key(text, default_comment):
    """One public key line, rebuilt from what was pasted: type, key and comment.
    Options, private keys and short RSA keys are refused."""
    if "PRIVATE KEY" in text:
        raise BadKey("that is a PRIVATE key: it never leaves the phone. Copy the public key "
                     "(one line starting ssh-ed25519 or ecdsa-sha2-), and clear the clipboard")
    lines = [line.strip() for line in text.strip().splitlines() if line.strip()]
    if len(lines) != 1:
        raise BadKey(f"expected one public key line, got {len(lines)}")
    match = KEY_LINE.match(" ".join(lines[0].split()))
    if not match or match["type"] not in KEY_TYPES:
        raise BadKey("not a public key line that starts with " + " or ".join(KEY_TYPES[:2]) + " ...")
    comment = "".join(c for c in (match["comment"] or "") if c.isprintable())[:100].strip() or default_comment
    line = f"{match['type']} {match['blob']} {comment}"
    bits, digest, _ = fingerprint(line)
    if match["type"] == "ssh-rsa" and bits < 3072:
        raise BadKey(f"an RSA key of {bits} bits is too short: make an Ed25519 key on the phone")
    return line, digest


def read_keys(paths):
    try:
        text = paths.authorized.read_text()
    except FileNotFoundError:
        return []
    return [line for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]


def write_keys(paths, lines):
    paths.keys.mkdir(parents=True, exist_ok=True)
    os.chmod(paths.keys, 0o700)
    tmp = paths.authorized.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write("".join(line + "\n" for line in lines))
    os.chmod(tmp, 0o600)
    os.replace(tmp, paths.authorized)


def same_key(a, b):
    return a.split()[:2] == b.split()[:2]


def add_key(paths, text, today=None):
    today = today or datetime.date.today()
    line, digest = parse_key(text, f"phone added {today:%Y-%m-%d}")
    keys = read_keys(paths)
    if any(same_key(line, existing) for existing in keys):
        return False, digest
    write_keys(paths, keys + [line])
    return True, digest


def describe_keys(paths):
    """[(fingerprint, comment, line)] of the keys let in."""
    found = []
    for line in read_keys(paths):
        try:
            _, digest, _ = fingerprint(line)
        except BadKey:
            digest = "(unreadable)"
        words = line.split(None, 2)
        found.append((digest, words[2] if len(words) > 2 else "", line))
    return found


def remove_key(paths, name):
    keys = describe_keys(paths)
    matches = [k for k in keys if name in (k[0], k[0].replace("SHA256:", ""))] or \
              [k for k in keys if k[1] == name]
    if not matches:
        raise BadKey(f"no key with the fingerprint or comment {name!r} (see `phone.py keys`)")
    if len(matches) > 1:
        raise BadKey(f"{len(matches)} keys have the comment {name!r}: name one by its fingerprint")
    write_keys(paths, [k[2] for k in keys if k is not matches[0]])
    return matches[0]


def phone_sessions(ps_output, me, listener=None):
    """[(pid, command)] of the phone's sessions: your sshd-session processes (the
    server's listener aside) and your mosh-servers, from `ps -axo pid=,user=,command=`.
    With Remote Login off, as setup leaves it, the server here is the only sshd that
    runs as you."""
    found = []
    for line in ps_output.splitlines():
        words = line.split(None, 2)
        if len(words) < 3 or words[1] != me or not words[0].isdigit():
            continue
        pid, command = int(words[0]), words[2]
        if pid == listener:
            continue
        if command.startswith(("sshd-session:", "sshd-auth:")) or command.split()[0].endswith("/mosh-server") \
                or command.split()[0] == "mosh-server":
            found.append((pid, command))
    return found


def kick(paths):
    me = pwd.getpwuid(os.getuid()).pw_name
    try:
        listener = int(paths.pid.read_text().split()[0])
    except (OSError, ValueError, IndexError):
        listener = None
    sessions = phone_sessions(run(["/bin/ps", "-axo", "pid=,user=,command="]).stdout, me, listener)
    for pid, command in sessions:
        try:
            os.kill(pid, signal.SIGTERM)
            print(f"ended {pid}: {command}")
        except ProcessLookupError:
            pass
    if not sessions:
        print("no phone session is open")


def clipboard():
    result = run(["/usr/bin/pbpaste"])
    if result.returncode != 0:
        raise SystemExit("phone.py: cannot read the clipboard (pbpaste)")
    return result.stdout


# --- setup and LaunchAgents ----------------------------------------------------

def agent_plist(paths, name):
    if name == "ssh":
        program = [PYTHON, "-B", str(paths.script), "serve"]
        # Exit 0 is a stop (launchd's SIGTERM, or a second copy): stay stopped.
        keep_alive = {"SuccessfulExit": False}
    else:
        # PreventSystemSleep, which holds on power only: on battery the Mac
        # sleeps as it always has.
        program = [CAFFEINATE, "-s"]
        keep_alive = True
    return plistlib.dumps({
        "Label": LABELS[name],
        "ProgramArguments": program,
        "RunAtLoad": True,
        "KeepAlive": keep_alive,
        "ThrottleInterval": 10,
        "StandardOutPath": str(paths.crash),
        "StandardErrorPath": str(paths.crash),
    })


def job(name, uid=None):
    """(state, pid) of a LaunchAgent, or (None, None) when it is not loaded."""
    uid = os.getuid() if uid is None else uid
    result = run(["/bin/launchctl", "print", f"gui/{uid}/{LABELS[name]}"])
    if result.returncode != 0:
        return None, None
    state = re.search(r"^\s*state = (\S+)", result.stdout, re.M)
    pid = re.search(r"^\s*pid = (\d+)", result.stdout, re.M)
    return (state.group(1) if state else "unknown"), (int(pid.group(1)) if pid else None)


def load_agent(paths, name):
    """Write the job's plist and (re)load it: launchd starts it at once and at
    every login."""
    uid = os.getuid()
    target = f"gui/{uid}/{LABELS[name]}"
    paths.agents.mkdir(parents=True, exist_ok=True)
    if job(name)[0] is not None:
        run(["/bin/launchctl", "bootout", target])
        for _ in range(50):  # bootout returns before the job has gone
            if job(name)[0] is None:
                break
            time.sleep(0.2)
    paths.plist(name).write_bytes(agent_plist(paths, name))
    run(["/bin/launchctl", "enable", target])
    result = run(["/bin/launchctl", "bootstrap", f"gui/{uid}", str(paths.plist(name))])
    if result.returncode != 0:
        raise SystemExit(f"phone.py: launchctl could not load {LABELS[name]}: {result.stderr.strip()}")


def unload_agent(paths, name):
    if job(name)[0] is not None:
        run(["/bin/launchctl", "bootout", f"gui/{os.getuid()}/{LABELS[name]}"])
    if paths.plist(name).exists():
        paths.plist(name).unlink()


def make_host_key(paths):
    paths.keys.mkdir(parents=True, exist_ok=True)
    os.chmod(paths.keys, 0o700)
    if paths.host_key.exists():
        return False
    name = run(["/usr/sbin/scutil", "--get", "LocalHostName"]).stdout.strip() or "mac"
    result = run([SSH_KEYGEN, "-q", "-t", "ed25519", "-N", "", "-C", f"herdr-phone@{name}",
                  "-f", str(paths.host_key)])
    if result.returncode != 0:
        raise SystemExit(f"phone.py: ssh-keygen failed: {result.stderr.strip()}")
    return True


def mosh_linked(paths):
    return paths.mosh_link.is_symlink() and os.readlink(paths.mosh_link) == str(paths.mosh_wrapper)


def link_mosh(paths):
    """~/.local/bin/mosh-server -> phone/mosh-server, unless something else has that name."""
    if mosh_linked(paths):
        return True
    if paths.mosh_link.exists() or paths.mosh_link.is_symlink():
        return False
    paths.mosh_link.parent.mkdir(parents=True, exist_ok=True)
    os.symlink(paths.mosh_wrapper, paths.mosh_link)
    return True


def mosh_real():
    return next((c for c in MOSH_REAL if os.path.isfile(c) and os.access(c, os.X_OK)), None)


def plugin_linked(herdr):
    result = run([herdr, "plugin", "list"])
    return result.returncode == 0 and re.search(rf"^- {re.escape(PLUGIN_ID)} .*\benabled\b", result.stdout, re.M)


def setup(paths):
    if sys.platform != "darwin":
        raise SystemExit("phone.py: this is for macOS")
    for tool in (SSHD, SSH_KEYGEN, CAFFEINATE, PYTHON):
        if not os.access(tool, os.X_OK):
            raise SystemExit(f"phone.py: {tool} is missing")
    if not paths.script.exists():
        raise SystemExit(f"phone.py: {paths.script} is missing: the LaunchAgent runs that copy, "
                         "the main checkout's (stow herdr, and land this change first)")
    if make_host_key(paths):
        print(f"made the server's host key, {fingerprint(paths.host_key.with_suffix('.pub').read_text().strip())[1]}")
    if not paths.authorized.exists():
        write_keys(paths, [])
    paths.state.mkdir(parents=True, exist_ok=True)
    os.chmod(paths.state, 0o700)
    for name in LABELS:
        load_agent(paths, name)
        print(f"loaded {LABELS[name]}")
    if not link_mosh(paths):
        print(f"left {paths.mosh_link} as it is: it is not phone's (status says what that means)")
    herdr = herdr_binary()
    if not plugin_linked(herdr):
        result = run([herdr, "plugin", "link", str(paths.plugin)])
        print("linked the phone plugin" if result.returncode == 0 else
              f"could not link the phone plugin: {(result.stderr or result.stdout).strip()}")
    # The server needs a moment to bind; status reads what it bound.
    for _ in range(20):
        if listening(paths):
            break
        time.sleep(0.5)
    print()
    return status(paths)


def uninstall(paths):
    for name in LABELS:
        unload_agent(paths, name)
        print(f"removed {LABELS[name]}")
    if mosh_linked(paths):
        paths.mosh_link.unlink()
        print(f"removed {paths.mosh_link}")
    herdr = herdr_binary()
    if plugin_linked(herdr):
        run([herdr, "plugin", "unlink", PLUGIN_ID])
        print("unlinked the phone plugin")
    print(f"Kept: the keys in {paths.keys} (setup uses them again), Tailscale, and mosh "
          "(brew uninstall mosh). A phone still connected stays until it leaves (phone.py kick).")


# --- status --------------------------------------------------------------------

def listening(paths):
    """The addresses the server's sshd listens on, from lsof."""
    try:
        pid = int(paths.pid.read_text().split()[0])
    except (OSError, ValueError, IndexError):
        return []
    result = run(["/usr/sbin/lsof", "-nP", "-a", "-p", str(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"])
    return [line[1:] for line in result.stdout.splitlines() if line.startswith("n")]


class Report:
    def __init__(self):
        self.problems = 0

    def ok(self, text):
        print(f"  ok  {text}")

    def bad(self, text, fix=None):
        self.problems += 1
        print(f"  !!  {text}")
        if fix:
            print(f"      {fix}")


def push_config_dir(herdr):
    result = run([herdr, "plugin", "config-dir", PLUGIN_ID])
    return result.stdout.strip() if result.returncode == 0 and result.stdout.strip() else None


def status(paths):
    report = Report()
    me = pwd.getpwuid(os.getuid()).pw_name
    command = "python3 ~/.config/herdr/phone/phone.py"
    print("Tailscale")
    ts = tailscale_status()
    host = None
    if ts is None:
        report.bad("Tailscale is not installed or not answering",
                   "install it from https://tailscale.com/download/mac (the Standalone app) and sign in")
    elif ts.get("BackendState") != "Running":
        report.bad(f"Tailscale is {ts.get('BackendState', 'not running').lower()}",
                   "connect it from its menu bar icon, or: tailscale up")
    else:
        me_ts = ts.get("Self") or {}
        host = (me_ts.get("DNSName") or "").rstrip(".")
        login = (ts.get("User") or {}).get(str(me_ts.get("UserID")), {}).get("LoginName", "your account")
        report.ok(f"connected as {login}: this Mac is {host} ({', '.join(me_ts.get('TailscaleIPs') or [])})")
        expiry = me_ts.get("KeyExpiry")
        if expiry:
            when = datetime.datetime.strptime(expiry[:19], "%Y-%m-%dT%H:%M:%S").replace(
                tzinfo=datetime.timezone.utc)
            days = (when - datetime.datetime.now(datetime.timezone.utc)).days
            report.bad(f"this Mac's Tailscale key expires on {when:%Y-%m-%d} ({days} days): the phone loses "
                       "it then, until you sign in again at the Mac",
                       "https://login.tailscale.com/admin/machines > this Mac > ... > Disable key expiry")
        else:
            report.ok("this Mac's Tailscale key does not expire")
        phones = [p for p in (ts.get("Peer") or {}).values() if p.get("OS") in ("iOS", "android")]
        if phones:
            for p in phones:
                seen = "online" if p.get("Online") else "offline now"
                report.ok(f"phone in the tailnet: {p.get('HostName')} ({p.get('OS')}, {seen})")
        else:
            report.bad("no phone in the tailnet yet",
                       f"install Tailscale on the phone and sign in as {login}")
        prefs = run([tailscale_binary(), "debug", "prefs"])
        try:
            shields = json.loads(prefs.stdout).get("ShieldsUp")
        except ValueError:
            shields = None
        if shields:
            report.bad("Shields Up is on: it turns the phone away", "tailscale set --shields-up=false")
    start = run(["/usr/bin/defaults", "read", "io.tailscale.ipn.macsys", "TailscaleStartOnLogin"])
    if start.returncode == 0 and start.stdout.strip() != "1":
        report.bad("Tailscale does not start at login",
                   "defaults write io.tailscale.ipn.macsys TailscaleStartOnLogin -bool true "
                   "(or its menu: Settings > Launch at login)")
    service = re.search(r"^\W*\([^)]*\)\s+(\S+)\s+VPN\s+\(io\.tailscale\.ipn\.",
                        run(["/usr/sbin/scutil", "--nc", "list"]).stdout, re.M)
    if service:
        shown = run(["/usr/sbin/scutil", "--nc", "show", service.group(1)]).stdout
        if "OnDemandEnabled : TRUE" in shown:
            report.ok("Tailscale reconnects by itself (after a restart too)")
        else:
            report.bad("Tailscale will not reconnect by itself after a restart",
                       "open the Tailscale app while connected: it turns that on")

    print("\nSSH server (tailnet only)")
    state, pid = job("ssh")
    if state is None:
        report.bad(f"its LaunchAgent {LABELS['ssh']} is not loaded", f"{command} setup")
    elif state != "running":
        report.bad(f"its LaunchAgent is {state}", f"see {paths.log} and {paths.crash}")
    bound = listening(paths)
    if bound:
        wild = [b for b in bound if b.startswith("*") or b.startswith("[::]")]
        if wild:
            report.bad(f"listening on every network: {', '.join(wild)}", f"{command} setup")
        report.ok(f"listening on {', '.join(bound)}")
    elif state == "running":
        report.bad("not listening", f"is Tailscale connected? see {paths.log}")
    if paths.host_key.exists():
        _, host_digest, _ = fingerprint(paths.host_key.with_suffix(".pub").read_text().strip())
        report.ok(f"host key {host_digest}")
    else:
        host_digest = None
        report.bad("no host key", f"{command} setup")
    keys = describe_keys(paths)
    if keys:
        for digest, comment, _ in keys:
            report.ok(f"phone let in: {comment} ({digest})")
    else:
        report.bad("no phone let in yet", f"{command} add-key   (the phone's public key on the clipboard)")
    real = mosh_real()
    if not real:
        report.bad("no mosh-server: SSH works, mosh will not", "brew install mosh")
    elif not (mosh_linked(paths) and paths.mosh_wrapper.exists()):
        report.bad(f"{paths.mosh_link} is not phone/mosh-server: an app that does not ask for the "
                   "tailnet address gets a mosh-server on every network",
                   f"{command} setup (it leaves a {paths.mosh_link} of another program alone)")
    else:
        report.ok(f"mosh-server {real}, bound to the tailnet address by {paths.mosh_link}")

    print("\nThe Mac stays reachable")
    state, _ = job("awake")
    if state == "running":
        report.ok("kept awake while on power (caffeinate -s)")
    else:
        report.bad("nothing keeps it awake: it sleeps an hour after you leave it", f"{command} setup")
    if "Battery Power" in run(["/usr/bin/pmset", "-g", "batt"]).stdout:
        report.bad("on battery now: it sleeps as usual until it is on power again")

    print("\nHerdr")
    herdr = herdr_binary()
    server = run([herdr, "status", "server"])
    if server.returncode == 0 and "status: running" in server.stdout:
        report.ok("the server is running")
    else:
        report.bad("the server is not running: the phone would start one with its SSH session's environment",
                   "start Herdr at the Mac (Ghostty: herdr)")
    if plugin_linked(herdr):
        report.ok(f"phone alerts plugin {PLUGIN_ID} is linked")
    else:
        report.bad(f"the phone alerts plugin {PLUGIN_ID} is not linked", f"{command} setup")
    config_dir = push_config_dir(herdr)
    config = None
    try:
        config = alert.load_config(config_dir) if config_dir else None
    except alert.PushError as error:
        report.bad(str(error), f"{command} push off, then choose again")
    if config:
        minutes = config.get("away_minutes", alert.DEFAULT_AWAY_MINUTES)
        report.ok(f"phone alerts through {config['service']}, when the screen is locked or the Mac "
                  f"has been untouched for {minutes} min")
    elif config_dir:
        report.bad("phone alerts are off", f"{command} push moshi   (Moshi's API token on the clipboard)")

    print("\nConnect from the phone's SSH app (in Moshi: a new connection)")
    shown_host = host or "this Mac's Tailscale name, once Tailscale is connected"
    print(f"  Host  {shown_host}")
    print(f"  Port  {PORT}")
    print(f"  User  {me}")
    print("  Auth  the key you let in (add-key); Connection type: Auto")
    if host_digest:
        print(f"  Host key, as the app shows it after the first connection: {host_digest}")
    print("  Then type a (or herdr) to attach. Ctrl-t is the prefix; Ctrl-t d detaches.")
    print()
    print("Everything is ready." if report.problems == 0 else
          f"{report.problems} thing{'s' if report.problems != 1 else ''} to do: the !! lines above.")
    return 0 if report.problems == 0 else 1


# --- push ---------------------------------------------------------------------

def push(paths, args):
    herdr = herdr_binary()
    config_dir = push_config_dir(herdr)
    if not config_dir:
        raise SystemExit(f"phone.py: the plugin {PLUGIN_ID} is not linked: run phone.py setup first")
    current = alert.load_config(config_dir)
    action = args[0] if args else None
    if action is None:
        if not current:
            print("phone alerts are off")
        else:
            shown = {k: ("<set>" if k == "token" else v) for k, v in current.items()}
            print(json.dumps(shown, indent=2))
        return 0
    if action == "off":
        path = Path(config_dir) / alert.CONFIG_NAME
        if path.exists():
            path.unlink()
        print("phone alerts are off")
        return 0
    if action == "test":
        if not current:
            raise SystemExit("phone.py: phone alerts are off: choose a service first (phone.py push moshi)")
        alert.send_test(current)
        print(f"sent a test push through {current['service']}")
        return 0
    if action == "away":
        if not current or len(args) != 2 or not args[1].isdigit():
            raise SystemExit("phone.py: usage: phone.py push away MINUTES (after choosing a service)")
        current["away_minutes"] = int(args[1])
        alert.save_config(config_dir, current)
        print(f"phone alerts when the screen is locked or the Mac has been untouched for {args[1]} min")
        return 0
    away = (current or {}).get("away_minutes", alert.DEFAULT_AWAY_MINUTES)
    if action == "moshi":
        token = (args[1] if len(args) > 1 else clipboard()).strip()
        if not re.fullmatch(r"\S{8,512}", token):
            raise SystemExit("phone.py: that does not look like Moshi's API token "
                             "(Moshi: Settings > Push Notifications > API token)")
        config = {"service": "moshi", "token": token, "away_minutes": away}
    elif action == "ntfy":
        url = args[1] if len(args) > 1 else f"https://ntfy.sh/herdr-{secrets.token_urlsafe(18)}"
        config = {"service": "ntfy", "url": url, "away_minutes": away}
        if len(args) > 2:
            config["token"] = args[2]
        alert.check_ntfy_url(url)
    else:
        raise SystemExit(f"phone.py: unknown push setting {action!r}: moshi, ntfy, away, test or off")
    alert.send_test(config)  # a service that cannot deliver is not saved
    alert.save_config(config_dir, config)
    print(f"phone alerts on, through {action}: a test push is on its way")
    if action == "ntfy":
        print(f"subscribe to {config['url']} in the ntfy app (anyone with that address can read the pushes)")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["setup", "status", "add-key", "keys", "remove-key", "kick",
                                            "push", "uninstall", "serve"])
    parser.add_argument("args", nargs="*")
    options = parser.parse_args(argv)
    paths = Paths(Path.home())
    command, args = options.command, options.args
    try:
        if command == "serve":
            return serve(paths, pwd.getpwuid(os.getuid()).pw_name)
        if command == "setup":
            return setup(paths)
        if command == "status":
            return status(paths)
        if command == "uninstall":
            uninstall(paths)
            return 0
        if command == "add-key":
            added, digest = add_key(paths, " ".join(args) if args else clipboard())
            print(f"{'let in' if added else 'already let in'}: {digest}")
            if added:
                print("That phone can log in now. Connection details: phone.py status")
            return 0
        if command == "keys":
            keys = describe_keys(paths)
            for digest, comment, _ in keys:
                print(f"{digest}  {comment}")
            if not keys:
                print("no phone let in yet: phone.py add-key")
            return 0
        if command == "remove-key":
            if len(args) != 1:
                raise SystemExit("phone.py: usage: phone.py remove-key FINGERPRINT|COMMENT")
            digest, comment, _ = remove_key(paths, args[0])
            print(f"removed {digest} {comment}: that phone cannot log in again. A session it has open "
                  "stays until it ends: phone.py kick ends every phone session now.")
            return 0
        if command == "kick":
            kick(paths)
            return 0
        if command == "push":
            return push(paths, args)
    except BadKey as error:
        raise SystemExit(f"phone.py: {error}")
    except alert.PushError as error:
        raise SystemExit(f"phone.py: {error}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
