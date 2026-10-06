import AppKit
import Foundation
import SwiftUI

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
/// - Discogs is switched off and the keychain is never touched.
/// Only the protocol is shared, marked "Demo" at the start of the session.
nonisolated enum DemoMode {
    static let argument = "--demo"

    /// `--statistics-demo` (Debug) opens the same demo on the statistics page.
    static let isActive: Bool = ProcessInfo.processInfo.arguments.contains { $0 == argument || $0 == "--statistics-demo" }
        || takeLaunchRequest()

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
    /// (`--screenshots`), e.g. the pictures of the tour; the services keep
    /// checking `isActive`, so nothing is synced, exported or backed up.
    static var showsBanner: Bool {
        #if DEBUG
        isActive && !ProcessInfo.processInfo.arguments.contains("--screenshots")
        #else
        isActive
        #endif
    }

    /// Backups and covers of the demo; emptied when a demo starts.
    static let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Plattenregal-Demo", isDirectory: true)

    /// Once at launch, before anything reads settings or folders.
    static func prepare() {
        guard isActive else { return }
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        AppDefaults.resetDemo()
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

/// Shown at the top of every page while the demo runs. Each page places it
/// with its own margins, so it lines up with the covers and cards below.
struct DemoBanner: View {
    var body: some View {
        AppBanner(message: String(localized: "Demo – eine Beispielsammlung zum Ausprobieren. Ändere, was du willst: Nichts wird gespeichert, deine eigene Sammlung bleibt unberührt."),
                  kind: .info, actionTitle: String(localized: "Demo beenden"), action: { DemoMode.end() })
    }
}
