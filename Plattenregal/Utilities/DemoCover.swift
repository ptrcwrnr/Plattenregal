import AppKit
import CoreText

/// Covers for the demo, drawn on the device: the demo stays offline and uses
/// no Discogs images. Each release gets a colour of its own with artist and
/// title, so the collection grid, the shelf and the statistics look alive.
/// Addressed like real covers (`plattenregal-demo://cover?…`), so every view
/// shows them through `CoverCache` without knowing about the demo. Also the
/// app's „Gezeichnete Cover“ and the widget's stand-in for a cover it
/// doesn't have, so part of the app and of the widget alike.
nonisolated enum DemoCover {
    static let scheme = "plattenregal-demo"

    static func url(artist: String, title: String, seed: Int) -> String {
        var components = URLComponents()
        components.scheme = scheme; components.host = "cover"
        components.queryItems = [.init(name: "artist", value: artist), .init(name: "title", value: title),
                                 .init(name: "seed", value: "\(seed)")]
        return components.string ?? "\(scheme)://cover"
    }

    /// 0..<360, the same as `seed * 47 % 360` for the demo's small seeds.
    static func hueDegrees(_ seed: Int) -> Int {
        ((seed % 360) * 47 % 360 + 360) % 360
    }

    static func render(_ url: URL, pixelSize: Int) -> CGImage? {
        guard url.scheme == scheme else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
        let seed = Int(value("seed")) ?? 0
        let size = max(64, min(pixelSize, 1_200))
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let side = CGFloat(size)
        // Two neighbouring hues per record, spread around the colour wheel.
        // Reduced first: any Discogs ID (or a stray huge or negative number)
        // gives a hue in 0..<1 instead of overflowing.
        let hue = CGFloat(hueDegrees(seed)) / 360
        let top = NSColor(hue: hue, saturation: 0.55, brightness: 0.78, alpha: 1).cgColor
        let bottom = NSColor(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.42, alpha: 1).cgColor
        if let gradient = CGGradient(colorsSpace: nil, colors: [top, bottom] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])
        }
        // A record peeking out at the top right, as a quiet motif. Artist
        // and title go to the bottom left: the app puts its marks at the top
        // left (position in the compartment, search hits) and the bottom
        // right (number of copies), where they would cover the lettering.
        context.setFillColor(NSColor(white: 0, alpha: 0.18).cgColor)
        context.fillEllipse(in: CGRect(x: side * 0.42, y: side * 0.36, width: side * 0.72, height: side * 0.72))
        context.setFillColor(NSColor(white: 1, alpha: 0.18).cgColor)
        context.fillEllipse(in: CGRect(x: side * 0.72, y: side * 0.66, width: side * 0.12, height: side * 0.12))

        func draw(_ text: String, font: CTFont, y: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.cgColor]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            // Cut short of the copy count at the bottom right instead of
            // running off the cover.
            let truncated = CTLineCreateTruncatedLine(line, Double(side * 0.68), .end,
                CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))) ?? line
            context.textPosition = CGPoint(x: side * 0.08, y: y)
            CTLineDraw(truncated, context)
        }
        draw(value("artist").uppercased(), font: CTFontCreateWithName("Helvetica-Bold" as CFString, side * 0.075, nil), y: side * 0.18)
        draw(value("title"), font: CTFontCreateWithName("Helvetica" as CFString, side * 0.07, nil), y: side * 0.08)
        return context.makeImage()
    }
}
