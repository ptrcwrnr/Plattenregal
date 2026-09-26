import AppKit
import SwiftUI

/// The page the main window opens with.
enum StartPage: String, CaseIterable, Identifiable {
    case collection, wantlist, shelf, statistics
    var id: Self { self }
    var title: String {
        switch self {
        case .collection: "Collection"
        case .wantlist: "Wantlist"
        case .statistics: "Statistik"
        case .shelf: "Regal"
        }
    }
    var destination: Destination {
        switch self {
        case .collection: .collection
        case .wantlist: .wantlist
        case .statistics: .statistics
        case .shelf: .shelf
        }
    }
}

/// Grid or list for the collection and the wantlist. Stored via
/// `@AppStorage`; an unknown stored value falls back to the default.
enum OverviewLayout: String, CaseIterable, Identifiable {
    case grid, list
    var id: Self { self }
    var title: String { self == .grid ? "Raster" : "Liste" }
    var systemImage: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// Order of the collection and wantlist. Only the alphabetical one has the
/// letter index at the edge; the random one is shuffled anew on each launch.
enum OverviewOrder: String, CaseIterable, Identifiable {
    case alphabetical, random, recent
    var id: Self { self }
    var title: String {
        switch self {
        case .alphabetical: "Alphabetisch"
        case .random: "Zufällig"
        case .recent: "Neueste zuerst"
        }
    }
    var hint: String {
        switch self {
        case .alphabetical: "Nach Interpret, mit dem Alphabet am Rand."
        case .random: "Bei jedem Start neu gemischt – so fällt immer mal wieder etwas anderes ins Auge."
        case .recent: "Zuletzt bei Discogs hinzugefügt zuerst."
        }
    }

    /// New with each launch and each switch to "Zufällig" in the settings;
    /// in between the random order stays put. One per page (its storage key):
    /// shuffling the wantlist must not reorder the collection on its next sync.
    @MainActor private static var shuffleSeeds: [String: UInt64] = [:]
    @MainActor static func reshuffle(_ scope: String) { shuffleSeeds[scope] = .random(in: .min ... .max) }
    /// Position of `key` in the current random order of `scope`.
    @MainActor static func shuffleRank(_ key: some Hashable, scope: String) -> Int {
        let seed = shuffleSeeds[scope] ?? {
            let seed = UInt64.random(in: .min ... .max)
            shuffleSeeds[scope] = seed
            return seed
        }()
        var hasher = Hasher()
        hasher.combine(seed)
        hasher.combine(key)
        return hasher.finalize()
    }

    /// `items` in this order. `key` identifies an item for the shuffle
    /// (copies of one release share it, so they stay one tile); `scope` names
    /// the page, see `shuffleSeeds`.
    @MainActor func apply<T, K: Hashable>(_ items: [T], scope: String, alphabetical: ([T]) -> [T], key: (T) -> K, added: (T) -> Date?) -> [T] {
        switch self {
        case .alphabetical:
            return alphabetical(items)
        case .random:
            let ranks = items.map { Self.shuffleRank(key($0), scope: scope) }
            return zip(ranks, items).sorted { $0.0 < $1.0 }.map(\.1)
        case .recent:
            // Undated ones last, in alphabetical order.
            let sorted = alphabetical(items)
            let dated = sorted.enumerated().map { (added($0.element), $0.offset, $0.element) }
            return dated.sorted { lhs, rhs in
                switch (lhs.0, rhs.0) {
                case let (l?, r?) where l != r: return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.1 < rhs.1
                }
            }.map(\.2)
        }
    }
}

/// Keys and limits of the `@AppStorage` display settings, shared by the
/// settings and the pages that read them.
enum DisplaySettings {
    static let collectionLayoutKey = "collectionLayout"
    static let wantlistLayoutKey = "wantlistLayout"
    static let collectionOrderKey = "collectionOrder"
    static let wantlistOrderKey = "wantlistOrder"
    static let coverSizeKey = "coverSize"
    static let statisticsOrderKey = "statisticsSectionOrder"

