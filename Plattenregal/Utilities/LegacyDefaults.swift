import Foundation

/// Settings that earlier versions wrote and nothing reads any more, removed
/// once at launch – so they don't pile up on Macs that ran older versions.
/// Only keys this app wrote itself and current code can never write again
/// are listed. When a setting is dropped, its key goes in here too.
nonisolated enum LegacyDefaults {
    /// Single keys of dropped settings.
    static let obsoleteKeys: Set<String> = [
        // The "Vermisst" column, gone since 12.10.2026.
        "missingColumnCollapsed",
    ]

    /// Key beginnings of whole families.
    static let obsoletePrefixes = [
        // Window sizes and sidebar widths from the time of `WindowGroup`:
        // macOS named them after the window's view types, so every build
        // with changed types left a new one (hundreds). The window is now a
        // `Window` with a fixed id ("NSWindow Frame main" / "… demo").
        "NSWindow Frame SwiftUI.WindowGroup<",
        "NSSplitView Subview Frames SwiftUI.WindowGroup<",
        // A one-time shelf name migration, removed 25.09.2026 – one flag per
        // database file, test databases included.
        "LibraryStorage.legacyShelfNameMigratedV5",
    ]

    static func isObsolete(_ key: String) -> Bool {
        obsoleteKeys.contains(key) || obsoletePrefixes.contains { key.hasPrefix($0) }
    }

    /// Removes the obsolete keys stored in `domain` and returns how many.
    /// Reads only that domain, never the global or registered defaults.
    @discardableResult
    static func removeObsolete(from defaults: UserDefaults = .standard,
                               domain: String? = Bundle.main.bundleIdentifier) -> Int {
        guard let domain, let stored = defaults.persistentDomain(forName: domain) else { return 0 }
        let obsolete = stored.keys.filter(isObsolete)
        for key in obsolete { defaults.removeObject(forKey: key) }
        return obsolete.count
    }
}
