import SwiftUI
import SwiftData

// MARK: - Copies in the selected compartment

/// A cover grid in physical shelf order, or the original sortable table.
/// Owns a cached snapshot that follows actual content changes, not unrelated
/// page renders. Editing and actions are shared by both presentations.
struct ShelfContentsView: View {
    @Environment(\.modelContext) private var context
    let shelf: Shelf
    let session: ShelfContentsSession
    let owner: String?
    let missing: Set<UUID>
    let focusCopy: RecordCopy?
    let focusRevision: Int
    let select: (RecordCopy?) -> Void
    /// After a copy left its place here: the page lets go of its focus.
    let placed: (RecordCopy) -> Void
    /// Shows the card with the records this one stands between.
    let find: (RecordCopy) -> Void
    let unplace: (RecordCopy) -> Void
    let delete: (RecordCopy) -> Void
    let setMissing: (RecordCopy, Bool) -> Void
    @AppStorage("shelfContentsLayout") var layout = OverviewLayout.grid
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true
    @AppStorage(DisplaySettings.saleListKey) private var saleEnabled = true
    /// Records on the "Verkauf" list (settings tab "Listen"); none while the
    /// list is switched off there.
    var forSale: Set<UUID> { saleEnabled ? Set(LibraryRecords.of(context).saleMarks.map(\.copyID)) : [] }

    /// Always in physical order. Sorting the table never changes the grid.
    @State var items: [ShelfCopyItem] = []
    @State var tableItems: [ShelfCopyItem] = []
    var sortOrder: [KeyPathComparator<ShelfCopyItem>] { session.tableSortOrder }
    /// A selection made locally must not center itself under the pointer.
    @State private var clickedID: UUID?
    @State var quickEditID: UUID?
    /// Updates arriving during an edit are applied once its popover closes.
    @State private var reloadPending = false
    @State var loadedShelfID: UUID?
    @State private var loadedSignature: Int?
    @State var menuFor: (id: UUID, anchor: UnitPoint)?
    @State var gridClicks = GridSecondaryClicks<UUID>()
    @State private var error: String?
    @State var focusScroll: FocusScroll?
    @State var gridRestorePending = true
    /// A compartment opened for a record (search, "im Regal zeigen") stays
    /// invisible until it stands at that record, then fades in – instead of
    /// fading in at the top and visibly scrolling through the covers.
    @State var gridRevealPending: UUID?

    struct FocusScroll: Equatable {
        let shelfID: UUID
        let layout: OverviewLayout
        let copyID: UUID
        // Following the same copy again is still a new request.
        let requestID = UUID()
    }

    private var signature: Int {
        var hasher = Hasher()
        let forSale = forSale
        hasher.combine(shelf.id)
        hasher.combine(LibraryChanges.shared.libraryVersion)
        hasher.combine(owner)
        for copy in shelf.copies where !copy.isDeleted && copy.shelf?.id == shelf.id {
            hasher.combine(copy.id)
            hasher.combine(copy.positionInShelf)
            hasher.combine(copy.discogsActive)
            hasher.combine(missing.contains(copy.id))
            hasher.combine(forSale.contains(copy.id))
        }
        return hasher.finalize()
    }

    private var layoutSelection: Binding<OverviewLayout> {
        Binding(get: { layout }, set: { value in
            // Close capture before SwiftUI mounts the incoming presentation.
            gridRestorePending = true
            layout = value
        })
    }

    var selection: Binding<UUID?> {
        Binding(
            get: { focusCopy?.id },
            set: { id in selectLocally(id.flatMap { id in items.first { $0.id == id }?.copy }) }
        )
    }

    func selectLocally(_ copy: RecordCopy?) {
        clickedID = copy?.id
        focusScroll = nil
        select(copy)
    }

