"""Every sprite pixel, as CoreText draws the glyphs, against the design. Also CoreText's metrics against Hack's."""
import subprocess, sys, os, re, tempfile
from sprites import CHARACTERS, STATES, BASE, W, H
size = 128
here = os.path.dirname(os.path.abspath(__file__)); os.chdir(here)
tmp = tempfile.mkdtemp()
tool = os.path.join(tmp, "ctdraw")
subprocess.run(["swiftc", "-O", "ctdraw.swift", "-o", tool], check=True, capture_output=True)
def run(path, cps):
    raw = os.path.join(tmp, "ct.raw")
    out = subprocess.run([tool, path, str(size), raw, *[f"{c:X}" for c in cps]], capture_output=True, text=True, check=True).stdout.splitlines()
    return out[0], out[1:], open(raw, "rb").read()
metrics = lambda head: head[head.index("ascent="):]
hack_head, _, _ = run(os.path.expanduser("~/Library/Fonts/HackNerdFontMono-Regular.ttf"), [0x61])
fails = []
for style in ("Regular", "Bold", "Italic", "BoldItalic"):
    cps = [BASE[n] + s * 3 + t for n in CHARACTERS for s in range(len(STATES)) for t in range(3)]
    head, lines, raw = run(f"fonts/HerdrSprites-{style}.ttf", cps)
    if metrics(head) != metrics(hack_head): fails.append(f"{style}: CoreText metrics differ from Hack: {head} vs {hack_head}")
    asc = float(re.search(r"ascent=([\d.]+)", head).group(1)); desc = float(re.search(r"descent=([\d.]+)", head).group(1))
    off = 0; i = 0; compared = 0
    for n, sprites in CHARACTERS.items():
        for s, state in enumerate(STATES):
            for t in range(3):
                m = re.search(r"found=(\w+) glyph=(\d+) advance=([\d.]+) w=(\d+) h=(\d+)", lines[i]); i += 1
                found, gid, adv, w, h = m.group(1) == "true", int(m.group(2)), float(m.group(3)), int(m.group(4)), int(m.group(5))
                if not found or gid == 0: fails.append(f"{style}: {n}.{state}.{t} has no glyph")
                img = raw[off:off + w * h]; off += w * h; top = h - (asc + desc)     # CoreText's origin is the bottom
                for r in range(H):
                    for c in range(8):
                        x = int((c + 0.5) * adv / 8); y = int(top + (r + 0.5) * (asc + desc) / H)
                        got = img[y * w + x] > 127; compared += 1                 # CGContext rows run top to bottom in memory
                        if got != bool(sprites[state][r][t * 8 + c]): fails.append(f"{style}: {n}.{state} tile {t} pixel ({c},{r}) drawn {got}")
    print(f"{style}: CoreText loaded it as '{head.split(' ascent')[0]}', metrics equal Hack's, {compared} pixels compared")
print("FAILURES:" if fails else "all CoreText checks passed", *fails[:12], sep="\n" if fails else " ")
sys.exit(1 if fails else 0)
