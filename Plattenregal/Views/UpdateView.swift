import AppKit
import SwiftUI

/// The update window: "Suche …", then whether Plattenregal is up to date, a
/// newer version with what's new and how to install it, or what went wrong.
/// Its own small window like "Über Plattenregal", so it also opens while the
/// main window is closed.
struct UpdateView: View {
    static let windowID = "update"
    static let width: CGFloat = 460

    @State private var checker = UpdateChecker.shared
    @Environment(\.dismissWindow) private var dismissWindow
    /// „Herunterladen“ was clicked: the window says what comes next.
    @State private var downloading: AppVersion?

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            HStack(alignment: .top, spacing: AppStyle.cardPadding) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The whole width: three buttons don't fit beside the icon.
            HStack(spacing: AppStyle.itemSpacing) { actions }
        }
        .padding(AppStyle.pagePadding)
        .frame(width: Self.width)
        .animation(AppStyle.standardAnimation, value: checker.state)
        // Opened from the menu while nothing has been asked yet (or a
        // previous check was cancelled): ask now.
        .onAppear { if checker.state == .idle { checker.checkNow() } }
        .onDisappear {
            downloading = nil
            if checker.state == .checking { checker.cancelCheck() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch checker.state {
        case .idle, .checking:
            header(String(localized: "Nach Updates suchen"),
                   String(localized: "Plattenregal fragt bei GitHub nach der neuesten Version …"))
            ProgressView().progressViewStyle(.linear)
                .accessibilityLabel(String(localized: "Suche nach Updates"))
        case .upToDate(let latest):
            let current = checker.currentVersion
            header(String(localized: "Plattenregal ist aktuell"),
                   current > latest
                    ? String(localized: "Du hast Version \(current.description), neuer als die zuletzt veröffentlichte \(latest.description).")
                    : String(localized: "Du hast Version \(current.description), die neueste Version."))
            if let lastCheck = checker.lastCheck {
                Text("Geprüft um \(lastCheck.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .available(let release):
            available(release)
        case .failed(let error):
            header(error.title, error.errorDescription ?? ErrorMessages.generic,
                   systemImage: error.isOffline ? "wifi.slash" : "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch checker.state {
        case .idle, .checking:
            Spacer()
            SecondaryButton(title: String(localized: "Abbrechen")) { close() }
                .keyboardShortcut(.cancelAction)
        case .upToDate:
            Spacer()
            PrimaryButton(title: String(localized: "OK")) { close() }
                .keyboardShortcut(.defaultAction)
        case .available(let release):
            GhostButton(title: String(localized: "Diese Version überspringen")) {
                checker.skip(release)
                close()
            }
            Spacer()
            if downloading == release.version {
                PrimaryButton(title: String(localized: "Fertig")) { close() }
                    .keyboardShortcut(.defaultAction)
            } else {
                SecondaryButton(title: String(localized: "Später")) { close() }
                    .keyboardShortcut(.cancelAction)
                PrimaryButton(title: release.downloadURL == nil ? String(localized: "Auf GitHub öffnen") : String(localized: "Herunterladen")) {
                    checker.download(release)
                    downloading = release.version
                }
                .keyboardShortcut(.defaultAction)
            }
        case .failed:
            // GitHub's page may work where its interface doesn't (too many requests).
            GhostButton(title: String(localized: "Im Browser ansehen")) {
                if !NSWorkspace.shared.open(UpdateService.releasesPageURL) { NSSound.beep() }
            }
            Spacer()
            SecondaryButton(title: String(localized: "Schließen")) { close() }
                .keyboardShortcut(.cancelAction)
            PrimaryButton(title: String(localized: "Erneut versuchen")) { checker.checkNow() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: States

    @ViewBuilder
    private func available(_ release: AvailableRelease) -> some View {
        header(String(localized: "Plattenregal \(release.version.description) ist da"), details(of: release))
        let highlights = release.highlights
        if !highlights.isEmpty { whatsNew(highlights) }
        if downloading == release.version {
            AppBanner(message: release.downloadURL == nil
                      ? String(localized: "Die Seite der Version ist im Browser geöffnet. Lade dort die DMG und ersetze Plattenregal wie unten beschrieben.")
                      : String(localized: "Die DMG wird in deinem Browser geladen. Öffne sie danach und ersetze Plattenregal wie unten beschrieben."),
                      kind: .info)
        }
        installSteps
        Link(String(localized: "Alle Hinweise auf GitHub"), destination: release.pageURL)
            .font(.caption)
            // Petrol in Klassisch, the chosen accent in Modern – like every other link-like action.
            .tint(AppStyle.accent)
    }

    // MARK: Parts

    private func header(_ title: String, _ text: String, systemImage: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: AppStyle.itemSpacing) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(AppStyle.warningColor).accessibilityHidden(true)
                }
                Text(title)
            }
            .font(AppStyle.sectionTitle)
            Text(text).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Du hast Version 1.0.2 · veröffentlicht am 3. Nov. 2026 · 11 MB"
    private func details(of release: AvailableRelease) -> String {
        var parts = [String(localized: "Du hast Version \(checker.currentVersion.description).")]
        if let date = release.publishedAt {
            parts.append(String(localized: "Veröffentlicht am \(date.formatted(date: .long, time: .omitted))."))
        }
        if let size = release.downloadSize {
            parts.append(String(localized: "Download: \(size.formatted(.byteCount(style: .file)))."))
        }
        return parts.joined(separator: " ")
    }

    /// The points of the release notes, as in "Über Plattenregal"; scrolls when long.
    private func whatsNew(_ highlights: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
            Text("Was ist neu").font(AppStyle.captionMark).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    ForEach(Array(highlights.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: AppStyle.itemSpacing) {
                            Text(verbatim: "•").foregroundStyle(.tertiary).accessibilityHidden(true)
                            Text(Self.markdown(point)).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 200)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
    }

    private var installSteps: some View {
        VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
            Text("So aktualisierst du").font(AppStyle.captionMark).foregroundStyle(.secondary)
            // ⌘Q only sends it to the background then, and the Finder can't replace a running app.
            Text(AppLifecycle.shared.keepsRunning
                 ? String(localized: "Die geladene DMG öffnen, Plattenregal ganz beenden (⌥⌘Q) und die neue Version in den Ordner „Programme“ ziehen, die alte ersetzen. Sammlung, Regale, Einstellungen und Token bleiben erhalten. Fragt macOS danach nach dem Schlüsselbund, wähle „Immer erlauben“; eventuell ist „Dennoch öffnen“ unter Systemeinstellungen → Datenschutz & Sicherheit noch einmal nötig.")
                 : String(localized: "Die geladene DMG öffnen, Plattenregal beenden und die neue Version in den Ordner „Programme“ ziehen, die alte ersetzen. Sammlung, Regale, Einstellungen und Token bleiben erhalten. Fragt macOS danach nach dem Schlüsselbund, wähle „Immer erlauben“; eventuell ist „Dennoch öffnen“ unter Systemeinstellungen → Datenschutz & Sicherheit noch einmal nötig."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Bold, code and links of the release notes; plain text if that fails.
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    private func close() {
        dismissWindow(id: Self.windowID)
    }
}

/// „Nach Updates suchen …“ in the app menu, under „Über Plattenregal“.
struct UpdateCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Nach Updates suchen …") { UpdateCommand.check(openWindow) }
    }

    /// Opens the window and asks GitHub – from the menu, the settings and the
    /// record in the menu bar.
    static func check(_ openWindow: OpenWindowAction) {
        AppLifecycle.shared.leaveBackground()
        NSApp.activate()
        UpdateChecker.shared.checkNow()
        openWindow(id: UpdateView.windowID)
    }
}
