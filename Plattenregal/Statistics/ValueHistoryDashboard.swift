import SwiftUI
import Charts

enum HistoryMetric: String, CaseIterable, Identifiable {
    case median = "Median", minimum = "Niedrig", maximum = "Hoch"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .median: String(localized: "Median")
        case .minimum: String(localized: "Niedrig")
        case .maximum: String(localized: "Hoch")
        }
    }
    func value(_ snapshot: CollectionValueSnapshot) -> Decimal {
        switch self { case .median: snapshot.medianValue; case .minimum: snapshot.minimumValue; case .maximum: snapshot.maximumValue }
    }
}
enum HistoryPeriod: String, CaseIterable, Identifiable {
    case month = "1M", quarter = "3M", half = "6M", year = "1J", all = "Alles"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .month: String(localized: "1M", comment: "Zeitraum: ein Monat")
        case .quarter: String(localized: "3M", comment: "Zeitraum: drei Monate")
        case .half: String(localized: "6M", comment: "Zeitraum: sechs Monate")
        case .year: String(localized: "1J", comment: "Zeitraum: ein Jahr")
        case .all: String(localized: "Alles")
        }
    }
    func start(now: Date = .now) -> Date {
        let months: Int
        switch self { case .month: months = 1; case .quarter: months = 3; case .half: months = 6; case .year: months = 12; case .all: return .distantPast }
        return Calendar.current.date(byAdding: .month, value: -months, to: now) ?? now
    }
}
struct ValueHistoryDashboard: View {
    let snapshots: [CollectionValueSnapshot]
    @Environment(\.statisticsColumns) private var columns
    @State private var metric: HistoryMetric = .median
    @State private var period: HistoryPeriod = .all
    @State private var selectedCurrency = ""
    /// The picked currency while the history still has it; after an account
    /// switch it may not, and the page must not get stuck on an empty curve.
    private var currency: String {
        if !selectedCurrency.isEmpty, snapshots.contains(where: { $0.currency == selectedCurrency }) { return selectedCurrency }
        return snapshots.last?.currency ?? "EUR"
    }
    private var sameCurrency: [CollectionValueSnapshot] { snapshots.filter { $0.currency == currency } }
    private var visible: [CollectionValueSnapshot] { sameCurrency.filter { $0.date >= period.start() } }
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.blockSpacing) {
            // The current value itself is shown in the statistics hero.
            if sameCurrency.isEmpty {
                Text("Noch kein Sammlungswert. Zum Laden die Seite nach unten ziehen oder ⌘R drücken – eine Historie entsteht ab dem ersten erfolgreichen Abruf.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !snapshots.isEmpty {
                VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                    ViewThatFits(in: .horizontal) {
                        HStack { subheading(String(localized: "Wertentwicklung")); Spacer(); controls; periods }
                        VStack(alignment: .leading, spacing: AppStyle.itemSpacing) { subheading(String(localized: "Wertentwicklung")); HStack { controls; periods } }
                    }
                    if visible.isEmpty { Text("Für diesen Zeitraum gibt es noch keine Momentaufnahmen.").font(.callout).foregroundStyle(.secondary) }
                    else {
                        HistoryLineChart(points: visible.map { .init(id: $0.id, date: $0.date, value: metric.value($0)) }, currency: currency)
                        if visible.count == 1 { Text("Erste Momentaufnahme gespeichert. Weitere Abrufe an späteren Tagen ergänzen die Kurve.").font(.caption).foregroundStyle(.secondary) }
                    }
                    changes
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: StatisticsLayout.gutter, alignment: .top), count: 2), alignment: .leading, spacing: AppStyle.blockSpacing) {
                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        subheading(String(localized: "Durchschnittlicher Wert pro Platte"))
                        if let average = sameCurrency.last?.averagePerItem { StatFigure(title: String(localized: "pro Platte"), value: money(average)) }
                        HistoryLineChart(points: visible.compactMap { row in row.averagePerItem.map { .init(id: row.id, date: row.date, value: $0) } }, currency: currency)
                        if let current = sameCurrency.last, let currentAverage = current.averagePerItem,
                           let target = Calendar.current.date(byAdding: .month, value: -6, to: current.date),
                           let previous = sameCurrency.last(where: { $0.date <= target }), let oldAverage = previous.averagePerItem {
                            ChangeLabel(title: String(localized: "Seit mindestens 6 Monaten"), current: currentAverage, previous: oldAverage, currency: currency)
                        }
                        Text("Median-Gesamtwert ÷ Anzahl der Platten in der Collection. Kein durchschnittlicher Verkaufspreis einzelner Releases.").font(.caption).foregroundStyle(.tertiary)
                            .help("Die Zusammensetzung der Sammlung beeinflusst diese Kennzahl. Sie beschreibt keine Preisentwicklung eines unveränderten Bestands.")
                    }
                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        subheading(String(localized: "Größe der Sammlung"))
                        if let latest = sameCurrency.last { StatFigure(title: String(localized: "Exemplare"), value: latest.collectionItemCount.formatted()) }
                        HistoryLineChart(points: visible.map { .init(id: $0.id, date: $0.date, value: Decimal($0.collectionItemCount)) }, currency: nil)
                        Text("Anzahl der Platten in der Discogs-Collection zum jeweiligen Zeitpunkt.").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
    private func subheading(_ text: String) -> some View {
        Text(text).font(.headline).lineLimit(1)
    }
    private var controls: some View {
        HStack {
            GlassSegmentedPicker(selection: $metric, options: HistoryMetric.allCases, small: true) { Text($0.title) }
                .accessibilityLabel("Wert")
            if Set(snapshots.map(\.currency)).count > 1 {
                GlassMenuPicker(title: String(localized: "Währung"), selection: Binding(get: { currency }, set: { selectedCurrency = $0 }), current: currency) {
                    ForEach(Array(Set(snapshots.map(\.currency))).sorted(), id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }
    private var periods: some View {
        GlassSegmentedPicker(selection: $period, options: HistoryPeriod.allCases, small: true) { Text($0.title) }
            .accessibilityLabel("Zeitraum")
    }
    @ViewBuilder private var changes: some View {
        if let latest = sameCurrency.last, sameCurrency.count >= 2 {
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                ChangeLabel(title: String(localized: "Seit letzter Momentaufnahme"), current: metric.value(latest), previous: metric.value(sameCurrency[sameCurrency.count - 2]), currency: currency)
                if let target = Calendar.current.date(byAdding: .day, value: -30, to: latest.date), let old = sameCurrency.last(where: { $0.date <= target }) {
                    ChangeLabel(title: String(localized: "Seit mindestens 30 Tagen"), current: metric.value(latest), previous: metric.value(old), currency: currency)
                }
                if let target = Calendar.current.date(byAdding: .year, value: -1, to: latest.date), let old = sameCurrency.last(where: { $0.date <= target }) {
                    ChangeLabel(title: String(localized: "Seit mindestens 1 Jahr"), current: metric.value(latest), previous: metric.value(old), currency: currency)
                }
            }
        }
    }
    private func money(_ amount: Decimal) -> String { DiscogsMoney.format(amount, currency: currency) }
}
struct HistoryPoint: Identifiable { let id: UUID; let date: Date; let value: Decimal }
struct HistoryLineChart: View {
    let points: [HistoryPoint]
    let currency: String?
    /// The point under the pointer. Its ID, not the date there: the date
    /// changes with every pixel the pointer moves, and each change drew the
    /// whole chart again – the point only every few pixels.
    @State private var selectedID: UUID?
    /// The chart's width: a half-width chart gets fewer dates on its axis,
    /// so they never run into each other.
    @State private var width: CGFloat = 0
    private var dateLabelCount: Int { max(2, min(5, Int(width / 130))) }
    /// Months between two date labels, so no more than `dateLabelCount` fit
    /// the span; `nil` (automatic) for spans too short to count in months.
    /// A hint like `desiredCount` alone is not enough: Swift Charts keeps
    /// quarterly labels even on a half-width chart, where they collide.
    private var monthStep: Int? {
        guard let first = points.map(\.date).min(), let last = points.map(\.date).max(),
              let months = Calendar.current.dateComponents([.month], from: first, to: last).month, months >= 3 else { return nil }
        return [1, 2, 3, 4, 6, 12, 24, 60].first { months / $0 < dateLabelCount } ?? 120
    }
    private var dateMarks: AxisMarkValues {
        monthStep.map { .stride(by: .month, count: $0) } ?? .automatic(desiredCount: dateLabelCount)
    }
    private var selected: HistoryPoint? { selectedID.flatMap { id in points.first { $0.id == id } } }
    /// The point closest to `date`.
    private func nearest(_ date: Date?) -> HistoryPoint? {
        guard let date else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
    private func select(_ date: Date?) {
        let id = nearest(date)?.id
        if id != selectedID { selectedID = id }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
            if points.isEmpty { Text("Noch keine Daten im Zeitraum").foregroundStyle(.secondary).frame(height: 180) }
            else {
                Chart {
                    ForEach(points) { point in
                        // Swift Charts receives a rendering conversion only. Storage and arithmetic stay Decimal.
                        let value = NSDecimalNumber(decimal: point.value).doubleValue
                        AreaMark(x: .value("Datum", point.date), yStart: .value("Basis", baseline), yEnd: .value("Wert", value))
                            .interpolationMethod(AppStyle.chartInterpolation)
                            .foregroundStyle(LinearGradient(colors: [AppStyle.accent.opacity(AppStyle.chartAreaOpacity), AppStyle.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Datum", point.date), y: .value("Wert", value))
                            .interpolationMethod(AppStyle.chartInterpolation)
                            .lineStyle(StrokeStyle(lineWidth: AppStyle.chartLineWidth, lineCap: .round))
                            .foregroundStyle(AppStyle.accent)
                        if points.count == 1 || selected?.id == point.id {
                            PointMark(x: .value("Datum", point.date), y: .value("Wert", value))
                                .foregroundStyle(AppStyle.accent).symbolSize(points.count == 1 ? 60 : 70)
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("Datum", selected.date)).foregroundStyle(.secondary.opacity(0.4))
                    }
                }.chartXSelection(value: Binding(get: { selected?.date }, set: { select($0) })).chartYAxisLabel(currency ?? String(localized: "Exemplare"))
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: dateMarks) { value in
                            AxisGridLine()
                            AxisTick()
                            // The last date ends at the plot's right edge instead of
                            // reaching past it into the value axis.
                            if monthStep != nil {
                                // Month and year, like the automatic labels of a long span.
                                AxisValueLabel(format: .dateTime.month(.abbreviated).year(),
                                               anchor: value.index == value.count - 1 ? .topTrailing : nil)
                            } else {
                                AxisValueLabel(anchor: value.index == value.count - 1 ? .topTrailing : nil)
                            }
                        }
                    }
                    .frame(height: 180)
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
                    .chartOverlay { proxy in GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                if let frame = proxy.plotFrame { select(proxy.value(atX: point.x - geometry[frame].minX)) }
                            case .ended: select(nil)
                            }
                        }
                    }}
                // The value under the pointer, read out below the chart instead
                // of a box wandering along inside it.
                Group {
                    if let selected {
                        HStack(alignment: .firstTextBaseline, spacing: AppStyle.tightSpacing) {
                            Text(formatted(selected.value)).font(AppStyle.strongCallout).monospacedDigit()
                            Text(selected.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Maus über die Kurve bewegen, um Werte zu sehen.").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .lineLimit(1)
                .frame(height: 18, alignment: .leading)
            }
        }
    }
    /// Bottom of the gradient fill: just under the lowest value, matching the non-zero y scale.
    private var baseline: Double {
        let values = points.map { NSDecimalNumber(decimal: $0.value).doubleValue }
        guard let low = values.min(), let high = values.max() else { return 0 }
        return low - max((high - low) * 0.1, abs(low) * 0.02)
    }
    private func formatted(_ value: Decimal) -> String {
        currency.map { DiscogsMoney.format(value, currency: $0) } ?? NSDecimalNumber(decimal: value).stringValue
    }
}
/// Change since an earlier snapshot: neutral amount, with only a small
/// up/down arrow carrying the direction color.
struct ChangeLabel: View {
    let title: String
    let current: Decimal
    let previous: Decimal
    let currency: String
    var body: some View {
        let change = CollectionValueHistoryService.change(current: current, previous: previous)
        VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: AppStyle.tightSpacing) {
                if change.amount != 0 {
                    Image(systemName: change.amount > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(AppStyle.captionMark)
                        .foregroundStyle(change.amount > 0 ? AppStyle.successColor : AppStyle.errorColor)
                }
                Text((change.amount > 0 ? "+" : "") + DiscogsMoney.format(change.amount, currency: currency))
                    .font(.headline).monospacedDigit()
                if let percent = change.percent {
                    Text((percent > 0 ? "+" : "") + (percent / 100).formatted(.percent.precision(.fractionLength(2))))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }
}
