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
        static let keepsRunningInBackground = "keepsRunningInBackground"
        static let automaticUpdateChecks = "automaticUpdateChecks"
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
    /// ⌘Q and closing the last window keep the app running with only the
    /// record in the menu bar (see `AppLifecycle`). On by default.
    var keepsRunningInBackground: Bool {
        didSet { defaults.set(keepsRunningInBackground, forKey: Key.keepsRunningInBackground) }
    }
    /// Once a day ask GitHub for a newer version (`UpdateChecker`). On by default.
    var automaticUpdateChecks: Bool {
        didSet {
            defaults.set(automaticUpdateChecks, forKey: Key.automaticUpdateChecks)
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
        keepsRunningInBackground = defaults.object(forKey: Key.keepsRunningInBackground) == nil || defaults.bool(forKey: Key.keepsRunningInBackground)
        automaticUpdateChecks = defaults.object(forKey: Key.automaticUpdateChecks) == nil || defaults.bool(forKey: Key.automaticUpdateChecks)
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
        drawnCovers = false
        menuBarSearch = true
        quickSearchHotKey = true
        quickSearchLook = .darkGlass
        quickSearchPosition = .center
        keepsRunningInBackground = true
        automaticUpdateChecks = true
        // The demo's settings are its own; the language is the real app's.
        if !DemoMode.isActive { language = .system }
    }

    private func store(_ value: String, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
