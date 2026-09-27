import SwiftUI
import SwiftData

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
    /// Candidates marked "Vermisst": the view lists them in their own column.
    private(set) var missing: Set<UUID> = []
    /// For candidates that belong in another shelf alphabetically: its name,
    /// shown in their row ("gehört in „K – Ma“").
    private(set) var belongsElsewhere: [UUID: String] = [:]
    /// The row under the pointer; the target card tells where it would go.
    private(set) var hoveredID: UUID?
    var error: String?
    @ObservationIgnored let table = ShelfAssignmentTableController()

    init(shelf: Shelf) {
        self.shelf = shelf
    }

    /// `nil` once the record or the shelf is gone (see `isGone`).
    var hovered: RecordCopy? {
        hoveredID.flatMap { id in candidates.first { $0.id == id } }.flatMap { isGone($0) ? nil : $0 }
    }
    /// The last record added here, while it still stands in this shelf.
    var lastAddedHere: RecordCopy? {
        lastAdded.flatMap { !isGone($0) && $0.shelf?.id == shelf.id ? $0 : nil }
    }

    func hover(_ copy: RecordCopy, _ hovering: Bool) {
        if hovering { hoveredID = copy.id } else if hoveredID == copy.id { hoveredID = nil }
    }

    /// Where `copy` goes in this shelf: its alphabetical place among the
    /// records there, and the two it would stand between.
    func spot(for copy: RecordCopy) -> (position: Int, before: RecordCopy?, after: RecordCopy?) {
        let items = PositionService.inShelfOrder(shelf.copies, excluding: copy.id)
        let position = AlphabeticalPlacement.position(for: copy, in: shelf)
        return (position,
                position > 1 ? items[position - 2] : nil,
                position <= items.count ? items[position - 1] : nil)
    }

    var visible: [RecordCopy] {
        guard !query.isEmpty else { return candidates }
        let words = SearchIndex<UUID>.words(query)
        return candidates.filter { searchIndex.matches($0.id, words) }
    }

    /// Taken once: the list is a snapshot and must not reorder while records
    /// are added or paused. Records that fit this shelf alphabetically come
    /// first, then the rest – each by artist. Paused ones keep their place,
    /// so one found again returns right where it belongs.
    func load(_ context: ModelContext, owner: String?, labels: ShelfLabels) {
        guard !loaded else { return }
        loaded = true
        self.owner = owner
        do {
            let copies = try context.fetch(FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.shelf == nil }))
            let excluded = Set(try context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID))
            let available = ShelfAssignmentPresentation.candidates(copies, owner: owner, excluding: excluded)
            missing = Set(try context.fetch(FetchDescriptor<MissingCopyMark>()).map(\.copyID))
            let shelves = Shelf.inUse(try context.fetch(FetchDescriptor<Shelf>()))
            let fits = AlphabeticalPlacement.fittingShelves(for: available, in: shelves)
            for copy in available {
                guard let other = fits[copy.id], !other.isEmpty, !other.contains(where: { $0.id == shelf.id }) else { continue }
                belongsElsewhere[copy.id] = other.map { labels.prefix(for: $0) + (labels[$0.id] ?? $0.numberText) }
                    .joined(separator: " oder ")
            }
            let sorted = ShelfAssignmentPresentation.sortedByArtist(available)
            candidates = sorted.filter { belongsElsewhere[$0.id] == nil } + sorted.filter { belongsElsewhere[$0.id] != nil }
            searchIndex = SearchIndex(available, id: \.id, text: SortingService.searchText)
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
            // Its alphabetical place; standing in a shelf now, it turned up after all.
            try PositionService(context: context).move(copy, to: shelf, position: spot(for: copy).position, found: true)
            missing.remove(copy.id)
            if hoveredID == copy.id { hoveredID = nil }
            candidates.removeAll { $0.id == copy.id }
            lastAdded = copy
            addedCount += 1
            error = nil
        } catch { self.error = error.reportedMessage() }
    }

    /// Marks changed elsewhere (e.g. "Wieder gefunden" in the "Vermisst"
    /// column): the paused rows follow.
    func syncMissing(_ ids: Set<UUID>) {
        if ids != missing { missing = ids }
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

/// "+" in the compartment header: pick records that don't have a shelf yet;
/// beside them, while any are marked, the "Vermisst" list.
/// Built like the record detail card: a glass panel over the page, closed by a click beside it or Esc,
/// the target compartment on a tinted glass card, the shared search bar and
/// compact rows with glass buttons. All state is in the session.
struct ShelfAssignmentView: View {
    @Bindable var session: ShelfAssignmentSession
    let owner: String?
    let rangeLabel: String?
    /// All shelf names, for the rows that belong elsewhere.
    let labels: ShelfLabels
    /// A record that belongs in another shelf: close and show its place there.
    let findPlace: (RecordCopy) -> Void
    /// Records marked "Vermisst" in the whole rack (see `KallaxView.missingCopies`).
    var missingCopies: [RecordCopy] = []
    /// Off in the settings: no pause buttons and no "Vermisst" column.
    var missingEnabled = true
    /// From the "Vermisst" column: close and show the record in its shelf.
    var showMissing: (RecordCopy) -> Void = { _ in }
    var found: (RecordCopy) -> Void = { _ in }
    @Environment(\.modelContext) private var context
    /// The "Vermisst" column folded away; remembered for the next opening.
    @AppStorage(DisplaySettings.missingColumnCollapsedKey) private var missingCollapsed = false

    static let listWidth: CGFloat = 460
    static let missingWidth: CGFloat = 380
    /// The column only while something is marked: without, the panel stays narrow.
    private var hasMissing: Bool { missingEnabled && !missingCopies.isEmpty }
    private var showsMissing: Bool { hasMissing && !missingCollapsed }

    var body: some View {
        HStack(spacing: 0) {
            addColumn
                .frame(width: Self.listWidth)
            if showsMissing {
                Divider().padding(.vertical, AppStyle.pagePadding)
                MissingCopiesColumn(copies: missingCopies, labels: labels, show: showMissing, found: found,
                                    collapse: { missingCollapsed = true })
                    .frame(width: Self.missingWidth)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .frame(height: 640)
        .animation(AppStyle.standardAnimation, value: showsMissing)
        .onChange(of: Set(missingCopies.map(\.id))) { _, ids in session.syncMissing(ids) }
    }

    private var addColumn: some View {
        // Records marked "Vermisst" are listed in their own column, not here.
        let items = missingEnabled ? session.visible.filter { !session.missing.contains($0.id) } : session.visible
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Platte hinzufügen").font(AppStyle.dialogTitle)
                    Spacer()
                    // Folded away: the count, and the way to unfold it again.
                    if hasMissing && missingCollapsed {
                        Button { missingCollapsed = false } label: {
                            HStack(spacing: 4) {
                                Text("\(missingCopies.count) vermisst").monospacedDigit()
                                Image(systemName: "chevron.left").font(.caption.weight(.semibold))
                            }
                            .font(.callout)
                            .foregroundStyle(AppStyle.errorColor)
                            .lineLimit(1)
                            .fixedSize()
                        }
                        .appGlassButton()
                        .help("Vermisst-Liste aufklappen")
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                        .transition(.opacity)
                    }
                }
                .animation(AppStyle.standardAnimation, value: showsMissing)
                targetCard
                AppSearchField(placeholder: "Platten ohne Fach durchsuchen", text: $session.query)
                if let error = session.error {
                    AppBanner(message: error, kind: .error)
                        .transition(AppStyle.funnelTransition())
                }
                listCaption(count: items.count)
                    .padding(.top, AppStyle.tightSpacing)
                    // Nothing listed: the empty state below says it.
                    .opacity(items.isEmpty ? 0 : 1)
            }
            .padding(.horizontal, AppStyle.pagePadding)
            .padding(.top, AppStyle.pagePadding)
            ZStack {
                ShelfAssignmentTable(controller: session.table, items: items, missing: missingEnabled ? session.missing : [],
                                     missingEnabled: missingEnabled,
                                     // The next one by artist that fits here: where to go on.
                                     suggestedID: items.first { session.belongsElsewhere[$0.id] == nil }?.id,
                                     belongsElsewhere: session.belongsElsewhere,
                                     toggleMissing: { [session, context] copy in session.toggleMissing(copy, in: context) },
                                     hover: { [session] copy, hovering in session.hover(copy, hovering) },
                                     findPlace: findPlace) { [session, context] copy in
                    session.add(copy, in: context)
                }
                if session.loaded && items.isEmpty {
                    if !session.query.isEmpty {
                        AppEmptyState("Keine Treffer", systemImage: "magnifyingglass",
                                      description: Text("Versuche einen anderen Suchbegriff."))
                    } else if pausedCount > 0 {
                        AppEmptyState("Nur noch vermisste Platten", systemImage: "checkmark.circle",
                                      description: Text("Alle übrigen Platten ohne Fach stehen unter „Vermisst“."))
                    } else {
                        AppEmptyState("Alles einsortiert", systemImage: "checkmark.circle",
                                      description: Text("Jede Platte der Sammlung liegt bereits in einem Fach."))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(AppStyle.standardAnimation, value: session.error)
        .onAppear { session.load(context, owner: owner, labels: labels) }
    }

    /// Where the records go, like "Standort" on the detail card: the shelf,
    /// and – for the row under the pointer, else the last one added – the
    /// two records it goes between. The count of additions on the right.
    private var targetCard: some View {
        HStack(spacing: AppStyle.rowSpacing) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppStyle.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(rangeLabel.map { "Fach „\($0)“" } ?? "Dieses Fach").font(.headline).lineLimit(1)
                // One line, so long names never grow the card.
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: AppStyle.itemSpacing)
            if session.addedCount > 0 {
                Label("\(session.addedCount) hinzugefügt", systemImage: "checkmark")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppStyle.accent)
                    .contentTransition(.numericText())
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, AppStyle.cardPadding)
        .padding(.vertical, AppStyle.rowSpacing)
        .accentGlassCard()
        .animation(AppStyle.standardAnimation, value: session.addedCount)
        .animation(AppStyle.quickAnimation, value: session.hoveredID)
    }

    private var detail: String {
        if let copy = session.hovered {
            let artist = "„\(copy.release?.displayArtist ?? "—")“"
            if let other = session.belongsElsewhere[copy.id] { return "\(artist) gehört in „\(other)“ – Pfeil führt dorthin" }
            return "\(artist) \(place(session.spot(for: copy)))"
        }
        if let copy = session.lastAddedHere {
            let spot = session.spot(for: copy)
            return "Zuletzt „\(copy.release?.displayArtist ?? "—")“ \(place(spot))"
        }
        return "Jede Platte kommt an ihre alphabetische Stelle"
    }

    /// "zwischen „Air“ und „Björk“", "vor „Air“", "nach „Zappa“", "als erste Platte".
    private func place(_ spot: (position: Int, before: RecordCopy?, after: RecordCopy?)) -> String {
        func name(_ copy: RecordCopy) -> String { "„\(copy.release?.displayArtist ?? "—")“" }
        switch (spot.before, spot.after) {
        case let (before?, after?): return "zwischen \(name(before)) und \(name(after))"
        case let (nil, after?): return "ganz vorn, vor \(name(after))"
        case let (before?, nil): return "ans Ende, nach \(name(before))"
        case (nil, nil): return "als erste Platte"
        }
    }

    private func listCaption(count: Int) -> some View {
        HStack(spacing: 0) {
            Text("\(AppStyle.records(count)) ohne Fach").foregroundStyle(.secondary)
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
    }

    private var pausedCount: Int {
        guard missingEnabled else { return 0 }
        return session.candidates.filter { session.missing.contains($0.id) }.count
    }
}

/// Shows the session's table. SwiftUI may create and drop this wrapper as
/// often as it likes; it always hands back the same scroll view, so the
/// offset and the rows shown survive any rebuild of the sheet.
private struct ShelfAssignmentTable: NSViewRepresentable {
    let controller: ShelfAssignmentTableController
    let items: [RecordCopy]
    let missing: Set<UUID>
    let missingEnabled: Bool
    let suggestedID: UUID?
    let belongsElsewhere: [UUID: String]
    let toggleMissing: (RecordCopy) -> Void
    let hover: (RecordCopy, Bool) -> Void
    let findPlace: (RecordCopy) -> Void
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
        controller.hover = hover
        controller.findPlace = findPlace
        controller.belongsElsewhere = belongsElsewhere
        controller.setMissingEnabled(missingEnabled)
        controller.setMissing(missing)
        controller.apply(items)
        controller.setSuggested(suggestedID)
    }
}

/// The candidate list as a plain NSTableView. Removing a row there keeps the
/// clip view's origin as is: the row fades, the rows below slide up, and the
/// next "+" ends up exactly under the pointer.
@MainActor
final class ShelfAssignmentTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let rowHeight: CGFloat = 52
    let scrollView = NSScrollView()
    private let table = NSTableView()
    private var items: [RecordCopy] = []
    private var missing: Set<UUID> = []
    private var missingEnabled = true
    private var suggestedID: UUID?
    /// Fixed for a session (see `ShelfAssignmentSession.load`).
    fileprivate var belongsElsewhere: [UUID: String] = [:]
    fileprivate var add: (RecordCopy) -> Void = { _ in }
    fileprivate var toggleMissing: (RecordCopy) -> Void = { _ in }
    fileprivate var hover: (RecordCopy, Bool) -> Void = { _, _ in }
    fileprivate var findPlace: (RecordCopy) -> Void = { _ in }

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

    /// The setting changed while open: every row loses or gains its pause button.
    func setMissingEnabled(_ enabled: Bool) {
        guard enabled != missingEnabled else { return }
        missingEnabled = enabled
        table.reloadData()
    }

    /// Moves the "Als Nächstes" mark, redrawing just the two rows.
    func setSuggested(_ id: UUID?) {
        guard id != suggestedID else { return }
        let changed: Set<UUID?> = [suggestedID, id]
        suggestedID = id
        let rows = IndexSet(items.indices.filter { changed.contains(items[$0].id) })
        if !rows.isEmpty { table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0)) }
    }

    /// Redraws only the rows whose "Vermisst" state changed.
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
            // Records added here (or marked "Vermisst"): animate just those
            // rows; everything else, including the scroll offset, stays in place.
            table.removeRows(at: removed, withAnimation: [.effectFade, .slideUp])
        } else if let inserted = Self.removedIndexes(from: newIDs, to: oldIDs) {
            // Found again: back at its place, sliding in.
            table.insertRows(at: inserted, withAnimation: [.effectFade, .slideDown])
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
        let rowView = ShelfAssignmentRow(copy: copy, missing: missing.contains(copy.id), missingEnabled: missingEnabled,
                                         suggested: copy.id == suggestedID,
                                         belongsIn: belongsElsewhere[copy.id],
                                         toggleMissing: { [weak self] in self?.toggleMissing(copy) },
                                         hover: { [weak self] in self?.hover(copy, $0) },
                                         findPlace: { [weak self] in self?.findPlace(copy) }) { [weak self] in self?.add(copy) }
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
    /// Marked "Vermisst": shown paused, still addable once it turns up.
    let missing: Bool
    /// Off in the settings: no pause button.
    let missingEnabled: Bool
    /// The next one to add by artist: lightly marked.
    let suggested: Bool
    /// The shelf it fits alphabetically, when that isn't this one.
    let belongsIn: String?
    let toggleMissing: () -> Void
    let hover: (Bool) -> Void
    let findPlace: () -> Void
    let add: () -> Void

    var body: some View {
        let artist = copy.release?.displayArtist ?? "—"
        let title = copy.release?.displayTitle ?? "—"
        HStack(spacing: AppStyle.rowSpacing) {
            CoverView(url: copy.release?.coverURL, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(artist).font(.callout.weight(.medium)).lineLimit(1)
                    if suggested {
                        Text("Als Nächstes")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppStyle.accent)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(AppStyle.accent.opacity(0.12), in: Capsule())
                            .fixedSize()
                            .help("Nach Interpret die nächste Platte für dieses Fach")
                    }
                }
                HStack(spacing: 6) {
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if missing { MissingBadge() }
                    if let belongsIn {
                        Text("gehört in „\(belongsIn)“")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .fixedSize()
                            .help("Passt alphabetisch in „\(belongsIn)“, nicht in dieses Fach")
                    }
                }
            }
            .opacity(missing ? 0.55 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(artist) – \(title)")
            Spacer(minLength: AppStyle.itemSpacing)
            if missingEnabled {
                RowGlassButton(systemImage: missing ? "pause.fill" : "pause",
                               color: missing ? AppStyle.errorColor : .secondary, action: toggleMissing)
                    .help(missing ? "Wieder gefunden" : "Vermisst – vorerst zurückstellen")
                    .accessibilityLabel(missing ? "\(artist) – \(title) wieder gefunden" : "\(artist) – \(title) als vermisst markieren")
            }
            if let belongsIn {
                RowGlassButton(systemImage: "arrow.turn.up.right", color: .secondary, action: findPlace)
                    .help("Zu „\(belongsIn)“ wechseln und dort einsortieren")
                    .accessibilityLabel("\(artist) – \(title) in „\(belongsIn)“ einsortieren")
            }
            // The main action: accent in the glyph, like chosen options elsewhere.
            RowGlassButton(systemImage: "plus", color: AppStyle.accent, action: add)
                .help(belongsIn == nil ? "An ihrer alphabetischen Stelle ins Fach hinzufügen" : "Trotzdem in dieses Fach hinzufügen")
                .accessibilityLabel("\(artist) – \(title) ins Fach hinzufügen")
        }
        .padding(.horizontal, AppStyle.pagePadding)
        .frame(height: ShelfAssignmentTableController.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The suggested row: a faint accent wash behind it.
        .background {
            if suggested {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppStyle.accent.opacity(0.07))
                    .padding(.horizontal, AppStyle.pagePadding - 10)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(Rectangle())
        .onHover(perform: hover)
    }
}

/// A small round Liquid Glass button for a row's actions.
private struct RowGlassButton: View {
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

enum ShelfAssignmentPresentation {
    /// Only copies without a shelf that aren't marked "Nicht im Regal". Moving
    /// between shelves happens by taking a copy out (trash) and adding it
    /// here. Reads the copy → shelf side of the relationship, which
    /// PositionService writes directly; the inverse `shelf.copies` can lag
    /// one update cycle behind.
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

// MARK: - Sortierung prüfen

/// One opening of "Sortierung prüfen" for a compartment.
struct ShelfSortCheckRequest: Identifiable {
    let id = UUID()
    let shelf: Shelf
}

/// "Sortierung prüfen" from a compartment's menu: checks its stored order
/// and, where records are out of place, lists the moves at the shelf one by
/// one – each only refers to records that already stand right. Once they
/// are done, "Reihenfolge übernehmen" stores the new order.
struct ShelfSortCheckView: View {
    let shelf: Shelf
    let rangeLabel: String?
    @Environment(\.modelContext) private var context
    @AppStorage(ShelfSecondaryOrder.key) private var savedOrder = ShelfSecondaryOrder.title
    @State private var order = ShelfSecondaryOrder.current
    /// Steps ticked off at the shelf.
    @State private var done: Set<UUID> = []
    @State private var error: String?

    private var gone: Bool { shelf.isDeleted || shelf.modelContext == nil }

    var body: some View {
        // A sync may be removing records meanwhile: never read a deleted one.
        let copies = gone ? [] : PositionService.inShelfOrder(shelf.copies.filter { !$0.isDeleted && $0.modelContext != nil })
        let steps = ShelfSortCheck.steps(copies, by: order)
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sortierung prüfen").font(AppStyle.dialogTitle)
                Text("\(rangeLabel.map { "Fach „\($0)“" } ?? "Dieses Fach") · \(AppStyle.records(copies.count)) · Plätze von links gezählt")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: AppStyle.rowSpacing) {
                Text("Nach Interpret, bei gleichem Interpreten nach").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                GlassSegmentedPicker(selection: $order, options: ShelfSecondaryOrder.allCases, small: true) { Text($0.title) }
                    .accessibilityLabel("Bei gleichem Interpreten nach")
            }
            if steps.isEmpty {
                inOrder(count: copies.count)
            } else {
                summary(steps)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            SortStepRow(number: index + 1, step: step, done: done.contains(step.id)) {
                                if done.contains(step.id) { done.remove(step.id) } else { done.insert(step.id) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
                footer(steps)
            }
            if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
        }
        .padding(AppStyle.pagePadding)
        .frame(width: 560)
        .animation(AppStyle.standardAnimation, value: order)
        .animation(AppStyle.standardAnimation, value: error)
        // Another order is another list of moves.
        .onChange(of: order) { done = [] }
    }

    private func inOrder(count: Int) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack(spacing: AppStyle.rowSpacing) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(AppStyle.successColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Alles in Ordnung").font(.headline)
                    Text(count < 2 ? "Zu wenige Platten, um etwas zu prüfen." : "Alle \(count) Platten stehen in der richtigen Reihenfolge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppStyle.cardPadding)
            .padding(.vertical, AppStyle.rowSpacing)
            .accentGlassCard()
            if order != savedOrder {
                HStack(spacing: AppStyle.rowSpacing) {
                    Text("Beim Einsortieren gilt bisher „\(savedOrder.title)“.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    SecondaryButton(title: "„\(order.title)“ übernehmen") { savedOrder = order }
                }
            }
        }
    }

    private func summary(_ steps: [ShelfSortCheck.Step]) -> some View {
        let finished = steps.filter { done.contains($0.id) }.count
        return HStack(spacing: AppStyle.rowSpacing) {
            Image(systemName: "arrow.left.arrow.right").font(.system(size: 20)).foregroundStyle(AppStyle.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(steps.count == 1 ? "1 Platte umstellen" : "\(steps.count) Platten umstellen").font(.headline)
                Text("Der Reihe nach herausnehmen und an die neue Stelle stellen. Die übrigen bleiben, wo sie sind.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: AppStyle.itemSpacing)
            Text("\(finished) / \(steps.count)")
                .font(.callout.weight(.medium)).monospacedDigit()
                .foregroundStyle(finished == steps.count ? AppStyle.successColor : .secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, AppStyle.cardPadding)
        .padding(.vertical, AppStyle.rowSpacing)
        .accentGlassCard()
        .animation(AppStyle.quickAnimation, value: finished)
    }

    private func footer(_ steps: [ShelfSortCheck.Step]) -> some View {
        HStack(spacing: AppStyle.rowSpacing) {
            Text(order == savedOrder
                 ? "Wenn alles umgestellt ist, die neue Reihenfolge übernehmen."
                 : "Übernimmt „\(order.title)“ auch für Platzsuche und Hinzufügen in allen Fächern.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: AppStyle.itemSpacing)
            PrimaryButton(title: "Reihenfolge übernehmen") { apply() }
        }
    }

    private func apply() {
        guard !gone else { return }
        do {
            try PositionService(context: context).sortAlphabetically(shelf, by: order)
            savedOrder = order
            done = []
            error = nil
        } catch { self.error = error.reportedMessage() }
    }
}

/// One move: the record with its cover and where it stands now, then where
/// it goes – behind the record shown (or at the very front, before it).
private struct SortStepRow: View {
    let number: Int
    let step: ShelfSortCheck.Step
    let done: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let release = step.copy.release
        Button(action: toggle) {
            HStack(spacing: AppStyle.rowSpacing) {
                ZStack {
                    Circle().strokeBorder(done ? Color.clear : Color.secondary.opacity(0.4), lineWidth: 1)
                    if done {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(AppStyle.successColor)
                    } else {
                        Text("\(number)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 22, height: 22)
                CoverView(url: release?.coverURL, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(release?.displayArtist ?? "—") – \(release?.displayTitle ?? "—")")
                        .font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 5) {
                        Text("Platz \(step.position)").monospacedDigit()
                        Image(systemName: "arrow.right").font(.caption2.weight(.semibold))
                        if let neighbour = step.before ?? step.after {
                            CoverView(url: neighbour.release?.coverURL, size: 16)
                            Text("\(step.before == nil ? "ganz vorn, vor" : "hinter") „\(neighbour.release?.displayArtist ?? "—") – \(neighbour.release?.displayTitle ?? "—")“")
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .opacity(done ? 0.45 : 1)
            .contentShape(Rectangle())
            .appHoverable(hovering, cornerRadius: 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: done)
        .help(done ? "Doch noch nicht umgestellt" : "Als umgestellt abhaken")
    }
}
