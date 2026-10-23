import SwiftUI

/// The keyboard shortcuts, for the list under Einstellungen → Tastenkürzel. The
/// app-wide ones are registered with these values (see `GlobalShortcuts`), so
/// the list can't drift from what the keys do.
enum AppShortcuts {
    static let syncAll = KeyboardShortcut("r", modifiers: [.command, .option])
    static let cancelSync = KeyboardShortcut(".", modifiers: .command)
    static let grid = KeyboardShortcut("1", modifiers: [.command, .option])
    static let list = KeyboardShortcut("2", modifiers: [.command, .option])
    static let largerCovers = KeyboardShortcut("+", modifiers: .command)
    static let smallerCovers = KeyboardShortcut("-", modifiers: .command)
    static let defaultCovers = KeyboardShortcut("0", modifiers: .command)
    static let shelfHistory = KeyboardShortcut("y", modifiers: .command)

    /// A tooltip that names its shortcut, the same way everywhere:
    /// „Synchronisieren (⌘R)“.
    static func help(_ title: String, keys: String) -> String { "\(title) (\(keys))" }

    struct Entry: Identifiable {
        let keys: String
        let title: String
        var id: String { keys }
    }
    struct Group: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    static var groups: [Group] {
        [
            Group(title: String(localized: "Überall"), entries: [
                Entry(keys: "⌘1 – ⌘4", title: String(localized: "Collection, Wantlist, Regal, Statistik")),
                Entry(keys: "⌘F", title: String(localized: "Suchen")),
                Entry(keys: "⌘R", title: String(localized: "Seite aktualisieren")),
                Entry(keys: "⌥⌘R", title: String(localized: "Alles mit Discogs synchronisieren")),
                Entry(keys: "⌘.", title: String(localized: "Synchronisierung abbrechen")),
                Entry(keys: "⌘,", title: String(localized: "Einstellungen")),
            ]),
            Group(title: String(localized: "Collection und Wantlist"), entries: [
                Entry(keys: "⌥⌘1 / ⌥⌘2", title: String(localized: "Raster / Liste")),
                Entry(keys: "⌘+ / ⌘−", title: String(localized: "Cover größer / kleiner")),
                Entry(keys: "⌘0", title: String(localized: "Cover in Standardgröße")),
                Entry(keys: "esc", title: String(localized: "Suche leeren, dann schließen")),
            ]),
            Group(title: String(localized: "Regal"), entries: [
                Entry(keys: "⌘← / ⌘→", title: String(localized: "Vorheriges / nächstes Regal")),
                Entry(keys: "⌘Z", title: String(localized: "Herausnehmen rückgängig machen")),
                Entry(keys: "⌘Y", title: String(localized: "Verlauf: Einsortiertes und Verschobenes rückgängig machen")),
            ]),
            Group(title: String(localized: "Statistik"), entries: [
                Entry(keys: "⇧⌘R", title: String(localized: "Zufallsfund: neue Platte ziehen")),
            ]),
            Group(title: String(localized: "Einstellungen"), entries: [
                Entry(keys: "esc / ⌘W", title: String(localized: "Einstellungen schließen")),
            ]),
            Group(title: String(localized: "Einstellungen → Regal"), entries: [
                Entry(keys: "← / →", title: String(localized: "Zwischen den Regalen wechseln")),
                Entry(keys: String(localized: "Leertaste"), title: String(localized: "Regal aktivieren oder deaktivieren")),
            ]),
        ]
    }
}
