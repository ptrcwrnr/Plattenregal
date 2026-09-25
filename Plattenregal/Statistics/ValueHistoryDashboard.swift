import SwiftUI
import Charts

enum HistoryMetric: String, CaseIterable, Identifiable {
    case median = "Median", minimum = "Niedrig", maximum = "Hoch"
    var id: String { rawValue }
    func value(_ snapshot: CollectionValueSnapshot) -> Decimal {
        switch self { case .median: snapshot.medianValue; case .minimum: snapshot.minimumValue; case .maximum: snapshot.maximumValue }
    }
}
enum HistoryPeriod: String, CaseIterable, Identifiable {
    case month = "1M", quarter = "3M", half = "6M", year = "1J", all = "Alles"
    var id: String { rawValue }
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
        VStack(alignment: .leading, spacing: 28) {
            // The current value itself is shown in the statistics hero.
            if sameCurrency.isEmpty {
                Text("Noch kein Sammlungswert. Zum Laden die Seite nach unten ziehen oder ⌘R drücken – eine Historie entsteht ab dem ersten erfolgreichen Abruf.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !snapshots.isEmpty {
                VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                    ViewThatFits(in: .horizontal) {
                        HStack { subheading("Wertentwicklung"); Spacer(); controls; periods }
                        VStack(alignment: .leading, spacing: AppStyle.itemSpacing) { subheading("Wertentwicklung"); HStack { controls; periods } }
                    }
                    if visible.isEmpty { Text("Für diesen Zeitraum gibt es noch keine Momentaufnahmen.").font(.callout).foregroundStyle(.secondary) }
                    else {
                        HistoryLineChart(points: visible.map { .init(id: $0.id, date: $0.date, value: metric.value($0)) }, currency: currency)
                        if visible.count == 1 { Text("Erste Momentaufnahme gespeichert. Weitere Abrufe an späteren Tagen ergänzen die Kurve.").font(.caption).foregroundStyle(.secondary) }
                    }
                    changes
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: StatisticsLayout.gutter, alignment: .top), count: 2), alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        subheading("Durchschnittlicher Wert pro Platte")
                        if let average = sameCurrency.last?.averagePerItem { StatFigure(title: "pro Platte", value: money(average)) }
                        HistoryLineChart(points: visible.compactMap { row in row.averagePerItem.map { .init(id: row.id, date: row.date, value: $0) } }, currency: currency)
                        if let current = sameCurrency.last, let currentAverage = current.averagePerItem,
                           let target = Calendar.current.date(byAdding: .month, value: -6, to: current.date),
                           let previous = sameCurrency.last(where: { $0.date <= target }), let oldAverage = previous.averagePerItem {
                            ChangeLabel(title: "Seit mindestens 6 Monaten", current: currentAverage, previous: oldAverage, currency: currency)
                        }
                        Text("Median-Gesamtwert ÷ Anzahl der Platten in der Collection. Kein durchschnittlicher Verkaufspreis einzelner Releases.").font(.caption).foregroundStyle(.tertiary)
                            .help("Die Zusammensetzung der Sammlung beeinflusst diese Kennzahl. Sie beschreibt keine Preisentwicklung eines unveränderten Bestands.")
                    }
                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        subheading("Größe der Sammlung")
                        if let latest = sameCurrency.last { StatFigure(title: "Exemplare", value: latest.collectionItemCount.formatted()) }
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
            GlassSegmentedPicker(selection: $metric, options: HistoryMetric.allCases, small: true) { Text($0.rawValue) }
                .accessibilityLabel("Wert")
            if Set(snapshots.map(\.currency)).count > 1 {
                GlassMenuPicker(title: "Währung", selection: Binding(get: { currency }, set: { selectedCurrency = $0 }), current: currency) {
                    ForEach(Array(Set(snapshots.map(\.currency))).sorted(), id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }
    private var periods: some View {
        GlassSegmentedPicker(selection: $period, options: HistoryPeriod.allCases, small: true) { Text($0.rawValue) }
            .accessibilityLabel("Zeitraum")
    }
    @ViewBuilder private var changes: some View {
        if let latest = sameCurrency.last, sameCurrency.count >= 2 {
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                ChangeLabel(title: "Seit letzter Momentaufnahme", current: metric.value(latest), previous: metric.value(sameCurrency[sameCurrency.count - 2]), currency: currency)
                if let target = Calendar.current.date(byAdding: .day, value: -30, to: latest.date), let old = sameCurrency.last(where: { $0.date <= target }) {
                    ChangeLabel(title: "Seit mindestens 30 Tagen", current: metric.value(latest), previous: metric.value(old), currency: currency)
                }
                if let target = Calendar.current.date(byAdding: .year, value: -1, to: latest.date), let old = sameCurrency.last(where: { $0.date <= target }) {
                    ChangeLabel(title: "Seit mindestens 1 Jahr", current: metric.value(latest), previous: metric.value(old), currency: currency)
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
    @State private var selectedDate: Date?
    private var selected: HistoryPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if points.isEmpty { Text("Noch keine Daten im Zeitraum").foregroundStyle(.secondary).frame(height: 180) }
            else {
                Chart {
                    ForEach(points) { point in
                        // Swift Charts receives a rendering conversion only. Storage and arithmetic stay Decimal.
                        let value = NSDecimalNumber(decimal: point.value).doubleValue
                        AreaMark(x: .value("Datum", point.date), yStart: .value("Basis", baseline), yEnd: .value("Wert", value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [AppStyle.accent.opacity(0.25), AppStyle.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Datum", point.date), y: .value("Wert", value))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .foregroundStyle(AppStyle.accent)
                        if points.count == 1 || selected?.id == point.id {
                            PointMark(x: .value("Datum", point.date), y: .value("Wert", value))
                                .foregroundStyle(AppStyle.accent).symbolSize(points.count == 1 ? 60 : 70)
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("Datum", selected.date)).foregroundStyle(.secondary.opacity(0.4))
                            .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                VStack(spacing: 0) {
                                    Text(formatted(selected.value)).font(.caption.weight(.semibold)).monospacedDigit()
                                    Text(selected.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppStyle.borderColor))
                            }
                    }
                }.chartXSelection(value: $selectedDate).chartYAxisLabel(currency ?? "Exemplare")
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .frame(height: 180)
                    .chartOverlay { proxy in GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                if let frame = proxy.plotFrame { selectedDate = proxy.value(atX: point.x - geometry[frame].minX) }
                            case .ended: selectedDate = nil
                            }
                        }
                    }}
                Text("Maus über die Kurve bewegen, um Werte zu sehen.").font(.caption).foregroundStyle(.tertiary)
                    .opacity(selected == nil ? 1 : 0)
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
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if change.amount != 0 {
                    Image(systemName: change.amount > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption.weight(.semibold))
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
