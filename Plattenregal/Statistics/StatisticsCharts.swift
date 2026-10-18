import SwiftUI
import SwiftData
import Charts

// MARK: - Bars

/// Bar chart that explains each bar on hover (in a line below it) and
/// optionally opens it on click.
struct HoverBarChart: View {
    struct Bar: Identifiable {
        let id: String
        let label: String
        let count: Int
        var group: StatisticGroup?
    }
    let bars: [Bar]
    var height: CGFloat = 200
    var select: ((StatisticGroup) -> Void)?
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
            chart
            readout
        }
    }

    /// The hovered bar, read out below the chart instead of a box inside it.
    private var readout: some View {
        Group {
            if let bar = bars.first(where: { $0.id == hovered }) {
                HStack(alignment: .firstTextBaseline, spacing: AppStyle.tightSpacing) {
                    Text(bar.label).font(.callout.weight(.semibold))
                    Text(AppStyle.records(bar.count)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Text(select == nil ? String(localized: "Maus über die Balken bewegen, um Werte zu sehen.") : String(localized: "Maus über die Balken bewegen, um Werte zu sehen; ein Klick öffnet die Platten."))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
        .frame(height: 18, alignment: .leading)
    }

    private var chart: some View {
        let step = max(1, Int((Double(bars.count) / 10).rounded(.up)))
        return Chart(bars) { bar in
            BarMark(x: .value("Zeitraum", bar.id), y: .value("Platten", bar.count))
                .cornerRadius(3)
                .foregroundStyle(hovered == bar.id
                                 ? AnyShapeStyle(AppStyle.accent)
                                 : AnyShapeStyle(LinearGradient(colors: [AppStyle.accent.opacity(hovered == nil ? 0.85 : 0.35), AppStyle.accent.opacity(hovered == nil ? 0.45 : 0.18)],
                                                                startPoint: .top, endPoint: .bottom)))
        }
        .chartXAxis {
            AxisMarks { value in
                // Categorical axes label every bar; thin them out so they never collide.
                if value.index % step == 0 {
                    AxisValueLabel(collisionResolution: .disabled) {
                        if let id = value.as(String.self) { Text(id).fixedSize() }
                    }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { AxisGridLine(); AxisValueLabel() } }
        .frame(height: height)
        .animation(AppStyle.quickAnimation, value: hovered)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            guard let frame = proxy.plotFrame else { return }
                            // Only a new bar draws the chart again, not every pixel moved.
                            let bar = proxy.value(atX: point.x - geometry[frame].minX, as: String.self)
                            if bar != hovered { hovered = bar }
                        case .ended: hovered = nil
                        }
                    }
                    .onTapGesture { point in
                        guard let select, let frame = proxy.plotFrame,
                              let id = proxy.value(atX: point.x - geometry[frame].minX, as: String.self),
                              let group = bars.first(where: { $0.id == id })?.group else { return }
                        select(group)
                    }
            }
        }
    }
}

struct TimeTravel: View {
    let statistics: CollectionStatistics
    let byDecade: Bool
    let select: (StatisticGroup) -> Void
    @Environment(\.statisticsColumns) private var columns

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                span(String(localized: "Ältestes Release"), statistics.oldest)
                span(String(localized: "Neuestes Release"), statistics.newest)
                span(String(localized: "Jahre Musikgeschichte"), statistics.oldest.flatMap { oldest in statistics.newest.map { $0 - oldest } })
            }
            HoverBarChart(bars: bars, height: 220, select: select)
            // Gaps only when there are any: "0 ohne Jahr" says nothing.
            Text(([String(localized: "Jahr der konkreten Pressung")]
                  + (statistics.missingYear > 0 ? [String(localized: "\(statistics.missingYear) ohne Jahr")] : [])
                  + (statistics.missingStyle > 0 ? [String(localized: "\(statistics.missingStyle) ohne Style")] : [])).joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func span(_ title: String, _ year: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(year.map(String.init) ?? "—").font(.system(.title2, design: AppStyle.figureDesign, weight: .semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Continuous years/decades, including empty ones, so gaps stay visible.
    private var bars: [HoverBarChart.Bar] {
        let source = byDecade ? statistics.decades : statistics.years
        let byKey = Dictionary(source.map { (Int($0.id.prefix(4)) ?? 0, $0) }, uniquingKeysWith: { first, _ in first })
        guard let low = byKey.keys.min(), let high = byKey.keys.max() else { return [] }
        return stride(from: low, through: high, by: byDecade ? 10 : 1).map { key in
            let label = byDecade ? String(localized: "\(String(key))er") : String(key)
            return .init(id: label, label: label, count: byKey[key]?.count ?? 0, group: byKey[key])
        }
    }
}

struct AcquisitionChart: View {
    let statistics: CollectionStatistics
    let byYear: Bool
    @Environment(\.statisticsColumns) private var columns

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                if let peak = source.max(by: { $0.count < $1.count }) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(AppStyle.records(peak.count))").font(.system(.title2, design: AppStyle.figureDesign, weight: .semibold)).monospacedDigit()
                        Text("Rekord: \(peak.date.formatted(byYear ? .dateTime.year() : .dateTime.year().month(.wide)))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(AppStyle.records(source.reduce(0) { $0 + $1.count }))").font(.system(.title2, design: AppStyle.figureDesign, weight: .semibold)).monospacedDigit()
                    Text("mit bekanntem Datum").font(.caption).foregroundStyle(.secondary)
                }
            }
            if source.isEmpty {
                Text("Noch keine bekannten Hinzufügedaten.").font(.callout).foregroundStyle(.secondary)
            } else {
                HoverBarChart(bars: bars, height: 200)
            }
            Text("Aus den Hinzufügedaten der aktuell enthaltenen Exemplare. Entfernte Collection-Einträge sind nicht enthalten.").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var source: [AcquisitionBin] { byYear ? statistics.acquisitionYears : statistics.months }

    /// Continuous months/years from the first acquisition to the last, empty ones included.
    private var bars: [HoverBarChart.Bar] {
        let calendar = Calendar.current
        let component: Calendar.Component = byYear ? .year : .month
        guard let first = source.first?.date, let last = source.last?.date else { return [] }
        let counts = Dictionary(source.map { ($0.date, $0.count) }, uniquingKeysWith: +)
        var bars: [HoverBarChart.Bar] = []
        var date = first
        while date <= last {
            let label = byYear ? date.formatted(.dateTime.year()) : date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
            bars.append(.init(id: label, label: label, count: counts[date] ?? 0))
            // The period's own start, as the bins are keyed: where a month
            // begins with a clock change, adding one lands beside it and
            // every later bar would miss its count.
            guard let next = calendar.date(byAdding: component, value: 1, to: date),
                  let start = calendar.dateInterval(of: component, for: next)?.start, start > date else { break }
            date = start
        }
        return bars
    }
}

// MARK: - Shared rows

/// The ten latest additions on the shared column grid (two rows at full width).
struct RecentRecords: View {
    let copies: [RecordCopy]
    let open: (RecordCopy) -> Void
    @Environment(\.statisticsColumns) private var columns
    var body: some View {
        LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
            ForEach(copies.prefix(10)) { copy in
                Button { open(copy) } label: { CoverTile(copy: copy) }
                    .buttonStyle(.plain)
            }
        }
    }
}

/// A record as a cover filling its grid cell, with artist, title and the
/// date it was added.
private struct CoverTile: View {
    let copy: RecordCopy
    @State private var hovering = false
    var body: some View {
        let artist = copy.release?.displayArtist ?? String(localized: "Unbekannt")
        let title = copy.release?.displayTitle ?? String(localized: "Unbekannte Veröffentlichung")
        VStack(alignment: .leading, spacing: CoverGrid.captionSpacing) {
            CoverView(url: copy.release?.coverURL, size: nil)
                .shadow(color: .black.opacity(hovering ? 0.25 : 0.1), radius: hovering ? 10 : 4, y: hovering ? 6 : 2)
                .scaleEffect(hovering ? 1.04 : 1)
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text(artist).font(.callout.weight(.medium)).lineLimit(1)
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                let date = DiscogsDate.parse(copy.discogsDateAdded)
                Text(date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? String(localized: "Datum unbekannt"))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: hovering)
        .help("\(artist) – \(title)")
    }
}

/// A key figure without a box: large number, small label underneath.
struct StatFigure: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
            Text(value)
                .font(.system(.title, design: AppStyle.figureDesign, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// Ranked list with a bar per entry that grows in on appear and lights up on
/// hover; clicking an entry opens its records.
struct GroupStatisticsList: View {
    let groups: [StatisticGroup]
    let total: Int
    var columnCount = 1
    var initialLimit = 10
    let select: (StatisticGroup) -> Void
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            if groups.isEmpty { Text("Keine Angaben vorhanden").font(.callout).foregroundStyle(.secondary) }
            let maximum = CGFloat(max(1, groups.map(\.count).max() ?? 1))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: StatisticsLayout.gutter, alignment: .topLeading), count: columnCount), spacing: AppStyle.tightSpacing) {
                ForEach(expanded ? groups : Array(groups.prefix(initialLimit))) { group in
                    GroupRow(group: group, total: total, ratio: CGFloat(group.count) / maximum, select: select)
                }
            }
            if groups.count > initialLimit {
                Button(expanded ? "Weniger anzeigen" : "Alle \(groups.count) anzeigen") {
                    withAnimation(AppStyle.standardAnimation) { expanded.toggle() }
                }
                .appLinkButton().font(.caption)
            }
        }
    }

    private struct GroupRow: View {
        let group: StatisticGroup
        let total: Int
        let ratio: CGFloat
        let select: (StatisticGroup) -> Void
        @State private var hovering = false
        @State private var grown = false
        var body: some View {
            Button { select(group) } label: {
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        Text(group.name).lineLimit(1)
                        Spacer(minLength: AppStyle.tightSpacing)
                        Text(group.count.formatted()).monospacedDigit()
                        Text(group.percentage(of: total)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                    .font(.callout)
                    GeometryReader { geo in
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule().fill(AppStyle.accent.opacity(hovering ? 1 : 0.65))
                            .frame(width: geo.size.width * ratio * (grown ? 1 : 0))
                    }
                    .frame(height: hovering ? 5 : 3)
                }
                .padding(.vertical, AppStyle.tightSpacing)
                // The hover tint bleeds outward so names stay flush with the card title.
                .background(hovering ? AppStyle.hoverBackground : .clear, in: RoundedRectangle(cornerRadius: AppStyle.rowRadius).inset(by: -6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: hovering)
            .onAppear {
                if AppStyle.reduceMotion { grown = true } else { withAnimation(.smooth(duration: 0.7).delay(0.05)) { grown = true } }
            }
            .help("\(AppStyle.records(group.count)) mit \(group.name) anzeigen")
        }
    }
}
