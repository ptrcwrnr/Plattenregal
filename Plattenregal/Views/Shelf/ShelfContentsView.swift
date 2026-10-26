import SwiftUI
import SwiftData

// MARK: - Copies in the selected compartment

/// A cover grid in physical shelf order, or the original sortable table.
/// Owns a cached snapshot that follows actual content changes, not unrelated
/// page renders. Editing and actions are shared by both presentations.
struct ShelfContentsView: View, Equatable {
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

    /// The page passes new closures on every render of its own (a search
    /// keystroke, the placement card), and closures never compare equal: the
    /// whole grid was rebuilt each time, ~50–150 ms with a full compartment.
    /// They only call into the page's state, so the data decides. Changes
    /// to the records themselves arrive through Observation anyway.
    static func == (a: Self, b: Self) -> Bool {
        a.shelf === b.shelf && a.session === b.session && a.owner == b.owner && a.missing == b.missing
            && a.focusCopy === b.focusCopy && a.focusRevision == b.focusRevision
    }
    @AppStorage("shelfContentsLayout") private var layout = OverviewLayout.grid
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true
    @AppStorage(DisplaySettings.saleListKey) private var saleEnabled = true
    /// Records on the "Verkauf" list (settings tab "Listen"); none while the
    /// list is switched off there.
    private var forSale: Set<UUID> { saleEnabled ? Set(LibraryRecords.of(context).saleMarks.map(\.copyID)) : [] }

    /// Always in physical order. Sorting the table never changes the grid.
    @State private var items: [ShelfCopyItem] = []
    @State private var tableItems: [ShelfCopyItem] = []
    private var sortOrder: [KeyPathComparator<ShelfCopyItem>] { session.tableSortOrder }
    /// A selection made locally must not center itself under the pointer.
    @State private var clickedID: UUID?
    @State private var quickEditID: UUID?
    /// Updates arriving during an edit are applied once its popover closes.
    @State private var reloadPending = false
    @State private var loadedShelfID: UUID?
    @State private var loadedSignature: Int?
    @State private var menuFor: (id: UUID, anchor: UnitPoint)?
    @State private var gridClicks = GridSecondaryClicks<UUID>()
    @State private var error: String?
    @State private var focusScroll: FocusScroll?
    @State private var gridRestorePending = true
    /// Width of the grid's slot (see `grid`); 0 until it is laid out.
    @State private var gridWidth: CGFloat = 0
    /// A compartment opened for a record (search, "im Regal zeigen") stays
    /// invisible until it stands at that record, then fades in – instead of
    /// fading in at the top and visibly scrolling through the covers.
    @State private var gridRevealPending: UUID?

    private struct FocusScroll: Equatable {
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

    private var selection: Binding<UUID?> {
        Binding(
            get: { focusCopy?.id },
            set: { id in selectLocally(id.flatMap { id in items.first { $0.id == id }?.copy }) }
        )
    }

    private func selectLocally(_ copy: RecordCopy?) {
        clickedID = copy?.id
        focusScroll = nil
        select(copy)
    }

