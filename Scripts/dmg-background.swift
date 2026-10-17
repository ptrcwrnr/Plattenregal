// Draws the background of the DMG window (see make-dmg.sh) in the colors of
// the classic design: paper, petrol and the label gold. The app icon sits at
// (130, 190), the Applications folder at (430, 190) and the guides
// (Handbuch.pdf, User Guide.pdf) at (620, 190) and (770, 190) – centers in
// points, matching the icon positions make-dmg.sh sets in the Finder.
//
//   swift Scripts/dmg-background.swift <out.png> <scale>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write("swift dmg-background.swift <out.png> <scale>\n".data(using: .utf8)!)
    exit(1)
}
let width = 880.0, height = 400.0
let appX = 130.0, applicationsX = 430.0

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> NSColor {
    NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
}
let paper = rgb(0xF4EFE5)
let petrol = rgb(0x1D4C5B), ink = rgb(0x233A3E), muted = rgb(0x63716E), gold = rgb(0xE2B660)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// AppKit counts y from the bottom; `top` converts from the Finder's top-left.
func top(_ y: Double) -> Double { height - y }

// Paper with a soft light from above the icon.
paper.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
NSGradient(starting: NSColor.white.withAlphaComponent(0.55), ending: NSColor.white.withAlphaComponent(0))!
    .draw(fromCenter: NSPoint(x: appX, y: top(190)), radius: 0,
          toCenter: NSPoint(x: appX, y: top(190)), radius: 190, options: [])

// The chart colors of the app (petrol, gold, moss, rust, blue, plum, olive).
let palette: [NSColor] = [0x2F6F80, 0xD9A441, 0x7FA38A, 0xC2714F, 0x5B7DA6, 0x8C5A7A, 0xA8A060].map { rgb($0) }

// An equalizer along the bottom edge, its colors running through the palette;
// the record covers its middle.
var barX = 4.0, bar = 0
while barX < width {
    let level = abs(sin(Double(bar) * 0.55) * cos(Double(bar) * 0.21)) * 0.8 + abs(sin(Double(bar) * 1.7)) * 0.2
    let barHeight = 8 + 46 * level
    let position = barX / width * Double(palette.count - 1)
    let color = palette[Int(position)].blended(withFraction: position - floor(position),
                                                of: palette[min(Int(position) + 1, palette.count - 1)])!
    color.withAlphaComponent(0.42).setFill()
    NSBezierPath(roundedRect: NSRect(x: barX, y: -3, width: 6, height: barHeight + 3), xRadius: 3, yRadius: 3).fill()
    barX += 10
    bar += 1
}

// Notes drifting in the upper corners, clear of the title and the icons.
let notes: [(String, Double, Double, Double, Int)] = [
    ("♪", 40, 52, -10, 0), ("♫", 92, 98, 8, 3), ("♩", 30, 150, -6, 5),
    ("♫", 690, 54, 6, 1), ("♬", 790, 44, 10, 4), ("♪", 852, 104, -8, 2),
]
for (glyph, x, y, angle, colorIndex) in notes {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: x, yBy: top(y))
    transform.rotate(byDegrees: angle)
    transform.concat()
    let string = NSAttributedString(string: glyph, attributes: [
        .font: NSFont.systemFont(ofSize: 30), .foregroundColor: palette[colorIndex].withAlphaComponent(0.55),
    ])
    let size = string.size()
    string.draw(at: NSPoint(x: -size.width / 2, y: -size.height / 2))
    NSGraphicsContext.restoreGraphicsState()
}

// A black record rising from the bottom edge like the one in the app icon,
// low enough that the Finder's black icon labels stay on the paper: grooves,
// a sheen and the gold label peeking out.
let record = NSPoint(x: (appX + applicationsX) / 2, y: top(452))
func disc(_ radius: Double) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: record.x - radius, y: record.y - radius, width: 2 * radius, height: 2 * radius))
}
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = ink.withAlphaComponent(0.25)
shadow.shadowBlurRadius = 18
shadow.shadowOffset = NSSize(width: 0, height: -2)
shadow.set()
rgb(0x16191A).setFill()
disc(168).fill()
NSGraphicsContext.restoreGraphicsState()
var groove = 164.0
while groove > 66 {
    NSColor.white.withAlphaComponent(groove.truncatingRemainder(dividingBy: 18) < 2 ? 0.10 : 0.04).setStroke()
    let ring = disc(groove)
    ring.lineWidth = 0.5
    ring.stroke()
    groove -= 2
}
NSGraphicsContext.saveGraphicsState()
disc(168).addClip()
NSGradient(colors: [.white.withAlphaComponent(0), .white.withAlphaComponent(0.16), .white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: record.x - 168, y: record.y - 168, width: 336, height: 336), angle: 120)
NSGraphicsContext.restoreGraphicsState()
gold.setFill()
disc(62).fill()
rgb(0xC99A45).setStroke()
let labelRing = disc(48)
labelRing.lineWidth = 0.8
labelRing.stroke()

// The arrow from the app to the folder, centered in the gap between them. At
// the icons' center line (190) it looked too high: the folder's body below its
// tab and the envelope in the app icon carry the weight lower, so it sits on
// the middle of the folder's body.
let arrowY = top(197), arrowStart = (appX + applicationsX) / 2 - 60, arrowEnd = (appX + applicationsX) / 2 + 60
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: arrowStart, y: arrowY))
arrow.line(to: NSPoint(x: arrowEnd - 4, y: arrowY))
arrow.lineWidth = 4
arrow.lineCapStyle = .round
petrol.setStroke()
arrow.stroke()
let tip = NSBezierPath()
tip.move(to: NSPoint(x: arrowEnd - 14, y: arrowY + 12))
tip.line(to: NSPoint(x: arrowEnd, y: arrowY))
tip.line(to: NSPoint(x: arrowEnd - 14, y: arrowY - 12))
tip.lineWidth = 4
tip.lineCapStyle = .round
tip.lineJoinStyle = .round
gold.setStroke()
tip.stroke()

// Title and hint, centered.
func text(_ string: String, size: Double, weight: NSFont.Weight, color: NSColor, y: Double) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style,
        .kern: weight == .semibold ? 0.2 : 0,
    ]
    let string = NSAttributedString(string: string, attributes: attributes)
    let lineHeight = string.size().height
    string.draw(in: NSRect(x: 0, y: top(y) - lineHeight, width: width, height: lineHeight))
}
text("Plattenregal", size: 22, weight: .semibold, color: ink, y: 30)
text("Zum Installieren in den Programme-Ordner ziehen", size: 12, weight: .regular, color: muted, y: 62)
text("Drag to the Applications folder to install", size: 11, weight: .regular, color: muted.withAlphaComponent(0.75), y: 80)

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
