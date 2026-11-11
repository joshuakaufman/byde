import AppKit

/// Menu bar icon, drawn in code. Template image: macOS tints it for light and dark menu bars.
/// "Framed pause": a rounded frame with three dots. Geometry in points, origin top-left (flipped drawing).
enum MenuIcon {
    static func image(done: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            let frame = NSBezierPath(roundedRect: NSRect(x: 1, y: 3.5, width: 16, height: 11), xRadius: 2.5, yRadius: 2.5)
            let dots = [5.5, 9, 12.5].map { x in
                NSBezierPath(ovalIn: NSRect(x: x - 1.3, y: 9 - 1.3, width: 2.6, height: 2.6))
            }
            if done {
                // Solid frame with the dots cut out as true transparency (even-odd).
                for d in dots { frame.append(d) }
                frame.windingRule = .evenOdd
                frame.fill()
            } else {
                frame.lineWidth = 1.3
                frame.stroke()
                for d in dots { d.fill() }
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
