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
    /// `nil`: "Einsortieren" from the round button – every record without a
    /// shelf, each to its own alphabetical place in the rack.
    let shelf: Shelf?
    var isRackWide: Bool { shelf == nil }
    /// Shelves in use, taken with the candidates (rack-wide places).
    private var shelves: [Shelf] = []
    /// Records without a shelf, sorted by artist; loaded once, then only
    /// shrinks as records are added here.
    private(set) var candidates: [RecordCopy] = []
    /// Account the candidates were chosen for (see `load`).
    private var owner: String?
    private(set) var loaded = false
    private(set) var addedCount = 0
    private(set) var lastAdded: RecordCopy?
    /// Candidates marked "Vermisst": left out of the list until they are
    /// released in the settings.
    private(set) var missing: Set<UUID> = []
    /// For candidates that belong in another shelf alphabetically: its name,
    /// shown in their row ("gehört in „K – Ma“"). Rack-wide: every
    /// candidate's shelf.
    private(set) var belongsElsewhere: [UUID: String] = [:]
    /// The row under the pointer; the target card tells where it would go.
    private(set) var hoveredID: UUID?
    var error: String?
    @ObservationIgnored let table = ShelfAssignmentTableController()

    init(shelf: Shelf?) {
        self.shelf = shelf
    }

    /// `nil` once the record or the shelf is gone (see `isGone`).
    var hovered: RecordCopy? {
        hoveredID.flatMap { id in candidates.first { $0.id == id } }.flatMap { isGone($0) ? nil : $0 }
    }
    /// The last record added here, while it still stands in this shelf
    /// (rack-wide: in any shelf).
    var lastAddedHere: RecordCopy? {
        lastAdded.flatMap { copy in
            guard !isGone(copy), let placed = copy.shelf else { return nil }
            return shelf == nil || placed.id == shelf?.id ? copy : nil
        }
    }

    func hover(_ copy: RecordCopy, _ hovering: Bool) {
        if hovering { hoveredID = copy.id } else if hoveredID == copy.id { hoveredID = nil }
    }

    /// Where `copy` goes: its alphabetical place among the records of this
    /// shelf, and the two it would stand between. Rack-wide its place in the
    /// whole rack – between two shelves the end of the first; the arrow
    /// offers both. `nil` while no shelf holds records yet.
    func spot(for copy: RecordCopy) -> AlphabeticalPlacement.Spot? {
        guard let shelf else { return AlphabeticalPlacement.spots(for: copy, in: shelves).first }
        let items = PositionService.inShelfOrder(shelf.copies, excluding: copy.id)
        let position = AlphabeticalPlacement.position(for: copy, in: shelf)
        return AlphabeticalPlacement.Spot(shelf: shelf, position: position,
                                          before: position > 1 ? items[position - 2] : nil,
                                          after: position <= items.count ? items[position - 1] : nil)
    }

    /// Where an added `copy` stands now and between which records.
    func placed(_ copy: RecordCopy) -> AlphabeticalPlacement.Spot? {
        guard shelf == nil else { return spot(for: copy) }
        return AlphabeticalPlacement.current(for: copy, in: shelves)
    }

    /// Every place `copy` would stand, for the "i" in its row: in this shelf
    /// when it fits here, else in the rack (two at a shelf boundary).
    func places(for copy: RecordCopy) -> [AlphabeticalPlacement.Spot] {
        guard !isGone(copy) else { return [] }
        if shelf != nil, belongsElsewhere[copy.id] == nil { return spot(for: copy).map { [$0] } ?? [] }
        return AlphabeticalPlacement.spots(for: copy, in: shelves)
    }

    var visible: [RecordCopy] { candidates }

    /// Taken once: the list is a snapshot and must not reorder while records
    /// are added or paused. Records that fit this shelf alphabetically come
    /// first, then the rest – each by artist (rack-wide simply by artist). Paused ones keep their place,
    /// so one found again returns right where it belongs.
    func load(_ context: ModelContext, owner: String?, labels: ShelfLabels) {
        guard !loaded else { return }
        loaded = true
        self.owner = owner
        do {
            var unplaced = FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.shelf == nil })
            // Their artists and titles are read right below (sort keys, list):
            // in one fetch, not one request per release.
            unplaced.relationshipKeyPathsForPrefetching = [\.release]
            let copies = try context.fetch(unplaced)
            let excluded = Set(try context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID))
            let available = ShelfAssignmentPresentation.candidates(copies, owner: owner, excluding: excluded)
            missing = Set(try context.fetch(FetchDescriptor<MissingCopyMark>()).map(\.copyID))
            shelves = Shelf.inUse(try context.fetch(FetchDescriptor<Shelf>()))
            let fits = AlphabeticalPlacement.fittingShelves(for: available, in: shelves)
            for copy in available {
                guard let other = fits[copy.id], !other.isEmpty else { continue }
                if let shelf, other.contains(where: { $0.id == shelf.id }) { continue }
                belongsElsewhere[copy.id] = other.map { labels.prefix(for: $0) + (labels[$0.id] ?? $0.numberText) }
                    .joined(separator: String(localized: " oder "))
            }
            let sorted = ShelfAssignmentPresentation.sortedByArtist(available)
            candidates = shelf == nil ? sorted
                : sorted.filter { belongsElsewhere[$0.id] == nil } + sorted.filter { belongsElsewhere[$0.id] != nil }
        } catch { self.error = ReadError.wrapping(error).reportedMessage() }
    }

    /// The list is a snapshot: a record or the shelf may be gone meanwhile
    /// (reset or restore in the settings window). Reading those would crash.
    private func isGone(_ copy: RecordCopy) -> Bool {
        guard let shelf else { return copy.isDeleted || copy.modelContext == nil }
        return copy.isDeleted || copy.modelContext == nil || shelf.isDeleted || shelf.modelContext == nil
    }

    func add(_ copy: RecordCopy, in context: ModelContext) {
        guard !isGone(copy) else { candidates.removeAll { $0.id == copy.id }; return }
        guard copy.shelf == nil else { candidates.removeAll { $0.id == copy.id }; return }
        // The list is a snapshot; a sync meanwhile may have taken the record
        // out of the collection.
        guard copy.isInCurrentCollection(owner: owner) else {
            candidates.removeAll { $0.id == copy.id }
            error = String(localized: "„\(copy.release?.displayArtist ?? "—") – \(copy.release?.displayTitle ?? "—")“ ist nicht mehr in der Collection.")
            return
        }
        // Rack-wide while no shelf holds records: only the arrow helps.
        guard let spot = spot(for: copy), !spot.shelf.isDeleted, spot.shelf.modelContext != nil else { return }
        do {
            // Its alphabetical place; standing in a shelf now, it turned up after all.
            try PositionService(context: context).move(copy, to: spot.shelf, position: spot.position, found: true)
            missing.remove(copy.id)
            if hoveredID == copy.id { hoveredID = nil }
            candidates.removeAll { $0.id == copy.id }
            lastAdded = copy
            addedCount += 1
            error = nil
        } catch { self.error = error.reportedMessage() }
    }

    /// Marks changed elsewhere (released in the settings): the rows follow.
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

