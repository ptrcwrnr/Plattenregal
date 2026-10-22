import SwiftUI
import Charts

// MARK: - Sound donut

enum SoundDimension: String, CaseIterable, Identifiable {
    case genres = "Genres", styles = "Styles", formats = "Formate", countries = "Länder"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .genres: String(localized: "Genres")
        case .styles: String(localized: "Styles")
        case .formats: String(localized: "Formate")
        case .countries: String(localized: "Länder")
        }
    }
}

/// Interactive donut: hovering a slice (or its legend row) highlights it and
/// shows its share in the middle, clicking opens the records.
struct SoundDonut: View {
    let statistics: CollectionStatistics
    let dimension: SoundDimension
    let select: (StatisticGroup) -> Void
    @Environment(\.statisticsColumns) private var columns
    @State private var width: CGFloat = 0

    fileprivate struct Slice: Identifiable {
        let group: StatisticGroup
        let label: String
        let color: Color
        var id: String { group.id }
    }

    private var groups: [StatisticGroup] {
        switch dimension {
        case .genres: statistics.genres
        case .styles: statistics.styles
        case .formats: statistics.formats.filter { $0.name.hasPrefix("Merkmal: ") }
        case .countries: statistics.countries
        }
    }

    private var missing: Int {
        switch dimension {
        case .genres: statistics.missingGenre
        case .styles: statistics.missingStyle
        case .formats: statistics.missingFormatDetail
        case .countries: statistics.missingCountry
        }
    }

    private func slices(_ groups: [StatisticGroup]) -> [Slice] {
        let colors = StatisticsPalette.colors
        let top = groups.prefix(colors.count)
        var result = top.enumerated().map { index, group in
            Slice(group: group, label: display(group.name), color: colors[index])
        }
        let rest = groups.dropFirst(top.count)
        if !rest.isEmpty {
            let union = rest.reduce(into: Set<UUID>()) { $0.formUnion($1.copyIDs) }
            result.append(Slice(group: StatisticGroup(id: "weitere:\(dimension.rawValue)", name: String(localized: "Weitere \(dimension.title) (\(rest.count))"), copyIDs: union),
                                label: String(localized: "Weitere (\(rest.count))"), color: StatisticsPalette.other))
        }
        return result
    }
    private func display(_ name: String) -> String {
        name.hasPrefix("Merkmal: ") ? String(name.dropFirst("Merkmal: ".count)) : name
    }

