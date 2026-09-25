import SwiftUI
import SwiftData
import Charts

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
        case .overview: "Deine Sammlung"
        case .highlights: "Auf einen Blick"
        case .valueHistory: "Sammlungswert im Verlauf"
        case .sound: "Klangbild"
        case .artists: "Top-Künstler"
        case .labels: "Labels"
        case .discover: "Zufallsfund"
        case .years: "Zeitreise"
        case .acquisitions: "Neuzugänge"
        case .recent: "Zuletzt hinzugefügt"
        }
    }
    var systemImage: String {
        switch self {
        case .overview: "opticaldisc"
        case .highlights: "sparkles"
        case .valueHistory: "chart.line.uptrend.xyaxis"
        case .sound: "waveform"
        case .artists: "music.mic"
        case .labels: "tag"
        case .discover: "dice"
        case .years: "clock.arrow.circlepath"
        case .acquisitions: "calendar.badge.plus"
        case .recent: "clock"
        }
    }
}

/// One grid for the whole page: the same gutter between cards, inside cards
/// and between columns, and one column count shared by every tiled row
/// (figures, facts, artists, recent records), so tiles line up across cards.
enum StatisticsLayout {
    static let gutter: CGFloat = 20
    static let tilePadding: CGFloat = 12
    static let titleSpacing: CGFloat = 16
    static let maxWidth: CGFloat = 1200
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

/// Statistics as a set of calm, interactive cards: a hero with the collection
/// value, hoverable charts that explain themselves on mouse-over, a record
/// podium for the top artists and a random pick from the shelf. Everything
/// clickable opens the matching records. Cards can be reordered by dragging
/// their title.
struct StatisticsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.isActivePage) private var isActivePage
    /// Something was saved while the page was hidden; reload when it's shown.
    @State private var stale = false
    let model: StatisticsViewModel
    @State private var filter: StatisticGroup?
    @State private var opened: RecordCopy?
    @State private var reloadTask: Task<Void, Never>?
    /// `busy` and `isRunning` often end together after a sync; one reload is enough.
    @State private var syncReloadTask: Task<Void, Never>?
    @State private var soundDimension: SoundDimension = .styles
    @State private var yearsByDecade = true
    @State private var additionsByYear = false
    @AppStorage(DisplaySettings.statisticsOrderKey) private var savedSectionOrder = ""
    let showShelf: (RecordCopy) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: StatisticsLayout.gutter) {
                    if DemoMode.isActive { DemoBanner() }
                    if let error = model.error {
                        // Dismissable: a failed value refresh shouldn't sit above the
                        // page until the next successful one.
                        AppBanner(message: error, kind: .warning, onDismiss: { model.error = nil })
                            .textSelection(.enabled)
                            .transition(AppStyle.funnelTransition())
                    }
                    ForEach(visibleSections) { section in
                        movableSection(section)
                    }
                    // Only once loaded: before the first calculation the count is 0 too.
                    if model.version > 0 && model.statistics.totalItems == 0 {
                        AppEmptyState("Noch keine Sammlung", systemImage: "opticaldisc", description: Text(DemoMode.isActive ? DemoMode.emptyHint : "Die Statistik entsteht aus deiner Discogs-Collection. Trage den Token in den Einstellungen ein und synchronisiere."))
                            .frame(height: 240)
                    }
                    footnotes.padding(.top, AppStyle.itemSpacing)
                }
                .padding(.horizontal, AppStyle.pagePadding + 4)
                .padding(.vertical, AppStyle.pagePadding)
                .frame(maxWidth: StatisticsLayout.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .environment(\.statisticsColumns, StatisticsLayout.columnCount(contentWidth: cardContentWidth(for: geometry.size.width)))
                .animation(AppStyle.standardAnimation, value: model.error)
            }
            .pullToRefresh(disabled: refreshBlocked, action: refresh)
            .overlay(alignment: .top) { activityPill }
        }
        // Loading starts eagerly at app launch (see RootView) so this page is
        // already populated by the time it's shown; no per-appearance reload here.
        .onChange(of: model.owner) { _, _ in Task { await model.reload(container: context.container) } }
        // After a sync: the account may be new or changed, and the numbers are.
        // Once more when the tracklist download after it is through (countries).
        .onChange(of: DiscogsSyncService.shared.busy) { _, busy in if !busy { reloadAfterSync() } }
        .onChange(of: DiscogsSyncService.shared.isRunning) { _, running in if !running { reloadAfterSync() } }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { _ in
            // During a sync and its tracklist download the store saves every few
            // seconds; recomputing everything each time would only stutter.
            // The sync's end reloads once (above).
            guard !model.busy, !DiscogsSyncService.shared.isRunning else { return }
            // Hidden (e.g. while sorting records on the shelf page): don't
            // recompute the whole collection after every single move — once
            // when the page is shown again is enough.
            guard isActivePage else { stale = true; return }
            reloadTask?.cancel()
            reloadTask = Task {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                await model.reload(container: context.container)
            }
        }
        // Token stored or removed in the settings window: this page stays
        // shown meanwhile, so it wouldn't notice on its own.
        .onChange(of: DiscogsSyncService.shared.tokenRevision) { _, _ in model.updateTokenState() }
        .onChange(of: isActivePage) { _, active in
            if active { model.updateTokenState() }
            guard active, stale else { return }
            stale = false
            Task { await model.reload(container: context.container) }
        }
        .onDisappear { reloadTask?.cancel() }
        .sheet(item: $filter) { group in
            VStack(spacing: 0) {
                AppSheetHeader(title: group.name, onClose: { filter = nil })
                CollectionView(showShelf: { copy in filter = nil; showShelf(copy) }, analyticsFilter: group)
            }.frame(minWidth: 850, minHeight: 650)
            .environment(\.gridReferenceWidth, nil)
        }
        .sheet(item: $opened) { copy in RecordDetailView(copy: copy) { opened = nil; showShelf(copy) } }
    }

    private var refreshBlocked: Bool { model.busy || DiscogsSyncService.shared.busy }
    private func reloadAfterSync() {
        syncReloadTask?.cancel()
        syncReloadTask = Task {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let before = model.owner
            await model.resolveOwner(container: context.container)
            // A changed owner already reloads via `onChange(of: model.owner)`.
            if model.owner == before { await model.reload(container: context.container) }
        }
    }
    private func refresh() {
        guard !refreshBlocked else { return }
        Task { await model.refresh(container: context.container) }
    }

    /// Floating status while the collection value is refreshed or recalculated.
    @ViewBuilder private var activityPill: some View {
        if model.busy || model.calculating {
            HStack(spacing: AppStyle.itemSpacing) {
                ProgressView().controlSize(.small)
                Text(model.busy ? "Sammlungswert wird aktualisiert …" : "Wird berechnet …")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .appGlassSurface(cornerRadius: 20)
            .padding(.top, 12)
            .transition(AppStyle.funnelTransition())
            .allowsHitTesting(false)
        }
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.statistics.totalItems > 0 {
                Text("Anteile beziehen sich auf Exemplare. Mehrere Styles, Künstler oder Labels pro Release werden einzeln gezählt; die Anteile können zusammen über 100 % liegen.")
            }
            Text("Historische Werte sind Momentaufnahmen der damaligen Sammlung, keine Renditeberechnung.")
            Text("Bereiche lassen sich am Titel ziehen, um sie anzuordnen. Diagramme zeigen Details beim Überfahren, ein Klick öffnet die Platten.")
            Text("Zum Aktualisieren die Seite nach unten ziehen (Trackpad oder mit gedrückter Maustaste) oder ⌘R drücken.")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    /// Content width of a full-width card for a page `width` wide.
    private func cardContentWidth(for width: CGFloat) -> CGFloat {
        min(max(0, width - 2 * (AppStyle.pagePadding + 4)), StatisticsLayout.maxWidth) - 2 * StatisticsLayout.gutter
    }
    private var orderedSections: [StatisticsSection] { StatisticsSection.ordered(from: savedSectionOrder) }
    private var visibleSections: [StatisticsSection] {
        orderedSections.filter { model.statistics.totalItems > 0 || $0 == .overview || $0 == .valueHistory }
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
        StatisticsMovableArea(section: section, prominent: section == .overview, accessory: accessory(for: section), move: moveSection) {
            sectionContent(section)
        }
    }
    /// Controls that sit on the right of a card's title row.
    private func accessory(for section: StatisticsSection) -> AnyView? {
        switch section {
        case .sound: AnyView(segmented($soundDimension, SoundDimension.allCases.map { ($0.rawValue, $0) }))
        case .years: AnyView(segmented($yearsByDecade, [("Jahrzehnte", true), ("Jahre", false)]))
        case .acquisitions: AnyView(segmented($additionsByYear, [("Monate", false), ("Jahre", true)]))
        default: nil
        }
    }
    private func segmented<Value: Hashable>(_ selection: Binding<Value>, _ options: [(String, Value)]) -> some View {
        Picker("Ansicht", selection: selection.animation(AppStyle.standardAnimation)) {
            ForEach(options, id: \.0) { Text($0.0).tag($0.1) }
        }
        .pickerStyle(.segmented).labelsHidden().controlSize(.small).fixedSize()
    }
    @ViewBuilder private func sectionContent(_ section: StatisticsSection) -> some View {
        switch section {
        case .overview: StatisticsHero(statistics: model.statistics, history: model.history, hasOwner: !model.owner.isEmpty, hasToken: model.hasToken)
        case .highlights: StatisticsFacts(statistics: model.statistics, select: select)
        case .valueHistory:
            if !model.owner.isEmpty {
                ValueHistoryDashboard(snapshots: model.history)
            } else {
                Text("Sammlungswert und Verlauf erscheinen, sobald deine Discogs-Collection synchronisiert ist.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .sound: SoundDonut(statistics: model.statistics, dimension: soundDimension, select: select)
        case .artists: ArtistPodium(groups: model.statistics.artists, total: model.statistics.totalItems, copies: model.copiesByID, select: select)
        case .labels: LabelBoard(groups: model.statistics.labels, total: model.statistics.totalItems, select: select)
        case .discover: RandomRecordCard(copies: model.copies, version: model.version, open: open, showShelf: showShelf)
        case .years: TimeTravel(statistics: model.statistics, byDecade: yearsByDecade, select: select)
        case .acquisitions: AcquisitionChart(statistics: model.statistics, byYear: additionsByYear)
        case .recent: recentSection
        }
    }
    private var recentSection: some View {
        RecentRecords(copies: model.statistics.recentlyAdded.compactMap { model.copiesByID[$0] }, open: open)
    }
    private func select(_ group: StatisticGroup) { filter = group }
    /// The page's records come from the view model's own read context. The
    /// detail sheet (and the editor inside it) saves through the app's main
    /// context, so hand it the same record from there — edits made on the
    /// read-context copy would silently never be saved.
    private func open(_ copy: RecordCopy) {
        opened = context.model(for: copy.persistentModelID) as? RecordCopy
    }
}

// MARK: - Card chrome

/// A card on the statistics page: its title (also the drag handle for
/// reordering) and content on a quiet rounded surface.
private struct StatisticsMovableArea<Content: View>: View {
    let section: StatisticsSection
    var prominent = false
    var accessory: AnyView?
    let move: (String, StatisticsSection) -> Bool
    @ViewBuilder let content: Content
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            // Fixed-height title row, so content starts at the same height in every card.
            HStack(spacing: StatisticsLayout.gutter) {
                Label(section.title, systemImage: section.systemImage)
                    .font(AppStyle.sectionTitle)
                    .labelStyle(SectionTitleLabelStyle())
                    .lineLimit(1)
                    .draggable("plattenregal-statistics:\(section.rawValue)")
                    .help("Am Titel ziehen, um den Bereich anzuordnen")
                    .accessibilityHint("Ziehen, um den Bereich zu verschieben")
                Spacer(minLength: 0)
                accessory
            }
            .frame(height: 28)
            content
        }
        .padding(StatisticsLayout.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: AppStyle.controlRadius)
                .fill(prominent
                      ? AnyShapeStyle(LinearGradient(colors: [AppStyle.accent.opacity(0.16), AppStyle.accent.opacity(0.03)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.primary.opacity(0.03)))
        }
        .backgroundPreferenceValue(StatisticsBackdropKey.self) { url in
            // A card's content can ask for a blurred cover behind the whole card.
            if let url {
                GeometryReader { geometry in
                    let edge = max(geometry.size.width, geometry.size.height)
                    CoverView(url: url, size: edge)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .blur(radius: 60)
                        .opacity(0.35)
                }
                .transition(.opacity)
                .id(url)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.controlRadius)
                .strokeBorder(isTargeted ? AppStyle.selectedBorder : AppStyle.borderColor, lineWidth: isTargeted ? 2 : 1)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            return move(first, section)
        } isTargeted: { isTargeted = $0 }
        .animation(AppStyle.quickAnimation, value: isTargeted)
    }
}

/// Cover URL a card's content wants blurred behind the card.
private struct StatisticsBackdropKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) { value = value ?? nextValue() }
}

