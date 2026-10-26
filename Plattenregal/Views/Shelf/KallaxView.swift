import SwiftUI
import SwiftData

/// The shelf page as one calm column: the KALLAX drawn as a single piece of
/// furniture and the selected compartment underneath at full width with
/// a cover grid or compact table. The search sits in the toolbar; its
/// matches float over the top of the page.
struct KallaxView: View {
    @Environment(\.modelContext) private var context
    /// Shared with the other pages, fetched only when they change (see `LibraryRecords`).
    private var records: LibraryRecords { .of(context) }
    private var allShelves: [Shelf] { records.shelves }
    private var cabinets: [Cabinet] { records.cabinets }
    private var allCopies: [RecordCopy] { records.copies }
    private var exclusions: [OptimizationExclusion] { records.exclusions }
    private var missingMarks: [MissingCopyMark] { records.missingMarks }
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true
    private var accounts: [DiscogsAccount] { records.accounts }
    /// The compartment selected in the rack.
    @State private var highlight: UUID?
    /// "Im Regal anzeigen" / "Platz im Regal finden" from other pages; taken
    /// over into `placement` right away. Also the round buttons' clicks and
    /// the panel over the page (see `ShelfRequests`).
    @Bindable var requests: ShelfRequests
    /// The text of the search field in the toolbar.
    let search: ShelfSearch
    @Environment(\.searchRequests) private var searchRequests
    /// The record being sorted in and the spots it fits alphabetically.
    @State private var placement: Placement?
    /// Measured height of the placement card; the compartment contents
    /// make room for it by moving down (see `shelfDetail`).
    @State private var placementCardHeight: CGFloat = 0
    /// The contents stand below the card by layout (`true`) or, while the
    /// card comes, goes or changes height, by an offset (see `moveCard`).
    @State private var cardSettled = true
    /// Only the latest of overlapping card moves settles the contents.
    @State private var cardMove = 0
    /// A card waiting for its compartment to be built (see `startPlacement`);
    /// cleared when anything else ends or replaces the placement.
    @State private var pendingPlacement: UUID?
    /// "Namen ändern …" from a locked compartment's menu.
    @State private var showsNameEditor = false
    /// Cabinet tab whose right-click menu is open, and where.
    @State private var cabinetMenu: (id: UUID, anchor: UnitPoint)?
    /// Cabinet tab whose name popover is open ("Regal umbenennen …").
    @State private var renamingCabinet: UUID?
    @State private var lockPreview = ShelfLockPreview()
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
    /// Whether the page is shown (see `PageActivity`).
    @State private var activity = PageActivity()
    /// Counts, labels and the sold count were computed at least once – at
    /// the page's first build, shown or not, so the first visit is instant.
    @State private var contentLoaded = false
    /// Records, places or the account changed while the page was hidden
    /// (a sync, edits on the collection page): `refreshContent` runs once it
    /// shows again, not after every change nobody sees.
    @State private var contentPending = false
    /// The same for a running search and new tracklists (see `applySearchWhenShown`).
    @State private var searchPending = false
    @State private var settingsTab: AppSettingsView.Tab?
    /// The side the next cabinet slides in from (see `show(_:)`).
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range