    private func quickEditBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { quickEditID == id }, set: { if !$0, quickEditID == id { quickEditID = nil } })
    }

    private func menuBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { menuFor?.id == id }, set: { if !$0, menuFor?.id == id { menuFor = nil } })
    }

    private func scrollPosition(for presentation: OverviewLayout) -> Binding<UUID?> {
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

    private func edit(_ copy: RecordCopy) {
        menuFor = nil
        selectLocally(copy)
        quickEditID = copy.id
    }

    private func activate(_ copy: RecordCopy) {
        edit(copy)
    }

    private func quickEditor(_ copy: RecordCopy) -> some View {
        ShelfCopyQuickEditor(copy: copy)
    }

    private func actionMenu(_ copy: RecordCopy) -> some View {
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

    /// Only the width counts (it sets the columns). A `GeometryReader` here
    /// rebuilt every tile on any change of size – also of the height alone,
    /// on every frame while the placement card pushed the grid down.
    private func grid(_ proxy: ScrollViewProxy) -> some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { gridWidth = $0 }
            .overlay(alignment: .topLeading) {
                // Built once the width is known, so it never reflows from zero.
                if gridWidth > 0 { gridScroll(proxy, width: max(0, gridWidth - 4)) }
            }
    }

    private func gridScroll(_ proxy: ScrollViewProxy, width: CGFloat) -> some View {
        let columns = CoverGrid.columnCount(available: width, minimum: 135)
        return ScrollView {
            // Every tile carries a glass tag (Modern): one container for
            // all of them renders them together, ~10 % less per scroll step.
            GlassEffectContainer(spacing: 0) {
                LazyVGrid(columns: CoverGrid.columns(count: columns), alignment: .leading, spacing: CoverGrid.spacing) {
                    ForEach(items) { item in
                        Button { activate(item.copy) } label: { tile(item) }
                            .buttonStyle(.plain)
                            .id(item.id)
                            .popover(isPresented: quickEditBinding(item.id), arrowEdge: .trailing) {
                                quickEditor(item.copy)
                            }
                            .gridSecondaryClickCell(item.id, in: gridClicks)
                            .popover(isPresented: menuBinding(item.id),
                                     attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
                                actionMenu(item.copy)
                            }
                            .help("Position \(item.position) · \(item.artist) · \(item.title)\nKlick: Exemplar bearbeiten. Rechtsklick: weitere Aktionen.")
                            .accessibilityLabel("Position \(item.position), \(item.artist), \(item.title)")
                            .accessibilityAddTraits(focusCopy?.id == item.id ? .isSelected : [])
                            .accessibilityAction(named: Text("Exemplar bearbeiten")) { edit(item.copy) }
                    }
                }
                .scrollTargetLayout()
                .gridSecondaryClickGrid(gridClicks)
                .coverGridMotion(width: width, columnCount: columns)
                // Room for the covers' shadows inside the scroll view, which
                // clips; the negative padding below keeps the covers flush
                // with the rack.
                .padding(.horizontal, AppStyle.hairSpacing + CoverGrid.shadowRoom)
                .padding(.top, AppStyle.hairSpacing)
                // The last covers scroll clear of the round button.
                .padding(.bottom, CoverGrid.spacing + AppStyle.floatingClearance)
            }
        }
        .onGridSecondaryClick(gridClicks) { id, point in
            quickEditID = nil
            menuFor = (id, point)
        }
        .padding(.horizontal, -CoverGrid.shadowRoom)
        .scrollPosition(tracking: scrollPosition(for: .grid))
        .opacity(gridRevealPending != nil && gridRevealPending == loadedShelfID ? 0 : 1)
        .id(loadedShelfID)
        .task(id: loadedShelfID) {
            let shelfID = shelf.id
            let saved = session.gridScrollPositions[shelfID]
            gridRestorePending = true
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled, layout == .grid, loadedShelfID == shelfID else { return }
            // On mount SwiftUI can publish row zero before applying an
            // existing scrollPosition. Keep capture closed until an
            // explicit restore has laid out the saved copy. An external
            // focus request takes precedence over a remembered position.
            let hasFocusRequest = focusScroll?.shelfID == shelfID && focusScroll?.layout == .grid
            if !hasFocusRequest, let saved, items.contains(where: { $0.id == saved }) {
                withAnimation(nil) {
                    session.gridScrollPositions[shelfID] = saved
                    proxy.scrollTo(saved, anchor: .top)
                }
            }
            // Opened for a record: jump to it while still invisible.
            if gridRevealPending == shelfID, let request = focusScroll, request.shelfID == shelfID,
               items.contains(where: { $0.id == request.copyID }) {
                withAnimation(nil) {
                    session.gridScrollPositions[shelfID] = request.copyID
                    proxy.scrollTo(request.copyID, anchor: .center)
                }
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(25))
            if gridRevealPending == shelfID {
                withAnimation(AppStyle.fadeAnimation) { gridRevealPending = nil }
            }
            guard !Task.isCancelled, layout == .grid, loadedShelfID == shelfID else { return }
            gridRestorePending = false
        }
    }

    private func tile(_ item: ShelfCopyItem) -> some View {
        let selected = focusCopy?.id == item.id
        return VStack(alignment: .leading, spacing: CoverGrid.captionSpacing) {
            CoverView(url: item.copy.release?.shownCoverURL, size: nil)
                .atelierRecordSleeve()
                .overlay {
                    RoundedRectangle(cornerRadius: AtelierCoverFrame.usesMat ? AppStyle.cardRadius : 2)
                        .strokeBorder(selected ? AppStyle.selectedBorder : .clear, lineWidth: AppStyle.selectionLineWidth)
                }
                .overlay(alignment: .topLeading) {
                    Text(String(item.position))
                        .font(AppStyle.captionMark).monospacedDigit()
                        .padding(.horizontal, AppStyle.itemSpacing).padding(.vertical, AppStyle.tightSpacing)
                        .appChipSurface(in: Capsule())
                        .padding(AtelierCoverFrame.badgeInset)
                }
            // The same caption as in Collection and Wantlist.
            RecordCaption(release: item.copy.release, emphasized: selected)
            VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                if item.missing { MissingBadge() }
                if item.forSale { SaleBadge() }
                if item.sold {
                    Text("Nicht in der Collection")
                        .font(AppStyle.badge).foregroundStyle(AppStyle.warningColor)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            .frame(minHeight: 14, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }

    private var table: some View {
        Table(tableItems, selection: selection, sortOrder: Binding(
            get: { sortOrder }, set: { session.tableSortOrder = $0 }
        )) {
            TableColumn("Pos.", value: \.position) { item in
                Text(String(item.position)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 34, ideal: 40, max: 52)
            TableColumn("") { item in CoverView(url: item.copy.release?.shownCoverURL, size: 20) }
                .width(24)
            TableColumn("Interpret", value: \.artist) { item in
                Text(item.artist).lineLimit(1).help(item.artist)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .popover(isPresented: quickEditBinding(item.id), arrowEdge: .trailing) {
                        quickEditor(item.copy)
                    }
            }
            .width(min: 120, ideal: 220)
            TableColumn("Titel", value: \.title) { item in
                HStack(spacing: AppStyle.itemSpacing) {
                    Text(item.title).lineLimit(1).help(item.title)
                    if item.missing {
                        MissingBadge()
                            .help("Beim Einsortieren nicht gefunden – Rechtsklick → „Wieder gefunden“, sobald sie auftaucht")
                    }
                    if item.forSale { SaleBadge() }
                    if item.sold {
                        StatusTag(text: String(localized: "Nicht in der Collection"), color: AppStyle.warningColor)
                            .help("Nicht (mehr) in deiner Discogs-Collection – per Rechtsklick aus dem Fach entfernen")
                    }
                }
            }
            .width(min: 120, ideal: 280)
            TableColumn("Jahr", value: \.year) { item in
                Text(item.year > 0 ? String(item.year) : "–").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 48, max: 60)
            TableColumn("Label", value: \.label) { item in
                Text(item.label.isEmpty ? "–" : item.label).lineLimit(1).foregroundStyle(.secondary).help(item.label)
            }
            .width(min: 80, ideal: 160)
            TableColumn("Genre", value: \.genre) { item in
                Text(item.genre.isEmpty ? "–" : item.genre).lineLimit(1).foregroundStyle(.secondary).help(item.genre)
            }
            .width(min: 80, ideal: 130)
        }
        .tableStyle(.inset)
        .background(QuietIconColumnHeaders())
        .background(TableRowClickToggle { selectLocally(nil) })
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        // The last rows scroll clear of the round button.
        .contentMargins(.bottom, AppStyle.floatingClearance, for: .scrollContent)
        .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
            if let id = ids.first, let copy = items.first(where: { $0.id == id })?.copy { activate(copy) }
        }
        .overlay(TableRowClicks(secondary: { row, point in
            guard tableItems.indices.contains(row) else { return }
            quickEditID = nil
            menuFor = (tableItems[row].id, point)
        }))
        .popover(isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }),
                 attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
            if let id = menuFor?.id, let copy = items.first(where: { $0.id == id })?.copy {
                actionMenu(copy)
            }
        }
        .background(ShelfTableScrollBridge(
            ids: tableItems.map(\.id),
            position: scrollPosition(for: .list),
            revealID: focusScroll?.layout == .list ? focusScroll?.copyID : nil,
            revealRequest: focusScroll?.layout == .list ? focusScroll?.requestID : nil
        ))
        .id(loadedShelfID)
        .appTableCard()
    }
}
