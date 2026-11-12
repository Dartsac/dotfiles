"""Build the Herdr Sprites font: every sprite as three one-cell glyphs.

The font copies the cell of the terminal font (Hack Nerd Font Mono): same units
per em, advance width, ascent and descent. A sprite's pixels then fill the cell
exactly, and three glyphs side by side join into one picture.
"""
import os, sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.removeOverlaps import removeOverlaps
from sprites import CHARACTERS, STATES, BASE, W, H

CELL = 8                                   # sprite pixels per terminal cell
out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
hack = TTFont(os.path.expanduser("~/Library/Fonts/HackNerdFontMono-Regular.ttf"))
UPM = hack["head"].unitsPerEm
ADV = hack["hmtx"][hack.getBestCmap()[ord("a")]][0]
ASC, DESC = hack["hhea"].ascent, hack["hhea"].descent
XH, CAP = hack["OS/2"].sxHeight, hack["OS/2"].sCapHeight
assert (ASC - DESC) % H == 0, "cell height must divide into whole pixel rows"
XS = [round(i * ADV / CELL) for i in range(CELL + 1)]
YS = [ASC - r * (ASC - DESC) // H for r in range(H + 1)]


def glyph(rows):
    """One cell: a clockwise rectangle for each run of lit pixels in each row."""
    pen = TTGlyphPen(None)
    for r, row in enumerate(rows):
        c = 0
        while c < CELL:
            if not row[c]:
                c += 1; continue
            start = c
            while c < CELL and row[c]: c += 1
            x0, x1, top, bottom = XS[start], XS[c], YS[r], YS[r + 1]
            pen.moveTo((x0, bottom)); pen.lineTo((x0, top)); pen.lineTo((x1, top)); pen.lineTo((x1, bottom)); pen.closePath()
    return pen.glyph()


def left_edge(rows):
    """Where the leftmost lit pixel starts. hmtx must say this, or the outline is drawn shifted."""
    lit = [c for row in rows for c in range(CELL) if row[c]]
    return XS[min(lit)] if lit else 0


order, cmap, glyphs = [".notdef", "space"], {0x20: "space"}, {".notdef": TTGlyphPen(None).glyph(), "space": TTGlyphPen(None).glyph()}
bearing = {".notdef": 0, "space": 0}
for name, sprites in CHARACTERS.items():
    for s, state in enumerate(STATES):
        for t in range(W // CELL):
            g = f"{name}.{state}.{t}"
            order.append(g); cmap[BASE[name] + s * 3 + t] = g
            rows = [row[t * CELL:(t + 1) * CELL] for row in sprites[state]]
            glyphs[g] = glyph(rows); bearing[g] = left_edge(rows)

STYLES = {  # style name: (weight, fsSelection, macStyle, italic angle)
    "Regular": (400, 0x40, 0, 0), "Bold": (700, 0x20, 1, 0), "Italic": (400, 0x01, 2, -10), "Bold Italic": (700, 0x21, 3, -10),
}
for style, (weight, fs, mac, angle) in STYLES.items():
    fb = FontBuilder(unitsPerEm=UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(dict(glyphs))
    fb.setupHorizontalMetrics({g: (ADV, bearing[g]) for g in order})
    fb.setupHorizontalHeader(ascent=ASC, descent=DESC, lineGap=0)
    ps = "HerdrSprites-" + style.replace(" ", "")
    fb.setupNameTable({"familyName": "Herdr Sprites", "styleName": style, "uniqueFontIdentifier": ps + ";1.0", "fullName": "Herdr Sprites " + style, "psName": ps, "version": "Version 1.0"})
    fb.setupOS2(sTypoAscender=ASC, sTypoDescender=DESC, sTypoLineGap=0, usWinAscent=ASC, usWinDescent=-DESC, sxHeight=XH, sCapHeight=CAP,
                usWeightClass=weight, fsSelection=fs, xAvgCharWidth=ADV, achVendID="HRDR")
    fb.setupPost(isFixedPitch=1, italicAngle=angle)
    font = fb.font
    font["head"].macStyle = mac
    font["OS/2"].panose.bFamilyType, font["OS/2"].panose.bProportion = 2, 9      # Latin text, monospaced
    removeOverlaps(font)                   # merge the rectangles into clean outlines
    for g in order:                        # merging must not have moved anything
        gl = font["glyf"][g]; gl.recalcBounds(font["glyf"])
        assert font["hmtx"][g] == (ADV, bearing[g]) and (gl.numberOfContours == 0 or gl.xMin == bearing[g]), g
    path = os.path.join(out_dir, f"HerdrSprites-{style.replace(' ', '')}.ttf")
    font.save(path); print("wrote", path, os.path.getsize(path), "bytes,", len(order) - 2, "sprite glyphs")