/// "+" in the compartment header: pick records that don't have a shelf yet.
/// Records marked "Vermisst" aren't offered; the settings list them.
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
    /// Every mark in the rack; a record released in the settings returns to the list.
    var missingIDs: Set<UUID> = []
    /// Records the settings list under "Vermisst".
    var missingCount = 0
    /// Off in the settings: no pause buttons, marked records are listed like the rest.
    var missingEnabled = true
    /// Opens the settings on "Vermisst".
    var openMissing: () -> Void = {}
    @Environment(\.modelContext) private var context

    static let listWidth: CGFloat = 460

    var body: some View {
        addColumn
            .frame(width: Self.listWidth, height: 640)
            .onChange(of: missingIDs) { _, ids in session.syncMissing(ids) }
    }

    private var addColumn: some View {
        // Records marked "Vermisst" wait in the settings, not here.
        let items = missingEnabled ? session.visible.filter { !session.missing.contains($0.id) } : session.visible
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(session.isRackWide ? "Einsortieren" : "Platte hinzufügen").font(AppStyle.dialogTitle)
                    Spacer()
                    // Where the paused records went, and the way to them.
                    if missingEnabled && missingCount > 0 {
                        Button(action: openMissing) {
                            Text("\(missingCount) vermisst").monospacedDigit()
                                .font(.callout)
                                .foregroundStyle(AppStyle.errorColor)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .appGlassButton()
                        .help("Vermisste Platten in den Einstellungen ansehen und freigeben")
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                        .transition(.opacity)
                    }
                }
                .animation(AppStyle.standardAnimation, value: missingCount)
                targetCard
                if let error = session.error {
                    AppBanner(message: error, kind: .error)
                        .transition(AppStyle.funnelTransition())
                }
            }
            .padding(.horizontal, AppStyle.pagePadding)
            .padding(.top, AppStyle.pagePadding)
            ZStack {
                ShelfAssignmentTable(controller: session.table, items: items, missing: missingEnabled ? session.missing : [],
                                     missingEnabled: missingEnabled,
                                     rackWide: session.isRackWide,
                                     // The next one by artist that fits here: where to go on.
                                     suggestedID: session.isRackWide ? items.first?.id : items.first { session.belongsElsewhere[$0.id] == nil }?.id,
                                     belongsElsewhere: session.belongsElsewhere,
                                     toggleMissing: { [session, context] copy in session.toggleMissing(copy, in: context) },
                                     hover: { [session] copy, hovering in session.hover(copy, hovering) },
                                     places: places,
                                     findPlace: findPlace) { [session, context] copy in
                    session.add(copy, in: context)
                }
                if session.loaded && items.isEmpty {
                    if pausedCount > 0 {
                        AppEmptyState(String(localized: "Nur noch vermisste Platten"), systemImage: "checkmark.circle",
                                      description: Text("Alle übrigen Platten ohne Fach sind als vermisst markiert. In den Einstellungen unter „Vermisst“ gibst du sie wieder frei."),
                                      actionTitle: String(localized: "Vermisste Platten …"), action: openMissing)
                    } else {
                        AppEmptyState(String(localized: "Alles einsortiert"), systemImage: "checkmark.circle",
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
        AssignmentCard(title: session.isRackWide ? String(localized: "Platten ohne Fach")
                           : rangeLabel.map { String(localized: "Fach „\($0)“") } ?? String(localized: "Dieses Fach"),
                       detail: detail) {
            if session.addedCount > 0 {
                Label(session.isRackWide ? "\(session.addedCount) einsortiert" : "\(session.addedCount) hinzugefügt", systemImage: "checkmark")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(AppStyle.accent)
                    .contentTransition(.numericText())
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .animation(AppStyle.standardAnimation, value: session.addedCount)
        .animation(AppStyle.quickAnimation, value: session.hoveredID)
    }

    private var detail: String {
        if let copy = session.hovered {
            let artist = String(localized: "„\(copy.release?.displayArtist ?? "—")“")
            if session.isRackWide {
                guard let spot = session.spot(for: copy) else { return String(localized: "\(artist) – noch steht keine Platte im Regal") }
                return String(localized: "\(artist) in „\(name(spot.shelf))“ \(place(spot))")
            }
            if let other = session.belongsElsewhere[copy.id] { return String(localized: "\(artist) gehört in „\(other)“ – „i“ zeigt den Platz") }
            if let spot = session.spot(for: copy) { return String(localized: "\(artist) \(place(spot))") }
        }
        if let copy = session.lastAddedHere, let spot = session.placed(copy) {
            let artist = copy.release?.displayArtist ?? "—"
            if session.isRackWide { return String(localized: "Zuletzt „\(artist)“ in „\(name(spot.shelf))“ \(place(spot))") }
            return String(localized: "Zuletzt „\(artist)“ \(place(spot))")
        }
        return String(localized: "Jede Platte kommt an ihre alphabetische Stelle")
    }

    /// "zwischen „Air“ und „Björk“", "vor „Air“", "nach „Zappa“", "als erste Platte".
    private func place(_ spot: AlphabeticalPlacement.Spot) -> String {
        func name(_ copy: RecordCopy) -> String { String(localized: "„\(copy.release?.displayArtist ?? "—")“") }
        switch (spot.before, spot.after) {
        case let (before?, after?): return String(localized: "zwischen \(name(before)) und \(name(after))")
        case let (nil, after?): return String(localized: "ganz vorn, vor \(name(after))")
        case let (before?, nil): return String(localized: "ans Ende, nach \(name(before))")
        case (nil, nil): return String(localized: "als erste Platte")
        }
    }

    /// For the "i" of a row: each fitting shelf with position and neighbours.
    private func places(for copy: RecordCopy) -> [AssignmentPlace] {
        session.places(for: copy).map { spot in
            let between = place(spot)
            return AssignmentPlace(id: spot.shelf.id, shelf: labels.prefix(for: spot.shelf) + name(spot.shelf), position: spot.position,
                                   neighbours: between.prefix(1).uppercased() + between.dropFirst())
        }
    }

    /// Just the compartment: the row below names the cabinet too, and the
    /// card has one line.
    private func name(_ shelf: Shelf) -> String { labels[shelf.id] ?? shelf.numberText }

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
    let rackWide: Bool
    let suggestedID: UUID?
    let belongsElsewhere: [UUID: String]
    let toggleMissing: (RecordCopy) -> Void
    let hover: (RecordCopy, Bool) -> Void
    let places: (RecordCopy) -> [AssignmentPlace]
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
        controller.places = places
        controller.findPlace = findPlace
        controller.belongsElsewhere = belongsElsewhere
        controller.rackWide = rackWide
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
    static let rowHeight = AssignmentRowMetrics.height
    let scrollView = NSScrollView()
    private let table = NSTableView()
    private var items: [RecordCopy] = []
    private var missing: Set<UUID> = []
    private var missingEnabled = true
    private var suggestedID: UUID?
    /// Fixed for a session (see `ShelfAssignmentSession.load`).
    fileprivate var belongsElsewhere: [UUID: String] = [:]
    fileprivate var rackWide = false
    fileprivate var add: (RecordCopy) -> Void = { _ in }
    fileprivate var toggleMissing: (RecordCopy) -> Void = { _ in }
    fileprivate var hover: (RecordCopy, Bool) -> Void = { _, _ in }
    fileprivate var places: (RecordCopy) -> [AssignmentPlace] = { _ in [] }
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
                                         rackWide: rackWide,
                                         toggleMissing: { [weak self] in self?.toggleMissing(copy) },
                                         hover: { [weak self] in self?.hover(copy, $0) },
                                         places: { [weak self] in self?.places(copy) ?? [] },
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

/// The card over the list of "Platte hinzufügen": the shelf the records go to.
struct AssignmentCard<Trailing: View>: View {
    /// Covers in the lists below; the symbol is centered above them.
    static var coverSize: CGFloat { 38 }
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: AppStyle.rowSpacing) {
            // Centered in a column as wide as a cover: sits right above the
            // covers below, and the texts line up with theirs.
            Image(systemName: "square.grid.3x3.fill")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(AppStyle.accent)
                .frame(width: Self.coverSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).lineLimit(1)
                // One line, so long names never grow the card.
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: AppStyle.itemSpacing)
            trailing
        }
        .padding(.horizontal, AppStyle.rowSpacing)
        .padding(.vertical, AppStyle.rowSpacing)
        .appCardSurface(cornerRadius: 16)
        // The surface reaches out past the column, so the symbol and texts
        // line up with the title above and the rows below.
        .padding(.horizontal, -AppStyle.rowSpacing)
    }
}

/// Rows of "Platte hinzufügen" and the shelf search: the same height and cover.
enum AssignmentRowMetrics {
    static let height: CGFloat = 52
}

private struct ShelfAssignmentRow: View {
    static let coverSize = AssignmentCard<EmptyView>.coverSize
    let copy: RecordCopy
    /// Marked "Vermisst": shown paused, still addable once it turns up.
    let missing: Bool
    /// Off in the settings: no pause button.
    let missingEnabled: Bool
    /// The next one to add by artist: lightly marked.
    let suggested: Bool
    /// The shelf it fits alphabetically, when that isn't this one.
    let belongsIn: String?
    /// "Einsortieren": no shelf of its own, each row goes to `belongsIn`.
    let rackWide: Bool
    let toggleMissing: () -> Void
    let hover: (Bool) -> Void
    /// Where it would stand, read when the "i" is clicked.
    let places: () -> [AssignmentPlace]
    let findPlace: () -> Void
    let add: () -> Void
    @State private var hovering = false
    /// The popover of the "i": where the record would stand.
    @State private var showsPlace = false

    var body: some View {
        let artist = copy.release?.displayArtist ?? "—"
        let title = copy.release?.displayTitle ?? "—"
        HStack(spacing: AppStyle.rowSpacing) {
            CoverView(url: copy.release?.coverURL, size: Self.coverSize)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(artist).font(.callout.weight(.medium)).lineLimit(1)
                    if suggested {
                        StatusTag(text: String(localized: "Als Nächstes"), color: AppStyle.accent)
                            .help(rackWide ? String(localized: "Nach Interpret die nächste Platte") : String(localized: "Nach Interpret die nächste Platte für dieses Fach"))
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
                            .help(rackWide ? String(localized: "Passt alphabetisch in „\(belongsIn)“") : String(localized: "Passt alphabetisch in „\(belongsIn)“, nicht in dieses Fach"))
                    }
                }
            }
            .opacity(missing ? 0.55 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(artist) – \(title)")
            Spacer(minLength: AppStyle.itemSpacing)
            if missingEnabled {
                RowSymbolButton(systemImage: missing ? "pause.circle.fill" : "pause.circle",
                                color: missing ? AppStyle.errorColor : .secondary,
                                visible: hovering || missing, action: toggleMissing)
                    .help(missing ? "Wieder gefunden" : "Vermisst – vorerst zurückstellen")
                    .accessibilityLabel(missing ? String(localized: "\(artist) – \(title) wieder gefunden") : String(localized: "\(artist) – \(title) als vermisst markieren"))
            }
            // Where it would stand once sorted in; stays while its popover is open.
            RowSymbolButton(systemImage: "info.circle", color: .secondary, visible: hovering || showsPlace) { showsPlace = true }
                .help("Zeigt, wo sie einsortiert stehen würde")
                .accessibilityLabel("\(artist) – \(title): Platz im Regal")
                .popover(isPresented: $showsPlace, arrowEdge: .bottom) {
                    AssignmentPlacePopover(artist: artist, title: title, places: places()) {
                        showsPlace = false
                        findPlace()
                    }
                }
            if rackWide {
                if let belongsIn {
                    RowSymbolButton(systemImage: "plus.circle", color: AppStyle.accent, visible: hovering, action: add)
                        .help("An ihrer alphabetischen Stelle in „\(belongsIn)“ einsortieren")
                        .accessibilityLabel("\(artist) – \(title) in „\(belongsIn)“ einsortieren")
                }
            } else {
                // The main action: accent in the glyph, like chosen options elsewhere.
                RowSymbolButton(systemImage: "plus.circle", color: AppStyle.accent, visible: hovering, action: add)
                    .help(belongsIn == nil ? String(localized: "An ihrer alphabetischen Stelle ins Fach hinzufügen") : String(localized: "Trotzdem in dieses Fach hinzufügen"))
                    .accessibilityLabel("\(artist) – \(title) ins Fach hinzufügen")
            }
        }
        .padding(.horizontal, AppStyle.pagePadding)
        .frame(height: ShelfAssignmentTableController.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The suggested row: a faint accent wash behind it.
        .background {
            if suggested {
                RoundedRectangle(cornerRadius: AppStyle.cardRadius)
                    .fill(AppStyle.accent.opacity(0.07))
                    .padding(.horizontal, AppStyle.pagePadding - 10)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0; hover($0) }
        .animation(AppStyle.fadeAnimation, value: hovering)
    }
}

/// A row action as a bare symbol: only shown while the pointer is over the row.
private struct RowSymbolButton: View {
    let systemImage: String
    let color: Color
    let visible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
    }
}

/// A place a record without a shelf would stand, as the "i" of its row tells it.
struct AssignmentPlace: Identifiable {
    /// The shelf's ID: one entry per fitting shelf.
    let id: UUID
    let shelf: String
    let position: Int
    /// "Zwischen „Air“ und „Björk“".
    let neighbours: String
}

/// The popover of a row's "i": the shelf and position the record would get
/// (both, when it falls between two shelves) and the way to see it in the rack.
private struct AssignmentPlacePopover: View {
    let artist: String
    let title: String
    let places: [AssignmentPlace]
    let show: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Hier würde sie stehen").font(.callout.weight(.medium))
                Text("\(artist) – \(title)").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if places.isEmpty {
                Text("Es steht noch keine Platte im Regal, an der sie sich ausrichten könnte.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    if index > 0 { Text("oder genauso gut").font(.caption).foregroundStyle(.tertiary) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Fach „\(place.shelf)“ · Position \(place.position)").font(.callout).monospacedDigit()
                        Text(place.neighbours).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("Im Regal zeigen", action: show)
                    .appLinkButton()
                    .font(.callout)
            }
        }
        .padding(AppStyle.cardPadding)
        .frame(width: 300, alignment: .leading)
        .appPopoverSurface()
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

    /// Artist, then title (`SortingService.sorted`: keys built once per
    /// record, ties by ID so equal copies keep their order between updates).
    static func sortedByArtist(_ copies: [RecordCopy]) -> [RecordCopy] {
        SortingService.sorted(copies)
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
    /// Closes the panel once the new order is saved: left open, it would
    /// only say "Alles in Ordnung", and the next click on the shelf page
    /// would merely close it instead of reaching a compartment.
    let close: () -> Void
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
                Text("\(rangeLabel.map { String(localized: "Fach „\($0)“") } ?? String(localized: "Dieses Fach")) · \(AppStyle.records(copies.count)) · Plätze von links gezählt")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: AppStyle.rowSpacing) {
                    Text("Nach Interpret, bei gleichem Interpreten nach").font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    GlassSegmentedPicker(selection: $order, options: ShelfSecondaryOrder.allCases, small: true) { Text($0.title) }
                        .accessibilityLabel("Bei gleichem Interpreten nach")
                }
                // Said where it arises instead of next to the button.
                if order != savedOrder && !steps.isEmpty {
                    Text("Übernimmt „\(order.title)“ auch für Platzsuche und Hinzufügen in allen Fächern.")
                        .font(.caption).foregroundStyle(AppStyle.accent)
                        .transition(.opacity)
                }
            }
            if steps.isEmpty {
                inOrder(count: copies.count)
            } else {
                summary(steps)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        let current = steps.first { !done.contains($0.id) }?.id
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            SortStepRow(number: index + 1, step: step, done: done.contains(step.id), current: step.id == current) {
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
        .onChange(of: order) { done = []; logCheck() }
        .onAppear {
            logCheck()
            #if DEBUG
            // Screenshots: --preview-sortcheck-done=N ticks off the first N moves.
            if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-sortcheck-done=") }),
               let count = Int(raw.dropFirst("--preview-sortcheck-done=".count)) {
                done = Set(steps.prefix(count).map(\.id))
            }
            #endif
        }
    }

    private func inOrder(count: Int) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack(spacing: AppStyle.rowSpacing) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(AppStyle.successColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Alles in Ordnung").font(.headline)
                    Text(count < 2 ? String(localized: "Zu wenige Platten, um etwas zu prüfen.") : String(localized: "Alle \(count) Platten stehen in der richtigen Reihenfolge."))
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
                    SecondaryButton(title: String(localized: "„\(order.title)“ übernehmen")) {
                        AppLog.info("Regal", "Bei gleichem Interpreten jetzt nach \(order.title) statt \(savedOrder.title) (aus „Sortierung prüfen“)")
                        savedOrder = order
                    }
                }
            }
        }
    }

    /// What is left to move: count, progress, and once everything is ticked
    /// off "Alles umgestellt" – then the button below turns into the main action.
    private func summary(_ steps: [ShelfSortCheck.Step]) -> some View {
        let finished = steps.filter { done.contains($0.id) }.count
        let complete = finished == steps.count
        return VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack(spacing: AppStyle.rowSpacing) {
                Image(systemName: complete ? "checkmark.circle.fill" : "arrow.left.arrow.right")
                    .font(.system(size: 22))
                    .foregroundStyle(complete ? AppStyle.successColor : AppStyle.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26)
                Text(complete ? String(localized: "Alles umgestellt")
                     : steps.count == 1 ? String(localized: "1 Platte umstellen") : String(localized: "\(steps.count) Platten umstellen"))
                    .font(.headline)
                Spacer(minLength: AppStyle.itemSpacing)
                Text("\(finished) von \(steps.count)")
                    .font(.callout.weight(.medium)).monospacedDigit()
                    .foregroundStyle(complete ? AppStyle.successColor : AppStyle.accent)
                    .contentTransition(.numericText())
            }
            SortProgressBar(fraction: Double(finished) / Double(max(steps.count, 1)), complete: complete)
        }
        .padding(.horizontal, AppStyle.cardPadding)
        .padding(.vertical, AppStyle.rowSpacing)
        .accentGlassCard()
        .animation(AppStyle.standardAnimation, value: finished)
    }

    /// Only the button: a quiet one while moves are open, the main action
    /// once all are ticked off. Saving early stays possible.
    private func footer(_ steps: [ShelfSortCheck.Step]) -> some View {
        let complete = steps.allSatisfy { done.contains($0.id) }
        return HStack {
            Spacer(minLength: 0)
            if complete {
                PrimaryButton(title: String(localized: "Reihenfolge übernehmen")) { apply() }
            } else {
                SecondaryButton(title: String(localized: "Reihenfolge übernehmen")) { apply() }
            }
        }
        .animation(AppStyle.standardAnimation, value: complete)
    }

    /// For the protocol: which compartment was checked, by what, and the result.
    private func logCheck() {
        guard !gone else { return }
        let copies = PositionService.inShelfOrder(shelf.copies.filter { !$0.isDeleted && $0.modelContext != nil })
        let count = ShelfSortCheck.steps(copies, by: order).count
        AppLog.info("Regal", "Sortierung geprüft: \(PositionService.name(shelf)), Interpret, dann \(order.title) – "
                    + (count == 0 ? String(localized: "alles in Ordnung") : String(localized: "\(count) von \(copies.count) Platten umzustellen")))
    }

    private func apply() {
        guard !gone else { return }
        do {
            try PositionService(context: context).sortAlphabetically(shelf, by: order)
            if savedOrder != order {
                AppLog.info("Regal", "Bei gleichem Interpreten jetzt nach \(order.title) statt \(savedOrder.title) (aus „Sortierung prüfen“)")
            }
            savedOrder = order
            done = []
            error = nil
            close()
        } catch { self.error = error.reportedMessage() }
    }
}

