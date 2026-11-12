#!/usr/bin/env python3
"""Generate pixel-aligned, state-colored sprites outside git via theme-sync.

The original 24x16 design is rasterized on Ghostty's integer cell grid, with
one sbix strike for each common device-pixel font size. SVG outlines at the
font's fractional advance left a dark seam between the three tiles. Bitmap
strikes use the complete rounded cell, so the joins have no fractional gap.

Input: a resolved palette as JSON on stdin. --output <folder> and optional
--check. Generated fonts contain paid theme colors and never belong in git.
"""
import argparse
import hashlib
from array import array
from functools import lru_cache
import io
import json
import math
from pathlib import Path
import struct
import sys
import zlib

from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables.sbixStrike import Strike
from fontTools.ttLib.tables.sbixGlyph import Glyph
from fontTools.ttLib.tables._g_l_y_f import GlyphCoordinates

from characters import COLORS
from sprites import CHARACTERS, H

HERE = Path(__file__).resolve().parent
# A running Ghostty keeps the font it has loaded: a changed file under the
# same family name is not read again, and a sprite added since shows as "?".
# So the name carries a tag that changes with the drawings and their colors'
# names. Ghostty's config names the family (a test checks it is the current
# one); reloading that config then loads the new font, with nothing restarted.
TAG = hashlib.sha1(repr((sorted(COLORS.items()), CHARACTERS)).encode()).hexdigest()[:4]
FAMILY = "Herdr Sprites Pixel " + TAG
FILES = "HerdrSpritesPixel-%s-%%s.ttf" % TAG
STYLES = ("Regular", "Bold", "Italic", "BoldItalic")
PIXEL_SIZES = tuple(range(8, 97)) + (104, 112, 120, 128, 144, 160, 192)


def resolve(name, palette):
    if "+" not in name:
        return palette[name]
    first, rest = name.split("+")
    second, percent = rest.split(":")
    a, b = (bytes.fromhex(palette[n][1:]) for n in (first, second))
    return "#" + "".join("%02x" % round(x + (y - x) * int(percent) / 100) for x, y in zip(a, b))


def nearest(value):
    """Ghostty/Zig rounds halves away from zero, unlike Python's round."""
    return math.floor(value + 0.5)


def cell(font, ppem):
    upm = font["head"].unitsPerEm
    face_width = font["hmtx"]["space"][0] * ppem / upm
    face_height = (font["hhea"].ascent - font["hhea"].descent + font["hhea"].lineGap) * ppem / upm
    width, height = nearest(face_width), nearest(face_height)
    baseline = nearest(-font["hhea"].descent * ppem / upm - (height - face_height) / 2)
    return width, height, baseline


@lru_cache(maxsize=16_384)
def bitmap(name, width, height, color):
    """A tile's PNG, exactly width x height, without any antialiasing at joins.

    Integer edges are computed on the whole cell, not each path's bounds. This
    is the same design as the outline font, just snapped onto device pixels.
    """
    character, state, tile = name.split(".")
    rows = CHARACTERS[character][state]
    tile = int(tile)
    rgba = bytes.fromhex(color[1:]) + b"\xff"
    xs = [nearest(c * width / 8) for c in range(9)]
    ys = [nearest(r * height / H) for r in range(H + 1)]
    pixels = [bytearray(width * 4) for _ in range(height)]
    for r in range(H):
        for c in range(8):
            if rows[r][tile * 8 + c]:
                for y in range(ys[r], ys[r + 1]):
                    pixels[y][xs[c] * 4:xs[c + 1] * 4] = rgba * (xs[c + 1] - xs[c])

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    raw = b"".join(b"\x00" + row for row in pixels)  # PNG filter 0: no prediction
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def colored_font(source, palette):
    """Preserve the outline fallback, codepoints and metrics; add pixel strikes."""
    font = TTFont(source, recalcTimestamp=False)
    for record in font["name"].names:
        value = record.toUnicode().replace("Herdr Sprites", FAMILY).replace("HerdrSprites-", "HerdrSpritesPixel%s-" % TAG)
        record.string = value.encode(record.getEncoding())
    # CoreText reports glyf's bounds even for sbix. Give every tile the same
    # full-cell bounds with two zero-ink, one-point contours. Otherwise Ghostty
    # crops each bitmap to that tile's different ink bounds before snapping it,
    # which splits the picture. Original ink coordinates are untouched.
    advance = font["hmtx"]["space"][0]
    for name in font.getGlyphOrder():
        if name in (".notdef", "space"):
            continue
        glyph = font["glyf"][name]
        if glyph.numberOfContours == 0:
            glyph.coordinates, glyph.flags, glyph.endPtsOfContours = GlyphCoordinates(), array("B"), []
        n = len(glyph.coordinates)
        glyph.coordinates.extend([(0, font["hhea"].descent), (advance, font["hhea"].ascent)])
        glyph.flags.extend([1, 1])
        glyph.endPtsOfContours.extend([n, n + 1])
        glyph.numberOfContours += 2
        glyph.recalcBounds(font["glyf"])
        font["hmtx"][name] = (advance, 0)
    font["sbix"] = newTable("sbix")
    font["sbix"].strikes = {}
    for ppem in PIXEL_SIZES:
        width, height, baseline = cell(font, ppem)
        strike = Strike(ppem=ppem, resolution=72)
        for name in font.getGlyphOrder():
            if name in (".notdef", "space"):
                continue
            state = name.split(".")[1]
            color = resolve(COLORS["working" if state.startswith("work") else state], palette)
            strike.glyphs[name] = Glyph(glyphName=name, originOffsetX=0, originOffsetY=0,
                                       graphicType="png ", imageData=bitmap(name, width, height, color))
        font["sbix"].strikes[ppem] = strike
    output = io.BytesIO()
    font.save(output)
    font.close()
    return output.getvalue()


def install(palette, folder, check=False):
    """Paths that changed (or would change). Identical input leaves fonts untouched.

    Fonts of earlier drawings are removed; Ghostty keeps what it has loaded."""
    folder = Path(folder)
    changed = []
    for old in sorted(set(folder.glob("HerdrSpritesPixel-*.ttf")) - {folder / (FILES % style) for style in STYLES}):
        changed.append(str(old))
        if not check:
            old.unlink()
    for style in STYLES:
        data = colored_font(HERE / "fonts" / ("HerdrSprites-%s.ttf" % style), palette)
        target = folder / (FILES % style)
        if target.exists() and target.read_bytes() == data:
            continue
        changed.append(str(target))
        if not check:
            folder.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix(".tmp")
            temporary.write_bytes(data)
            temporary.replace(target)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    print(json.dumps(install(json.load(sys.stdin), args.output, args.check)))


if __name__ == "__main__":
    main()
