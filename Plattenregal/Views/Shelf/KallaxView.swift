import SwiftUI
import SwiftData

/// The shelf page as one calm column: the KALLAX drawn as a single piece of
/// furniture and the selected compartment underneath at full width with
/// a cover grid or compact table. The search sits in the toolbar; its
/// matches float over the top of the page.
struct KallaxView: View {
    @Environment(\.modelContext) var context
    /// Shared with the other pages, fetched only when they change (see `LibraryRecords`).
    var records: LibraryRecords { .of(context) }
    private var allShelves: [Shelf] { records.shelves }
    var cabinets: [Cabinet] { records.cabinets }
    var allCopies: [RecordCopy] { records.copies }
    var exclusions: [OptimizationExclusion] { records.exclusions }
    private var missingMarks: [MissingCopyMark] { records.missingMarks }
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true
    private var accounts: [DiscogsAccount] { records.accounts }
    /// The compartment selected in the rack.
    @State var highlight: UUID?
    /// "Im Regal anzeigen" / "Platz im Regal finden" from other pages; taken
    /// over into `placement` right away.
    let requests: ShelfRequests
    /// The text of the search field in the toolbar.
    let search: ShelfSearch
    @Environment(\.searchRequests) private var searchRequests
    /// The record being sorted in and the spots it fits alphabetically.
    @State var placement: Placement?
    /// "Namen ändern …" from a locked compartment's menu.
    @State var showsNameEditor = false
    /// Cabinet tab whose right-click menu is open, and where.
    @State var cabinetMenu: (id: UUID, anchor: UnitPoint)?
    /// Cabinet tab whose name popover is open ("Regal umbenennen …").
    @State var renamingCabinet: UUID?
    @State var lockPreview = ShelfLockPreview()
    /// The open "Platte hinzufügen" sheet. A new session per opening, so a
    /// reopened sheet always starts from fresh data.
    @State var assignment: ShelfAssignmentSession?
    /// Kept past the sheet's dismissal to pick up its last addition.
    @State var closingAssignment: ShelfAssignmentSession?
    // Last copy taken out of a shelf via the trash button, kept briefly so the
    // removal can be undone (toast button or ⌘Z) instead of confirmed up front.
    @State var recentUnplace: UnplacedCopy?
    @State var pendingDelete: RecordCopy?
    @State var confirmRemoveSold = false
    /// Count for the question, taken when it is asked – `soldInShelves` walks
    /// the whole collection and must not run on every rebuild of the page.
    @State var soldToRemove = 0
    /// `soldInShelves.count`, taken whenever records, places or the account
    /// change – not on every click in the table.
    @State var soldCount = 0
    /// The open "Sortierung prüfen".
    @State var sortCheck: ShelfSortCheckRequest?
    @State var error: String?

    // Search inside the shelf view only lists matches with their location; it
    // never changes the selection below. `focusCopy` is the record picked in
    // the table.
    /// The committed (debounced) query; `search.text` is what is being typed.
    @State var searchQuery = ""
    @State var searchResults = ShelfSearchResults()
    @State var searchIndex = SearchIndex<UUID>()
    /// Set when records change; the index is rebuilt on the next search only.
    @State var searchIndexStale = true
    @State var changes = LibraryChanges.shared
    @State var focusCopy: RecordCopy?
    /// Repeating an external request for the same copy must reveal it again.
    @State var focusRevision = 0
    /// Scroll anchors survive a visit to an empty or reserved compartment.
    @State var contentsSession = ShelfContentsSession()
    /// While the search field has focus, ⌘Z belongs to its text, not to the
    /// "Aus Fach entfernt" toast.
    var searchFocused: Bool { searchRequests?.fieldFocused ?? false }

    /// The account the collection shows (see `DiscogsAccount.current`).
    var owner: String? { DiscogsAccount.current(in: accounts)?.username }

    // Recomputed only when the underlying placement/style data actually changes
    // (see `statsSignature`), not on every keystroke or unrelated re-render.
    @State private var shelfStats: [UUID: ShelfStatistics] = [:]
    @State var rangeLabels = ShelfLabels()
    /// Per-shelf results behind `shelfStats` and `rangeLabels`; only shelves
    /// whose records changed are computed again.
    @State private var shelfContent = ShelfContentCache()
    @State private var settingsTab: AppSettingsView.Tab?
    /// The side the next cabinet slides in from (see `show(_:)`).
    @State var cabinetEdge: Edge = .trailing
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range

