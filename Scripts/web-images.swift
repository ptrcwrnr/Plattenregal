// Makes the pictures of the web page (Webseite/index.html) from the screenshots
// of Scripts/marketing-shots.sh: cut out, scaled down, as JPEG (the window's
// transparent corners become white, the page rounds them off again with
// --radius-window). German from the plain files, English from the „-en“ ones
// (UI_LANG=en zsh Scripts/marketing-shots.sh …). The search from the menu bar
// stays a PNG, it needs its transparent edge. Plus 48 covers for the cover wall.
//
//   swift Scripts/web-images.swift
//
// Result: Marketing/Webseite/<de|en>/*.jpg|png and Marketing/Webseite/Cover/*.jpg
// – not in the repository (real covers), published together with the page.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let shots = root.appendingPathComponent("Marketing/Aufnahmen")
let output = root.appendingPathComponent("Marketing/Webseite")

struct Picture {
    let name: String            // file on the page
    let shot: String            // screenshot without language suffix
    let crop: CGRect?           // in pixels of the screenshot, nil = all of it
    let width: Int              // pixel width on the page (2× for sharp screens)
}

let pictures = [
    Picture(name: "shelf", shot: "shelf", crop: nil, width: 1600),
    Picture(name: "card", shot: "detail", crop: CGRect(x: 480, y: 152, width: 1600, height: 854), width: 1200),
    Picture(name: "collection", shot: "modern", crop: nil, width: 1600),
    Picture(name: "settings", shot: "modern-settings", crop: CGRect(x: 0, y: 0, width: 1720, height: 1046), width: 1400),
    Picture(name: "sortcheck", shot: "sortcheck", crop: CGRect(x: 722, y: 154, width: 1116, height: 1144), width: 1000),
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("Web-Bilder: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func load(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("fehlt: \(url.path)") }
    return image
}

/// Crops, scales to `width` and flattens onto white.
func render(_ image: CGImage, crop: CGRect?, width: Int) -> CGImage {
    let part = crop.flatMap { image.cropping(to: $0) } ?? image
    let height = Int((Double(part.height) * Double(width) / Double(part.width)).rounded())
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fail("Zeichenfläche") }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high
    context.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL, type: String, quality: Double = 0.82) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else { fail("Ziel \(url.path)") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fail("schreiben \(url.path)") }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    print("\(url.path.replacingOccurrences(of: root.path + "/", with: ""))  \(image.width) × \(image.height)  \(size / 1024) KB")
}

let fm = FileManager.default
for language in ["de", "en"] {
    let folder = output.appendingPathComponent(language)
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let suffix = language == "de" ? "" : "-\(language)"
    for picture in pictures {
        let image = load(shots.appendingPathComponent("\(picture.shot)\(suffix).png"))
        write(render(image, crop: picture.crop, width: picture.width),
              to: folder.appendingPathComponent("\(picture.name).jpg"), type: "public.jpeg")
    }
    // The search keeps its transparent edge and its own shadow.
    let search = load(shots.appendingPathComponent("modern-quicksearch\(suffix).png"))
    write(search, to: folder.appendingPathComponent("search.png"), type: "public.png")
}

// Cover wall: the first 48 of the 72 random covers.
let covers = output.appendingPathComponent("Cover")
try? fm.removeItem(at: covers)
try? fm.createDirectory(at: covers, withIntermediateDirectories: true)
for n in 1...48 {
    let name = String(format: "%02d.jpg", n)
    let source = shots.appendingPathComponent("Cover/\(name)")
    guard fm.fileExists(atPath: source.path) else { fail("Cover fehlt: \(name) – zuerst Scripts/marketing-shots.sh") }
    try! fm.copyItem(at: source, to: covers.appendingPathComponent(name))
}
print("Marketing/Webseite/Cover  48 Cover")
