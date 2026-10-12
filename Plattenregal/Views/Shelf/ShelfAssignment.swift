import SwiftUI
import SwiftData

/// One opening of the "Platte hinzufügen" sheet.
///
/// SwiftUI may rebuild the sheet's content at any time (e.g. when the first
/// save refreshes the shelf page behind it), so nothing that matters lives
/// in the view: the snapshot of candidates and the additions live here.
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
    /// Candidates marked "Gesucht": left out of the list until they are
    /// released in the settings.
    private(set) var missing: Set<UUID> = []
    /// For candidates that belong in another shelf alphabetically: its name,
    /// shown in their row ("gehört in „K – Ma“"). Rack-wide: every
    /// candidate's shelf.
    private(set) var belongsElsewhere: [UUID: String] = [:]
    /// The row under the pointer; the target card tells where it would go.
    private(set) var hoveredID: UUID?
    var error: String?

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

    /// Where `copy` would stand, shown on its tile: in this shelf when it
    /// fits here, else in the rack (the first of two at a shelf boundary).
    /// Kept until a record is added – every tile asks on each redraw, and
    /// finding a place walks the rack.
    func place(for copy: RecordCopy) -> AlphabeticalPlacement.Spot? {
        if let known = placeCache[copy.id] { return known }
        guard !isGone(copy) else { return nil }
        let spot = shelf != nil && belongsElsewhere[copy.id] == nil ? spot(for: copy)
            : AlphabeticalPlacement.spots(for: copy, in: shelves).first
        placeCache[copy.id] = .some(spot)
        return spot
    }
    @ObservationIgnored private var placeCache: [UUID: AlphabeticalPlacement.Spot?] = [:]

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
            // Positions behind it moved on.
            placeCache = [:]
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
/// Records marked "Gesucht" aren't offered; the settings list them.
/// A glass panel over the page, closed by a click beside it or Esc: the
/// target compartment on a glass card, below it one row per record – the
/// cover as large as in the compartment's grid, beside it across the panel
/// the record and, larger, where it goes. A click adds it. No title – the card says what
/// the panel is for. All state is in the session.
struct ShelfAssignmentView: View {
    @Bindable var session: ShelfAssignmentSession
    let owner: String?
    let rangeLabel: String?
    /// All shelf names, for the rows that belong elsewhere.
    let labels: ShelfLabels
    /// Every mark in the rack; a record released in the settings returns to the list.
    var missingIDs: Set<UUID> = []
    /// Off in the settings: no pause buttons, marked records are listed like the rest.
    var missingEnabled = true
    /// Opens the settings on "Listen".
    var openMissing: () -> Void = {}
    @Environment(\.modelContext) private var context

    static let listWidth: CGFloat = 660

    var body: some View {
        addColumn
            .frame(width: Self.listWidth, height: 640)
            .onChange(of: missingIDs) { _, ids in session.syncMissing(ids) }
    }

