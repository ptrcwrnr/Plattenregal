import AppKit
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

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Hell")
        case .dark: String(localized: "Dunkel")
        }
    }
    /// Always shown, so the row keeps its height when switching.
    var hint: String {
        switch self {
        case .system: String(localized: "Folgt der Einstellung von macOS.")
        case .light: String(localized: "Immer hell, unabhängig von macOS.")
        case .dark: String(localized: "Immer dunkel, unabhängig von macOS.")
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
        case .system: String(localized: "System")
        case .blue: String(localized: "Blau")
        case .purple: String(localized: "Lila")
        case .pink: String(localized: "Pink")
        case .red: String(localized: "Rot")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Gold")
        case .green: String(localized: "Grün")
        case .graphite: String(localized: "Graphit")
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
/// swatches line up with "Aus" under "System".
enum AmbientChoice: String, CaseIterable, Identifiable {
    case off, blue, purple, pink, red, orange, yellow, green, graphite
    var id: Self { self }
    var title: String { self == .off ? String(localized: "Aus") : AccentChoice(rawValue: rawValue)?.title ?? rawValue }
    /// nil when off.
    var color: Color? { AccentChoice(rawValue: rawValue)?.color }
}

/// The complete designs. The appearance settings (mode, accent, ambient)
/// stay stored independently, so returning to Modern restores them exactly.
/// The stored values are those of the first names: "none" from when Modern
/// (Liquid Glass) was the only, unnamed design, "atelier" for Klassisch.
enum SignatureDesign: String, CaseIterable, Identifiable {
    case liquidGlass = "none", atelier
    var id: Self { self }
    var title: String {
        switch self {
        case .liquidGlass: String(localized: "Modern")
        case .atelier: String(localized: "Klassisch")
        }
    }
    /// Accent and ambient color only exist in Modern; Klassisch brings its own.
    var usesColorChoices: Bool { self == .liquidGlass }
    /// Not translated, so the protocol reads the same in every language.
    var logName: String {
        switch self {
        case .liquidGlass: "Modern"
        case .atelier: "Klassisch"
        }
    }
}

/// The language of the app. `system` follows macOS (where Plattenregal can
/// also get its own language under Language & Region); the others override it
/// for this app only. Stored where macOS looks for it, so it applies from the
/// next launch on – menus and system panels included.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, german = "de", english = "en"
    var id: Self { self }
    var title: String {
        switch self {
        case .system: String(localized: "System")
        // Each in its own language, so it can be found whatever is shown.
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    private static let key = "AppleLanguages"

    /// The language set for this app – not the list macOS has for all apps.
    /// Always in the real defaults: the language is the same in the demo.
    static var stored: AppLanguage {
        let list = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key] as? [String]
        return list?.first.flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? .system
    }

    static func store(_ language: AppLanguage) {
        if language == .system { UserDefaults.standard.removeObject(forKey: key) }
        else { UserDefaults.standard.set([language.rawValue], forKey: key) }
    }
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
        static let signatureDesign = "signatureDesign"
    }

    private let defaults: UserDefaults
    /// The choice this launch was started with.
    private let languageAtLaunch = AppLanguage.stored

    var startPage: StartPage { didSet { store(startPage.rawValue, Key.startPage) } }
    var appearance: AppearanceMode { didSet { store(appearance.rawValue, Key.appearance); applyAppearance() } }
    var accent: AccentChoice { didSet { store(accent.rawValue, Key.accent) } }
    var ambient: AmbientChoice { didSet { store(ambient.rawValue, Key.ambient) } }
    var signatureDesign: SignatureDesign { didSet { store(signatureDesign.rawValue, Key.signatureDesign) } }
    var language: AppLanguage { didSet { AppLanguage.store(language) } }
    /// Whether the chosen language shows differently from this launch – a
    /// restart is only worth it then: on a German Mac, "System" and
    /// "Deutsch" look the same.
    var languageNeedsRestart: Bool {
        guard language != languageAtLaunch else { return false }
        let available = Bundle.main.localizations.filter { $0 != "Base" }
        let next = Bundle.preferredLocalizations(from: available, forPreferences: UserDefaults.standard.stringArray(forKey: "AppleLanguages")).first
        return next != Bundle.main.preferredLocalizations.first
    }

    init(defaults: UserDefaults = AppDefaults.store) {
        self.defaults = defaults
        startPage = defaults.string(forKey: Key.startPage).flatMap(StartPage.init) ?? .collection
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceMode.init) ?? .system
        accent = defaults.string(forKey: Key.accent).flatMap(AccentChoice.init) ?? .system
        ambient = defaults.string(forKey: Key.ambient).flatMap(AmbientChoice.init) ?? .blue
        signatureDesign = defaults.string(forKey: Key.signatureDesign).flatMap(SignatureDesign.init) ?? .liquidGlass
        language = languageAtLaunch
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
        signatureDesign = .liquidGlass
        // The demo's settings are its own; the language is the real app's.
        if !DemoMode.isActive { language = .system }
    }

    private func store(_ value: String, _ key: String) {
        defaults.set(value, forKey: key)
    }
}

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
