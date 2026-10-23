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
    /// Rack-wide: where the page stands – the open compartment and the
    /// cabinet shown. At a shelf boundary they decide which of the two
    /// fitting shelves a record goes to (see `AlphabeticalPlacement.preferredIndex`).
    private let openShelf: UUID?
    private let shownCabinet: UUID?

    init(shelf: Shelf?, openShelf: UUID? = nil, shownCabinet: UUID? = nil) {
        self.shelf = shelf
        self.openShelf = openShelf
        self.shownCabinet = shownCabinet
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
    /// whole rack – between two shelves the end of the first. `nil` while no
    /// shelf holds records yet.
    func spot(for copy: RecordCopy) -> AlphabeticalPlacement.Spot? {
        guard let shelf else { return rackSpot(for: copy) }
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
        let spot = shelf != nil && belongsElsewhere[copy.id] == nil ? spot(for: copy) : rackSpot(for: copy)
        placeCache[copy.id] = .some(spot)
        return spot
    }
    /// Its place in the whole rack; at a shelf boundary the preferred side.
    private func rackSpot(for copy: RecordCopy) -> AlphabeticalPlacement.Spot? {
        let spots = AlphabeticalPlacement.spots(for: copy, in: shelves)
        guard !spots.isEmpty else { return nil }
        return spots[AlphabeticalPlacement.preferredIndex(spots, for: copy, openShelf: openShelf, cabinet: shownCabinet)]
    }
    @ObservationIgnored private var placeCache: [UUID: AlphabeticalPlacement.Spot?] = [:]

    var visible: [RecordCopy] { candidates }

    /// Taken once: the list is a snapshot and must not reorder while records
    /// are added or put on the "Gesucht" list. Records that fit this shelf
    /// alphabetically come first, then the rest – each by artist (rack-wide
    /// simply by artist). Marked ones keep their place, so one found again
    /// returns right where it belongs.
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
        // Rack-wide while no shelf holds records: its row says to start with
        // "+" at a compartment.
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

    /// Right-click menu: not found while sorting in ("Gesucht"), or found again.
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
