import SwiftUI
import SwiftData

struct CollectionView: View {
    /// Shown or not, without re-rendering the grid on every page switch.
    @State private var activity = PageActivity()
    @Environment(\.modelContext) private var context
    /// Shared with the other pages, fetched only when they change (see `LibraryRecords`).
    private var records: LibraryRecords { .of(context) }
    private var copies: [RecordCopy] { records.copies }
    private var shelves: [Shelf] { records.shelves }
    private var exclusions: [OptimizationExclusion] { records.exclusions }
    private var accounts: [DiscogsAccount] { records.accounts }
    /// IDs of `exclusions`, looked up per table row and context menu.
    @State private var excludedIDs: Set<UUID> = []
    @State private var sync = DiscogsSyncService.shared
    @State private var changes = LibraryChanges.shared
    // The window's page switch; nil in the statistics drill-down sheet.
    private let pages: PageSelection<Destination>?
    // The search shared with the wantlist (see `LibrarySearch`); nil in the
    // statistics panel, which has no search. Objects, read directly: this page is
    // built once (see `PageStack`), and a binding handed in would keep the
    // value it had then.
    private let search: LibrarySearch?
    /// The query typed into the search field in the toolbar (see `ToolbarSearchField`).
    private var query: String { search?.query ?? "" }

    let showShelf: (RecordCopy) -> Void
    var analyticsFilter: StatisticGroup? = nil
    /// Kept for as long as the page lives (see `PageStack`), so a section
    /// switch or another page doesn't lose the place.
    @State private var scroll = ScrollAnchor<UUID>()
    @AppStorage(DisplaySettings.collectionLayoutKey) private var layout = OverviewLayout.grid
    /// The two lists of the settings tab "Listen"; off, their menu entries are gone.
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true
    @AppStorage(DisplaySettings.saleListKey) private var saleEnabled = true
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    @AppStorage(DisplaySettings.coverSizeKey) private var coverSize = DisplaySettings.defaultCoverSize
    /// Width left for the cover columns, derived from the grid's *current*
    /// size on every layout pass — never cached, so it can't go stale when the
    /// window changes size.
    private func gridContentWidth(in width: CGFloat) -> CGFloat {
        width - 2 * AppStyle.pageMargin
    }
    @AppStorage(DisplaySettings.collectionOrderKey) private var order = OverviewOrder.alphabetical
    /// One artist's records follow the shelf's order (Einstellungen › Regal).
    @AppStorage(ShelfSecondaryOrder.key) private var secondaryOrder = ShelfSecondaryOrder.title
    /// List layout: the row whose menu is open, and where it was right-clicked.
    @State private var tableMenu: (id: UUID, anchor: UnitPoint)?
    /// A Discogs token is stored; without one an empty collection leads to it.
    @State private var hasToken = true
    @State private var settingsTab: AppSettingsView.Tab?
    /// List layout: the row whose popover is open (double-click), and where.
    @State private var tableQuickLook: (id: UUID, anchor: UnitPoint)?
    /// Copy whose popover is open (single click on a cover).
    @State private var quickLook: UUID?
    /// The cover whose right-click menu is open, and where it was clicked.
    @State private var contextMenu: (id: UUID, anchor: UnitPoint)?
    @State private var gridClicks = GridSecondaryClicks<UUID>()
    /// The popover closes on the mouse-down of a click outside it; if that
    /// click lands on the same cover, it should stay closed, not reopen.
    @State private var quickLookDismissed: (id: UUID, at: Date)?
    @Environment(\.openURL) private var openURL
    @State private var error: String?

    init(
        pages: PageSelection<Destination>? = nil,
        search: LibrarySearch? = nil,
        showShelf: @escaping (RecordCopy) -> Void,
        analyticsFilter: StatisticGroup? = nil
    ) {
        self.pages = pages
        self.search = search
        self.showShelf = showShelf
        self.analyticsFilter = analyticsFilter
    }

    // Cached so that unrelated re-renders (popovers, scrolling) don't force
    // this filter/sort pass to redo its work on every frame — that repeated
    // O(n log n) work over the full collection was the source of the scroll
    // and navigation stutter.
    @State private var items: [RecordCopy] = []
    @State private var coverGroups: [CollectionCoverGroup] = []

