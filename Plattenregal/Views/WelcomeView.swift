import SwiftUI

/// The welcome on the first launch: what Plattenregal is and the three steps
/// to the own shelf, with the Discogs token as the way in and the demo for a
/// look around first. Replaces the tour of six pages with screenshots – an
/// empty app had nothing to show of it yet, and every change to the pages
/// meant taking 24 pictures again. Also from Hilfe › „Erste Schritte“.
@MainActor @Observable
final class AppWelcome {
    static let shared = AppWelcome()
    /// Set once the welcome (before it the tour) was closed, however;
    /// "Einstellungen zurücksetzen" brings it back.
    static let seenKey = "tourSeen"

    /// The open welcome.
    var request: WelcomeRequest?

    func show() { request = WelcomeRequest() }

    /// On the first launch only. Not in the demo (its settings are fresh on
    /// every start) and not for the tests, which run inside the app.
    func showOnFirstLaunch() {
        #if DEBUG
        // To look at the welcome in the demo: --preview-welcome.
        if ProcessInfo.processInfo.arguments.contains("--preview-welcome") { return show() }
        #endif
        guard !DemoMode.isActive, !AppDefaults.store.bool(forKey: Self.seenKey),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        show()
    }

    func markSeen() { AppDefaults.store.set(true, forKey: Self.seenKey) }
}

struct WelcomeRequest: Identifiable { let id = UUID() }

/// The brochure that also lies in the DMG (Plattenregal/Handbuch.pdf and the
/// English Handbook.pdf, made from Handbuch/Handbuch.html and Handbook.html by
/// Scripts/make-guide.swift), in the app's language, opened in the reader
/// macOS uses for PDFs.
enum Handbook {
    @MainActor static func open() {
        let name = Bundle.main.preferredLocalizations.first == "en" ? "Handbook" : "Handbuch"
        guard let url = Bundle.main.url(forResource: name, withExtension: "pdf") else {
            AppLog.warning("Hilfe", "\(name).pdf fehlt in der App")
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
        AppLog.info("Hilfe", "Handbuch geöffnet (\(name).pdf)")
    }
}

/// The Help menu, in place of the help book the app doesn't have.
struct HelpCommands: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        // No ⌘?: macOS keeps it for the search field of the Help menu.
        Button("Handbuch") { Handbook.open() }
        Button("Erste Schritte") {
            // The main window may be closed (the app keeps running without it).
            openWindow(id: "main")
            AppWelcome.shared.show()
        }
        if !DemoMode.isActive {
            Button("Demo starten …") { DemoMode.confirmStart() }
        }
    }
}

struct WelcomeView: View {
    let close: () -> Void
    @Environment(\.openSettings) private var openSettings

    static let width: CGFloat = 520

    private struct Step: Identifiable {
        let id: Int
        let title: String
        let text: String
    }

    private let steps = [
        Step(id: 1, title: String(localized: "Discogs verbinden"),
             text: String(localized: "Trag deinen persönlichen Token von Discogs ein. Damit liest Plattenregal deine Collection und Wantlist.")),
        Step(id: 2, title: String(localized: "Abgleichen"),
             text: String(localized: "⌥⌘R holt alle Platten. Neue Platten trägst du bei Discogs ein, beim nächsten Abgleich sind sie hier.")),
        Step(id: 3, title: String(localized: "Regal einrichten"),
             text: String(localized: "Leg unter Einstellungen › Regal deine Regale an, so wie sie bei dir stehen. Dann zeigt Plattenregal für jede Platte Fach und Position.")),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            HStack(spacing: AppStyle.rowSpacing) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    Text("Willkommen bei Plattenregal").font(AppStyle.dialogTitle)
                    Text("Deine Schallplatten auf dem Mac: die ganze Sammlung auf einen Blick und immer die Antwort, wo eine Platte im Regal steht.")
                        .font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                ForEach(steps) { step in
                    HStack(alignment: .firstTextBaseline, spacing: AppStyle.rowSpacing) {
                        number(step.id)
                        VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                            Text(step.title).font(.headline)
                            Text(step.text)
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            controls
        }
        .padding(AppStyle.pagePadding)
        .frame(width: Self.width)
    }

    /// The step's number in an accent ring – no filled badge.
    private func number(_ value: Int) -> some View {
        Text(value, format: .number)
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(AppStyle.accent)
            .frame(width: 26, height: 26)
            .overlay { Circle().strokeBorder(AppStyle.accent.opacity(0.6), lineWidth: 1.5) }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var controls: some View {
        // In the demo (from the Help menu) Discogs is switched off and the demo already runs.
        if DemoMode.isActive {
            HStack {
                Spacer()
                PrimaryButton(title: String(localized: "Los geht’s"), action: close)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            HStack(spacing: AppStyle.itemSpacing) {
                GhostButton(title: String(localized: "Später"), action: close)
                Spacer()
                SecondaryButton(title: String(localized: "Demo starten …")) {
                    close()
                    DemoMode.confirmStart()
                }
                PrimaryButton(title: String(localized: "Token eintragen …"), action: openDiscogsSettings)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// Straight to the token field (focused there when no token is stored).
    private func openDiscogsSettings() {
        close()
        SettingsRequest.shared.show(.discogs)
        openSettings()
    }
}
