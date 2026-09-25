import SwiftUI
import SwiftData
import AppKit

struct CollectionView: View {
    @Environment(\.isActivePage) private var isActivePage
    @Environment(\.modelContext) private var context
    @Query private var copies: [RecordCopy]
    @Query(sort: \Shelf.number) private var shelves: [Shelf]
    @Query private var exclusions: [OptimizationExclusion]
    @Query private var accounts: [DiscogsAccount]
    /// IDs of `exclusions`, looked up per table row and context menu.
    @State private var excludedIDs: Set<UUID> = []
    @State private var sync = DiscogsSyncService.shared
    // nil in the statistics drill-down sheet, which has no section picker.
    private let section: Binding<OverviewSection>?
    // Search lives in this page's own header bar. In the overview it is shared
    // by all sections (see OverviewView); the statistics sheet keeps its own.
    private let sharedQuery: Binding<String>?
    @State private var localQuery = ""
    private var queryBinding: Binding<String> { sharedQuery ?? $localQuery }
    private var query: String { queryBinding.wrappedValue }
    @Query private var wantlistEntries: [WantlistEntry]
    /// Search hits in the wantlist, for the hint next to the count.
    @State private var wantlistMatches = 0
    let showShelf: (RecordCopy) -> Void
    var analyticsFilter: StatisticGroup? = nil
    @Binding private var savedScrollPosition: UUID?
    @State private var scrollPosition: UUID?
    @AppStorage(DisplaySettings.collectionLayoutKey) private var layout = OverviewLayout.grid
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    @AppStorage(DisplaySettings.coverSizeKey) private var coverSize = DisplaySettings.defaultCoverSize
    /// Width left for the cover columns, derived from the grid's *current*
    /// size on every layout pass — never cached, so it can't go stale when the
    /// sidebar or window changes size.
    private func gridContentWidth(in width: CGFloat) -> CGFloat {
        width - 2 * (AppStyle.pagePadding + 4) - alphabetGutter
    }
    // Room for the alphabet index; header, grid and table all leave it free
    // so their right edges stay aligned.
    private var alphabetGutter: CGFloat { 24 }
    @Environment(\.gridReferenceWidth) private var gridReferenceWidth
    @State private var selection: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    /// Latest card frames for the rubber band. A plain reference, not state:
    /// the lazy grid republishes frames on every scroll step, and writing them
    /// must not re-render the view — but hit-testing needs the current layout.
    @State private var cardFrames = CardFrameStore()
    @State private var dragRectangle: CGRect?
    @State private var dragBaseSelection: Set<UUID> = []
    @State private var opened: RecordCopy?
    /// Copy whose popover is open (single click on a cover).
    @State private var quickLook: UUID?
    /// The popover closes on the mouse-down of a click outside it; if that
    /// click lands on the same cover, it should stay closed, not reopen.
    @State private var quickLookDismissed: (id: UUID, at: Date)?
    @State private var editing: RecordCopy?
    @State private var refresh = MetadataRefreshService()
    @Environment(\.openURL) private var openURL
    @State private var error: String?

    init(
        section: Binding<OverviewSection>? = nil,
        query: Binding<String>? = nil,
        showShelf: @escaping (RecordCopy) -> Void,
        analyticsFilter: StatisticGroup? = nil,
        scrollPosition: Binding<UUID?> = .constant(nil)
    ) {
        self.section = section
        self.sharedQuery = query
        self.showShelf = showShelf
        self.analyticsFilter = analyticsFilter
        _savedScrollPosition = scrollPosition
        _scrollPosition = State(initialValue: scrollPosition.wrappedValue)
    }

    // Cached so that unrelated re-renders (e.g. the card-frame tracking below,
    // which updates as the lazy grid scrolls) don't force this filter/sort pass
    // to redo its work on every frame — that repeated O(n log n) work over the
    // full collection was the source of the scroll and navigation stutter.
    @State private var items: [RecordCopy] = []
    @State private var coverGroups: [CollectionCoverGroup] = []
    // Cached alongside `items`: building this (Unicode folding per artist name)
    // for the whole collection on every body evaluation was the extra cost that
    // made the alphabet index noticeably choppier during navigation.
    @State private var alphabetIndex: [String: UUID] = [:]

