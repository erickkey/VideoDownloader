// Generates a white "!" on a transparent 1024×1024 canvas, heavily padded
// so it reads as roughly half-size once Finder renders it in an icon slot.
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

let config = NSImage.SymbolConfiguration(pointSize: 380, weight: .bold)
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
