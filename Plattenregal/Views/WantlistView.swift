import SwiftUI
import SwiftData

/// The Discogs wantlist as covers or a list, like the collection: search
/// after ⌘F, a popover with the tracklist on click, the app's own menu on
/// right-click.
struct WantlistView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    /// Shared with the other pages, fetched only when they change (see `LibraryRecords`).
    private var records: LibraryRecords { .of(context) }
    private var entries: [WantlistEntry] { records.wants }
    @State private var sync = DiscogsSyncService.shared
    /// Column order and visibility of the list (`AppPreferences.wantlistColumns`).
    @State private var preferences = AppPreferences.shared
    @State private var changes = LibraryChanges.shared
    /// Shared with the collection (see `LibrarySearch`). An object, read
    /// directly: this page is built once (see `PageStack`), and a binding
    /// handed in would keep the value it had then.
    let search: LibrarySearch
    private var query: String { search.query }
    private var accounts: [DiscogsAccount] { records.accounts }
    /// Shown or not, without re-rendering the list on every page switch.
    @State private var activity = PageActivity()
    // Same two stages as the collection: sort on data changes, cheap
    // filtering per (debounced) keystroke with the shared search texts.
    @State private var sortedEntries: [WantlistItem] = []
    @State private var queryPending = false
    /// Entries, account or metadata changed; one rebuild for all (see CollectionView).
    @State private var dataRevision = 0
    /// Changed while the page was hidden: rebuilt once it shows (see CollectionView).
    @State private var rebuildPending = false
    /// The query the visible entries were filtered with — the track lines
    /// follow it, not the raw field, so they match what is shown.
    @State private var appliedQuery = ""
    /// False until the first `rebuild`, so "Keine Treffer" doesn't flash.
    @State private var loaded = false
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var layout = OverviewLayout.grid
    @AppStorage(DisplaySettings.coverSizeKey) private var coverSize = DisplaySettings.defaultCoverSize
    // Filtered/sorted once per change of entries or query, not on every render.
    @State private var visibleEntries: [WantlistItem] = []
    /// See `ScrollAnchor`: scrolling must not rebuild the page.
    @State private var scroll = ScrollAnchor<Int>()
    /// Where the page was scrolled when the search began (see `leaveSearch`).
    @State private var scrollBeforeSearch: Int?
    /// The results, faded out while leaving a search.
    @State private var resultsHidden = false
    @State private var hasToken = true
    @State private var settingsTab: AppSettingsView.Tab?
    /// The entry whose menu is open, and where it was right-clicked.
    @State private var menuFor: (id: Int, anchor: UnitPoint)?
    @State private var gridClicks = GridSecondaryClicks<Int>()
    /// The entry whose popover (with the tracklist) is open; in the list
    /// also where it was double-clicked.
    @State private var quickLook: (id: Int, anchor: UnitPoint)?

    @AppStorage(DisplaySettings.wantlistOrderKey) private var order = OverviewOrder.alphabetical
    private func gridContentWidth(in width: CGFloat) -> CGFloat {
        width - 2 * AppStyle.pageMargin
    }

    var body: some View {
        // Spacing as in the collection (see CollectionView), so both pages
        // start their covers at the same height.
        VStack(alignment: .leading, spacing: 0) {
            if DemoMode.showsBanner {
                DemoBanner()
                    .padding(.horizontal, AppStyle.pageMargin)
                    .padding(.top, AppStyle.pagePadding)
            }
            // The grid right under the toolbar (see CollectionView).
            Color.clear.frame(height: DemoMode.showsBanner ? AppStyle.sectionSpacing
                              : layout == .grid ? CoverGrid.topSpace : AppStyle.pagePadding)
            Group {
            if !loaded {
                Color.clear
            } else if sortedEntries.isEmpty {
                AppEmptyState(
                    String(localized: "Wantlist ist leer"),
                    systemImage: "heart.text.clipboard",
                    description: Text(DemoMode.isActive ? DemoMode.emptyHint : String(localized: "Die Wantlist kommt von Discogs. Den Token dafür trägst du in den Einstellungen ein.")),
                    actionTitle: DemoMode.isActive ? String(localized: "Demo neu starten") : !hasToken ? String(localized: "Token eintragen") : sync.busy ? nil : String(localized: "Jetzt synchronisieren")
                ) {
                    if DemoMode.isActive { DemoMode.restart() }
                    else if !hasToken { settingsTab = .discogs }
                    else { syncWantlist() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleEntries.isEmpty {
                AppEmptyState(
                    String(localized: "Keine Treffer"),
                    systemImage: "magnifyingglass",
                    description: Text("Versuche einen anderen Titel, Interpreten oder ein anderes Label.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // As in the collection: the page margin lies inside grid and
                // table, so the index sits at the window edge, not the covers.
                ZStack(alignment: .trailing) {
                    if layout == .grid {
                        grid(visibleEntries)
                    } else {
                        table(visibleEntries)
                            .appBottomTableCard()
                            .padding(.horizontal, AppStyle.pageMargin)
                    }
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(resultsHidden ? 0 : 1)
            // Sync progress floats where the pull-to-refresh ring was.
            .overlay(alignment: .top) { DiscogsSyncPill() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { AmbientBackdrop(covers: Array(visibleEntries.lazy.compactMap { $0.entry.release?.shownCoverURL }.prefix(3))) }
        .settingsOpener($settingsTab)
        .onChange(of: order) { _, _ in scroll.id = nil; rebuildWhenShown() }
        .task(id: sync.tokenRevision) { hasToken = KeychainStore.hasToken }
        .task { rebuild() }
        .onChange(of: entries) { _, _ in dataRevision += 1 }
        .onChange(of: accounts) { _, _ in dataRevision += 1 }
        // See CollectionView: metadata and tracklist changes on the same objects.
        .onObservedChange(of: { changes.libraryVersion }) { _, _ in dataRevision += 1 }
        .task(id: dataRevision) {
            guard dataRevision > 0 else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            LibrarySearchIndexes.shared.invalidate(.wantlist)
            rebuildWhenShown()
        }
        // New tracks are found by a running search (the index follows them);
        // a hidden page catches up when shown.
        .onObservedChange(of: { changes.tracksVersion }) { _, _ in
            guard !query.isEmpty else { return }
            if activity.isActive { applyQuery() } else { queryPending = true }
        }
        .onObservedChange(of: { query }) { old, new in
            if old.isEmpty && !new.isEmpty && appliedQuery.isEmpty { scrollBeforeSearch = scroll.id }
        }
        .observedTask(id: { query }) {
            guard activity.isActive else { queryPending = true; return }
            // Cleared: no debounce, as in the collection.
            if query.isEmpty && !appliedQuery.isEmpty { await leaveSearch(); return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            applyQuery(animated: true)
        }
        .trackPageActivity(activity) { active in
            guard active else { return }
            if rebuildPending { rebuild() } else if queryPending { applyQuery() }
        }
    }

    /// The search ends: hits out, the whole list back where it was (see
    /// `applyQuery`), in again – as in the collection.
    private func leaveSearch() async {
        withAnimation(AppStyle.searchExitFadeOut) { resultsHidden = true }
        try? await Task.sleep(for: .milliseconds(100))
        if !Task.isCancelled {
            applyQuery()
            try? await Task.sleep(for: .milliseconds(30))
        }
        withAnimation(AppStyle.searchExitFadeIn) { resultsHidden = false }
    }

    /// Only the current account, as in the collection (see CollectionView).
    private var owner: String? { DiscogsAccount.current(in: accounts)?.username }

    private func rebuild() {
        let owner = owner
        let owned = owner.map { owner in entries.filter { $0.owner == owner } } ?? entries
        sortedEntries = WantlistItem.make(from: order.apply(owned, scope: DisplaySettings.wantlistOrderKey, alphabetical: WantlistPresentation.sorted,
                                                            key: \.releaseID, added: { DiscogsDate.parse($0.dateAdded) }))
        loaded = true
        rebuildPending = false
        applyQuery()
    }

    /// `rebuild` now if the page is shown, else once it is.
    private func rebuildWhenShown() {
        guard activity.isActive else { rebuildPending = true; return }
        rebuild()
    }

    /// `animated`: search results glide into place (grid only; a sync
    /// refresh or the table updates instantly).
    private func applyQuery(animated: Bool = false) {
        queryPending = false
        let words = SearchIndex<UUID>.words(query)
        let visible: [WantlistItem]
        if words.isEmpty {
            visible = sortedEntries
        } else {
            let index = LibrarySearchIndexes.shared.wantlist(entries)
            visible = sortedEntries.filter { index.matches($0.entry.persistentModelID, words) }
        }
        let searchEnded = !appliedQuery.isEmpty && words.isEmpty
        withAnimation(animated && layout == .grid ? AppStyle.layoutAnimation : nil) {
            visibleEntries = visible
            appliedQuery = words.isEmpty ? "" : query
        }
        // Back where the page was before the search (see CollectionView).
        if searchEnded {
            scroll.id = scrollBeforeSearch ?? visible.first?.id
            scrollBeforeSearch = nil
        }
        if let id = scroll.id, !visible.contains(where: { $0.id == id }) {
            scroll.id = nil
        }
    }

    /// Covers like the collection grid; a click shows the popover with the
    /// tracklist and the way to Discogs.
    private func grid(_ rows: [WantlistItem]) -> some View {
        // Width read live on every layout pass (no cached copy that could lag
        // behind a window resize); flexible columns keep covers inside their cells.
        GeometryReader { proxy in
            let width = gridContentWidth(in: proxy.size.width)
            let columnCount = CoverGrid.columnCount(
                available: width,
                minimum: DisplaySettings.coverSize(coverSize)
            )
            ScrollView {
                LazyVGrid(columns: CoverGrid.columns(count: columnCount), alignment: .leading, spacing: CoverGrid.spacing) {
                    ForEach(rows) { item in
                        let entry = item.entry
                        Button { quickLook = CoverGrid.popover(shown: quickLook?.id, afterClickOn: item.id).map { ($0, .center) } } label: {
                            WantlistCard(entry: entry,
                                         matchedTrack: appliedQuery.isEmpty ? nil : entry.release?.track(matching: appliedQuery))
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .popover(isPresented: quickLookBinding(item.id), arrowEdge: .trailing) {
                            RecordPopover(release: entry.release, discogsURL: sourceURL(entry))
                        }
                        // The app's own menu, as in the collection.
                        .gridSecondaryClickCell(item.id, in: gridClicks)
                        .popover(isPresented: menuBinding(item.id),
                                 attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
                            AppMenu(dismiss: { menuFor = nil }) { entryMenu(entry) }
                        }
                    }
                }
                .scrollTargetLayout()
                .gridSecondaryClickGrid(gridClicks)
                .coverGridMotion(width: width, columnCount: columnCount)
                .padding(.vertical, CoverGrid.spacing)
                .padding(.horizontal, AppStyle.pageMargin)
            }
            .scrollPosition(scroll)
            .onGridSecondaryClick(gridClicks) { id, point in
                if let item = rows.first(where: { $0.id == id }), sourceURL(item.entry) != nil {
                    menuFor = (id, point)
                }
            }
            .pullToRefresh(disabled: { sync.busy }, action: syncWantlist)
            .scrollsUnderToolbar(contentPadding: CoverGrid.spacing)
        }
    }

    private func table(_ rows: [WantlistItem]) -> some View {
        // Columns: dragged to another place by their header, shown or hidden
        // with a right-click on it (`TableColumnID`).
        Table(rows, columnCustomization: $preferences.wantlistColumns) {
            TableColumn("") { item in
                let entry = item.entry
                CoverView(url: entry.release?.shownCoverURL, size: 20)
            }
            .width(24)
            .tableColumnID(.cover)
            TableColumn(TableColumnID.artist.title) { item in
                let entry = item.entry
                let artist = entry.release?.displayArtist ?? String(localized: "Unbekannter Interpret")
                Text(artist).lineLimit(1)
            }
            .width(min: 120, ideal: 200)
            .tableColumnID(.artist)
            TableColumn(TableColumnID.title.title) { item in
                let entry = item.entry
                let title = entry.release?.displayTitle ?? String(localized: "Release #\(String(entry.releaseID))")
                Text(title).lineLimit(1)
            }
            .width(min: 140, ideal: 260)
            .tableColumnID(.title)
            TableColumn(TableColumnID.year.title) { item in
                let entry = item.entry
                Text(entry.release?.year.map(String.init) ?? "–").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 48, max: 60)
            .tableColumnID(.year)
            TableColumn(TableColumnID.note.title) { item in
                let entry = item.entry
                Text(entry.notes ?? "").lineLimit(1).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 180)
            .tableColumnID(.note)
            TableColumn(TableColumnID.added.title) { item in
                let entry = item.entry
                Text(DiscogsDate.parse(entry.dateAdded)?.formatted(date: .abbreviated, time: .omitted) ?? "–")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 120)
            .tableColumnID(.added)
            TableColumn("") { item in
                let entry = item.entry
                if sourceURL(entry) != nil {
                Button { open(entry) } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Auf Discogs öffnen")
                .accessibilityLabel("Auf Discogs öffnen")
                }
            }
            .width(24)
            .tableColumnID(.link)
        }
        .tableStyle(.inset)
        .background(QuietIconColumnHeaders())
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .tableColumnMenu($preferences.wantlistColumns)
        .scrollPosition(scroll)
        .refreshShortcut(disabled: { sync.busy }, action: syncWantlist)
        // The app's own menu, and on double-click the popover – as in the collection.
        .overlay(TableRowClicks(secondary: { row, point in
            guard rows.indices.contains(row), sourceURL(rows[row].entry) != nil else { return }
            menuFor = (rows[row].id, point)
        }, double: { row, point in
            guard rows.indices.contains(row) else { return }
            quickLook = (rows[row].id, point)
        }))
        // Its own layer: two popovers on one view get in each other's way.
        .background {
            Color.clear.popover(isPresented: Binding(get: { quickLook != nil && layout != .grid }, set: { if !$0 { quickLook = nil } }),
                                attachmentAnchor: .point(quickLook?.anchor ?? .center), arrowEdge: .trailing) {
                if let id = quickLook?.id, let entry = rows.first(where: { $0.id == id })?.entry {
                    RecordPopover(release: entry.release, discogsURL: sourceURL(entry))
                }
            }
        }
        .popover(isPresented: Binding(get: { menuFor != nil && layout != .grid }, set: { if !$0 { menuFor = nil } }),
                 attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
            if let id = menuFor?.id, let entry = rows.first(where: { $0.id == id })?.entry {
                AppMenu(dismiss: { menuFor = nil }) { entryMenu(entry) }
            }
        }
    }

    @ViewBuilder private func entryMenu(_ entry: WantlistEntry) -> some View {
        Button("Auf Discogs öffnen") { open(entry) }
    }

    private func quickLookBinding(_ id: Int) -> Binding<Bool> {
        Binding(get: { quickLook?.id == id && layout == .grid }, set: { if !$0, quickLook?.id == id { quickLook = nil } })
    }

    private func menuBinding(_ id: Int) -> Binding<Bool> {
        Binding(get: { menuFor?.id == id }, set: { if !$0, menuFor?.id == id { menuFor = nil } })
    }

    private func syncWantlist() {
        sync.start(.wantlist, container: context.container)
    }

    /// `nil` in the demo, whose sample IDs belong to unrelated Discogs releases.
    private func sourceURL(_ entry: WantlistEntry) -> URL? {
        if DemoMode.isActive { return nil }
        return entry.release?.sourceURL ?? URL(string: "https://www.discogs.com/release/\(entry.releaseID)")
    }
    private func open(_ entry: WantlistEntry) { if let url = sourceURL(entry) { openURL(url) } }
}

/// An entry of the wantlist as the page shows it, identified by its Discogs
/// release ID: a stored Int, cheap for the grid's identity, scroll position
/// and clicks – the model's `PersistentIdentifier` is read through SwiftData
/// and hashed heavily, on every cell the lazy grid lays out (the collection
/// uses its own stored IDs the same way, see `CollectionCoverGroup`).
struct WantlistItem: Identifiable {
    let id: Int
    let entry: WantlistEntry

    /// Keeps the order; one item per release (only entries of several
    /// accounts, shown without a current one, could repeat a release).
    static func make(from entries: [WantlistEntry]) -> [Self] {
        var seen = Set<Int>()
        return entries.compactMap { entry in
            let id = entry.releaseID
            return seen.insert(id).inserted ? Self(id: id, entry: entry) : nil
        }
    }
}

/// A cover of the wantlist grid with its caption: a view of its own, like
/// the collection's `RecordCard`, so SwiftUI keeps a cell instead of
/// re-evaluating it with the page.
private struct WantlistCard: View {
    let entry: WantlistEntry
    var matchedTrack: Track? = nil
    var body: some View {
        // The cover's address may come with a sync (see `RecordCaption`).
        let _ = LibraryChanges.shared.libraryVersion
        VStack(alignment: .leading, spacing: CoverGrid.captionSpacing) {
            CoverView(url: entry.release?.shownCoverURL, size: nil)
                .atelierRecordSleeve()
            RecordCaption(
                release: entry.release,
                matchedTrack: matchedTrack,
                fallbackArtist: String(localized: "Unbekannter Interpret"),
                fallbackTitle: String(localized: "Release #\(String(entry.releaseID))")
            )
        }
        .contentShape(Rectangle())
    }
}

enum WantlistPresentation {
    /// By alphabet section ("#" first, then A–Z), artist, title – as the collection.
    /// Searching goes through a `SearchIndex` over `searchText`.
    static func sorted(_ entries: [WantlistEntry]) -> [WantlistEntry] {
        // Keys read once per entry, not per comparison: the alphabet section
        // runs a Unicode transform, and a sort does ~n·log n comparisons.
        entries.map { entry in
            let artist = (entry.release?.displayArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (entry: entry, section: SortingService.alphabetSection(for: artist), artist: artist,
                    title: entry.release?.displayTitle ?? "", id: entry.releaseID)
        }
        .sorted { lhs, rhs in
            if lhs.section != rhs.section { return lhs.section < rhs.section }
            let artistOrder = lhs.artist.localizedStandardCompare(rhs.artist)
            if artistOrder != .orderedSame { return artistOrder == .orderedAscending }
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
        .map(\.entry)
    }

    /// Everything a wantlist search looks at, including the track titles.
    static func searchText(_ entry: WantlistEntry) -> String {
        guard let release = entry.release else { return String(entry.releaseID) }
        return [
            release.displayArtist, release.displayTitle, release.label,
            release.catalogNumber, release.country, release.format,
            release.genres.joined(separator: " "), release.styles.joined(separator: " "),
            release.tracks.map(\.title).joined(separator: " "),
            entry.notes ?? "", String(entry.releaseID)
        ].joined(separator: " ")
    }

}
