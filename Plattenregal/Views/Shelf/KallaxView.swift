import SwiftUI
import SwiftData

/// The shelf page as one calm column: a slim header bar (search after ⌘F, status), the
/// KALLAX drawn as a single piece of furniture, and the selected compartment
/// underneath at full width (spine strip, then a compact table of its records).
/// What other pages ask of the shelf page. An object, not a binding: pages
/// live in separate hosting views (see `PageStack`), and only Observation
/// reaches across.
@Observable final class ShelfRequests {
    /// A record to show: where it stands and between which records, or –
    /// without a shelf – where it belongs.
    var placing: UUID?
}

struct KallaxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shelf.number) private var allShelves: [Shelf]
    @Query(sort: \Cabinet.sortOrder) private var cabinets: [Cabinet]
    @Query private var allCopies: [RecordCopy]
    @Query private var exclusions: [OptimizationExclusion]
    @Query private var missingMarks: [MissingCopyMark]
    @Query private var accounts: [DiscogsAccount]
    /// The compartment selected in the rack.
    @State private var highlight: UUID?
    /// "Im Regal anzeigen" / "Platz im Regal finden" from other pages; taken
    /// over into `placement` right away.
    let requests: ShelfRequests
    /// The record being sorted in and the spots it fits alphabetically.
    @State private var placement: Placement?
    /// "Namen ändern …" from a locked compartment's menu.
    @State private var showsNameEditor = false
    @State private var lockPreview = ShelfLockPreview()
    /// The open "Platte hinzufügen" sheet. A new session per opening, so a
    /// reopened sheet always starts from fresh data.
    @State private var assignment: ShelfAssignmentSession?
    /// Kept past the sheet's dismissal to pick up its last addition.
    @State private var closingAssignment: ShelfAssignmentSession?
    // Last copy taken out of a shelf via the trash button, kept briefly so the
    // removal can be undone (toast button or ⌘Z) instead of confirmed up front.
    @State private var recentUnplace: UnplacedCopy?
    @State private var pendingDelete: RecordCopy?
    @State private var confirmRemoveSold = false
    /// Count for the question, taken when it is asked – `soldInShelves` walks
    /// the whole collection and must not run on every rebuild of the page.
    @State private var soldToRemove = 0
    @State private var sortingShelf: Shelf?
    @State private var error: String?

    // Search inside the shelf view only lists matches with their location; it
    // never changes the selection below. `focusCopy` is the spine picked in the
    // strip.
    /// The committed (debounced) query; the field keeps its own text while typing.
    @State private var searchQuery = ""
    @State private var searchResults = ShelfSearchResults()
    @State private var searchIndex = SearchIndex<UUID>()
    /// Set when records change; the index is rebuilt on the next search only.
    @State private var searchIndexStale = true
    @State private var changes = LibraryChanges.shared
    @State private var focusCopy: RecordCopy?
    /// While the search field has focus, ⌘Z belongs to its text, not to the
    /// "Aus Fach entfernt" toast.
    @FocusState private var searchFocused: Bool
    /// Whether ⌘F has revealed the search bar (see `SearchReveal`).
    @State private var searchPresented = false
    /// Width of "Vermisst" and the sold-records note beside the search bar.
    @State private var statusWidth: CGFloat = 0
    private var showsSearchBar: Bool { searchPresented || !searchQuery.isEmpty }

    /// The account the collection shows (see `DiscogsAccount.current`).
    private var owner: String? { DiscogsAccount.current(in: accounts)?.username }

    // Recomputed only when the underlying placement/style data actually changes
    // (see `statsSignature`), not on every keystroke or unrelated re-render.
    @State private var shelfStats: [UUID: ShelfStatistics] = [:]
    @State private var rangeLabels = ShelfLabels()
    /// Per-shelf results behind `shelfStats` and `rangeLabels`; only shelves
    /// whose records changed are computed again.
    @State private var shelfContent = ShelfContentCache()
    @State private var palette = StylePalette()
    @State private var settingsTab: AppSettingsView.Tab?
    /// The side the next cabinet slides in from (see `show(_:)`).
    @State private var cabinetEdge: Edge = .trailing
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range

    /// Compartments of the active cabinets, cabinet by cabinet in reading
    /// order. Inactive cabinets keep their records but stay off this page.
    private var shelves: [Shelf] { Shelf.inUse(allShelves) }
    private var activeCabinets: [Cabinet] { cabinets.filter(\.isActive) }
    /// The cabinet drawn at the top: the one holding the selected compartment.
    private var shownCabinet: Cabinet? {
        committedShelf?.cabinet.flatMap { cabinet in activeCabinets.first { $0.id == cabinet.id } } ?? activeCabinets.first
    }
    private var committedShelf: Shelf? { shelves.first { $0.id == highlight } }
    private var detailShelf: Shelf? { committedShelf }

    /// Evaluated on every render of this page (a click on a spine, too), so
    /// it must not walk the records. Every write reports itself in
    /// `LibraryChanges`: positions, locks and names via `PositionService.save`,
    /// cabinets via `CabinetService`, metadata via the sync and Discogs
    /// reloads. The counts are a safety net for anything arriving otherwise
    /// (the first load, the demo's sample data).
    private var statsSignature: Int {
        var hasher = Hasher()
        hasher.combine(changes.libraryVersion)
        hasher.combine(changes.placementsVersion)
        hasher.combine(changes.shelvesVersion)
        hasher.combine(allCopies.count)
        hasher.combine(allShelves.count)
        hasher.combine(cabinets.count)
        hasher.combine(labelStyle)
        return hasher.finalize()
    }

    /// Records that are no longer in the current Discogs collection (sold,
    /// given away, or from another account) but still hold a shelf position.
    /// The sync keeps their place on purpose — they may come back — so the
    /// shelf page points them out instead.
    private var soldInShelves: [RecordCopy] {
        let owner = owner
        // Deactivated cabinets are put away and not shown here; their records
        // are neither counted nor taken out from this page.
        return allCopies.filter { ($0.shelf?.isInUse ?? false) && $0.leftCurrentCollection(owner: owner) }
    }

    private var missingIDs: Set<UUID> { Set(missingMarks.map(\.copyID)) }

    /// Records marked "Vermisst": those still standing in a shelf in
    /// use (shelf order) and those waiting to be sorted in (by artist) – the
    /// list to work through while sorting the rest.
    private var missingCopies: [RecordCopy] {
        let ids = missingIDs
        guard !ids.isEmpty else { return [] }
        let owner = owner
        let excluded = Set(exclusions.map(\.copyID))
        let marked = allCopies.filter { ids.contains($0.id) }
        let placed = marked
            .filter { $0.shelf?.isInUse ?? false }
            .sorted { a, b in
                guard let sa = a.shelf, let sb = b.shelf else { return false }
                if sa.id != sb.id { return Shelf.physicalOrder(sa, sb) }
                return a.positionInShelf < b.positionInShelf
            }
        let waiting = marked.filter { ShelfAssignmentPresentation.isCandidate($0, owner: owner, excluding: excluded) }
        return placed + ShelfAssignmentPresentation.sortedByArtist(waiting)
    }

    private func forgetCopies() {
        closingAssignment = nil; assignment = nil
        focusCopy = nil; placement = nil; recentUnplace = nil
        pendingDelete = nil; confirmRemoveSold = false
    }

    private func setMissing(_ copy: RecordCopy, _ missing: Bool) {
        do { try PositionService(context: context).setMissing([copy], missing) }
        catch { self.error = error.reportedMessage() }
    }

    /// Jumps to a record from the "Vermisst" list: its shelf with the
    /// record picked, or – without a shelf – where it belongs alphabetically.
    private func showMissing(_ copy: RecordCopy) {
        guard let shelf = copy.shelf else { startPlacement(copy); return }
        selectShelf(shelf)
        focusCopy = copy
    }

    private func removeSoldFromShelves() {
        let sold = soldInShelves
        if let focus = focusCopy, sold.contains(where: { $0.id == focus.id }) { focusCopy = nil }
        // One transaction: a failure halfway must not leave some sold records
        // out and others still in, with gaps in between.
        do { try PositionService(context: context).unplace(sold) }
        catch { self.error = error.reportedMessage() }
    }

    /// Runs only when the (debounced) query or the data changes, never in
    /// `body`: plain substring checks against the prebuilt index instead of
    /// Unicode-comparing every record's text, tracks included.
    private func applySearch() {
        let words = SearchIndex<UUID>.words(searchQuery)
        guard !words.isEmpty else { searchResults = ShelfSearchResults(); return }
        if searchIndexStale {
            searchIndex = SearchIndex(allCopies, id: \.id, text: SortingService.searchText)
            searchIndexStale = false
        }
        let excluded = Set(exclusions.map(\.copyID))
        let owner = owner
        var placed: [RecordCopy] = [], unplaced: [RecordCopy] = []
        for copy in allCopies where searchIndex.matches(copy.id, words) {
            // Records in an inactive cabinet are put away: neither shown nor offered for placing.
            if let shelf = copy.shelf { if shelf.isInUse { placed.append(copy) } }
            // "Nicht im Regal" and records outside the current collection
            // aren't meant to be placed (same rule as "Platte hinzufügen").
            else if ShelfAssignmentPresentation.isCandidate(copy, owner: owner, excluding: excluded) { unplaced.append(copy) }
        }
        func sorted(_ copies: [RecordCopy], _ limit: Int) -> [RecordCopy] {
            Array(copies.map { (SortingService.sortKey($0), $0) }
                .sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
                .prefix(limit).map(\.1))
        }
        searchResults = ShelfSearchResults(
            placed: sorted(placed, ShelfSearchResults.placedLimit),
            unplaced: sorted(unplaced, ShelfSearchResults.unplacedLimit),
            hidden: max(0, placed.count - ShelfSearchResults.placedLimit) + max(0, unplaced.count - ShelfSearchResults.unplacedLimit),
            litShelfIDs: Set(placed.compactMap { $0.shelf?.id })
        )
    }

    /// Shared slot count for every spine row, so a sleeve has the same width in
    /// each compartment and the rows simply show how many records stand there —
    /// not a fill level.
    private var spineSlots: Int {
        max(40, shelfStats.values.map(\.count).max() ?? 0)
    }

    var body: some View {
        GeometryReader { geometry in
            let lit = searchResults.litShelfIDs
            VStack(alignment: .leading, spacing: 28) {
                if DemoMode.isActive { DemoBanner() }
                if nothingPlaced {
                    // Typically right after a new install and the first sync.
                    AppBanner(message: "Noch keine Platte steht in einem Fach. Hast du eine Sicherung deiner Fach-Belegung, stellst du sie hier wieder her.",
                              kind: .info, actionTitle: "Belegung wiederherstellen …", action: { settingsTab = .backup })
                }
                header
                    // The search results float over the rack below.
                    .zIndex(1)
                if activeCabinets.count > 1 { cabinetSwitcher }
                ShelfFurniture(
                    shelves: shownCabinet.map { cabinet in shelves.filter { $0.cabinet?.id == cabinet.id } } ?? shelves,
                    rows: shownCabinet?.rows ?? ShelfGeometry.rows,
                    columns: shownCabinet?.columns ?? ShelfGeometry.columns,
                    stats: { shelfStats[$0.id] ?? ShelfStatistics(shelf: $0) },
                    rangeLabel: { rangeLabels[$0.id] },
                    palette: palette,
                    selectedID: detailShelf?.id,
                    litIDs: lit,
                    lockPreview: lockPreview,
                    select: selectShelf,
                    menu: shelfMenu(for:)
                )
                // A compact overview with roughly KALLAX-like proportions, so the
                // compartment area below (strip + table) gets most of the height.
                .frame(height: ShelfFurnitureMetrics.height(rows: shownCabinet?.rows ?? ShelfGeometry.rows))
                .frame(maxWidth: furnitureWidth(geometry.size.width), alignment: .leading)
                // Another cabinet slides in from the side it lies on.
                .id(shownCabinet?.id)
                .transition(AppStyle.reduceMotion ? .opacity : .push(from: cabinetEdge))
                shelfDetail
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, AppStyle.pagePadding + 4)
            .padding(.top, AppStyle.pagePadding)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { deselect() })
            .background { AmbientBackdrop(color: ambientColor) }
            .onExitCommand { if placement != nil { cancelPlacement() } else { deselect() } }
            .overlay(alignment: .bottom) { undoToast }
        }
        .task(id: statsSignature) {
            shelfContent.refresh(allShelves, version: changes.libraryVersion)
            shelfStats = Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, shelfContent.stats(for: $0)) })
            rangeLabels = ShelfRangeLabels.compute(for: allShelves, style: labelStyle, ends: shelfContent.ends)
            ensureShelfSelected()
            refreshPlacement()
            searchIndexStale = true
            if !searchQuery.isEmpty { applySearch() }
        }
        .onChange(of: searchQuery) { applySearch() }
        .settingsOpener($settingsTab)
        .searchReveal(isPresented: $searchPresented, focus: $searchFocused, query: searchQuery)
        .animation(AppStyle.searchBarAnimation, value: showsSearchBar)
        // Another account synced: other records count as in the collection.
        .onChange(of: owner) { searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        // Metadata and tracklist updates don't show up in `statsSignature`.
        .onChange(of: changes.libraryVersion) { searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        .onChange(of: changes.tracksVersion) { searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        .onAppear { takePlacingRequest() }
        .onChange(of: requests.placing) { takePlacingRequest() }
        // Marks change without touching `statsSignature` (menu, table, sheet).
        .onChange(of: missingIDs) { refreshPlacement() }
        // Settings (other window) rebuilt cabinets, restored a backup or reset
        // the locations: the sheet's list and target shelf may be stale or gone.
        .onChange(of: changes.shelvesVersion) {
            if assignment != nil { AppLog.info("Regal", "„Platte hinzufügen“ geschlossen: Regale wurden in den Einstellungen geändert") }
            assignment = nil; showsNameEditor = false; sortingShelf = nil
        }
        // "Alles zurücksetzen" deleted every record: nothing here may keep
        // pointing at one – reading a deleted model crashes.
        .onReceive(NotificationCenter.default.publisher(for: .plattenregalDidReset)) { _ in forgetCopies() }
        .sheet(item: $assignment, onDismiss: {
            // The shelf behind the sheet follows the additions only now, so
            // nothing rebuilds the sheet while records are being added.
            if let copy = closingAssignment?.lastAdded { focusCopy = copy }
            closingAssignment = nil
        }) { session in
            ShelfAssignmentView(session: session, owner: owner, rangeLabel: rangeLabels[session.shelf.id], labels: rangeLabels) { copy in
                // Its own shelf instead: no record to pick up here afterwards.
                closingAssignment = nil
                assignment = nil
                startPlacement(copy)
            }
        }
        .confirmationDialog(
            soldToRemove == 1 ? "Platte ohne Collection aus dem Regal nehmen?" : "\(soldToRemove) Platten ohne Collection aus dem Regal nehmen?",
            isPresented: $confirmRemoveSold
        ) {
            Button("Aus Regal nehmen") { removeSoldFromShelves() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Diese Platten sind nicht (mehr) in deiner Discogs-Collection – verkauft, verschenkt oder aus einem anderen Discogs-Konto –, stehen hier aber noch in ihren Fächern. Die übrigen Platten rücken auf. Kommen sie später zurück in die Collection, kannst du sie wieder einsortieren.")
        }
        .confirmationDialog(
            "Exemplar endgültig aus der Sammlung löschen?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Aus Sammlung löschen", role: .destructive) {
                if let copy = pendingDelete { delete(copy) }
                pendingDelete = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Die Platte ist nicht (mehr) in deiner Discogs-Collection. Löschen entfernt sie samt Fach und Position; die übrigen Platten im Fach rücken auf. Das lässt sich nicht rückgängig machen.")
        }
        .confirmationDialog(
            "Physische Reihenfolge ändern?",
            isPresented: Binding(get: { sortingShelf != nil }, set: { if !$0 { sortingShelf = nil } })
        ) {
            Button("Fach alphabetisch sortieren") {
                if let shelf = sortingShelf, !shelf.isDeleted, shelf.modelContext != nil {
                    do { try PositionService(context: context).sortAlphabetically(shelf) }
                    catch { self.error = error.reportedMessage() }
                }
                sortingShelf = nil
            }
            Button("Abbrechen", role: .cancel) { sortingShelf = nil }
        } message: {
            Text("Die gespeicherten Positionen dieses Fachs ändern sich. Stelle die Platten anschließend auch im Regal in diese Reihenfolge.")
        }
        .alert(
            "Änderung nicht möglich",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) { Button("OK") {} } message: { Text(error ?? "") }
    }

    /// The mood behind the glass: the selected compartment's main genre color.
    private var ambientColor: Color? {
        guard let shelf = detailShelf, !shelf.isReserved,
              let style = shelfStats[shelf.id]?.dominantColorStyle else { return nil }
        return palette.color(for: style, solid: true)
    }

    /// Records are there, but none stands in a shelf yet.
    private var nothingPlaced: Bool {
        !DemoMode.isActive && !allCopies.isEmpty && !allCopies.contains { $0.shelf != nil }
    }

    /// Narrow cabinets (1 × 4, 2 × 2 …) keep roughly square compartments
    /// instead of stretching across the whole page.
    private func furnitureWidth(_ available: CGFloat) -> CGFloat {
        let columns = shownCabinet?.columns ?? ShelfGeometry.columns
        // Four columns and more use the whole width, like the KALLAX always did.
        guard columns < 4 else { return available }
        return min(available, max(CGFloat(columns) * 300, 380))
    }

    /// One tab per active cabinet; ⌘← / ⌘→ step through them.
    private var cabinetSwitcher: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            GlassSegmentedPicker(
                selection: Binding(get: { shownCabinet?.id }, set: { id in
                    if let cabinet = activeCabinets.first(where: { $0.id == id }) { show(cabinet) }
                }),
                options: activeCabinets.map { Optional($0.id) }
            ) { id in
                Text(activeCabinets.first { $0.id == id }?.name ?? "")
            }
            .accessibilityLabel("Regal")
            Text(shownCabinet.map { "\($0.sizeText) · \(AppStyle.records($0.recordCount))" } ?? "")
                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button("Vorheriges Regal") { stepCabinet(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .hidden().frame(width: 0)
            Button("Nächstes Regal") { stepCabinet(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .hidden().frame(width: 0)
        }
        .padding(.bottom, -14)
        .help("Zwischen den Regalen wechseln: ⌘← / ⌘→")
    }

    private func stepCabinet(_ offset: Int) {
        guard let current = shownCabinet, let index = activeCabinets.firstIndex(where: { $0.id == current.id }) else { return }
        let next = (index + offset + activeCabinets.count) % activeCabinets.count
        show(activeCabinets[next])
    }

    /// Selects the cabinet's first compartment with records (else its first one).
    private func show(_ cabinet: Cabinet) {
        guard cabinet.id != shownCabinet?.id else { return }
        let own = shelves.filter { $0.cabinet?.id == cabinet.id }
        guard let shelf = own.first(where: { !$0.isReserved && !$0.copies.isEmpty }) ?? own.first else { return }
        let from = activeCabinets.firstIndex { $0.id == shownCabinet?.id } ?? 0
        let to = activeCabinets.firstIndex { $0.id == cabinet.id } ?? 0
        cabinetEdge = to > from ? .trailing : .leading
        withAnimation(AppStyle.layoutAnimation ?? AppStyle.fadeAnimation) { selectShelf(shelf) }
    }

    /// The search bar (only after ⌘F) and the status controls beside it;
    /// collapsed when neither is there, so the rack moves up. Always
    /// mounted, see `searchBarSlot`.
    @ViewBuilder private var header: some View {
        // Both walk the whole collection: once per body, not per use.
        let missing = missingCopies
        let sold = soldInShelves.count
        let hasStatus = !missing.isEmpty || sold > 0
        // The bar centered under the page switch in the toolbar, the status
        // on the right; the bar keeps clear of the status on both sides,
        // so it stays centered without running into it.
        ZStack {
            ShelfSearchField(
                query: $searchQuery,
                focused: $searchFocused,
                matches: searchResults.placed,
                unplaced: searchResults.unplaced,
                hidden: searchResults.hidden,
                labels: rangeLabels,
                missing: missingIDs,
                onClear: { searchQuery = "" },
                place: startPlacement
            )
            .frame(maxWidth: AppStyle.searchBarMaxWidth)
            .padding(.horizontal, statusWidth > 0 ? statusWidth + AppStyle.rowSpacing : 0)
            .searchBarSlot(shown: showsSearchBar)
            HStack(spacing: AppStyle.rowSpacing) {
                if !missing.isEmpty {
                    MissingCopiesControl(copies: missing, labels: rangeLabels, show: showMissing,
                                         found: { setMissing($0, false) })
                }
                if sold > 0 {
                    ShelfStatusControl(soldInShelves: sold, removeSold: { soldToRemove = sold; confirmRemoveSold = true })
                        .frame(height: AppStyle.controlHeight)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { statusWidth = $0 }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // 28: the page's stack spacing (see `body`).
        .searchBarSlot(shown: showsSearchBar || hasStatus, collapsedSpacing: 28)
    }

    @ViewBuilder private var shelfDetail: some View {
        if let shown = detailShelf {
            let stats = shelfStats[shown.id] ?? ShelfStatistics(shelf: shown)
            let selectedCopy = focusCopy.flatMap { $0.shelf?.id == shown.id ? $0 : nil }
            // Spines are drawn in this order; a click maps to the copy at its
            // index, never by `positionInShelf` (which may have gaps or doubles).
            let ordered = PositionService(context: context).ordered(shown)
            let spot = placement.flatMap { !$0.found && $0.spot?.shelf.id == shown.id ? $0.spot : nil }
            let missing = missingIDs
            let missingSlots = Set(ordered.indices.filter { missing.contains(ordered[$0].id) }.map { $0 + 1 })
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                if let placement {
                    PlacementCard(
                        placement: placement,
                        labels: rangeLabels,
                        missing: missingIDs,
                        choose: choosePlacementSpot,
                        confirm: confirmPlacement,
                        cancel: cancelPlacement
                    )
                    .transition(AppStyle.funnelTransition())
                }
                VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                    detailHeader(for: shown, stats: stats)
                    if !shown.isReserved && stats.count > 0 {
                        ShelfPositionStrip(stats: stats, slots: spineSlots, palette: palette, selectedCopy: selectedCopy,
                                           selectedSlot: selectedCopy.flatMap { copy in ordered.firstIndex { $0.id == copy.id } }.map { $0 + 1 },
                                           insertionPosition: spot?.position, missingSlots: missingSlots, copies: ordered) { slot in
                            if ordered.indices.contains(slot - 1) { toggleSelection(ordered[slot - 1]) }
                        }
                    }
                }
                if shown.isReserved || shown.copies.isEmpty {
                    ShelfLockReader(shelf: shown, preview: lockPreview) { locked in
                        if locked {
                            detailNote("Gesperrtes Fach – nicht für Platten vorgesehen. Per Rechtsklick auf das Fach kannst du es entsperren.")
                        } else {
                            HStack(spacing: AppStyle.itemSpacing) {
                                detailNote("Noch keine Platten in diesem Fach.")
                                Button("Platte hinzufügen") { startAssignment(shown) }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                } else {
                    ShelfCopyTable(
                        shelf: shown,
                        shelves: shelves,
                        rangeLabels: rangeLabels,
                        owner: owner,
                        missing: missingIDs,
                        focusCopy: focusCopy,
                        select: { copy in
                            if let copy { if focusCopy?.id != copy.id { focusCopy = copy } } else { deselect() }
                        },
                        placed: showPlaced,
                        find: startPlacement,
                        unplace: unplace,
                        delete: { pendingDelete = $0 },
                        setMissing: setMissing
                    )
                    .padding(.vertical, 4)
                    .appGlassSurface(cornerRadius: AppStyle.cardRadius + 4)
                    .modifier(FadeInOnChange(value: shown.id))
                }
            }
        } else {
            detailNote("Wähle ein Fach im Regal oder suche oben nach einer Platte.")
        }
    }

    private func detailNote(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    private func detailHeader(for shown: Shelf, stats: ShelfStatistics) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppStyle.rowSpacing) {
            // Title, indicator and the plus button follow the options switch via
            // `ShelfLockReader`, so they change together with the hatching.
            ShelfLockReader(shelf: shown, preview: lockPreview) { locked in
                Text(locked ? (shown.name.isEmpty ? "Gesperrtes Fach" : shown.name) : (rangeLabels[shown.id] ?? "Leeres Fach"))
                    .contentTransition(.opacity)
            }
            .font(AppStyle.pageTitle)
            .lineLimit(1)
            .layoutPriority(1)
            .popover(isPresented: $showsNameEditor, arrowEdge: .bottom) {
                // Fresh state per shelf: a name seeded for one shelf must
                // never be saved onto another.
                ShelfNamePopover(shelf: shown).id(shown.id)
            }
            ShelfLockReader(shelf: shown, preview: lockPreview) { locked in
                if locked {
                    Image(systemName: "lock")
                } else {
                    Text(AppStyle.records(stats.count)).monospacedDigit()
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: AppStyle.itemSpacing)
            HStack(spacing: AppStyle.tightSpacing) {
                ShelfLockReader(shelf: shown, preview: lockPreview) { locked in
                    IconButton(systemImage: "plus", help: "Platte hinzufügen") {
                        startAssignment(shown)
                    }
                    .disabled(locked)
                }
            }
            .foregroundStyle(.secondary)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        }
    }

    @ViewBuilder private var undoToast: some View {
        if let entry = recentUnplace {
            HStack(spacing: 12) {
                Text("Aus Fach entfernt")
                // A shelf locked meanwhile takes no records, and a record marked
                // "Nicht im Regal" meanwhile stays out; nothing to undo then.
                if canUndo(entry) {
                    Button("Rückgängig", action: undoUnplace)
                        .buttonStyle(.link)
                        .keyboardShortcut(searchFocused ? nil : KeyboardShortcut("z", modifiers: .command))
                }
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 16)
            .transition(AppStyle.funnelTransition(from: .bottom))
            .task(id: entry.id) {
                try? await Task.sleep(for: .seconds(6))
                if recentUnplace?.id == entry.id {
                    withAnimation(AppStyle.standardAnimation) { recentUnplace = nil }
                }
            }
        }
    }

    /// The compartment's right-click menu (an `AppMenu`, like the collection's).
    @ViewBuilder private func shelfMenu(for shelf: Shelf) -> some View {
        let locked = lockPreview.isLocked(shelf)
        Button("Inhalt anzeigen") { selectShelf(shelf) }
        Button("Platte hinzufügen …") { selectShelf(shelf); startAssignment(shelf) }
            .disabled(locked)
        Button("Alphabetisch sortieren …") { sortingShelf = shelf }
            .disabled(locked || shelf.copies.count < 2)
        Divider()
        if locked {
            Button("Namen ändern …") { selectShelf(shelf); showsNameEditor = true }
            Button("Fach entsperren") { setLocked(shelf, false) }
        } else {
            Button {
                setLocked(shelf, true)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Fach sperren")
                    if !shelf.copies.isEmpty {
                        Text("Nur leere Fächer lassen sich sperren").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!shelf.copies.isEmpty)
        }
    }

    /// Shows the new state at once via `lockPreview` and saves once the
    /// compartment has faded over: saving makes the page recompute, which
    /// would stutter mid-animation. Unlocking drops the name as well.
    private func setLocked(_ shelf: Shelf, _ locked: Bool) {
        withAnimation(AppStyle.standardAnimation) { lockPreview.set(locked, for: shelf) }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !shelf.isDeleted, shelf.modelContext != nil else { return lockPreview.clear(shelf) }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                do { try PositionService(context: context).configure(shelf, name: locked ? shelf.name : "", isReserved: locked) }
                catch { self.error = error.reportedMessage() }
                lockPreview.clear(shelf)
            }
        }
    }

    /// New records go to their alphabetical place in the compartment.
    private func startAssignment(_ shelf: Shelf) {
        let session = ShelfAssignmentSession(shelf: shelf)
        closingAssignment = session
        assignment = session
    }

    private func selectShelf(_ shelf: Shelf) {
        searchQuery = ""; focusCopy = nil
        // Picking the other fitting shelf switches the spot; any other shelf ends the placement.
        if let placement {
            if let index = placement.spots.firstIndex(where: { $0.shelf.id == shelf.id }) {
                self.placement?.chosen = index
            } else {
                cancelPlacement()
            }
        }
        if highlight != shelf.id { showsNameEditor = false }
        withAnimation(AppStyle.standardAnimation) { highlight = shelf.id }
    }

    /// After the quick editor changed where a copy stands: follow it to its
    /// new shelf, or drop the focus when it left the shelves altogether.
    private func showPlaced(_ copy: RecordCopy) {
        guard let shelf = copy.shelf else {
            if focusCopy?.id == copy.id { focusCopy = nil }
            return
        }
        if highlight != shelf.id { withAnimation(AppStyle.standardAnimation) { highlight = shelf.id } }
        focusCopy = copy
    }

    private func toggleSelection(_ copy: RecordCopy) {
        if focusCopy?.id == copy.id { deselect() } else { focusCopy = copy }
    }

    // Returns the strip to its resting state; the shelf itself stays selected.
    private func deselect() {
        guard focusCopy != nil else { return }
        focusCopy = nil
    }

    /// There is always a selected shelf: the bottom-left compartment (where the
    /// alphabet starts), or the first occupied one if that is empty/reserved.
    /// An existing valid selection (e.g. "im Regal zeigen") is kept.
    private func ensureShelfSelected() {
        if let highlight, shelves.contains(where: { $0.id == highlight }) { return }
        let cabinet = activeCabinets.first
        let bottomLeft = ((cabinet?.rows ?? ShelfGeometry.rows) - 1) * (cabinet?.columns ?? ShelfGeometry.columns) + 1
        let occupied = { (shelf: Shelf) in !shelf.isReserved && !shelf.copies.isEmpty }
        highlight = shelves.first { $0.cabinet?.id == cabinet?.id && $0.sortOrder == bottomLeft && occupied($0) }?.id
            ?? shelves.first(where: occupied)?.id
            ?? shelves.first?.id
    }

    // MARK: Placement

    private func takePlacingRequest() {
        guard let id = requests.placing else { return }
        requests.placing = nil
        if let copy = allCopies.first(where: { $0.id == id }) { startPlacement(copy) }
    }

    private func startPlacement(_ copy: RecordCopy) {
        searchQuery = ""; focusCopy = nil; showsNameEditor = false
        var new = Placement(copy: copy, shelves: shelves)
        new.excluded = exclusions.contains { $0.copyID == copy.id }
        new.missing = missingIDs.contains(copy.id)
        withAnimation(AppStyle.standardAnimation) {
            placement = new
            if let shelf = new.spot?.shelf { highlight = shelf.id }
        }
        // A placed record is pulled out in the strip and selected in the table.
        if new.found && new.putAwayIn == nil { focusCopy = copy }
    }

    /// Records may change while the card is open (sync, edits in the table):
    /// recompute the spots, keeping the chosen shelf if it still fits. The
    /// card closes once the record was placed or taken out of its shelf.
    private func refreshPlacement() {
        guard let current = placement else { return }
        let copy = current.copy
        guard copy.modelContext != nil, (copy.shelf != nil) == current.found else { placement = nil; return }
        var updated = Placement(copy: copy, shelves: shelves)
        updated.excluded = current.excluded
        updated.missing = missingIDs.contains(copy.id)
        if let shelfID = current.spot?.shelf.id, let index = updated.spots.firstIndex(where: { $0.shelf.id == shelfID }) {
            updated.chosen = index
        }
        placement = updated
        if let shelf = updated.spot?.shelf, highlight != shelf.id { highlight = shelf.id }
    }

    private func choosePlacementSpot(_ index: Int) {
        guard let placement, placement.spots.indices.contains(index) else { return }
        self.placement?.chosen = index
        withAnimation(AppStyle.standardAnimation) { highlight = placement.spots[index].shelf.id }
    }

    private func confirmPlacement() {
        guard let placement, let spot = placement.spot else { return }
        if placement.found {
            // Standing where it should: a "Vermisst" mark is settled.
            if placement.missing { setMissing(placement.copy, false) }
            withAnimation(AppStyle.standardAnimation) { self.placement = nil }
            return
        }
        do {
            try PositionService(context: context).move(placement.copy, to: spot.shelf, position: spot.position, found: true)
            withAnimation(AppStyle.standardAnimation) { self.placement = nil }
            focusCopy = placement.copy
        } catch { self.error = error.reportedMessage() }
    }

    private func cancelPlacement() {
        withAnimation(AppStyle.standardAnimation) { placement = nil }
    }

    private func unplace(_ copy: RecordCopy) {
        guard let shelf = copy.shelf else { return }
        let entry = UnplacedCopy(copy: copy, shelf: shelf, position: copy.positionInShelf)
        if focusCopy?.id == copy.id { focusCopy = nil }
        do {
            try PositionService(context: context).unplace(copy)
            withAnimation(AppStyle.standardAnimation) { recentUnplace = entry }
        } catch { self.error = error.reportedMessage() }
    }

    private func canUndo(_ entry: UnplacedCopy) -> Bool {
        // The compartment may be gone meanwhile (cabinet made smaller, backup
        // restored, reset); reading a deleted model would crash.
        !entry.copy.isDeleted && entry.copy.modelContext != nil
            && !entry.shelf.isDeleted && entry.shelf.modelContext != nil
            && entry.copy.shelf == nil && !entry.shelf.isReserved
            && !exclusions.contains { $0.copyID == entry.copy.id }
    }

    private func undoUnplace() {
        guard let entry = recentUnplace else { return }
        withAnimation(AppStyle.standardAnimation) { recentUnplace = nil }
        // Someone may have re-placed the copy meanwhile; don't yank it back.
        guard canUndo(entry) else { return }
        let position = min(max(entry.position, 1), entry.shelf.copies.count + 1)
        do { try PositionService(context: context).move(entry.copy, to: entry.shelf, position: position) }
        catch { self.error = error.reportedMessage() }
    }

    private func delete(_ copy: RecordCopy) {
        // Records still in the Discogs collection leave via Discogs (see the table menu).
        guard !copy.isInCurrentCollection(owner: owner) else { return }
        // A deleted model must not stay referenced: reading it afterwards
        // (strip selection, undo toast, placement card) would crash.
        if focusCopy?.id == copy.id { focusCopy = nil }
        if recentUnplace?.copy.id == copy.id { recentUnplace = nil }
        if placement?.copy.id == copy.id { placement = nil }
        do { try PositionService(context: context).delete(copy) }
        catch { self.error = error.reportedMessage() }
    }
}

/// Fades the content in afresh whenever `value` changes, e.g. the table
/// when another compartment is picked, without rebuilding it.
private struct FadeInOnChange<Value: Equatable>: ViewModifier {
    let value: Value
    @State private var opacity: Double = 1

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onChange(of: value) {
                opacity = 0
                withAnimation(AppStyle.fadeAnimation) { opacity = 1 }
            }
    }
}
