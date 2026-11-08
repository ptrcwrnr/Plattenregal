import SwiftUI
import SwiftData

/// Closing the last window is handled by `AppLifecycle`, not by AppKit: into
/// the background while that is switched on (the record in the menu bar brings
/// the window back), else it quits like ⌘Q. AppKit's own rule would also
/// count the search panel and miss the background.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    /// The record in the menu bar and ⌥ Leertaste (see `ShelfQuickSearch`) –
    /// not in test runs, whose store is empty and whose app must not take
    /// the shortcut from a running Plattenregal.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        // Only here: macOS hands over the open event while launching finishes.
        let atLogin = AppLifecycle.launchedAsLoginItem
        ShelfQuickSearch.shared.start()
        AppLifecycle.shared.start(launchedAtLogin: atLogin)
        // Once a day, quietly; not in the demo or preview starts.
        UpdateChecker.shared.startAutomaticChecks()
        // The widget „Platte des Tages“ shows the user's own collection,
        // never the demo's.
        if let container = ShelfQuickSearch.shared.container, !DemoMode.isActive {
            RecordOfTheDayPublisher.shared.start(container: container)
        }
        #if DEBUG
        // --preview-update=…: the update window with a given answer (see `UpdateChecker.showPreview`).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { UpdateChecker.shared.showPreview() }
        // --preview-widget-link=Artist: a click on the widget showing that
        // artist's record, while launching – as when the click launches the app.
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-widget-link=") }),
           let context = ShelfQuickSearch.shared.container?.mainContext {
            let artist = String(raw.dropFirst("--preview-widget-link=".count))
            let copies = (try? context.fetch(RecordCopy.fetchingReleases())) ?? []
            if let copy = copies.first(where: { $0.release?.artist == artist }) {
                RecordOfTheDayPublisher.open(RecordOfTheDay.link(to: copy.id))
            }
        }
        #endif
    }
    /// A click on the widget „Platte des Tages“ (`plattenregal://platte/…`).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { RecordOfTheDayPublisher.open(url) }
    }
    /// The Dock's „Beenden“, a script or logout – see `AppLifecycle.terminateReply`.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLifecycle.shared.terminateReply()
    }
    /// Opened again from the Finder or Launchpad while running in the
    /// background: the Dock icon comes back before SwiftUI opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        AppLifecycle.shared.leaveBackground()
        return true
    }
}