private struct SectionTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.callout.weight(.semibold)).foregroundStyle(AppStyle.accent)
            configuration.title
        }
    }
}

/// Categorical colors for the donut; the last slot is reserved for "Weitere".
enum StatisticsPalette {
    static let colors: [Color] = [.blue, .teal, .indigo, .purple, .pink, .orange, .mint]
    static let other = Color.gray.opacity(0.5)
}

// MARK: - Hero

/// Numbers that roll into place instead of just appearing.
struct RollingNumber: View {
    let value: Double
    let format: (Double) -> String
    @State private var shown: Double = 0
    var body: some View {
        Text(format(shown))
            .monospacedDigit()
            .contentTransition(.numericText(value: shown))
            .onAppear { update() }
            .onChange(of: value) { _, _ in update() }
    }
    private func update() {
        if AppStyle.reduceMotion { shown = value } else { withAnimation(.smooth(duration: 0.8)) { shown = value } }
    }
}

private struct StatisticsHero: View {
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
                figure("Schallplatten", statistics.totalItems, "opticaldisc")
                figure("Releases", statistics.uniqueReleases, "square.stack")
                figure("Künstler", statistics.artists.count, "music.mic")
                figure("Styles", statistics.styles.count, "waveform")
                figure("Labels", statistics.labels.count, "tag")
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
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 10) {
                    if sameCurrency.count >= 2 { DeltaChip(current: latest.medianValue, previous: sameCurrency[sameCurrency.count - 2].medianValue, currency: latest.currency) }
                    Text("Spanne \(DiscogsMoney.format(latest.minimumValue, currency: latest.currency)) – \(DiscogsMoney.format(latest.maximumValue, currency: latest.currency))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(([latest.averagePerItem.map { "≈ \(DiscogsMoney.format($0, currency: latest.currency)) pro Platte" }]
                      + ["Stand \(latest.date.formatted(date: .abbreviated, time: .shortened))"]).compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Schallplatten in der Sammlung").font(.callout).foregroundStyle(.secondary)
                RollingNumber(value: Double(statistics.totalItems)) { Int($0.rounded()).formatted() }
                    .font(.system(size: 44, weight: .bold, design: .rounded))
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
                .background(AppStyle.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                RollingNumber(value: Double(value)) { Int($0.rounded()).formatted() }
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(StatisticsLayout.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
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
                Text("(" + (percent > 0 ? "+" : "") + (percent / 100).formatted(.percent.precision(.fractionLength(1))) + ")")
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

private struct StatisticsFacts: View {
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
            facts.append(.init(title: "Häufigster Künstler", value: artist.name, detail: "\(AppStyle.records(artist.count)) · \(artist.percentage(of: total))", systemImage: "music.mic", color: .blue, group: artist))
        }
        if let style = statistics.styles.first {
            facts.append(.init(title: "Häufigster Style", value: style.name, detail: "\(AppStyle.records(style.count)) · \(style.percentage(of: total))", systemImage: "waveform", color: .teal, group: style))
        }
        if let decade = statistics.decades.max(by: { $0.count < $1.count }) {
            facts.append(.init(title: "Stärkstes Jahrzehnt", value: decade.name, detail: "\(AppStyle.records(decade.count))", systemImage: "calendar", color: .indigo, group: decade))
        }
        if let year = statistics.years.max(by: { $0.count < $1.count }) {
            facts.append(.init(title: "Häufigstes Jahr", value: year.name, detail: "\(AppStyle.records(year.count))", systemImage: "star", color: .purple, group: year))
        }
        let thisYear = Calendar.current.component(.year, from: .now)
        // Compared with the same stretch of last year, not all of it: early in
        // the year a whole previous year would always look like much more.
        let current = statistics.addedThisYear, previous = statistics.addedLastYearToDate
        let comparison = current > previous ? "\(current - previous) mehr als im Vorjahreszeitraum"
            : current < previous ? "\(previous - current) weniger als im Vorjahreszeitraum"
            : "genauso viele wie im Vorjahreszeitraum"
        let period = Date.now.formatted(.dateTime.day().month(.abbreviated))
        facts.append(.init(title: "Neu in \(thisYear)", value: "\(AppStyle.records(current))", detail: comparison, systemImage: "plus.circle", color: .orange,
                           help: "1. Jan. bis \(period): \(current) in \(thisYear), \(previous) in \(thisYear - 1)"))
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
                        Image(systemName: fact.systemImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(fact.color)
                            .frame(width: 28, height: 28)
                            .background(fact.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
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
                .background(hovering && fact.group != nil ? fact.color.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
                .contentShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            }
            .buttonStyle(.plain)
            // Tiles without records to open still take the pointer for their tooltip.
            .allowsHitTesting(fact.group != nil || fact.help != nil)
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: hovering)
            .help(fact.help ?? fact.group.map { "\(AppStyle.records($0.count)) mit \($0.name) anzeigen" } ?? "")
        }
    }
}

// MARK: - Sound donut

private enum SoundDimension: String, CaseIterable, Identifiable {
    case genres = "Genres", styles = "Styles", formats = "Formate", countries = "Länder"
    var id: String { rawValue }
}

/// Interactive donut: hovering a slice (or its legend row) highlights it and
/// shows its share in the middle, clicking opens the records.
private struct SoundDonut: View {
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
        let top = groups.prefix(StatisticsPalette.colors.count)
        var result = top.enumerated().map { index, group in
            Slice(group: group, label: display(group.name), color: StatisticsPalette.colors[index])
        }
        let rest = groups.dropFirst(top.count)
        if !rest.isEmpty {
            let union = rest.reduce(into: Set<UUID>()) { $0.formUnion($1.copyIDs) }
            result.append(Slice(group: StatisticGroup(id: "weitere:\(dimension.rawValue)", name: "Weitere \(dimension.rawValue) (\(rest.count))", copyIDs: union),
                                label: "Weitere (\(rest.count))", color: StatisticsPalette.other))
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
                            Text("\(AppStyle.records(missing)) ohne Angabe\(dimension == .countries ? " – Länder kommen mit den Tracklisten von Discogs" : "")")
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
                    .font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(slice.color)
                Text(slice.label).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                Text("\(AppStyle.records(slice.group.count))").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 2) {
                // All of them, including those under "Weitere".
                Text("\(groups.count)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(dimension.rawValue).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ slices: [Slice]) -> some View {
        let maximum = CGFloat(max(1, slices.map(\.group.count).max() ?? 1))
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(slices) { slice in
                Button { select(slice.group) } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(slice.color).frame(width: 10, height: 10)
                        Text(slice.label).lineLimit(1)
                        Spacer(minLength: 8)
                        Capsule().fill(slice.color.opacity(0.5))
                            .frame(width: 70 * CGFloat(slice.group.count) / maximum, height: 4)
                            .frame(width: 70, alignment: .leading)
                        Text("\(slice.group.count)").monospacedDigit().frame(minWidth: 36, alignment: .trailing)
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
private struct ArtistPodium: View {
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
                .buttonStyle(.link).font(.caption)
                if showsList {
                    GroupStatisticsList(groups: Array(groups.dropFirst(podiumCount)), total: total, columnCount: 2, select: select)
                        .transition(AppStyle.funnelTransition())
                }
            }
        }
    }

    /// A stable representative cover: the first copy (by ID) that has one.
    private func cover(for group: StatisticGroup) -> String? {
        group.copyIDs.compactMap { copies[$0] }
            .filter { $0.release?.coverURL != nil }
            .min { $0.id.uuidString < $1.id.uuidString }?
            .release?.coverURL
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
                    CoverView(url: cover, size: nil)
                        .overlay(alignment: .topLeading) {
                            Text("\(rank)")
                                .font(.system(.callout, design: .rounded, weight: .bold))
                                .foregroundStyle(rank == 1 ? .white : .primary)
                                .frame(width: 28, height: 28)
                                .background(rank == 1 ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.regularMaterial), in: Circle())
                                .padding(6)
                        }
                        .shadow(color: .black.opacity(hovering ? 0.25 : 0.1), radius: hovering ? 10 : 4, y: hovering ? 6 : 2)
                        .scaleEffect(hovering ? 1.03 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.name).font(.callout.weight(.medium)).lineLimit(1)
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
private struct RandomRecordCard: View {
    let copies: [RecordCopy]
    /// `StatisticsViewModel.version`: the shelf labels are recomputed on it,
    /// not on every render.
    let version: Int
    let open: (RecordCopy) -> Void
    let showShelf: (RecordCopy) -> Void
    @Environment(\.statisticsColumns) private var columns
    @State private var shelfLabels = ShelfLabels()
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
                            .frame(width: min(coverWidth, 380))
                            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .help("Details anzeigen")
                    .frame(width: coverWidth, alignment: .leading)
                    details(pick, release)
                }
                .id(pick.id)
                .transition(AppStyle.reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                           removal: .move(edge: .leading).combined(with: .opacity)))
                .preference(key: StatisticsBackdropKey.self, value: release.coverURL)
            } else {
                Text("Noch keine Platten zum Ziehen.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        // Whenever the pick is gone (first load, or a sync removed it) and
        // there is something to pick — not only when the count changes.
        .task(id: [version, labelStyle.hashValue]) {
            if pick == nil { pickID = copies.randomElement()?.id }
            shelfLabels = ShelfRangeLabels.compute(for: shelves, style: labelStyle)
        }
    }

    private func details(_ pick: RecordCopy, _ release: Release) -> some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.gutter) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Heute aus deiner Sammlung").font(.caption.weight(.semibold)).foregroundStyle(AppStyle.accent)
                Text(release.displayArtist)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(2)
                Text(release.displayTitle).font(.title2).foregroundStyle(.secondary).lineLimit(2)
            }
            // Same columns as the page grid to the right of the cover.
            LazyVGrid(columns: StatisticsLayout.columns(max(1, columns - coverSpan)), alignment: .leading, spacing: 14) {
                detail("Jahr", release.year.map(String.init))
                detail("Label", release.displayLabel)
                detail("Land", release.country)
                detail("Format", release.format)
                detail("Tracks", release.tracks.isEmpty ? nil : "\(release.tracks.count)")
                detail("Fach", ShelfRangeLabels.location(of: pick, labels: shelfLabels,
                                                         excluded: exclusions.contains { $0.copyID == pick.id }))
            }
            if !release.styles.isEmpty {
                HStack(spacing: 6) { ForEach(release.styles.prefix(4), id: \.self) { AppBadge(title: $0) } }
            }
            HStack(spacing: AppStyle.itemSpacing) {
                Button { reroll() } label: {
                    Label("Neue Platte ziehen", systemImage: "dice")
                        .symbolEffect(.bounce, value: rolls)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Neue Platte ziehen (⇧⌘R)")
                SecondaryButton(title: pick.shelf == nil ? "Platz im Regal finden" : "Im Regal zeigen") { showShelf(pick) }
                GhostButton(title: "Details") { open(pick) }
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

    private func reroll() {
        rolls += 1
        let candidates = copies.count > 1 ? copies.filter { $0.id != pick?.id } : copies
        withAnimation(AppStyle.layoutAnimation ?? AppStyle.fadeAnimation) { pickID = candidates.randomElement()?.id }
    }
}

// MARK: - Labels

/// The top labels as two rows of tiles on the page grid, the rest as a list on demand.
private struct LabelBoard: View {
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
                .buttonStyle(.link).font(.caption)
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
                        Text("\(rank)").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(AppStyle.accent)
                        Text(group.name).font(.callout.weight(.medium)).lineLimit(1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(group.count)").font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                        Text("\(group.count == 1 ? "Platte" : "Platten") · \(group.percentage(of: total))").font(.caption).foregroundStyle(.secondary)
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
                .background(hovering ? AppStyle.accent.opacity(0.08) : Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
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

// MARK: - Bars

/// Bar chart that explains each bar on hover and optionally opens it on click.
struct HoverBarChart: View {
    struct Bar: Identifiable {
        let id: String
        let label: String
        let count: Int
        var group: StatisticGroup?
    }
    let bars: [Bar]
    var height: CGFloat = 200
    var unit = "Platten"
    var select: ((StatisticGroup) -> Void)?
    @State private var hovered: String?

    var body: some View {
        let step = max(1, Int((Double(bars.count) / 10).rounded(.up)))
        Chart(bars) { bar in
            BarMark(x: .value("Zeitraum", bar.id), y: .value(unit, bar.count))
                .cornerRadius(3)
                .foregroundStyle(hovered == bar.id
                                 ? AnyShapeStyle(AppStyle.accent)
                                 : AnyShapeStyle(LinearGradient(colors: [AppStyle.accent.opacity(hovered == nil ? 0.85 : 0.35), AppStyle.accent.opacity(hovered == nil ? 0.45 : 0.18)],
                                                                startPoint: .top, endPoint: .bottom)))
                .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    if hovered == bar.id {
                        VStack(spacing: 0) {
                            Text(bar.label).font(.caption.weight(.semibold))
                            Text(unit == "Platten" ? AppStyle.records(bar.count) : "\(bar.count) \(unit)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppStyle.borderColor))
                    }
                }
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
                            hovered = proxy.value(atX: point.x - geometry[frame].minX, as: String.self)
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

private struct TimeTravel: View {
    let statistics: CollectionStatistics
    let byDecade: Bool
    let select: (StatisticGroup) -> Void
    @Environment(\.statisticsColumns) private var columns

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                span("Ältestes Release", statistics.oldest)
                span("Neuestes Release", statistics.newest)
                span("Jahre Musikgeschichte", statistics.oldest.flatMap { oldest in statistics.newest.map { $0 - oldest } })
            }
            HoverBarChart(bars: bars, height: 220, select: select)
            Text("Jahr der konkreten Pressung · \(statistics.missingYear) ohne Jahr · \(statistics.missingStyle) ohne Style")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func span(_ title: String, _ year: Int?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(year.map(String.init) ?? "—").font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Continuous years/decades, including empty ones, so gaps stay visible.
    private var bars: [HoverBarChart.Bar] {
        let source = byDecade ? statistics.decades : statistics.years
        let byKey = Dictionary(source.map { (Int($0.id.prefix(4)) ?? 0, $0) }, uniquingKeysWith: { first, _ in first })
        guard let low = byKey.keys.min(), let high = byKey.keys.max() else { return [] }
        return stride(from: low, through: high, by: byDecade ? 10 : 1).map { key in
            let label = byDecade ? "\(key)er" : String(key)
            return .init(id: label, label: label, count: byKey[key]?.count ?? 0, group: byKey[key])
        }
    }
}

private struct AcquisitionChart: View {
    let statistics: CollectionStatistics
    let byYear: Bool
    @Environment(\.statisticsColumns) private var columns

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                if let peak = source.max(by: { $0.count < $1.count }) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(AppStyle.records(peak.count))").font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
                        Text("Rekord: \(peak.date.formatted(byYear ? .dateTime.year() : .dateTime.year().month(.wide)))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(AppStyle.records(source.reduce(0) { $0 + $1.count }))").font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
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
            guard let next = calendar.date(byAdding: component, value: 1, to: date) else { break }
            date = next
        }
        return bars
    }
}

// MARK: - Shared rows

/// A record as a cover with artist, title and (optionally) the date it was added.
/// The ten latest additions on the shared column grid (two rows at full width).
private struct RecentRecords: View {
    let copies: [RecordCopy]
    let open: (RecordCopy) -> Void
    @Environment(\.statisticsColumns) private var columns
    var body: some View {
        LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
            ForEach(copies.prefix(10)) { copy in
                Button { open(copy) } label: { CoverTile(copy: copy, showsAddedDate: true) }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct CoverTile: View {
    let copy: RecordCopy
    /// `nil` fills the available width (grid cells).
    var size: CGFloat?
    var showsAddedDate = false
    @State private var hovering = false
    var body: some View {
        let artist = copy.release?.displayArtist ?? "Unbekannt"
        let title = copy.release?.displayTitle ?? "Unbekannte Veröffentlichung"
        VStack(alignment: .leading, spacing: 6) {
            CoverView(url: copy.release?.coverURL, size: size)
                .shadow(color: .black.opacity(hovering ? 0.25 : 0.1), radius: hovering ? 10 : 4, y: hovering ? 6 : 2)
                .scaleEffect(hovering ? 1.04 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(artist).font(.callout.weight(.medium)).lineLimit(1)
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if showsAddedDate {
                    let date = DiscogsDate.parse(copy.discogsDateAdded)
                    Text(date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Datum unbekannt")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, alignment: .leading)
        .frame(maxWidth: size == nil ? .infinity : nil, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .topLeading), count: columnCount), spacing: 4) {
                ForEach(expanded ? groups : Array(groups.prefix(initialLimit))) { group in
                    GroupRow(group: group, total: total, ratio: CGFloat(group.count) / maximum, select: select)
                }
            }
            if groups.count > initialLimit {
                Button(expanded ? "Weniger anzeigen" : "Alle \(groups.count) anzeigen") {
                    withAnimation(AppStyle.standardAnimation) { expanded.toggle() }
                }
                .buttonStyle(.link).font(.caption)
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(group.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(group.count)").monospacedDigit()
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
                .padding(.vertical, 5)
                // The hover tint bleeds outward so names stay flush with the card title.
                .background(hovering ? AppStyle.hoverBackground : .clear, in: RoundedRectangle(cornerRadius: 8).inset(by: -6))
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
