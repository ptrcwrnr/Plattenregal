import SwiftUI
import SwiftData

/// Two lines at most: what is happening overall (with animated dots and a
/// small "x" to cancel), and underneath the current step — collection,
/// wantlist, then the tracklists. Reports "abgeschlossen" only when the
/// tracklist download after the sync is through as well.
struct DiscogsSyncStatusView: View {
    @State private var sync = DiscogsSyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if sync.isRunning {
                    ActivityRing(size: 13)
                    Text("Synchronisierung läuft")
                    CancelIconButton(help: String(localized: "Synchronisierung abbrechen")) { sync.cancel() }
                } else {
                    Text(sync.status)
                        .transition(.opacity)
                    if let error = sync.error {
                        ErrorInfoButton(title: sync.status, message: error) { sync.dismissStatus() }
                    }
                }
            }
            if let detail {
                // Step on the second line, its counter on the third.
                // Gentle motion: steps blend into each other, counters roll,
                // and the counter line eases in and out instead of popping.
                VStack(alignment: .leading, spacing: 1) {
                    Text(detail.text)
                        .foregroundStyle(detail.isError ? AnyShapeStyle(AppStyle.errorColor) : AnyShapeStyle(.secondary))
                        .lineLimit(2)
                        .contentTransition(.interpolate)
                    if let progress = detail.progress {
                        Text(progress)
                            .foregroundStyle(.tertiary).lineLimit(1)
                            .contentTransition(.numericText())
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .textSelection(.enabled)
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.45), value: sync.isRunning)
        .animation(.smooth(duration: 0.45), value: detail?.text)
        .animation(.smooth(duration: 0.35), value: detail?.progress)
    }

    private var detail: (text: String, progress: String?, isError: Bool)? {
        if sync.busy { return (sync.status, nil, false) }
        if sync.isRunning {
            let progress = sync.tracklistProgress.map { progress in
                // Zero-padded to the total's width, so the counter doesn't jump around.
                let digits = String(progress.total).count
                return String(localized: "\(String(format: "%0\(digits)d", progress.done)) von \(progress.total)", comment: "Fortschritt beim Laden der Tracklisten")
            }
            return (String(localized: "Tracklisten werden geladen"), progress, false)
        }
        // Errors live in the "i" popover, not in the line.
        if let summary = sync.summary { return (summary, nil, false) }
        return nil
    }
}

/// Small "i" next to a failed sync; opens a glass popover (like the record
/// popover) with the error in plain words and a way to dismiss the hint.
private struct ErrorInfoButton: View {
    let title: String
    let message: String
    let dismiss: () -> Void
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppStyle.warningColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Was ist passiert?")
        .accessibilityLabel("Fehlerdetails anzeigen")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
                Label(title.isEmpty ? String(localized: "Hinweis") : title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(AppStyle.warningColor)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack {
                    Spacer()
                    Button("Hinweis ausblenden") { showing = false; dismiss() }
                        .buttonStyle(.link).font(.callout)
                }
            }
            .padding(AppStyle.cardPadding)
            .frame(width: 320)
        }
    }
}

/// The sync as a floating Liquid Glass capsule at the top of the page, right
/// where the pull-to-refresh ring filled up: the ring spins while Discogs is
/// read, fills with the tracklist count, turns into a checkmark with the
/// summary and slides away. Every change in between is animated.
struct DiscogsSyncPill: View {
    @State private var sync = DiscogsSyncService.shared

    private enum Phase: Equatable { case loading, tracklists, done, failed, note }
    private var phase: Phase {
        if sync.busy { return .loading }
        if sync.isRunning { return .tracklists }
        if sync.error != nil { return .failed }
        if sync.summary != nil || sync.status == DiscogsSyncService.completedStatus { return .done }
        return .note
    }