    // Search works in two stages so typing stays smooth: `rebuildBase` does
    // the expensive part (filter, sort, search texts, letter anchors) only when
    // the data or section changes; `applyQuery` then just filters that
    // sorted list with the prebuilt index on each (debounced) keystroke.
    @State private var base: [RecordCopy] = []
    @State private var searchIndex = SearchIndex<UUID>()
    @State private var letters: [UUID: String] = [:]
    @State private var wantlistIndex = SearchIndex<PersistentIdentifier>()
    /// Discogs release IDs on the wantlist, for the search badge on the covers.
    @State private var wantedReleaseIDs: Set<Int> = []
    /// The query changed while this section was hidden; apply it on return.
    @State private var queryPending = false
    /// Records were placed or moved while the page was hidden: its shelf
    /// labels are rebuilt once it shows again (over a second for a very
    /// large collection – not for every record sorted in on the shelf page).
    @State private var labelsPending = false
    /// False until the first `rebuildBase`, so the empty state doesn't flash.
    @State private var loaded = false
    /// Whether the visible items are a search result — the placement badges
    /// follow this, not the raw field (whitespace, debounce).
    @State private var searching = false

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
        base = showsAlphabetIndex ? SortingService.sortedByAlphabetSection(matched) : SortingService.sorted(matched, by: .artistAZ)
        searchIndex = SearchIndex(base, id: \.id, text: SortingService.searchText)
        letters = showsAlphabetIndex
            ? Dictionary(base.map { ($0.id, SortingService.alphabetSection(for: $0.release?.displayArtist ?? "")) }, uniquingKeysWith: { a, _ in a })
            : [:]
        shelfLabels = ShelfRangeLabels.compute(for: shelves, style: labelStyle)
        labelsPending = false
        loaded = true
        applyQuery(animated: animated)
    }

    private func refreshLabels() {
        guard isActivePage else { labelsPending = true; return }
        labelsPending = false
        shelfLabels = ShelfRangeLabels.compute(for: shelves, style: labelStyle)
    }

    private func applyQuery(animated: Bool = false) {
        queryPending = false
        let words = SearchIndex<UUID>.words(query)
        let filtered = words.isEmpty ? base : base.filter { searchIndex.matches($0.id, words) }
        let grouped = CollectionCoverGroup.make(from: filtered)
        withAnimation(animated && layout == .grid ? AppStyle.layoutAnimation : nil) {
            items = filtered
            coverGroups = grouped
            searching = !words.isEmpty
        }
        normalizeGridScrollPosition(in: grouped)
        alphabetIndex = showsAlphabetIndex ? alphabetAnchors(for: items) : [:]
        wantlistMatches = section == nil || words.isEmpty ? 0
            : currentWantlist.reduce(0) { $0 + (wantlistIndex.matches($1.persistentModelID, words) ? 1 : 0) }
    }

    private func normalizeGridScrollPosition(in groups: [CollectionCoverGroup]) {
        guard layout == .grid, let scrollPosition,
              let group = groups.first(where: { group in group.copies.contains { $0.id == scrollPosition } })
        else { return }
        if scrollPosition != group.primary.id { self.scrollPosition = group.primary.id }
    }

    private func rebuildWantlistIndex() {
        guard section != nil else { return }
        let entries = currentWantlist
        wantlistIndex = SearchIndex(entries, id: \.persistentModelID, text: WantlistPresentation.searchText)
        wantedReleaseIDs = Set(entries.map(\.releaseID))
    }

    private var currentWantlist: [WantlistEntry] {
        guard let owner = DiscogsAccount.current(in: accounts)?.username else { return wantlistEntries }
        return wantlistEntries.filter { $0.owner == owner }
    }

    // Shelves are named as chosen in the settings, never by their internal number.
    @State private var shelfLabels = ShelfLabels()
    private func placeLabel(for copy: RecordCopy) -> String {
        guard let shelf = copy.shelf else {
            return excludedIDs.contains(copy.id) ? "Nicht im Regal" : "–"
        }
        if shelf.isReserved { return shelfLabels.prefix(for: shelf) + (shelf.name.isEmpty ? "Gesperrtes Fach" : shelf.name) }
        return shelfLabels.prefix(for: shelf) + (shelfLabels[shelf.id] ?? "–")
    }

    var body: some View {
        let visibleIDs = items.map(\.id)
        VStack(spacing: 0) {
            // Not in the drill-down sheets of the statistics: only on the page itself.
            if DemoMode.isActive && analyticsFilter == nil {
                DemoBanner()
                    .padding(.horizontal, AppStyle.pagePadding + 4)
                    .padding(.trailing, alphabetGutter)
                    .padding(.top, AppStyle.pagePadding)
            }
            collectionControls(items: items)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppStyle.pagePadding + 4)
                .padding(.trailing, alphabetGutter)
                .padding(.top, DemoMode.isActive && analyticsFilter == nil ? AppStyle.rowSpacing : AppStyle.pagePadding)
                .padding(.bottom, AppStyle.sectionSpacing)
            if sync.hasStatus {
                DiscogsSyncStatusView()
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppStyle.pagePadding + 4).padding(.bottom, AppStyle.rowSpacing)
                    .transition(AppStyle.funnelTransition())
            }
            Group {
            if !loaded {
                Color.clear
            } else if items.isEmpty {
                // Hits filtered away; an empty collection still gets the sync prompt below.
                if !base.isEmpty {
                    AppEmptyState("Keine Treffer", systemImage: "magnifyingglass",
                        description: Text("Versuche einen anderen Titel, Interpreten oder ein Label."))
                } else if analyticsFilter != nil {
                    AppEmptyState("Keine Schallplatten", systemImage: "opticaldisc",
                        description: Text("In dieser Auswahl ist nichts mehr in der Collection."))
                } else {
                    // The collection mirrors Discogs, so the way in is a sync.
                    if DemoMode.isActive {
                        AppEmptyState("Noch keine Schallplatten", systemImage: "opticaldisc",
                            description: Text(DemoMode.emptyHint), actionTitle: "Demo neu starten") { DemoMode.restart() }
                    } else {
                        AppEmptyState("Noch keine Schallplatten", systemImage: "opticaldisc",
                            description: Text("Die Collection kommt von Discogs. Den Token dafür trägst du in den Einstellungen ein."),
                            actionTitle: sync.busy ? nil : "Jetzt synchronisieren") {
                            sync.start(.collection, container: context.container)
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
                                reference: gridReferenceWidth.map(gridContentWidth(in:)),
                                minimum: DisplaySettings.coverSize(coverSize)
                            )
                            ScrollView {
                                ZStack(alignment: .topLeading) {
                                    // Each tile has the release's stable identity, so
                                    // filtering keeps the existing cover view alive.
                                    LazyVGrid(columns: CoverGrid.columns(count: columnCount), alignment: .leading, spacing: CoverGrid.spacing) {
                                        ForEach(coverGroups) { group in
                                            let copy = group.primary
                                            // A single click opens the popover; ⌘/⇧-click and the
                                            // rubber band still select several records for bulk actions.
                                            Button {
                                                select(group, in: coverGroups)
                                            } label: {
                                                RecordCard(
                                                    copy: copy,
                                                    copyCount: group.copies.count,
                                                    selected: group.copies.contains { selection.contains($0.id) } || quickLook == copy.id,
                                                    placement: !searching || section == nil ? nil : PlacementBadge(
                                                        inCollection: true,
                                                        inWantlist: copy.release.map { wantedReleaseIDs.contains($0.discogsID) } ?? false
                                                    )
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .id(copy.id)
                                            .background {
                                                GeometryReader { proxy in
                                                    Color.clear.preference(
                                                        key: RecordCardFrameKey.self,
                                                        value: [copy.id: proxy.frame(in: .named("collectionGrid"))]
                                                    )
                                                }
                                            }
                                            .popover(isPresented: quickLookBinding(for: copy.id), arrowEdge: .trailing) {
                                                GroupedRecordPopover(copies: group.copies, labels: shelfLabels)
                                            }
                                            .contextMenu { gridContextMenu(group, items: items) }
                                            .help("\(copy.release?.displayArtist ?? "Unbekannt") · \(copy.release?.displayTitle ?? "—")\(group.copies.count > 1 ? " · \(group.copies.count) Exemplare" : "")")
                                            .accessibilityLabel("\(copy.release?.displayArtist ?? "Unbekannt"), \(copy.release?.displayTitle ?? "—")\(group.copies.count > 1 ? ", \(group.copies.count) Exemplare" : "")")
                                        }
                                    }
                                    .coverGridMotion(width: width, columnCount: columnCount)
                                    .scrollTargetLayout()
                                    if let dragRectangle {
                                        Rectangle()
                                            .fill(AppStyle.selectedBackground)
                                            .overlay(Rectangle().stroke(AppStyle.selectedBorder, lineWidth: 1))
                                            .frame(width: dragRectangle.width, height: dragRectangle.height)
                                            .offset(x: dragRectangle.minX, y: dragRectangle.minY)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .padding(.horizontal, AppStyle.pagePadding + 4)
                                .padding(.vertical, CoverGrid.spacing)
                                .padding(.trailing, alphabetGutter)
                                .coordinateSpace(name: "collectionGrid")
                                .onPreferenceChange(RecordCardFrameKey.self) { frames in
                                    // Only needed for the rubber-band drag selection below. Stored
                                    // outside SwiftUI state (see `CardFrameStore`), so plain
                                    // scrolling doesn't re-render the whole view.
                                    cardFrames.frames = frames
                                }
                                .simultaneousGesture(gridSelectionGesture)
                            }
                            .scrollPosition(id: $scrollPosition, anchor: .top)
                            // Mouse drags already draw the selection rectangle here,
                            // so pulling works with the trackpad (and ⌘R) only.
                            .pullToRefresh(disabled: sync.busy, allowsMouseDrag: false) {
                                sync.start(.collection, container: context.container)
                            }
                        }
                    } else {
                        Table(items, selection: $selection) {
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
                        .alternatingRowBackgrounds(.disabled)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, AppStyle.pagePadding + 4)
                        .padding(.trailing, alphabetGutter)
                        .contextMenu(forSelectionType: UUID.self) { ids in
                            tableContextMenu(ids, items: items)
                        } primaryAction: { ids in
                            if ids.count == 1 { opened = copies.first(where: { ids.contains($0.id) }) }
                        }
                        .scrollPosition(id: $scrollPosition, anchor: .top)
                        .refreshShortcut(disabled: sync.busy) {
                            sync.start(.collection, container: context.container)
                        }
                    }

                    if showsAlphabetIndex {
                        AlphabetIndex(
                            availableSymbols: Set(alphabetIndex.keys),
                            action: { navigateToLetter($0, anchors: alphabetIndex) }
                        )
                        .padding(.trailing, 8)
                    }
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The sync status line slides in/out and the content below follows smoothly.
        .animation(AppStyle.standardAnimation, value: sync.hasStatus)
        .sheet(item: $opened) { copy in RecordDetailView(copy: copy, labels: shelfLabels) { showShelf(copy); opened = nil } }
        .sheet(item: $editing) { RecordEditor(copy: $0) }
        .alert("Änderung nicht gespeichert", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: visibleIDs) { _, visibleIDs in
            selection.formIntersection(Set(visibleIDs))
            if let scrollPosition, !visibleIDs.contains(scrollPosition) {
                self.scrollPosition = nil
            }
        }
        .onChange(of: layout) { _, _ in normalizeGridScrollPosition(in: coverGroups) }
        .task { excludedIDs = Set(exclusions.map(\.copyID)); rebuildWantlistIndex(); rebuildBase() }
        .onChange(of: copies) { _, _ in rebuildBase() }
        .onChange(of: labelStyle) { _, style in shelfLabels = ShelfRangeLabels.compute(for: shelves, style: style) }
        .onChange(of: sync.shelvesVersion) { _, _ in refreshLabels() }
        .onChange(of: sync.placementsVersion) { _, _ in refreshLabels() }
        .onChange(of: exclusions) { _, exclusions in excludedIDs = Set(exclusions.map(\.copyID)) }
        .onChange(of: accounts) { _, _ in rebuildWantlistIndex(); rebuildBase() }
        .onChange(of: wantlistEntries) { _, _ in rebuildWantlistIndex(); applyQuery() }
        // Changed metadata on existing records and newly loaded tracklists
        // don't change the @Query arrays; the sync service reports them.
        .onChange(of: sync.libraryVersion) { _, _ in rebuildWantlistIndex(); rebuildBase() }
        .onChange(of: sync.tracksVersion) { _, _ in
            searchIndex = SearchIndex(base, id: \.id, text: SortingService.searchText)
            rebuildWantlistIndex()
            if !query.isEmpty { applyQuery() }
        }
        // Debounced, and only for the visible section — the hidden ones
        // share the query but catch up when they're shown again.
        .task(id: query) {
            guard isActivePage else { queryPending = true; return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            applyQuery(animated: true)
        }
        .onChange(of: isActivePage) { _, active in
            if active && labelsPending { refreshLabels() }
            if active && queryPending { applyQuery() }
        }
        .onAppear {
            if scrollPosition == nil { scrollPosition = savedScrollPosition }
        }
        .onDisappear {
            // Keep fast, per-frame scroll state inside this page. Writing every
            // visible item back into RootView would rebuild the complete
            // NavigationSplitView continuously while the user scrolls.
            savedScrollPosition = scrollPosition
        }
    }

    private var showsAlphabetIndex: Bool { true }

    private func alphabetAnchors(for items: [RecordCopy]) -> [String: UUID] {
        items.reduce(into: [:]) { result, copy in
            guard let symbol = letters[copy.id] else { return }
            if result[symbol] == nil { result[symbol] = copy.id }
        }
    }

    private func navigateToLetter(_ symbol: String, anchors: [String: UUID]) {
        guard let id = anchors[symbol] else { return }
        withAnimation(AppStyle.layoutAnimation) { scrollPosition = id }
    }

    // No "Löschen" here: every record shown comes from the Discogs collection,
    // and the next sync would bring a locally deleted copy back as a new one
    // (without its shelf place). Records leave via Discogs; "Nicht einsortieren"
    // keeps one off the shelf.
    @ViewBuilder private func bulkMenus(for ids: Set<UUID>, items: [RecordCopy]) -> some View {
        // Shelf placement itself happens only on the shelf page.
        let selected = items.filter { ids.contains($0.id) }
        exclusionButton(for: selected)
        refreshButton(for: selected)
    }

    /// "Nicht einsortieren" / "Wieder einsortieren", depending on whether all
    /// of the given copies are already kept out of the shelves.
    @ViewBuilder private func exclusionButton(for selectedCopies: [RecordCopy]) -> some View {
        let allExcluded = !selectedCopies.isEmpty && selectedCopies.allSatisfy { excludedIDs.contains($0.id) }
        Button(allExcluded ? "Wieder einsortieren" : "Nicht einsortieren") {
            perform { try PositionService(context: context).setExcluded(selectedCopies, !allExcluded) }
        }
    }

    @ViewBuilder private func gridContextMenu(_ group: CollectionCoverGroup, items: [RecordCopy]) -> some View {
        let groupIDs = Set(group.copies.map(\.id))
        // Bulk actions only when the selection reaches beyond this release;
        // its own copies alone keep the per-copy menus.
        if !groupIDs.isDisjoint(with: selection), !selection.isSubset(of: groupIDs) {
            bulkMenus(for: selection, items: items)
        } else if group.copies.count > 1 {
            ForEach(Array(group.copies.enumerated()), id: \.element.id) { index, copy in
                let excluded = excludedIDs.contains(copy.id)
                Menu("Exemplar \(index + 1) · \(ShelfRangeLabels.location(of: copy, labels: shelfLabels, excluded: excluded))") { actions(copy) }
            }
        } else {
            actions(group.primary)
        }
    }

    @ViewBuilder private func tableContextMenu(_ ids: Set<UUID>, items: [RecordCopy]) -> some View {
        if ids.count > 1 {
            bulkMenus(for: ids, items: items)
        } else if let copy = items.first(where: { ids.contains($0.id) }) {
            actions(copy)
        }
    }

    private func select(_ group: CollectionCoverGroup, in groups: [CollectionCoverGroup]) {
        let copy = group.primary
        let groupIDs = Set(group.copies.map(\.id))
        let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            // Without a usable anchor (none yet, or hidden by a search) the
            // range starts at the clicked record instead of dropping the selection.
            let end = groups.firstIndex(where: { $0.id == group.id })
            let start = selectionAnchor.flatMap { anchor in
                groups.firstIndex { $0.copies.contains { $0.id == anchor } }
            } ?? end
            guard let start, let end else { return }
            let range = min(start, end)...max(start, end)
            let ids = Set(range.flatMap { groups[$0].copies.map(\.id) })
            if modifiers.contains(.command) { selection.formUnion(ids) }
            else { selection = ids }
            if selectionAnchor == nil || groups[start].id == group.id { selectionAnchor = copy.id }
        } else if modifiers.contains(.command) {
            if groupIDs.isSubset(of: selection) { selection.subtract(groupIDs) }
            else { selection.formUnion(groupIDs) }
            selectionAnchor = copy.id
        } else {
            // Plain click: the popover for this record. It isn't a bulk
            // selection, so any marked records are released.
            selection = []
            selectionAnchor = copy.id
            let justClosed = quickLookDismissed.map { $0.id == copy.id && Date().timeIntervalSince($0.at) < 0.4 } ?? false
            if !justClosed { quickLook = copy.id }
        }
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

    private var gridSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("collectionGrid"))
            .onChanged { value in
                if dragRectangle == nil {
                    let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                    dragBaseSelection = modifiers.contains(.command) ? selection : []
                }
                let rectangle = selectionRectangle(from: value.startLocation, to: value.location)
                dragRectangle = rectangle
                let hitIDs = Set(coverGroups.filter { group in
                    guard let frame = cardFrames.frames[group.primary.id] else { return false }
                    return frame.intersects(rectangle)
                }.flatMap { $0.copies.map(\.id) })
                selection = dragBaseSelection.union(hitIDs)
            }
            .onEnded { _ in
                dragRectangle = nil
                dragBaseSelection = []
                // The first selected record in grid order, not an arbitrary
                // element of the set, so a following ⇧-click finds it.
                selectionAnchor = coverGroups.first { group in group.copies.contains { selection.contains($0.id) } }?.primary.id
            }
    }

    private func selectionRectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    // Same header bar as the wantlist: sections and search on the left,
    // the layout switch on the right. The selection part
    // only appears as text next to the search field.
    private func collectionControls(items: [RecordCopy]) -> some View {
        HStack(spacing: AppStyle.rowSpacing) {
            if let section { OverviewSectionPicker(selection: section) }
            if let section {
                OverviewSearchControl(
                    placeholder: "Collection durchsuchen",
                    query: queryBinding,
                    otherCount: wantlistMatches,
                    otherSection: .wantlist
                ) { section.wrappedValue = .wantlist }
            } else {
                AppSearchField(placeholder: "Collection durchsuchen", text: queryBinding)
                    .frame(maxWidth: 380)
            }
            selectionControls(items: items)
            Spacer(minLength: AppStyle.rowSpacing)
            displayOptions
        }
        .frame(height: 30)
    }
    @ViewBuilder private func selectionControls(items: [RecordCopy]) -> some View {
        if !selection.isEmpty {
            HStack(spacing: 6) {
                Text("·").foregroundStyle(.tertiary)
                Text("\(selection.count) ausgewählt").monospacedDigit().foregroundStyle(AppStyle.accent)
                IconButton(systemImage: "xmark.circle.fill", help: "Auswahl aufheben") { selection.removeAll() }
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize()
        }
    }
    private var displayOptions: some View {
        OverviewLayoutPicker(selection: $layout.animation(AppStyle.fadeAnimation), iconOnly: true)
    }
    @ViewBuilder private func actions(_ copy: RecordCopy) -> some View {
        Button("Öffnen") { opened = copy }
        Button("Bearbeiten") { editing = copy }
        Button(copy.shelf == nil ? "Platz im Regal finden" : "Im Regal anzeigen") { showShelf(copy) }
        if let url = copy.release?.sourceURL {
            Button("Bei Discogs öffnen") { openURL(url) }
        }
        refreshButton(for: [copy])
        Divider()
        exclusionButton(for: [copy])
    }
    /// Reloads the Discogs data of the given records (only those from Discogs).
    @ViewBuilder private func refreshButton(for selected: [RecordCopy]) -> some View {
        let releases = Array(Set(selected.compactMap(\.release).map(\.id)))
            .compactMap { id in selected.first { $0.release?.id == id }?.release }
        // Not in the demo: Discogs is off there.
        if !releases.isEmpty && !DemoMode.isActive {
            Button("Discogs-Daten aktualisieren") {
                Task {
                    await refresh.reload(releases, context: context)
                    if let message = refresh.error { error = message }
                }
            }
            .disabled(refresh.busy || sync.busy)
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.reportedMessage() } }
}
/// A grid tile represents one release, even when the collection contains
/// several physical copies. Only the cover and a quiet copy count are shown.
struct CollectionCoverGroup: Identifiable {
    enum Identity: Hashable {
        case discogs(Int)
        case orphan(UUID)
    }

    let id: Identity
    var copies: [RecordCopy]
    var primary: RecordCopy { copies[0] }

    static func make(from copies: [RecordCopy]) -> [Self] {
        var groups: [Self] = []
        var positions: [Identity: Int] = [:]
        for copy in copies {
            let identity = identity(of: copy)
            if let position = positions[identity] {
                groups[position].copies.append(copy)
            } else {
                positions[identity] = groups.count
                groups.append(Self(id: identity, copies: [copy]))
            }
        }
        return groups
    }

    /// The tile a copy belongs to: its Discogs release.
    static func identity(of copy: RecordCopy) -> Identity {
        if let release = copy.release { return .discogs(release.discogsID) }
        return .orphan(copy.id)
    }
}

struct RecordCard: View {
    let copy: RecordCopy
    var copyCount = 1
    var selected = false
    /// Set while searching: where this record is (see `PlacementBadge`).
    var placement: PlacementBadge? = nil
    var body: some View {
        CoverView(url: copy.release?.coverURL, size: nil)
            .overlay(alignment: .topLeading) {
                if let placement { placement.transition(.opacity) }
            }
            .animation(AppStyle.quickAnimation, value: placement == nil)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? AppStyle.selectedBorder : Color.clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, AppStyle.accent)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if copyCount > 1 {
                    Text("\(copyCount)×")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.regularMaterial, in: Capsule())
                        .padding(6)
                }
            }
            .animation(AppStyle.quickAnimation, value: selected)
            .contentShape(Rectangle())
    }
}

private final class CardFrameStore {
    var frames: [UUID: CGRect] = [:]
}

private struct RecordCardFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct AlphabetIndex: View {
    let availableSymbols: Set<String>
    let action: (String) -> Void

    private var symbols: [String] { SortingService.alphabetNavigationSymbols }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                let available = availableSymbols.contains(symbol)
                Button { action(symbol) } label: {
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .frame(width: 16, height: 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(available ? AppStyle.accent : Color.secondary.opacity(0.35))
                .disabled(!available)
                .help(available ? "Zu \(symbol) springen" : "Keine Einträge unter \(symbol)")
                .accessibilityLabel(available ? "Zu Buchstabe \(symbol) springen" : "Keine Einträge unter Buchstabe \(symbol)")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alphabetische Navigation")
    }
}

/// "♪ A2 · Title" under a cover, replacing the release title while a search
/// found the record by one of its tracks.
struct MatchedTrackLine: View {
    let track: Track
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "music.note")
            Text(track.position.isEmpty ? track.title : "\(track.position) · \(track.title)")
        }
        .font(.caption)
        .foregroundStyle(.tint)
        .lineLimit(1)
        .help("Gefunden über den Track „\(track.title)“")
    }
}

