// Draws the background of the DMG window (see make-dmg.sh) in the colors of
// the classic design: paper, petrol and the label gold – a petrol band with
// the title at the top (as on the guide's cover), the arrow between the
// icons and a black record rising from the bottom edge. No written hint: the
// arrow says it. The app icon sits at (140, 178), the Applications folder at
// (400, 178) – centers in points, matching the icon positions make-dmg.sh
// sets in the Finder.
//
//   swift Scripts/dmg-background.swift <out.png> <scale>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let scale = Double(args[2]) else {
    FileHandle.standardError.write("swift dmg-background.swift <out.png> <scale>\n".data(using: .utf8)!)
    exit(1)
}
let width = 540.0, height = 380.0
let appX = 140.0, applicationsX = 400.0, iconY = 178.0

func rgb(_ hex: UInt32, _ alpha: Double = 1) -> NSColor {
    NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
}
let paper = rgb(0xF4EFE5), cream = rgb(0xF4EFE5)
let petrolDeep = rgb(0x123C4B), petrolLight = rgb(0x2A6273)
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
    .draw(fromCenter: NSPoint(x: appX, y: top(iconY)), radius: 0,
          toCenter: NSPoint(x: appX, y: top(iconY)), radius: 170, options: [])

// A black record rising from the bottom edge like the one in the app icon,
// low enough that the Finder's black icon labels stay on the paper: grooves,
// a sheen and the gold label peeking out.
let record = NSPoint(x: width / 2, y: top(414))
let recordRadius = 150.0, labelRadius = 56.0
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
disc(recordRadius).fill()
NSGraphicsContext.restoreGraphicsState()
var groove = recordRadius - 4
while groove > labelRadius + 4 {
    NSColor.white.withAlphaComponent(groove.truncatingRemainder(dividingBy: 18) < 2 ? 0.10 : 0.04).setStroke()
    let ring = disc(groove)
    ring.lineWidth = 0.5
    ring.stroke()
    groove -= 2
}
NSGraphicsContext.saveGraphicsState()
disc(recordRadius).addClip()
NSGradient(colors: [.white.withAlphaComponent(0), .white.withAlphaComponent(0.16), .white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: record.x - recordRadius, y: record.y - recordRadius, width: 2 * recordRadius, height: 2 * recordRadius), angle: 120)
NSGraphicsContext.restoreGraphicsState()
gold.setFill()
disc(labelRadius).fill()
rgb(0xC99A45).setStroke()
let labelRing = disc(labelRadius - 13)
labelRing.lineWidth = 0.8
labelRing.stroke()

// The arrow from the app to the folder, centered in the gap between them. At
// the icons' center line it looked too high: the folder's body below its
// tab and the envelope in the app icon carry the weight lower, so it sits on
// the middle of the folder's body.
let arrowY = top(iconY + 7), arrowStart = (appX + applicationsX) / 2 - 52, arrowEnd = (appX + applicationsX) / 2 + 52
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

// The petrol band with the radial light of the guide's cover, the title in
// New York (the guide's serif) and the gold rule beneath it.
let bandHeight = 92.0
NSGradient(colors: [petrolLight, petrol, petrolDeep], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
    .draw(in: NSBezierPath(rect: NSRect(x: 0, y: top(bandHeight), width: width, height: bandHeight)),
          relativeCenterPosition: NSPoint(x: 0, y: 0.6))
let serif = NSFont(descriptor: NSFont.systemFont(ofSize: 28, weight: .semibold).fontDescriptor.withDesign(.serif)!, size: 28)!
let style = NSMutableParagraphStyle()
style.alignment = .center
let title = NSAttributedString(string: "Plattenregal", attributes: [
    .font: serif, .foregroundColor: cream, .paragraphStyle: style, .kern: -0.3,
])
let titleHeight = title.size().height
title.draw(in: NSRect(x: 0, y: top(24) - titleHeight, width: width, height: titleHeight))
gold.setFill()
NSBezierPath(roundedRect: NSRect(x: width / 2 - 20, y: top(24 + 42), width: 40, height: 2), xRadius: 1, yRadius: 1).fill()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
