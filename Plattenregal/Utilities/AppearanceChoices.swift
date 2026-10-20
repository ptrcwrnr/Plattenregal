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
    case atelier, liquidGlass = "none"
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
