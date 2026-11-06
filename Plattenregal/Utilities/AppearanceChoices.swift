import AppKit
import SwiftUI

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

/// How the search in the menu bar looks in Modern, over whatever lies on
/// the desktop. In Klassisch it is always paper, like the design's cards.
enum QuickSearchLook: String, CaseIterable, Identifiable {
    case darkGlass, lightGlass, white
    var id: Self { self }
    var title: String {
        switch self {
        case .darkGlass: String(localized: "Dunkles Glas")
        case .lightGlass: String(localized: "Helles Glas")
        case .white: String(localized: "Weiß")
        }
    }
    /// Always shown, so the row keeps its height when switching.
    var hint: String {
        switch self {
        case .darkGlass: String(localized: "Dunkel getönt, liest sich über jedem Hintergrundbild gut.")
        case .lightGlass: String(localized: "Hell getönt, das Hintergrundbild schimmert durch.")
        case .white: String(localized: "Deckend weiß, nichts scheint durch.")
        }
    }
    /// The panel's appearance: field, labels and rack follow it, in light
    /// and dark mode alike.
    var appearance: NSAppearance? {
        switch self {
        case .darkGlass: NSAppearance(named: .darkAqua)
        case .lightGlass, .white: NSAppearance(named: .aqua)
        }
    }
}

/// Where the search in the menu bar opens: at the top in the middle of the
/// screen – on a MacBook with a notch right below it – or in the top right
/// corner. Either way, whether opened from the record or with ⌥ Leertaste.
/// (Until 1.11.2026 there was "underRecord" instead of the corner; a stored
/// "underRecord" now reads as unknown and falls back to the middle.)
enum QuickSearchPosition: String, CaseIterable, Identifiable {
    case center, topRight
    var id: Self { self }
    var title: String {
        switch self {
        case .center: String(localized: "Oben mittig")
        case .topRight: String(localized: "Oben rechts")
        }
    }
    /// Always shown, so the row keeps its height when switching.
    var hint: String {
        switch self {
        case .center: String(localized: "Erscheint oben in der Mitte des Bildschirms, bei einer Notch direkt darunter.")
        case .topRight: String(localized: "Erscheint oben rechts in der Ecke des Bildschirms, so nah am Rand wie an der Menüleiste.")
        }
    }
}

/// What a click on a match in the search in the menu bar does (and ↩ on
/// the highlighted one): hold it, so the rack below stays put while one
/// walks to the shelf – the default –, show it on the shelf page of the
/// app, or open it on Discogs. The latter two close the search.
enum QuickSearchClick: String, CaseIterable, Identifiable {
    case hold, showInApp, discogs
    var id: Self { self }
    var title: String {
        switch self {
        case .hold: String(localized: "Markieren")
        case .showInApp: String(localized: "In der App")
        case .discogs: String(localized: "Auf Discogs")
        }
    }
    /// Always shown, so the row keeps its height when switching.
    var hint: String {
        switch self {
        case .hold: String(localized: "Ein Klick hält den Treffer fest, das Regal darunter bleibt stehen; ein zweiter Klick lässt ihn los.")
        case .showInApp: String(localized: "Ein Klick schließt die Suche und zeigt die Platte in Plattenregal auf der Regalseite.")
        case .discogs: String(localized: "Ein Klick schließt die Suche und öffnet die Platte im Browser auf Discogs.")
        }
    }
    /// What a click does for a record: Discogs only with a Discogs page
    /// (none for the demo's sample records), else the match is held.
    func resolved(hasDiscogsPage: Bool) -> QuickSearchClick {
        self == .discogs && !hasDiscogsPage ? .hold : self
    }
    /// Tooltip of a match.
    func help(pinned: Bool) -> String {
        switch self {
        case .hold: pinned ? String(localized: "Klicken, um die Platte wieder loszulassen") : String(localized: "Klicken, um die Platte festzuhalten")
        case .showInApp: String(localized: "Klicken, um die Platte in Plattenregal zu zeigen")
        case .discogs: String(localized: "Klicken, um die Platte auf Discogs zu öffnen")
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
    // Klassisch first: the settings list the designs in this order.
    case atelier, liquidGlass = "none", vinyl
    var id: Self { self }
    var title: String {
        switch self {
        case .liquidGlass: String(localized: "Modern")
        case .atelier: String(localized: "Klassisch")
        case .vinyl: String(localized: "Vinyl")
        }
    }
    /// Klassisch and Vinyl: matte paper instead of glass, built the same way.
    var isPaper: Bool { self != .liquidGlass }
    /// The colors of a paper design; Modern has none (it takes the system's
    /// and the chosen accent), Klassisch's stand in.
    var paperColors: ClassicColors { self == .vinyl ? .vinyl : .klassisch }
    /// Vinyl has dark colors only, so the whole app shows itself dark –
    /// menus, fields and sheets included – whatever the mode says.
    var isAlwaysDark: Bool { self == .vinyl }
    /// Accent and ambient color only exist in Modern; the others bring their own.
    var usesColorChoices: Bool { self == .liquidGlass }
    /// Not translated, so the protocol reads the same in every language.
    var logName: String {
        switch self {
        case .liquidGlass: "Modern"
        case .atelier: "Klassisch"
        case .vinyl: "Vinyl"
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
