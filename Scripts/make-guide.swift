// Renders the brochure Handbuch/Handbuch.html into a PDF, one A4 page per
// <section class="page"> (595 × 842 pt). WebKit draws it, so the text stays
// text. Elements with data-version get the given version. make-dmg.sh calls
// this and puts the PDF next to the app.
//
//   swift Scripts/make-guide.swift <out.pdf> [version]
import AppKit
import PDFKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("swift make-guide.swift <out.pdf> [version]\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: args[1])
let appVersion = args.count >= 3 ? args[2] : nil
let html = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../Handbuch/Handbuch.html").standardizedFileURL
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
