import SwiftUI
import SwiftData


// MARK: - Copies in the selected compartment

/// One physical copy, even when several copies share the same release.
/// Both presentations use this snapshot, so a menu always acts on the copy
/// whose position is shown rather than on a release's first copy.
nonisolated struct ShelfCopyItem: Identifiable {
    let copy: RecordCopy
    let id: UUID
    let position: Int
    let artist: String
    let title: String
    /// 0 when unknown, so it sorts to one end instead of breaking the comparator.
    let year: Int
    let label: String
    let genre: String
    let sold: Bool
    let missing: Bool

    init(_ copy: RecordCopy, release: ShelfCopyReleaseFields, owner: String?, missing: Bool) {
        self.copy = copy
        id = copy.id
        position = copy.positionInShelf
        artist = release.artist
        title = release.title
        year = release.year
        label = release.label
        genre = release.genre
        sold = copy.leftCurrentCollection(owner: owner)
        self.missing = missing
    }

    /// SwiftData may publish the two sides of a relationship at different
    /// times after a move. The copy's current shelf is the final authority.
    @MainActor static func snapshot(for shelf: Shelf, owner: String?, missing: Set<UUID>) -> [ShelfCopyItem] {
        let copies = shelf.copies.filter { !$0.isDeleted && $0.shelf?.id == shelf.id }
        return PositionService.inShelfOrder(copies).map {
            ShelfCopyItem($0, release: .of($0), owner: owner, missing: missing.contains($0.id))
        }
    }
}

/// What a compartment's tiles and table rows show of a record's release,
/// kept per record until record data changes (`libraryVersion`, like
/// `ShelfSortKeys`). After every save SwiftData fetches each release again
/// one by one on the next read: sorting in a record or moving one with the
/// position slider re-read the whole compartment behind it (~20 ms for 150).
nonisolated struct ShelfCopyReleaseFields {
    let artist: String
    let title: String
    /// 0 when unknown, so it sorts to one end instead of breaking the comparator.
    let year: Int
    let label: String
    let genre: String

    @MainActor private static var cache: [PersistentIdentifier: ShelfCopyReleaseFields] = [:]
    @MainActor private static var version: Int?

    @MainActor static func of(_ copy: RecordCopy) -> ShelfCopyReleaseFields {
        let current = LibraryChanges.shared.libraryVersion
        if version != current { cache = [:]; version = current }
        let id = copy.persistentModelID
        if let fields = cache[id] { return fields }
        let release = copy.release
        let fields = ShelfCopyReleaseFields(artist: release?.displayArtist ?? "—", title: release?.displayTitle ?? "—",
                                            year: release?.year ?? 0, label: release?.displayLabel ?? "",
                                            genre: release?.primaryStyle ?? "")
        cache[id] = fields
        return fields
    }
}

