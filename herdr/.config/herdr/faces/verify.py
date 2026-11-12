"""Check the built fonts against the designs: tables, metrics, and every pixel as FreeType draws it."""
import os, sys
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont
from sprites import CHARACTERS, STATES, BASE, W, H
os.chdir(os.path.dirname(os.path.abspath(__file__)))
hack = TTFont(os.path.expanduser("~/Library/Fonts/HackNerdFontMono-Regular.ttf"))
ADV = hack["hmtx"][hack.getBestCmap()[ord("a")]][0]; ASC, DESC, UPM = hack["hhea"].ascent, hack["hhea"].descent, hack["head"].unitsPerEm
fails = []
def check(ok, what):
    if not ok: fails.append(what)
for style in ("Regular", "Bold", "Italic", "BoldItalic"):
    path = f"fonts/HerdrSprites-{style}.ttf"; f = TTFont(path); cm = f.getBestCmap()
    want = {BASE[n] + s * 3 + t for n in CHARACTERS for s in range(len(STATES)) for t in range(3)}
    check(want <= set(cm), f"{style}: missing codepoints"); check(set(cm) - want == {0x20}, f"{style}: unexpected codepoints {set(cm) - want}")
    check(f["head"].unitsPerEm == UPM, f"{style}: upm")
    check((f["hhea"].ascent, f["hhea"].descent, f["hhea"].lineGap) == (ASC, DESC, 0), f"{style}: hhea")
    o, ho = f["OS/2"], hack["OS/2"]
    check((o.sTypoAscender, o.sTypoDescender, o.sTypoLineGap, o.usWinAscent, o.usWinDescent, o.sxHeight) == (ho.sTypoAscender, ho.sTypoDescender, ho.sTypoLineGap, ho.usWinAscent, ho.usWinDescent, ho.sxHeight), f"{style}: OS/2 metrics")
    check(f["post"].isFixedPitch == 1, f"{style}: fixed pitch")
    check(all(adv == ADV for adv, _ in f["hmtx"].metrics.values()), f"{style}: advance widths")
    glyf = f["glyf"]
    for g in f.getGlyphOrder():
        gl = glyf[g]
        if gl.numberOfContours > 0:
            check(0 <= gl.xMin and gl.xMax <= ADV and DESC <= gl.yMin and gl.yMax <= ASC, f"{style}: {g} leaves its cell ({gl.xMin},{gl.yMin},{gl.xMax},{gl.yMax})")
            check(f["hmtx"][g][1] == gl.xMin, f"{style}: {g} left bearing")
    # every pixel, as FreeType rasterises the glyph
    size = 128; scale = size / UPM; font = ImageFont.truetype(path, size)
    cw, ch = round(ADV * scale) + 2, round((ASC - DESC) * scale) + 2
    for name, sprites in CHARACTERS.items():
        for s, state in enumerate(STATES):
            for t in range(3):
                img = Image.new("L", (cw, ch), 0); ImageDraw.Draw(img).text((0, ASC * scale), chr(BASE[name] + s * 3 + t), font=font, fill=255, anchor="ls")
                for r in range(H):
                    for c in range(8):
                        got = img.getpixel((int((c + 0.5) * ADV / 8 * scale), int((r + 0.5) * (ASC - DESC) / H * scale))) > 127
                        if got != bool(sprites[state][r][t * 8 + c]): fails.append(f"{style}: {name}.{state} tile {t} pixel ({c},{r}) drawn {got}")
    print(f"{style}: {len(want)} glyphs, metrics match Hack, {len(want) * 8 * H} pixels compared")
print("FAILURES:" if fails else "all checks passed", *fails[:20], sep="\n" if fails else " ")
sys.exit(1 if fails else 0)
