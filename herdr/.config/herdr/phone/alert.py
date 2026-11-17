#!/usr/bin/env python3
"""Phone alerts: a push to the owner's phone when an agent is done or needs
input, sent only while the owner is away from this Mac: its screen is locked,
or nobody has touched its keyboard, mouse or trackpad for `away_minutes`
(5 unless `phone.py push away` says otherwise).

Herdr runs `alert.py` at every agent status change (herdr-plugin.toml), and
`alert.py --test` from the plugin's action. Nothing is sent until `phone.py
push` has chosen a service: Moshi (the phone's SSH app) or ntfy. The choice
and its token are in push.json, in the plugin's config folder (`herdr plugin
config-dir dotfiles.phone`), which only you can read.

Each finish and each question is pushed once, as the away alert does
(away-alert/away-alert.sh): a finish by its completion number, a question by
the attention id the Pi reporter gives it, else by its state change number. A
push carries the agent, its workspace and its activity: never what is on its
screen.
"""
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from herdr_cli import herdr_binary  # noqa: E402

CONFIG_NAME = "push.json"
DEFAULT_AWAY_MINUTES = 5
MOSHI_URL = "https://api.getmoshi.app/api/webhook"
# Moshi's API is behind Cloudflare, which refuses Python's own User-Agent
# (HTTP 403, error 1010).
USER_AGENT = "dotfiles-herdr-phone/1"
SAFE_ID = re.compile(r"^[A-Za-z0-9_-]+$")
SAFE_IDENTITY = re.compile(r"^[A-Za-z0-9:_-]+$")
NTFY_TOPIC = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


class PushError(Exception):
    pass


def log(message):
    print(f"phone alert: {message}", file=sys.stderr)  # Herdr's plugin log keeps it


# --- the setting -----------------------------------------------------------------

def check_ntfy_url(url):
    parts = urllib.parse.urlsplit(url)
    if parts.scheme not in ("https", "http") or not parts.netloc or not NTFY_TOPIC.match(parts.path.strip("/")):
        raise PushError(f"{url!r} is not an ntfy topic address, like https://ntfy.sh/<topic>")


def load_config(config_dir):
    """The setting phone.py push wrote, or None when phone alerts are off."""
    try:
        with open(os.path.join(config_dir, CONFIG_NAME)) as f:
            config = json.load(f)
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as error:
        raise PushError(f"{CONFIG_NAME} cannot be read: {error}") from None
    if not isinstance(config, dict):
        raise PushError(f"{CONFIG_NAME} holds no setting")
    service = config.get("service")
    if service == "moshi" and not config.get("token"):
        raise PushError(f"{CONFIG_NAME}: Moshi needs its token")
    if service == "ntfy":
        check_ntfy_url(config.get("url", ""))
    elif service != "moshi":
        raise PushError(f"{CONFIG_NAME}: the service is {service!r}, not moshi or ntfy")
    minutes = config.get("away_minutes", DEFAULT_AWAY_MINUTES)
    if not isinstance(minutes, int) or isinstance(minutes, bool) or minutes < 0:
        raise PushError(f"{CONFIG_NAME}: away_minutes must be a whole number of minutes")
    return config


def save_config(config_dir, config):
    """Readable by you alone: it holds the service's token."""
    os.makedirs(config_dir, exist_ok=True)
    path = os.path.join(config_dir, CONFIG_NAME)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(config, f, indent=2)
        f.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


# --- delivery --------------------------------------------------------------------

def request(config, title, message, link=None, urgent=False):
    """(url, headers, JSON body) of the one HTTP request that delivers a push."""
    if config["service"] == "moshi":
        body = {"token": config["token"], "title": title, "message": message}
        if link:
            body["data"] = {"type": "url", "url": link}
        return MOSHI_URL, {}, body
    # ntfy takes JSON at the server's root, naming the topic in the body.
    parts = urllib.parse.urlsplit(config["url"])
    root = urllib.parse.urlunsplit((parts.scheme, parts.netloc, "/", "", ""))
    body = {"topic": parts.path.strip("/"), "title": title, "message": message,
            "priority": 4 if urgent else 3}
    headers = {"Authorization": f"Bearer {config['token']}"} if config.get("token") else {}
    return root, headers, body


