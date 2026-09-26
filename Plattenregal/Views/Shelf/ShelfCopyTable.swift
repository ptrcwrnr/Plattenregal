import SwiftUI
import SwiftData

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
    /// Marked "Vermisst".
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
struct ShelfCopyTable: View {
    @Environment(\.modelContext) private var context
    let shelf: Shelf
    let shelves: [Shelf]
    let rangeLabels: ShelfLabels
    let owner: String?
    /// Copies marked "Vermisst"; part of `signature`, so a mark
    /// rebuilds the rows like any other change.
    let missing: Set<UUID>
    let focusCopy: RecordCopy?
    let select: (RecordCopy?) -> Void
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
    /// The row whose menu is open, and where in the table it was right-clicked.
    @State private var menuFor: (id: UUID, anchor: UnitPoint)?
    @State private var error: String?

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

    /// The row's right-click menu (an `AppMenu`, like the collection's).
    @ViewBuilder private func rowMenu(_ copy: RecordCopy) -> some View {
        Button("Exemplar bearbeiten …") { quickEditID = copy.id }
        Button("Platz im Regal zeigen") { find(copy) }
        Divider()
        if missing.contains(copy.id) {
            Button("Wieder gefunden") { setMissing(copy, false) }
        } else {
            Button("Als vermisst markieren") { setMissing(copy, true) }
        }
        // Takes it out of the shelf for good: it no longer waits to be sorted in.
        Button("Nicht im Regal") {
            do { try PositionService(context: context).setExcluded([copy], true) }
            catch { self.error = error.reportedMessage() }
        }
        Button("Aus Fach entfernen") { unplace(copy) }
        // Only for records no longer in the Discogs collection: an
        // active one would come back with the next sync as a new copy.
        if !copy.isInCurrentCollection(owner: owner) {
            Divider()
            Button("Aus Sammlung löschen …", role: .destructive) { delete(copy) }
        }
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
            // Only for the double-click; the menu is the app's own (below).
            .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
                if let id = ids.first, items.contains(where: { $0.id == id }) { quickEditID = id }
            }
            .overlay(TableRowClicks(secondary: { row, point in
                guard items.indices.contains(row) else { return }
                menuFor = (items[row].id, point)
            }))
            .popover(isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }),
                     attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
                if let id = menuFor?.id, let copy = items.first(where: { $0.id == id })?.copy {
                    AppMenu(dismiss: { menuFor = nil }) { rowMenu(copy) }
                }
            }
            .alert("Änderung nicht möglich", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
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
/// position it stands at.
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
        /// Frosted glass behind the header: the rows scroll underneath it, and
        /// the see-through header let their text mix with the column titles.
        private let frost: NSVisualEffectView = {
            let view = NSVisualEffectView()
            view.material = .headerView
            view.blendingMode = .withinWindow
            view.state = .active
            return view
        }()
        private var frameObserver: NSObjectProtocol?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
            frameObserver = nil
            guard let clip = superview, let scroll = clip.superview else { return frost.removeFromSuperview() }
            // Sits in the scroll view right below the header's clip view, so it
            // covers the rows but never the column titles.
            scroll.addSubview(frost, positioned: .below, relativeTo: clip)
            frost.frame = clip.frame
            clip.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self, weak clip] _ in
                guard let clip else { return }
                MainActor.assumeIsolated { self?.frost.frame = clip.frame }
            }
        }

        isolated deinit {
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        }

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
