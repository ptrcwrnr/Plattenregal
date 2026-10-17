// Takes the screenshots of the guide (Handbuch/Bilder/<de|en>/*.jpg) anew
// from the demo collection, in the design Klassisch: builds Debug, starts the
// app once per picture with --snapshot (the app draws its own window into a
// PNG and quits – no screen recording permission, no clicks), then crops,
// scales and saves each one as JPEG. Run it after visible changes to the
// pages, then render the guide again (make-guide.swift / make-dmg.sh).
//
//   swift Scripts/guide-screenshots.swift [de|en]   (both without argument)
//
// The main window remembers its frame in the app's real settings; the script
// sets it to 1223 × 793 pt for the pictures (the crops below rely on that)
// and puts the previous frame back afterwards.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let languages = CommandLine.arguments.count > 1 ? Array(CommandLine.arguments.dropFirst()) : ["de", "en"]
let home = FileManager.default.homeDirectoryForCurrentUser
let container = home.appendingPathComponent("Library/Containers/de.private.Plattenregal/Data")
let preferences = container.appendingPathComponent("Library/Preferences/de.private.Plattenregal").path
let frameKey = "NSWindow Frame main"
let windowSize = CGSize(width: 1223, height: 793)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("Bilder: \(message)\n".data(using: .utf8)!)
    exit(1)
}

@discardableResult
func run(_ tool: String, _ arguments: [String], timeout: TimeInterval = 600) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { fail("\(tool) ließ sich nicht starten: \(error)") }
    let deadline = Date.now.addingTimeInterval(timeout)
    var data = Data()
    // Read while it runs, so a full pipe can't block it.
    while process.isRunning {
        data.append(pipe.fileHandleForReading.availableData)
        if Date.now > deadline { process.terminate(); fail("\(tool) nach \(Int(timeout)) s abgebrochen") }
    }
    data.append(pipe.fileHandleForReading.readDataToEndOfFile())
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

// MARK: Pictures

/// Where a picture is cut from the window, in points.
enum Crop {
    /// The whole width, from the top down to this share of the height.
    case top(Double)
    /// A piece of this size at the bottom right corner.
    case bottomRight(width: Double, height: Double)
    /// A piece of this width in the middle, from y to y + height.
    case centered(width: Double, y: Double, height: Double)
    /// The whole width, from the top down to this many points.
    case topPoints(Double)
    /// Any rectangle.
    case rect(x: Double, y: Double, width: Double, height: Double)
}

struct Shot {
    let name: String
    let arguments: [String]
    let crop: Crop
    let maxWidth: Int
}

let shots: [Shot] = [
    Shot(name: "collection", arguments: ["--preview-page=Collection"], crop: .top(0.70), maxWidth: 1600),
    Shot(name: "fan", arguments: ["--preview-page=Collection", "--preview-actions"],
         crop: .bottomRight(width: 318, height: 182), maxWidth: 700),
    Shot(name: "shelf", arguments: ["--preview-page=Regal"], crop: .top(0.75), maxWidth: 1600),
    Shot(name: "sortin", arguments: ["--preview-page=Regal", "--preview-sortin"],
         crop: .centered(width: 660, y: 76, height: 639), maxWidth: 1100),
    Shot(name: "statistics", arguments: ["--preview-page=Statistik"], crop: .top(0.69), maxWidth: 1600),
    Shot(name: "settings-discogs", arguments: ["--settings-tab=Discogs"], crop: .topPoints(270), maxWidth: 1200),
    Shot(name: "settings-shelf", arguments: ["--settings-tab=Regal"], crop: .rect(x: 20, y: 58, width: 440, height: 204), maxWidth: 900),
]

