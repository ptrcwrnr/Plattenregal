import SwiftUI
import SwiftData
import Charts

enum StatisticsSection: String, CaseIterable, Identifiable {
    case overview, valueHistory, highlights, styles, artists, labels
    case years, acquisitions, recent

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Überblick"
        case .valueHistory: "Sammlungswert und Entwicklung"
        case .highlights: "Highlights"
        case .styles: "Styles"
        case .artists: "Häufigste Künstler"
        case .labels: "Labels"
        case .years: "Erscheinungsjahre"
        case .acquisitions: "Neuzugänge über Zeit"
        case .recent: "Zuletzt hinzugefügt"
        }
    }
    var compact: Bool {
        switch self {
        case .styles, .artists, .labels: true
        default: false
        }
    }
}

private struct StatisticsRow: Identifiable {
    let sections: [StatisticsSection]
    let compact: Bool
    var id: String { sections.map(\.rawValue).joined(separator: ",") }
}

struct StatisticsView: View {
    @Environment(\.modelContext) private var context
    let model: StatisticsViewModel
    @State private var market = MarketValueService.shared
    @State private var filter: StatisticGroup?
    @State private var opened: RecordCopy?
    @State private var additionsByYear = false
    @State private var reloadTask: Task<Void, Never>?
    @AppStorage("statisticsSectionOrder") private var savedSectionOrder = ""
    let showShelf: (RecordCopy) -> Void
    private let columns = [GridItem(.adaptive(minimum: 270), alignment: .top)]
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                header
                if let error = model.error {
                    AppBanner(message: error, kind: .warning)
                        .textSelection(.enabled)
                }
                if model.calculating { ProgressView("Lokale Statistik wird berechnet …").controlSize(.small) }
                Text("Bereiche am Griff ziehen, um sie anzuordnen. Die Reihenfolge bleibt gespeichert.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(sectionRows(for: geometry.size.width)) { row in
                    if row.compact {
                        HStack(alignment: .top, spacing: AppStyle.sectionSpacing) {
                            ForEach(row.sections) { section in
                                movableSection(section).frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            ForEach(0..<(compactColumnCount(for: geometry.size.width) - row.sections.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    } else if let section = row.sections.first {
                        movableSection(section)
                    }
                }
                if model.statistics.totalItems == 0 {
                    AppEmptyState("Noch keine Sammlung", systemImage: "opticaldisc", description: Text("Importiere deine Discogs Collection oder füge Schallplatten hinzu."))
                        .frame(height: 240)
                } else {
                    Text("Anteile beziehen sich auf Exemplare. Mehrere Styles, Künstler oder Labels pro Release werden einzeln gezählt; die Anteile können zusammen über 100 % liegen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Historische Werte sind Momentaufnahmen der damaligen Sammlung, keine Renditeberechnung.").font(.caption).foregroundStyle(.secondary)
            }.padding(AppStyle.pagePadding).frame(maxWidth: 1500, alignment: .leading).frame(maxWidth: .infinity)
        }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        // Loading starts eagerly at app launch (see RootView) so this page is
        // already populated by the time it's shown; no per-appearance reload here.
        .onChange(of: model.owner) { _, _ in Task { await model.reload(container: context.container) } }
        .onChange(of: DiscogsSyncService.shared.busy) { _, busy in if !busy { Task { await model.reload(container: context.container) } } }
        .onChange(of: market.busy) { _, busy in if !busy { Task { await model.reload(container: context.container) } } }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in
            guard !market.busy, !model.busy else { return }
            reloadTask?.cancel()
            reloadTask = Task {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                await model.reload(container: context.container)
            }
        }
        .onDisappear { reloadTask?.cancel() }
        .sheet(item: $filter) { group in
            VStack(spacing: 0) {
                AppSheetHeader(title: group.name, onClose: { filter = nil })
                CollectionView(mode: .all, query: "", showShelf: { copy in filter = nil; showShelf(copy) }, analyticsFilter: group)
            }.frame(minWidth: 850, minHeight: 650)
        }
        .sheet(item: $opened) { copy in RecordDetailView(copy: copy) { opened = nil; showShelf(copy) } }
    }
    private var orderedSections: [StatisticsSection] {
        let saved = savedSectionOrder.split(separator: ",").compactMap { StatisticsSection(rawValue: String($0)) }
        var seen: Set<StatisticsSection> = []
        return (saved + StatisticsSection.allCases).filter { seen.insert($0).inserted }
    }
    private func compactColumnCount(for width: CGFloat) -> Int {
        let available = min(max(0, width - 2 * AppStyle.pagePadding), 1500)
        return max(1, min(3, Int((available + AppStyle.sectionSpacing) / 290)))
    }
    private func sectionRows(for width: CGFloat) -> [StatisticsRow] {
        let count = compactColumnCount(for: width)
        let visible = orderedSections.filter { model.statistics.totalItems > 0 || $0 == .overview || $0 == .valueHistory }
        var rows: [StatisticsRow] = []
        var pending: [StatisticsSection] = []
        func flush() {
            if !pending.isEmpty { rows.append(StatisticsRow(sections: pending, compact: true)); pending.removeAll() }
        }
        for section in visible {
            if section.compact {
                pending.append(section)
                if pending.count == count { flush() }
            } else {
                flush()
                rows.append(StatisticsRow(sections: [section], compact: false))
            }
        }
        flush()
        return rows
    }
    private func moveSection(_ payload: String, to target: StatisticsSection) -> Bool {
        let prefix = "plattenregal-statistics:"
        guard payload.hasPrefix(prefix),
              let source = StatisticsSection(rawValue: String(payload.dropFirst(prefix.count))),
              source != target else { return false }
        var sections = orderedSections
        guard let sourceIndex = sections.firstIndex(of: source) else { return false }
        sections.remove(at: sourceIndex)
        guard let targetIndex = sections.firstIndex(of: target) else { return false }
        sections.insert(source, at: sourceIndex < targetIndex ? targetIndex + 1 : targetIndex)
        savedSectionOrder = sections.map(\.rawValue).joined(separator: ",")
        return true
    }
    private func movableSection(_ section: StatisticsSection) -> some View {
        StatisticsMovableArea(section: section, move: moveSection) {
            sectionContent(section)
        }
    }
    @ViewBuilder private func sectionContent(_ section: StatisticsSection) -> some View {
        switch section {
        case .overview: overview
        case .valueHistory:
            if !model.owner.isEmpty {
                ValueHistoryDashboard(snapshots: model.history)
            } else {
                DashboardCard(title: "Sammlungswert und Entwicklung") {
                    Text("Wähle eine synchronisierte Discogs Collection für den offiziellen Sammlungswert und die Wert-Historie.")
                        .foregroundStyle(.secondary)
                }
            }
        case .highlights: highlights
        case .styles: GroupStatisticsCard(title: "Styles", groups: model.statistics.styles, total: model.statistics.totalItems, select: select)
        case .artists: GroupStatisticsCard(title: "Häufigste Künstler", groups: model.statistics.artists, total: model.statistics.totalItems, select: select)
        case .labels: GroupStatisticsCard(title: "Labels", groups: model.statistics.labels, total: model.statistics.totalItems, select: select)
        case .years: years
        case .acquisitions: acquisitions
        case .recent: recentSection
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            AppPageHeading(title: "Deine Sammlung in Zahlen", subtitle: "Entdecken · Vergleichen · Entwicklung verfolgen")
            HStack(spacing: AppStyle.rowSpacing) {
                Button { Task { await model.refresh(container: context.container) } } label: {
                    Label("Statistik aktualisieren", systemImage: "arrow.clockwise")
                }.buttonStyle(.borderless).fixedSize().disabled(model.busy || DiscogsSyncService.shared.busy)
                Spacer(minLength: 0)
            }.padding(AppStyle.cardPadding).appControlSurface()
            if model.busy { ProgressView("Sammlungswert wird aktualisiert …").controlSize(.small) }
        }
    }
    private var overview: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 14) {
            MetricCard(title: "Schallplatten", value: model.statistics.totalItems.formatted(), symbol: "opticaldisc")
            MetricCard(title: "Eindeutige Releases", value: model.statistics.uniqueReleases.formatted(), symbol: "square.stack")
            MetricCard(title: "Künstler", value: model.statistics.artists.count.formatted(), symbol: "person.2")
            MetricCard(title: "Styles", value: model.statistics.styles.count.formatted(), symbol: "waveform")
            MetricCard(title: "Labels", value: model.statistics.labels.count.formatted(), symbol: "tag")
        }
    }
    private var highlights: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sammlung · Highlights").font(AppStyle.dialogTitle)
            LazyVGrid(columns: columns, alignment: .leading) {
                ForEach(model.statistics.highlights, id: \.self) { text in
                    Label(text, systemImage: "chart.bar.fill").font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding().background(.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
                }
            }
        }
    }
    private var years: some View {
        DashboardCard(title: "Erscheinungsjahre") {
            HStack {
                Text("Ältestes Release: \(model.statistics.oldest.map(String.init) ?? "—")")
                Spacer(); Text("Neuestes Release: \(model.statistics.newest.map(String.init) ?? "—")")
            }.foregroundStyle(.secondary)
            YearDistributionChart(groups: model.statistics.years, select: select)
            GroupStatisticsCard(title: "Jahre", groups: model.statistics.years, total: model.statistics.totalItems,
                                columnCount: 3, initialLimit: 30, select: select)
            Text("Jahr der konkreten Pressung · \(model.statistics.missingYear) ohne Jahr · \(model.statistics.missingStyle) ohne Style").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var acquisitions: some View {
        DashboardCard(title: "Neuzugänge über Zeit") {
            Picker("Gruppierung", selection: $additionsByYear) { Text("Monate").tag(false); Text("Jahre").tag(true) }.pickerStyle(.segmented).frame(maxWidth: 240)
            let bins = additionsByYear ? model.statistics.acquisitionYears : model.statistics.months
            if bins.isEmpty { Text("Noch keine bekannten Hinzufügedaten.").foregroundStyle(.secondary) }
            else {
                Chart(bins) { bin in
                    BarMark(x: .value("Datum", bin.date, unit: additionsByYear ? .year : .month), y: .value("Exemplare", bin.count))
                        .foregroundStyle(AppStyle.chartColors[0].gradient)
                }.frame(height: 200)
                if let peak = bins.max(by: { $0.count < $1.count }) {
                    Text("Meiste Neuzugänge: \(peak.date.formatted(.dateTime.year().month(.wide))) · \(peak.count) Exemplare").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Aus den Hinzufügedaten der aktuell enthaltenen Exemplare. Entfernte Collection-Einträge sind nicht enthalten.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var recentSection: some View {
        DashboardCard(title: "Zuletzt hinzugefügt") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                ForEach(model.statistics.recentlyAdded, id: \.self) { id in
                    if let copy = model.copies.first(where: { $0.id == id }) {
                        Button { opened = copy } label: {
                            StatisticsReleaseRow(copy: copy, showsAddedDate: true)
                                .padding(AppStyle.rowSpacing)
                                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private func select(_ group: StatisticGroup) { filter = group }

}
private struct StatisticsMovableArea<Content: View>: View {
    let section: StatisticsSection
    let move: (String, StatisticsSection) -> Bool
    @ViewBuilder let content: Content
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 26)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                    .contentShape(Rectangle())
                    .draggable("plattenregal-statistics:\(section.rawValue)")
                    .accessibilityLabel("\(section.title) verschieben")
                    .help("\(section.title) ziehen, um den Bereich anzuordnen")
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            return move(first, section)
        } isTargeted: { isTargeted = $0 }
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.controlRadius)
                .strokeBorder(isTargeted ? AppStyle.selectedBorder : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .animation(AppStyle.quickAnimation, value: isTargeted)
    }
}
struct StatisticsReleaseRow: View {
    let copy: RecordCopy
    var showsAddedDate = false
    var body: some View {
        HStack(spacing: 12) {
            CoverView(url: copy.release?.coverURL, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(copy.release?.artist ?? "Unbekannt").font(.headline).lineLimit(1)
                Text(copy.release?.title ?? "Unbekannte Veröffentlichung").lineLimit(1)
                if let year = copy.release?.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                if showsAddedDate {
                    let date = copy.discogsInstanceID == nil ? copy.dateAdded : AnalyticsItem.date(copy.discogsDateAdded)
                    Text(date.map { "Hinzugefügt am " + $0.formatted(date: .abbreviated, time: .omitted) } ?? "Datum unbekannt")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct DashboardCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            Text(title).font(AppStyle.sectionTitle)
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(AppStyle.cardPadding)
            .appGlassSurface(cornerRadius: AppStyle.cardRadius)
    }
}
struct MetricCard: View {
    let title: String
    let value: String
    let symbol: String
    var prominent = false
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            Label(title, systemImage: symbol).font(.callout).foregroundStyle(.secondary).frame(minHeight: 32, alignment: .top)
            Text(value).font(AppStyle.pageTitle).minimumScaleFactor(0.65).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(AppStyle.cardPadding)
            .background(prominent ? AppStyle.selectedBackground : Color.clear, in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            .appGlassSurface(cornerRadius: AppStyle.cardRadius)
    }
}
struct GroupStatisticsCard: View {
    let title: String
    let groups: [StatisticGroup]
    let total: Int
    var columnCount = 1
    var initialLimit = 10
    let select: (StatisticGroup) -> Void
    @State private var expanded = false
    var body: some View {
        DashboardCard(title: title) {
            if groups.isEmpty { Text("Keine Angaben vorhanden").foregroundStyle(.secondary) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: columnCount), spacing: 18) {
            ForEach(expanded ? groups : Array(groups.prefix(initialLimit))) { group in
                Button { select(group) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(group.name).lineLimit(2); Spacer()
                            Text("\(group.count)").monospacedDigit().bold()
                            Text(group.percentage(of: total)).foregroundStyle(.secondary).frame(minWidth: 34, alignment: .trailing)
                        }
                        GeometryReader { geo in
                            Capsule().fill(.tint.opacity(0.16))
                            Capsule().fill(.tint).frame(width: geo.size.width * CGFloat(group.count) / CGFloat(max(1, groups.map(\.count).max() ?? 1)))
                        }.frame(height: 4)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).help("\(group.count) Exemplare mit \(group.name) anzeigen")
            }
            }
            if groups.count > initialLimit { Button(expanded ? "Weniger anzeigen" : "Alle \(groups.count) anzeigen") { expanded.toggle() }.font(.caption) }
        }
    }
}
struct YearDistributionChart: View {
    let groups: [StatisticGroup]
    let select: (StatisticGroup) -> Void
    var body: some View {
        Chart(groups) { group in
            BarMark(x: .value("Jahr", Int(group.id) ?? 0), y: .value("Exemplare", group.count))
                .foregroundStyle(AppStyle.chartColors[1].gradient)
        }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { value in
            AxisGridLine(); AxisTick(); AxisValueLabel { if let year = value.as(Int.self) { Text(String(year)) } }
        }}.chartXScale(domain: domain).frame(height: 220)
            .chartOverlay { proxy in GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle()).onTapGesture { point in
                    guard let frame = proxy.plotFrame else { return }
                    let x = point.x - geometry[frame].minX
                    if let year: Int = proxy.value(atX: x), let group = groups.min(by: { abs((Int($0.id) ?? 0) - year) < abs((Int($1.id) ?? 0) - year) }) { select(group) }
                }
            }}
    }
    private var domain: ClosedRange<Int> {
        let years = groups.compactMap { Int($0.id) }
        return ((years.min() ?? 1990) - 1)...((years.max() ?? 2026) + 1)
    }
}
