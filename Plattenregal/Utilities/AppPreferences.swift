import AppKit
import SwiftUI

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
        static let drawnCovers = "drawnCovers"
        static let menuBarSearch = "menuBarSearch"
        static let quickSearchHotKey = "quickSearchHotKey"
        static let quickSearchLook = "quickSearchLook"
        static let quickSearchPosition = "quickSearchPosition"
        static let quickSearchClick = "quickSearchClick"
        static let pageNames = "pageNames"
        static func markColor(_ mark: RecordMark) -> String { "markColor-\(mark.rawValue)" }
        static let keepsRunningInBackground = "keepsRunningInBackground"
        static let updateCheckInterval = "updateCheckInterval"
        /// Up to 1.0.3: the switch for a check once a day. Read while no
        /// `updateCheckInterval` is stored, removed with the first change.
        static let automaticUpdateChecks = "automaticUpdateChecks"
    }

    private let defaults: UserDefaults
    /// The choice this launch was started with.
    private let languageAtLaunch = AppLanguage.stored

    var startPage: StartPage { didSet { store(startPage.rawValue, Key.startPage) } }
    var appearance: AppearanceMode { didSet { store(appearance.rawValue, Key.appearance); applyAppearance() } }
    var accent: AccentChoice { didSet { store(accent.rawValue, Key.accent) } }
    var ambient: AmbientChoice { didSet { store(ambient.rawValue, Key.ambient) } }
    var signatureDesign: SignatureDesign {
        didSet {
            store(signatureDesign.rawValue, Key.signatureDesign)
            if signatureDesign.isAlwaysDark != oldValue.isAlwaysDark { applyAppearance() }
        }
    }
    var language: AppLanguage { didSet { AppLanguage.store(language) } }
    /// Drawn covers as in the demo (colour, artist, title) instead of the
    /// Discogs images. Off by default.
    var drawnCovers: Bool { didSet { defaults.set(drawnCovers, forKey: Key.drawnCovers) } }
    /// The record in the menu bar that opens the search in the shelves. On by default.
    var menuBarSearch: Bool {
        didSet { defaults.set(menuBarSearch, forKey: Key.menuBarSearch); ShelfQuickSearch.shared.applySettings() }
    }
    /// ⌥ Leertaste opens that search from every app. On by default.
    var quickSearchHotKey: Bool {
        didSet { defaults.set(quickSearchHotKey, forKey: Key.quickSearchHotKey); ShelfQuickSearch.shared.applySettings() }
    }
    /// How that search looks in Modern. Dark glass by default.
    var quickSearchLook: QuickSearchLook { didSet { store(quickSearchLook.rawValue, Key.quickSearchLook) } }
    /// Where that search opens. At the top in the middle by default.
    var quickSearchPosition: QuickSearchPosition { didSet { store(quickSearchPosition.rawValue, Key.quickSearchPosition) } }
    /// The user's own page names by `Destination.rawValue` (see `PageNames`);
    /// a page without one keeps its own name.
    var pageNames: [String: String] { didSet { defaults.set(pageNames, forKey: Key.pageNames) } }
    /// The color of each state's dot (`RecordMark`); the design's own by default.
    var markColors: [RecordMark: StatusColorChoice] {
        didSet {
            for mark in RecordMark.allCases where markColors[mark] != oldValue[mark] {
                // The default leaves nothing stored, like a fresh install.
                if let choice = markColors[mark], choice != .standard { store(choice.rawValue, Key.markColor(mark)) }
                else { defaults.removeObject(forKey: Key.markColor(mark)) }
            }
        }
    }
    func markColor(_ mark: RecordMark) -> StatusColorChoice { markColors[mark] ?? .standard }
    func setMarkColor(_ choice: StatusColorChoice, for mark: RecordMark) { markColors[mark] = choice }

    /// What a click on a match in that search does. Holds it by default.
    var quickSearchClick: QuickSearchClick { didSet { store(quickSearchClick.rawValue, Key.quickSearchClick) } }
    /// ⌘Q and closing the last window keep the app running with only the
    /// record in the menu bar (see `AppLifecycle`). On by default.
    var keepsRunningInBackground: Bool {
        didSet { defaults.set(keepsRunningInBackground, forKey: Key.keepsRunningInBackground) }
    }
    /// How often to ask GitHub for a newer version (`UpdateChecker`). Weekly by default.
    var updateCheckInterval: UpdateCheckInterval {
        didSet {
            store(updateCheckInterval.rawValue, Key.updateCheckInterval)
            defaults.removeObject(forKey: Key.automaticUpdateChecks)
            UpdateChecker.shared.automaticChecksChanged()
        }
    }
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
        drawnCovers = defaults.bool(forKey: Key.drawnCovers)
        // On unless switched off; `bool(forKey:)` also reads "NO" from a launch argument.
        menuBarSearch = defaults.object(forKey: Key.menuBarSearch) == nil || defaults.bool(forKey: Key.menuBarSearch)
        quickSearchHotKey = defaults.object(forKey: Key.quickSearchHotKey) == nil || defaults.bool(forKey: Key.quickSearchHotKey)
        quickSearchLook = defaults.string(forKey: Key.quickSearchLook).flatMap(QuickSearchLook.init) ?? .darkGlass
        quickSearchPosition = defaults.string(forKey: Key.quickSearchPosition).flatMap(QuickSearchPosition.init) ?? .center
        quickSearchClick = defaults.string(forKey: Key.quickSearchClick).flatMap(QuickSearchClick.init) ?? .hold
        pageNames = defaults.dictionary(forKey: Key.pageNames)?.compactMapValues { $0 as? String } ?? [:]
        // An unknown value (a later version's color) counts as the default.
        markColors = Dictionary(uniqueKeysWithValues: RecordMark.allCases.map { mark in
            (mark, defaults.string(forKey: Key.markColor(mark)).flatMap(StatusColorChoice.init) ?? .standard)
        })
        keepsRunningInBackground = defaults.object(forKey: Key.keepsRunningInBackground) == nil || defaults.bool(forKey: Key.keepsRunningInBackground)
        updateCheckInterval = Self.storedUpdateCheckInterval(in: defaults)
        language = languageAtLaunch
    }

    /// Light or dark for every window, including sheets and the settings.
    /// Vinyl is always dark; the chosen mode stays stored for the others.
    func applyAppearance() {
        NSApplication.shared.appearance = signatureDesign.isAlwaysDark ? NSAppearance(named: .darkAqua) : appearance.appearance
    }

    /// Back to the defaults (used by "Einstellungen zurücksetzen").
    func reset() {
        startPage = .collection
        appearance = .system
        accent = .system
        ambient = .blue
        signatureDesign = .liquidGlass
        drawnCovers = false
        menuBarSearch = true
        quickSearchHotKey = true
        quickSearchLook = .darkGlass
        quickSearchPosition = .center
        quickSearchClick = .hold
        pageNames = [:]
        markColors = Dictionary(uniqueKeysWithValues: RecordMark.allCases.map { ($0, .standard) })
        keepsRunningInBackground = true
        updateCheckInterval = .weekly
        // The demo's settings are its own; the language is the real app's.
        if !DemoMode.isActive { language = .system }
    }

    /// The stored choice; else the switch of 1.0.3 and earlier: off stays off
    /// (never), on – the daily check – becomes weekly. Only read here, so a
    /// launch argument is never stored; the first change stores the choice
    /// and drops the old switch. `bool(forKey:)` also reads "NO" from a
    /// launch argument.
    private static func storedUpdateCheckInterval(in defaults: UserDefaults) -> UpdateCheckInterval {
        if let raw = defaults.string(forKey: Key.updateCheckInterval), let interval = UpdateCheckInterval(rawValue: raw) {
            return interval
        }
        let switchedOff = defaults.object(forKey: Key.automaticUpdateChecks) != nil && !defaults.bool(forKey: Key.automaticUpdateChecks)
        return switchedOff ? .never : .weekly
    }

    /// Sets a page's own name as typed (`PageNames.limited`); an empty one
    /// gives the page its own name back.
    func setPageName(_ name: String, for page: Destination) {
        let limited = PageNames.limited(name)
        if limited.isEmpty { pageNames[page.rawValue] = nil } else { pageNames[page.rawValue] = limited }
    }

    private func store(_ value: String, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
