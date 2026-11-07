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
    /// `sections` with `source` dropped onto `target`: dragged down it lands
    /// below the target, dragged up above it – also onto a direct neighbour.
    /// `nil` when nothing would change.
    static func moving(_ source: StatisticsSection, onto target: StatisticsSection,
                       in sections: [StatisticsSection]) -> [StatisticsSection]? {
        guard source != target, let from = sections.firstIndex(of: source),
              let to = sections.firstIndex(of: target) else { return nil }
        var moved = sections
        // The offset counts in the list before the move: behind the target when dragged down.
        moved.move(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
        return moved
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
    /// Top artists and labels: this many tiles and no further ranking. The
    /// full list of hundreds was too long and stuttered, every row growing
    /// its bar; a list to unfold below the tiles was one step too many.
    static let rankingCount = 10
    /// The ten tiles in even rows: two rows of five on a wide page, five rows
    /// of two on a narrow one (three columns would leave the tenth alone).
    static func rankingColumns(page columns: Int) -> Int { columns >= 5 ? 5 : 2 }
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

// MARK: - Hover while scrolling

/// Whether the statistics page is scrolling right now. Read only by the
/// hover modifiers below, so its changes don't draw the page again.
@Observable @MainActor final class StatisticsScrolling {
    var active = false
}

extension EnvironmentValues {
    @Entry var statisticsScrolling: StatisticsScrolling?
}

extension View {
    /// `onHover` for the statistics page, held back while it scrolls: there
    /// the tiles, legend rows and charts pass under a resting pointer, and
    /// each one passed lit up and had its chart drawn again, animated (two
    /// in five frames were dropped). The last change is handed on as soon
    /// as the page rests, so what lies under the pointer then lights up.
    func statisticsHover(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(DeferredHover(action: action))
    }
    /// `onContinuousHover`, held back while the page scrolls (see `statisticsHover`).
    func statisticsContinuousHover(_ action: @escaping (HoverPhase) -> Void) -> some View {
        modifier(DeferredContinuousHover(action: action))
    }
}

/// What the pointer did while the page scrolled. Not observed: keeping it
/// must not draw anything.
@MainActor final class PendingHover<Value> {
    var value: Value?
    /// The value kept while `scrolling` is active, otherwise `nil` (hand it on now).
    func hold(_ value: Value, while scrolling: StatisticsScrolling?) -> Value? {
        guard scrolling?.active == true else { return value }
        self.value = value
        return nil
    }
    func take() -> Value? {
        defer { value = nil }
        return value
    }
}

private struct DeferredHover: ViewModifier {
    let action: (Bool) -> Void
    @Environment(\.statisticsScrolling) private var scrolling
    @State private var pending = PendingHover<Bool>()
    func body(content: Content) -> some View {
        content
            .onHover { inside in pending.hold(inside, while: scrolling).map(action) }
            .onChange(of: scrolling?.active == true) { _, active in
                if !active { pending.take().map(action) }
            }
    }
}

private struct DeferredContinuousHover: ViewModifier {
    let action: (HoverPhase) -> Void
    @Environment(\.statisticsScrolling) private var scrolling
    @State private var pending = PendingHover<HoverPhase>()
    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in pending.hold(phase, while: scrolling).map(action) }
            .onChange(of: scrolling?.active == true) { _, active in
                if !active { pending.take().map(action) }
            }
    }
}