/// Kept by the shelf page, including while an empty or reserved compartment
/// replaces this view. Scroll positions belong to one compartment and one
/// presentation; switching between them never overwrites the other's place.
@Observable final class ShelfContentsSession {
    // Not observed: the scroll views write them whenever another row reaches
    // the top, and an observed change re-ran the whole cover grid each time.
    // Restoring a place scrolls explicitly (`ScrollViewProxy`, the table's
    // scroll bridge), so no view needs to follow them.
    @ObservationIgnored var gridScrollPositions: [UUID: UUID] = [:]
    @ObservationIgnored var listScrollPositions: [UUID: UUID] = [:]
    var tableSortOrder = [KeyPathComparator(\ShelfCopyItem.position)]
}

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
    @AppStorage("shelfContentsLayout") private var layout = OverviewLayout.grid
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true

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
        hasher.combine(shelf.id)
        hasher.combine(LibraryChanges.shared.libraryVersion)
        hasher.combine(owner)
        for copy in shelf.copies where !copy.isDeleted && copy.shelf?.id == shelf.id {
            hasher.combine(copy.id)
            hasher.combine(copy.positionInShelf)
            hasher.combine(copy.discogsActive)
            hasher.combine(missing.contains(copy.id))
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
        let next = ShelfCopyItem.snapshot(for: shelf, owner: owner, missing: missing)
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
                Button("Als vermisst markieren") { menuFor = nil; setMissing(copy, true) }
            }
        }
        Button {
            menuFor = nil
            do {
                try PositionService(context: context).setExcluded([copy], true)
                placed(copy)
            } catch { self.error = error.reportedMessage() }
        } label: { Text("Nicht im Regal") }
        Button("Aus Fach entfernen") { menuFor = nil; unplace(copy) }
        // An active copy would return on the next sync as a new copy.
        if !copy.isInCurrentCollection(owner: owner) {
            Button("Aus Sammlung löschen …", role: .destructive) { menuFor = nil; delete(copy) }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Spacer(minLength: 12)
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

    private func grid(_ proxy: ScrollViewProxy) -> some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 4)
            let columns = CoverGrid.columnCount(available: width, minimum: 135)
            ScrollView {
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
                    .padding(.horizontal, 2 + CoverGrid.shadowRoom)
                    .padding(.top, 2)
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
    }

    private func tile(_ item: ShelfCopyItem) -> some View {
        let selected = focusCopy?.id == item.id
        return VStack(alignment: .leading, spacing: CoverGrid.captionSpacing) {
            CoverView(url: item.copy.release?.coverURL, size: nil)
                .atelierRecordSleeve()
                .overlay {
                    RoundedRectangle(cornerRadius: AtelierCoverFrame.usesMat ? AppStyle.cardRadius : 2)
                        .strokeBorder(selected ? AppStyle.selectedBorder : .clear, lineWidth: 2)
                }
                .overlay(alignment: .topLeading) {
                    Text(String(item.position))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .appChipSurface(in: Capsule())
                        .padding(AtelierCoverFrame.badgeInset)
                }
            // The same caption as in Collection and Wantlist.
            RecordCaption(release: item.copy.release, emphasized: selected)
            VStack(alignment: .leading, spacing: 3) {
                if item.missing { MissingBadge() }
                if item.sold {
                    Text("Nicht in der Collection")
                        .font(.caption2.weight(.medium)).foregroundStyle(AppStyle.warningColor)
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
            TableColumn("") { item in CoverView(url: item.copy.release?.coverURL, size: 20) }
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
                HStack(spacing: 6) {
                    Text(item.title).lineLimit(1).help(item.title)
                    if item.missing {
                        MissingBadge()
                            .help("Beim Einsortieren nicht gefunden – Rechtsklick → „Wieder gefunden“, sobald sie auftaucht")
                    }
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

/// SwiftUI's Table does not reliably publish or restore scrollPosition on
/// macOS. Keep the top visible copy through the native clip view instead.
/// A saved target is restored before any initial bounds change can replace it
/// with the new table's first row. External requests use their own token, so
/// asking to show the same copy again still centers it.
private struct ShelfTableScrollBridge: NSViewRepresentable {
    let ids: [UUID]
    let position: Binding<UUID?>
    let revealID: UUID?
    let revealRequest: UUID?

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.configure(ids: ids, position: position, revealID: revealID, revealRequest: revealRequest)
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stop() }

    final class Anchor: NSView {
        private var ids: [UUID] = []
        private var position: Binding<UUID?>?
        private var restoreID: UUID?
        private var revealID: UUID?
        private var revealRequest: UUID?
        private var lastRevealRequest: UUID?
        private var lastObservedID: UUID?
        private var needsRestore = true
        private var restoring = true
        private weak var table: NSTableView?
        private var observer: NSObjectProtocol?
        private var pending: DispatchWorkItem?
        private var generation = 0
        private var stopped = false

        func configure(ids: [UUID], position: Binding<UUID?>, revealID: UUID?, revealRequest: UUID?) {
            if self.position == nil || self.ids != ids {
                self.ids = ids
                restoreID = position.wrappedValue
                needsRestore = true
                restoring = true
                lastObservedID = nil
            }
            self.position = position
            self.revealID = revealID
            self.revealRequest = revealRequest
            schedule()
        }

        override func viewDidMoveToWindow() {
            if window == nil { stop() }
            else {
                stopped = false
                restoreID = position?.wrappedValue
                needsRestore = true
                restoring = true
                lastObservedID = nil
                schedule()
            }
        }

        override func layout() {
            super.layout()
            // A table can finish mounting after the bounded install retries.
            if window != nil, !stopped, needsRestore { schedule() }
        }

        private func schedule(attempt: Int = 0) {
            pending?.cancel()
            generation += 1
            let revision = generation
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.stopped, self.generation == revision, self.window != nil else { return }
                self.install(attempt: attempt)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.025), execute: work)
        }

        private func install(attempt: Int) {
            guard let native = nearbyTable(), let scroll = native.enclosingScrollView,
                  native.numberOfRows == ids.count, !ids.isEmpty,
                  scroll.contentView.bounds.height > 0, native.bounds.height > 0 else {
                if attempt < 20 { schedule(attempt: attempt + 1) }
                return
            }
            if table !== native {
                if let observer { NotificationCenter.default.removeObserver(observer) }
                table = native
                let clip = scroll.contentView
                clip.postsBoundsChangedNotifications = true
                observer = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.capture() }
                }
            }
            let wantsReveal = revealRequest != nil && revealRequest != lastRevealRequest
            guard needsRestore || wantsReveal else { return }
            // A remembered copy that has left the compartment restores to the top.
            if !wantsReveal, let id = restoreID, !ids.contains(id) { restoreID = nil }
            let target = wantsReveal ? revealID : restoreID
            guard let row = target.flatMap({ ids.firstIndex(of: $0) }) ?? (needsRestore && target == nil ? 0 : nil) else {
                if attempt < 20 { schedule(attempt: attempt + 1) }
                return
            }
            restoring = true
            native.layoutSubtreeIfNeeded()
            let clip = scroll.contentView
            let rect = native.rect(ofRow: row)
            // Inset tables draw their fixed header over the clip view. Its
            // top inset is real document space: row zero starts at -topInset,
            // and a restored row belongs below that header, not behind it.
            let inset = scroll.contentInsets
            // An inset NSTableView has an implicit header inset even when
            // NSScrollView.contentInsets reports zero (its natural y is -28).
            let topInset = max(inset.top, native.headerView?.frame.height ?? 0)
            if target != nil {
                let y = wantsReveal
                    ? rect.midY - (clip.bounds.height + topInset - inset.bottom) / 2
                    : rect.minY - topInset
                let minimum = -topInset
                let maximum = max(minimum, native.bounds.height - clip.bounds.height + inset.bottom)
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(minimum, y), maximum)))
                scroll.reflectScrolledClipView(clip)
            }
            native.headerView?.needsDisplay = true
            needsRestore = false
            if wantsReveal { lastRevealRequest = revealRequest }
            restoring = false
            capture()
        }

        private func capture() {
            guard !stopped, !restoring, !needsRestore, let table,
                  table.numberOfRows == ids.count, !ids.isEmpty else { return }
            var visible = table.visibleRect
            if let scroll = table.enclosingScrollView {
                let clip = scroll.contentView.bounds
                let topInset = max(scroll.contentInsets.top, table.headerView?.frame.height ?? 0)
                let top = max(visible.minY, clip.minY + topInset)
                let bottom = min(visible.maxY, clip.maxY - scroll.contentInsets.bottom)
                visible = NSRect(x: visible.minX, y: top, width: visible.width, height: max(0, bottom - top))
            }
            let rows = table.rows(in: visible)
            guard rows.location != NSNotFound, ids.indices.contains(rows.location) else { return }
            let id = ids[rows.location]
            guard id != lastObservedID else { return }
            lastObservedID = id
            if position?.wrappedValue != id { position?.wrappedValue = id }
        }

        func stop() {
            stopped = true
            generation += 1
            pending?.cancel()
            pending = nil
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            table = nil
        }

        isolated deinit {
            pending?.cancel()
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

/// A compact editor for the position within the copy's current compartment.
private struct ShelfCopyQuickEditor: View {
    let copy: RecordCopy
    @Environment(\.modelContext) private var context
    @State private var position = 1
    @State private var isSliding = false
    @State private var error: String?

    /// Walks the shelf's records: `body` reads it once (it runs again with
    /// every step of the slider), not in each of the places that show it.
    private var currentMaxPosition: Int {
        // The same copies the grid and table count (see `ShelfCopyItem.snapshot`).
        guard let shelf = copy.shelf else { return 1 }
        return shelf.copies.filter { !$0.isDeleted && $0.shelf?.id == shelf.id && $0.id != copy.id }.count + 1
    }

    var body: some View {
        let maxPosition = currentMaxPosition
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack(spacing: AppStyle.rowSpacing) {
                CoverView(url: copy.release?.coverURL, size: 44)
                    .atelierRecordSleeve()
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.release?.displayArtist ?? "—")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(copy.release?.displayTitle ?? "—")
                        .font(.headline).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Slider(value: Binding(
                get: { Double(position) },
                set: { value in
                    let next = min(max(Int(value.rounded()), 1), maxPosition)
                    if isSliding { position = next } else { setPosition(next) }
                }
            ), in: 1...Double(max(maxPosition, 2)), onEditingChanged: { editing in
                isSliding = editing
                if !editing { setPosition(position) }
            })
            .tint(AppStyle.isAtelier ? AtelierPalette.accent : nil)
            .opacity(AppStyle.isAtelier ? 0.02 : 1)
            .overlay {
                if AppStyle.isAtelier {
                    GeometryReader { geometry in
                        let inset: CGFloat = 10
                        let travel = max(geometry.size.width - 2 * inset, 0)
                        let progress = CGFloat(position - 1) / CGFloat(max(maxPosition - 1, 1))
                        ZStack(alignment: .leading) {
                            Capsule().fill(AtelierPalette.accent.opacity(0.15))
                                .frame(height: 5)
                            Capsule().fill(AtelierPalette.accent.opacity(0.65))
                                .frame(width: inset + travel * progress, height: 5)
                            Circle().fill(AtelierPalette.accent)
                                .frame(width: 20, height: 20)
                                .shadow(color: AtelierPalette.shadow, radius: 2, y: 1)
                                .offset(x: travel * progress)
                        }
                        .frame(height: geometry.size.height)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .disabled(maxPosition <= 1)
            .accessibilityLabel("Position")
            .accessibilityValue(String(localized: "\(position) von \(maxPosition)"))
            .help(String(localized: "Position 1 bis \(maxPosition)"))
            .overlay {
                GeometryReader { geometry in
                    if isSliding {
                        Text(String(position))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AppStyle.accent)
                            .position(
                                x: 10 + CGFloat(position - 1) / CGFloat(max(maxPosition - 1, 1)) * max(geometry.size.width - 20, 0),
                                y: -7
                            )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .padding(.top, 14)
            .padding(.bottom, AppStyle.tightSpacing)
            if let error {
                Text(error).font(.caption).foregroundStyle(AppStyle.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .padding(AppStyle.cardPadding)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { position = min(max(copy.positionInShelf, 1), currentMaxPosition) }
        .onDisappear { setPosition(position) }
        .appPopoverSurface()
    }

    private func setPosition(_ value: Int) {
        // A sync may have removed the copy while the popover was open.
        guard !copy.isDeleted, let shelf = copy.shelf else { return }
        do {
            let clamped = min(max(value, 1), currentMaxPosition)
            if clamped != copy.positionInShelf {
                try PositionService(context: context).move(copy, to: shelf, position: clamped)
            }
            position = clamped
            error = nil
        } catch {
            position = min(max(copy.positionInShelf, 1), currentMaxPosition)
            self.error = error.reportedMessage()
        }
    }
}

/// Icon columns (untitled: cover, row actions) don't need dividers in the
/// table header, and neither does the end of the last column. SwiftUI offers
/// no switch for that, so this swaps in a header view that leaves those out.
/// Used by every table in the app, so their headers look the same.
struct QuietIconColumnHeaders: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Anchor() }
    func updateNSView(_ view: NSView, context: Context) {
        guard let anchor = view as? Anchor else { return }
        // Read here, so switching the design updates the header right away;
        // AppKit draws it on its own and would keep the old look until the
        // next scroll or resize.
        anchor.atelier = AppStyle.isAtelier
        anchor.install()
    }

    final class Anchor: NSView {
        var atelier = AppStyle.isAtelier {
            didSet { if atelier != oldValue { nearbyTable()?.headerView?.needsDisplay = true } }
        }
        override func viewDidMoveToWindow() { install() }

        /// The table may not exist yet when this is placed (e.g. a window
        /// opened in the background); then it looks again a few times.
        func install(attempt: Int = 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.2)) { [weak self] in
                guard let self, self.window != nil else { return }
                guard let table = self.nearbyTable(), let header = table.headerView else {
                    if attempt < 10 { self.install(attempt: attempt + 1) }
                    return
                }
                if !(header is Header) {
                    let replacement = Header(frame: header.frame)
                    replacement.tableView = table
                    table.headerView = replacement
                }
                table.headerView?.tableView = table
                table.headerView?.needsDisplay = true
            }
        }
    }

    final class Header: NSTableHeaderView {
        /// Frosted glass behind the header: the rows scroll underneath it, and
        /// the see-through header let their text mix with the column titles.
        private let frost: NSVisualEffectView = {
            let view = NSVisualEffectView()
            view.material = .headerView
            view.blendingMode = .withinWindow
            view.state = .active
            return view
        }()
        // Klassisch paints its opaque petrol background in the same draw
        // pass as its titles, avoiding sibling layer ordering on remount.
        private var frameObserver: NSObjectProtocol?

        /// Vibrancy would darken the cream titles into the petrol.
        override var allowsVibrancy: Bool { AppStyle.isAtelier ? false : super.allowsVibrancy }

        override func viewWillDraw() {
            super.viewWillDraw()
            frost.isHidden = AppStyle.isAtelier
        }

        /// Draw the titles explicitly in both designs: SwiftUI's header cells
        /// can leave a replacement header blank when asked to draw themselves.
        /// Modern keeps its frosted backdrop; Klassisch paints the petrol band.
        private func drawColumnHeaders(_ table: NSTableView, dividers: [CGFloat]) {
            let atelier = AppStyle.isAtelier
            if atelier {
                NSColor(AtelierPalette.petrol).setFill()
                bounds.fill()
            }
            let titleColor = atelier ? NSColor(AtelierPalette.toolbarSelection) : NSColor.labelColor
            let secondaryTitleColor = atelier ? titleColor.withAlphaComponent(0.8) : NSColor.secondaryLabelColor
            let dividerColor = atelier ? titleColor.withAlphaComponent(0.18) : NSColor.separatorColor
            let sortKey = table.sortDescriptors.first
            for (index, column) in table.tableColumns.enumerated() where !column.title.isEmpty {
                let cell = column.headerCell
                let rect = headerRect(ofColumn: index)
                let sorted = sortKey != nil && column.sortDescriptorPrototype?.key == sortKey?.key
                let font = NSFont.systemFont(ofSize: cell.font?.pointSize ?? NSFont.systemFontSize,
                                             weight: sorted ? .semibold : .regular)
                let title = NSAttributedString(string: column.title, attributes: [
                    .font: font, .foregroundColor: sorted ? titleColor : secondaryTitleColor,
                ])
                let size = title.size()
                // Over the column's content, as the system header places its titles.
                let origin = NSPoint(x: rect.minX + 10, y: rect.midY - size.height / 2)
                title.draw(at: origin)
                if sorted, let ascending = sortKey?.ascending,
                   let arrow = NSImage(systemSymbolName: ascending ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: font.pointSize * 0.75, weight: .semibold).applying(.init(paletteColors: [titleColor]))) {
                    let arrowRect = NSRect(x: origin.x + size.width + 6, y: rect.midY - arrow.size.height / 2,
                                           width: arrow.size.width, height: arrow.size.height)
                    arrow.draw(in: arrowRect)
                }
            }
            dividerColor.setFill()
            for index in table.tableColumns.indices.dropLast() {
                let x = headerRect(ofColumn: index).maxX
                guard !dividers.contains(where: { abs($0 - x) < 1 }) else { continue }
                NSRect(x: x - 0.5, y: bounds.midY - 7, width: 1, height: 14).fill()
            }
            if !atelier {
                NSRect(x: bounds.minX, y: isFlipped ? bounds.maxY - 1 : bounds.minY,
                       width: bounds.width, height: 1).fill()
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
            frameObserver = nil
            guard let clip = superview, let scroll = clip.superview else {
                frost.removeFromSuperview()
                return
            }
            // Sits in the scroll view right below the header's clip view, so it
            // covers the rows but never the column titles.
            scroll.addSubview(frost, positioned: .below, relativeTo: clip)
            frost.frame = clip.frame
            clip.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self, weak clip] _ in
                guard let clip else { return }
                MainActor.assumeIsolated {
                    self?.frost.frame = clip.frame
                }
            }
        }

        isolated deinit {
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let table = tableView else { return super.draw(dirtyRect) }
            let columns = table.tableColumns
            // Skip dividers on an icon column, just before one and at the end
            // of the last column. The inset style's empty lead-in before the
            // first column has nothing to separate either.
            var edges: [CGFloat] = columns.isEmpty ? [] : [headerRect(ofColumn: 0).minX]
            for index in columns.indices {
                let isIcon = columns[index].title.isEmpty
                let beforeIcon = index + 1 < columns.count && columns[index + 1].title.isEmpty
                let isLast = index == columns.count - 1
                guard isIcon || beforeIcon || isLast else { continue }
                edges.append(headerRect(ofColumn: index).maxX)
            }
            drawColumnHeaders(table, dividers: edges)
        }
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