    static let defaultCoverSize = 155.0
    static let coverSizeRange = 120.0...220.0

    /// The stored minimum cover size, kept within the slider's range – a
    /// value from an older version or `defaults write` (NaN, 0, negative)
    /// would otherwise break the column count.
    static func coverSize(_ stored: Double) -> Double {
        guard stored.isFinite else { return defaultCoverSize }
        return min(max(stored, coverSizeRange.lowerBound), coverSizeRange.upperBound)
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }
    /// Always shown, so the row keeps its height when switching.
    var hint: String {
        switch self {
        case .system: "Folgt der Einstellung von macOS."
        case .light: "Immer hell, unabhängig von macOS."
        case .dark: "Immer dunkel, unabhängig von macOS."
        }
    }
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The app's own accent, or the one set in the macOS settings.
enum AccentChoice: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "Wie macOS"
        case .blue: "Blau"
        case .purple: "Lila"
        case .pink: "Pink"
        case .red: "Rot"
        case .orange: "Orange"
        case .yellow: "Gold"
        case .green: "Grün"
        case .graphite: "Graphit"
        }
    }
    var color: Color {
        switch self {
        case .system: .accentColor
        case .blue: .blue
        case .purple: .purple
        // The accent carries white text (selected segments, primary buttons).
        // SwiftUI's pink is almost the red, and its orange, yellow, green and
        // (in dark mode) gray are too light for white text. These keep a
        // contrast of at least 3:1 in both modes (see AccentContrastTests).
        case .pink: Color(red: 0.97, green: 0.31, blue: 0.62)
        case .red: .red
        case .orange: Color(red: 0.87, green: 0.44, blue: 0.0)
        case .yellow: Color(red: 0.74, green: 0.51, blue: 0.0)
        case .green: Color(red: 0.16, green: 0.62, blue: 0.27)
        case .graphite: Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }
}

/// The faint glow behind every page, from the top of the window: off or one
/// of the accent colors. Same count as `AccentChoice`, so both rows of
/// swatches line up with "Aus" under "Wie macOS".
enum AmbientChoice: String, CaseIterable, Identifiable {
    case off, blue, purple, pink, red, orange, yellow, green, graphite
    var id: Self { self }
    var title: String { self == .off ? "Aus" : AccentChoice(rawValue: rawValue)?.title ?? rawValue }
    /// nil when off.
    var color: Color? { AccentChoice(rawValue: rawValue)?.color }
}

/// Settings that change the whole app at once. Observable, so every view
/// reading `AppStyle.accent` redraws when the accent changes; stored in
/// the same user defaults as the `@AppStorage` settings.
@Observable final class AppPreferences {
    static let shared = AppPreferences()

    enum Key {
        static let startPage = "startPage"
        static let appearance = "appearanceMode"
        static let accent = "accentChoice"
        static let ambient = "ambientChoice"
    }

    var startPage: StartPage { didSet { store(startPage.rawValue, Key.startPage) } }
    var appearance: AppearanceMode { didSet { store(appearance.rawValue, Key.appearance); applyAppearance() } }
    var accent: AccentChoice { didSet { store(accent.rawValue, Key.accent) } }
    var ambient: AmbientChoice { didSet { store(ambient.rawValue, Key.ambient) } }

    private init() {
        let defaults = AppDefaults.store
        startPage = defaults.string(forKey: Key.startPage).flatMap(StartPage.init) ?? .collection
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceMode.init) ?? .system
        accent = defaults.string(forKey: Key.accent).flatMap(AccentChoice.init) ?? .system
        ambient = defaults.string(forKey: Key.ambient).flatMap(AmbientChoice.init) ?? .blue
    }

    /// Light or dark for every window, including sheets and the settings.
    func applyAppearance() {
        NSApplication.shared.appearance = appearance.appearance
    }

    /// Back to the defaults (used by "Einstellungen zurücksetzen").
    func reset() {
        startPage = .collection
        appearance = .system
        accent = .system
        ambient = .blue
    }

    private func store(_ value: String, _ key: String) {
        AppDefaults.store.set(value, forKey: key)
    }
}