def send(config, title, message, link=None, urgent=False, urlopen=None):
    urlopen = urlopen or urllib.request.urlopen
    url, headers, body = request(config, title, message, link, urgent)
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST", headers={
        "Content-Type": "application/json", "User-Agent": USER_AGENT, **headers})
    secret = config.get("token") or "\0"
    try:
        with urlopen(req, timeout=15) as response:
            response.read()
    except urllib.error.HTTPError as error:
        detail = error.read(300).decode("utf-8", "replace").strip().replace(secret, "<token>")
        raise PushError(f"{config['service']} refused the push: HTTP {error.code} {detail}") from None
    except (urllib.error.URLError, OSError) as error:
        reason = getattr(error, "reason", error)
        raise PushError(f"{config['service']} could not be reached: {reason}") from None


def send_test(config, urlopen=None):
    send(config, "Phone alerts are on",
         "Herdr will tell you here when an agent is done or needs input while you are away from the Mac.",
         urlopen=urlopen)


def moshi_link(workspace, tab, pane):
    """Moshi opens its open card for Herdr's default session there (or says it has none)."""
    query = [(k, v) for k, v in (("workspace", workspace), ("tab", tab), ("pane", pane)) if v]
    return "moshi://herdr?" + urllib.parse.urlencode(query) if query else None


# --- are you at the Mac? ------------------------------------------------------------

