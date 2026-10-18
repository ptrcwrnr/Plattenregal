// Writes Webseite/icon.png: the app icon from the brochure with its shadow
// drawn in (offset 14, blur 22, black 35 % at 156 pt, as on the guide's
// cover). Browsers clipped the CSS drop-shadow at the image's frame, which
// showed as a square edge around the icon; a shadow in the image itself
// looks the same everywhere. The canvas adds 96 px left, right and top and
// 160 px below the 512 px icon, which index.html allows for.
//
//   swift Scripts/web-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appendingPathComponent("Handbuch/Bilder/icon.png")
let output = root.appendingPathComponent("Webseite/icon.png")
guard let icon = NSImage(contentsOf: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("Kein Symbol: \(source.path)\n".data(using: .utf8)!)
    exit(1)
}
let size = 512.0, side = 96.0, top = 96.0, bottom = 160.0
let scale = size / 156 // CSS-Pixel des Symbols → Bildpixel
let width = Int(size + 2 * side), height = Int(size + top + bottom)
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 22 * scale,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
context.draw(icon, in: CGRect(x: side, y: bottom, width: size, height: size))
let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: output)
print(output.path, width, "×", height)
