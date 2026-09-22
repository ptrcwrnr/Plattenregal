import SwiftUI
import SwiftData
import OSLog

@main struct PlattenregalApp: App {
    private let container: ModelContainer?
    private let startupError: String?
    init() {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--statistics-demo") {
                container = PreviewData.statisticsContainer
            } else if ProcessInfo.processInfo.arguments.contains("--demo") {
                container = PreviewData.container
            } else {
                container = try LibraryStorage.makeContainer(inMemory: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
            }
            #else
            container = try LibraryStorage.makeContainer()
            #endif
            startupError = nil
        }
        catch {
            container = nil; startupError = error.localizedDescription
            Logger(subsystem: "de.private.Plattenregal", category: "Storage").error("Store initialization failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    var body: some Scene {
        WindowGroup {
            if let container {
                RootView().appAppearance().modelContainer(container).frame(minWidth: 1050, minHeight: 720)
            } else {
                ContentUnavailableView {
                    Label("Sammlung konnte nicht geöffnet werden", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(startupError ?? "Unbekannter Datenbankfehler")
                    Text("Die vorhandene Datenbank wurde nicht gelöscht. Bitte sichere sie, bevor du weitere Schritte unternimmst.")
                }.padding().frame(width: 650, height: 320)
            }
        }.defaultSize(width: 1300, height: 850)
        Settings {
            if let container { AppSettingsView().appAppearance().modelContainer(container) }
        }
    }
}
