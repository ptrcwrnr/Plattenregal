import SwiftUI

/// The page the main window opens with.
enum StartPage: String, CaseIterable, Identifiable {
    case collection, wantlist, shelf, statistics
    var id: Self { self }
    var title: String {
        switch self {
        case .collection: String(localized: "Collection")
        case .wantlist: String(localized: "Wantlist")
        case .statistics: String(localized: "Statistik")
        case .shelf: String(localized: "Regal")
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
    var title: String { self == .grid ? String(localized: "Raster") : String(localized: "Liste") }
    var systemImage: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// Order of the collection and wantlist. The random one is shuffled anew on
/// each launch.
enum OverviewOrder: String, CaseIterable, Identifiable {
    case alphabetical, random, recent
    var id: Self { self }
    var title: String {
        switch self {
        case .alphabetical: String(localized: "Alphabetisch")
        case .random: String(localized: "Zufällig")
        case .recent: String(localized: "Neueste zuerst")
        }
    }
    var hint: String {
        switch self {
        case .alphabetical: String(localized: "Nach Interpret, mit dem Alphabet am Rand.")
        case .random: String(localized: "Bei jedem Start neu gemischt – so fällt immer mal wieder etwas anderes ins Auge.")
        case .recent: String(localized: "Zuletzt bei Discogs hinzugefügt zuerst.")
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
    /// "Gesucht" on the shelf page: marking records not found while sorting
    /// in; the settings list them. Off hides the marks; they are kept.
    static let missingListKey = "missingListEnabled"
    /// "Verkauf": marking records to be sold some day; the settings list
    /// them. Off hides the marks and the menu entries; the marks are kept.
    static let saleListKey = "saleListEnabled"
    static var saleListEnabled: Bool { AppDefaults.store.object(forKey: saleListKey) as? Bool ?? true }

    /// Klein, Mittel, Groß: the minimum cover width in the grid. The
    /// columns always fill the width, so a size only shows once the column
    /// count changes; the old 5-pt slider changed nothing on every second
    /// step. These are far enough apart that each one changes the count at
    /// usual window widths.
    static let coverSizes: [Double] = [125, 155, 195]
    static let defaultCoverSize = 155.0

    /// The stored minimum cover size as one of `coverSizes` – the nearest,
    /// for a value from the old slider; a broken one (NaN, `defaults
    /// write`) is the default.
    static func coverSize(_ stored: Double) -> Double {
        guard stored.isFinite else { return defaultCoverSize }
        return coverSizes.min { abs($0 - stored) < abs($1 - stored) } ?? defaultCoverSize
    }

    /// The size `offset` steps from `stored`, stopping at the ends (⌘+ / ⌘−).
    static func coverSize(_ stored: Double, offset: Int) -> Double {
        let index = coverSizes.firstIndex(of: coverSize(stored)) ?? 1
        return coverSizes[min(max(index + offset, 0), coverSizes.count - 1)]
    }

    static func coverSizeName(_ size: Double) -> String {
        switch coverSizes.firstIndex(of: coverSize(size)) {
        case 0: String(localized: "Klein", comment: "Covergröße")
        case 2: String(localized: "Groß", comment: "Covergröße")
        default: String(localized: "Mittel", comment: "Covergröße")
        }
    }
}
