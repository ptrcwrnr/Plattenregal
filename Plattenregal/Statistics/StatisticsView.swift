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
    /// Shown or not, without re-rendering every card on each page switch.
    @State private var activity = PageActivity()
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
        .background { AmbientBackdrop(covers: ambientCovers) }
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
            guard activity.isActive else { stale = true; return }
            reloadTask?.cancel()
            reloadTask = Task {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                await model.reload(container: context.container)
            }
        }
        // Token stored or removed in the settings window: this page stays
        // shown meanwhile, so it wouldn't notice on its own.
        .onChange(of: DiscogsSyncService.shared.tokenRevision) { _, _ in model.updateTokenState() }
        .trackPageActivity(activity) { active in
            if active { model.updateTokenState() }
            guard active, stale else { return }
            stale = false
            Task { await model.reload(container: context.container) }
        }
        .onDisappear { reloadTask?.cancel() }
        // The model already let go of its records (see `StatisticsViewModel.forget`).
        .onReceive(NotificationCenter.default.publisher(for: .plattenregalDidReset)) { _ in
            opened = nil; filter = nil
            // The Discogs account is gone as well.
            Task { await model.initialLoad(container: context.container) }
        }
        .sheet(item: $filter) { group in
            VStack(spacing: 0) {
                AppSheetHeader(title: group.name, onClose: { filter = nil })
                CollectionView(showShelf: { copy in filter = nil; showShelf(copy) }, analyticsFilter: group)
            }.frame(minWidth: 850, minHeight: 650)
        }
        .sheet(item: $opened) { copy in RecordDetailView(copy: copy) { opened = nil; showShelf(copy) } }
    }

    /// Behind the page: the covers of the latest additions.
    private var ambientCovers: [String] {
        Array(model.statistics.recentlyAdded.lazy.compactMap { model.copiesByID[$0]?.release?.coverURL }.prefix(3))
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
        GlassSegmentedPicker(selection: selection.animation(AppStyle.standardAnimation), options: options.map(\.1), small: true) { value in
            Text(options.first { $0.1 == value }?.0 ?? "")
        }
        .accessibilityLabel("Ansicht")
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
/// reordering) and content on a Liquid Glass surface.
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
                      ? AnyShapeStyle(LinearGradient(colors: [AppStyle.accent.opacity(0.07), AppStyle.accent.opacity(0.0)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.clear))
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
        .appGlassSurface(cornerRadius: AppStyle.controlRadius)
        // The glass brings its own edge; a frame only marks the drop target.
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.controlRadius)
                .strokeBorder(AppStyle.selectedBorder.opacity(isTargeted ? 1 : 0), lineWidth: 2)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            return move(first, section)
        } isTargeted: { isTargeted = $0 }
        .animation(AppStyle.quickAnimation, value: isTargeted)
    }
}

/// Cover URL a card's content wants blurred behind the card.
struct StatisticsBackdropKey: PreferenceKey {
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
