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
                    HStack(spacing: 0) {
                        Text("Synchronisierung läuft")
                        AnimatedDots()
                    }
                    CancelIconButton(help: "Synchronisierung abbrechen") { sync.cancel() }
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
                return String(format: "%0\(digits)d von %d", progress.done, progress.total)
            }
            return ("Tracklisten werden geladen", progress, false)
        }
        // Errors live in the "i" popover, not in the line.
        if let summary = sync.summary { return (summary, nil, false) }
        return nil
    }
}

/// Three dots filling up one after another; static with reduce motion.
private struct AnimatedDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if reduceMotion {
            Text("…")
        } else {
            TimelineView(.periodic(from: .now, by: 0.4)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 4
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        Text(".").opacity(index < step ? 1 : 0)
                    }
                }
                .accessibilityHidden(true)
            }
        }
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
                Label(title.isEmpty ? "Hinweis" : title, systemImage: "exclamationmark.triangle.fill")
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

/// The small "x" used to cancel a running task, like "Auswahl aufheben".
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
/// Wantlist in the shelf/statistics style: slim header bar (search, count,
/// sync) and a compact table instead of cards.
struct WantlistView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var entries: [WantlistEntry]
    @State private var sync = DiscogsSyncService.shared
    @State private var changes = LibraryChanges.shared
    /// Shared with the other overview sections (see OverviewView).
    @Binding var query: String
    /// Whether ⌘F has revealed the search bar; shared like `query`.
    @Binding var searchPresented: Bool
    @FocusState private var searchFocused: Bool
    private var showsSearchBar: Bool { searchPresented || !query.isEmpty }
    @Query private var copies: [RecordCopy]
    @Query private var accounts: [DiscogsAccount]
    @Environment(\.isActivePage) private var isActivePage
    /// Search hits in the collection, for the hint next to the count.
    @State private var collectionMatches = 0
    // Same two stages as the collection: sort and index on data changes,
    // cheap filtering per (debounced) keystroke.
    @State private var sortedEntries: [WantlistEntry] = []
    @State private var searchIndex = SearchIndex<PersistentIdentifier>()
    @State private var collectionIndex = SearchIndex<UUID>()
    /// Active copies with the release they belong to: the hint counts
    /// releases (grid tiles), not copies.
    @State private var activeCopies: [(id: UUID, group: CollectionCoverGroup.Identity)] = []
    /// Discogs release IDs in the collection, for the search badge on the covers.
    @State private var ownedReleaseIDs: Set<Int> = []
    @State private var queryPending = false
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
    @Binding var section: OverviewSection

    /// Same margins as the collection (see CollectionView).
    private var pageMargin: CGFloat { AppStyle.pagePadding + 4 }
    private var alphabetGutter: CGFloat { 24 }
    private func gridContentWidth(in width: CGFloat) -> CGFloat {
        width - 2 * pageMargin - alphabetGutter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            if DemoMode.isActive {
                DemoBanner()
                    .padding(.horizontal, pageMargin)
                    .padding(.trailing, alphabetGutter)
            }
            if showsSearchBar {
                OverviewSearchControl(
                    placeholder: "Wantlist durchsuchen",
                    query: $query,
                    focus: $searchFocused,
                    otherCount: collectionMatches,
                    otherSection: .collection
                ) { section = .collection }
                .padding(.horizontal, pageMargin)
                .padding(.trailing, alphabetGutter)
                .transition(AppStyle.funnelTransition())
            }
            header
                .padding(.horizontal, pageMargin)
            if sync.hasStatus {
                DiscogsSyncStatusView()
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, pageMargin)
                    .transition(AppStyle.funnelTransition())
            }
            if !loaded {
                Color.clear
            } else if sortedEntries.isEmpty {
                AppEmptyState(
                    "Wantlist ist leer",
                    systemImage: "heart.text.clipboard",
                    description: Text(DemoMode.isActive ? DemoMode.emptyHint : "Die Wantlist kommt von Discogs. Den Token dafür trägst du in den Einstellungen ein."),
                    actionTitle: DemoMode.isActive ? "Demo neu starten" : sync.busy ? nil : "Jetzt synchronisieren"
                ) { if DemoMode.isActive { DemoMode.restart() } else { syncWantlist() } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleEntries.isEmpty {
                AppEmptyState(
                    "Keine Treffer",
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
                            .padding(.horizontal, pageMargin)
                            .padding(.trailing, alphabetGutter)
                    }
                    alphabetNavigation
                }
            }
        }
        .padding(.top, AppStyle.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(AppStyle.standardAnimation, value: sync.hasStatus)
        .animation(AppStyle.standardAnimation, value: showsSearchBar)
        .searchReveal(isPresented: $searchPresented, focus: $searchFocused, query: query)
        .task { rebuildCollectionIndex(); rebuild() }
        .onChange(of: entries) { _, _ in rebuild() }
        .onChange(of: copies) { _, _ in rebuildCollectionIndex(); applyQuery() }
        .onChange(of: accounts) { _, _ in rebuildCollectionIndex(); rebuild() }
        // See CollectionView: metadata and tracklist changes on the same objects.
        .onChange(of: changes.libraryVersion) { _, _ in rebuildCollectionIndex(); rebuild() }
        .onChange(of: changes.tracksVersion) { _, _ in
            searchIndex = SearchIndex(sortedEntries, id: \.persistentModelID, text: WantlistPresentation.searchText)
            rebuildCollectionIndex()
            if !query.isEmpty { applyQuery() }
        }
        .task(id: query) {
            guard isActivePage else { queryPending = true; return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            applyQuery(animated: true)
        }
        .onChange(of: isActivePage) { _, active in if active && queryPending { applyQuery() } }
    }

    /// Only the current account, as in the collection (see CollectionView).
    private var owner: String? { DiscogsAccount.current(in: accounts)?.username }

    private func rebuild() {
        let owner = owner
        let owned = owner.map { owner in entries.filter { $0.owner == owner } } ?? entries
        sortedEntries = WantlistPresentation.sorted(owned)
        searchIndex = SearchIndex(sortedEntries, id: \.persistentModelID, text: WantlistPresentation.searchText)
        loaded = true
        applyQuery()
    }

    private func rebuildCollectionIndex() {
        let owner = owner
        let active = copies.filter { $0.isInCurrentCollection(owner: owner) }
        activeCopies = active.map { ($0.id, CollectionCoverGroup.identity(of: $0)) }
        ownedReleaseIDs = Set(active.compactMap { $0.release?.discogsID })
        collectionIndex = SearchIndex(active, id: \.id, text: SortingService.searchText)
    }

    /// `animated`: search results glide into place (grid only; a sync
    /// refresh or the table updates instantly).
    private func applyQuery(animated: Bool = false) {
        queryPending = false
        let words = SearchIndex<UUID>.words(query)
        let visible = words.isEmpty ? sortedEntries : sortedEntries.filter { searchIndex.matches($0.persistentModelID, words) }
        collectionMatches = words.isEmpty ? 0
            : Set(activeCopies.filter { collectionIndex.matches($0.id, words) }.map(\.group)).count
        withAnimation(animated && layout == .grid ? AppStyle.layoutAnimation : nil) {
            visibleEntries = visible
            appliedQuery = words.isEmpty ? "" : query
        }
        alphabetIndex = visible.reduce(into: [:]) { result, entry in
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

    /// Covers like the collection grid; click opens the release on Discogs.
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
                        Button { open(entry) } label: {
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
                                    Text(entry.release?.displayArtist ?? "Unbekannter Interpret")
                                        .font(.callout).lineLimit(1)
                                    if !appliedQuery.isEmpty, let track = entry.release?.track(matching: appliedQuery) {
                                        MatchedTrackLine(track: track)
                                    } else {
                                        Text(entry.release?.displayTitle ?? "Release #\(entry.releaseID)")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(entry.persistentModelID)
                        .help([entry.release?.displayArtist, entry.release?.displayTitle, entry.notes].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ") + (DemoMode.isActive ? "" : "\nKlicken, um bei Discogs zu öffnen"))
                        .contextMenu { if sourceURL(entry) != nil { Button("Bei Discogs öffnen") { open(entry) } } }
                    }
                }
                .coverGridMotion(width: width, columnCount: columnCount)
                .scrollTargetLayout()
                .padding(.vertical, AppStyle.rowSpacing)
                .padding(.horizontal, pageMargin)
                .padding(.trailing, alphabetGutter)
            }
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .pullToRefresh(disabled: sync.busy, action: syncWantlist)
        }
    }

    private var header: some View {
        HStack(spacing: AppStyle.rowSpacing) {
            OverviewSectionPicker(selection: $section)
            Spacer(minLength: AppStyle.rowSpacing)
            OverviewLayoutPicker(selection: $layout.animation(AppStyle.fadeAnimation), iconOnly: true)
        }
        .frame(height: 30)
        .padding(.trailing, alphabetGutter)
    }

    private func table(_ rows: [WantlistEntry]) -> some View {
        Table(rows) {
            TableColumn("") { entry in
                CoverView(url: entry.release?.coverURL, size: 20)
            }
            .width(24)
            TableColumn("Interpret") { entry in
                let artist = entry.release?.displayArtist ?? "Unbekannter Interpret"
                Text(artist).lineLimit(1).help(artist)
            }
            .width(min: 120, ideal: 200)
            TableColumn("Titel") { entry in
                let title = entry.release?.displayTitle ?? "Release #\(entry.releaseID)"
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
                .help("Bei Discogs öffnen")
                .accessibilityLabel("Bei Discogs öffnen")
                }
            }
            .width(24)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .scrollPosition(id: $scrollPosition, anchor: .top)
        .refreshShortcut(disabled: sync.busy, action: syncWantlist)
        .contextMenu(forSelectionType: WantlistEntry.ID.self) { ids in
            if let entry = rows.first(where: { ids.contains($0.id) }), sourceURL(entry) != nil {
                Button("Bei Discogs öffnen") { open(entry) }
            }
        } primaryAction: { ids in
            if let entry = rows.first(where: { ids.contains($0.id) }) { open(entry) }
        }
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
        entries.sorted { lhs, rhs in
            let leftArtist = (lhs.release?.displayArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rightArtist = (rhs.release?.displayArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let leftSection = SortingService.alphabetSection(for: leftArtist)
            let rightSection = SortingService.alphabetSection(for: rightArtist)
            if leftSection != rightSection { return leftSection < rightSection }
            let artistOrder = leftArtist.localizedStandardCompare(rightArtist)
            if artistOrder != .orderedSame { return artistOrder == .orderedAscending }
            let leftTitle = lhs.release?.displayTitle ?? ""
            let rightTitle = rhs.release?.displayTitle ?? ""
            let titleOrder = leftTitle.localizedStandardCompare(rightTitle)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.releaseID < rhs.releaseID
        }
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
