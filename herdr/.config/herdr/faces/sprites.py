"""Herdr sprites: two characters drawn from scratch on a 24x16 pixel grid.

Each sprite is three terminal cells wide (8 pixels per cell) and one cell tall.
A sprite is a set of lit pixels; the font turns each pixel into a square of
outline, so the glyph takes the text color and the dark parts are the
terminal background showing through.
"""
W, H = 24, 16
# New states go last: a sprite's codepoints follow from its place here.
STATES = ["idle", "work1", "work2", "work3", "work4", "blocked", "done", "unknown", "ready"]


def grid():
    return [[0] * W for _ in range(H)]


def put(g, pts, v=1, dy=0):
    for x, y in pts:
        y += dy
        if 0 <= x < W and 0 <= y < H:
            g[y][x] = v


def box(x0, y0, x1, y1):
    return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]


def art(x0, y0, rows):
    """Pixels from rows of text: '#' is lit."""
    return [(x0 + x, y0 + y) for y, row in enumerate(rows) for x, ch in enumerate(row) if ch == "#"]


# ---- things both characters hold up -----------------------------------------
ZZ = art(17, 2, ["..####", "....#.", "...#..", "..####", "......", "......", "###...", ".#....", "###..."])
BANG = art(20, 1, ["##", "##", "##", "##", "##", "##", "##", "..", "##", "##"])
HEART = art(16, 3, [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."])
PROMPT = art(17, 5, ["##.....", ".##....", "..##...", ".##....", "##.....", ".......", "..#####"])     # ">_": awake, waiting to be asked
QUESTION = art(18, 1, [".###.", "#...#", "....#", "...#.", "..#..", "..#..", ".....", "..#.."])


def plus(cx, cy, size):
    """A sparkle: a dot, a small cross or a big cross."""
    if size == 0:
        return [(cx, cy)]
    arm = range(-size, size + 1)
    return [(cx + d, cy) for d in arm] + [(cx, cy + d) for d in arm]


# ---- Byte: a robot with a monitor for a head --------------------------------
def byte(eyes="open", mouth="smile", arm="down", antenna=True, extra=()):
    g = grid()
    put(g, box(7, 1, 8, 1))                                  # antenna stem
    if antenna:
        put(g, box(7, 0, 8, 0))                              # antenna light
    put(g, box(1, 2, 14, 11))                                # head
    put(g, [(1, 2), (14, 2), (1, 11), (14, 11)], 0)          # rounded corners
    put(g, box(3, 4, 12, 9), 0)                              # the screen, dark
    put(g, box(7, 12, 8, 12))                                # neck
    put(g, box(4, 13, 11, 13)); put(g, box(3, 14, 12, 15))   # body
    put(g, [(2, 14), (2, 15)])                               # left arm, down
    face = {
        "open":   box(5, 5, 6, 6) + box(9, 5, 10, 6),
        "right":  box(6, 5, 7, 6) + box(10, 5, 11, 6),       # looking at the keyboard
        "shut":   box(5, 6, 6, 6) + box(9, 6, 10, 6),
        "wide":   box(4, 5, 6, 6) + box(9, 5, 11, 6),        # kept clear of the screen's edge
        "happy":  [(4, 6), (5, 5), (6, 6), (9, 6), (10, 5), (11, 6)],
        "dots":   [(5, 6), (10, 6)],
    }[eyes]
    lips = {
        "smile": [(5, 8), (10, 8)] + box(6, 9, 9, 9),
        "flat":  box(6, 8, 9, 8),
        "small": box(7, 8, 8, 8),
        "grin":  box(6, 8, 9, 8) + box(7, 9, 8, 9),
    }[mouth]
    put(g, face); put(g, lips)
    put(g, {
        "down":  [(13, 14), (13, 15)],
        "keys":  box(12, 13, 15, 13) + [(16, 13)],                                   # hand on the keys
        "lift":  [(12, 13), (13, 13), (14, 12), (15, 12), (16, 11)],                  # hand lifted off them
        "wave":  [(12, 13), (13, 13), (14, 13), (15, 12), (16, 11), (17, 10), (17, 9), (16, 8), (17, 8), (18, 8)],
    }[arm])
    put(g, extra)
    return g


KEYBOARD = art(15, 14, ["#.#.#.#.", "########"])
BYTE = {
    "idle":    byte(eyes="shut", mouth="small", antenna=False, extra=ZZ),
    "work1":   byte(eyes="right", mouth="smile", arm="keys", antenna=True,  extra=KEYBOARD + [(20, 12)]),
    "work2":   byte(eyes="right", mouth="flat",  arm="lift", antenna=False, extra=KEYBOARD + [(21, 10)]),
    "work3":   byte(eyes="right", mouth="smile", arm="keys", antenna=True,  extra=KEYBOARD + [(22, 8), (20, 12)]),
    "work4":   byte(eyes="shut",  mouth="flat",  arm="lift", antenna=False, extra=KEYBOARD + [(21, 10)]),
    "blocked": byte(eyes="wide", mouth="small", arm="wave", extra=BANG),
    "done":    byte(eyes="happy", mouth="grin", extra=HEART),
    "unknown": byte(eyes="dots", mouth="flat", antenna=False, extra=QUESTION + [(9, 0)]),
    "ready":   byte(eyes="open", mouth="smile", extra=PROMPT),
}


# ---- Wisp: a ghost in the machine -------------------------------------------
BODY = [(5, 10, 2), (4, 11, 3), (3, 12, 4)] + [(2, 13, y) for y in range(5, 13)]
HEM = {"a": "###.####.###", "b": "##.####.####", "flat": "############"}


def wisp(eyes="open", mouth="o", dy=0, hem="a", arm="rest", shadow=None, hollow=False, extra=()):
    g = grid()
    body = [(x, y) for x0, x1, y in BODY for x in range(x0, x1 + 1)]
    body += [(2 + i, 13) for i, ch in enumerate(HEM[hem]) if ch == "#"]
    if hem == "flat":
        body += box(1, 13, 14, 13)                           # settled on the ground
    put(g, body, dy=dy)
    holes = {
        "open":    box(5, 6, 6, 8) + box(9, 6, 10, 8),
        "shut":    box(5, 8, 6, 8) + box(9, 8, 10, 8),
        "wide":    box(5, 5, 6, 8) + box(9, 5, 10, 8),
        "intent":  [(6, 6)] + box(5, 7, 6, 8) + [(9, 6)] + box(9, 7, 10, 8),   # brows drawn in
        "happy":   [(4, 6), (5, 6), (3, 7), (6, 7), (10, 6), (11, 6), (9, 7), (12, 7)],   # two arches
        "dots":    [(5, 7), (10, 7)],
    }[eyes]
    lips = {
        "o":     box(7, 10, 8, 10),
        "big":   box(7, 10, 8, 11),
        "smile": [(6, 10), (9, 10)] + box(7, 11, 8, 11),
        "none":  [],
    }[mouth]
    if hollow:                                               # only the outline is left: it has faded out
        lit = {(x, y + dy) for x, y in body}
        edge = [(x, y) for x, y in lit if {(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)} - lit]
        g = grid(); put(g, edge); put(g, holes + lips, dy=dy)
    else:
        put(g, holes + lips, 0, dy=dy)
    put(g, {
        "rest": [(1, 9), (14, 9)],
        "cast": [(1, 9), (14, 8), (15, 7)],                  # reaching toward the sparkles
        "wave": [(1, 9), (14, 7), (15, 6), (16, 5), (16, 4)],
        "none": [],
    }[arm], dy=dy)
    if shadow:
        put(g, box(shadow[0], 15, shadow[1], 15))
    put(g, extra)
    return g


WISP = {
    "idle":    wisp(eyes="shut", mouth="none", dy=2, hem="flat", arm="none", extra=ZZ),
    "work1":   wisp(eyes="intent", mouth="smile", dy=0,  hem="a", arm="cast", shadow=(4, 11), extra=plus(20, 5, 2) + plus(19, 11, 0)),
    "work2":   wisp(eyes="intent", mouth="smile", dy=0,  hem="b", arm="cast", shadow=(4, 11), extra=plus(20, 5, 1) + plus(19, 11, 1)),
    "work3":   wisp(eyes="intent", mouth="smile", dy=-1, hem="a", arm="cast", shadow=(5, 10), extra=plus(20, 5, 0) + plus(19, 11, 2)),
    "work4":   wisp(eyes="intent", mouth="smile", dy=-1, hem="b", arm="cast", shadow=(5, 10), extra=plus(20, 5, 1) + plus(19, 11, 1)),
    "blocked": wisp(eyes="wide", mouth="big", dy=-1, hem="a", arm="wave", shadow=(5, 10), extra=BANG),
    "done":    wisp(eyes="happy", mouth="smile", dy=-1, hem="b", shadow=(5, 10), extra=HEART),
    "unknown": wisp(eyes="dots", mouth="none", dy=0, hem="a", arm="none", hollow=True, extra=QUESTION),
    "ready":   wisp(eyes="open", mouth="smile", dy=0, hem="a", shadow=(4, 11), extra=PROMPT),
}

CHARACTERS = {"byte": BYTE, "wisp": WISP}
BASE = {"byte": 0x100000, "wisp": 0x100040}       # Supplementary Private Use Area-B: no font uses it


def codepoints(name, state):
    start = BASE[name] + STATES.index(state) * 3
    return [start, start + 1, start + 2]


def text(name, state):
    return "".join(chr(c) for c in codepoints(name, state))


if __name__ == "__main__":
    for name, sprites in CHARACTERS.items():
        for state in STATES:
            print(f"--- {name} {state}")
            for row in sprites[state]:
                print("".join("#" if v else "." for v in row))