    var body: some View {
        ZStack(alignment: .top) {
            if sync.hasStatus {
                pill
                    .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: sync.hasStatus)
    }

    private var pill: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            icon
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .id(phase == .loading || phase == .tracklists ? Phase.loading : phase)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit().lineLimit(1)
                        .contentTransition(.numericText())
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            if sync.isRunning {
                CancelIconButton(help: String(localized: "Synchronisierung abbrechen")) { sync.cancel() }
                    .transition(.opacity)
            } else if let error = sync.error {
                ErrorInfoButton(title: sync.status, message: error) { sync.dismissStatus() }
                    .transition(.opacity)
            } else if phase == .note {
                CancelIconButton(help: String(localized: "Ausblenden")) { sync.dismissStatus() }
                    .transition(.opacity)
            }
        }
        .activityPillChrome()
        .animation(.smooth(duration: 0.45), value: phase)
        .animation(.smooth(duration: 0.45), value: title)
        .animation(.smooth(duration: 0.35), value: subtitle)
    }

    @ViewBuilder private var icon: some View {
        switch phase {
        case .loading:
            ActivityRing()
        case .tracklists:
            ActivityRing(progress: sync.tracklistProgress.map { Double($0.done) / Double(max(1, $0.total)) })
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppStyle.accent)
                .symbolEffect(.bounce, value: phase)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppStyle.warningColor)
        case .note:
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch phase {
        case .loading: sync.status.isEmpty ? String(localized: "Synchronisierung läuft") : sync.status
        case .tracklists: String(localized: "Tracklisten werden geladen")
        case .done: String(localized: "Synchronisiert")
        case .failed: sync.status.isEmpty ? String(localized: "Synchronisierung nicht möglich") : sync.status
        case .note: sync.status.isEmpty ? String(localized: "Hinweis") : sync.status
        }
    }

    private var subtitle: String? {
        switch phase {
        case .tracklists:
            return sync.tracklistProgress.map { String(localized: "\($0.done.formatted()) von \($0.total.formatted())") }
        case .done:
            return sync.summary
        default:
            return nil
        }
    }
}

/// The small "x" used to cancel a running sync.
private struct CancelIconButton: View {
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
/// The Discogs wantlist as covers or a list, like the collection: search
/// after ⌘F, a popover with the tracklist on click, the app's own menu on
/// right-click.
struct WantlistView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var entries: [WantlistEntry]
    @State private var sync = DiscogsSyncService.shared
    @State private var changes = LibraryChanges.shared
    /// Shared with the collection (see `LibrarySearch`). An object, read
    /// directly: this page is built once (see `PageStack`), and a binding
    /// handed in would keep the value it had then.
    let search: LibrarySearch
    private var query: String { search.query }
    @FocusState private var searchFocused: Bool
    private var showsSearchBar: Bool { search.isPresented || !search.query.isEmpty }
    @Query private var copies: [RecordCopy]
    @Query private var accounts: [DiscogsAccount]
    /// Shown or not, without re-rendering the list on every page switch.
    @State private var activity = PageActivity()
    /// Search hits in the collection, for the hint next to the count.
    @State private var collectionMatches = 0
    // Same two stages as the collection: sort on data changes, cheap
    // filtering per (debounced) keystroke with the shared search texts.
    @State private var sortedEntries: [WantlistEntry] = []
    /// Active copies with the release they belong to: the hint counts
    /// releases (grid tiles), not copies.
    @State private var activeCopies: [(id: UUID, group: CollectionCoverGroup.Identity)] = []
    /// Discogs release IDs in the collection, for the search badge on the covers.
    @State private var ownedReleaseIDs: Set<Int> = []
    @State private var queryPending = false
    /// Entries, records, account or metadata changed; one rebuild for all (see CollectionView).
    @State private var dataRevision = 0
    /// The query the visible entries were filtered with — badges and track
    /// lines follow it, not the raw field, so they match what is shown.
    @State private var appliedQuery = ""
    /// False until the first `rebuild`, so "Keine Treffer" doesn't flash.
    @State private var loaded = false
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var layout = OverviewLayout.grid
    @AppStorage(DisplaySettings.coverSizeKey) private var coverSize = DisplaySettings.defaultCoverSize
    // Filtered/sorted once per change of entries or query, not on every render.
    @State private var visibleEntries: [WantlistEntry] = []
    @State private var alphabetIndex: [String: PersistentIdentifier] = [:]
    @State private var scrollPosition: PersistentIdentifier?
    /// Where the page was scrolled when the search began (see `leaveSearch`).
    @State private var scrollBeforeSearch: PersistentIdentifier?
    /// The results, faded out while leaving a search.
    @State private var resultsHidden = false
    @State private var hasToken = true
    @State private var settingsTab: AppSettingsView.Tab?
    /// The entry whose menu is open, and where it was right-clicked.
    @State private var menuFor: (id: PersistentIdentifier, anchor: UnitPoint)?
    /// The entry whose popover (with the tracklist) is open; in the list
    /// also where it was double-clicked.
    @State private var quickLook: (id: PersistentIdentifier, anchor: UnitPoint)?
    /// The window's page switch, to jump to the collection's hits.
    let pages: PageSelection<Destination>

