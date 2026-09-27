import SwiftUI
import AppKit

/// "Über Plattenregal": a small card with icon, name, version and author
/// instead of the system panel, whose empty credits area made it tall.
struct AboutView: View {
    static let windowID = "about"
    static let author = "Patrice Werner"

    /// "Version 1.0 (092026)" from the bundle, as in the protocol header.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: AppStyle.itemSpacing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Plattenregal").font(AppStyle.dialogTitle)
            Text(Self.versionLine)
                .font(.callout).foregroundStyle(.secondary)
                .monospacedDigit().textSelection(.enabled)
            Text("© 2026 \(Self.author)")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.top, AppStyle.tightSpacing)
        }
        .padding(.horizontal, AppStyle.pagePadding)
        .padding(.top, AppStyle.pagePadding + AppStyle.itemSpacing)
        .padding(.bottom, AppStyle.pagePadding)
        .frame(width: 260)
    }
}

/// Replaces "Über Plattenregal" in the app menu so it opens `AboutView`.
struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Über Plattenregal") { openWindow(id: AboutView.windowID) }
    }
}
