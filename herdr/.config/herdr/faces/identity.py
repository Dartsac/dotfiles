"""Give a space and its agents one color: every line of text they show.

Only the character keeps its state color, which its font paints (Bit, made of
ordinary text, takes the workspace color too).

Herdr styles a whole metadata token. A prefix of invisible word joiners lets
its rules choose the workspace hue without a visible label, extra cell or
separator. Herdr's text renderer skips these zero-width standalone graphemes.
They are not sent to the terminal or attached to the sprite: a variation
selector there made CoreText replace the sprite's last tile with a tofu box.
"""
import json
from pathlib import Path

# Fifteen text colors, Dracula PRO colors or mixes of two, in the order they
# are handed out. A new workspace takes the first one nobody is using, so the
# order is the design (owner, 2026-11-12):
#   0-5    one per hue family. With six spaces open no two share a family.
#   6-9    lighter versions of four of them, the one nearest two others last
#   10-14  colors that resemble an earlier one (teal and sea green look like
#          green to the owner) and darker versions, which are dim: about Lc 51
#          where the others are 62 or more. The owner chose to have them.
#   then the first again.
# None is a state color of a character (characters.COLORS), nor near one,
# except that unknown's violet is allowed here because it is rarely seen.
# The first six slots hold what the first six open workspaces had before, in
# the same families, so those did not change family when this replaced the
# sixteen colors used until then.
TITLE_COLORS = (
    "blue+bright_white:33",           # violet
    "blue+cyan:50",                   # blue
    "orange",
    "dim_green",                      # green
    "magenta+foreground:15",          # pink
    "foreground",                     # cream
    "bright_magenta+bright_white:33", # light pink
    "bright_cyan+blue:25",            # light blue
    "bright_white+bright_blue:33",    # light violet
    "foreground+orange:50",           # light orange
    "cyan+bgdark:25",                 # teal
    "dim_blue+cyan:40",               # dark blue
    "dim_cyan+green:40",              # sea green
    "bright_blue+blue:33",            # dark violet
    "green+dim_black:33",             # dark green
)
JOINER = "\u2060"
BOLD = ("$face", "$alert")


def marker(slot):
    if not isinstance(slot, int) or not 0 <= slot < len(TITLE_COLORS):
        raise ValueError("unknown title color slot")
    return JOINER * (slot + 1)


def tag(text, slot):
    """Prefix the invisible identity marker. Keep it inside Herdr's 80-character limit."""
    prefix = marker(slot)
    return prefix + text[:80 - len(prefix)]


def color_rules():
    # First matching rule wins, so the longest prefix must be tried first.
    return [(marker(slot), TITLE_COLORS[slot]) for slot in reversed(range(len(TITLE_COLORS)))]


def rules(token="$face", indent="  "):
    # The name, and a note that asks for something, are bold; other lines are
    # the same hue at normal weight.
    base, bold = ("foreground", "true") if token in BOLD else ("comment+foreground:55", "false")
    lines = ['%s[{ token = "%s", fg = "{{%s}}", bold = %s, dim = false, rules = [' % (indent, token, base, bold)]
    for prefix, color in color_rules():
        escaped = "\\u2060" * len(prefix)
        lines.append('%s  { starts_with = "%s", fg = "{{%s}}" },' % (indent, escaped, color))
    return "\n".join(lines)


class TitleColors:
    """Stable assignments for a Herdr session, saved by workspace id.

    A new workspace takes the first color in TITLE_COLORS that no open one
    has, so the later, look-alike colors appear only when the earlier ones are
    all in use. With every color in use, the least-used repeats, first first.
    Keep saved assignments unless they collide while an unused color exists.
    Previously open workspaces take priority over newly restored ones; at
    startup, the first visible owner keeps a colliding color.
    Closed workspaces do not reserve colors from new ones. An open workspace
    never changes color because an earlier one became free.
    """
    def __init__(self, path):
        self.path = Path(path)
        try:
            data = json.loads(self.path.read_text())
        except (OSError, ValueError):
            data = {}
        self.saved = {key: slot for key, slot in data.items()
                      if isinstance(key, str) and type(slot) is int and 0 <= slot < len(TITLE_COLORS)} if isinstance(data, dict) else {}
        self.active = set()

    def assign(self, workspaces):
        ids = [w["workspace_id"] for w in workspaces]
        current = {key: self.saved[key] for key in ids if key in self.saved}
        free = [slot for slot in range(len(TITLE_COLORS)) if slot not in current.values()]
        owners = set()
        # Reserve all existing distinct hues first. Only duplicates move, and
        # only when a free slot exists. Existing visible owners beat restores.
        for key in sorted(current, key=lambda key: key not in self.active):
            slot = current[key]
            if slot in owners and free:
                current[key] = free.pop(0)
            owners.add(current[key])
        for key in ids:
            if key not in current:
                counts = [list(current.values()).count(slot) for slot in range(len(TITLE_COLORS))]
                current[key] = min(range(len(TITLE_COLORS)), key=lambda slot: counts[slot])
        self.active = set(ids)
        if any(self.saved.get(key) != slot for key, slot in current.items()):
            self.saved.update(current)
            self.path.parent.mkdir(parents=True, exist_ok=True)
            temporary = self.path.with_suffix(".tmp")
            temporary.write_text(json.dumps(self.saved, sort_keys=True) + "\n")
            temporary.replace(self.path)
        return current


def apply(snapshot, values, slots):
    """Mark every line of a workspace and of its agents with the workspace's color.

    values is {(kind, id): {token: text or None}}. None (a token being
    cleared) and panes whose workspace has no color are left as they are.
    """
    workspace_for = {a["pane_id"]: a.get("workspace_id") for a in snapshot.get("agents") or []}
    out = {}
    for (kind, target), tokens in values.items():
        slot = slots.get(target if kind == "workspace" else workspace_for.get(target))
        out[(kind, target)] = {token: text if slot is None or text is None else tag(text, slot) for token, text in tokens.items()}
    return out
