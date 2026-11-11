#!/usr/bin/env swift
// Regenerates the app icon: Assets.xcassets/AppIcon.appiconset (PNGs + Contents.json).
// Usage, from the repo root:   swift scripts/make-app-icon.swift
// build.sh turns the PNGs into AppIcon.icns. Change the colours below and rerun to restyle.
import AppKit

let background = "2C3440"   // dark slate
let glyph      = "F2EFE9"   // warm off-white

func color(_ hex: String) -> NSColor {
    let v = UInt32(hex, radix: 16)!
    return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

/// The "done" glyph (solid frame, three dots cut out) on a macOS rounded square, drawn into an exact-pixel bitmap.
func render(pixels px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let S = CGFloat(px)

    // Standard macOS icon body: 824/1024 of the canvas, corner radius ≈ 22.4% of the body.
    let body = S * 824 / 1024
    let inset = (S - body) / 2
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: body, height: body),
                            xRadius: body * 0.2237, yRadius: body * 0.2237)
    color(background).setFill()
    tile.fill()

    // Glyph on the menu bar's 18-unit grid; (9, 9) is its centre. Small sizes get a bigger glyph and larger dots.
    let small = px <= 32
    let unit = body * (small ? 0.72 : 0.60) / 16     // pixels per grid unit; the frame is 16 units wide
    let dotRadius: CGFloat = small ? 1.6 : 1.3
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {   // grid (top-left) → canvas (bottom-left)
        NSRect(x: S / 2 + (x - 9) * unit, y: S / 2 - (y + h - 9) * unit, width: w * unit, height: h * unit)
    }
    // "Done" state of the menu bar icon: solid frame with the three dots cut out (even-odd).
    let glyphPath = NSBezierPath(roundedRect: rect(1, 3.5, 16, 11), xRadius: 2.5 * unit, yRadius: 2.5 * unit)
    for x: CGFloat in [5.5, 9, 12.5] {
        glyphPath.append(NSBezierPath(ovalIn: rect(x - dotRadius, 9 - dotRadius, dotRadius * 2, dotRadius * 2)))
    }
    glyphPath.windingRule = .evenOdd
    color(glyph).setFill()
    glyphPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    .deletingLastPathComponent().deletingLastPathComponent()
let dir = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)" + (scale == 2 ? "@2x" : "") + ".png"
        try render(pixels: pt * scale).write(to: dir.appendingPathComponent(name))
        images.append(#"    {"idiom":"mac","size":"\#(pt)x\#(pt)","scale":"\#(scale)x","filename":"\#(name)"}"#)
    }
}
let json = "{\n  \"images\":[\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\":{\"version\":1,\"author\":\"xcode\"}\n}\n"
try json.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try #"{"info":{"version":1,"author":"xcode"}}"#.write(to: root.appendingPathComponent("Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) icons to \(dir.path)")
