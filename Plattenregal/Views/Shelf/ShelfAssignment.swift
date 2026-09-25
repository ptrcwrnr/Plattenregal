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
    /// Candidates marked "Vermisst": they stay in the list, paused.
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
struct ShelfAssignmentView: View {
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
                        Text(" · \(pausedCount) vermisst").foregroundStyle(AppStyle.errorColor)
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
    /// Marked "Vermisst": shown paused, still addable once it turns up.
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
            .help(missing ? "Wieder gefunden" : "Vermisst – vorerst zurückstellen")
            .accessibilityLabel(missing ? "\(artist) – \(title) wieder gefunden" : "\(artist) – \(title) als vermisst markieren")
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
