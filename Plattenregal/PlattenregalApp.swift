import SwiftUI
import SwiftData
import OSLog

@main struct PlattenregalApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    /// Another instance has the collection open; not a problem with the data.
    private let openElsewhere: Bool
    init() {
        let info = Bundle.main.infoDictionary
        // Before anything reads settings: the demo gets fresh ones of its own.
        DemoMode.prepare()
        AppLog.startSession(details: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)" + (DemoMode.isActive ? " · Demo" : ""),
                            version: "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))")
        FocusRings.disableGlobally()
        // macOS shows a glass bubble with the input source (or Caps Lock) over
        // the cursor when a text field is focused first – right over the page
        // when ⌘F reveals the search. Off for this app unless switched on in
        // macOS on purpose. Stored in the app's own domain: a registered
        // default lives only in this process, and the bubble didn't see it.
        InputSourceIndicator.disableForApp()
        // Before the first window, so it never flashes in the wrong mode –
        // also the error window, which has no `appAppearance()`.
        AppPreferences.shared.applyAppearance()
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
            startupError = nil; openElsewhere = false
            if let context = container?.mainContext {
                let copies = (try? context.fetchCount(FetchDescriptor<RecordCopy>())) ?? -1
                let wants = (try? context.fetchCount(FetchDescriptor<WantlistEntry>())) ?? -1
                AppLog.info("Datenbank", "Geöffnet: \(copies) Exemplare, \(wants) Wantlist-Einträge")
            }
            // A first backup for layouts that haven't changed since the feature arrived.
            if let container { ShelfAutoBackup.shared.scheduleBackup(of: container) }
        }
        catch StorageError.alreadyOpen {
            container = nil; startupError = nil; openElsewhere = true
            let own = ProcessInfo.processInfo.processIdentifier
            if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .first(where: { $0.processIdentifier != own && !$0.isTerminated }) {
                AppLog.handMarkerBack(to: other.processIdentifier)
            }
        }
        catch {
            container = nil; startupError = error.localizedDescription; openElsewhere = false
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
        WindowGroup {
            if let container, Self.previewsSettings {
                AppSettingsView().appAppearance().modelContainer(container).defaultAppStorage(AppDefaults.store)
            } else if let container {
                RootView().appAppearance().modelContainer(container).defaultAppStorage(AppDefaults.store)
                    .frame(minWidth: 1050, minHeight: 720)
            } else {
                if DemoMode.isActive {
                    ContentUnavailableView {
                        Label("Die Demo konnte nicht gestartet werden", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("Die Beispielsammlung ließ sich nicht aufbauen. Deine eigene Sammlung ist davon nicht betroffen.")
                        if let startupError { Text("Technische Details: \(startupError)").font(.caption).foregroundStyle(.secondary) }
                    } actions: {
                        Button("Demo beenden") { DemoMode.end() }
                    }.padding().frame(width: 650, height: 320)
                } else if openElsewhere {
                    ContentUnavailableView {
                        Label("Plattenregal ist bereits geöffnet", systemImage: "macwindow.on.rectangle")
                    } description: {
                        Text(StorageError.alreadyOpen.errorDescription ?? "")
                    } actions: {
                        Button("Beenden") { NSApp.terminate(nil) }
                    }.padding().frame(width: 650, height: 320)
                } else {
                ContentUnavailableView {
                    Label("Sammlung konnte nicht geöffnet werden", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Plattenregal konnte deine gespeicherte Sammlung beim Start nicht laden. Deine Daten sind noch da – es wurde nichts gelöscht.")
                    Text("Beende die App und starte sie noch einmal. Klappt es dann immer noch nicht, sichere zuerst den Ordner ~/Library/Containers/de.private.Plattenregal, bevor du etwas anderes versuchst.")
                    // For whoever helps: the system's own wording.
                    if let startupError { Text("Technische Details: \(startupError)").font(.caption).foregroundStyle(.secondary) }
                } actions: {
                    // What happened at launch is in the protocol – that file helps whoever looks into it.
                    if let log = AppLog.fileURL {
                        Button("Protokoll im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([log]) }
                    }
                }.padding().frame(width: 650, height: 360)
                }
            }
        }
        .defaultSize(width: 1300, height: 850)
        .commands {
            CommandGroup(after: .appSettings) {
                if DemoMode.isActive {
                    Button("Demo beenden") { DemoMode.end() }
                    Button("Demo neu starten") { DemoMode.restart() }
                } else {
                    Button("Demo starten …") { DemoMode.confirmStart() }
                }
            }
        }
        Settings {
            if let container {
                AppSettingsView().appAppearance().modelContainer(container).defaultAppStorage(AppDefaults.store)
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
