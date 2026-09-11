// Generates a "!" icon for the unlock-instructions file: white glyph on a
// solid red circle, centered on a transparent 1024×1024 canvas.
//
// A bare glyph (no fill behind it) doesn't work here: Finder hit-tests
// custom file icons by alpha, and a thin shape like "!" leaves most of the
// icon's square transparent, so clicks next to the stroke miss the item
// entirely and only the text label below responds. A filled circle keeps
// the icon clearly smaller than the app/Applications icons next to it
// while staying fully clickable anywhere within it.
//
// Usage: swift Scripts/make-bang-icon.swift <out.png>

import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "bang-icon.png"
let S = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("no rep") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Solid circle — smaller than the full canvas (reads smaller than a
// full-bleed app icon) and fully opaque (so the whole visible icon is
// one clickable hit area, not just the thin glyph on top of it).
let diameter: CGFloat = 700
let circleRect = CGRect(x: (CGFloat(S) - diameter) / 2, y: (CGFloat(S) - diameter) / 2,
                         width: diameter, height: diameter)
ctx.setFillColor(NSColor.systemRed.cgColor)
ctx.fillEllipse(in: circleRect)

let config = NSImage.SymbolConfiguration(pointSize: 340, weight: .black)
guard let symbol = NSImage(systemSymbolName: "exclamationmark", accessibilityDescription: nil)?
    .withSymbolConfiguration(config)
else { fatalError("no symbol") }

// tint it solid white (SF Symbols draw in the current fill colour via sourceAtop)
let tinted = NSImage(size: symbol.size)
tinted.lockFocus()
symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
NSColor.white.set()
NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
tinted.unlockFocus()

let drawRect = NSRect(
    x: (CGFloat(S) - tinted.size.width) / 2,
    y: (CGFloat(S) - tinted.size.height) / 2,
    width: tinted.size.width, height: tinted.size.height
)
tinted.draw(in: drawRect)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
