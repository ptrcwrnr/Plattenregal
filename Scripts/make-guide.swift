// Renders the brochure Handbuch/Handbuch.html into a PDF, one A4 page per
// <section class="page"> (595 × 842 pt). WebKit draws it, so the text stays
// text. Elements with data-version get the given version. make-dmg.sh calls
// this for Plattenregal/Handbuch.pdf, which the app carries (Hilfe ›
// Handbuch) and the DMG shows next to it.
//
//   swift Scripts/make-guide.swift <out.pdf> [version] [--if-changed]
//
// With --if-changed an existing PDF of the same version that is newer than
// the brochure, its pictures and this script is kept: a new PDF differs in
// dates and ID even with the same content, and would show up in git each time.
import AppKit
import PDFKit
import WebKit

var args = Array(CommandLine.arguments.dropFirst())
let ifChanged = args.contains("--if-changed")
args.removeAll { $0 == "--if-changed" }
guard !args.isEmpty else {
    FileHandle.standardError.write("swift make-guide.swift <out.pdf> [version] [--if-changed]\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: args[0])
let appVersion = args.count >= 2 ? args[1] : nil
let script = URL(fileURLWithPath: #filePath)
let html = script.deletingLastPathComponent()
    .appendingPathComponent("../Handbuch/Handbuch.html").standardizedFileURL
/// Stored in the PDF, so --if-changed can tell the version apart.
let versionSubject = "Version \(appVersion ?? "-")"

func modified(_ url: URL) -> Date {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
}
if ifChanged, FileManager.default.fileExists(atPath: output.path),
   PDFDocument(url: output)?.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String == versionSubject {
    let folder = html.deletingLastPathComponent()
    let sources = [script] + (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])?
        .compactMap { $0 as? URL } ?? [])
    let built = modified(output)
    if sources.allSatisfy({ modified($0) <= built }) {
        print("\(output.path) (unverändert)")
        exit(0)
    }
}
let pageSize = CGSize(width: 595, height: 842)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("Handbuch: \(message)\n".data(using: .utf8)!)
    exit(1)
}

@MainActor final class Renderer: NSObject, WKNavigationDelegate {
    let webView = WKWebView(frame: CGRect(origin: .zero, size: CGSize(width: pageSize.width, height: pageSize.height * 20)))

    func start() {
        webView.navigationDelegate = self
        webView.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await render() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("\(error)") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail("\(error)") }

    func render() async {
        do {
            if let version = appVersion {
                let escaped = version.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                _ = try await webView.evaluateJavaScript("document.querySelectorAll('[data-version]').forEach(e => e.textContent = \"\(escaped)\")")
            }
            // Fonts and images must be ready before anything is drawn.
            _ = try await webView.callAsyncJavaScript("""
                await document.fonts.ready;
                await Promise.all([...document.images].map(i => i.complete ? null : new Promise(r => { i.onload = i.onerror = r; })));
                """, contentWorld: .page)
            let broken = try await webView.evaluateJavaScript("[...document.images].filter(i => !i.naturalWidth).map(i => i.getAttribute('src')).join(', ')") as? String ?? ""
            guard broken.isEmpty else { fail("Bild fehlt: \(broken)") }
            let pages = try await webView.evaluateJavaScript("document.querySelectorAll('.page').length") as? Int ?? 0
            guard pages > 0 else { fail("keine Seiten gefunden") }
            webView.frame.size.height = pageSize.height * CGFloat(pages)
            try await Task.sleep(for: .milliseconds(300))

            let document = PDFDocument()
            for index in 0..<pages {
                let configuration = WKPDFConfiguration()
                configuration.rect = CGRect(x: 0, y: pageSize.height * CGFloat(index), width: pageSize.width, height: pageSize.height)
                let data = try await webView.pdf(configuration: configuration)
                guard let page = PDFDocument(data: data)?.page(at: 0) else { fail("Seite \(index + 1) ließ sich nicht erzeugen") }
                document.insert(page, at: document.pageCount)
            }
            document.documentAttributes = [
                PDFDocumentAttribute.titleAttribute: "Plattenregal – Handbuch",
                PDFDocumentAttribute.authorAttribute: "Patrice Werner",
                PDFDocumentAttribute.subjectAttribute: versionSubject,
            ]
            guard document.write(to: output) else { fail("konnte \(output.path) nicht schreiben") }
            print(output.path)
            exit(0)
        } catch {
            fail("\(error)")
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = MainActor.assumeIsolated { Renderer() }
MainActor.assumeIsolated { renderer.start() }
app.run()