@main struct PlattenregalApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private let container: ModelContainer?
    /// Another instance has the collection open; not a problem with the data.
    private let openElsewhere: Bool
    init() {
        let info = Bundle.main.infoDictionary
        // Before anything reads settings: the demo gets fresh ones of its own.
        DemoMode.prepare()
        AppLog.startSession(details: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)" + (DemoMode.isActive ? " · Demo" : "")
                                + (AppPreferences.shared.signatureDesign == .liquidGlass ? "" : " · Design \(AppPreferences.shared.signatureDesign.logName)"),
                            version: "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))")
        FocusRings.disableGlobally()
        // Settings only older versions wrote (window sizes of every former
        // build, dropped options); hundreds had piled up.
        let obsolete = LegacyDefaults.removeObsolete()
        if obsolete > 0 { AppLog.info("Einstellungen", "\(obsolete) veraltete Einträge früherer Versionen entfernt") }
        #if DEBUG
        DebugSnapshot.scheduleIfRequested()
        #endif
        // macOS shows a glass bubble with the input source (or Caps Lock) over
        // the cursor when a text field is focused first – right over the page
        // when ⌘F reveals the search. Off for this app unless switched on in
        // macOS on purpose. Stored in the app's own domain: a registered
        // default lives only in this process, and the bubble didn't see it.
        InputSourceIndicator.disableForApp()
        // Before the first window, so it never flashes in the wrong mode –
        // also the error window, which has no `appAppearance()`.
        AppPreferences.shared.applyAppearance()
        // The chosen icon from the start, so the Dock never shows the standard
        // first; the link to the Dock plug-in listens before it speaks.
        DockTileLink.shared.start()
        AppPreferences.shared.dockIcon.apply()
        do {
            if DemoMode.isActive {
                // Sample collection in memory; the real database stays closed.
                container = try DemoData.makeContainer()
            } else {
                #if DEBUG
                container = try LibraryStorage.makeContainer(inMemory: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
                #else
                container = try LibraryStorage.makeContainer()
                #endif
            }
            openElsewhere = false
            if let context = container?.mainContext {
                let copies = (try? context.fetchCount(FetchDescriptor<RecordCopy>())) ?? -1
                let wants = (try? context.fetchCount(FetchDescriptor<WantlistEntry>())) ?? -1
                AppLog.info("Datenbank", "Geöffnet: \(copies) Exemplare, \(wants) Wantlist-Einträge")
            }
            // The search in the menu bar reads this store; it starts once launching is done.
            ShelfQuickSearch.shared.container = container
            // A first backup for layouts that haven't changed since the feature arrived.
            if let container { ShelfAutoBackup.shared.scheduleBackup(of: container) }
            // Offers the collection to paired Apple TVs – never the demo's, and
            // not from a test run, whose in-memory store would answer in the
            // real Mac's name.
            // Switched off for now (`AppleTVLink.isAvailable`): not even made.
            if AppleTVLink.isAvailable, let container, !DemoMode.isActive, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                AppleTVLink.shared.attach(container)
            }
        }
        catch StorageError.alreadyOpen {
            container = nil; openElsewhere = true
            let own = ProcessInfo.processInfo.processIdentifier
            if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .first(where: { $0.processIdentifier != own && !$0.isTerminated }) {
                AppLog.handMarkerBack(to: other.processIdentifier)
            }
        }
        catch {
            container = nil; openElsewhere = false
            AppLog.error("Datenbank", "Öffnen fehlgeschlagen, App zeigt die Fehlerseite: \(error)")
        }
    }
    /// Debug only: the main window shows the settings (`--settings-tab=…`, with a demo store).
    private static var previewsSettings: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--settings-tab=") }
        #else
        false
        #endif
    }
    var body: some Scene {
        // One main window: a second one (⌘N) would load and compute every
        // page again. `Window` drops "Neues Fenster". Closed as the last
        // window, the app goes to the background or quits (`AppLifecycle`);
        // otherwise it comes back from the Fenster menu.
        Window("Plattenregal", id: DemoMode.mainWindowID) {
            if let container, Self.previewsSettings {
                AppSettingsView().appAppearance().modelContainer(container).defaultAppStorage(AppDefaults.store)
            } else if let container {
                ReleasedInBackground {
                    RootView().appAppearance().modelContainer(container).defaultAppStorage(AppDefaults.store)
                }
                .frame(minWidth: 1050, minHeight: 720)
                // The demo opens as large as the real window (see `DemoWindowFrame`).
                .background { if DemoMode.isActive { DemoWindowFrame() } }
            } else {
                if DemoMode.isActive {
                    ContentUnavailableView {
                        Label("Die Demo konnte nicht gestartet werden", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Die Beispielsammlung ließ sich nicht aufbauen. Deine eigene Sammlung ist davon nicht betroffen.")
                        Text("Die technischen Details stehen im Protokoll.").font(.caption).foregroundStyle(.secondary)
                    } actions: {
                        Button("Demo beenden") { DemoMode.end() }.appGlassButton()
                    }.padding().frame(width: 650, height: 320)
                } else if openElsewhere {
                    ContentUnavailableView {
                        Label("Plattenregal ist bereits geöffnet", systemImage: "macwindow.on.rectangle")
                    } description: {
                        Text(StorageError.alreadyOpen.errorDescription ?? "")
                    } actions: {
                        Button("Beenden") { NSApp.terminate(nil) }.appGlassButton()
                    }.padding().frame(width: 650, height: 320)
                } else {
                ContentUnavailableView {
                    Label("Sammlung konnte nicht geöffnet werden", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Plattenregal konnte deine gespeicherte Sammlung beim Start nicht laden. Die App hat nichts gelöscht oder zurückgesetzt.")
                    Text("Beende die App und starte sie noch einmal. Klappt es dann immer noch nicht, sichere zuerst den Ordner ~/Library/Containers/de.private.Plattenregal, bevor du etwas anderes versuchst.")
                    // Keep system wording in the protocol, outside the readable explanation.
                    Text("Die technischen Details stehen im Protokoll.").font(.caption).foregroundStyle(.secondary)
                } actions: {
                    // What happened at launch is in the protocol – that file helps whoever looks into it.
                    if let log = AppLog.fileURL {
                        Button("Protokoll im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([log]) }.appGlassButton()
                    }
                }.padding().frame(width: 650, height: 360)
                }
            }
        }
        // Whole window incl. toolbar. The minimum height is 772 pt (720 pt
        // content below the 52 pt toolbar).
        .defaultSize(width: 1200, height: 780)
        // With --settings-tab the window takes the settings' own size, so
        // screenshots look like the settings window.
        .windowResizability(Self.previewsSettings ? .contentSize : .automatic)
        // No right-click menu on the toolbar ("Symbol und Text" …): its
        // layout is fixed.
        .windowToolbarLabelStyle(fixed: .iconOnly)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
                UpdateCommand()
            }
            CommandGroup(replacing: .appTermination) { QuitCommands() }
            CommandGroup(replacing: .help) { HelpCommands() }
            CommandGroup(after: .appSettings) {
                if DemoMode.isActive {
                    Button("Demo beenden") { DemoMode.end() }
                    Button("Demo neu starten") { DemoMode.restart() }
                } else {
                    Button("Demo starten") { DemoMode.confirmStart() }
                }
            }
        }
        Window("Über Plattenregal", id: AboutView.windowID) {
            AboutView().appAppearance().windowMinimizeBehavior(.disabled)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
        // Not a document: no entry in the Fenster menu.
        .commandsRemoved()
        Window("Softwareaktualisierung", id: UpdateView.windowID) {
            UpdateView().appAppearance().windowMinimizeBehavior(.disabled)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
        .commandsRemoved()
        Settings {
            if let container {
                ReleasedInBackground {
                    AppSettingsView().appAppearance().modelContainer(container).defaultAppStorage(AppDefaults.store)
                        .closesOnClickElsewhere()
                }
            } else {
                // Same situation the main window explains; don't open an empty window.
                ContentUnavailableView("Einstellungen nicht verfügbar", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(DemoMode.isActive
                        ? "Die Demo konnte nicht gestartet werden. Über „Plattenregal → Demo beenden“ geht es zurück zu deiner Sammlung."
                        : openElsewhere
                        ? "Plattenregal ist bereits in einer anderen Instanz geöffnet. Beende diese hier und nutze die andere."
                        : "Plattenregal konnte deine Sammlung beim Start nicht laden. Beende die App und starte sie noch einmal."))
                    .padding().frame(width: 420, height: 240)
            }
        }
    }
}

/// A closed SwiftUI window keeps its whole content – views, layers, covers –
/// and only leaves the screen. In the background (`AppLifecycle`) nothing
/// shows it, so it is dropped and built anew when a window opens again, as
/// after a launch. Long-running work (sync, tracklists, export, backups)
/// lives in services, not in these views, and goes on.
private struct ReleasedInBackground<Content: View>: View {
    @State private var lifecycle = AppLifecycle.shared
    @Environment(\.openWindow) private var openWindow
    @ViewBuilder let content: Content
    var body: some View {
        Group {
            if lifecycle.isInBackground { Color.clear } else { content }
        }
        // The record's menu opens the main window with this. Set
        // here, not in `RootView`: launched at login straight into the
        // background, the window shows only `Color.clear` before it closes,
        // and `RootView` would never have handed them over.
        .onAppear {
            let search = ShelfQuickSearch.shared
            search.openMainWindow = { [openWindow] in openWindow(id: DemoMode.mainWindowID) }
            UpdateChecker.shared.openWindow = { [openWindow] in openWindow(id: UpdateView.windowID) }
        }
    }
}

/// ⌘Q keeps Plattenregal running with only the record in the menu bar while
/// that is switched on (see `AppLifecycle`); ⌥⌘Q quits completely then.
private struct QuitCommands: View {
    @State private var lifecycle = AppLifecycle.shared
    var body: some View {
        Button("Plattenregal beenden") { lifecycle.quitRequested() }
            .keyboardShortcut("q")
        if lifecycle.keepsRunning {
            Button("Plattenregal ganz beenden") { lifecycle.quitCompletely() }
                .keyboardShortcut("q", modifiers: [.command, .option])
        }
    }
}