def idle_seconds(run=subprocess.run):
    """Seconds since the last keyboard, mouse or trackpad input here, or None."""
    try:
        out = run(["/usr/sbin/ioreg", "-c", "IOHIDSystem", "-d", "4", "-r", "-k", "HIDIdleTime"],
                  capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.search(r'"HIDIdleTime" = (\d+)', out)
    return int(match.group(1)) / 1e9 if match else None


def screen_locked(run=subprocess.run):
    """Whether the screen is locked (or at the login window), or None."""
    try:
        out = run(["/usr/sbin/ioreg", "-n", "Root", "-d1", "-a"], capture_output=True, timeout=5).stdout
        locked = plistlib.loads(out).get("IOConsoleLocked")
    except (OSError, subprocess.SubprocessError, ValueError, plistlib.InvalidFileException, AttributeError):
        return None
    return locked if isinstance(locked, bool) else None


def away(config, run=subprocess.run):
    """(whether you are away from the Mac, why). When the Mac cannot say, you
    are: a push too many beats a question nobody sees."""
    locked = screen_locked(run)
    if locked:
        return True, "the screen is locked"
    idle = idle_seconds(run)
    if locked is None or idle is None:
        return True, "the Mac cannot say whether you are there"
    minutes = config.get("away_minutes", DEFAULT_AWAY_MINUTES)
    if idle >= minutes * 60:
        return True, f"the Mac has been untouched for {int(idle // 60)} min"
    return False, f"the Mac was used {int(idle)}s ago"


# --- the event ---------------------------------------------------------------------

def herdr_json(herdr, *args, run=subprocess.run):
    try:
        result = run([herdr, *args], capture_output=True, text=True, timeout=10)
        return json.loads(result.stdout)["result"] if result.returncode == 0 else None
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return None


def main(argv=None, env=None, run=subprocess.run, sleep=time.sleep, urlopen=None):
    argv = sys.argv[1:] if argv is None else argv
    env = os.environ if env is None else env
    config_dir = env.get("HERDR_PLUGIN_CONFIG_DIR", "")
    try:
        config = load_config(config_dir) if config_dir else None
    except PushError as error:
        log(str(error))
        return 1
    if argv == ["--test"]:
        if not config:
            log("phone alerts are off: python3 ~/.config/herdr/phone/phone.py push moshi")
            return 1
        try:
            send_test(config, urlopen=urlopen)
        except PushError as error:
            log(str(error))
            return 1
        log(f"sent a test push through {config['service']}")
        return 0

    try:
        event = json.loads(env.get("HERDR_PLUGIN_EVENT_JSON") or "{}").get("data") or {}
    except (ValueError, AttributeError):
        return 0
    status = event.get("agent_status")
    if status in ("done", "idle"):
        what = "is done"
    elif status == "blocked":
        what = "needs input"
    else:
        return 0
    if not config:
        return 0  # off: say nothing at every status change
    sleep(1)  # Herdr's own alert waits a second too (ui.toast.delay_seconds): never push a passing state
    is_away, why = away(config, run)
    if not is_away:
        log(f"not pushed: you are at the Mac ({why})")
        return 0

    herdr = herdr_binary()
    pane = event.get("pane_id") or ""
    agent = (herdr_json(herdr, "agent", "get", pane, run=run) or {}).get("agent") if pane else None
    if not agent:
        log(f"not pushed: {pane or 'the pane'} has no agent now")
        return 0
    tokens = agent.get("tokens") or {}
    if status == "blocked":
        if agent.get("agent_status") != "blocked":
            log("not pushed: no longer needs input")
            return 0
        identity = f"blocked-{tokens.get('attention-id') or agent.get('state_change_seq')}"
        title = tokens.get("attention-title") or ""
        detail = tokens.get("activity") or ""
    else:
        completion = agent.get("completion_seq")
        if (agent.get("agent_status") not in ("idle", "done") or completion is None
                or completion != agent.get("state_change_seq")):
            log(f"not pushed: {status} is not a finished task")
            return 0
        identity = f"completion-{completion}"
        title = tokens.get("completion-title") or ""
        detail = (tokens.get("activity") or "") if title else ""
    terminal = str(agent.get("terminal_id") or "")
    # Ids become file names only when they are this plain.
    if not SAFE_ID.match(terminal) or not SAFE_IDENTITY.match(identity):
        log("not pushed: an id it cannot use as a file name")
        return 0
    state_dir = env.get("HERDR_PLUGIN_STATE_DIR") or ""
    if not state_dir:
        log("not pushed: Herdr gave no state folder")
        return 1
    os.makedirs(state_dir, exist_ok=True)
    ledger = os.path.join(state_dir, f"pushed-{terminal}")
    claim = f"{ledger}.{identity}.sending"
    try:
        os.mkdir(claim)
    except FileExistsError:
        log("not pushed: another handler is pushing this one")
        return 0
    try:
        try:
            with open(ledger) as f:
                if f.read().strip() == identity:
                    log("not pushed: already pushed")
                    return 0
        except FileNotFoundError:
            pass
        name = event.get("display_agent") or event.get("agent") or agent.get("agent") or "Agent"
        title = title or f"{name} {what}"
        workspace = agent.get("workspace_id") or event.get("workspace_id") or ""
        label = ((herdr_json(herdr, "workspace", "get", workspace, run=run) or {}).get("workspace") or {}).get(
            "label", "") if workspace else ""
        task = tokens.get("topic") or ""
        body = " · ".join(part for part in (label, task, detail) if part) or "Herdr"
        link = moshi_link(workspace, agent.get("tab_id"), agent.get("pane_id") or pane) \
            if config["service"] == "moshi" else None
        try:
            send(config, title, body, link=link, urgent=status == "blocked", urlopen=urlopen)
        except PushError as error:
            log(f"not pushed: {error}")
            return 1  # not recorded: the next status change of this one tries again
        with open(ledger, "w") as f:
            f.write(identity + "\n")
        log(f"pushed ({why}): {title} · {body}")
        return 0
    finally:
        os.rmdir(claim)


if __name__ == "__main__":
    sys.exit(main())