    /// Compartments of the active cabinets, cabinet by cabinet in reading
    /// order. Inactive cabinets keep their records but stay off this page.
    var shelves: [Shelf] { Shelf.inUse(allShelves) }
    var activeCabinets: [Cabinet] { cabinets.filter(\.isActive) }
    /// The cabinet drawn at the top: the one holding the selected compartment.
    var shownCabinet: Cabinet? {
        committedShelf?.cabinet.flatMap { cabinet in activeCabinets.first { $0.id == cabinet.id } } ?? activeCabinets.first
    }
    private var committedShelf: Shelf? { shelves.first { $0.id == highlight } }
    var detailShelf: Shelf? { committedShelf }

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
    var soldInShelves: [RecordCopy] {
        let owner = owner
        // Deactivated cabinets are put away and not shown here; their records
        // are neither counted nor taken out from this page.
        // The collection check first: it fails for almost every record, so their
        // shelves aren't read (this runs after every save).
        return allCopies.filter { $0.leftCurrentCollection(owner: owner) && ($0.shelf?.isInUse ?? false) }
    }

    /// Empty while "Gesucht" is off in the settings: no marks shown anywhere
    /// on this page (they are kept, and return when it is switched on again).
    var missingIDs: Set<UUID> { missingEnabled ? Set(missingMarks.map(\.copyID)) : [] }

    var body: some View {
        GeometryReader { geometry in
            let lit = searchResults.litShelfIDs
            VStack(alignment: .leading, spacing: AppStyle.blockSpacing) {
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
                    VStack(alignment: .leading, spacing: AppStyle.blockSpacing) {
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
            .padding(.horizontal, AppStyle.pageMargin)
            .padding(.top, AppStyle.pagePadding)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { deselect() })
            .onExitCommand { if placement != nil { cancelPlacement() } else { deselect() } }
            .overlay(alignment: .bottom) { undoToast }
            // The matches of the search, right below its field at the
            // right end of the toolbar, floating over the rack.
            .overlay(alignment: .topTrailing) { searchResultsPanel }
        }
        .observedTask(id: { statsSignature }) {
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
        .onObservedChange(of: { changes.libraryVersion }) { _, _ in searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        .onObservedChange(of: { changes.tracksVersion }) { _, _ in searchIndexStale = true; if !searchQuery.isEmpty { applySearch() } }
        .onAppear { takePlacingRequest(); takeSortingInRequest() }
        #if DEBUG
        // Screenshots without clicking: --preview-add opens
        // "Platte hinzufügen" for the selected compartment,
        // --preview-place=Artist the placement card of that artist's record,
        // --preview-sortcheck "Sortierung prüfen" of the first unsorted compartment,
        // --preview-sortin "Einsortieren" of the round button.
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            try? await Task.sleep(for: .seconds(1))
            if arguments.contains("--preview-add") {
                ensureShelfSelected()
                if let shelf = committedShelf { startAssignment(shelf) }
            } else if let raw = arguments.first(where: { $0.hasPrefix("--preview-place=") }) {
                let artist = String(raw.dropFirst("--preview-place=".count))
                if let copy = allCopies.first(where: { $0.release?.artist == artist }) { startPlacement(copy) }
            } else if arguments.contains("--preview-sortin") {
                startAssignment(nil)
            } else if arguments.contains("--preview-sortcheck") {
                let shelves = cabinets.flatMap(\.shelves)
                if let shelf = shelves.first(where: { !ShelfSortCheck.steps(PositionService.inShelfOrder($0.copies), by: .current).isEmpty }) {
                    sortCheck = ShelfSortCheckRequest(shelf: shelf)
                }
            }
        }
        #endif
        .onChange(of: requests.placing) { takePlacingRequest() }
        .onChange(of: requests.sortingIn) { takeSortingInRequest() }
        // Marks change without touching `statsSignature` (menu, table, sheet).
        .onChange(of: missingIDs) { refreshPlacement() }
        // Settings (other window) rebuilt cabinets, restored a backup or reset
        // the locations: the sheet's list and target shelf may be stale or gone.
        .onObservedChange(of: { changes.shelvesVersion }) { _, _ in
            if assignment != nil { AppLog.info("Regal", "„Platte hinzufügen“ geschlossen: Regale wurden in den Einstellungen geändert") }
            assignment = nil; showsNameEditor = false; sortCheck = nil
        }
        // "Alles zurücksetzen" deleted every record: nothing here may keep
        // pointing at one – reading a deleted model crashes.
        .onReceive(NotificationCenter.default.publisher(for: .plattenregalDidReset)) { _ in forgetCopies() }
        .appPanel(item: $assignment, onDismiss: {
            // The shelf behind the sheet follows the additions only now, so
            // nothing rebuilds the sheet while records are being added.
            if let copy = closingAssignment?.lastAdded, !copy.isDeleted, copy.modelContext != nil { showPlaced(copy) }
            closingAssignment = nil
        }) { session in
            ShelfAssignmentView(session: session, owner: owner, rangeLabel: session.shelf.flatMap { rangeLabels[$0.id] }, labels: rangeLabels,
                                missingIDs: missingIDs,
                                missingEnabled: missingEnabled,
                                openMissing: { settingsTab = .lists })
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

}
