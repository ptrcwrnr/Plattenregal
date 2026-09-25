import SwiftUI
import SwiftData

/// The shelf page as one calm column: a slim header bar (search + status), the
/// KALLAX drawn as a single piece of furniture, and the selected compartment
/// underneath at full width (spine strip, then a compact table of its records).
struct KallaxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shelf.number) private var allShelves: [Shelf]
    @Query(sort: \Cabinet.sortOrder) private var cabinets: [Cabinet]
    @Query private var allCopies: [RecordCopy]
    @Query private var exclusions: [OptimizationExclusion]
    @Query private var missingMarks: [MissingCopyMark]
    @Query private var accounts: [DiscogsAccount]
    @Binding var highlight: UUID?
    /// Set from elsewhere ("Platz im Regal finden") to show where a record
    /// without a shelf belongs; taken over into `placement` right away.
    @Binding var placing: UUID?
    /// The record being sorted in and the spots it fits alphabetically.
    @State private var placement: Placement?
    @State private var showsShelfOptions = false
    @State private var lockPreview = ShelfLockPreview()
    @State private var editCopy: RecordCopy?
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
    @State private var sync = DiscogsSyncService.shared
    @State private var changes = LibraryChanges.shared
    @State private var focusCopy: RecordCopy?
    /// While the search field has focus, ⌘Z belongs to its text, not to the
    /// "Aus Fach entfernt" toast.
    @FocusState private var searchFocused: Bool

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

    /// Records marked "Nicht auffindbar": those still standing in a shelf in
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
        editCopy = nil; pendingDelete = nil; confirmRemoveSold = false
    }

    private func setMissing(_ copy: RecordCopy, _ missing: Bool) {
        do { try PositionService(context: context).setMissing([copy], missing) }
        catch { self.error = error.reportedMessage() }
    }

    /// Jumps to a record from the "Nicht auffindbar" list: its shelf with the
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
                header
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
                .frame(height: CGFloat(shownCabinet?.rows ?? ShelfGeometry.rows) * 62 + 2)
                .frame(maxWidth: furnitureWidth(geometry.size.width), alignment: .leading)
                shelfDetail
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, AppStyle.pagePadding + 4)
            .padding(.top, AppStyle.pagePadding)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { deselect() })
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
        // Another account synced: other records count as in the collection.
        .onChange(of: owner) { searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        // Metadata and tracklist updates don't show up in `statsSignature`.
        .onChange(of: changes.libraryVersion) { searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        .onChange(of: changes.tracksVersion) { searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        .onAppear { takePlacingRequest() }
        .onChange(of: placing) { takePlacingRequest() }
        // Marks change without touching `statsSignature` (menu, table, sheet).
        .onChange(of: missingIDs) { refreshPlacement() }
        // Settings (other window) rebuilt cabinets, restored a backup or reset
        // the locations: the sheet's list and target shelf may be stale or gone.
        .onChange(of: changes.shelvesVersion) {
            if assignment != nil { AppLog.info("Regal", "„Platte hinzufügen“ geschlossen: Regale wurden in den Einstellungen geändert") }
            assignment = nil; showsShelfOptions = false; sortingShelf = nil
        }
        // "Alles zurücksetzen" deleted every record: nothing here may keep
        // pointing at one – reading a deleted model crashes.
        .onReceive(NotificationCenter.default.publisher(for: .plattenregalDidReset)) { _ in forgetCopies() }
        .sheet(item: $editCopy) { RecordEditor(copy: $0) }
        .sheet(item: $assignment, onDismiss: {
            // The shelf behind the sheet follows the additions only now, so
            // nothing rebuilds the sheet while records are being added.
            if let copy = closingAssignment?.lastAdded { focusCopy = copy }
            closingAssignment = nil
        }) { session in
            ShelfAssignmentView(session: session, owner: owner, rangeLabel: rangeLabels[session.shelf.id])
        }
        .confirmationDialog(
            soldInShelves.count == 1 ? "Platte ohne Collection aus dem Regal nehmen?" : "\(soldInShelves.count) Platten ohne Collection aus dem Regal nehmen?",
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
            Text("Die Platte ist nicht (mehr) in deiner Discogs-Collection. Löschen entfernt sie samt Fach, Position und deinen Notizen; die übrigen Platten im Fach rücken auf. Das lässt sich nicht rückgängig machen.")
        }
        .confirmationDialog(
            "Physische Reihenfolge ändern?",
            isPresented: Binding(get: { sortingShelf != nil }, set: { if !$0 { sortingShelf = nil } })
        ) {
            Button("Fach alphabetisch sortieren") {
                if let shelf = sortingShelf, !shelf.isDeleted, shelf.modelContext != nil {
                    do { try PositionService(context: context).sort(shelf, by: .artistAZ) }
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
            Picker("Regal", selection: Binding(get: { shownCabinet?.id }, set: { id in
                if let cabinet = activeCabinets.first(where: { $0.id == id }) { show(cabinet) }
            })) {
                ForEach(activeCabinets) { cabinet in
                    Text(cabinet.name).tag(Optional(cabinet.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
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
        selectShelf(shelf)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AppStyle.rowSpacing) {
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
            .frame(maxWidth: .infinity)
            let missing = missingCopies
            if !missing.isEmpty {
                MissingCopiesControl(copies: missing, labels: rangeLabels, show: showMissing,
                                     found: { setMissing($0, false) })
            }
            if !soldInShelves.isEmpty {
                ShelfStatusControl(soldInShelves: soldInShelves.count, removeSold: { confirmRemoveSold = true })
                    .frame(height: 30)
            }
        }
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
                                           insertionPosition: spot?.position, missingSlots: missingSlots) { slot in
                            if ordered.indices.contains(slot - 1) { toggleSelection(ordered[slot - 1]) }
                        }
                    }
                }
                if shown.isReserved || shown.copies.isEmpty {
                    ShelfLockReader(shelf: shown, preview: lockPreview) { locked in
                        if locked {
                            detailNote("Gesperrtes Fach – nicht für Platten vorgesehen. Über die Fachoptionen kannst du die Sperre aufheben.")
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
                        edit: { editCopy = $0 },
                        placed: showPlaced,
                        find: startPlacement,
                        unplace: unplace,
                        delete: { pendingDelete = $0 },
                        setMissing: setMissing
                    )
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
                IconButton(systemImage: "slider.horizontal.3", help: "Fachoptionen") { showsShelfOptions.toggle() }
                    .popover(isPresented: $showsShelfOptions, arrowEdge: .bottom) {
                        ShelfOptionsPopover(shelf: shown, preview: lockPreview)
                            // Fresh state per shelf: values seeded for one shelf must
                            // never be saved onto another.
                            .id(shown.id)
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
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(AppStyle.borderColor))
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

    @ViewBuilder private func shelfMenu(for shelf: Shelf) -> some View {
        Button("Inhalt anzeigen") { selectShelf(shelf) }
        Button("Platte hinzufügen …") { startAssignment(shelf) }
            .disabled(shelf.isReserved)
        Divider()
        Button("Fachoptionen …") { selectShelf(shelf); showsShelfOptions = true }
        Button("Alphabetisch sortieren …") { sortingShelf = shelf }
            .disabled(shelf.copies.count < 2)
    }

    /// New records go right after the one picked in the strip/table,
    /// otherwise to the end of the compartment.
    private func startAssignment(_ shelf: Shelf) {
        let session = ShelfAssignmentSession(shelf: shelf, after: focusCopy.flatMap { $0.shelf?.id == shelf.id ? $0 : nil })
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
        if highlight != shelf.id { showsShelfOptions = false }
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
        guard let id = placing else { return }
        placing = nil
        if let copy = allCopies.first(where: { $0.id == id }) { startPlacement(copy) }
    }

    private func startPlacement(_ copy: RecordCopy) {
        searchQuery = ""; focusCopy = nil; showsShelfOptions = false
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
            // Standing where it should: a "Nicht auffindbar" mark is settled.
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
        if editCopy?.id == copy.id { editCopy = nil }
        do { try PositionService(context: context).delete(copy) }
        catch { self.error = error.reportedMessage() }
    }
}

// MARK: - Search

/// Slim search field; matches float over the rack like a popover so the page
/// layout never shifts while typing.
private struct ShelfSearchField: View {
    /// Committed query, updated after a short pause in typing so the page
    /// behind the field isn't rebuilt on every keystroke.
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    let matches: [RecordCopy]
    /// Records without a shelf; picking one shows where it belongs, picking
    /// a placed match shows where it stands.
    let unplaced: [RecordCopy]
    /// Matches beyond the listed ones.
    let hidden: Int
    let labels: ShelfLabels
    /// Copies marked "Nicht auffindbar".
    let missing: Set<UUID>
    let onClear: () -> Void
    let place: (RecordCopy) -> Void
    @State private var text = ""

    /// Only words count: a field of spaces searches nothing.
    private static func hasWords(_ value: String) -> Bool { !SearchIndex<UUID>.words(value).isEmpty }

    private func clear() {
        text = ""
        onClear()
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Platte im Regal suchen …", text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
                .onExitCommand(perform: clear)
            if !text.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
            if Self.hasWords(text) && Self.hasWords(query) {
                results.offset(y: 36)
                    // Still the previous query's matches while typing pauses.
                    .opacity(query == text ? 1 : 0.6)
                    .animation(AppStyle.quickAnimation, value: query == text)
            }
        }
        .task(id: text) {
            // Clearing is immediate; typing waits for a short pause.
            if !text.isEmpty {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
            if query != text { query = text }
        }
        // Cleared from outside (picking a shelf or a result).
        .onChange(of: query) { _, new in if new.isEmpty { text = "" } }
    }

    @ViewBuilder private var results: some View {
        Group {
            if matches.isEmpty && unplaced.isEmpty {
                Text("Keine Treffer im Regal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(matches) { copy in
                        Button { place(copy) } label: {
                            SearchResultRow(copy: copy, labels: labels, missing: missing.contains(copy.id))
                        }
                        .buttonStyle(.plain)
                        .help("Zeigt, zwischen welchen Platten sie steht")
                    }
                    if !unplaced.isEmpty {
                        if !matches.isEmpty { Divider().padding(.vertical, 3) }
                        ForEach(unplaced) { copy in
                            Button { place(copy) } label: {
                                SearchResultRow(copy: copy, labels: labels, missing: missing.contains(copy.id), placeable: true)
                            }
                            .buttonStyle(.plain)
                            .help("Zeigt, wo die Platte alphabetisch hingehört")
                        }
                    }
                    if hidden > 0 {
                        Text("\(hidden) weitere Treffer – Suche genauer eingrenzen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                }
                .padding(5)
            }
        }
        // Same glass as the system popovers in the overview.
        .appGlassSurface(cornerRadius: 12)
    }
}

private struct SearchResultRow: View {
    let copy: RecordCopy
    let labels: ShelfLabels
    var missing = false
    var placeable = false
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            CoverView(url: copy.release?.coverURL, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(copy.release?.displayArtist ?? "—").font(.callout).lineLimit(1)
                HStack(spacing: 6) {
                    Text(copy.release?.displayTitle ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if missing { MissingBadge() }
                }
            }
            Spacer(minLength: 8)
            Text(placeable ? "Ohne Fach · Platz finden" : ShelfRangeLabels.location(of: copy, labels: labels))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .appHoverable(hovering, cornerRadius: 8)
        .onHover { hovering = $0 }
    }
}

/// Full-width strip of the selected compartment: an abstracted row of record
/// spines standing left to right, matching how the physical copies sit in the
/// shelf. Clicking a spine pulls it out; the line underneath carries both the
/// selection and the genre legend so the colors are explained right where
/// they're used.
private struct ShelfPositionStrip: View {
    let stats: ShelfStatistics
    let slots: Int
    let palette: StylePalette
    let selectedCopy: RecordCopy?
    /// 1-based index of `selectedCopy` among the drawn spines.
    let selectedSlot: Int?
    /// Where a record being sorted in would go; drawn as a marker between spines.
    var insertionPosition: Int? = nil
    /// 1-based spines marked "Nicht auffindbar"; drawn as an outline.
    var missingSlots: Set<Int> = []
    let select: (Int) -> Void


    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpineRack(
                styles: stats.spineStyles,
                slots: slots,
                palette: palette,
                selectedPosition: selectedSlot,
                insertionPosition: insertionPosition,
                missingPositions: missingSlots,
                selectable: true,
                onSelect: select
            )
            .frame(height: 46)
            HStack(spacing: AppStyle.rowSpacing) {
                Group {
                    if let insertionPosition {
                        Text("Neue Platte an Position \(insertionPosition) · \(AppStyle.records(stats.count)) im Fach")
                            .foregroundStyle(AppStyle.accent)
                    } else if let copy = selectedCopy {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(palette.color(for: copy.release?.primaryStyle ?? "", solid: true))
                                .frame(width: 7, height: 7)
                            Text("Position \(selectedSlot ?? copy.positionInShelf) von \(stats.count) · \(copy.release?.displayArtist ?? "—") – \(copy.release?.displayTitle ?? "—")")
                                .foregroundStyle(.primary)
                            if let slot = selectedSlot, missingSlots.contains(slot) { MissingBadge() }
                        }
                    } else {
                        Text("\(AppStyle.records(stats.count)) · von links nach rechts"
                             + (missingSlots.isEmpty ? "" : " · \(missingSlots.count) nicht auffindbar"))
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: AppStyle.rowSpacing)
                ShelfStyleLegend(stats: stats, palette: palette)
                    .layoutPriority(-1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Placement

/// What the shelf search found: placed records (listed with their location),
/// records without a shelf (offered for sorting in) and the shelves to keep
/// lit. `litShelfIDs == nil` while not searching, so nothing is dimmed.
struct ShelfSearchResults {
    static let placedLimit = 8
    static let unplacedLimit = 4
    var placed: [RecordCopy] = []
    var unplaced: [RecordCopy] = []
    /// Matches left out by the limits above.
    var hidden = 0
    var litShelfIDs: Set<UUID>? = nil
}

/// A record being sorted in: the spots it fits (one, or two at a shelf
/// boundary) and the one currently shown. For a record that already has a
/// shelf (`found`) the single spot is where it stands, to put it back there.
struct Placement {
    let copy: RecordCopy
    let found: Bool
    let spots: [AlphabeticalPlacement.Spot]
    var chosen = 0
    /// Marked "Nicht im Regal"; sorting it in lifts that.
    var excluded = false
    /// Marked "Nicht auffindbar"; sorting it in counts as found.
    var missing = false
    /// Name of the deactivated cabinet the record stands in: its shelf isn't
    /// on this page, so there is no spot to show.
    let putAwayIn: String?

    init(copy: RecordCopy, shelves: [Shelf]) {
        self.copy = copy
        found = copy.shelf != nil
        if let shelf = copy.shelf, !shelf.isInUse {
            putAwayIn = shelf.cabinet?.name ?? ""
            spots = []
            return
        }
        putAwayIn = nil
        spots = found
            ? AlphabeticalPlacement.current(for: copy, in: shelves).map { [$0] } ?? []
            : AlphabeticalPlacement.spots(for: copy, in: shelves)
    }
    var spot: AlphabeticalPlacement.Spot? { spots.indices.contains(chosen) ? spots[chosen] : nil }
}

/// Sits above the compartment that was picked for the record: what goes
/// where, between which two records, and — at a shelf boundary — the other
/// shelf that fits just as well, with how many records each already holds.
private struct PlacementCard: View {
    let placement: Placement
    let labels: ShelfLabels
    /// Copies marked "Nicht auffindbar": no help as a landmark at the shelf.
    let missing: Set<UUID>
    let choose: (Int) -> Void
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        let release = placement.copy.release
        HStack(alignment: .top, spacing: AppStyle.rowSpacing) {
            CoverView(url: release?.coverURL, size: 52)
            VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                Text("\(placement.found ? "Hier steht" : "Einsortieren"): \(release?.displayArtist ?? "—") – \(release?.displayTitle ?? "—")")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if placement.excluded && !placement.found {
                    Label("Steht auf „Nicht im Regal“ – beim Einsortieren wird das aufgehoben.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if placement.missing && placement.putAwayIn == nil {
                    Label(placement.found
                          ? "Als nicht auffindbar markiert – hier sollte sie stehen."
                          : "Als nicht auffindbar markiert – beim Einsortieren gilt sie als gefunden.",
                          systemImage: "pause.circle")
                        .font(.callout)
                        .foregroundStyle(AppStyle.errorColor)
                }
                if let spot = placement.spot {
                    Text(location(spot))
                        .font(.callout)
                    Text(neighbours(spot))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    ForEach(Array(placement.spots.enumerated()), id: \.element.id) { index, other in
                        if index != placement.chosen {
                            Button { choose(index) } label: {
                                Text("Passt genauso \(other.position == 1 ? "an den Anfang" : "ans Ende") von „\(name(other.shelf))“ (\(AppStyle.records(other.shelf.copies.count))) – dorthin wechseln")
                            }
                            .buttonStyle(.link)
                            .font(.callout)
                            .padding(.top, 2)
                        }
                    }
                } else if let cabinet = placement.putAwayIn {
                    Text("Steht im deaktivierten Regal „\(cabinet)“. Aktiviere es in den Einstellungen unter „Regale“, um sie hier zu sehen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Es steht noch keine Platte im Regal, an der sich die Platte ausrichten könnte. Wähle ein Fach und füge sie dort über „+“ hinzu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: AppStyle.itemSpacing)
            HStack(spacing: AppStyle.itemSpacing) {
                SecondaryButton(title: "Abbrechen", action: cancel)
                if placement.spot != nil {
                    PrimaryButton(title: placement.found ? "Gefunden" : "Hier einsortieren", action: confirm)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .background(AppStyle.selectedBackground, in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: AppStyle.cardRadius).strokeBorder(AppStyle.selectedBorder.opacity(0.35)))
    }

    /// As chosen in the settings; shelves are never named by their internal number.
    private func name(_ shelf: Shelf) -> String { labels.prefix(for: shelf) + (labels[shelf.id] ?? "Leeres Fach") }

    private func location(_ spot: AlphabeticalPlacement.Spot) -> String {
        let count = spot.shelf.copies.count
        let place = spot.position == 1 ? "ganz links" : spot.position > count ? "ganz rechts" : "Position \(spot.position)"
        return "Fach „\(name(spot.shelf))“ · \(place) · \(AppStyle.records(count)) im Fach"
    }

    private func neighbours(_ spot: AlphabeticalPlacement.Spot) -> String {
        func title(_ copy: RecordCopy) -> String {
            let text = "„\(copy.release?.displayArtist ?? "—") – \(copy.release?.displayTitle ?? "—")“"
            let note = missing.contains(copy.id) ? " – nicht auffindbar" : ""
            guard let shelf = copy.shelf, shelf.id != spot.shelf.id else { return text + note }
            return text + " (Fach „\(name(shelf))“\(note))"
        }
        switch (spot.before, spot.after) {
        case let (before?, after?): return "Zwischen \(title(before)) und \(title(after))"
        case let (before?, nil): return "Nach \(title(before))"
        case let (nil, after?): return "Vor \(title(after))"
        case (nil, nil): return ""
        }
    }
}

private struct UnplacedCopy {
    let id = UUID()
    let copy: RecordCopy
    let shelf: Shelf
    let position: Int
}

// MARK: - Style colors

/// The one place genre colors are defined: a fixed style → color mapping used
/// by the spine strip, its legend and the dot in each compartment. Muted tones,
/// each with a slightly lighter dark-mode variant so the dark ones stay visible
/// on a dark background. Every style not listed shares one light neutral.
///
/// Each color group is also a style *family* with a name: the legend counts
/// families, so one color is one line ("Trance" covers Progressive Trance).
struct StylePalette {
    private static let groups: [(name: String, light: UInt32, dark: UInt32, styles: [String])] = [
        ("Techno", 0x4A4A4F, 0x7A7A80, ["Techno", "Minimal", "Minimal Techno"]),                     // dark grey
        ("Trance", 0x8B2E2E, 0xB04A48, ["Trance", "Progressive Trance"]),                            // dark red
        ("Hard Trance", 0xC8483F, 0xD8645A, ["Hard Trance", "Euro Dance", "Hands Up"]),              // red
        ("House & Electro", 0x9A9A9E, 0xA8A8AD, ["Progressive House", "Electro House", "Electro", "Tech House"]), // grey
        ("Neo Trance", 0x5E4232, 0x8A6A55, ["Neo Trance"]),                                          // dark brown
        ("Deep House", 0x2F4A6E, 0x5577A3, ["Deep House"]),                                          // dark blue
        ("Hardstyle", 0xD4A93A, 0xDDB654, ["Hardstyle"]),                                            // yellow
        ("Drum & Bass / Breaks", 0x3A2A4A, 0x6E5788, ["Drum & Bass", "Breaks"]),                     // black-violet
    ]
    /// Name of the neutral family for every style not listed above.
    static let otherFamily = "Sonstige"

    private static let families: [String: (name: String, colorStyle: String)] = {
        var result: [String: (name: String, colorStyle: String)] = [:]
        for group in groups {
            for style in group.styles { result[normalize(style)] = (group.name, group.styles[0]) }
        }
        return result
    }()

    /// The family a style belongs to, and a style that stands for its color.
    /// Unlisted styles form "Sonstige" (colored like any unlisted style).
    static func family(of style: String) -> (name: String, colorStyle: String) {
        families[normalize(style)] ?? (otherFamily, "")
    }
    private static let other = Color.adaptive(hex: 0xD6D6D8, dark: 0x5C5C61)

    private static let mapping: [String: Color] = {
        var result: [String: Color] = [:]
        for group in groups {
            let color = Color.adaptive(hex: group.light, dark: group.dark)
            for style in group.styles { result[normalize(style)] = color }
        }
        return result
    }()

    /// Folds case, spaces, hyphens, "&"/"and"/"n" and similar spellings, so
    /// "Hardtrance", "hard-trance" and "Hard Trance" (or "Drum n Bass" and
    /// "Drum & Bass") land on the same key.
    static func normalize(_ style: String) -> String {
        let folded = style.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
        var key = String(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
        for alias in ["drumnbass", "drumbass", "dnb"] where key == alias { key = "drumandbass" }
        return key
    }

    func color(for style: String, solid: Bool = false) -> Color {
        let base = Self.mapping[Self.normalize(style)] ?? Self.other
        return solid ? base : base.opacity(0.9)
    }
}

// MARK: - Spine rack

/// Records as thin vertical spines standing left to right, one slot per unit of
/// slot, so rows sharing a slot count show sleeves at the same width.
/// Empty slots draw nothing but the shelf floor.
///
/// With `selectable`, the selected position is pulled out like a real sleeve
/// (taller, a bit wider, full opacity, smooth animation) while the rest dims
/// slightly; clicking a spine reports its 1-based position.
struct SpineRack: View {
    let styles: [String]
    let slots: Int
    let palette: StylePalette
    var selectedPosition: Int? = nil
    /// Draws a marker in front of this 1-based position (count + 1 = the end).
    var insertionPosition: Int? = nil
    /// 1-based positions drawn as an outline only: listed there, but not found.
    var missingPositions: Set<Int> = []
    var selectable = false
    var onSelect: ((Int) -> Void)? = nil

    // The spine being animated; kept while it slides back in after deselection.
    @State private var liftedPosition: Int?
    @State private var lift: Double = 0
    /// Only needed to map a tap to its slot; the canvas lays itself out.
    @State private var width: CGFloat = 0

    var body: some View {
        SpineCanvas(
            styles: styles,
            slots: max(slots, styles.count, 1),
            palette: palette,
            liftedPosition: liftedPosition,
            lift: lift,
            insertionPosition: insertionPosition,
            missingPositions: missingPositions,
            reservesHeadroom: selectable
        )
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .onTapGesture { location in
            guard selectable, let onSelect, !styles.isEmpty, width > 0 else { return }
            let slot = width / CGFloat(max(slots, styles.count, 1))
            let index = Int(location.x / slot)
            if styles.indices.contains(index) { onSelect(index + 1) }
        }
        .onAppear {
            if let selectedPosition { liftedPosition = selectedPosition; lift = 1 }
        }
        .onChange(of: selectedPosition) { _, position in
            if let position {
                if liftedPosition != position { liftedPosition = position; lift = 0 }
                withAnimation(AppStyle.layoutAnimation) { lift = 1 }
            } else {
                withAnimation(AppStyle.layoutAnimation) { lift = 0 }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SpineCanvas: View, Animatable {
    let styles: [String]
    let slots: Int
    let palette: StylePalette
    let liftedPosition: Int?
    var lift: Double
    let insertionPosition: Int?
    let missingPositions: Set<Int>
    let reservesHeadroom: Bool

    nonisolated var animatableData: Double {
        get { lift }
        set { lift = newValue }
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                         with: .color(AppStyle.borderColor))
            let slot = size.width / CGFloat(slots)
            let baseWidth = max(0.8, slot * 0.62)
            let usable = size.height - 1
            // Leave room above the row so a pulled-out spine (1.4×) still fits.
            let scale: CGFloat = reservesHeadroom ? 0.66 : 0.8
            let t = CGFloat(lift)
            for (index, style) in styles.enumerated() {
                let jitter = CGFloat((index &* 37 &+ style.count &* 11) % 9) / 100
                let isLifted = liftedPosition == index + 1
                if isLifted && t > 0 { continue }
                let height = min(usable, usable * (scale + jitter * (reservesHeadroom ? 0.5 : 1)))
                var color = palette.color(for: style)
                if liftedPosition != nil { color = color.opacity(1 - 0.45 * Double(t)) }
                let rect = CGRect(x: CGFloat(index) * slot + (slot - baseWidth) / 2, y: usable - height,
                                  width: baseWidth, height: height)
                if missingPositions.contains(index + 1) {
                    // A gap where the record should stand: a red outline, like its tag.
                    let line = min(1.2, baseWidth / 3)
                    context.stroke(Path(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), cornerRadius: min(1, baseWidth / 2)),
                                   with: .color(AppStyle.errorColor.opacity(liftedPosition != nil ? 0.8 - 0.35 * Double(t) : 0.8)),
                                   lineWidth: line)
                } else {
                    context.fill(Path(roundedRect: rect, cornerRadius: min(1, baseWidth / 2)), with: .color(color))
                }
            }
            // Draw the lifted spine last so its wider body sits on top of its neighbours.
            if let position = liftedPosition, styles.indices.contains(position - 1), t > 0 {
                let index = position - 1, style = styles[index]
                let jitter = CGFloat((index &* 37 &+ style.count &* 11) % 9) / 100
                let height = min(usable, usable * (scale + jitter * (reservesHeadroom ? 0.5 : 1)) * (1 + 0.4 * t))
                let width = min(slot * 1.6, baseWidth * (1 + 0.5 * t))
                let rect = CGRect(x: CGFloat(index) * slot + (slot - width) / 2, y: usable - height, width: width, height: height)
                let color = palette.color(for: style, solid: true)
                context.fill(Path(roundedRect: rect, cornerRadius: min(1, width / 2)), with: .color(color))
            }
            // The gap a new record goes into: an accent bar standing between the spines, a bit taller than them.
            if let position = insertionPosition, position >= 1 {
                let width: CGFloat = 3
                let x = min(max(CGFloat(position - 1) * slot - width / 2, 0), size.width - width)
                let rect = CGRect(x: x, y: 0, width: width, height: usable)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(AppStyle.accent))
            }
        }
    }
}

/// Diagonal hatching for reserved compartments.
private struct HatchPattern: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.stroke(path, with: .color(Color.secondary.opacity(0.18)), lineWidth: 1)
        }
    }
}

// MARK: - Status

/// Status next to the search field: records still in a shelf although they
/// left the Discogs collection, plus the way to take them out.
private struct ShelfStatusControl: View {
    let soldInShelves: Int
    let removeSold: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text("\(soldInShelves) nicht in der Collection").monospacedDigit().foregroundStyle(AppStyle.warningColor)
                .help("Nicht (mehr) in deiner Discogs-Collection – verkauft, verschenkt oder aus einem anderen Konto –, aber noch im Regal")
            Text("·").foregroundStyle(.tertiary)
            Button("Aus Regal nehmen", action: removeSold)
                .buttonStyle(.link)
        }
        .font(.callout)
    }
}

/// Small tag on a record marked "Nicht auffindbar" (table, search, "Platte hinzufügen").
private struct MissingBadge: View {
    var body: some View {
        Text("Nicht auffindbar")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppStyle.errorColor)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(AppStyle.errorColor.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

/// Status next to the search field: records marked "Nicht auffindbar" while
/// sorting. The menu lists them by shelf; picking one shows it in its shelf.
private struct MissingCopiesControl: View {
    let copies: [RecordCopy]
    let labels: ShelfLabels
    let show: (RecordCopy) -> Void
    let found: (RecordCopy) -> Void

    var body: some View {
        Menu {
            ForEach(copies) { copy in
                Menu(Self.name(copy) + " – " + (copy.shelf.map { labels[$0.id] ?? $0.numberText } ?? "noch ohne Fach")) {
                    Button(copy.shelf == nil ? "Platz im Regal finden" : "Im Fach zeigen") { show(copy) }
                    Button("Wieder gefunden") { found(copy) }
                }
            }
        } label: {
            // A plain button style keeps the label's own color (a borderless
            // menu draws it in the default text color).
            // Outlined like the result button next to the overview search.
            HStack(spacing: 3) {
                Text("\(copies.count) nicht auffindbar").monospacedDigit().lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(AppStyle.errorColor)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(.callout)
        .help("Beim Einsortieren nicht gefunden – vermutlich noch in einem anderen Fach")
    }

    private static func name(_ copy: RecordCopy) -> String {
        "\(copy.release?.displayArtist ?? "—") – \(copy.release?.displayTitle ?? "—")"
    }
}

// MARK: - Shelf furniture

/// The KALLAX as one piece of furniture: a single outer frame with the
/// compartments separated by thin dividers, so the rack is the one distinct
/// shape on the page.
private struct ShelfFurniture<Menu: View>: View {
    let shelves: [Shelf]
    let rows: Int
    let columns: Int
    let stats: (Shelf) -> ShelfStatistics
    let rangeLabel: (Shelf) -> String?
    let palette: StylePalette
    let selectedID: UUID?
    /// Shelves kept at full strength; `nil` = no search/focus, nothing dimmed.
    let litIDs: Set<UUID>?
    let lockPreview: ShelfLockPreview
    let select: (Shelf) -> Void
    @ViewBuilder let menu: (Shelf) -> Menu

    private static var frameColor: Color { Color.primary.opacity(0.28) }
    private static var dividerColor: Color { Color.primary.opacity(0.14) }

    /// Always the cabinet's full grid of equal cells, addressed by the place
    /// in the cabinet, so a missing shelf can never shift or stretch its neighbours.
    private var grid: [[(Int, Shelf?)]] {
        (0..<rows).map { row in
            (1...columns).map { column in
                let slot = row * columns + column
                return (slot, shelves.first { $0.sortOrder == slot })
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(grid.enumerated()), id: \.offset) { index, row in
                if index > 0 { Self.dividerColor.frame(height: 1) }
                HStack(spacing: 0) {
                    ForEach(row, id: \.0) { number, shelf in
                        if (number - 1) % columns > 0 { Self.dividerColor.frame(width: 1) }
                        if let shelf {
                            Button { select(shelf) } label: {
                                ShelfCompartment(
                                    shelf: shelf,
                                    stats: stats(shelf),
                                    rangeLabel: rangeLabel(shelf),
                                    palette: palette,
                                    lockPreview: lockPreview,
                                    selected: selectedID == shelf.id,
                                    dimmed: litIDs.map { !$0.contains(shelf.id) } ?? false
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contextMenu { menu(shelf) }
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Self.frameColor, lineWidth: 2))
    }
}

private struct ShelfCompartment: View {
    let shelf: Shelf
    let stats: ShelfStatistics
    let rangeLabel: String?
    let palette: StylePalette
    let lockPreview: ShelfLockPreview
    var selected = false
    var dimmed = false
    @State private var hovering = false

    /// Follows the options popover's switch immediately (see `ShelfLockPreview`).
    private var isReserved: Bool { lockPreview.isLocked(shelf) }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Always in the tree and faded via opacity: the most reliable way to
            // animate it, independent of how the change arrives.
            .background { HatchPattern().opacity(isReserved ? 1 : 0) }
            .background(selected ? AppStyle.accent.opacity(0.12) : hovering ? AppStyle.hoverBackground : Color.clear)
            .contentShape(Rectangle())
            .opacity(dimmed ? 0.3 : 1)
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: selected)
            .animation(AppStyle.standardAnimation, value: dimmed)
            // Hatching and label crossfade when the shelf is (un)locked.
            .animation(AppStyle.standardAnimation, value: isReserved)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        if isReserved {
            HStack(spacing: 5) {
                Image(systemName: "lock")
                Text(shelf.name.isEmpty ? "Gesperrt" : shelf.name).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else if stats.count > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Text(rangeLabel ?? "—")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    Circle()
                        .fill(palette.color(for: stats.dominantColorStyle ?? "", solid: true))
                        .frame(width: 6, height: 6)
                    Text(AppStyle.records(stats.count)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else {
            // Without a view here the compartment collapses to nothing and
            // can't be clicked, so empty shelves get a quiet placeholder.
            Text("Leer")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var accessibilityText: String {
        if isReserved { return "\(shelf.name.isEmpty ? "Fach" : shelf.name), gesperrt" }
        if stats.count == 0 { return "Leeres Fach" }
        return "\(rangeLabel ?? "Fach"), \(AppStyle.records(stats.count))"
    }
}

// MARK: - Style legend

/// Genre legend for the spine strip. Shows as many of the top styles as fit
/// on one line instead of wrapping onto a row of its own.
private struct ShelfStyleLegend: View {
    let stats: ShelfStatistics
    let palette: StylePalette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: min(4, stats.styleShares.count), through: 1, by: -1)), id: \.self) { count in
                entries(count)
            }
            Color.clear.frame(width: 0, height: 0)
        }
        .font(.caption.monospacedDigit())
    }

    private func entries(_ count: Int) -> some View {
        HStack(spacing: AppStyle.rowSpacing) {
            ForEach(stats.styleShares.prefix(count)) { share in
                HStack(spacing: 5) {
                    Circle().fill(palette.color(for: share.colorStyle)).frame(width: 7, height: 7)
                    Text(share.style).foregroundStyle(.secondary)
                    Text("\(Int((share.fraction * 100).rounded())) %").foregroundStyle(.tertiary)
                }
                .fixedSize()
                .help(share.members.joined(separator: ", "))
            }
        }
    }
}

private extension Color {
    static func adaptive(hex light: UInt32, dark: UInt32) -> Color {
        func rgb(_ v: UInt32) -> (Double, Double, Double) {
            (Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
        }
        return adaptive(light: rgb(light), dark: rgb(dark))
    }

    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

// MARK: - Copy table in the shelf detail area

nonisolated private struct ShelfCopyItem: Identifiable {
    let copy: RecordCopy
    let id: UUID
    let position: Int
    let artist: String
    let title: String
    /// 0 when unknown, so it sorts to one end instead of breaking the comparator.
    let year: Int
    let genre: String
    /// Not in the current Discogs collection (sold, other account).
    let sold: Bool
    /// Marked "Nicht auffindbar".
    let missing: Bool

    init(_ copy: RecordCopy, owner: String?, missing: Bool) {
        self.copy = copy
        id = copy.id
        position = copy.positionInShelf
        artist = copy.release?.displayArtist ?? "—"
        title = copy.release?.displayTitle ?? "—"
        year = copy.release?.year ?? 0
        genre = copy.release?.primaryStyle ?? ""
        sold = copy.leftCurrentCollection(owner: owner)
        self.missing = missing
    }
}

/// Compact, sortable table of the shelf's records (default: position in the
/// shelf). Owns a cached snapshot that is rebuilt only when the shelf's
/// contents actually change (see `signature`), not on every unrelated
/// re-render of the surrounding page (e.g. a search hover).
private struct ShelfCopyTable: View {
    @Environment(\.modelContext) private var context
    let shelf: Shelf
    let shelves: [Shelf]
    let rangeLabels: ShelfLabels
    let owner: String?
    /// Copies marked "Nicht auffindbar"; part of `signature`, so a mark
    /// rebuilds the rows like any other change.
    let missing: Set<UUID>
    let focusCopy: RecordCopy?
    let select: (RecordCopy?) -> Void
    let edit: (RecordCopy) -> Void
    let placed: (RecordCopy) -> Void
    /// Shows the card with the records this one stands between.
    let find: (RecordCopy) -> Void
    let unplace: (RecordCopy) -> Void
    let delete: (RecordCopy) -> Void
    let setMissing: (RecordCopy, Bool) -> Void

    @State private var items: [ShelfCopyItem] = []
    @State private var sortOrder = [KeyPathComparator(\ShelfCopyItem.position)]
    /// The row last clicked in the table itself. Such a selection must not
    /// scroll: the row is already under the pointer, and centering it would
    /// slide the list away so the pointer ends up over a neighbouring record.
    @State private var clickedID: UUID?
    /// Row whose quick editor popover is open (double-click).
    @State private var quickEditID: UUID?
    /// Data changed while the quick editor was open; rows are rebuilt once it
    /// closes, so a background sync can't pull the popover's row away.
    @State private var reloadPending = false
    /// Shelf the rows were last built for: only a new shelf scrolls to the
    /// selected record, not every data refresh.
    @State private var loadedShelfID: UUID?

    private func quickEditBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { quickEditID == id }, set: { if !$0, quickEditID == id { quickEditID = nil } })
    }

    private var signature: Int {
        var hasher = Hasher()
        hasher.combine(shelf.id)
        // Artist, title, year and genre are copied into the rows; a sync or a
        // Discogs reload changes them on the same copies, so follow those too.
        hasher.combine(LibraryChanges.shared.libraryVersion)
        hasher.combine(owner)
        for copy in shelf.copies { hasher.combine(copy.id); hasher.combine(copy.positionInShelf); hasher.combine(copy.discogsActive); hasher.combine(missing.contains(copy.id)) }
        return hasher.finalize()
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { focusCopy?.id },
            set: { id in
                clickedID = id
                select(id.flatMap { id in items.first { $0.id == id }?.copy })
            }
        )
    }

    private func reload(_ proxy: ScrollViewProxy) {
        reloadPending = false
        items = PositionService(context: context).ordered(shelf).map { ShelfCopyItem($0, owner: owner, missing: missing.contains($0.id)) }.sorted(using: sortOrder)
        guard loadedShelfID != shelf.id else { return }
        loadedShelfID = shelf.id
        if let id = focusCopy?.id { proxy.scrollTo(id, anchor: .center) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            Table(items, selection: selection, sortOrder: $sortOrder) {
                TableColumn("Pos.", value: \.position) { item in
                    Text(String(item.position)).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 34, ideal: 40, max: 52)
                TableColumn("") { item in
                    CoverView(url: item.copy.release?.coverURL, size: 20)
                }
                .width(24)
                TableColumn("Interpret", value: \.artist) { item in
                    Text(item.artist).lineLimit(1).help(item.artist)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .popover(isPresented: quickEditBinding(item.id), arrowEdge: .bottom) {
                            ShelfCopyQuickEditor(copy: item.copy, shelves: shelves, rangeLabels: rangeLabels) {
                                quickEditID = nil
                                placed(item.copy)
                            }
                        }
                }
                .width(min: 120, ideal: 220)
                TableColumn("Titel", value: \.title) { item in
                    HStack(spacing: 6) {
                        Text(item.title).lineLimit(1).help(item.title)
                        if item.missing {
                            MissingBadge()
                                .help("Beim Einsortieren nicht gefunden – Rechtsklick → „Wieder gefunden“, sobald sie auftaucht")
                        }
                        if item.sold {
                            Text("Nicht in der Collection")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(AppStyle.warningColor)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(AppStyle.warningColor.opacity(0.12), in: Capsule())
                                .help("Nicht (mehr) in deiner Discogs-Collection – über den Papierkorb aus dem Fach nehmen")
                        }
                    }
                }
                .width(min: 120, ideal: 280)
                TableColumn("Jahr", value: \.year) { item in
                    Text(item.year > 0 ? String(item.year) : "–").monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 40, ideal: 48, max: 60)
                TableColumn("Genre", value: \.genre) { item in
                    Text(item.genre.isEmpty ? "–" : item.genre).lineLimit(1).foregroundStyle(.secondary).help(item.genre)
                }
                .width(min: 80, ideal: 130)
                TableColumn("") { item in
                    HStack(spacing: 2) {
                        RowIconButton(systemImage: "scope", help: "Zeigen, zwischen welchen Platten sie steht") { find(item.copy) }
                        RowIconButton(systemImage: "trash", help: "Aus Fach entfernen", hoverColor: AppStyle.errorColor) { unplace(item.copy) }
                    }
                }
                .width(46)
            }
            .tableStyle(.inset)
            .background(QuietIconColumnHeaders())
            // Like a spine in the strip: clicking the picked record again puts it back.
            .background(TableRowClickToggle { select(nil) })
            .alternatingRowBackgrounds(.disabled)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let copy = items.first(where: { $0.id == id })?.copy {
                    Button("Exemplar bearbeiten") { edit(copy) }
                    Button("Platz im Regal zeigen") { find(copy) }
                    if missing.contains(copy.id) {
                        Button("Wieder gefunden") { setMissing(copy, false) }
                    } else {
                        Button("Als nicht auffindbar markieren") { setMissing(copy, true) }
                    }
                    Button("Aus Fach entfernen") { unplace(copy) }
                    // Only for records no longer in the Discogs collection: an
                    // active one would come back with the next sync as a new copy.
                    if !copy.isInCurrentCollection(owner: owner) {
                        Divider()
                        Button("Aus Sammlung löschen …", role: .destructive) { delete(copy) }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, items.contains(where: { $0.id == id }) { quickEditID = id }
            }
            .task(id: signature) {
                guard quickEditID == nil else { reloadPending = true; return }
                reload(proxy)
            }
            .onChange(of: quickEditID) { _, id in
                if id == nil && reloadPending { reload(proxy) }
            }
            .onChange(of: sortOrder) { _, order in items.sort(using: order) }
            .onChange(of: focusCopy?.id) { _, id in
                let fromTable = id == clickedID
                clickedID = nil
                guard let id, !fromTable else { return }
                withAnimation(AppStyle.layoutAnimation) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

/// Double-click on a row in the compartment table: the release at a glance,
/// whether the copy belongs in the shelf at all, and which compartment and
/// position it stands at. Everything else stays in the full `RecordEditor`.
private struct ShelfCopyQuickEditor: View {
    let copy: RecordCopy
    let shelves: [Shelf]
    let rangeLabels: ShelfLabels
    /// Called after a successful save.
    let done: () -> Void
    @Environment(\.modelContext) private var context
    @State private var notInShelf = false
    @State private var shelfID: UUID?
    @State private var position = 1
    @State private var error: String?

    private var availableShelves: [Shelf] { shelves.filter { !$0.isReserved } }
    private var targetShelf: Shelf? { availableShelves.first { $0.id == shelfID } }

    /// Last valid position: the end of the shelf, one further when the copy
    /// comes in from another compartment.
    private var maxPosition: Int {
        guard let target = targetShelf else { return 1 }
        let others = target.copies.filter { $0.id != copy.id }.count
        return others + 1
    }

    private func shelfLabel(_ shelf: Shelf) -> String {
        rangeLabels.prefix(for: shelf) + (rangeLabels[shelf.id] ?? "Leeres Fach (Reihe \(shelf.row), Spalte \(shelf.column))")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Veröffentlichung") {
                    LabeledContent("Interpret:") {
                        Text(copy.release?.displayArtist ?? "—").textSelection(.enabled)
                    }
                    LabeledContent("Titel:") {
                        Text(copy.release?.displayTitle ?? "—").textSelection(.enabled)
                    }
                }
                Section("Zugehörigkeit") {
                    Toggle("Nicht im Regal:", isOn: $notInShelf.animation(AppStyle.quickAnimation))
                    if notInShelf {
                        Text("Die Platte verlässt ihr Fach und zählt nicht zu den Platten, die noch einsortiert werden müssen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Lage") {
                    Picker("Fach:", selection: $shelfID) {
                        ForEach(availableShelves) { shelf in
                            Text(shelfLabel(shelf)).tag(Optional(shelf.id))
                        }
                    }
                    LabeledContent("Position:") {
                        HStack(spacing: AppStyle.tightSpacing) {
                            PositionNudgeButton(systemImage: "chevron.left", help: "Eine Position nach links") {
                                position = max(position - 1, 1)
                            }
                            .disabled(position <= 1)
                            TextField("Position", value: $position, format: .number)
                                .labelsHidden()
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.center)
                                .monospacedDigit()
                                .frame(width: 34)
                            PositionNudgeButton(systemImage: "chevron.right", help: "Eine Position nach rechts") {
                                position = min(position + 1, maxPosition)
                            }
                            .disabled(position >= maxPosition)
                            Text("von \(maxPosition)").monospacedDigit().foregroundStyle(.secondary)
                                .padding(.leading, AppStyle.tightSpacing)
                        }
                    }
                }
                .disabled(notInShelf)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            if let error {
                Text(error).font(.caption).foregroundStyle(AppStyle.errorColor)
                    .padding(.horizontal, AppStyle.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                PrimaryButton(title: "Speichern", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, AppStyle.cardPadding)
            .padding(.bottom, AppStyle.cardPadding)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            shelfID = copy.shelf?.id
            position = max(copy.positionInShelf, 1)
        }
        // Typed values outside 1…end snap back right away, not only on save.
        .onChange(of: position) { _, value in
            let clamped = min(max(value, 1), maxPosition)
            if clamped != value { position = clamped }
        }
        .onChange(of: shelfID) { _, id in
            guard let target = targetShelf else { return }
            // Back in its own shelf: its current spot; elsewhere: where it belongs alphabetically.
            position = id == copy.shelf?.id
                ? max(copy.positionInShelf, 1)
                : AlphabeticalPlacement.position(for: copy, in: target)
        }
    }

    private func save() {
        let service = PositionService(context: context)
        do {
            if notInShelf {
                try service.setExcluded([copy], true)
            } else if let target = targetShelf {
                let clamped = min(max(position, 1), maxPosition)
                if target.id != copy.shelf?.id || clamped != copy.positionInShelf {
                    try service.move(copy, to: target, position: clamped)
                }
            }
            done()
        } catch { self.error = error.reportedMessage() }
    }
}

/// Small chevron that moves a copy one slot left or right in the quick editor.
/// Quiet at rest, a soft fill while hovered — no stepper chrome.
private struct PositionNudgeButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(hovering && isEnabled ? AppStyle.hoverBackground : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Takes a copy out of its shelf (undoable via the toast). Quiet secondary
/// color at rest, red only while hovered.
private struct RowIconButton: View {
    let systemImage: String
    let help: String
    var hoverColor: Color = AppStyle.accent
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(hovering ? hoverColor : .secondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Icon columns (untitled: cover, row actions) don't need dividers in the
/// table header. SwiftUI offers no switch for that, so this swaps in a header
/// view that leaves out the divider on either side of such a column.
private struct QuietIconColumnHeaders: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Anchor() }
    func updateNSView(_ view: NSView, context: Context) { (view as? Anchor)?.install() }

    final class Anchor: NSView {
        override func viewDidMoveToWindow() { install() }

        func install() {
            DispatchQueue.main.async { [weak self] in
                guard let table = self?.nearbyTable(), let header = table.headerView, !(header is Header) else { return }
                table.headerView = Header(frame: header.frame)
            }
        }
    }

    final class Header: NSTableHeaderView {
        override func draw(_ dirtyRect: NSRect) {
            guard let table = tableView else { return super.draw(dirtyRect) }
            let columns = table.tableColumns
            // Each header cell draws its divider on its right edge: skip it on
            // an icon column and on the column just before one.
            let clip = NSBezierPath(rect: bounds)
            clip.windingRule = .evenOdd
            for index in columns.indices {
                let isIcon = columns[index].title.isEmpty
                let beforeIcon = index + 1 < columns.count && columns[index + 1].title.isEmpty
                guard isIcon || beforeIcon else { continue }
                let edge = headerRect(ofColumn: index).maxX
                // Keep the line along the header's bottom edge intact.
                let height = bounds.height - 2
                clip.appendRect(NSRect(x: edge - 2, y: isFlipped ? bounds.minY : bounds.maxY - height, width: 3, height: height))
            }
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            super.draw(dirtyRect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

private extension NSView {
    /// A table sits next to its background views, not above them: search
    /// upwards for the nearest ancestor that contains one.
    func nearbyTable() -> NSTableView? {
        func table(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for subview in view.subviews { if let found = table(in: subview) { return found } }
            return nil
        }
        var node = superview
        while let current = node {
            if let found = table(in: current) { return found }
            node = current.superview
        }
        return nil
    }
}

/// A plain click on the already selected row clears the selection, as a
/// click on the pulled-out spine does. `NSTableView` keeps the row selected
/// (only ⌘-click deselects), so this watches mouse-downs on the table itself.
/// The deselection waits out the double-click interval: a double-click opens
/// the quick editor and must leave the row selected. Clicks in icon columns
/// (untitled: cover, row buttons) are left alone.
private struct TableRowClickToggle: NSViewRepresentable {
    let deselect: () -> Void

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.deselect = deselect }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stop() }

    final class Anchor: NSView {
        var deselect: (() -> Void)?
        private var monitor: Any?
        private var pending: DispatchWorkItem?

        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stop() {
            pending?.cancel(); pending = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            pending?.cancel(); pending = nil
            guard let table = nearbyTable(), event.window === table.window, event.clickCount == 1,
                  event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return }
            let point = table.convert(event.locationInWindow, from: nil)
            // Not when something covers the table there (a popover, the search results).
            guard table.visibleRect.contains(point),
                  table.window?.contentView?.hitTest(event.locationInWindow)?.isDescendant(of: table) == true else { return }
            let row = table.row(at: point), column = table.column(at: point)
            guard row >= 0, row == table.selectedRow, table.numberOfSelectedRows == 1,
                  table.tableColumns.indices.contains(column), !table.tableColumns[column].title.isEmpty else { return }
            let item = DispatchWorkItem { [weak self, weak table] in
                guard let table, table.selectedRow == row else { return }
                self?.deselect?()
            }
            pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: item)
        }
    }
}

/// What the shelf page shows as locked while the options popover is open.
///
/// Saving a shelf makes the whole shelf page recompute (statistics, range
/// labels over every copy); doing that mid-animation stutters. So the switch
/// only flips this small observable, which just the compartments read, and the
/// store is written once the animation is over. Afterwards the entry is
/// dropped and the compartment reads the (now equal) model value again.
@MainActor @Observable
final class ShelfLockPreview {
    private var overrides: [UUID: Bool] = [:]

    func isLocked(_ shelf: Shelf) -> Bool { overrides[shelf.id] ?? shelf.isReserved }
    func set(_ locked: Bool, for shelf: Shelf) { overrides[shelf.id] = locked }
    func clear(_ shelf: Shelf) { overrides[shelf.id] = nil }
}

/// Builds its content from a shelf's locked state as `ShelfLockPreview` sees
/// it. Only this small view observes the preview, so flipping the switch
/// re-renders just these bits, not the whole shelf page.
private struct ShelfLockReader<Content: View>: View {
    let shelf: Shelf
    let preview: ShelfLockPreview
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        let locked = preview.isLocked(shelf)
        content(locked)
            .animation(AppStyle.standardAnimation, value: locked)
    }
}

/// Options of the selected compartment: locking it for records, with an
/// optional name that only appears while locked.
///
/// Fixed size on purpose: the name row and the hint share one slot and
/// crossfade, because a resizing NSPopover fights SwiftUI's animation.
private struct ShelfOptionsPopover: View {
    let shelf: Shelf
    let preview: ShelfLockPreview
    @Environment(\.modelContext) private var context
    // Seeded up front, not in onAppear, so the popover opens in its final state.
    @State private var isLocked: Bool
    @State private var name: String
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    /// Slightly longer than the animation, so the save lands after it.
    private static let saveDelay: Duration = .milliseconds(350)

    init(shelf: Shelf, preview: ShelfLockPreview) {
        self.shelf = shelf
        self.preview = preview
        _isLocked = State(initialValue: shelf.isReserved)
        _name = State(initialValue: shelf.name)
    }

    private var canLock: Bool { shelf.isReserved || shelf.copies.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: lockBinding) {
                Text("Fach sperren")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(!canLock)
            ZStack(alignment: .leading) {
                nameRow
                    .opacity(isLocked ? 1 : 0)
                    .offset(y: isLocked || AppStyle.reduceMotion ? 0 : -6)
                    .allowsHitTesting(isLocked)
                hint
                    .opacity(isLocked ? 0 : 1)
                    .offset(y: !isLocked || AppStyle.reduceMotion ? 0 : 6)
                    .allowsHitTesting(false)
            }
            .frame(height: AppStyle.controlHeight)
        }
        .padding(AppStyle.cardPadding)
        .frame(width: 280)
        // Persist once the switch has settled; a quick double flip cancels
        // the pending save and only the final state is written.
        .task(id: isLocked) {
            guard isLocked != shelf.isReserved else { return preview.clear(shelf) }
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            save()
        }
        .onDisappear(perform: save)
    }

    /// The switch animates the popover and the compartment behind it in one
    /// transaction; nothing is saved here.
    private var lockBinding: Binding<Bool> {
        Binding(
            get: { isLocked },
            set: { locked in
                withAnimation(AppStyle.standardAnimation) {
                    isLocked = locked
                    preview.set(locked, for: shelf)
                    error = nil
                }
                if locked { nameFocused = true }
            }
        )
    }

    private var nameRow: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            Text("Name:").foregroundStyle(.secondary)
            TextField("Name", text: $name, prompt: Text(""))
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .onSubmit(save)
                .padding(.horizontal, 8)
                .frame(height: AppStyle.controlHeight)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var hint: some View {
        Text(hintText)
            .font(.caption)
            .foregroundStyle(error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(AppStyle.errorColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hintText: String {
        if let error { return error }
        if !canLock { return "Nur leere Fächer können gesperrt werden." }
        return "In ein gesperrtes Fach können keine Platten gelegt werden."
    }

    /// Writes the popover's state to the store without animation: the page
    /// already shows it via `preview`, so nothing should move again.
    private func save() {
        // Removed meanwhile (cabinet resized or backup restored in the settings).
        guard !shelf.isDeleted, shelf.modelContext != nil else { return }
        let newName = isLocked ? name.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard shelf.isReserved != isLocked || shelf.name != newName else {
            preview.clear(shelf)
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            do {
                try PositionService(context: context).configure(shelf, name: newName, isReserved: isLocked)
                preview.clear(shelf)
            } catch {
                // Back to what is stored; the hint slot shows why.
                withAnimation(AppStyle.standardAnimation) {
                    isLocked = shelf.isReserved
                    preview.clear(shelf)
                    self.error = error.reportedMessage()
                }
            }
        }
    }
}

/// One opening of the "Platte hinzufügen" sheet.
///
/// The list must never move under the pointer while records are added one
/// after another. SwiftUI may rebuild the sheet's content at any time (e.g.
/// when the first save refreshes the shelf page behind it), so nothing that
/// matters lives in the view: the snapshot of candidates, the additions and
/// the AppKit table with its scroll offset all live here, and a rebuilt view
/// just shows the same table again.
@MainActor @Observable
final class ShelfAssignmentSession: Identifiable {
    let id = UUID()
    let shelf: Shelf
    /// Copy selected in the compartment when the sheet opened; `nil` = append.
    private let after: RecordCopy?
    var query = ""
    /// Records without a shelf, sorted by artist; loaded once, then only
    /// shrinks as records are added here.
    private(set) var candidates: [RecordCopy] = []
    private var searchIndex = SearchIndex<UUID>()
    /// Account the candidates were chosen for (see `load`).
    private var owner: String?
    private(set) var loaded = false
    private(set) var addedCount = 0
    private(set) var lastAdded: RecordCopy?
    /// Candidates marked "Nicht auffindbar": they stay in the list, paused.
    private(set) var missing: Set<UUID> = []
    var error: String?
    @ObservationIgnored let table = ShelfAssignmentTableController()

    init(shelf: Shelf, after: RecordCopy?) {
        self.shelf = shelf
        self.after = after
    }

    /// Where the next record goes: after the last one added here, otherwise
    /// after the record selected when the sheet opened, otherwise at the end.
    var anchor: RecordCopy? {
        (lastAdded ?? after).flatMap { $0.shelf?.id == shelf.id ? $0 : nil }
    }

    var visible: [RecordCopy] {
        guard !query.isEmpty else { return candidates }
        let words = SearchIndex<UUID>.words(query)
        return candidates.filter { searchIndex.matches($0.id, words) }
    }

    func load(_ context: ModelContext, owner: String?) {
        guard !loaded else { return }
        loaded = true
        self.owner = owner
        do {
            let copies = try context.fetch(FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.shelf == nil }))
            let excluded = Set(try context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID))
            let available = ShelfAssignmentPresentation.candidates(copies, owner: owner, excluding: excluded)
            candidates = ShelfAssignmentPresentation.sortedByArtist(available)
            searchIndex = SearchIndex(available, id: \.id, text: SortingService.searchText)
            missing = Set(try context.fetch(FetchDescriptor<MissingCopyMark>()).map(\.copyID))
        } catch { self.error = error.reportedMessage() }
    }

    /// The list is a snapshot: a record or the shelf may be gone meanwhile
    /// (reset or restore in the settings window). Reading those would crash.
    private func isGone(_ copy: RecordCopy) -> Bool {
        copy.isDeleted || copy.modelContext == nil || shelf.isDeleted || shelf.modelContext == nil
    }

    func add(_ copy: RecordCopy, in context: ModelContext) {
        guard !isGone(copy) else { candidates.removeAll { $0.id == copy.id }; return }
        guard copy.shelf == nil else { candidates.removeAll { $0.id == copy.id }; return }
        // The list is a snapshot; a sync meanwhile may have taken the record
        // out of the collection.
        guard copy.isInCurrentCollection(owner: owner) else {
            candidates.removeAll { $0.id == copy.id }
            error = "„\(copy.release?.displayArtist ?? "—") – \(copy.release?.displayTitle ?? "—")“ ist nicht mehr in der Collection."
            return
        }
        do {
            let service = PositionService(context: context)
            let position = anchor.map { $0.positionInShelf + 1 }
                ?? service.ordered(shelf, excluding: copy.id).count + 1
            // Standing in a shelf now, so it turned up after all.
            try service.move(copy, to: shelf, position: position, found: true)
            missing.remove(copy.id)
            candidates.removeAll { $0.id == copy.id }
            lastAdded = copy
            addedCount += 1
            error = nil
        } catch { self.error = error.reportedMessage() }
    }

    /// Pause button: not found while sorting in, or found again.
    func toggleMissing(_ copy: RecordCopy, in context: ModelContext) {
        guard !isGone(copy) else { candidates.removeAll { $0.id == copy.id }; return }
        let marked = !missing.contains(copy.id)
        do {
            try PositionService(context: context).setMissing([copy], marked)
            if marked { missing.insert(copy.id) } else { missing.remove(copy.id) }
            error = nil
        } catch { self.error = error.reportedMessage() }
    }
}

/// "+" in the compartment header: pick records that don't have a shelf yet.
/// Same vocabulary as the rest of the app — sheet header, shared search field,
/// compact rows with a quiet per-row action. All state is in the session.
private struct ShelfAssignmentView: View {
    @Bindable var session: ShelfAssignmentSession
    let owner: String?
    let rangeLabel: String?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = session.visible
        VStack(spacing: 0) {
            header(count: items.count)
            AppSearchField(placeholder: "Platten ohne Fach durchsuchen", text: $session.query)
                .padding(.horizontal, AppStyle.pagePadding)
                .padding(.bottom, AppStyle.cardPadding)
            if let error = session.error {
                AppBanner(message: error, kind: .error)
                    .padding(.horizontal, AppStyle.pagePadding)
                    .padding(.bottom, AppStyle.itemSpacing)
                    .transition(AppStyle.funnelTransition())
            }
            Divider()
            ZStack {
                ShelfAssignmentTable(controller: session.table, items: items, missing: session.missing,
                                     toggleMissing: { [session, context] copy in session.toggleMissing(copy, in: context) }) { [session, context] copy in
                    session.add(copy, in: context)
                }
                if session.loaded && items.isEmpty {
                    AppEmptyState(
                        session.query.isEmpty ? "Alles einsortiert" : "Keine Treffer",
                        systemImage: session.query.isEmpty ? "checkmark.circle" : "magnifyingglass",
                        description: Text(session.query.isEmpty ? "Jede Platte der Sammlung liegt bereits in einem Fach." : "Versuche einen anderen Suchbegriff.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 440, height: 620)
        .animation(AppStyle.standardAnimation, value: session.error)
        .onAppear { session.load(context, owner: owner) }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .center, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                Text("Platte hinzufügen").font(AppStyle.dialogTitle)
                // One line, so a longer text never grows the header.
                HStack(spacing: 0) {
                    Text(subtitle(count: count)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    // Its own text, so a long anchor name never cuts it off.
                    if pausedCount > 0 {
                        Text(" · \(pausedCount) nicht auffindbar").foregroundStyle(AppStyle.errorColor)
                            .lineLimit(1).fixedSize()
                    }
                }
                .font(.callout)
            }
            Spacer(minLength: AppStyle.itemSpacing)
            Button { dismiss() } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 32, height: 32)
                    .background(AppStyle.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Fertig")
            .accessibilityLabel("Fertig")
        }
        .padding(.horizontal, AppStyle.pagePadding)
        .padding(.top, AppStyle.pagePadding)
        .padding(.bottom, AppStyle.cardPadding)
    }

    private var pausedCount: Int { session.candidates.filter { session.missing.contains($0.id) }.count }

    private func subtitle(count: Int) -> String {
        let target = rangeLabel.map { "In „\($0)“" } ?? "In dieses Fach"
        let place = session.anchor.map { "nach „\($0.release?.displayArtist ?? "—")“" } ?? "ans Ende"
        var text = "\(target) \(place) · \(AppStyle.records(count)) ohne Fach"
        if session.addedCount > 0 { text += " · \(session.addedCount) hinzugefügt" }
        return text
    }
}

/// Shows the session's table. SwiftUI may create and drop this wrapper as
/// often as it likes; it always hands back the same scroll view, so the
/// offset and the rows shown survive any rebuild of the sheet.
private struct ShelfAssignmentTable: NSViewRepresentable {
    let controller: ShelfAssignmentTableController
    let items: [RecordCopy]
    let missing: Set<UUID>
    let toggleMissing: (RecordCopy) -> Void
    let add: (RecordCopy) -> Void

    // A fresh container each time, holding the one shared scroll view: when
    // SwiftUI tears down an old wrapper it only takes its own container along.
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        update(container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) { update(container) }

    private func update(_ container: NSView) {
        let scroll = controller.scrollView
        if scroll.superview !== container {
            scroll.frame = container.bounds
            scroll.autoresizingMask = [.width, .height]
            container.addSubview(scroll)
        }
        controller.add = add
        controller.toggleMissing = toggleMissing
        controller.setMissing(missing)
        controller.apply(items)
    }
}

/// The candidate list as a plain NSTableView. Removing a row there keeps the
/// clip view's origin as is: the row fades, the rows below slide up, and the
/// next "+" ends up exactly under the pointer.
@MainActor
final class ShelfAssignmentTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let rowHeight: CGFloat = 48
    let scrollView = NSScrollView()
    private let table = NSTableView()
    private var items: [RecordCopy] = []
    private var missing: Set<UUID> = []
    fileprivate var add: (RecordCopy) -> Void = { _ in }
    fileprivate var toggleMissing: (RecordCopy) -> Void = { _ in }

    override init() {
        super.init()
        table.addTableColumn(NSTableColumn(identifier: .init("record")))
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.usesAutomaticRowHeights = false
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.focusRingType = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(doubleClicked(_:))
        table.dataSource = self
        table.delegate = self

        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: AppStyle.tightSpacing, left: 0, bottom: AppStyle.tightSpacing, right: 0)
    }

    /// Redraws only the rows whose "Nicht auffindbar" state changed.
    func setMissing(_ new: Set<UUID>) {
        guard new != missing else { return }
        let changed = new.symmetricDifference(missing)
        missing = new
        let rows = IndexSet(items.indices.filter { changed.contains(items[$0].id) })
        if !rows.isEmpty { table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0)) }
    }

    func apply(_ new: [RecordCopy]) {
        let oldIDs = items.map(\.id)
        let newIDs = new.map(\.id)
        guard oldIDs != newIDs else { items = new; return }
        items = new
        if let removed = Self.removedIndexes(from: oldIDs, to: newIDs) {
            // Records added here: animate just those rows; everything else,
            // including the scroll offset, stays exactly in place.
            table.removeRows(at: removed, withAnimation: [.effectFade, .slideUp])
        } else {
            // First load or a new search: show the results from the top.
            table.reloadData()
            table.scrollRowToVisible(0)
        }
    }

    /// Indexes dropped from `old` if `new` is `old` minus some elements in
    /// the same order; `nil` otherwise.
    static func removedIndexes(from old: [UUID], to new: [UUID]) -> IndexSet? {
        guard new.count < old.count else { return nil }
        var removed = IndexSet()
        var next = 0
        for (index, id) in old.enumerated() {
            if next < new.count, new[next] == id { next += 1 } else { removed.insert(index) }
        }
        return next == new.count ? removed : nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let copy = items[row]
        let rowView = ShelfAssignmentRow(copy: copy, missing: missing.contains(copy.id),
                                         toggleMissing: { [weak self] in self?.toggleMissing(copy) }) { [weak self] in self?.add(copy) }
        let id = NSUserInterfaceItemIdentifier("ShelfAssignmentRow")
        if let host = tableView.makeView(withIdentifier: id, owner: nil) as? NSHostingView<ShelfAssignmentRow> {
            host.rootView = rowView
            return host
        }
        let host = NSHostingView(rootView: rowView)
        host.identifier = id
        host.sizingOptions = []
        return host
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    @objc private func doubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard items.indices.contains(row) else { return }
        add(items[row])
    }
}

private struct ShelfAssignmentRow: View {
    let copy: RecordCopy
    /// Marked "Nicht auffindbar": shown paused, still addable once it turns up.
    let missing: Bool
    let toggleMissing: () -> Void
    let add: () -> Void

    var body: some View {
        let artist = copy.release?.displayArtist ?? "—"
        let title = copy.release?.displayTitle ?? "—"
        HStack(spacing: AppStyle.rowSpacing) {
            CoverView(url: copy.release?.coverURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist).font(.callout.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if missing { MissingBadge() }
                }
            }
            .opacity(missing ? 0.55 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(artist) – \(title)")
            Spacer(minLength: AppStyle.itemSpacing)
            Button(action: toggleMissing) {
                Image(systemName: missing ? "pause.fill" : "pause")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(missing ? AppStyle.errorColor.opacity(0.12) : AppStyle.hoverBackground, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(missing ? AppStyle.errorColor : .secondary)
            .help(missing ? "Wieder gefunden" : "Nicht auffindbar – vorerst zurückstellen")
            .accessibilityLabel(missing ? "\(artist) – \(title) wieder gefunden" : "\(artist) – \(title) als nicht auffindbar markieren")
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(AppStyle.hoverBackground, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Ins Fach hinzufügen")
            .accessibilityLabel("\(artist) – \(title) ins Fach hinzufügen")
        }
        .padding(.horizontal, AppStyle.pagePadding)
        .frame(height: ShelfAssignmentTableController.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ShelfAssignmentPresentation {
    static func availableCopies(
        _ copies: [RecordCopy],
        for shelf: Shelf,
        matching query: String,
        owner: String? = nil,
        excluding excluded: Set<UUID> = []
    ) -> [RecordCopy] {
        // Only copies without a shelf that aren't marked "Nicht im Regal". Moving
        // between shelves happens by taking a
        // copy out (trash) and adding it here. Reads the copy → shelf side of the
        // relationship, which PositionService writes directly; the inverse
        // `shelf.copies` can lag one update cycle behind.
        sortedByArtist(
            candidates(copies, owner: owner, excluding: excluded)
                .filter { query.isEmpty || SortingService.matches($0, query: query) }
        )
    }

    static func candidates(_ copies: [RecordCopy], owner: String?, excluding excluded: Set<UUID>) -> [RecordCopy] {
        copies.filter { isCandidate($0, owner: owner, excluding: excluded) }
    }

    /// Without a shelf, in the current collection and not "Nicht im Regal".
    static func isCandidate(_ copy: RecordCopy, owner: String?, excluding excluded: Set<UUID>) -> Bool {
        copy.shelf == nil && copy.isInCurrentCollection(owner: owner) && !excluded.contains(copy.id)
    }

    /// Artist, then title. Keys are built once per record instead of twice
    /// per comparison.
    static func sortedByArtist(_ copies: [RecordCopy]) -> [RecordCopy] {
        copies
            .map { (copy: $0, key: SortingService.sortKey($0)) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.copy)
    }
}

