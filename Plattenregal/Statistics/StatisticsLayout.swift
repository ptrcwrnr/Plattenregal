import SwiftUI

enum StatisticsSection: String, CaseIterable, Identifiable {
    case overview, highlights, valueHistory, sound, artists, labels, discover
    case years, acquisitions, recent

    var id: String { rawValue }
    /// The saved drag & drop order (comma-separated raw values); unknown
    /// entries are skipped, sections missing from it keep their default place.
    static func ordered(from saved: String) -> [StatisticsSection] {
        let saved = saved.split(separator: ",").compactMap { StatisticsSection(rawValue: String($0)) }
        var seen: Set<StatisticsSection> = []
        return (saved + allCases).filter { seen.insert($0).inserted }
    }
    var title: String {
        switch self {
        case .overview: String(localized: "Deine Sammlung")
        case .highlights: String(localized: "Auf einen Blick")
        case .valueHistory: String(localized: "Sammlungswert im Verlauf")
        case .sound: String(localized: "Klangbild")
        case .artists: String(localized: "Top-Künstler")
        case .labels: String(localized: "Labels")
        case .discover: String(localized: "Zufallsfund")
        case .years: String(localized: "Zeitreise")
        case .acquisitions: String(localized: "Neuzugänge")
        case .recent: String(localized: "Zuletzt hinzugefügt")
        }
    }
}

/// One grid for the whole page: the same gutter between cards, inside cards
/// and between columns, and one column count shared by every tiled row
/// (figures, facts, artists, recent records), so tiles line up across cards.
enum StatisticsLayout {
    static let gutter: CGFloat = AppStyle.sectionSpacing
    static let tilePadding: CGFloat = AppStyle.rowSpacing
    static let titleSpacing: CGFloat = AppStyle.cardPadding
    static let maxWidth: CGFloat = 1200
    /// Top artists and labels: tiles first, the rest of the ranking on
    /// demand – never more than this many places in all. The full list of
    /// hundreds was too long and stuttered, every row growing its bar.
    static let rankingCount = 20
    /// Columns for a card whose content (inside its padding) is `width` wide.
    static func columnCount(contentWidth width: CGFloat) -> Int { width >= 860 ? 5 : 3 }
    static func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gutter, alignment: .topLeading), count: count)
    }
    /// Width of `span` adjacent columns within `width`.
    static func span(_ span: Int, of count: Int, in width: CGFloat) -> CGFloat {
        // Never negative: before its first measurement a card is 0 wide.
        let column = max(0, (width - CGFloat(count - 1) * gutter) / CGFloat(count))
        return column * CGFloat(span) + gutter * CGFloat(span - 1) * (column > 0 ? 1 : 0)
    }
}

extension EnvironmentValues {
    @Entry var statisticsColumns = 5
}

/// Categorical colors for the donut; the last slot is reserved for "Weitere".
/// Klassisch takes its own, calmer palette.
enum StatisticsPalette {
    static var colors: [Color] { AppStyle.isAtelier ? AtelierPalette.chart : [.blue, .teal, .indigo, .purple, .pink, .orange, .mint] }
    static var other: Color { AppStyle.isAtelier ? AtelierPalette.muted.opacity(0.5) : Color.gray.opacity(0.5) }
}

// MARK: - Hero

/// Numbers that roll into place instead of just appearing.
struct RollingNumber: View {
    let value: Double
    let format: (Double) -> String
    @State private var shown: Double = 0
    /// Only rolls where it can be seen: on the hidden page (at launch, after
    /// a sync elsewhere) every frame of it was drawn for nobody.
    @Environment(\.pageVisibility) private var visibility
    var body: some View {
        Text(format(shown))
            .monospacedDigit()
            .contentTransition(.numericText(value: shown))
            .onAppear { update() }
            .onChange(of: value) { _, _ in update() }
    }
    private func update() {
        if AppStyle.reduceMotion || !(visibility?.isShown ?? true) { shown = value } else { withAnimation(AppStyle.rollAnimation) { shown = value } }
    }
}
