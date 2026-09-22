import SwiftUI
import Charts

enum HistoryMetric: String, CaseIterable, Identifiable {
    case median = "Mittelwert", minimum = "Niedrig", maximum = "Hoch"
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
    @State private var metric: HistoryMetric = .median
    @State private var period: HistoryPeriod = .all
    @State private var selectedCurrency = ""
    private var currency: String { selectedCurrency.isEmpty ? snapshots.last?.currency ?? "EUR" : selectedCurrency }
    private var sameCurrency: [CollectionValueSnapshot] { snapshots.filter { $0.currency == currency } }
    private var visible: [CollectionValueSnapshot] { sameCurrency.filter { $0.date >= period.start() } }
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            Text("Geschätzter Wert der Sammlung").font(AppStyle.dialogTitle)
            if let latest = sameCurrency.last {
                HStack(spacing: AppStyle.rowSpacing) {
                    MetricCard(title: "Niedrig", value: money(latest.minimumValue), symbol: "arrow.down.right")
                    MetricCard(title: "Mittelwert · Median", value: money(latest.medianValue), symbol: "chart.line.uptrend.xyaxis", prominent: true)
                    MetricCard(title: "Hoch", value: money(latest.maximumValue), symbol: "arrow.up.right")
                }
                Text("Stand \(latest.date.formatted(date: .abbreviated, time: .shortened)) · \(latest.collectionItemCount) Discogs-Exemplare · Währung wie von Discogs geliefert").font(.caption).foregroundStyle(.secondary)
            } else {
                DashboardCard(title: "Sammlungswert noch nicht verfügbar") {
                    Text("Mit „Statistik aktualisieren“ den offiziellen Discogs-Wert laden. Eine Historie entsteht ab dem ersten erfolgreichen Abruf.").foregroundStyle(.secondary)
                }
            }
            if !snapshots.isEmpty {
                DashboardCard(title: "Wertentwicklung") {
                    ViewThatFits(in: .horizontal) {
                        HStack { controls; Spacer(); periods }
                        VStack(alignment: .leading) { controls; periods }
                    }
                    if visible.isEmpty { Text("Für diesen Zeitraum gibt es noch keine Momentaufnahmen.").foregroundStyle(.secondary) }
                    else {
                        HistoryLineChart(points: visible.map { .init(id: $0.id, date: $0.date, value: metric.value($0)) }, currency: currency)
                        if visible.count == 1 { Text("Erste Momentaufnahme gespeichert. Weitere Abrufe an späteren Tagen ergänzen die Kurve.").font(.caption).foregroundStyle(.secondary) }
                    }
                    changes
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), alignment: .top)], spacing: 20) {
                    DashboardCard(title: "Durchschnittlicher Wert pro Platte") {
                        if let average = sameCurrency.last?.averagePerItem { Text(money(average)).font(AppStyle.pageTitle) }
                        HistoryLineChart(points: visible.compactMap { row in row.averagePerItem.map { .init(id: row.id, date: row.date, value: $0) } }, currency: currency)
                        if let current = sameCurrency.last, let currentAverage = current.averagePerItem,
                           let target = Calendar.current.date(byAdding: .month, value: -6, to: current.date),
                           let previous = sameCurrency.last(where: { $0.date <= target }), let oldAverage = previous.averagePerItem {
                            ChangeLabel(title: "Seit mindestens 6 Monaten", current: currentAverage, previous: oldAverage, currency: currency)
                        }
                        Text("Median-Gesamtwert ÷ Collection-Instanzen. Kein durchschnittlicher Verkaufspreis einzelner Releases.").font(.caption).foregroundStyle(.secondary)
                            .help("Die Zusammensetzung der Sammlung beeinflusst diese Kennzahl. Sie beschreibt keine Preisentwicklung eines unveränderten Bestands.")
                    }
                    DashboardCard(title: "Größe der Sammlung") {
                        if let latest = sameCurrency.last { Text("\(latest.collectionItemCount) Exemplare").font(AppStyle.pageTitle) }
                        HistoryLineChart(points: visible.map { .init(id: $0.id, date: $0.date, value: Decimal($0.collectionItemCount)) }, currency: nil)
                        Text("Historisch gespeicherte Anzahl der Discogs Collection-Instanzen.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private var controls: some View {
        HStack {
            Picker("Wert", selection: $metric) { ForEach(HistoryMetric.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
            if Set(snapshots.map(\.currency)).count > 1 {
                Picker("Währung", selection: Binding(get: { currency }, set: { selectedCurrency = $0 })) {
                    ForEach(Array(Set(snapshots.map(\.currency))).sorted(), id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }
    private var periods: some View {
        Picker("Zeitraum", selection: $period) { ForEach(HistoryPeriod.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 280)
    }
    @ViewBuilder private var changes: some View {
        if let latest = sameCurrency.last, sameCurrency.count >= 2 {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185))], alignment: .leading) {
                ChangeLabel(title: "Seit letztem Snapshot", current: metric.value(latest), previous: metric.value(sameCurrency[sameCurrency.count - 2]), currency: currency)
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
                        LineMark(x: .value("Datum", point.date), y: .value("Wert", NSDecimalNumber(decimal: point.value).doubleValue)).foregroundStyle(AppStyle.chartColors[0])
                        PointMark(x: .value("Datum", point.date), y: .value("Wert", NSDecimalNumber(decimal: point.value).doubleValue)).foregroundStyle(AppStyle.chartColors[0]).symbolSize(points.count == 1 ? 60 : 16)
                    }
                    if let selected { RuleMark(x: .value("Datum", selected.date)).foregroundStyle(.secondary.opacity(0.4)) }
                }.chartXSelection(value: $selectedDate).chartYAxisLabel(currency ?? "Exemplare")
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                    .frame(height: 190)
                    .chartOverlay { proxy in GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                if let frame = proxy.plotFrame { selectedDate = proxy.value(atX: point.x - geometry[frame].minX) }
                            case .ended: selectedDate = nil
                            }
                        }
                    }}
                Text(selected.map { "\($0.date.formatted(date: .abbreviated, time: .shortened)) · \(formatted($0.value))" } ?? "Maus über die Kurve bewegen, um Werte zu sehen.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func formatted(_ value: Decimal) -> String {
        currency.map { DiscogsMoney.format(value, currency: $0) } ?? NSDecimalNumber(decimal: value).stringValue
    }
}
struct ChangeLabel: View {
    let title: String
    let current: Decimal
    let previous: Decimal
    let currency: String
    var body: some View {
        let change = CollectionValueHistoryService.change(current: current, previous: previous)
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text((change.amount > 0 ? "+" : "") + DiscogsMoney.format(change.amount, currency: currency)).font(.headline)
            if let percent = change.percent {
                Text((percent > 0 ? "+" : "") + (percent / 100).formatted(.percent.precision(.fractionLength(1)))).font(.caption)
            }
        }.foregroundStyle(change.amount < 0 ? AppStyle.warningColor : change.amount > 0 ? AppStyle.successColor : Color.secondary)
    }
}
