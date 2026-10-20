import SwiftUI
import SwiftData
import AppKit

struct CollectionView: View {
    /// Shown or not, without re-rendering the grid on every page switch.
    @State var activity = PageActivity()
    @Environment(\.modelContext) var context
    /// Shared with the other pages, fetched only when they change (see `LibraryRecords`).
    var records: LibraryRecords { .of(context) }
    var copies: [RecordCopy] { records.copies }
    var shelves: [Shelf] { records.shelves }
    private var exclusions: [OptimizationExclusion] { records.exclusions }
    var accounts: [DiscogsAccount] { records.accounts }
    /// IDs of `exclusions`, looked up per table row and context menu.
    @State var excludedIDs: Set<UUID> = []
    @State var sync = DiscogsSyncService.shared
    @State private var changes = LibraryChanges.shared
    // The window's page switch; nil in the statistics drill-down sheet.
    let pages: PageSelection<Destination>?
    // The search shared with the wantlist (see `LibrarySearch`); nil in the
    // statistics panel, which has no search. Objects, read directly: this page is
    // built once (see `PageStack`), and a binding handed in would keep the
    // value it had then.
    let search: LibrarySearch?
    /// The query typed into the search field in the toolbar (see `ToolbarSearchField`).
    var query: String { search?.query ?? "" }

    let showShelf: (RecordCopy) -> Void
    var analyticsFilter: StatisticGroup? = nil
    /// Kept for as long as the page lives (see `PageStack`), so a section
    /// switch or another page doesn't lose the place.
    @State var scroll = ScrollAnchor<UUID>()
    @AppStorage(DisplaySettings.collectionLayoutKey) var layout = OverviewLayout.grid
    /// The two lists of the settings tab "Listen"; off, their menu entries are gone.
    @AppStorage(DisplaySettings.missingListKey) var missingEnabled = true
    @AppStorage(DisplaySettings.saleListKey) var saleEnabled = true
    @AppStorage(ShelfLabelStyle.key) var labelStyle = ShelfLabelStyle.range
    @AppStorage(DisplaySettings.coverSizeKey) private var coverSize = DisplaySettings.defaultCoverSize
    /// Width left for the cover columns, derived from the grid's *current*
    /// size on every layout pass — never cached, so it can't go stale when the
    /// window changes size.
    private func gridContentWidth(in width: CGFloat) -> CGFloat {
        width - 2 * AppStyle.pageMargin
    }
    @AppStorage(DisplaySettings.collectionOrderKey) var order = OverviewOrder.alphabetical
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
    @State var quickLook: UUID?
    /// The cover whose right-click menu is open, and where it was clicked.
    @State var contextMenu: (id: UUID, anchor: UnitPoint)?
    @State private var gridClicks = GridSecondaryClicks<UUID>()
    /// The popover closes on the mouse-down of a click outside it; if that
    /// click lands on the same cover, it should stay closed, not reopen.
    @State var quickLookDismissed: (id: UUID, at: Date)?
    @Environment(\.openURL) var openURL
    @State var error: String?

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
    @State var items: [RecordCopy] = []
    @State var coverGroups: [CollectionCoverGroup] = []

    // Search works in two stages so typing stays smooth: `rebuildBase` does
    // the expensive part (filter, sort) only when the data or
    // section changes; `applyQuery` then just filters that sorted list with
    // the search texts folded once (`LibrarySearchIndexes`) on each
    // (debounced) keystroke.
    @State var base: [RecordCopy] = []
    /// The query changed while this section was hidden; apply it on return.
    @State var queryPending = false
    /// Records, account, metadata or wantlist changed. A sync reports itself
    /// and changes the queries a moment apart; one rebuild covers them all.
    @State private var dataRevision = 0
    /// Records were placed or moved while the page was hidden: its shelf
    /// labels are rebuilt once it shows again (over a second for a very
    /// large collection – not for every record sorted in on the shelf page).
    @State var labelsPending = false
    /// False until the first `rebuildBase`, so the empty state doesn't flash.
    @State var loaded = false
    /// Whether the visible items are a search result — follows the applied
    /// query, not the raw field (whitespace, debounce).
    @State var searching = false
    /// The query the visible items were filtered with, for the matched track
    /// under a cover – as in the wantlist.
    @State var appliedQuery = ""
    /// Where the page was scrolled when the search began, to go back there
    /// when it ends (see `leaveSearch`).
    @State var scrollBeforeSearch: UUID?
    /// The results, faded out while leaving a search.
    @State var resultsHidden = false

    // Shelves are named as chosen in the settings, never by their internal number.
    @State var shelfLabels = ShelfLabels()
    /// Only shelves whose records changed are read again (see `ShelfLabelsCache`).
    @State var labelsCache = ShelfLabelsCache()
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

}
