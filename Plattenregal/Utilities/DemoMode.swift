import AppKit
import Foundation
import SwiftUI

/// A launch that leaves the keychain and Discogs alone: the demo, and in
/// Debug builds the launches for pictures (`--preview-…`, `--snapshot=…`).
/// Those show the real collection, but a Debug build is signed differently
/// from the installed app, so reading the token made macOS ask for the
/// keychain password on every recording – and a picture needs no Discogs.
nonisolated enum OfflineLaunch {
    static let isActive: Bool = DemoMode.isActive || isPreview

    /// Debug only: started with a preview or snapshot switch.
    static let isPreview: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--preview-") || $0.hasPrefix("--snapshot=") }
        #else
        false
        #endif
    }()
}

/// Plattenregal with a sample collection instead of the own one – to try
/// things out or show the app. Started and ended by relaunching, so the real
/// database and the demo are never open at the same time. The relaunch can't
/// pass arguments (the sandbox drops them), so the old instance leaves a
/// short-lived request in the user defaults that the new one takes at launch;
/// `--demo` works too, from Xcode or the command line.
///
/// In the demo everything is kept apart from the real app:
/// - the collection lives in memory only and is gone when the demo ends,
/// - settings go to their own defaults (`AppDefaults`), fresh each time,
/// - backups and covers go to a temporary folder,
/// - Discogs is switched off and the keychain is never touched,
/// - the main window keeps its own size and place (`mainWindowID`).
/// Only the protocol is shared, marked "Demo" at the start of the session.
nonisolated enum DemoMode {
    static let argument = "--demo"

    /// `--statistics-demo` (Debug) opens the same demo on the statistics page.
    static let isActive: Bool = ProcessInfo.processInfo.arguments.contains { $0 == argument || $0 == "--statistics-demo" }
        || takeLaunchRequest()

    /// The main window's id. macOS saves the window's size and place under
    /// it ("NSWindow Frame main"), in the real defaults – the demo has its
    /// own, so trying something out never changes the size of the real
    /// app's window.
    static var mainWindowID: String { isActive ? "demo" : "main" }

    /// Set right before relaunching into the demo, taken (and removed) by
    /// the next launch. Only valid for a minute: if the relaunch fails, a
    /// later normal start must not end up in the demo.
    private static let requestKey = "demoLaunchRequest"
    private static func takeLaunchRequest() -> Bool {
        // The real defaults on purpose: `AppDefaults` depends on `isActive`.
        let defaults = UserDefaults.standard
        let requested = defaults.object(forKey: requestKey) as? Date
        if requested != nil { defaults.removeObject(forKey: requestKey) }
        return accepts(request: requested, isTest: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
    }

    /// Whether a launch request makes this launch a demo: only a fresh one
    /// (a failed relaunch must not turn a later normal start into a demo),
    /// and never for the tests, which run inside the app.
    static func accepts(request: Date?, now: Date = .now, isTest: Bool) -> Bool {
        guard let request, !isTest else { return false }
        return abs(now.timeIntervalSince(request)) < 60
    }

    /// The banner on the pages and the demo notes and locked controls in the
    /// settings (token field, automatic export and backup). Debug builds can
    /// leave them out for screenshots of the sample collection
    /// (`--screenshots`); the services keep checking `isActive`, so nothing
    /// is synced, exported or backed up.
    static var showsBanner: Bool {
        #if DEBUG
        isActive && !ProcessInfo.processInfo.arguments.contains("--screenshots")
        #else
        isActive
        #endif
    }

    /// Another Plattenregal of this build besides this one – a demo from
    /// Xcode, say, whose folder must stay.
    private static var otherInstanceRunning: Bool {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains { $0.processIdentifier != own && !$0.isTerminated }
    }

    /// Backups and covers of the demo; emptied when a demo starts, removed
    /// at the next normal launch.
    static let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Plattenregal-Demo", isDirectory: true)

    /// Once at launch, before anything reads settings or folders. A normal
    /// launch removes what the last demo left in the temporary folder
    /// (covers, backups) – unless a demo is still running beside it.
    static func prepare() {
        guard isActive else {
            if !otherInstanceRunning { try? FileManager.default.removeItem(at: temporaryDirectory) }
            return
        }
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        AppDefaults.resetDemo()
        // Screenshot runs (`--snapshot`) set the demo's window themselves.
        let screenshotRun = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--snapshot=") }
        if !screenshotRun { adoptMainWindowFrame(in: .standard) }
    }

    /// Where macOS keeps the size and place of each main window (see `mainWindowID`).
    static let mainFrameKey = "NSWindow Frame main"
    static let demoFrameKey = "NSWindow Frame demo"

    /// The demo opens with the size and place of the real main window, so
    /// it looks like the app does every day. It still saves its frame under
    /// its own key: resizing during the demo leaves the real window alone.
    /// Without a real window yet (first start right into the demo) the demo
    /// keeps what it had.
    /// The window's own rectangle from a saved frame ("x y width height"
    /// followed by the screen's); nil for anything unusable.
    static func windowRect(fromSavedFrame saved: String) -> NSRect? {
        let numbers = saved.split(separator: " ").compactMap { Double($0) }
        guard numbers.count >= 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        return NSRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    static func adoptMainWindowFrame(in defaults: UserDefaults) {
        guard let frame = defaults.string(forKey: mainFrameKey), !frame.isEmpty else { return }
        defaults.set(frame, forKey: demoFrameKey)
    }

    // MARK: Starting and ending

    /// Asks first, then relaunches into the demo.
    @MainActor static func confirmStart() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Demo starten?")
        alert.informativeText = String(localized: "Plattenregal startet neu – mit einer Beispielsammlung zum Ausprobieren. Du kannst alles verändern: Platten einsortieren, Regale anlegen, Einstellungen ändern. Nichts davon wird gespeichert, und deine eigene Sammlung bleibt unberührt.\n\nBeenden kannst du die Demo jederzeit über „Demo beenden“.")
        if DiscogsSyncService.shared.isRunning {
            alert.informativeText += String(localized: "\n\nDie laufende Synchronisierung wird dabei abgebrochen; es wird nichts halb gespeichert, und sie lässt sich später einfach wiederholen.")
        }
        alert.addButton(withTitle: String(localized: "Demo starten"))
        alert.addButton(withTitle: String(localized: "Abbrechen"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        relaunch(intoDemo: true)
    }

    /// Back to the own collection; the demo's changes are dropped.
    @MainActor static func end() { relaunch(intoDemo: false) }

    /// A fresh demo – the sample collection back as it was, e.g. after
    /// "Alles zurücksetzen" emptied it.
    @MainActor static func restart() { relaunch(intoDemo: true) }

    /// Part of every file name the demo suggests or writes ("Plattenregal
    /// Collection (Demo).csv"), so a folder shared with the real app never
    /// gets its files replaced by sample data.
    static var fileSuffix: String { isActive ? " (Demo)" : "" }

    /// For empty pages in the demo, where "synchronise with Discogs" doesn't apply.
    static let emptyHint = String(localized: "Die Beispielsammlung ist leer – vermutlich wurde sie zurückgesetzt. Starte die Demo neu, um sie zurückzuholen.")

    /// Set once a relaunch is under way: a second click must not start a
    /// second new instance before this one has quit.
    @MainActor private static var relaunching = false

    /// For a new app language: the same app again, a demo stays a (fresh) demo.
    @MainActor static func relaunchForLanguage() { relaunch(intoDemo: isActive, forLanguage: true) }

    @MainActor private static func relaunch(intoDemo: Bool, forLanguage: Bool = false) {
        guard !relaunching else { return }
        // Another instance (e.g. started from Xcode) would mean two apps on the
        // same database after the switch – or a demo next to it. Not guessed at.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
        guard others.isEmpty else {
            AppLog.warning("App", "Neustart \(forLanguage ? "für die Sprache" : "für die Demo") abgelehnt: eine weitere Instanz läuft (\(others.map(\.processIdentifier)))")
            let alert = NSAlert()
            alert.messageText = String(localized: "Plattenregal läuft noch ein zweites Mal")
            alert.informativeText = String(localized: "Beende zuerst die andere Plattenregal-Instanz und versuche es dann noch einmal. So sind nie zwei Instanzen auf derselben Sammlung geöffnet.")
            alert.runModal()
            return
        }
        relaunching = true
        AppLog.info("App", forLanguage ? "Neustart für die Sprache" : intoDemo ? "Demo wird gestartet (Neustart)" : "Demo wird beendet (Neustart)")
        if intoDemo { UserDefaults.standard.set(Date.now, forKey: requestKey) }
        else { UserDefaults.standard.removeObject(forKey: requestKey) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    relaunching = false
                    UserDefaults.standard.removeObject(forKey: requestKey)
                    AppLog.error("App", "Neustart \(forLanguage ? "für die Sprache" : "für die Demo") fehlgeschlagen: \(error)")
                    let alert = NSAlert()
                    if forLanguage {
                        alert.messageText = String(localized: "Plattenregal konnte nicht neu starten")
                        alert.informativeText = String(localized: "Beende die App und öffne sie wieder – dann erscheint sie in der neuen Sprache.")
                    } else if intoDemo {
                        alert.messageText = String(localized: "Die Demo konnte nicht gestartet werden")
                        alert.informativeText = String(localized: "Deine Sammlung bleibt geöffnet. Versuche es später noch einmal.")
                    } else {
                        alert.messageText = String(localized: "Plattenregal konnte nicht neu starten")
                        alert.informativeText = String(localized: "Beende die App und öffne sie wieder – dann startet sie mit deiner eigenen Sammlung. In der Demo wurde nichts gespeichert.")
                    }
                    alert.runModal()
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

/// The user defaults the app reads and writes. In the demo a separate
/// domain, so trying out settings never changes the real ones.
nonisolated enum AppDefaults {
    private static let demoSuite = "de.private.Plattenregal.demo"

    nonisolated(unsafe) static let store: UserDefaults = {
        guard DemoMode.isActive else { return .standard }
        // Never fall back to the real settings: the demo would change them.
        // (Only fails for the bundle ID or the global domain as suite name.)
        guard let demo = UserDefaults(suiteName: demoSuite) else { preconditionFailure("Demo-Einstellungen nicht verfügbar") }
        return demo
    }()

    /// The domain `store` writes to (for "Einstellungen zurücksetzen").
    static var domainName: String? { DemoMode.isActive ? demoSuite : Bundle.main.bundleIdentifier }

    /// Every demo starts with the default settings.
    fileprivate static func resetDemo() {
        store.removePersistentDomain(forName: demoSuite)
    }
}

/// Gives the demo's main window the frame `DemoMode.prepare()` stored for it
/// (the real window's, or a screenshot run's own). macOS doesn't restore
/// it by itself: the demo window always opened at its minimum size.
/// Applied once, when the window first appears; resizing afterwards is the
/// user's – and stays in the demo.
struct DemoWindowFrame: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class Probe: NSView {
        @MainActor private static var applied = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !Self.applied,
                  let saved = UserDefaults.standard.string(forKey: DemoMode.demoFrameKey),
                  var frame = DemoMode.windowRect(fromSavedFrame: saved) else { return }
            Self.applied = true
            // Never below the window's minimum size. Not fitted into the
            // screen (as `setFrame(from:)` would): screenshot runs place the
            // window mostly beside it on purpose.
            let minimum = window.frameRect(forContentRect: NSRect(origin: .zero, size: window.contentMinSize)).size
            frame.size.width = max(frame.width, minimum.width, window.minSize.width)
            frame.size.height = max(frame.height, minimum.height, window.minSize.height)
            window.setFrame(frame, display: true)
        }
    }
}

/// Shown at the top of every page while the demo runs. Each page places it
/// with its own margins, so it lines up with the covers and cards below.
struct DemoBanner: View {
    var body: some View {
        AppBanner(message: String(localized: "Demo – eine Beispielsammlung zum Ausprobieren. Ändere, was du willst: Nichts wird gespeichert, deine eigene Sammlung bleibt unberührt."),
                  kind: .info, actionTitle: String(localized: "Demo beenden"), action: { DemoMode.end() })
    }
}
