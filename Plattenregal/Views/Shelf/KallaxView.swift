import SwiftUI
import SwiftData

/// What other pages ask of the shelf page. An object, not a binding: pages
/// live in separate hosting views (see `PageStack`), and only Observation
/// reaches across.
@Observable final class ShelfRequests {
    /// A record to show: where it stands and between which records, or –
    /// without a shelf – where it belongs.
    var placing: UUID?
}

/// What is typed into the search field in the toolbar while the shelf page is
/// shown (see `ToolbarSearchField`). An object, read by the page itself: the
/// page is built once (see `PageStack`).
@Observable final class ShelfSearch {
    var text = ""
}

/// The shelf page as one calm column: the KALLAX drawn as a single piece of
/// furniture and the selected compartment underneath at full width with
/// a cover grid or compact table. The search sits in the toolbar; its
/// matches float over the top of the page.
struct KallaxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shelf.number) private var allShelves: [Shelf]
    @Query(sort: \Cabinet.sortOrder) private var cabinets: [Cabinet]
    @Query private var allCopies: [RecordCopy]
    @Query private var exclusions: [OptimizationExclusion]
    @Query private var missingMarks: [MissingCopyMark]
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true
    @Query private var accounts: [DiscogsAccount]
    /// The compartment selected in the rack.
    @State private var highlight: UUID?
    /// "Im Regal anzeigen" / "Platz im Regal finden" from other pages; taken
    /// over into `placement` right away.
    let requests: ShelfRequests
    /// The text of the search field in the toolbar.
    let search: ShelfSearch
    @Environment(\.searchRequests) private var searchRequests
    /// The record being sorted in and the spots it fits alphabetically.
    @State private var placement: Placement?
    /// "Namen ändern …" from a locked compartment's menu.
    @State private var showsNameEditor = false
    /// Cabinet tab whose right-click menu is open, and where.
    @State private var cabinetMenu: (id: UUID, anchor: UnitPoint)?
    /// Cabinet tab whose name popover is open ("Regal umbenennen …").
    @State private var renamingCabinet: UUID?
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
    /// `soldInShelves.count`, taken whenever records, places or the account
    /// change – not on every click in the table.
    @State private var soldCount = 0
    /// The open "Sortierung prüfen".
    @State private var sortCheck: ShelfSortCheckRequest?
    @State private var error: String?

    // Search inside the shelf view only lists matches with their location; it
    // never changes the selection below. `focusCopy` is the record picked in
    // the table.
    /// The committed (debounced) query; `search.text` is what is being typed.
    @State private var searchQuery = ""
    @State private var searchResults = ShelfSearchResults()
    @State private var searchIndex = SearchIndex<UUID>()
    /// Set when records change; the index is rebuilt on the next search only.
    @State private var searchIndexStale = true
    @State private var changes = LibraryChanges.shared
    @State private var focusCopy: RecordCopy?
    /// Repeating an external request for the same copy must reveal it again.
    @State private var focusRevision = 0
    /// Scroll anchors survive a visit to an empty or reserved compartment.
    @State private var contentsSession = ShelfContentsSession()
    /// While the search field has focus, ⌘Z belongs to its text, not to the
    /// "Aus Fach entfernt" toast.
    private var searchFocused: Bool { searchRequests?.fieldFocused ?? false }

    /// The account the collection shows (see `DiscogsAccount.current`).
    private var owner: String? { DiscogsAccount.current(in: accounts)?.username }

    // Recomputed only when the underlying placement/style data actually changes
    // (see `statsSignature`), not on every keystroke or unrelated re-render.
    @State private var shelfStats: [UUID: ShelfStatistics] = [:]
    @State private var rangeLabels = ShelfLabels()
    /// Per-shelf results behind `shelfStats` and `rangeLabels`; only shelves
    /// whose records changed are computed again.
    @State private var shelfContent = ShelfContentCache()
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

    /// Evaluated on every render of this page (a click in the table, too), so
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

    /// Empty while "Vermisst" is off in the settings: no marks shown anywhere
    /// on this page (they are kept, and return when it is switched on again).
    private var missingIDs: Set<UUID> { missingEnabled ? Set(missingMarks.map(\.copyID)) : [] }

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
        closingAssignment = nil; assignment = nil; sortCheck = nil
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
        focusRevision += 1
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
        // Ties (two copies of one album) by ID, so rows don't swap while typing.
        func sorted(_ copies: [RecordCopy], _ limit: Int) -> [RecordCopy] {
            Array(SortingService.sorted(copies).prefix(limit))
        }
        searchResults = ShelfSearchResults(
            placed: sorted(placed, ShelfSearchResults.placedLimit),
            unplaced: sorted(unplaced, ShelfSearchResults.unplacedLimit),
            hidden: max(0, placed.count - ShelfSearchResults.placedLimit) + max(0, unplaced.count - ShelfSearchResults.unplacedLimit),
            litShelfIDs: Set(placed.compactMap { $0.shelf?.id })
        )
    }

    /// Space between the page's big blocks: banners, header, rack, compartment.
    private static let blockSpacing: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let lit = searchResults.litShelfIDs
            VStack(alignment: .leading, spacing: Self.blockSpacing) {
                if DemoMode.showsBanner { DemoBanner() }
                if nothingPlaced {
                    // Typically right after a new install and the first sync.
                    AppBanner(message: String(localized: "Noch keine Platte steht in einem Fach. Hast du eine Sicherung deiner Fach-Belegung, stellst du sie hier wieder her."),
                              kind: .info, actionTitle: String(localized: "Belegung wiederherstellen …"), action: { settingsTab = .backup })
                }
                // The header brings its own spacing below, so a collapsed
                // header leaves no gap (see `header`).
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: Self.blockSpacing) {
                        if activeCabinets.count > 1 { cabinetSwitcher }
                        ShelfFurniture(
                            shelves: shownCabinet.map { cabinet in shelves.filter { $0.cabinet?.id == cabinet.id } } ?? shelves,
                            rows: shownCabinet?.rows ?? ShelfGeometry.rows,
                            columns: shownCabinet?.columns ?? ShelfGeometry.columns,
                            stats: { shelfStats[$0.id] ?? ShelfStatistics(shelf: $0) },
                            rangeLabel: { rangeLabels[$0.id] },
                            selectedID: detailShelf?.id,
                            litIDs: lit,
                            lockPreview: lockPreview,
                            select: selectShelf,
                            add: { shelf in selectShelf(shelf); startAssignment(shelf) },
                            menu: shelfMenu(for:)
                        )
                        // A compact overview with roughly KALLAX-like proportions, so the
                        // compartment area below (strip + table) gets most of the height.
                        // Always the full width, flush with the compartment area below.
                        .frame(height: ShelfFurnitureMetrics.height(rows: shownCabinet?.rows ?? ShelfGeometry.rows))
                        // Another cabinet slides in from the side it lies on.
                        .id(shownCabinet?.id)
                        .transition(AppStyle.reduceMotion ? .opacity : .push(from: cabinetEdge))
                        shelfDetail
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .padding(.horizontal, AppStyle.pagePadding + 4)
            .padding(.top, AppStyle.pagePadding)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { deselect() })
            .onExitCommand { if placement != nil { cancelPlacement() } else { deselect() } }
            .overlay(alignment: .bottom) { undoToast }
            // The matches of the search, right below its field at the
            // right end of the toolbar, floating over the rack.
            .overlay(alignment: .topTrailing) { searchResultsPanel }
        }
        .task(id: statsSignature) {
            shelfContent.refresh(allShelves, version: changes.libraryVersion)
            shelfStats = Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, shelfContent.stats(for: $0)) })
            rangeLabels = ShelfRangeLabels.compute(for: allShelves, style: labelStyle, ends: shelfContent.ends)
            soldCount = soldInShelves.count
            ensureShelfSelected()
            refreshPlacement()
            searchIndexStale = true
            if !searchQuery.isEmpty { applySearch() }
        }
        // Clearing is immediate; typing waits for a short pause, so the page
        // isn't searched on every keystroke.
        .task(id: search.text) {
            let text = search.text
            if !text.isEmpty {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
            if searchQuery != text { searchQuery = text }
        }
        .onChange(of: searchQuery) { _, new in
            applySearch()
            // Cleared here (a match picked, another compartment chosen): the field follows.
            if new.isEmpty && !search.text.isEmpty { search.text = "" }
        }
        .settingsOpener($settingsTab)
        // Another account synced: other records count as in the collection.
        .onChange(of: owner) {
            soldCount = soldInShelves.count
            searchIndexStale = true; if !searchQuery.isEmpty { applySearch() }
        }
        // Metadata and tracklist updates don't show up in `statsSignature`.
        .onChange(of: changes.libraryVersion) { searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        .onChange(of: changes.tracksVersion) { searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        .onAppear { takePlacingRequest() }
        #if DEBUG
        // Screenshots for the tour without clicking: --preview-add opens
        // "Platte hinzufügen" for the selected compartment,
        // --preview-place=Artist the placement card of that artist's record,
        // --preview-sortcheck "Sortierung prüfen" of the first unsorted compartment.
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            try? await Task.sleep(for: .seconds(1))
            if arguments.contains("--preview-add") {
                ensureShelfSelected()
                if let shelf = committedShelf { startAssignment(shelf) }
            } else if let raw = arguments.first(where: { $0.hasPrefix("--preview-place=") }) {
                let artist = String(raw.dropFirst("--preview-place=".count))
                if let copy = allCopies.first(where: { $0.release?.artist == artist }) { startPlacement(copy) }
            } else if arguments.contains("--preview-sortcheck") {
                let shelves = cabinets.flatMap(\.shelves)
                if let shelf = shelves.first(where: { !ShelfSortCheck.steps(PositionService.inShelfOrder($0.copies), by: .current).isEmpty }) {
                    sortCheck = ShelfSortCheckRequest(shelf: shelf)
                }
            }
        }
        #endif
        .onChange(of: requests.placing) { takePlacingRequest() }
        // Marks change without touching `statsSignature` (menu, table, sheet).
        .onChange(of: missingIDs) { refreshPlacement() }
        // Settings (other window) rebuilt cabinets, restored a backup or reset
        // the locations: the sheet's list and target shelf may be stale or gone.
        .onChange(of: changes.shelvesVersion) {
            if assignment != nil { AppLog.info("Regal", "„Platte hinzufügen“ geschlossen: Regale wurden in den Einstellungen geändert") }
            assignment = nil; showsNameEditor = false; sortCheck = nil
        }
        // "Alles zurücksetzen" deleted every record: nothing here may keep
        // pointing at one – reading a deleted model crashes.
        .onReceive(NotificationCenter.default.publisher(for: .plattenregalDidReset)) { _ in forgetCopies() }
        .appPanel(item: $assignment, onDismiss: {
            // The shelf behind the sheet follows the additions only now, so
            // nothing rebuilds the sheet while records are being added.
            if let copy = closingAssignment?.lastAdded {
                focusCopy = copy
                focusRevision += 1
            }
            closingAssignment = nil
        }) { session in
            ShelfAssignmentView(session: session, owner: owner, rangeLabel: rangeLabels[session.shelf.id], labels: rangeLabels,
                                findPlace: { copy in
                                    // Its own shelf instead: no record to pick up here afterwards.
                                    closingAssignment = nil
                                    assignment = nil
                                    startPlacement(copy)
                                },
                                missingCopies: missingCopies,
                                missingEnabled: missingEnabled,
                                showMissing: { copy in
                                    closingAssignment = nil
                                    assignment = nil
                                    showMissing(copy)
                                },
                                found: { setMissing($0, false) })
        }
        .appPanel(item: $sortCheck) { request in
            ShelfSortCheckView(shelf: request.shelf, rangeLabel: rangeLabels[request.shelf.id], close: { sortCheck = nil })
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
        .alert(
            "Änderung nicht möglich",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) { Button("OK") {} } message: { Text(error ?? "") }
    }

    /// Records are there, but none stands in a shelf yet.
    private var nothingPlaced: Bool {
        !DemoMode.isActive && !allCopies.isEmpty && !allCopies.contains { $0.shelf != nil }
    }

    /// One tab per active cabinet; ⌘← / ⌘→ step through them.
    private var cabinetSwitcher: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            GlassSegmentedPicker(
                selection: Binding(get: { shownCabinet?.id }, set: { id in
                    if let cabinet = activeCabinets.first(where: { $0.id == id }) { show(cabinet) }
                }),
                options: activeCabinets.map { Optional($0.id) },
                separators: true,
                secondaryClick: { id, point in if let id { cabinetMenu = (id, point) } }
            ) { id in
                cabinetTab(activeCabinets.first { $0.id == id })
            }
            .accessibilityLabel("Regal")
            Spacer()
            Button("Vorheriges Regal") { stepCabinet(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .hidden().frame(width: 0)
            Button("Nächstes Regal") { stepCabinet(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .hidden().frame(width: 0)
        }
        // Tabs and rack belong together: half the usual gap.
        .padding(.bottom, -Self.blockSpacing / 2)
        .help("Zwischen den Regalen wechseln: ⌘← / ⌘→")
    }

    /// A tab's name, carrying its right-click menu and the name popover –
    /// each on its own layer, two popovers on one view get in each other's way.
    @ViewBuilder private func cabinetTab(_ cabinet: Cabinet?) -> some View {
        if let cabinet {
            Text(cabinet.name)
                .popover(isPresented: Binding(
                    get: { cabinetMenu?.id == cabinet.id },
                    set: { if !$0, cabinetMenu?.id == cabinet.id { cabinetMenu = nil } }
                ), attachmentAnchor: .point(cabinetMenu?.anchor ?? .center), arrowEdge: .bottom) {
                    AppMenu(dismiss: { cabinetMenu = nil }) {
                        Button("Regal anzeigen") { show(cabinet) }
                        Button("Regal umbenennen …") { renamingCabinet = cabinet.id }
                    }
                    // Not the tab's accent or gray: popovers inherit it.
                    .foregroundStyle(.primary)
                }
                .background {
                    Color.clear.popover(isPresented: Binding(
                        get: { renamingCabinet == cabinet.id },
                        set: { if !$0, renamingCabinet == cabinet.id { renamingCabinet = nil } }
                    ), arrowEdge: .bottom) {
                        CabinetNamePopover(cabinet: cabinet).id(cabinet.id)
                            .foregroundStyle(.primary)
                    }
                }
        }
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

    /// The status controls (sold records still in the rack), right-aligned
    /// above the rack; absent when there are none, so the rack moves up.
    @ViewBuilder private var header: some View {
        let sold = soldCount
        if sold > 0 {
            ShelfStatusControl(soldInShelves: sold, removeSold: { soldToRemove = sold; confirmRemoveSold = true })
                .frame(height: AppStyle.controlHeight)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, Self.blockSpacing)
        }
    }

    /// Only while the committed query has words, so a field of spaces lists nothing.
    @ViewBuilder private var searchResultsPanel: some View {
        let typed = !SearchIndex<UUID>.words(search.text).isEmpty
        if typed && !SearchIndex<UUID>.words(searchQuery).isEmpty {
            ShelfSearchResultsPanel(
                matches: searchResults.placed,
                unplaced: searchResults.unplaced,
                hidden: searchResults.hidden,
                labels: rangeLabels,
                missing: missingIDs,
                place: startPlacement
            )
            // Still the previous query's matches while typing pauses.
            .opacity(searchQuery == search.text ? 1 : 0.6)
            .animation(AppStyle.quickAnimation, value: searchQuery == search.text)
            .frame(width: AppStyle.toolbarSearchWidth + 60)
            .padding(.trailing, AppStyle.pagePadding + 4)
            .padding(.top, 6)
            .transition(.opacity)
        }
    }

    @ViewBuilder private var shelfDetail: some View {
        if let shown = detailShelf {
            // The contents own their grid/list switch.
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
                // One slot: an animated switch between an empty and a filled
                // compartment crossfades instead of stacking both for a moment.
                ZStack(alignment: .topLeading) {
                if shown.isReserved || shown.copies.isEmpty {
                    ShelfLockReader(shelf: shown, preview: lockPreview) { locked in
                        if locked {
                            detailNote(String(localized: "Gesperrtes Fach – nicht für Platten vorgesehen. Per Rechtsklick auf das Fach kannst du es entsperren."))
                        } else {
                            HStack(spacing: AppStyle.itemSpacing) {
                                detailNote(String(localized: "Noch keine Platten in diesem Fach."))
                                Button("Platte hinzufügen") { startAssignment(shown) }
                                    .appLinkButton()
                            }
                        }
                    }
                } else {
                    ShelfContentsView(
                        shelf: shown,
                        session: contentsSession,
                        owner: owner,
                        missing: missingIDs,
                        focusCopy: focusCopy,
                        focusRevision: focusRevision,
                        select: { copy in
                            if let copy { if focusCopy?.id != copy.id { focusCopy = copy } } else { deselect() }
                        },
                        placed: showPlaced,
                        find: startPlacement,
                        unplace: unplace,
                        delete: { pendingDelete = $0 },
                        setMissing: setMissing
                    )
                }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .popover(isPresented: $showsNameEditor, arrowEdge: .top) {
                // Fresh state per shelf: a name seeded for one shelf must
                // never be saved onto another.
                ShelfNamePopover(shelf: shown).id(shown.id)
            }
        } else {
            detailNote(String(localized: "Wähle ein Fach im Regal oder suche oben nach einer Platte."))
        }
    }

    private func detailNote(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var undoToast: some View {
        if let entry = recentUnplace {
            HStack(spacing: AppStyle.rowSpacing) {
                Text("Aus Fach entfernt")
                // A shelf locked meanwhile takes no records, and a record marked
                // "Nicht im Regal" meanwhile stays out; nothing to undo then.
                if canUndo(entry) {
                    Button("Rückgängig", action: undoUnplace)
                        .appLinkButton()
                        .keyboardShortcut(searchFocused ? nil : KeyboardShortcut("z", modifiers: .command))
                }
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .appChipSurface(in: Capsule())
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
        Button("Platte hinzufügen") { selectShelf(shelf); startAssignment(shelf) }
            .disabled(locked)
        Button("Sortierung prüfen") { selectShelf(shelf); sortCheck = ShelfSortCheckRequest(shelf: shelf) }
            .disabled(locked || shelf.copies.count < 2)
        if locked {
            Button("Namen ändern …") { selectShelf(shelf); showsNameEditor = true }
            Button("Fach entsperren") { setLocked(shelf, false) }
        } else {
            Button("Fach sperren") { setLocked(shelf, true) }
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

    /// After a copy's place changed from the compartment contents: follow it
    /// to its new shelf, or drop the focus when it left the shelves altogether.
    private func showPlaced(_ copy: RecordCopy) {
        guard let shelf = copy.shelf else {
            if focusCopy?.id == copy.id { focusCopy = nil }
            return
        }
        if highlight != shelf.id { withAnimation(AppStyle.standardAnimation) { highlight = shelf.id } }
        focusCopy = copy
        focusRevision += 1
    }

    // Lets go of the picked record; the shelf itself stays selected.
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
        if new.found && new.putAwayIn == nil {
            focusCopy = copy
            focusRevision += 1
        }
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
            focusRevision += 1
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
