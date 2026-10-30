import AppKit

/// A vinyl record as a one-color symbol, for the menu bar: SF Symbols has a
/// CD (`opticaldisc`) but no record. Drawn as a template, so macOS tints it
/// like its own symbols (light, dark, highlighted).
///
/// A full disc with lines cut out of it: two grooves as arcs on opposite
/// sides (where light catches a record – full rings made it a target), the
/// edge of the label and the spindle hole.
enum RecordGlyph {
    /// Menu bar symbols are drawn at 18 × 18 pt.
    static let menuBarSize: CGFloat = 18

    static let menuBarImage: NSImage = {
        let size = NSSize(width: menuBarSize, height: menuBarSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            func circle(_ radius: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            }
            NSColor.black.setFill()
            circle(8).fill()
            // Everything below is cut out of the disc.
            NSGraphicsContext.current?.compositingOperation = .clear
            for (radius, start) in [(6.2, 100.0), (4.9, 110.0)] as [(CGFloat, CGFloat)] {
                for offset: CGFloat in [0, 180] {
                    let arc = NSBezierPath()
                    arc.appendArc(withCenter: center, radius: radius, startAngle: start + offset, endAngle: start + offset + 70)
                    arc.lineWidth = 0.7
                    arc.lineCapStyle = .round
                    arc.stroke()
                }
            }
            let label = circle(3.1)
            label.lineWidth = 0.7
            label.stroke()
            circle(0.9).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = String(localized: "Im Regal suchen")
        return image
    }()
}
