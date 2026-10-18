// Draws the background of the DMG window (see make-dmg.sh) in the style of the
// guide (Handbuch/Handbuch.html): a petrol band like its cover with the gold
// kicker, the serif title and the gold rule, below it plain paper for the
// icons, the hint in the guide's lead style and a folio at the foot. The app
// icon sits at (130, 190), the Applications folder at (430, 190) and the
// guides (Handbuch.pdf, User Guide.pdf) at (620, 190) and (770, 190) – centers
// in points, matching the icon positions make-dmg.sh sets in the Finder.
//
//   swift Scripts/dmg-background.swift <out.png> <scale> [<version>]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write("swift dmg-background.swift <out.png> <scale> [<version>]\n".data(using: .utf8)!)
    exit(1)
}
let version = args.count > 3 ? args[3] : nil
let width = 880.0, height = 400.0
let appX = 130.0, applicationsX = 430.0

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> NSColor {
    NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
}
// The colors of the guide (its :root), which are those of the classic design.
let paper = rgb(0xF4EFE5), cream = rgb(0xF4EFE5)
let petrol = rgb(0x1D4C5B), petrolDeep = rgb(0x123C4B), petrolLight = rgb(0x2A6273)
let ink = rgb(0x233A3E), muted = rgb(0x63716E), gold = rgb(0xE2B660)

// The guide's spacing scale (pt) and its margin.
enum Space {
    static let s = 8.0, m = 12.0, l = 16.0, xl = 20.0, xl2 = 24.0, xl3 = 32.0, xl4 = 48.0
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// AppKit counts y from the bottom; `top` converts from the Finder's top-left.
func top(_ y: Double) -> Double { height - y }

// The guide's typefaces: New York for titles and the lead, SF for the rest.
func serif(_ size: Double, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
    var descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.serif)!
    if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
    return NSFont(descriptor: descriptor, size: size)!
}
func sans(_ size: Double, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

/// Draws a line of text with its top at `y`; centered, or from `x` to the
/// left or right edge of the margin.
func text(_ string: String, font: NSFont, color: NSColor, y: Double, kern: Double = 0,
          alignment: NSTextAlignment = .center) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    let string = NSAttributedString(string: string, attributes: [
        .font: font, .foregroundColor: color, .paragraphStyle: style, .kern: kern,
    ])
    let lineHeight = string.size().height
    let inset = alignment == .center ? 0 : Space.xl4
    string.draw(in: NSRect(x: inset, y: top(y) - lineHeight, width: width - 2 * inset, height: lineHeight))
}

// Paper, as on the guide's pages.
paper.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// The petrol band with the radial light of the guide's cover.
let bandHeight = 108.0
let band = NSRect(x: 0, y: top(bandHeight), width: width, height: bandHeight)
NSGradient(colors: [petrolLight, petrol, petrolDeep], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
    .draw(in: NSBezierPath(rect: band), relativeCenterPosition: NSPoint(x: 0, y: 0.6))

text("INSTALLIEREN  ·  INSTALL", font: sans(8.5, weight: .semibold), color: gold, y: Space.xl2, kern: 3)
text("Plattenregal", font: serif(30, weight: .semibold), color: cream, y: Space.xl2 + Space.l, kern: -0.3)
gold.setFill()
NSBezierPath(roundedRect: NSRect(x: width / 2 - 20, y: top(Space.xl2 + Space.l + 44), width: 40, height: 2),
             xRadius: 1, yRadius: 1).fill()

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

// The hint below the icon labels: German in the guide's lead, English beneath
// it as secondary text.
text("Zum Installieren Plattenregal auf den Programme-Ordner ziehen.", font: serif(14), color: ink, y: 296)
text("Drag Plattenregal to the Applications folder to install.", font: sans(11), color: muted, y: 296 + Space.xl2)

// The folio, as at the foot of the guide's pages.
let folioY = height - Space.xl2 - 12
let folio = NSMutableAttributedString(string: "Plattenregal", attributes: [
    .font: sans(9.5, weight: .semibold), .foregroundColor: petrol,
])
folio.append(NSAttributedString(string: version.map { " · Version \($0)" } ?? "", attributes: [
    .font: sans(9.5), .foregroundColor: muted,
]))
folio.draw(at: NSPoint(x: Space.xl4, y: top(folioY) - folio.size().height))
text("macOS 27 · Apple Silicon", font: sans(9.5), color: muted, y: folioY, kern: 0.2, alignment: .right)

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