/// Cuts, scales and saves as JPEG. On the main window, a plain piece of the
/// toolbar covers the three (inactive) window buttons.
func save(_ source: URL, crop: Crop, maxWidth: Int, to output: URL) {
    guard let data = try? Data(contentsOf: source), let image = NSBitmapImageRep(data: data)?.cgImage else {
        fail("\(source.lastPathComponent) nicht lesbar")
    }
    // The app draws at the screen's backing scale.
    let scale = Double(NSScreen.main?.backingScaleFactor ?? 2)
    let isMainWindow = abs(Double(image.width) / scale - windowSize.width) < 1 && abs(Double(image.height) / scale - windowSize.height) < 2
    let full = CGSize(width: Double(image.width) / scale, height: Double(image.height) / scale)
    let points: CGRect = switch crop {
    case .top(let share): CGRect(x: 0, y: 0, width: full.width, height: full.height * share)
    case .bottomRight(let width, let height): CGRect(x: full.width - width, y: full.height - height, width: width, height: height)
    case .centered(let width, let y, let height): CGRect(x: (full.width - width) / 2, y: y, width: width, height: height)
    case .topPoints(let height): CGRect(x: 0, y: 0, width: full.width, height: height)
    case .rect(let x, let y, let width, let height): CGRect(x: x, y: y, width: width, height: height)
    }
    let pixels = CGRect(x: points.minX * scale, y: points.minY * scale, width: points.width * scale, height: points.height * scale).integral
    guard let cropped = image.cropping(to: pixels) else { fail("Zuschnitt außerhalb von \(source.lastPathComponent)") }
    let factor = min(1, Double(maxWidth) / pixels.width)
    let width = Int(pixels.width * factor), height = Int(pixels.height * factor)
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("Zeichenfläche") }
    // Paper behind the transparent window corners.
    context.setFillColor(CGColor(srgbRed: 0xF4 / 255, green: 0xEF / 255, blue: 0xE5 / 255, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high
    context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
    if isMainWindow, points.minX == 0, points.minY == 0,
       let patch = image.cropping(to: CGRect(x: 110 * scale, y: 8 * scale, width: 85 * scale, height: 37 * scale)) {
        let unit = factor * scale
        context.draw(patch, in: CGRect(x: 15 * unit, y: Double(height) - 45 * unit, width: 85 * unit, height: 37 * unit))
    }
    guard let jpeg = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    else { fail("JPEG") }
    do { try jpeg.write(to: output) } catch { fail("\(output.path): \(error)") }
}

// MARK: Run

if !NSRunningApplication.runningApplications(withBundleIdentifier: "de.private.Plattenregal").isEmpty {
    fail("Plattenregal läuft – bitte zuerst beenden (die Fenstergröße wird sonst beim Beenden überschrieben).")
}

print("Debug-Build …")
let build = run("/usr/bin/xcodebuild", ["-project", root.appendingPathComponent("Plattenregal.xcodeproj").path,
                                        "-scheme", "Plattenregal", "-configuration", "Debug", "build"])
guard build.status == 0 else { fail("Debug-Build fehlgeschlagen") }
let settings = run("/usr/bin/xcodebuild", ["-project", root.appendingPathComponent("Plattenregal.xcodeproj").path,
                                           "-scheme", "Plattenregal", "-configuration", "Debug", "-showBuildSettings"]).output
guard let products = settings.split(separator: "\n").first(where: { $0.contains(" BUILT_PRODUCTS_DIR = ") })?
    .components(separatedBy: " = ").last else { fail("BUILT_PRODUCTS_DIR nicht gefunden") }
let binary = "\(products)/Plattenregal.app/Contents/MacOS/Plattenregal"

// The window size for the pictures, the user's own afterwards.
let previousFrame = run("/usr/bin/defaults", ["read", preferences, frameKey])
let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1512, height: 949)
// Mostly beside the screen, on the side away from the pointer: under a
// resting pointer, rows and covers would be drawn hovered. The app still
// draws the whole window.
let pointer = NSEvent.mouseLocation
let windowX = pointer.x < screen.midX ? screen.maxX - 200 : screen.minX - windowSize.width + 200
let frame = "\(Int(windowX)) \(Int(screen.maxY - windowSize.height - 40)) \(Int(windowSize.width)) \(Int(windowSize.height)) \(Int(screen.minX)) \(Int(screen.minY)) \(Int(screen.width)) \(Int(screen.height))"
func restoreFrame() {
    if previousFrame.status == 0 {
        run("/usr/bin/defaults", ["write", preferences, frameKey, previousFrame.output.trimmingCharacters(in: .whitespacesAndNewlines)])
    } else {
        run("/usr/bin/defaults", ["delete", preferences, frameKey])
    }
}
signal(SIGINT) { _ in restoreFrame(); exit(130) }

let temporary = container.appendingPathComponent("tmp")
for language in languages {
    let folder = root.appendingPathComponent("Handbuch/Bilder/\(language)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for shot in shots {
        run("/usr/bin/defaults", ["write", preferences, frameKey, frame])
        let file = "handbuch-\(language)-\(shot.name).png"
        let snapshot = temporary.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: snapshot)
        // The settings pairs first: after a lone flag like --demo, macOS would
        // read "--demo -signatureDesign" as a pair and take "atelier" for a
        // file to open – and an app opened with a file shows no start window.
        run(binary, ["-signatureDesign", "atelier", "-appearanceMode", "light", "-atelierCoverFrame", "sleeve",
                     "-tourSeen", "YES", "-AppleLanguages", "(\(language))", "--demo", "--screenshots"]
            + shot.arguments + ["--snapshot=\(file)"], timeout: 90)
        guard FileManager.default.fileExists(atPath: snapshot.path) else { restoreFrame(); fail("kein Schnappschuss für \(language)/\(shot.name)") }
        let output = folder.appendingPathComponent("\(shot.name).jpg")
        save(snapshot, crop: shot.crop, maxWidth: shot.maxWidth, to: output)
        try? FileManager.default.removeItem(at: snapshot)
        print("\(language)/\(shot.name).jpg")
    }
}
restoreFrame()
