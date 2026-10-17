import SwiftUI
import SwiftData

/// Two lines at most: what is happening overall (with animated dots and a
/// small "x" to cancel), and underneath the current step — collection,
/// wantlist, then the tracklists. Reports "abgeschlossen" only when the
/// tracklist download after the sync is through as well.
struct DiscogsSyncStatusView: View {
    @State private var sync = DiscogsSyncService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
            HStack(spacing: AppStyle.itemSpacing) {
                if sync.isRunning {
                    ActivityRing(size: 13)
                    Text("Synchronisierung läuft")
                    CancelIconButton(help: String(localized: "Synchronisierung abbrechen"), keys: "⌘.") { sync.cancel() }
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
                VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
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
                        .appLinkButton().font(.callout)
                }
            }
            .padding(AppStyle.cardPadding)
            .frame(width: 320)
            .appPopoverSurface()
        }
    }
}

/// The sync as a floating Liquid Glass capsule at the top of the page, right
/// where the pull-to-refresh ring filled up: the ring spins while Discogs is
/// read, fills with the tracklist count, turns into a checkmark with the
/// summary and slides away. Each step stays a moment before the next one
/// takes over (quick ones in between are skipped), and every change — text,
/// icon, size — moves in one animation, so the capsule glides instead of jumping.
struct DiscogsSyncPill: View {
    @State private var sync = DiscogsSyncService.shared
    /// What the capsule shows; follows `current` (see `follow`).
    @State private var shown: Content?
    @State private var shownSince = ContinuousClock.now
    @State private var pendingStep: Task<Void, Never>?

    private enum Phase: Equatable { case loading, tracklists, done, failed, note }
    private struct Content: Equatable {
        var phase: Phase
        var title: String
        var subtitle: String?
        var progress: Double?
        var error: String?
        var isRunning: Bool { phase == .loading || phase == .tracklists }
        /// Only the numbers moved: shown right away.
        func isSameStep(as other: Content) -> Bool { phase == other.phase && title == other.title }
    }

    /// How long a step stays before the next one replaces it.
    private static let minimumStep: Duration = .milliseconds(900)
    private static let entrance = Animation.spring(duration: 0.5, bounce: 0.2)
    private static let motion = Animation.smooth(duration: 0.45)