    /// Compartments of the active cabinets, cabinet by cabinet in reading
    /// order. Inactive cabinets keep their records but stay off this page.
    private var shelves: [Shelf] { Shelf.inUse(allShelves) }
    private var activeCabinets: [Cabinet] { cabinets.filter(\.isActive) }
    /// The cabinet drawn at the top: the one holding the selected compartment.
    private var shownCabinet: Cabinet? { shown.cabinet }
    private var committedShelf: Shelf? { shelves.first { $0.id == highlight } }
    /// What one render of the page draws, read once: `shelves` filters and
    /// sorts every compartment, and the rack, its tabs and the contents below
    /// each asked for it again (about ten times per click in the table).
    private struct Shown {
        let shelves: [Shelf]
        let cabinets: [Cabinet]
        /// The selected compartment (`committedShelf`).
        let shelf: Shelf?
        /// The cabinet holding it (`shownCabinet`).
        let cabinet: Cabinet?
    }
    private var shown: Shown {
        let shelves = shelves
        let cabinets = activeCabinets
        let shelf = shelves.first { $0.id == highlight }
        let cabinet = shelf?.cabinet.flatMap { cabinet in cabinets.first { $0.id == cabinet.id } } ?? cabinets.first
        return Shown(shelves: shelves, cabinets: cabinets, shelf: shelf, cabinet: cabinet)
    }

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
        // The collection check first: it fails for almost every record, so their
        // shelves aren't read (this runs after every save).
        return allCopies.filter { $0.leftCurrentCollection(owner: owner) && ($0.shelf?.isInUse ?? false) }
    }

    /// Empty while "Gesucht" is off in the settings: no marks shown anywhere
    /// on this page (they are kept, and return when it is switched on again).
    private var missingIDs: Set<UUID> { missingEnabled ? Set(missingMarks.map(\.copyID)) : [] }

    private func forgetCopies() {
        requests.panel = nil
        focusCopy = nil; placement = nil; pendingPlacement = nil; recentUnplace = nil
        pendingDelete = nil; confirmRemoveSold = false
    }

    private func setMissing(_ copy: RecordCopy, _ missing: Bool) {
        do { try PositionService(context: context).setMissing([copy], missing) }
        catch { self.error = error.reportedMessage() }
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
        searchPending = false
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
            // "Ohne Regalplatz" and records outside the current collection
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

    /// A running search follows new tracklists or another account now if
    /// the page is shown, else once it is. Not for changed records: the hits
    /// may hold one that was deleted, and the hidden page still draws them.
    private func applySearchWhenShown() {
        searchIndexStale = true
        guard !searchQuery.isEmpty else { return }
        if activity.isActive { applySearch() } else { searchPending = true }
    }

    /// Statistics and range labels of the compartments and the sold count.
    /// Reads every placed record's release after a sync (~40 ms for 720
    /// records, more from disk).
    private func refreshContent() {
        contentLoaded = true
        contentPending = false
        shelfContent.refresh(allShelves, version: changes.libraryVersion)
        shelfStats = Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, shelfContent.stats(for: $0)) })
        rangeLabels = ShelfRangeLabels.compute(for: allShelves, style: labelStyle, ends: shelfContent.ends)
        soldCount = soldInShelves.count
    }

    /// `refreshContent` now if the page is shown or was never computed, else once it is shown.
    /// Holds no records, so nothing stale can point at a deleted one meanwhile.
    private func refreshContentWhenShown() {
        guard activity.isActive || !contentLoaded else { contentPending = true; return }
        refreshContent()
    }

    /// The panel on top of the page and the round buttons' clicks: their own
    /// step, the page's chain of modifiers is already as long as the
    /// compiler takes in one expression.
    var body: some View {
        shelfPage
            .onChange(of: requests.pressed) { takeButtonRequest() }
            .onAppear { takeButtonRequest() }
            // ⌘Y opens the "Verlauf" and closes it again, like its round
            // button (see `AppShortcuts`).
            .background {
                Button("Verlauf") { press(.history) }
                    .keyboardShortcut(AppShortcuts.shelfHistory)
                    .hidden().frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .appPanel(item: $requests.panel, onDismiss: panelLeft) { panel in
                switch panel {
                case .assignment(let session):
                    ShelfAssignmentView(session: session, owner: owner, rangeLabel: session.shelf.flatMap { rangeLabels[$0.id] }, labels: rangeLabels,
                                        missingIDs: missingIDs,
                                        missingEnabled: missingEnabled,
                                        openMissing: { settingsTab = .lists })
                case .sortCheck(let request):
                    ShelfSortCheckView(shelf: request.shelf, rangeLabel: rangeLabels[request.shelf.id], close: { close(panel) })
                case .history:
                    ShelfHistoryView(labels: rangeLabels)
                }
            }
            // Catches up on what changed while another page was in front.
            .trackPageActivity(activity) { active in
                guard active else { return }
                if contentPending { refreshContent() }
                if searchPending { applySearch() }
            }
    }

    private var shelfPage: some View {
        GeometryReader { geometry in
            let page = self.shown
            let cabinet = page.cabinet
            // The search's hits, else the compartment the card points to.
            let lit = searchResults.litShelfIDs ?? placement?.spot.map { [$0.shelf.id] }
            VStack(alignment: .leading, spacing: AppStyle.blockSpacing) {
                // The page's notes as one block at the very top: the sold
                // records right below the demo banner (or in its place),
                // close together instead of a whole block apart.
                if DemoMode.showsBanner || soldCount > 0 || nothingPlaced {
                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        if DemoMode.showsBanner { DemoBanner() }
                        if soldCount > 0 { soldBanner(soldCount) }
                        if nothingPlaced {
                            // Typically right after a new install and the first sync.
                            AppBanner(message: String(localized: "Noch keine Platte steht in einem Fach. Hast du eine Sicherung deiner Fach-Belegung, stellst du sie hier wieder her."),
                                      kind: .info, actionTitle: String(localized: "Belegung wiederherstellen …"), action: { settingsTab = .backup })
                        }
                    }
                }
                if page.cabinets.count > 1 { cabinetSwitcher(page) }
                // One slot: the old cabinet fades out where the new one settles in.
                ZStack {
                    ShelfFurniture(
                        shelves: cabinet.map { cabinet in page.shelves.filter { $0.cabinet?.id == cabinet.id } } ?? page.shelves,
                        rows: cabinet?.rows ?? ShelfGeometry.rows,
                        columns: cabinet?.columns ?? ShelfGeometry.columns,
                        stats: { shelfStats[$0.id] ?? ShelfStatistics(shelf: $0) },
                        rangeLabel: { rangeLabels[$0.id] },
                        selectedID: page.shelf?.id,
                        litIDs: lit,
                        lockPreview: lockPreview,
                        select: selectShelf,
                        add: { shelf in selectShelf(shelf); startAssignment(shelf) },
                        menu: shelfMenu(for:)
                    )
                    // A compact overview with roughly KALLAX-like proportions, so the
                    // compartment area below (strip + table) gets most of the height.
                    // Always the full width, flush with the compartment area below.
                    .frame(height: ShelfFurnitureMetrics.height(rows: cabinet?.rows ?? ShelfGeometry.rows))
                    // Another cabinet fades and settles in like a page.
                    .id(cabinet?.id)
                    .transition(AppStyle.pageTransition)
                }
                shelfDetail(page.shelf)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, AppStyle.pageMargin)
            .padding(.top, AppStyle.pagePadding)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { deselect() })
            .onExitCommand { if placement != nil || pendingPlacement != nil { cancelPlacement() } else { deselect() } }
            .overlay(alignment: .bottom) { undoToast }
            // The matches of the search, right below the toolbar's bar
            // (centered like it), floating over the rack.
            .overlay(alignment: .top) { searchResultsPanel }
        }
        .observedTask(id: { statsSignature }) {
            refreshContentWhenShown()
            // Shown or not: selection, card and hits must never keep a
            // compartment or record that is gone (the hidden page still draws).
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
            if activity.isActive { soldCount = soldInShelves.count } else { contentPending = true }
            applySearchWhenShown()
        }
        // Tracklists don't show up in `statsSignature`; metadata does
        // (`libraryVersion`), so the task above covers it.
        .onObservedChange(of: { changes.tracksVersion }) { _, _ in applySearchWhenShown() }
        .onAppear { takePlacingRequest() }
        #if DEBUG
        // Screenshots without clicking: --preview-add opens
        // "Platte hinzufügen" for the selected compartment,
        // --preview-place=Artist the placement card of that artist's record,
        // --preview-sortcheck "Sortierung prüfen" of the first unsorted compartment,
        // --preview-sortin "Einsortieren" of the round button,
        // --preview-history the "Verlauf".
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            try? await Task.sleep(for: .seconds(1))
            if arguments.contains("--preview-add") {
                ensureShelfSelected()
                if let shelf = committedShelf { startAssignment(shelf) }
            } else if let raw = arguments.first(where: { $0.hasPrefix("--preview-place=") }) {
                let artist = String(raw.dropFirst("--preview-place=".count))
                if let copy = allCopies.first(where: { $0.release?.artist == artist }) { startPlacement(copy, opensShelf: true) }
            } else if arguments.contains("--preview-sortin") {
                startAssignment(nil)
            } else if arguments.contains("--preview-history") {
                openHistory()
            } else if arguments.contains("--preview-sortcheck") {
                let shelves = cabinets.flatMap(\.shelves)
                if let shelf = shelves.first(where: { !ShelfSortCheck.steps(PositionService.inShelfOrder($0.copies), by: .current).isEmpty }) {
                    requests.panel = .sortCheck(ShelfSortCheckRequest(shelf: shelf))
                }
            }
        }
        #endif
        .onChange(of: requests.placing) { takePlacingRequest() }
        // Marks change without touching `statsSignature` (menu, table, sheet).
        .onChange(of: missingIDs) { refreshPlacement() }
        // Settings (other window) rebuilt cabinets, restored a backup or reset
        // the locations: the sheet's list and target shelf may be stale or gone.
        .onObservedChange(of: { changes.shelvesVersion }) { _, _ in
            if case .assignment = requests.panel { AppLog.info("Regal", "„Platte hinzufügen“ geschlossen: Regale wurden in den Einstellungen geändert") }
            requests.panel = nil; showsNameEditor = false
        }
        // "Alles zurücksetzen" deleted every record: nothing here may keep
        // pointing at one – reading a deleted model crashes.
        .onReceive(NotificationCenter.default.publisher(for: .plattenregalDidReset)) { _ in forgetCopies() }
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
    private func cabinetSwitcher(_ shown: Shown) -> some View {
        HStack(spacing: AppStyle.itemSpacing) {
            GlassSegmentedPicker(
                selection: Binding(get: { shown.cabinet?.id }, set: { id in
                    if let cabinet = activeCabinets.first(where: { $0.id == id }) { show(cabinet) }
                }),
                options: shown.cabinets.map { Optional($0.id) },
                separators: true,
                secondaryClick: { id, point in if let id { cabinetMenu = (id, point) } }
            ) { id in
                cabinetTab(shown.cabinets.first { $0.id == id })
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
        // Tabs and rack belong together: a row's gap instead of a block's.
        .padding(.bottom, AppStyle.rowSpacing - AppStyle.blockSpacing)
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

    /// Selects the cabinet's starting compartment (see `startShelf(in:)`).
    private func show(_ cabinet: Cabinet) {
        guard cabinet.id != shownCabinet?.id, let shelf = startShelf(in: cabinet) else { return }
        withAnimation(AppStyle.layoutAnimation ?? AppStyle.fadeAnimation) { selectShelf(shelf) }
    }

    /// Records no longer in the collection but still in a compartment: a
    /// banner like the page's other notes, absent when there are none.
    private func soldBanner(_ sold: Int) -> some View {
        AppBanner(message: sold == 1
                    ? String(localized: "Eine Platte im Regal ist nicht mehr in deiner Discogs-Collection.")
                    : String(localized: "\(sold) Platten im Regal sind nicht mehr in deiner Discogs-Collection."),
                  kind: .warning,
                  actionTitle: String(localized: "Aus Regal nehmen …"),
                  action: { soldToRemove = sold; confirmRemoveSold = true })
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
                place: { startPlacement($0) }
            )
            // Still the previous query's matches while typing pauses.
            .opacity(searchQuery == search.text ? 1 : 0.6)
            .animation(AppStyle.quickAnimation, value: searchQuery == search.text)
            .frame(width: AppStyle.searchResultsWidth)
            .padding(.top, AppStyle.itemSpacing)
            .transition(.opacity)
        }
    }

    /// `selected`: `committedShelf`, read once for the render (see `Shown`).
    @ViewBuilder private func shelfDetail(_ selected: Shelf?) -> some View {
        if let shown = selected {
            // The placement card sits above the contents. While it comes, goes
            // or changes height, they move by an offset and keep their size:
            // resizing the grid or table on every frame of the animation made
            // it stutter (every cover's scroll layout and glass recomputed).
            // Once it stands, a padding takes over in one step that looks
            // the same, so the last records are reachable again.
            let cardInset = placement == nil ? 0 : placementCardHeight + AppStyle.sectionSpacing
            ZStack(alignment: .topLeading) {
                // One slot: an animated switch between an empty and a filled
                // compartment crossfades instead of stacking both for a moment.
                // The contents own their grid/list switch.
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
                        find: { startPlacement($0) },
                        unplace: unplace,
                        delete: { pendingDelete = $0 },
                        setMissing: setMissing
                    )
                    .equatable()
                }
                }
                .padding(.top, cardSettled ? cardInset : 0)
                .offset(y: cardSettled ? 0 : cardInset)
                if let placement {
                    PlacementCard(
                        placement: placement,
                        labels: rangeLabels,
                        missing: missingIDs,
                        choose: choosePlacementSpot,
                        confirm: confirmPlacement,
                        cancel: cancelPlacement
                    )
                    // Animated also when measured a frame late (the first
                    // card, or another spot chosen with more or fewer lines).
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                        guard height != placementCardHeight else { return }
                        moveCard { placementCardHeight = height }
                    }
                    .transition(AppStyle.funnelTransition())
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
                // "Ohne Regalplatz" meanwhile stays out; nothing to undo then.
                if canUndo(entry) {
                    Button("Rückgängig", action: undoUnplace)
                        .appLinkButton()
                        .keyboardShortcut(searchFocused ? nil : KeyboardShortcut("z", modifiers: .command))
                }
            }
            .font(.callout)
            .padding(.horizontal, AppStyle.cardPadding)
            .padding(.vertical, AppStyle.itemSpacing)
            .appChipSurface(in: Capsule())
            .padding(.bottom, AppStyle.cardPadding)
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
        Button("Sortierung prüfen") { selectShelf(shelf); requests.panel = .sortCheck(ShelfSortCheckRequest(shelf: shelf)) }
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

    /// New records go to their alphabetical place in the compartment –
    /// without one (the round button), each to its place in the rack.
    /// A new session per opening, so a reopened panel always starts from fresh data.
    private func startAssignment(_ shelf: Shelf?) {
        requests.panel = .assignment(ShelfAssignmentSession(shelf: shelf, openShelf: highlight, shownCabinet: shownCabinet?.id))
    }

    private func selectShelf(_ shelf: Shelf) {
        searchQuery = ""; focusCopy = nil; pendingPlacement = nil
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
        // Opening the compartment the card points to: a placed record is
        // picked out there, as if the card had opened it.
        if let placement, placement.found, placement.putAwayIn == nil, placement.spot?.shelf.id == shelf.id {
            focusCopy = placement.copy
            focusRevision += 1
        }
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

    /// There is always a selected shelf: the start of the first cabinet, or the
    /// first occupied compartment of any other one if that cabinet is empty.
    /// An existing valid selection (e.g. "im Regal zeigen") is kept.
    private func ensureShelfSelected() {
        if let highlight, shelves.contains(where: { $0.id == highlight }) { return }
        highlight = activeCabinets.first.flatMap { cabinet in
            shelves.first { $0.cabinet?.id == cabinet.id && Self.holdsRecords($0) }
        }?.id
            ?? shelves.first(where: Self.holdsRecords)?.id
            ?? shelves.first?.id
    }

    /// Where a cabinet is entered, the same for every way in (app start,
    /// switching cabinets): its first compartment with records in reading
    /// order – where the app starts the alphabet – else its first one. How the
    /// real rack is filled doesn't matter here.
    private func startShelf(in cabinet: Cabinet) -> Shelf? {
        let own = shelves.filter { $0.cabinet?.id == cabinet.id }
        return own.first(where: Self.holdsRecords) ?? own.first
    }

    private static func holdsRecords(_ shelf: Shelf) -> Bool { !shelf.isReserved && !shelf.copies.isEmpty }

    // MARK: Placement

    private func takePlacingRequest() {
        guard let id = requests.placing else { return }
        requests.placing = nil
        if let copy = allCopies.first(where: { $0.id == id }) { startPlacement(copy, opensShelf: true) }
    }

    // MARK: Panels

    private func takeButtonRequest() {
        guard let button = requests.pressed else { return }
        requests.pressed = nil
        press(button)
    }

    /// A round button or ⌘Y: its panel closes if it is the one open, else it
    /// opens – in place of any other panel (there is only one, see `ShelfPanel`).
    private func press(_ button: ShelfButton) {
        if let panel = requests.panel, panel.button == button { close(panel); return }
        switch button {
        case .history: openHistory()
        case .sortingIn: openSortingIn()
        }
    }

    private func openHistory() {
        if placement != nil || pendingPlacement != nil { cancelPlacement() }
        requests.panel = .history(ShelfHistoryRequest())
    }

    /// Every record without a shelf, each to its place in the rack.
    private func openSortingIn() {
        placement = nil; pendingPlacement = nil
        startAssignment(nil)
    }

    /// Closes this panel – only if it is still the one shown, so a late close
    /// from a panel that was already replaced can't close its successor.
    private func close(_ panel: ShelfPanel) {
        if requests.panel?.id == panel.id { requests.panel = nil }
    }

    /// A panel closed or was replaced. After "Platte hinzufügen" the shelf
    /// follows the last addition only now, so nothing rebuilds the panel
    /// while records are being added.
    private func panelLeft(_ panel: ShelfPanel) {
        guard case .assignment(let session) = panel,
              let copy = session.lastAdded, !copy.isDeleted, copy.modelContext != nil else { return }
        showPlaced(copy)
    }

    /// Shows the card for the record. The open compartment stays as it is
    /// and the rack marks the one the card points to – opening another
    /// compartment builds its whole grid. It is opened only when asked for
    /// (`opensShelf`: "Im Regal anzeigen" from another page) or when it
    /// stands in another cabinet, where the mark couldn't be seen.
    private func startPlacement(_ copy: RecordCopy, opensShelf: Bool = false) {
        searchQuery = ""; focusCopy = nil; showsNameEditor = false
        var new = Placement(copy: copy, shelves: shelves, openShelf: highlight, cabinet: shownCabinet?.id)
        new.excluded = exclusions.contains { $0.copyID == copy.id }
        new.missing = missingIDs.contains(copy.id)
        let target = new.spot?.shelf
        let otherCabinet = target.map { $0.cabinet?.id != shownCabinet?.id } ?? false
        let opens = target != nil && target?.id != highlight && (opensShelf || otherCabinet)
        // Another compartment builds its whole grid or table in one long
        // frame; a card animating in at the same time would stall and jump.
        // So the compartment opens first and the card follows once it's built.
        let id = UUID()
        pendingPlacement = opens ? id : nil
        moveCard {
            placement = opens ? nil : new
            if opens, let target { highlight = target.id }
        }
        // A placed record is picked out in the grid and selected in the table,
        // when its compartment is the open one.
        if new.found && new.putAwayIn == nil && target?.id == highlight {
            focusCopy = copy
            focusRevision += 1
        }
        guard opens else { return }
        Task {
            await Self.untilSettled()
            guard pendingPlacement == id else { return }
            pendingPlacement = nil
            moveCard { placement = new }
            refreshPlacement()
        }
    }

    /// Animates a change that moves the contents below the card: by an
    /// offset while it runs, then by layout again (see `shelfDetail`).
    private func moveCard(_ change: () -> Void) {
        cardMove += 1
        let move = cardMove
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { cardSettled = false }
        withAnimation(AppStyle.standardAnimation, change) {
            guard cardMove == move else { return }
            withTransaction(instant) { cardSettled = true }
        }
    }

    /// Returns once the main thread runs freely again: after a short
    /// minimum, two short sleeps in a row must come back on time. Gives up
    /// after about half a second.
    private static func untilSettled() async {
        let clock = ContinuousClock()
        try? await Task.sleep(for: .milliseconds(60))
        var calm = 0, tries = 0
        while calm < 2 && tries < 20 {
            tries += 1
            let start = clock.now
            try? await Task.sleep(for: .milliseconds(16))
            calm = clock.now - start < .milliseconds(32) ? calm + 1 : 0
        }
    }

    /// Records may change while the card is open (sync, edits in the table):
    /// recompute the spots, keeping the chosen shelf if it still fits. The
    /// card closes once the record was placed or taken out of its shelf.
    private func refreshPlacement() {
        guard let current = placement else { return }
        let copy = current.copy
        guard !copy.isDeleted, copy.modelContext != nil, (copy.shelf != nil) == current.found else { placement = nil; return }
        var updated = Placement(copy: copy, shelves: shelves, openShelf: highlight, cabinet: shownCabinet?.id)
        updated.excluded = current.excluded
        updated.missing = missingIDs.contains(copy.id)
        if let shelfID = current.spot?.shelf.id, let index = updated.spots.firstIndex(where: { $0.shelf.id == shelfID }) {
            updated.chosen = index
        }
        placement = updated
    }

    private func choosePlacementSpot(_ index: Int) {
        guard let placement, placement.spots.indices.contains(index) else { return }
        // Moves the mark in the rack; the open compartment stays.
        self.placement?.chosen = index
    }

    private func confirmPlacement() {
        guard let placement, let spot = placement.spot else { return }
        if placement.found {
            // Standing where it should: a "Gesucht" mark is settled.
            if placement.missing { setMissing(placement.copy, false) }
            moveCard { self.placement = nil }
            return
        }
        do {
            try PositionService(context: context).move(placement.copy, to: spot.shelf, position: spot.position, found: true)
            moveCard { self.placement = nil }
            if spot.shelf.id == highlight {
                focusCopy = placement.copy
                focusRevision += 1
            }
        } catch { self.error = error.reportedMessage() }
    }

    private func cancelPlacement() {
        pendingPlacement = nil
        moveCard { placement = nil }
    }

    private func unplace(_ copy: RecordCopy) {
        guard let shelf = copy.shelf else { return }
        if focusCopy?.id == copy.id { focusCopy = nil }
        do {
            guard let entry = try PositionService(context: context).unplace(copy) else { return }
            withAnimation(AppStyle.standardAnimation) { recentUnplace = UnplacedCopy(copy: copy, shelf: shelf, entry: entry) }
        } catch { self.error = error.reportedMessage() }
    }

    private func canUndo(_ entry: UnplacedCopy) -> Bool {
        // The compartment may be gone meanwhile (cabinet made smaller, backup
        // restored, reset); reading a deleted model would crash.
        !entry.copy.isDeleted && entry.copy.modelContext != nil
            && !entry.shelf.isDeleted && entry.shelf.modelContext != nil
            && entry.copy.shelf == nil && !entry.shelf.isReserved
            && !exclusions.contains { $0.copyID == entry.copy.id }
            && !entry.entry.isDeleted && entry.entry.modelContext != nil && entry.entry.undoneAt == nil
    }

    private func undoUnplace() {
        guard let entry = recentUnplace else { return }
        withAnimation(AppStyle.standardAnimation) { recentUnplace = nil }
        // Someone may have re-placed the copy meanwhile; don't yank it back.
        guard canUndo(entry) else { return }
        do { try PositionService(context: context).undo(entry.entry) }
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
        pendingPlacement = nil
        do { try PositionService(context: context).delete(copy) }
        catch { self.error = error.reportedMessage() }
    }
}