    /// Same margins as the collection (see CollectionView).
    private var pageMargin: CGFloat { AppStyle.pagePadding + 4 }
    /// Kept with any order, so switching it never changes the cover size.
    private var alphabetGutter: CGFloat { 24 }
    @AppStorage(DisplaySettings.wantlistOrderKey) private var order = OverviewOrder.alphabetical
    private func gridContentWidth(in width: CGFloat) -> CGFloat {
        width - 2 * pageMargin - alphabetGutter
    }

    var body: some View {
        // Spacing as in the collection (see CollectionView), so both pages
        // start their covers at the same height.
        VStack(alignment: .leading, spacing: 0) {
            if DemoMode.showsBanner {
                DemoBanner()
                    .padding(.horizontal, pageMargin)
                    .padding(.trailing, alphabetGutter)
                    .padding(.top, AppStyle.pagePadding)
            }
            OverviewSearchControl(
                placeholder: String(localized: "Wantlist durchsuchen"),
                query: Bindable(search).query,
                focus: $searchFocused,
                otherCount: collectionMatches,
                otherSection: .collection
            ) { pages.current = .collection }
            .padding(.horizontal, pageMargin)
            .padding(.top, DemoMode.showsBanner ? AppStyle.rowSpacing : AppStyle.pagePadding)
            .searchBarSlot(shown: showsSearchBar, topPadding: DemoMode.showsBanner ? AppStyle.rowSpacing : AppStyle.pagePadding)
            Color.clear.frame(height: showsSearchBar || DemoMode.showsBanner ? AppStyle.sectionSpacing : AppStyle.pagePadding)
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
                            .appTableCard()
                            .padding(.horizontal, pageMargin)
                            .padding(.trailing, alphabetGutter)
                    }
                    if order == .alphabetical { alphabetNavigation }
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(resultsHidden ? 0 : 1)
            // Sync progress floats where the pull-to-refresh ring was.
            .overlay(alignment: .top) { DiscogsSyncPill() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { AmbientBackdrop(covers: Array(visibleEntries.lazy.compactMap { $0.release?.coverURL }.prefix(3))) }
        .animation(AppStyle.searchBarAnimation, value: showsSearchBar)
        .searchReveal(isPresented: Bindable(search).isPresented, focus: $searchFocused, query: Bindable(search).query)
        .settingsOpener($settingsTab)
        .onChange(of: order) { _, _ in scrollPosition = nil; rebuild() }
        .task(id: sync.tokenRevision) { hasToken = KeychainStore.hasToken }
        .task { rebuildCollection(); rebuild() }
        .onChange(of: entries) { _, _ in dataRevision += 1 }
        .onChange(of: copies) { _, _ in dataRevision += 1 }
        .onChange(of: accounts) { _, _ in dataRevision += 1 }
        // See CollectionView: metadata and tracklist changes on the same objects.
        .onChange(of: changes.libraryVersion) { _, _ in dataRevision += 1 }
        .task(id: dataRevision) {
            guard dataRevision > 0 else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            LibrarySearchIndexes.shared.invalidate()
            rebuildCollection()
            rebuild()
        }
        // New tracks are found by a running search (the index follows them).
        .onChange(of: changes.tracksVersion) { _, _ in if !query.isEmpty { applyQuery() } }
        .onChange(of: query) { old, new in
            if old.isEmpty && !new.isEmpty && appliedQuery.isEmpty { scrollBeforeSearch = scrollPosition }
        }
        .task(id: query) {
            guard activity.isActive else { queryPending = true; return }
            // Cleared: no debounce, as in the collection.
            if query.isEmpty && !appliedQuery.isEmpty { await leaveSearch(); return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            applyQuery(animated: true)
        }
        .trackPageActivity(activity) { active in if active && queryPending { applyQuery() } }
    }

    /// The search ends: hits out, the whole list back where it was, in again
    /// (see CollectionView).
    private func leaveSearch() async {
        withAnimation(AppStyle.searchExitFadeOut) { resultsHidden = true }
        try? await Task.sleep(for: .milliseconds(100))
        if !Task.isCancelled {
            applyQuery()
            scrollPosition = scrollBeforeSearch ?? visibleEntries.first?.persistentModelID
            scrollBeforeSearch = nil
            try? await Task.sleep(for: .milliseconds(30))
        }
        withAnimation(AppStyle.searchExitFadeIn) { resultsHidden = false }
    }

    /// Only the current account, as in the collection (see CollectionView).
    private var owner: String? { DiscogsAccount.current(in: accounts)?.username }

    private func rebuild() {
        let owner = owner
        let owned = owner.map { owner in entries.filter { $0.owner == owner } } ?? entries
        sortedEntries = order.apply(owned, scope: DisplaySettings.wantlistOrderKey, alphabetical: WantlistPresentation.sorted,
                                    key: \.releaseID, added: { DiscogsDate.parse($0.dateAdded) })
        loaded = true
        applyQuery()
    }

    private func rebuildCollection() {
        let owner = owner
        let active = copies.filter { $0.isInCurrentCollection(owner: owner) }
        activeCopies = active.map { ($0.id, CollectionCoverGroup.identity(of: $0)) }
        ownedReleaseIDs = Set(active.compactMap { $0.release?.discogsID })
    }

    /// `animated`: search results glide into place (grid only; a sync
    /// refresh or the table updates instantly).
    private func applyQuery(animated: Bool = false) {
        queryPending = false
        let words = SearchIndex<UUID>.words(query)
        let visible: [WantlistEntry]
        if words.isEmpty {
            visible = sortedEntries
            collectionMatches = 0
        } else {
            let index = LibrarySearchIndexes.shared.wantlist(entries)
            visible = sortedEntries.filter { index.matches($0.persistentModelID, words) }
            let collection = LibrarySearchIndexes.shared.collection(copies)
            collectionMatches = Set(activeCopies.filter { collection.matches($0.id, words) }.map(\.group)).count
        }
        withAnimation(animated && layout == .grid ? AppStyle.layoutAnimation : nil) {
            visibleEntries = visible
            appliedQuery = words.isEmpty ? "" : query
        }
        // Only the alphabetical order has the index at the edge.
        alphabetIndex = order != .alphabetical ? [:] : visible.reduce(into: [:]) { result, entry in
            let symbol = SortingService.alphabetSection(for: entry.release?.displayArtist ?? "")
            if result[symbol] == nil { result[symbol] = entry.persistentModelID }
        }
        if let scrollPosition, !visible.contains(where: { $0.persistentModelID == scrollPosition }) {
            self.scrollPosition = nil
        }
    }

    private var alphabetNavigation: some View {
        AlphabetIndex(availableSymbols: Set(alphabetIndex.keys)) { symbol in
            guard let id = alphabetIndex[symbol] else { return }
            withAnimation(AppStyle.layoutAnimation) { scrollPosition = id }
        }
        .padding(.trailing, 8)
    }

    /// Covers like the collection grid; a click shows the popover with the
    /// tracklist and the way to Discogs.
    private func grid(_ rows: [WantlistEntry]) -> some View {
        // Width read live on every layout pass (no cached copy that could lag
        // behind a window resize); flexible columns keep covers inside their cells.
        GeometryReader { proxy in
            let width = gridContentWidth(in: proxy.size.width)
            let columnCount = CoverGrid.columnCount(
                available: width,
                minimum: DisplaySettings.coverSize(coverSize)
            )
            ScrollView {
                LazyVGrid(columns: CoverGrid.columns(count: columnCount), alignment: .leading, spacing: 16) {
                    ForEach(rows) { entry in
                        Button { quickLook = (entry.persistentModelID, .center) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverView(url: entry.release?.coverURL, size: nil)
                                    .overlay(alignment: .topLeading) {
                                        if !appliedQuery.isEmpty {
                                            PlacementBadge(inCollection: ownedReleaseIDs.contains(entry.releaseID), inWantlist: true)
                                                .transition(.opacity)
                                        }
                                    }
                                    .animation(AppStyle.quickAnimation, value: appliedQuery.isEmpty)
                                VStack(alignment: .leading, spacing: 1) {
                                    // As under the covers on the statistics page.
                                    Text(entry.release?.displayArtist ?? String(localized: "Unbekannter Interpret"))
                                        .font(.callout.weight(.medium)).lineLimit(1)
                                    if !appliedQuery.isEmpty, let track = entry.release?.track(matching: appliedQuery) {
                                        MatchedTrackLine(track: track)
                                    } else {
                                        Text(entry.release?.displayTitle ?? String(localized: "Release #\(String(entry.releaseID))"))
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: quickLookBinding(entry.persistentModelID), arrowEdge: .trailing) {
                            RecordPopover(release: entry.release, discogsURL: sourceURL(entry))
                        }
                        .id(entry.persistentModelID)
                        .help([entry.release?.displayArtist, entry.release?.displayTitle, entry.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – "))
                        // The app's own menu, as in the collection.
                        .onSecondaryClick { point in
                            if sourceURL(entry) != nil { menuFor = (entry.persistentModelID, point) }
                        }
                        .popover(isPresented: menuBinding(entry.persistentModelID),
                                 attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
                            AppMenu(dismiss: { menuFor = nil }) { entryMenu(entry) }
                        }
                    }
                }
                .coverGridMotion(width: width, columnCount: columnCount)
                .scrollTargetLayout()
                .padding(.vertical, CoverGrid.spacing)
                .padding(.horizontal, pageMargin)
                .padding(.trailing, alphabetGutter)
            }
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .pullToRefresh(disabled: sync.busy, action: syncWantlist)
        }
    }

    private func table(_ rows: [WantlistEntry]) -> some View {
        Table(rows) {
            TableColumn("") { entry in
                CoverView(url: entry.release?.coverURL, size: 20)
            }
            .width(24)
            TableColumn("Interpret") { entry in
                let artist = entry.release?.displayArtist ?? String(localized: "Unbekannter Interpret")
                Text(artist).lineLimit(1).help(artist)
            }
            .width(min: 120, ideal: 200)
            TableColumn("Titel") { entry in
                let title = entry.release?.displayTitle ?? String(localized: "Release #\(String(entry.releaseID))")
                Text(title).lineLimit(1).help(title)
            }
            .width(min: 140, ideal: 260)
            TableColumn("Jahr") { entry in
                Text(entry.release?.year.map(String.init) ?? "–").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 48, max: 60)
            TableColumn("Notiz") { entry in
                Text(entry.notes ?? "").lineLimit(1).foregroundStyle(.secondary).help(entry.notes ?? "")
            }
            .width(min: 80, ideal: 180)
            TableColumn("Hinzugefügt") { entry in
                Text(DiscogsDate.parse(entry.dateAdded)?.formatted(date: .abbreviated, time: .omitted) ?? "–")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 120)
            TableColumn("") { entry in
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
        }
        .tableStyle(.inset)
        .background(QuietIconColumnHeaders())
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .refreshShortcut(disabled: sync.busy, action: syncWantlist)
        // The app's own menu, and on double-click the popover – as in the collection.
        .overlay(TableRowClicks(secondary: { row, point in
            guard rows.indices.contains(row), sourceURL(rows[row]) != nil else { return }
            menuFor = (rows[row].persistentModelID, point)
        }, double: { row, point in
            guard rows.indices.contains(row) else { return }
            quickLook = (rows[row].persistentModelID, point)
        }))
        // Its own layer: two popovers on one view get in each other's way.
        .background {
            Color.clear.popover(isPresented: Binding(get: { quickLook != nil && layout != .grid }, set: { if !$0 { quickLook = nil } }),
                                attachmentAnchor: .point(quickLook?.anchor ?? .center), arrowEdge: .trailing) {
                if let id = quickLook?.id, let entry = rows.first(where: { $0.persistentModelID == id }) {
                    RecordPopover(release: entry.release, discogsURL: sourceURL(entry))
                }
            }
        }
        .popover(isPresented: Binding(get: { menuFor != nil && layout != .grid }, set: { if !$0 { menuFor = nil } }),
                 attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
            if let id = menuFor?.id, let entry = rows.first(where: { $0.persistentModelID == id }) {
                AppMenu(dismiss: { menuFor = nil }) { entryMenu(entry) }
            }
        }
    }

    @ViewBuilder private func entryMenu(_ entry: WantlistEntry) -> some View {
        Button("Auf Discogs öffnen") { open(entry) }
    }

    private func quickLookBinding(_ id: PersistentIdentifier) -> Binding<Bool> {
        Binding(get: { quickLook?.id == id && layout == .grid }, set: { if !$0, quickLook?.id == id { quickLook = nil } })
    }

    private func menuBinding(_ id: PersistentIdentifier) -> Binding<Bool> {
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

enum WantlistPresentation {
    /// By alphabet section, artist, title – the order of the alphabet index.
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