    private var current: Content? {
        guard sync.hasStatus else { return nil }
        let phase: Phase =
            if sync.busy { .loading }
            else if sync.isRunning { .tracklists }
            else if sync.error != nil { .failed }
            else if sync.summary != nil || sync.status == DiscogsSyncService.completedStatus { .done }
            else { .note }
        let title = switch phase {
        case .loading: sync.status.isEmpty ? String(localized: "Synchronisierung läuft") : sync.status
        case .tracklists: String(localized: "Tracklisten werden geladen")
        case .done: String(localized: "Synchronisiert")
        case .failed: sync.status.isEmpty ? String(localized: "Synchronisierung nicht möglich") : sync.status
        case .note: sync.status.isEmpty ? String(localized: "Hinweis") : sync.status
        }
        let subtitle: String? = switch phase {
        case .tracklists: sync.tracklistProgress.map { String(localized: "\($0.done.formatted()) von \($0.total.formatted())") }
        case .done: sync.summary
        default: nil
        }
        let progress = phase == .tracklists ? sync.tracklistProgress.map { Double($0.done) / Double(max(1, $0.total)) } : nil
        return Content(phase: phase, title: title, subtitle: subtitle, progress: progress, error: sync.error)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let shown {
                pill(shown)
                    .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
            }
        }
        .onAppear { shown = current; shownSince = .now }
        .onChange(of: current) { _, new in follow(new) }
        .onDisappear { pendingStep?.cancel() }
    }

    /// Numbers within a step update at once; a new step (or the end) waits
    /// until the current one has been visible for `minimumStep`, and only the
    /// latest state is shown then.
    private func follow(_ new: Content?) {
        pendingStep?.cancel()
        if let old = shown, let new, old.isSameStep(as: new) {
            withAnimation(Self.motion) { shown = new }
            return
        }
        let wait = shown == nil ? .zero : Self.minimumStep - (ContinuousClock.now - shownSince)
        pendingStep = Task {
            if wait > .zero {
                do { try await Task.sleep(for: wait) } catch { return }
            }
            withAnimation(shown == nil || new == nil ? Self.entrance : Self.motion) { shown = new }
            shownSince = .now
        }
    }

    private func pill(_ content: Content) -> some View {
        HStack(spacing: AppStyle.itemSpacing) {
            icon(content)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .id(content.isRunning ? Phase.loading : content.phase)
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text(content.title)
                    .font(.callout)
                    .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .contentTransition(.interpolate)
                if let subtitle = content.subtitle {
                    // In the accent like the ring and the checkmark (Klassisch: petrol), not grey.
                    Text(subtitle)
                        .font(.caption.weight(.medium)).foregroundStyle(AppStyle.accent)
                        .monospacedDigit().lineLimit(1)
                        .contentTransition(.numericText())
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            if content.isRunning {
                CancelIconButton(help: String(localized: "Synchronisierung abbrechen"), keys: "⌘.") { sync.cancel() }
                    .transition(.opacity)
            } else if let error = content.error {
                ErrorInfoButton(title: content.title, message: error) { sync.dismissStatus() }
                    .transition(.opacity)
            } else if content.phase == .note {
                CancelIconButton(help: String(localized: "Ausblenden")) { sync.dismissStatus() }
                    .transition(.opacity)
            }
        }
        // Text and icon move with the capsule as one piece while it resizes.
        .geometryGroup()
        .activityPillChrome()
    }

    @ViewBuilder private func icon(_ content: Content) -> some View {
        switch content.phase {
        case .loading:
            ActivityRing()
        case .tracklists:
            ActivityRing(progress: content.progress)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppStyle.accent)
                .symbolEffect(.bounce, value: content.phase)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppStyle.warningColor)
        case .note:
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

/// The small "x" used to cancel a running sync.
private struct CancelIconButton: View {
    let help: String
    var keys: String?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(keys.map { AppShortcuts.help(help, keys: $0) } ?? help)
        .accessibilityLabel(help)
    }
}
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
    @State private var changes = LibraryChanges.shared
    /// Shared with the collection (see `LibrarySearch`). An object, read
    /// directly: this page is built once (see `PageStack`), and a binding
    /// handed in would keep the value it had then.
    let search: LibrarySearch
    private var query: String { search.query }
    private var copies: [RecordCopy] { records.copies }
    private var accounts: [DiscogsAccount] { records.accounts }
    /// Shown or not, without re-rendering the list on every page switch.
    @State private var activity = PageActivity()
    // Same two stages as the collection: sort on data changes, cheap
    // filtering per (debounced) keystroke with the shared search texts.
    @State private var sortedEntries: [WantlistItem] = []
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
    /// The window's page switch, to jump to the collection's hits.
    let pages: PageSelection<Destination>

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
                            .appTableCard()
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
        .background { AmbientBackdrop(covers: Array(visibleEntries.lazy.compactMap { $0.entry.release?.coverURL }.prefix(3))) }
        .settingsOpener($settingsTab)
        .onChange(of: order) { _, _ in scroll.id = nil; rebuild() }
        .task(id: sync.tokenRevision) { hasToken = KeychainStore.hasToken }
        .task { rebuildCollection(); rebuild() }
        .onChange(of: entries) { _, _ in dataRevision += 1 }
        .onChange(of: copies) { _, _ in dataRevision += 1 }
        .onChange(of: accounts) { _, _ in dataRevision += 1 }
        // See CollectionView: metadata and tracklist changes on the same objects.
        .onObservedChange(of: { changes.libraryVersion }) { _, _ in dataRevision += 1 }
        .task(id: dataRevision) {
            guard dataRevision > 0 else { return }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            LibrarySearchIndexes.shared.invalidate()
            rebuildCollection()
            rebuild()
        }
        // New tracks are found by a running search (the index follows them).
        .onObservedChange(of: { changes.tracksVersion }) { _, _ in if !query.isEmpty { applyQuery() } }
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
        .trackPageActivity(activity) { active in if active && queryPending { applyQuery() } }
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
        applyQuery()
    }

    private func rebuildCollection() {
        let owner = owner
        let active = copies.filter { $0.isInCurrentCollection(owner: owner) }
        ownedReleaseIDs = Set(active.compactMap { $0.release?.discogsID })
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
                        Button { quickLook = (item.id, .center) } label: {
                            WantlistCard(entry: entry,
                                         matchedTrack: appliedQuery.isEmpty ? nil : entry.release?.track(matching: appliedQuery))
                        }
                        .buttonStyle(.plain)
                        .help([entry.release?.displayArtist, entry.release?.displayTitle, entry.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – "))
                        .overlay(alignment: .topLeading) {
                            if !appliedQuery.isEmpty {
                                PlacementBadge(
                                    inCollection: ownedReleaseIDs.contains(item.id),
                                    inWantlist: true,
                                    current: .wantlist,
                                    show: { pages.current = $0 }
                                )
                                .padding(AtelierCoverFrame.badgeInset)
                            }
                        }
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
        }
    }

    private func table(_ rows: [WantlistItem]) -> some View {
        Table(rows) {
            TableColumn("") { item in
                let entry = item.entry
                CoverView(url: entry.release?.coverURL, size: 20)
            }
            .width(24)
            TableColumn("Interpret") { item in
                let entry = item.entry
                let artist = entry.release?.displayArtist ?? String(localized: "Unbekannter Interpret")
                Text(artist).lineLimit(1).help(artist)
            }
            .width(min: 120, ideal: 200)
            TableColumn("Titel") { item in
                let entry = item.entry
                let title = entry.release?.displayTitle ?? String(localized: "Release #\(String(entry.releaseID))")
                Text(title).lineLimit(1).help(title)
            }
            .width(min: 140, ideal: 260)
            TableColumn("Jahr") { item in
                let entry = item.entry
                Text(entry.release?.year.map(String.init) ?? "–").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 48, max: 60)
            TableColumn("Notiz") { item in
                let entry = item.entry
                Text(entry.notes ?? "").lineLimit(1).foregroundStyle(.secondary).help(entry.notes ?? "")
            }
            .width(min: 80, ideal: 180)
            TableColumn("Hinzugefügt") { item in
                let entry = item.entry
                Text(DiscogsDate.parse(entry.dateAdded)?.formatted(date: .abbreviated, time: .omitted) ?? "–")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100, max: 120)
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
        }
        .tableStyle(.inset)
        .background(QuietIconColumnHeaders())
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
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
            CoverView(url: entry.release?.coverURL, size: nil)
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