    // Search works in two stages so typing stays smooth: `rebuildBase` does
    // the expensive part (filter, sort) only when the data or
    // section changes; `applyQuery` then just filters that sorted list with
    // the search texts folded once (`LibrarySearchIndexes`) on each
    // (debounced) keystroke.
    @State private var base: [RecordCopy] = []
    /// The query changed while this section was hidden; apply it on return.
    @State private var queryPending = false
    /// Records, account, metadata or wantlist changed. A sync reports itself
    /// and changes the queries a moment apart; one rebuild covers them all.
    @State private var dataRevision = 0
    /// Records were placed or moved while the page was hidden: its shelf
    /// labels are rebuilt once it shows again (over a second for a very
    /// large collection – not for every record sorted in on the shelf page).
    @State private var labelsPending = false
    /// False until the first `rebuildBase`, so the empty state doesn't flash.
    @State private var loaded = false
    /// Whether the visible items are a search result — follows the applied
    /// query, not the raw field (whitespace, debounce).
    @State private var searching = false
    /// The query the visible items were filtered with, for the matched track
    /// under a cover – as in the wantlist.
    @State private var appliedQuery = ""
    /// Where the page was scrolled when the search began, to go back there
    /// when it ends (see `leaveSearch`).
    @State private var scrollBeforeSearch: UUID?
    /// The results, faded out while leaving a search.
    @State private var resultsHidden = false

    /// `animated`: records glide to their new place (search or section).
    /// Data refreshes (e.g. a Discogs sync) and the list layout update
    /// instantly — animating an NSTable diff of the whole collection would stutter.
    private func rebuildBase(animated: Bool = false) {
        let analyticsIDs = analyticsFilter?.copyIDs
        // Only the current account: copies of an earlier one stay active in
        // the store (a sync only touches its own), matching the statistics.
        let owner = DiscogsAccount.current(in: accounts)?.username
        let matched = copies.filter { copy in
            (analyticsIDs == nil || analyticsIDs!.contains(copy.id)) &&
            copy.isInCurrentCollection(owner: owner)
        }
        base = order.apply(matched, scope: DisplaySettings.collectionOrderKey, alphabetical: SortingService.sortedByAlphabetSection,
                           key: { CollectionCoverGroup.identity(of: $0) },
                           added: { DiscogsDate.parse($0.discogsDateAdded) })
        shelfLabels = labelsCache.labels(for: shelves, style: labelStyle)
        labelsPending = false
        loaded = true
        applyQuery(animated: animated)
    }

    private func refreshLabels() {
        guard activity.isActive else { labelsPending = true; return }
        labelsPending = false
        shelfLabels = labelsCache.labels(for: shelves, style: labelStyle)
    }

    private func applyQuery(animated: Bool = false) {
        queryPending = false
        let words = SearchIndex<UUID>.words(query)
        let filtered: [RecordCopy]
        if words.isEmpty { filtered = base } else {
            let index = LibrarySearchIndexes.shared.collection(copies)
            filtered = base.filter { index.matches($0.id, words) }
        }
        let grouped = CollectionCoverGroup.make(from: filtered)
        let searchEnded = searching && words.isEmpty
        withAnimation(animated && layout == .grid ? AppStyle.layoutAnimation : nil) {
            items = filtered
            coverGroups = grouped
            searching = !words.isEmpty
            appliedQuery = words.isEmpty ? "" : query
        }
        // Back where the page was before the search – also when it was
        // cleared while this page was hidden.
        if searchEnded {
            scroll.id = scrollBeforeSearch ?? filtered.first?.id
            scrollBeforeSearch = nil
        }
        // A place filtered away isn't held on to.
        if let id = scroll.id, !filtered.contains(where: { $0.id == id }) { scroll.id = nil }
        normalizeGridScrollPosition(in: grouped)
    }

    private func normalizeGridScrollPosition(in groups: [CollectionCoverGroup]) {
        guard layout == .grid, let id = scroll.id,
              let group = groups.first(where: { group in group.copies.contains { $0.id == id } })
        else { return }
        if id != group.primary.id { scroll.id = group.primary.id }
    }

    // Shelves are named as chosen in the settings, never by their internal number.
    @State private var shelfLabels = ShelfLabels()
    /// Only shelves whose records changed are read again (see `ShelfLabelsCache`).
    @State private var labelsCache = ShelfLabelsCache()
    private func placeLabel(for copy: RecordCopy) -> String {
        guard let shelf = copy.shelf else {
            return excludedIDs.contains(copy.id) ? String(localized: "Ohne Regalplatz") : "–"
        }
        if shelf.isReserved { return shelfLabels.prefix(for: shelf) + (shelf.name.isEmpty ? String(localized: "Gesperrtes Fach") : shelf.name) }
        return shelfLabels.prefix(for: shelf) + (shelfLabels[shelf.id] ?? "–")
    }

