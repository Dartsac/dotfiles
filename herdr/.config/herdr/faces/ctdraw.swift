// Rasterise glyphs with CoreText, the engine Ghostty uses on macOS.
// usage: ctdraw <font.ttf> <size> <out.raw> <hex codepoint>...
// Prints the font's CoreText metrics, then one line per glyph; writes 8-bit grey bitmaps back to back.
import Foundation
import CoreText
import CoreGraphics

let args = CommandLine.arguments
let size = CGFloat(Double(args[2])!)
guard let provider = CGDataProvider(url: URL(fileURLWithPath: args[1]) as CFURL), let cg = CGFont(provider) else { fatalError("CoreText cannot load \(args[1])") }
let font = CTFontCreateWithGraphicsFont(cg, size, nil, nil)
print("family=\(CTFontCopyFamilyName(font)) style=\(CTFontCopyName(font, kCTFontStyleNameKey) ?? "?" as CFString) ascent=\(CTFontGetAscent(font)) descent=\(CTFontGetDescent(font)) leading=\(CTFontGetLeading(font)) upm=\(CTFontGetUnitsPerEm(font)) xheight=\(CTFontGetXHeight(font)) cap=\(CTFontGetCapHeight(font))")
var out = Data()
for hex in args[4...] {
    let scalar = Unicode.Scalar(UInt32(hex, radix: 16)!)!
    var units = Array(String(Character(scalar)).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: units.count)
    let found = CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count)
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(font, .horizontal, [glyphs[0]], &advance, 1)
    let w = Int((advance.width).rounded(.up)), h = Int((CTFontGetAscent(font) + CTFontGetDescent(font)).rounded(.up))
    var pixels = [UInt8](repeating: 0, count: w * h)
    let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 1, alpha: 1)
    var position = CGPoint(x: 0, y: CGFloat(h) - CTFontGetAscent(font))       // baseline, measured from the bottom
    CTFontDrawGlyphs(font, [glyphs[0]], &position, 1, ctx)
    print("U+\(hex) found=\(found) glyph=\(glyphs[0]) advance=\(advance.width) w=\(w) h=\(h)")
    out.append(contentsOf: pixels)
}
try! out.write(to: URL(fileURLWithPath: args[3]))