/// One move: the record with its cover and where it stands now, then where
/// it goes – behind the record shown (or at the very front, before it).
private struct SortStepRow: View {
    let number: Int
    let step: ShelfSortCheck.Step
    let done: Bool
    /// The next open move: framed like every selection (gold in Klassisch).
    let current: Bool
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
                    // Where it goes is what matters at the shelf: in the text's
                    // own color, only the current place muted.
                    HStack(spacing: 5) {
                        Text("Platz \(step.position)").monospacedDigit().foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        if let neighbour = step.before ?? step.after {
                            CoverView(url: neighbour.release?.coverURL, size: 16)
                            Text(target(neighbour)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .opacity(done ? 0.45 : 1)
            .contentShape(Rectangle())
            .appHoverable(hovering && !current, cornerRadius: 8)
            .background {
                if current {
                    RoundedRectangle(cornerRadius: 8).fill(AppStyle.selectedBackground)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppStyle.selectedBorder, lineWidth: 1.5))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: done)
        .animation(AppStyle.standardAnimation, value: current)
        .help(done ? "Doch noch nicht umgestellt" : "Als umgestellt abhaken")
    }

    /// "hinter **Artist** – Title" (or "ganz vorn, vor …"): the artist in bold.
    private func target(_ neighbour: RecordCopy) -> AttributedString {
        var artist = AttributedString(neighbour.release?.displayArtist ?? "—")
        artist.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString((step.before == nil ? String(localized: "ganz vorn, vor") : String(localized: "hinter")) + " ")
            + artist + AttributedString(" – \(neighbour.release?.displayTitle ?? "—")")
    }
}

/// Thin bar under the count: the accent filling up, green when complete.
private struct SortProgressBar: View {
    let fraction: Double
    let complete: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(AppStyle.borderColor)
                Capsule().fill(complete ? AppStyle.successColor : AppStyle.accent)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4)
    }
}