/// Search and the other section's matching results sit directly beside each other.
/// The outlined result button appears only for a nonempty search with matches.
struct OverviewSearchControl: View {
    let placeholder: String
    @Binding var query: String
    let otherCount: Int
    let otherSection: OverviewSection
    let openOtherSection: () -> Void

    private var showsOtherSection: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && otherCount > 0
    }

    var body: some View {
        HStack(spacing: 4) {
            AppSearchField(placeholder: placeholder, text: $query)
                .frame(maxWidth: 380)
            if showsOtherSection {
                Button(action: openOtherSection) {
                    Text("\(otherCount) in der \(otherSection.rawValue)")
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: AppStyle.controlHeight)
                        .foregroundStyle(.secondary)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Treffer in der \(otherSection.rawValue) anzeigen")
                .accessibilityLabel("\(otherCount) Treffer in der \(otherSection.rawValue) anzeigen")
                .transition(.opacity)
            }
        }
        .font(.callout)
        .animation(AppStyle.fadeAnimation, value: showsOtherSection)
    }
}

/// Small glass tag on a cover while searching: where the record is —
/// "Collection", "Wantlist" or both. Deliberately quiet (caption size,
/// secondary text) so it reads as a hint, not a label.
struct PlacementBadge: View, Equatable {
    let inCollection: Bool
    let inWantlist: Bool
    var body: some View {
        Text([inCollection ? "Collection" : nil, inWantlist ? "Wantlist" : nil].compactMap { $0 }.joined(separator: " · "))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(6)
            .accessibilityLabel("In: " + [inCollection ? "Collection" : nil, inWantlist ? "Wantlist" : nil].compactMap { $0 }.joined(separator: " und "))
    }
}
