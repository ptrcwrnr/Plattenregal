// Renders the product pictures of Marketing/Produktbilder.html: every
// <section class="frame"> becomes one JPEG in Marketing/Bilder/, at twice its
// CSS size (App Store 2880 × 1800, posts 1080 × 1350, story 1080 × 1920).
// WebKit draws the page in an off-screen window, so shadows and filters look
// as in Safari. The screenshots come from Scripts/marketing-shots.sh.
//
//   swift Scripts/make-marketing.swift [id …]   (all frames without argument)
//   swift Scripts/make-marketing.swift --updates [id …]
//     (the pictures for new versions from Scripts/update-bilder.html, no covers:
//      update-<version>, seit-post, seit-story)
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let arguments = Array(CommandLine.arguments.dropFirst())
let updates = arguments.contains("--updates")
let page = root.appendingPathComponent(updates ? "Scripts/update-bilder.html" : "Marketing/Produktbilder.html")
let output = root.appendingPathComponent("Marketing/Bilder")
let wanted = Set(arguments.filter { $0 != "--updates" })
let scale: CGFloat = 2

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("Produktbilder: \(message)\n".data(using: .utf8)!)
    exit(1)
}

@MainActor final class Renderer: NSObject, WKNavigationDelegate {
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    // Off screen, but a real window: snapshots then use its 2× backing.
    lazy var window: NSWindow = {
        let window = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: 1440, height: 900),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = webView
        window.orderBack(nil)
        return window
    }()

    func start() {
        _ = window
        webView.navigationDelegate = self
        webView.loadFileURL(page, allowingReadAccessTo: root)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { Task { await render() } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("\(error)") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail("\(error)") }

    func render() async {
        do {
            // Fonts and every picture (also those added by the script) first.
            _ = try await webView.callAsyncJavaScript("""
                await document.fonts.ready;
                await Promise.all([...document.images].map(i => i.complete ? null : new Promise(r => { i.onload = i.onerror = r; })));
                """, contentWorld: .page)
            let broken = try await webView.evaluateJavaScript("[...document.images].filter(i => !i.naturalWidth).map(i => i.getAttribute('src')).join(', ')") as? String ?? ""
            guard broken.isEmpty else { fail("Bild fehlt: \(broken) – zuerst Scripts/marketing-shots.sh ausführen") }
            let frames = try await webView.evaluateJavaScript("[...document.querySelectorAll('.frame')].map(f => [f.id, f.offsetWidth, f.offsetHeight])") as? [[Any]] ?? []
            guard !frames.isEmpty else { fail("keine Bilder gefunden") }
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

            for frame in frames {
                guard let id = frame[0] as? String, let width = frame[1] as? Double, let height = frame[2] as? Double else { continue }
                if !wanted.isEmpty && !wanted.contains(id) { continue }
                _ = try await webView.evaluateJavaScript("""
                    document.documentElement.dataset.only = '\(id)';
                    document.querySelectorAll('.frame').forEach(f => f.classList.toggle('only', f.id === '\(id)'));
                    """)
                let size = CGSize(width: width, height: height)
                window.setContentSize(size)
                webView.frame = CGRect(origin: .zero, size: size)
                // Hidden pictures are decoded only once shown: wait for them (at most 20 s –
                // a full window screenshot of 2560 × 1600 once took longer than 5 s and the
                // window stayed empty; no requestAnimationFrame – an off-screen window gets no frames).
                _ = try await webView.callAsyncJavaScript("""
                    const pictures = [...document.getElementById(id).querySelectorAll('img')];
                    await Promise.race([
                        Promise.all(pictures.map(i => i.decode().catch(() => null))),
                        new Promise(r => setTimeout(r, 20000))
                    ]);
                    """, arguments: ["id": id], contentWorld: .page)
                try await Task.sleep(for: .milliseconds(1500))

                let configuration = WKSnapshotConfiguration()
                configuration.rect = CGRect(origin: .zero, size: size)
                configuration.afterScreenUpdates = true
                // A large screenshot is sometimes drawn only after the first snapshot
                // (the window stayed empty in about one of six pictures): take one to
                // warm up, then the real one.
                _ = try await webView.takeSnapshot(configuration: configuration)
                try await Task.sleep(for: .milliseconds(1000))
                let image = try await webView.takeSnapshot(configuration: configuration)
                save(image, pixels: CGSize(width: width * scale, height: height * scale),
                     to: output.appendingPathComponent("\(id).jpg"))
            }
            exit(0)
        } catch {
            fail("\(error)")
        }
    }

    /// Exactly the wanted pixel size, without alpha (the App Store refuses it).
    func save(_ image: NSImage, pixels: CGSize, to url: URL) {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                                         bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)
        else { fail("Zeichenfläche") }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.converting(to: .sRGB, renderingIntent: .perceptual)?
            .representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        else { fail("JPEG") }
        do { try data.write(to: url) } catch { fail("\(url.path): \(error)") }
        print("Marketing/Bilder/\(url.lastPathComponent)  \(Int(pixels.width)) × \(Int(pixels.height))")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = MainActor.assumeIsolated { Renderer() }
MainActor.assumeIsolated { renderer.start() }
app.run()
