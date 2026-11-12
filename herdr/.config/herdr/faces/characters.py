"""The sidebar characters: what each one shows for each agent state.

Byte and Wisp are drawn glyphs from the Herdr Sprites font (sprites.py), three
cells wide. Bit is made of ordinary characters and Nerd Font icons, six cells
wide, and needs no extra font.
"""
from sprites import text as sprite

# Herdr reports five of these. "ready" is this plugin's own: an agent Herdr
# calls idle that was at work a short while ago (faces.py, Awake).
STATES = ("idle", "ready", "working", "blocked", "done", "unknown")
# State colors. Only the character wears them; all text takes its workspace's
# color (identity.py). Bit has no font of its own, so it is colored as text.
# theme-sync writes these into Herdr Sprites Pixel, outside git.
# Each is a Dracula PRO color as it comes, unmixed (owner's choice, 2026-11-12,
# from a side-by-side preview against classic Dracula's):
#   idle     the palette's light neutral gray, the nearest plain color to the
#            mixed gray it replaces
#   ready    yellow, a lamp left on
#   working  cyan
#   blocked  red, the only warm dark one, so it is seen first
#   done     green
#   unknown  the palette's light violet, the match for classic Dracula's purple
#            (its own "purple" is darker)
COLORS = {
    "idle": "dim_white",
    "ready": "yellow",
    "working": "cyan",
    "blocked": "red",
    "done": "green",
    "unknown": "bright_blue",
}
ZZZ, KEYBOARD, KEYBOARD_PRESSED, WAVE = "\U000f04b2", "\U000f030c", "\U000f097b", "\U000f1821"
# A cell that draws nothing. Herdr trims spaces from token values, so a
# workspace with no agent is padded with these to keep the names lined up.
EMPTY = "\u2800"


def drawn(name):
    return {
        "idle": sprite(name, "idle"),
        "ready": sprite(name, "ready"),
        "working": [sprite(name, "work%d" % i) for i in (1, 2, 3, 4)],
        "blocked": sprite(name, "blocked"),
        "done": sprite(name, "done"),
        "unknown": sprite(name, "unknown"),
        "width": 3,
    }


CHARACTERS = {
    "byte": dict(drawn("byte"), title="Byte", about="a monitor-head robot"),
    "wisp": dict(drawn("wisp"), title="Wisp", about="a ghost in the machine"),
    "bit": {
        "title": "Bit", "about": "plain characters, no extra font",
        "idle": "[˘‿˘]" + ZZZ,
        "ready": "[•‿•]_",
        "working": ["[ò‿ó]" + KEYBOARD, "[ò_ó]" + KEYBOARD_PRESSED, "[ò‿ó]" + KEYBOARD, "[-‿-]" + KEYBOARD_PRESSED],
        "blocked": "[°o°]" + WAVE,
        "done": "[^‿^]♥",
        "unknown": "[·_·]?",
        "width": 6,
    },
}
# What the picker offers. "mixed" is Byte for Pi and Wisp for every other agent.
CHOICES = ("byte", "wisp", "bit", "mixed")
DEFAULT_CHOICE = "bit"


def character_for(choice, agent):
    """The character an agent of this kind gets under a choice."""
    if choice == "mixed":
        return "byte" if agent == "pi" else "wisp"
    return choice if choice in CHARACTERS else DEFAULT_CHOICE


def face(character, status, frame=0):
    """The character's glyphs for a status; `frame` steps the working animation."""
    c = CHARACTERS[character]
    if status == "working":
        return c["working"][frame % len(c["working"])]
    return c[status if status in STATES else "unknown"]


def blank(character):
    return EMPTY * CHARACTERS[character]["width"]


def indent(character):
    """Blank cells that put a later line of an entry under the name on its first.

    Herdr starts the first line one cell in and the others three cells in; the
    name starts after the character and a space."""
    return EMPTY * (CHARACTERS[character]["width"] - 1)
