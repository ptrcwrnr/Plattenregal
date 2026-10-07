import SwiftUI
import SwiftData
import Charts

struct StatisticsHero: View {
    let statistics: CollectionStatistics
    let history: [CollectionValueSnapshot]
    let hasOwner: Bool
    let hasToken: Bool
    @Environment(\.statisticsColumns) private var columns
    @State private var width: CGFloat = 0

    private var sameCurrency: [CollectionValueSnapshot] {
        guard let currency = history.last?.currency else { return [] }
        return history.filter { $0.currency == currency }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.gutter) {
            // Value on the first two columns, the curve on the remaining ones.
            HStack(alignment: .center, spacing: StatisticsLayout.gutter) {
                valueBlock.frame(width: StatisticsLayout.span(2, of: columns, in: width), alignment: .leading)
                sparkline.frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                figure(String(localized: "Schallplatten"), statistics.totalItems, "opticaldisc")
                figure(String(localized: "Releases"), statistics.uniqueReleases, "square.stack")
                figure(String(localized: "Künstler"), statistics.artists.count, "music.mic")
                figure(String(localized: "Styles"), statistics.styles.count, "waveform")
                figure(String(localized: "Labels"), statistics.labels.count, "tag")
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
    }

    @ViewBuilder private var valueBlock: some View {
        if let latest = sameCurrency.last {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sammlungswert · Median").font(.callout).foregroundStyle(.secondary)
                RollingNumber(value: NSDecimalNumber(decimal: latest.medianValue).doubleValue) {
                    DiscogsMoney.format(Decimal($0.rounded()), currency: latest.currency)
                }
                .font(.system(size: 44, weight: .bold, design: AppStyle.figureDesign))
                // The digits' own side bearing, so the number starts at
                // the edge of the words above and below it.
                .padding(.leading, -3)
                .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 10) {
                    if sameCurrency.count >= 2 { DeltaChip(current: latest.medianValue, previous: sameCurrency[sameCurrency.count - 2].medianValue, currency: latest.currency) }
                    Text("Spanne \(DiscogsMoney.format(latest.minimumValue, currency: latest.currency)) – \(DiscogsMoney.format(latest.maximumValue, currency: latest.currency))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(([latest.averagePerItem.map { String(localized: "≈ \(DiscogsMoney.format($0, currency: latest.currency)) pro Platte") }]
                      + [String(localized: "Stand \(latest.date.formatted(date: .abbreviated, time: .shortened))")]).compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Schallplatten in der Sammlung").font(.callout).foregroundStyle(.secondary)
                RollingNumber(value: Double(statistics.totalItems)) { Int($0.rounded()).formatted() }
                    .font(.system(size: 44, weight: .bold, design: AppStyle.figureDesign))
                // The digits' own side bearing, so the number starts at
                // the edge of the words above and below it.
                .padding(.leading, -3)
                Text(!hasOwner ? "Verbinde eine Discogs-Collection, um ihren Wert zu verfolgen."
                     : !hasToken ? "Für den Sammlungswert fehlt der Discogs-Token. Trage ihn in den Einstellungen ein."
                     : "Noch kein Sammlungswert. Zum Laden die Seite nach unten ziehen oder ⌘R drücken.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var sparkline: some View {
        if sameCurrency.count >= 2 {
            Chart(sameCurrency) { snapshot in
                let value = NSDecimalNumber(decimal: snapshot.medianValue).doubleValue
                AreaMark(x: .value("Datum", snapshot.date), y: .value("Wert", value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [AppStyle.accent.opacity(0.35), AppStyle.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Datum", snapshot.date), y: .value("Wert", value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(AppStyle.accent)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 96)
            .accessibilityLabel("Verlauf des Sammlungswerts")
        }
    }

    private func figure(_ title: String, _ value: Int, _ systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 34, height: 34)
                .background(AppStyle.isAtelier ? AtelierPalette.soft : AppStyle.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                RollingNumber(value: Double(value)) { Int($0.rounded()).formatted() }
                    .font(.system(.title2, design: AppStyle.figureDesign, weight: .semibold))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(StatisticsLayout.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statisticsTile()
    }
}

/// Small capsule with the change since the previous snapshot.
private struct DeltaChip: View {
    let current: Decimal
    let previous: Decimal
    let currency: String
    var body: some View {
        let change = CollectionValueHistoryService.change(current: current, previous: previous)
        let color: Color = change.amount > 0 ? AppStyle.successColor : change.amount < 0 ? AppStyle.errorColor : .secondary
        HStack(spacing: 4) {
            Image(systemName: change.amount > 0 ? "arrow.up.right" : change.amount < 0 ? "arrow.down.right" : "equal")
            Text((change.amount > 0 ? "+" : "") + DiscogsMoney.format(change.amount, currency: currency))
            if let percent = change.percent {
                Text("(" + (percent > 0 ? "+" : "") + (percent / 100).formatted(.percent.precision(.fractionLength(2))) + ")")
            }
        }
        .font(.caption.weight(.semibold)).monospacedDigit()
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .help("Veränderung seit der letzten Momentaufnahme")
    }
}

// MARK: - Facts

struct StatisticsFacts: View {
    let statistics: CollectionStatistics
    let select: (StatisticGroup) -> Void

    private struct Fact: Identifiable {
        let title: String, value: String, detail: String, systemImage: String, color: Color
        var group: StatisticGroup?
        var help: String?
        var id: String { title }
    }

    private var facts: [Fact] {
        var facts: [Fact] = []
        let total = statistics.totalItems
        if let artist = statistics.artists.first {
            facts.append(.init(title: String(localized: "Häufigster Künstler"), value: artist.name, detail: "\(AppStyle.records(artist.count)) · \(artist.percentage(of: total))", systemImage: "music.mic", color: .blue, group: artist))
        }
        if let style = statistics.styles.first {
            facts.append(.init(title: String(localized: "Häufigster Style"), value: style.name, detail: "\(AppStyle.records(style.count)) · \(style.percentage(of: total))", systemImage: "waveform", color: .teal, group: style))
        }
        if let decade = statistics.decades.max(by: { $0.count < $1.count }) {
            facts.append(.init(title: String(localized: "Stärkstes Jahrzehnt"), value: decade.name, detail: "\(AppStyle.records(decade.count))", systemImage: "calendar", color: .indigo, group: decade))
        }
        if let year = statistics.years.max(by: { $0.count < $1.count }) {
            facts.append(.init(title: String(localized: "Häufigstes Jahr"), value: year.name, detail: "\(AppStyle.records(year.count))", systemImage: "star", color: .purple, group: year))
        }
        let thisYear = Calendar.current.component(.year, from: .now)
        // Compared with the same stretch of last year, not all of it: early in
        // the year a whole previous year would always look like much more.
        let current = statistics.addedThisYear, previous = statistics.addedLastYearToDate
        let comparison = current > previous ? String(localized: "\(current - previous) mehr als im Vorjahreszeitraum")
            : current < previous ? String(localized: "\(previous - current) weniger als im Vorjahreszeitraum")
            : String(localized: "genauso viele wie im Vorjahreszeitraum")
        let period = Date.now.formatted(.dateTime.day().month(.abbreviated))
        facts.append(.init(title: String(localized: "Neu in \(String(thisYear))"), value: "\(AppStyle.records(current))", detail: comparison, systemImage: "plus.circle", color: .orange,
                           help: String(localized: "1. Jan. bis \(period): \(current) in \(String(thisYear)), \(previous) in \(String(thisYear - 1))")))
        return facts
    }

    @Environment(\.statisticsColumns) private var columns

    var body: some View {
        LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
            ForEach(facts) { fact in
                FactTile(fact: fact, select: select)
            }
        }
    }

    private struct FactTile: View {
        let fact: Fact
        let select: (StatisticGroup) -> Void
        @State private var hovering = false
        var body: some View {
            Button { if let group = fact.group { select(group) } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        // Klassisch: one petrol for all, no rainbow.
                        Image(systemName: fact.systemImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AppStyle.isAtelier ? AppStyle.accent : fact.color)
                            .frame(width: 28, height: 28)
                            .background(AppStyle.isAtelier ? AtelierPalette.soft : fact.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                        Text(fact.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if fact.group != nil {
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                .opacity(hovering ? 1 : 0)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.value).font(.headline).lineLimit(1)
                        Text(fact.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(StatisticsLayout.tilePadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .statisticsTile(hovering: hovering && fact.group != nil)
                .contentShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            }
            .buttonStyle(.plain)
            // Tiles without records to open still take the pointer for their tooltip.
            .allowsHitTesting(fact.group != nil || fact.help != nil)
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: hovering)
            .help(fact.help ?? fact.group.map { String(localized: "\(AppStyle.records($0.count)) mit \($0.name) anzeigen") } ?? "")
        }
    }
}

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
    @State private var hovered: String?

    private struct Slice: Identifiable {
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

    private var slices: [Slice] {
        let groups = groups
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
        let slices = slices
        Group {
            if slices.isEmpty {
                Text("Keine Angaben vorhanden").font(.callout).foregroundStyle(.secondary)
            } else {
                // Donut on the first two columns, legend across the rest.
                let donutSize = min(StatisticsLayout.span(2, of: columns, in: width), 280)
                HStack(alignment: .center, spacing: StatisticsLayout.gutter) {
                    donut(slices).frame(width: donutSize, height: donutSize)
                        .frame(width: StatisticsLayout.span(2, of: columns, in: width), alignment: .leading)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
    }

    private func donut(_ slices: [Slice]) -> some View {
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
                            hovered = slice(at: point, in: geometry[frame], slices: slices, sum: sum)?.id
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
    private func slice(at point: CGPoint, in rect: CGRect, slices: [Slice], sum: Int) -> Slice? {
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

    @ViewBuilder private func center(_ slices: [Slice]) -> some View {
        if let hovered, let slice = slices.first(where: { $0.id == hovered }) {
            VStack(spacing: 2) {
                Text(slice.group.percentage(of: statistics.totalItems))
                    .font(.system(.title, design: AppStyle.figureDesign, weight: .bold)).foregroundStyle(slice.color)
                Text(slice.label).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                Text("\(AppStyle.records(slice.group.count))").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 2) {
                // All of them, including those under "Weitere".
                Text(groups.count.formatted())
                    .font(.system(.title, design: AppStyle.figureDesign, weight: .bold))
                Text(dimension.title).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ slices: [Slice]) -> some View {
        // Measured against the largest named entry: "Weitere" bundles many and
        // would shrink every real bar to a few pixels; it is capped at full.
        let named = slices.filter { !$0.id.hasPrefix("weitere:") }
        let maximum = CGFloat(max(1, (named.isEmpty ? slices : named).map(\.group.count).max() ?? 1))
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(slices) { slice in
                Button { select(slice.group) } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 10, height: 10)
                        Text(slice.label).lineLimit(1)
                        Spacer(minLength: 8)
                        Capsule().fill(slice.color.opacity(0.5))
                            .frame(width: 70 * min(1, CGFloat(slice.group.count) / maximum), height: 4)
                            .frame(width: 70, alignment: .leading)
                        Text(slice.group.count.formatted()).monospacedDigit().frame(minWidth: 36, alignment: .trailing)
                        Text(slice.group.percentage(of: statistics.totalItems)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                    .font(.callout)
                    .padding(.vertical, 5)
                    .background(hovered == slice.id ? slice.color.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8).inset(by: -8))
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

// MARK: - Artist podium

/// The top artists as a row of covers with their rank, the rest as a list on demand.
struct ArtistPodium: View {
    let groups: [StatisticGroup]
    let total: Int
    let copies: [UUID: RecordCopy]
    let select: (StatisticGroup) -> Void
    @Environment(\.statisticsColumns) private var podiumCount
    @State private var showsList = false

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            if groups.isEmpty { Text("Keine Angaben vorhanden").font(.callout).foregroundStyle(.secondary) }
            LazyVGrid(columns: StatisticsLayout.columns(podiumCount), alignment: .leading, spacing: StatisticsLayout.gutter) {
                ForEach(Array(groups.prefix(podiumCount).enumerated()), id: \.element.id) { index, group in
                    ArtistTile(rank: index + 1, group: group, total: total, cover: cover(for: group), select: select)
                }
            }
            if groups.count > podiumCount {
                Button {
                    withAnimation(AppStyle.standardAnimation) { showsList.toggle() }
                } label: {
                    Label(showsList ? "Rangliste ausblenden" : "Rangliste ab Platz \(podiumCount + 1)", systemImage: showsList ? "chevron.up" : "chevron.down")
                }
                .appLinkButton().font(.caption)
                if showsList {
                    GroupStatisticsList(groups: Array(groups.dropFirst(podiumCount)), total: total, columnCount: 2, select: select)
                        .transition(AppStyle.funnelTransition())
                }
            }
        }
    }

    /// A representative cover that stays the same across launches and a new
    /// sync (copy IDs don't): the artist's earliest release, then by title.
    private func cover(for group: StatisticGroup) -> String? {
        group.copyIDs.compactMap { copies[$0]?.release }
            .filter { $0.coverURL != nil }
            .min { lhs, rhs in
                let left = lhs.year ?? Int.max, right = rhs.year ?? Int.max
                if left != right { return left < right }
                let order = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
                return order == .orderedSame ? lhs.discogsID < rhs.discogsID : order == .orderedAscending
            }?
            .coverURL
    }

    private struct ArtistTile: View {
        let rank: Int
        let group: StatisticGroup
        let total: Int
        let cover: String?
        let select: (StatisticGroup) -> Void
        @State private var hovering = false
        var body: some View {
            Button { select(group) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    // The rank sits by the name, as on the label tiles: on
                    // the cover it hid the artwork's own lettering.
                    CoverView(url: cover, size: nil)
                        .atelierRecordSleeve()
                        .shadow(color: .black.opacity(AppStyle.isAtelier ? 0 : hovering ? 0.25 : 0.1), radius: hovering ? 10 : 4, y: hovering ? 6 : 2)
                        .scaleEffect(hovering ? 1.03 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(rank)").font(.system(.caption, design: AppStyle.figureDesign, weight: .bold)).foregroundStyle(AppStyle.accent)
                            Text(group.name).font(.callout.weight(.medium)).lineLimit(1)
                        }
                        Text("\(AppStyle.records(group.count)) · \(group.percentage(of: total))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: hovering)
            .help("\(AppStyle.records(group.count)) von \(group.name) anzeigen")
        }
    }
}

// MARK: - Random pick

/// One random record from the collection, rerolled on demand: a large cover
/// on the first grid columns, details on the rest, the cover blurred behind.
struct RandomRecordCard: View {
    let copies: [RecordCopy]
    /// `StatisticsViewModel.version`: the shelf labels are recomputed on it,
    /// not on every render.
    let version: Int
    let open: (RecordCopy) -> Void
    let showShelf: (RecordCopy) -> Void
    @Environment(\.statisticsColumns) private var columns
    @State private var labelsCache = ShelfLabelsCache()
    /// Where the pick stands, read from the app's own records: the page's
    /// copies come from a reload, and sorting in doesn't reload the page.
    @State private var placement: (location: String, inShelf: Bool)?
    @Environment(\.modelContext) private var context
    @State private var width: CGFloat = 0
    /// Stored by ID and looked up in the current `copies`: each reload hands
    /// in new objects, and an old one must not stay on screen.
    @State private var pickID: UUID?
    @State private var rolls = 0
    @Query private var shelves: [Shelf]
    @Query private var exclusions: [OptimizationExclusion]
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    private var pick: RecordCopy? { pickID.flatMap { id in copies.first { $0.id == id } } }

    private var coverSpan: Int { columns >= 5 ? 2 : 1 }

    var body: some View {
        Group {
            if let pick, let release = pick.release {
                let coverWidth = StatisticsLayout.span(coverSpan, of: columns, in: width)
                HStack(alignment: .top, spacing: StatisticsLayout.gutter) {
                    Button { open(pick) } label: {
                        CoverView(url: release.coverURL, size: nil)
                            .atelierRecordSleeve()
                            .frame(width: min(coverWidth, 380))
                            .shadow(color: .black.opacity(AppStyle.isAtelier ? 0 : 0.25), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .help("Details anzeigen")
                    .frame(width: coverWidth, alignment: .leading)
                    details(pick, release)
                }
                .id(pick.id)
                .transition(AppStyle.reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                           removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                Text("Noch keine Platten zum Ziehen.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        // Whenever the pick is gone (first load, or a sync removed it) and
        // there is something to pick — not only when the count changes.
        // Places change without a reload of the page (see `StatisticsView.affectsStatistics`).
        .task(id: [version, labelStyle.hashValue, LibraryChanges.shared.placementsVersion, LibraryChanges.shared.shelvesVersion]) {
            if pick == nil { pickID = copies.randomElement()?.id }
            updatePlacement()
        }
        .onChange(of: pickID) { updatePlacement() }
    }

    private func details(_ pick: RecordCopy, _ release: Release) -> some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.gutter) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Heute aus deiner Sammlung").font(.caption.weight(.semibold)).foregroundStyle(AppStyle.accent)
                Text(release.displayArtist)
                    .font(.system(.largeTitle, design: AppStyle.figureDesign, weight: .bold))
                    .lineLimit(2)
                Text(release.displayTitle).font(.title2).foregroundStyle(.secondary).lineLimit(2)
            }
            // Same columns as the page grid to the right of the cover.
            LazyVGrid(columns: StatisticsLayout.columns(max(1, columns - coverSpan)), alignment: .leading, spacing: 14) {
                detail(String(localized: "Jahr"), release.year.map(String.init))
                detail(String(localized: "Label"), release.displayLabel)
                detail(String(localized: "Land"), release.country)
                detail(String(localized: "Format"), release.format)
                detail(String(localized: "Tracks"), release.tracks.isEmpty ? nil : "\(release.tracks.count)")
                detail(String(localized: "Fach"), placement?.location)
            }
            if !release.styles.isEmpty {
                HStack(spacing: 6) { ForEach(release.styles.prefix(4), id: \.self) { AppBadge(title: $0) } }
            }
            HStack(spacing: AppStyle.itemSpacing) {
                Button { reroll() } label: {
                    Label("Neue Platte ziehen", systemImage: "dice")
                        .symbolEffect(.bounce, value: rolls)
                        .foregroundStyle(AppStyle.accent)
                }
                .appGlassButton()
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Neue Platte ziehen (⇧⌘R)")
                SecondaryButton(title: placement?.inShelf != true ? String(localized: "Platz im Regal finden") : String(localized: "Im Regal zeigen")) { showShelf(pick) }
                SecondaryButton(title: String(localized: "Details")) { open(pick) }
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "—").font(.callout.weight(.medium)).lineLimit(1)
        }
        .help(value ?? "")
    }

    private func updatePlacement() {
        guard let id = pickID,
              let copy = try? context.fetch(FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.id == id })).first
        else { placement = nil; return }
        let labels = labelsCache.labels(for: shelves, style: labelStyle)
        placement = (ShelfRangeLabels.location(of: copy, labels: labels, excluded: exclusions.contains { $0.copyID == id }),
                     copy.shelf != nil)
    }

    private func reroll() {
        rolls += 1
        let candidates = copies.count > 1 ? copies.filter { $0.id != pick?.id } : copies
        withAnimation(AppStyle.layoutAnimation ?? AppStyle.fadeAnimation) { pickID = candidates.randomElement()?.id }
    }
}

// MARK: - Labels

/// The top labels as two rows of tiles on the page grid, the rest as a list on demand.
struct LabelBoard: View {
    let groups: [StatisticGroup]
    let total: Int
    let select: (StatisticGroup) -> Void
    @Environment(\.statisticsColumns) private var columns
    @State private var showsList = false

    private var boardCount: Int { columns * 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            if groups.isEmpty { Text("Keine Angaben vorhanden").font(.callout).foregroundStyle(.secondary) }
            let maximum = CGFloat(max(1, groups.first?.count ?? 1))
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                ForEach(Array(groups.prefix(boardCount).enumerated()), id: \.element.id) { index, group in
                    LabelTile(rank: index + 1, group: group, total: total, ratio: CGFloat(group.count) / maximum, select: select)
                }
            }
            if groups.count > boardCount {
                Button {
                    withAnimation(AppStyle.standardAnimation) { showsList.toggle() }
                } label: {
                    Label(showsList ? "Weitere Labels ausblenden" : "Alle \(groups.count) Labels", systemImage: showsList ? "chevron.up" : "chevron.down")
                }
                .appLinkButton().font(.caption)
                if showsList {
                    GroupStatisticsList(groups: Array(groups.dropFirst(boardCount)), total: total, columnCount: 2, select: select)
                        .transition(AppStyle.funnelTransition())
                }
            }
        }
    }

    private struct LabelTile: View {
        let rank: Int
        let group: StatisticGroup
        let total: Int
        let ratio: CGFloat
        let select: (StatisticGroup) -> Void
        @State private var hovering = false
        @State private var grown = false
        var body: some View {
            Button { select(group) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(rank)").font(.system(.caption, design: AppStyle.figureDesign, weight: .bold)).foregroundStyle(AppStyle.accent)
                        Text(group.name).font(.callout.weight(.medium)).lineLimit(1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(group.count.formatted()).font(.system(.title3, design: AppStyle.figureDesign, weight: .semibold)).monospacedDigit()
                        Text("\(group.count == 1 ? String(localized: "Platte") : String(localized: "Platten")) · \(group.percentage(of: total))").font(.caption).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule().fill(AppStyle.accent.opacity(hovering ? 1 : 0.65))
                            .frame(width: geo.size.width * ratio * (grown ? 1 : 0))
                    }
                    .frame(height: 4)
                }
                .padding(StatisticsLayout.tilePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .statisticsTile(hovering: hovering)
                .contentShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: hovering)
            .onAppear {
                if AppStyle.reduceMotion { grown = true } else { withAnimation(.smooth(duration: 0.7).delay(0.05)) { grown = true } }
            }
            .help("\(AppStyle.records(group.count)) von \(group.name) anzeigen")
        }
    }
}