    var body: some View {
        let groups = groups
        let slices = slices(groups)
        Group {
            if slices.isEmpty {
                Text("Keine Angaben vorhanden").font(.callout).foregroundStyle(.secondary)
            } else {
                // The slices are worked out here, the pointer is followed in
                // `SoundDonutChart`: a slice hovered doesn't build them again
                // (with "Weitere" merging the records of every other entry).
                SoundDonutChart(slices: slices, total: statistics.totalItems, entries: groups.count, missing: missing,
                                dimension: dimension, span: StatisticsLayout.span(2, of: columns, in: width), select: select)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
    }
}

/// The donut and its legend for given slices, following the pointer: a
/// hovered slice draws only this again.
private struct SoundDonutChart: View {
    let slices: [SoundDonut.Slice]
    let total: Int
    /// All entries of the dimension, including those under "Weitere".
    let entries: Int
    let missing: Int
    let dimension: SoundDimension
    /// Width of the first two grid columns, where the donut sits.
    let span: CGFloat
    let select: (StatisticGroup) -> Void
    @State private var hovered: String?

    var body: some View {
        // Donut on the first two columns, legend across the rest.
        HStack(alignment: .center, spacing: StatisticsLayout.gutter) {
            donut(slices).frame(width: min(span, 280), height: min(span, 280))
                .frame(width: span, alignment: .leading)
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                legend(slices)
                // The shares are of all records, so say how many have no value here.
                if missing > 0 {
                    Text("\(AppStyle.records(missing)) ohne Angabe\(dimension == .countries ? String(localized: " – Länder kommen mit den Tracklisten von Discogs") : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func donut(_ slices: [SoundDonut.Slice]) -> some View {
        let sum = max(1, slices.reduce(0) { $0 + $1.group.count })
        return Chart(slices) { slice in
            SectorMark(angle: .value("Exemplare", slice.group.count),
                       innerRadius: .ratio(0.6),
                       outerRadius: .ratio(hovered == slice.id ? 1 : 0.92),
                       angularInset: 1.5)
                .cornerRadius(5)
                .foregroundStyle(slice.color)
                .opacity(hovered == nil || hovered == slice.id ? 1 : 0.35)
        }
        .chartLegend(.hidden)
        .animation(AppStyle.quickAnimation, value: hovered)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame {
                    let rect = geometry[frame]
                    center(slices).frame(width: rect.width * 0.5).position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            guard let frame = proxy.plotFrame else { return }
                            // Only a new slice draws the chart again, not every pixel moved.
                            let id = slice(at: point, in: geometry[frame], slices: slices, sum: sum)?.id
                            if id != hovered { hovered = id }
                        case .ended: hovered = nil
                        }
                    }
                    .onTapGesture { point in
                        guard let frame = proxy.plotFrame,
                              let slice = slice(at: point, in: geometry[frame], slices: slices, sum: sum) else { return }
                        select(slice.group)
                    }
            }
        }
    }

    /// Maps a point to the slice under it. Sectors start at 12 o'clock and run clockwise.
    private func slice(at point: CGPoint, in rect: CGRect, slices: [SoundDonut.Slice], sum: Int) -> SoundDonut.Slice? {
        let dx = point.x - rect.midX, dy = point.y - rect.midY
        let radius = min(rect.width, rect.height) / 2
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= radius * 0.55, distance <= radius else { return nil }
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let target = angle / (2 * .pi) * Double(sum)
        var running = 0.0
        for slice in slices {
            running += Double(slice.group.count)
            if target < running { return slice }
        }
        return slices.last
    }

    @ViewBuilder private func center(_ slices: [SoundDonut.Slice]) -> some View {
        if let hovered, let slice = slices.first(where: { $0.id == hovered }) {
            VStack(spacing: AppStyle.hairSpacing) {
                Text(slice.group.percentage(of: total))
                    .font(.system(.title, design: AppStyle.figureDesign, weight: .bold)).foregroundStyle(slice.color)
                Text(slice.label).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                Text("\(AppStyle.records(slice.group.count))").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: AppStyle.hairSpacing) {
                // All of them, including those under "Weitere".
                Text(entries.formatted())
                    .font(.system(.title, design: AppStyle.figureDesign, weight: .bold))
                Text(dimension.title).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ slices: [SoundDonut.Slice]) -> some View {
        // Measured against the largest named entry: "Weitere" bundles many and
        // would shrink every real bar to a few pixels; it is capped at full.
        let named = slices.filter { !$0.id.hasPrefix("weitere:") }
        let maximum = CGFloat(max(1, (named.isEmpty ? slices : named).map(\.group.count).max() ?? 1))
        return VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
            ForEach(slices) { slice in
                Button { select(slice.group) } label: {
                    HStack(spacing: AppStyle.itemSpacing) {
                        RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 10, height: 10)
                        Text(slice.label).lineLimit(1)
                        Spacer(minLength: AppStyle.itemSpacing)
                        Capsule().fill(slice.color.opacity(0.5))
                            .frame(width: 70 * min(1, CGFloat(slice.group.count) / maximum), height: 4)
                            .frame(width: 70, alignment: .leading)
                        Text(slice.group.count.formatted()).monospacedDigit().frame(minWidth: 36, alignment: .trailing)
                        Text(slice.group.percentage(of: total)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                    .font(.callout)
                    .padding(.vertical, AppStyle.tightSpacing)
                    .background(hovered == slice.id ? slice.color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: AppStyle.rowRadius).inset(by: -AppStyle.itemSpacing))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hovered = slice.id } else if hovered == slice.id { hovered = nil }
                }
                .help("\(AppStyle.records(slice.group.count)) mit \(slice.label) anzeigen")
            }
        }
        .animation(AppStyle.quickAnimation, value: hovered)
    }
}