    func quickEditBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { quickEditID == id }, set: { if !$0, quickEditID == id { quickEditID = nil } })
    }

    func menuBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { menuFor?.id == id }, set: { if !$0, menuFor?.id == id { menuFor = nil } })
    }

    func scrollPosition(for presentation: OverviewLayout) -> Binding<UUID?> {
        let shelfID = shelf.id
        return Binding(
            get: {
                let id = presentation == .grid ? session.gridScrollPositions[shelfID] : session.listScrollPositions[shelfID]
                return id
            },
            set: { id in
                // A removed scroll view can emit nil while switching layouts.
                // Keep its last anchor; reload explicitly removes stale IDs.
                guard let id, layout == presentation, loadedShelfID == shelfID,
                      presentation != .grid || !gridRestorePending,
                      items.contains(where: { $0.id == id }) else { return }
                if presentation == .grid { session.gridScrollPositions[shelfID] = id }
                else { session.listScrollPositions[shelfID] = id }
            }
        )
    }

    private func reload() {
        let changedShelf = loadedShelfID != shelf.id
        if changedShelf {
            gridRestorePending = true
            // An editor from the previous compartment must never defer this
            // load, or keep a popover attached to one of its old tiles.
            quickEditID = nil
            menuFor = nil
            clickedID = nil
        } else if quickEditID != nil {
            reloadPending = true
            return
        }
        guard changedShelf || loadedSignature != signature || reloadPending else { return }
        reloadPending = false
        let next = ShelfCopyItem.snapshot(for: shelf, owner: owner, missing: missing, forSale: forSale)
        let newlyFocused = focusCopy.map { focus in !items.contains { $0.id == focus.id } } ?? false
        // Only a real compartment change fades the new contents in (grid and
        // table, as the table did before). Metadata updates and clicks never
        // reorder tiles with an animation, and table sorting stays immediate.
        let animate = loadedShelfID != nil && changedShelf
        if changedShelf, layout == .grid, AppStyle.layoutAnimation != nil,
           let id = focusCopy?.id, next.contains(where: { $0.id == id }) {
            gridRevealPending = shelf.id
        } else if changedShelf {
            gridRevealPending = nil
        }
        withAnimation(animate ? (layout == .grid ? AppStyle.layoutAnimation : AppStyle.fadeAnimation) : nil) {
            items = next
            tableItems = next.sorted(using: sortOrder)
            loadedShelfID = shelf.id
            loadedSignature = signature
        }
        let ids = Set(next.map(\.id))
        if let id = menuFor?.id, !ids.contains(id) { menuFor = nil }
        if let id = session.gridScrollPositions[shelf.id], !ids.contains(id) {
            session.gridScrollPositions[shelf.id] = nil
        }
        if let id = session.listScrollPositions[shelf.id], !ids.contains(id) {
            session.listScrollPositions[shelf.id] = nil
        }
        if changedShelf || newlyFocused {
            if let id = focusCopy?.id, ids.contains(id) { requestFocusScroll(id) }
            else { focusScroll = nil }
        }
    }

    private func requestFocusScroll(_ id: UUID) {
        focusScroll = FocusScroll(shelfID: shelf.id, layout: layout, copyID: id)
    }

    func edit(_ copy: RecordCopy) {
        menuFor = nil
        selectLocally(copy)
        quickEditID = copy.id
    }

    func activate(_ copy: RecordCopy) {
        edit(copy)
    }

    func quickEditor(_ copy: RecordCopy) -> some View {
        ShelfCopyQuickEditor(copy: copy)
    }

    func actionMenu(_ copy: RecordCopy) -> some View {
        AppMenu(dismiss: { menuFor = nil }) { rowMenu(copy) }
    }

    /// Both presentations use the same copy actions and persistence services.
    @ViewBuilder private func rowMenu(_ copy: RecordCopy) -> some View {
        Button("Exemplar bearbeiten") { edit(copy) }
        Button("Platz im Regal zeigen") { menuFor = nil; find(copy) }
        if missingEnabled {
            if missing.contains(copy.id) {
                Button("Wieder gefunden") { menuFor = nil; setMissing(copy, false) }
            } else {
                Button("Auf die Suchliste setzen") { menuFor = nil; setMissing(copy, true) }
            }
        }
        if saleEnabled {
            Button(forSale.contains(copy.id) ? "Nicht mehr verkaufen" : "Zum Verkauf vormerken") {
                menuFor = nil
                do { try PositionService(context: context).setForSale([copy], !forSale.contains(copy.id)) }
                catch { self.error = error.reportedMessage() }
            }
        }
        Button {
            menuFor = nil
            do {
                try PositionService(context: context).setExcluded([copy], true)
                placed(copy)
            } catch { self.error = error.reportedMessage() }
        } label: { Text("Ohne Regalplatz") }
        Button("Aus Fach entfernen") { menuFor = nil; unplace(copy) }
        // An active copy would return on the next sync as a new copy.
        if !copy.isInCurrentCollection(owner: owner) {
            Button("Aus Sammlung löschen …", role: .destructive) { menuFor = nil; delete(copy) }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                HStack(spacing: AppStyle.itemSpacing) {
                    Spacer(minLength: AppStyle.rowSpacing)
                    OverviewLayoutPicker(selection: layoutSelection.animation(AppStyle.fadeAnimation))
                        .accessibilityLabel("Ansicht der Fachinhalte")
                }
                // One slot for both: while fading between them, grid and
                // table overlap instead of sharing the height.
                ZStack(alignment: .topLeading) {
                    if layout == .grid { grid(proxy) }
                    else { table }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .alert("Änderung nicht möglich", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
            .task(id: signature) {
                guard !Task.isCancelled else { return }
                reload()
            }
            .onChange(of: shelf.id) { _, _ in reload() }
            .onChange(of: quickEditID) { _, id in
                if id == nil && reloadPending { reload() }
            }
            .onChange(of: sortOrder) { _, order in
                withAnimation(nil) { tableItems = items.sorted(using: order) }
            }
            .onChange(of: layout) { _, _ in
                gridRestorePending = true
                gridRevealPending = nil
                quickEditID = nil
                menuFor = nil
                focusScroll = nil
                // A previously visited presentation returns to its own place.
                // On the first switch, keep the selected copy in view.
                if scrollPosition(for: layout).wrappedValue == nil,
                   let id = focusCopy?.id, items.contains(where: { $0.id == id }) {
                    requestFocusScroll(id)
                }
            }
            .onChange(of: focusRevision) { _, _ in
                if let id = focusCopy?.id { requestFocusScroll(id) }
            }
            .onChange(of: focusCopy?.id) { _, id in
                let local = id != nil && id == clickedID
                clickedID = nil
                guard let id, !local else { focusScroll = nil; return }
                requestFocusScroll(id)
            }
            .task(id: focusScroll) {
                guard let request = focusScroll, request.layout == .grid else { return }
                // A request can arrive in the same update as a new compartment
                // or presentation. Let its scroll targets complete layout first.
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(25))
                guard !Task.isCancelled, request == focusScroll,
                      shelf.id == request.shelfID, layout == request.layout,
                      loadedShelfID == request.shelfID,
                      focusCopy?.id == request.copyID,
                      items.contains(where: { $0.id == request.copyID }) else { return }
                withAnimation(AppStyle.layoutAnimation) {
                    // ScrollViewReader can reveal a target without publishing
                    // it through scrollPosition. Keep the saved anchor in sync
                    // so a later status update cannot restore the old place.
                    session.gridScrollPositions[request.shelfID] = request.copyID
                    proxy.scrollTo(request.copyID, anchor: .center)
                }
            }
        }
    }

}