    private var addColumn: some View {
        // Records marked "Gesucht" wait in the settings, not here.
        let items = missingEnabled ? session.visible.filter { !session.missing.contains($0.id) } : session.visible
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                targetCard
                if let error = session.error {
                    AppBanner(message: error, kind: .error)
                        .transition(AppStyle.funnelTransition())
                }
            }
            .padding(.horizontal, AppStyle.pagePadding)
            .padding(.top, AppStyle.pagePadding)
            ZStack {
                ShelfAssignmentGrid(items: items, missingEnabled: missingEnabled,
                                    rackWide: session.isRackWide,
                                    // The next one by artist that fits here: where to go on.
                                    suggestedID: session.isRackWide ? items.first?.id : items.first { session.belongsElsewhere[$0.id] == nil }?.id,
                                    belongsElsewhere: session.belongsElsewhere,
                                    toggleMissing: { [session, context] copy in session.toggleMissing(copy, in: context) },
                                    hover: { [session] copy, hovering in session.hover(copy, hovering) },
                                    location: location) { [session, context] copy in
                    session.add(copy, in: context)
                }
                if session.loaded && items.isEmpty {
                    if pausedCount > 0 {
                        AppEmptyState(String(localized: "Nur noch gesuchte Platten"), systemImage: "checkmark.circle",
                                      description: Text("Alle übrigen noch nicht einsortierten Platten stehen auf der Suchliste. In den Einstellungen unter „Listen“ markierst du sie als gefunden."),
                                      actionTitle: String(localized: "Suchliste …"), action: openMissing)
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
        AssignmentCard(title: session.isRackWide ? String(localized: "Noch nicht einsortiert")
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
            if let other = session.belongsElsewhere[copy.id] { return String(localized: "\(artist) gehört in „\(other)“") }
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

    /// For a record's row: the compartment it goes to, the position there
    /// and the records it would stand between.
    private func location(for copy: RecordCopy) -> AssignmentLocation? {
        session.place(for: copy).map { spot in
            AssignmentLocation(shelf: labels.prefix(for: spot.shelf) + name(spot.shelf), position: spot.position, neighbours: place(spot))
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

/// Where a record without a shelf would stand, as its row tells it.
struct AssignmentLocation {
    /// Cabinet (when there are several) and compartment.
    let shelf: String
    let position: Int
    /// "zwischen „Air“ und „Björk“".
    let neighbours: String
}

/// The candidates, one row each. An added (or paused) record fades out and
/// the rest move up, so the next one lands under the pointer.
private struct ShelfAssignmentGrid: View {
    let items: [RecordCopy]
    let missingEnabled: Bool
    let rackWide: Bool
    let suggestedID: UUID?
    let belongsElsewhere: [UUID: String]
    let toggleMissing: (RecordCopy) -> Void
    let hover: (RecordCopy, Bool) -> Void
    /// Where each record would stand (see `ShelfAssignmentSession.place`).
    let location: (RecordCopy) -> AssignmentLocation?
    let add: (RecordCopy) -> Void
    /// The row whose right-click menu is open, and where it was clicked.
    @State private var menuFor: (id: UUID, anchor: UnitPoint)?
    @State private var clicks = GridSecondaryClicks<UUID>()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CoverGrid.spacing) {
                ForEach(items) { copy in
                    ShelfAssignmentRow(copy: copy, location: location(copy),
                                       suggested: copy.id == suggestedID,
                                       elsewhere: !rackWide && belongsElsewhere[copy.id] != nil,
                                       rackWide: rackWide,
                                       hover: { hover(copy, $0) }) { add(copy) }
                        .gridSecondaryClickCell(copy.id, in: clicks)
                        .popover(isPresented: Binding(get: { menuFor?.id == copy.id }, set: { if !$0, menuFor?.id == copy.id { menuFor = nil } }),
                                 attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
                            AppMenu(dismiss: { menuFor = nil }) {
                                Button(rackWide ? "Einsortieren" : "Zum Fach hinzufügen") { add(copy) }
                                if missingEnabled {
                                    Button("Auf die Suchliste setzen") { toggleMissing(copy) }
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .gridSecondaryClickGrid(clicks)
            .padding(.horizontal, AppStyle.pagePadding)
            .padding(.top, AppStyle.rowSpacing)
            .padding(.bottom, AppStyle.pagePadding)
            .animation(AppStyle.layoutAnimation, value: items.map(\.id))
        }
        .onGridSecondaryClick(clicks) { id, point in menuFor = (id, point) }
        .scrollIndicators(.automatic)
    }
}

/// The card over the covers of "Platte hinzufügen": the shelf the records go to.
struct AssignmentCard<Trailing: View>: View {
    /// Covers in the lists below; the symbol is centered above them.
    static var coverSize: CGFloat { 38 }
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: AppStyle.rowSpacing) {
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
        // Flush with the outer covers of the grid below.
        .appCardSurface(cornerRadius: 16)
    }
}

/// Rows of the shelf search and the "Gesucht" list: the same height and cover.
enum AssignmentRowMetrics {
    static let height: CGFloat = 52
}

/// One candidate across the panel: the cover as large as in a compartment's
/// grid, beside it the record's caption and – larger – where it goes:
/// compartment, position and the records it would stand between. A click
/// adds it; a right-click offers the search list.
private struct ShelfAssignmentRow: View {
    /// About the width of a cover in the compartment's grid.
    static let coverSize: CGFloat = 132
    let copy: RecordCopy
    /// Where it would stand in the compartment it belongs to.
    let location: AssignmentLocation?
    /// The next one to add by artist.
    let suggested: Bool
    /// "Platte hinzufügen": belongs in another shelf than the open one.
    let elsewhere: Bool
    let rackWide: Bool
    let hover: (Bool) -> Void
    let add: () -> Void
    @State private var hovering = false

    var body: some View {
        let artist = copy.release?.displayArtist ?? "—"
        let title = copy.release?.displayTitle ?? "—"
        Button(action: add) {
            HStack(alignment: .center, spacing: AppStyle.pagePadding - 4) {
                CoverView(url: copy.release?.coverURL, size: Self.coverSize)
                    .atelierRecordSleeve()
                VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                    VStack(alignment: .leading, spacing: 4) {
                        // The same caption as in the compartment, Collection and Wantlist.
                        RecordCaption(release: copy.release)
                        if suggested { StatusTag(text: String(localized: "Als Nächstes"), color: AppStyle.accent) }
                    }
                    place
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .contentShape(Rectangle())
            .appHoverable(hovering, cornerRadius: AppStyle.cardRadius + 8)
        }
        .buttonStyle(.plain)
        // The hover surface reaches out, so covers stay flush with the card above.
        .padding(-8)
        .help(help)
        .accessibilityLabel(rackWide ? String(localized: "\(artist) – \(title) einsortieren") : String(localized: "\(artist) – \(title) ins Fach hinzufügen"))
        .onHover { hovering = $0; hover($0) }
    }

    /// Where it goes, the largest text of the row.
    @ViewBuilder private var place: some View {
        if let location {
            VStack(alignment: .leading, spacing: 2) {
                Text(elsewhere ? String(localized: "Gehört in „\(location.shelf)“") : location.shelf)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(elsewhere ? AnyShapeStyle(.secondary) : AnyShapeStyle(AppStyle.accent))
                Text("Position \(location.position) · \(location.neighbours)")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Noch steht keine Platte im Regal, an der sie sich ausrichten könnte.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var help: String {
        if rackWide {
            return location == nil ? "" : String(localized: "Klick: hier einsortieren. Rechtsklick: weitere Aktionen.")
        }
        if elsewhere { return String(localized: "Klick: trotzdem in dieses Fach hinzufügen. Rechtsklick: weitere Aktionen.") }
        return String(localized: "Klick: an ihrer alphabetischen Stelle ins Fach hinzufügen. Rechtsklick: weitere Aktionen.")
    }
}

enum ShelfAssignmentPresentation {
    /// Only copies without a shelf that aren't marked "Ohne Regalplatz". Moving
    /// between shelves happens by taking a copy out (trash) and adding it
    /// here. Reads the copy → shelf side of the relationship, which
    /// PositionService writes directly; the inverse `shelf.copies` can lag
    /// one update cycle behind.
    static func candidates(_ copies: [RecordCopy], owner: String?, excluding excluded: Set<UUID>) -> [RecordCopy] {
        copies.filter { isCandidate($0, owner: owner, excluding: excluded) }
    }

    /// Without a shelf, in the current collection and not "Ohne Regalplatz".
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