    /// Behind the page: the first few covers of the list.
    private var ambientCovers: [String] {
        Array(items.lazy.compactMap { $0.release?.coverURL }.prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Not in the drill-down sheets of the statistics: only on the page itself.
            if DemoMode.showsBanner && analyticsFilter == nil {
                DemoBanner()
                    .padding(.horizontal, AppStyle.pageMargin)
                    .padding(.top, AppStyle.pagePadding)
            }
            if showsControls {
                collectionControls(items: items)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppStyle.pageMargin)
                    .padding(.top, DemoMode.showsBanner && analyticsFilter == nil ? AppStyle.rowSpacing : AppStyle.pagePadding)
                    .transition(AppStyle.funnelTransition())
            }
            Color.clear.frame(height: showsControls || DemoMode.showsBanner ? AppStyle.sectionSpacing : topSpace)
            Group {
            if !loaded {
                Color.clear
            } else if items.isEmpty {
                // Hits filtered away; an empty collection still gets the sync prompt below.
                if !base.isEmpty {
                    AppEmptyState(String(localized: "Keine Treffer"), systemImage: "magnifyingglass",
                        description: Text("Versuche einen anderen Titel, Interpreten oder ein anderes Label."))
                } else if analyticsFilter != nil {
                    AppEmptyState(String(localized: "Keine Schallplatten"), systemImage: "opticaldisc",
                        description: Text("In dieser Auswahl ist nichts mehr in der Collection."))
                } else {
                    // The collection mirrors Discogs, so the way in is a sync.
                    if DemoMode.isActive {
                        AppEmptyState(String(localized: "Noch keine Schallplatten"), systemImage: "opticaldisc",
                            description: Text(DemoMode.emptyHint), actionTitle: String(localized: "Demo neu starten")) { DemoMode.restart() }
                    } else {
                        if hasToken {
                            AppEmptyState(String(localized: "Noch keine Schallplatten"), systemImage: "opticaldisc",
                                description: Text("Die Collection kommt von Discogs. Eine Synchronisierung holt deine Sammlung."),
                                actionTitle: sync.busy ? nil : String(localized: "Jetzt synchronisieren")) {
                                sync.start(.collection, container: context.container)
                            }
                        } else {
                            // First start: nothing works without the token, so that is the way in.
                            AppEmptyState(String(localized: "Willkommen bei Plattenregal"), systemImage: "opticaldisc",
                                description: Text("Deine Collection kommt von Discogs. Trage deinen persönlichen Discogs-Token ein – danach synchronisiert Plattenregal deine Sammlung. Eine Sicherung deiner Fach-Belegung stellst du anschließend unter „Sicherung“ wieder her."),
                                actionTitle: String(localized: "Token eintragen")) { settingsTab = .discogs }
                        }
                    }
                }
            } else {
                ZStack(alignment: .trailing) {
                    if layout == .grid {
                        GeometryReader { proxy in
                            let width = gridContentWidth(in: proxy.size.width)
                            let columnCount = CoverGrid.columnCount(
                                available: width,
                                minimum: DisplaySettings.coverSize(coverSize)
                            )
                            ScrollView {
                                ZStack(alignment: .topLeading) {
                                    // Each tile has the release's stable identity, so
                                    // filtering keeps the existing cover view alive.
                                    LazyVGrid(columns: CoverGrid.columns(count: columnCount), alignment: .leading, spacing: CoverGrid.spacing) {
                                        ForEach(coverGroups) { group in
                                            let copy = group.primary
                                            // A click opens the popover with the tracklist.
                                            Button {
                                                showQuickLook(copy)
                                            } label: {
                                                RecordCard(copy: copy, copyCount: group.copies.count,
                                                           matchedTrack: appliedQuery.isEmpty
                                                               ? nil : copy.release?.track(matching: appliedQuery))
                                            }
                                            .buttonStyle(.plain)
                                            .help("\(copy.release?.displayArtist ?? String(localized: "Unbekannt")) · \(copy.release?.displayTitle ?? "—")\(group.copies.count > 1 ? String(localized: " · \(group.copies.count) Exemplare") : "")")
                                            .accessibilityLabel("\(copy.release?.displayArtist ?? String(localized: "Unbekannt")), \(copy.release?.displayTitle ?? "—")\(group.copies.count > 1 ? String(localized: ", \(group.copies.count) Exemplare") : "")")
                                            .id(copy.id)
                                            .popover(isPresented: quickLookBinding(for: copy.id), arrowEdge: .trailing) {
                                                RecordPopover(copy: group.primary)
                                            }
                                            .gridSecondaryClickCell(copy.id, in: gridClicks)
                                            .popover(isPresented: contextMenuBinding(for: copy.id),
                                                     attachmentAnchor: .point(contextMenu?.anchor ?? .center),
                                                     arrowEdge: .trailing) {
                                                AppMenu(dismiss: { contextMenu = nil }) { gridContextMenu(group) }
                                            }
                                        }
                                    }
                                    .scrollTargetLayout()
                                    .gridSecondaryClickGrid(gridClicks)
                                    .coverGridMotion(width: width, columnCount: columnCount)
                                }
                                .padding(.horizontal, AppStyle.pageMargin)
                                .padding(.vertical, CoverGrid.spacing)
                            }
                            .scrollPosition(scroll)
                            .onGridSecondaryClick(gridClicks) { id, point in
                                quickLook = nil
                                contextMenu = (id, point)
                            }
                            .pullToRefresh(disabled: { sync.busy }) {
                                sync.start(.collection, container: context.container)
                            }
                        }
                    } else {
                        Table(items) {
                            TableColumn("") { copy in CoverView(url: copy.release?.coverURL, size: 20) }.width(24)
                            TableColumn("Interpret") { copy in
                                let artist = copy.release?.displayArtist ?? "—"
                                Text(artist).lineLimit(1).help(artist)
                            }.width(min: 130, ideal: 190)
                            TableColumn("Titel") { copy in
                                let title = copy.release?.displayTitle ?? "—"
                                Text(title).lineLimit(1).help(title)
                            }.width(min: 150, ideal: 230)
                            TableColumn("Jahr") { copy in
                                Text(copy.release?.year.map(String.init) ?? "–").monospacedDigit().foregroundStyle(.secondary)
                            }.width(min: 40, ideal: 48, max: 60)
                            TableColumn("Label") { Text($0.release?.displayLabel ?? "").lineLimit(1).foregroundStyle(.secondary) }
                            TableColumn("Genre") { Text($0.release?.primaryStyle ?? "").lineLimit(1).foregroundStyle(.secondary) }
                            TableColumn("Fach") { Text(placeLabel(for: $0)).lineLimit(1).foregroundStyle(.secondary) }.width(min: 80, ideal: 110)
                            TableColumn("Pos.") { copy in
                                Text(copy.shelf == nil ? "–" : String(copy.positionInShelf)).monospacedDigit().foregroundStyle(.secondary)
                            }.width(min: 34, ideal: 40, max: 52)
                        }
                        .tableStyle(.inset)
                        .background(QuietIconColumnHeaders())
                        .alternatingRowBackgrounds(.disabled)
                        .scrollContentBackground(.hidden)
                        .appTableCard()
                        .padding(.horizontal, AppStyle.pageMargin)
                        // The app's own menu and, on double-click, the quick look – as in the grid.
                        .overlay(TableRowClicks(secondary: { row, point in
                            guard items.indices.contains(row) else { return }
                            tableMenu = (items[row].id, point)
                        }, double: { row, point in
                            guard items.indices.contains(row) else { return }
                            tableQuickLook = (items[row].id, point)
                        }))
                        .popover(isPresented: Binding(get: { tableMenu != nil }, set: { if !$0 { tableMenu = nil } }),
                                 attachmentAnchor: .point(tableMenu?.anchor ?? .center), arrowEdge: .trailing) {
                            if let id = tableMenu?.id {
                                AppMenu(dismiss: { tableMenu = nil }) { tableContextMenu(id, items: items) }
                            }
                        }
                        // Its own layer: two popovers on one view get in each other's way.
                        .background {
                            Color.clear.popover(isPresented: Binding(get: { tableQuickLook != nil }, set: { if !$0 { tableQuickLook = nil } }),
                                                attachmentAnchor: .point(tableQuickLook?.anchor ?? .center), arrowEdge: .trailing) {
                                if let id = tableQuickLook?.id, let copy = items.first(where: { $0.id == id }) {
                                    RecordPopover(copy: copy)
                                }
                            }
                        }
                        .scrollPosition(scroll)
                        .refreshShortcut(disabled: { sync.busy }) {
                            sync.start(.collection, container: context.container)
                        }
                    }

                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(resultsHidden ? 0 : 1)
            // Sync progress floats where the pull-to-refresh ring was.
            .overlay(alignment: .top) { if analyticsFilter == nil { DiscogsSyncPill() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(AppStyle.standardAnimation, value: showsControls)
        .background { if analyticsFilter == nil { AmbientBackdrop(covers: ambientCovers) } }
        .settingsOpener($settingsTab)
        .task(id: sync.tokenRevision) { hasToken = KeychainStore.hasToken }
        .alert("Änderung nicht gespeichert", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: layout) { _, _ in normalizeGridScrollPosition(in: coverGroups) }
        .onChange(of: order) { _, _ in scroll.id = nil; rebuildBase(animated: true) }
        .onChange(of: secondaryOrder) { _, _ in rebuildBase(animated: true) }
        .task { excludedIDs = Set(exclusions.map(\.copyID)); rebuildBase() }
        .onChange(of: copies) { _, _ in dataRevision += 1 }
        .onChange(of: labelStyle) { _, style in shelfLabels = labelsCache.labels(for: shelves, style: style) }
        .onObservedChange(of: { changes.shelvesVersion }) { _, _ in refreshLabels() }
        .onObservedChange(of: { changes.placementsVersion }) { _, _ in refreshLabels() }
        .onChange(of: exclusions) { _, exclusions in excludedIDs = Set(exclusions.map(\.copyID)) }
        .onChange(of: accounts) { _, _ in dataRevision += 1 }
        // Changed metadata on existing records and newly loaded tracklists
        // don't change the record lists; the sync service reports them.
        .onObservedChange(of: { changes.libraryVersion }) { _, _ in dataRevision += 1 }
        .task(id: dataRevision) {
            guard dataRevision > 0 else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            LibrarySearchIndexes.shared.invalidate()
            rebuildBase()
        }
        // New tracks are found by a running search (the index follows them).
        .onObservedChange(of: { changes.tracksVersion }) { _, _ in if !query.isEmpty { applyQuery() } }
        // Debounced, and only for the visible section — the hidden ones
        // share the query but catch up when they're shown again.
        .onObservedChange(of: { query }) { old, new in
            if old.isEmpty && !new.isEmpty && !searching { scrollBeforeSearch = scroll.id }
        }
        .observedTask(id: { query }) {
            guard activity.isActive else { queryPending = true; return }
            // Cleared: no debounce, the list comes back together with the
            // search bar going away.
            if query.isEmpty && searching { await leaveSearch(); return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            applyQuery(animated: true)
        }
        .trackPageActivity(activity) { active in
            if active && labelsPending { refreshLabels() }
            if active && queryPending { applyQuery() }
        }
    }

    /// The search ends: fade the hits out, show the whole list where it was
    /// before the search (see `applyQuery`), fade it in. Typing again
    /// meanwhile cancels this and brings the results back at once.
    private func leaveSearch() async {
        withAnimation(AppStyle.searchExitFadeOut) { resultsHidden = true }
        try? await Task.sleep(for: .milliseconds(100))
        if !Task.isCancelled {
            applyQuery()
            // One layout pass for the jump, still invisible.
            try? await Task.sleep(for: .milliseconds(30))
        }
        withAnimation(AppStyle.searchExitFadeIn) { resultsHidden = false }
    }

    // No "Löschen" here: every record shown comes from the Discogs collection,
    // and the next sync would bring a locally deleted copy back as a new one
    // (without its shelf place). Records leave via Discogs; "Ohne Regalplatz"
    // keeps one off the shelf.

    /// "Ohne Regalplatz" / "Wieder einsortieren", depending on whether all
    /// of the given copies are already kept out of the shelves.
    @ViewBuilder private func exclusionButton(for selectedCopies: [RecordCopy]) -> some View {
        let allExcluded = !selectedCopies.isEmpty && selectedCopies.allSatisfy { excludedIDs.contains($0.id) }
        Button(allExcluded ? "Wieder einsortieren" : "Ohne Regalplatz") {
            perform { try PositionService(context: context).setExcluded(selectedCopies, !allExcluded) }
        }
    }

    @ViewBuilder private func gridContextMenu(_ group: CollectionCoverGroup) -> some View {
        if group.copies.count > 1 {
            ForEach(Array(group.copies.enumerated()), id: \.element.id) { index, copy in
                let excluded = excludedIDs.contains(copy.id)
                AppMenuSection(title: String(localized: "Exemplar \(index + 1) · \(ShelfRangeLabels.location(of: copy, labels: shelfLabels, excluded: excluded))"))
                actions(copy)
            }
        } else {
            actions(group.primary)
        }
    }

    @ViewBuilder private func tableContextMenu(_ id: UUID, items: [RecordCopy]) -> some View {
        if let copy = items.first(where: { $0.id == id }) {
            actions(copy)
        }
    }

    /// A click on a cover: its popover – unless that very popover was just
    /// closed by this click.
    private func showQuickLook(_ copy: RecordCopy) {
        let justClosed = quickLookDismissed.map { $0.id == copy.id && Date().timeIntervalSince($0.at) < 0.4 } ?? false
        if !justClosed { quickLook = copy.id }
    }

    private func contextMenuBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { contextMenu?.id == id },
            set: { if !$0, contextMenu?.id == id { contextMenu = nil } }
        )
    }

    private func quickLookBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { quickLook == id },
            set: { presented in
                guard !presented, quickLook == id else { return }
                quickLook = nil
                quickLookDismissed = (id, Date())
            }
        )
    }

    /// Above the content, right under the toolbar: the grid's covers start
    /// one `CoverGrid.spacing` below it in both designs (see `CoverGrid.topSpace`).
    private var topSpace: CGFloat { layout == .grid ? CoverGrid.topSpace : AppStyle.pagePadding }

    /// In the window the page has no header bar: page switch, grid/list and
    /// search are in the toolbar. The statistics panel has no toolbar, so
    /// there its title sits beside the layout switch — but no search: it is
    /// only for looking.
    private var showsControls: Bool { pages == nil }

    private func collectionControls(items: [RecordCopy]) -> some View {
        HStack(spacing: AppStyle.rowSpacing) {
            if let analyticsFilter {
                // Title and count, like the shelf's detail header.
                HStack(alignment: .firstTextBaseline, spacing: AppStyle.rowSpacing) {
                    Text(analyticsFilter.name).font(AppStyle.dialogTitle).lineLimit(1)
                    Text(AppStyle.records(items.count)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: AppStyle.rowSpacing)
            OverviewLayoutPicker(selection: $layout.animation(AppStyle.fadeAnimation))
        }
        .frame(height: AppStyle.searchBarHeight)
    }
    @ViewBuilder private func actions(_ copy: RecordCopy) -> some View {
        Button(copy.shelf == nil ? "Platz im Regal finden" : "Im Regal anzeigen") { showShelf(copy) }
        if let url = copy.release?.sourceURL {
            Button("Auf Discogs öffnen") { openURL(url) }
        }
        exclusionButton(for: [copy])
        if missingEnabled { missingButton(for: copy) }
        if saleEnabled { saleButton(for: copy) }
    }
    /// Marks the copy "Gesucht" (settings tab "Listen") or found again.
    /// Not offered for one kept out of the shelves ("Ohne Regalplatz"): there
    /// is nothing to look for, `setExcluded` lifts the mark for the same
    /// reason, and the settings wouldn't list it.
    @ViewBuilder private func missingButton(for copy: RecordCopy) -> some View {
        let missing = records.missingMarks.contains { $0.copyID == copy.id }
        if missing || !excludedIDs.contains(copy.id) {
            Button(missing ? "Wieder gefunden" : "Auf die Suchliste setzen") {
                perform { try PositionService(context: context).setMissing([copy], !missing) }
            }
        }
    }
    /// Puts the copy on the "Verkauf" list (settings tab "Listen") or takes it off.
    @ViewBuilder private func saleButton(for copy: RecordCopy) -> some View {
        let forSale = records.saleMarks.contains { $0.copyID == copy.id }
        Button(forSale ? "Nicht mehr verkaufen" : "Zum Verkauf vormerken") {
            perform { try PositionService(context: context).setForSale([copy], !forSale) }
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.reportedMessage() }
    }
}
