import SwiftUI
import SwiftData
import Charts

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
                    if DemoMode.showsBanner { DemoBanner() }
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
                        AppEmptyState(String(localized: "Noch keine Sammlung"), systemImage: "opticaldisc", description: Text(DemoMode.isActive ? DemoMode.emptyHint : String(localized: "Die Statistik entsteht aus deiner Discogs-Collection. Trage den Token in den Einstellungen ein und synchronisiere.")))
                            .frame(height: 240)
                    }
                    footnotes.padding(.top, AppStyle.itemSpacing)
                }
                .padding(.horizontal, AppStyle.pageMargin)
                .padding(.vertical, AppStyle.pagePadding)
                .frame(maxWidth: StatisticsLayout.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .environment(\.statisticsColumns, StatisticsLayout.columnCount(contentWidth: cardContentWidth(for: geometry.size.width)))
                .animation(AppStyle.standardAnimation, value: model.error)
            }
            .pullToRefresh(disabled: { refreshBlocked }, action: refresh)
            // The spring belongs to the pill alone: on the page it also caught
            // the new numbers committed with `calculating` and had every chart
            // glide to them (~0.45 s of a fully busy main thread per update).
            .overlay(alignment: .top) {
                activityPill.animation(.spring(duration: 0.45, bounce: 0.2), value: model.busy || model.calculating)
            }
        }
        .background { AmbientBackdrop(covers: ambientCovers) }
        // Loading starts eagerly at app launch (see RootView) so this page is
        // already populated by the time it's shown; no per-appearance reload here.
        .onChange(of: model.owner) { _, _ in Task { await model.reload(container: context.container) } }
        // After a sync: the account may be new or changed, and the numbers are.
        // Once more when the tracklist download after it is through (countries).
        // Read in modifiers of their own: the sync starting and ending must
        // not re-run this page (see `onObservedChange`).
        .onObservedChange(of: { DiscogsSyncService.shared.busy }) { _, busy in if !busy { reloadAfterSync() } }
        .onObservedChange(of: { DiscogsSyncService.shared.isRunning }) { _, running in if !running { reloadAfterSync() } }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave).receive(on: RunLoop.main)) { notification in
            // Sorting in, moving and marks change nothing counted here; the
            // random pick follows places on its own (see `RandomRecordCard`).
            guard Self.affectsStatistics(notification) else { return }
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
        .appPanel(item: $filter) { group in
            CollectionView(showShelf: { copy in filter = nil; showShelf(copy) }, analyticsFilter: group)
                .frame(maxWidth: 1100, maxHeight: 820)
        }
        .appPanel(item: $opened) { copy in RecordDetailView(copy: copy) { opened = nil; showShelf(copy) } }
        #if DEBUG
        // Screenshots without clicking: --preview-detail=Artist opens that
        // artist's record as from the page.
        .task {
            guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-detail=") }) else { return }
            let artist = String(raw.dropFirst("--preview-detail=".count))
            try? await Task.sleep(for: .seconds(1))
            opened = LibraryRecords.of(context).copies.first { $0.release?.artist == artist }
        }
        #endif
    }

    /// Behind the page: the covers of the latest additions.
    private var ambientCovers: [String] {
        Array(model.statistics.recentlyAdded.lazy.compactMap { model.copiesByID[$0]?.release?.coverURL }.prefix(3))
    }

    /// Whether a save touched what the page counts: releases, the value
    /// history, accounts, or records added or removed. Changes to records
    /// alone are places and marks – a sync's changes to them reload at its end.
    /// Without the details every save counts.
    static func affectsStatistics(_ notification: Notification) -> Bool {
        func identifiers(_ key: ModelContext.NotificationKey) -> [PersistentIdentifier]? {
            notification.userInfo?[key.rawValue] as? [PersistentIdentifier]
        }
        guard let inserted = identifiers(.insertedIdentifiers), let updated = identifiers(.updatedIdentifiers),
              let deleted = identifiers(.deletedIdentifiers) else { return true }
        let counted: Set<String> = [Schema.entityName(for: Release.self), Schema.entityName(for: CollectionValueSnapshot.self),
                                    Schema.entityName(for: DiscogsAccount.self)]
        let records = Schema.entityName(for: RecordCopy.self)
        return (inserted + deleted).contains { counted.contains($0.entityName) || $0.entityName == records }
            || updated.contains { counted.contains($0.entityName) }
    }

    private var refreshBlocked: Bool { model.busy || DiscogsSyncService.shared.busy }
    private func reloadAfterSync() {
        syncReloadTask?.cancel()
        syncReloadTask = Task {
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let before = model.owner
            await model.resolveOwner(container: context.container)
            // A changed owner already reloads via `onChange(of: model.owner)`.
            guard model.owner == before else { return }
            // Hidden: the sync capsule on the page shown is just changing to
            // "Synchronisiert" – all charts redrawn underneath made it stutter.
            // Once when this page is shown again is enough, as for other saves.
            guard activity.isActive else { stale = true; return }
            await model.reload(container: context.container)
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
                ActivityRing()
                Text(model.busy ? "Sammlungswert wird aktualisiert" : "Wird berechnet")
                    .font(.callout)
                    .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary))
                    .contentTransition(.interpolate)
            }
            .geometryGroup()
            .activityPillChrome()
            .animation(.smooth(duration: 0.45), value: model.busy)
            .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
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

    /// Content width of a full-width section for a page `width` wide: the
    /// sections lie flush with the page margins (no card padding).
    private func cardContentWidth(for width: CGFloat) -> CGFloat {
        min(max(0, width - 2 * AppStyle.pageMargin), StatisticsLayout.maxWidth)
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
        StatisticsMovableArea(section: section, first: section == visibleSections.first,
                              accessory: accessory(for: section), move: moveSection) {
            sectionContent(section)
        }
    }
    /// Controls that sit on the right of a card's title row.
    private func accessory(for section: StatisticsSection) -> AnyView? {
        switch section {
        case .sound: AnyView(segmented($soundDimension, SoundDimension.allCases.map { ($0.title, $0) }))
        case .years: AnyView(segmented($yearsByDecade, [(String(localized: "Jahrzehnte"), true), (String(localized: "Jahre"), false)]))
        case .acquisitions: AnyView(segmented($additionsByYear, [(String(localized: "Monate"), false), (String(localized: "Jahre"), true)]))
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
        case .discover: RandomRecordCard(copies: model.copies, copiesByID: model.copiesByID, version: model.version, open: open, showShelf: showShelf)
        case .years: TimeTravel(statistics: model.statistics, byDecade: yearsByDecade, select: select)
        case .acquisitions: AcquisitionChart(statistics: model.statistics, byYear: additionsByYear)
        case .recent: recentSection
        }
    }
    private var recentSection: some View {
        RecentRecords(copies: model.statistics.recentlyAdded.compactMap { model.copiesByID[$0] }, open: open)
    }
    private func select(_ group: StatisticGroup) { filter = group }
    /// The page's records are the app's own (see `StatisticsViewModel.reload`),
    /// so the detail panel and its editor save them through the main context.
    private func open(_ copy: RecordCopy) { opened = copy }
}
