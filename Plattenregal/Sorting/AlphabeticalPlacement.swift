import Foundation

enum AlphabeticalPlacement {
    /// A place in the rack a record fits alphabetically: the shelf, the
    /// 1-based position and the records it would stand between. `before` and
    /// `after` may sit in the neighbouring shelf when the spot is at an edge.
    struct Spot: Identifiable {
        let shelf: Shelf
        let position: Int
        let before: RecordCopy?
        let after: RecordCopy?
        var id: UUID { shelf.id }
    }

    /// Kept per record (see `ShelfSortKeys`): every placement walks all
    /// placed records, and reading their releases again after a save makes
    /// SwiftData fetch them one by one ("Platte hinzufügen": ~70 ms for 2 000).
    static func key(_ copy: RecordCopy) -> String { ShelfSortKeys.key(copy, by: .current) }

    /// Where `copy` belongs inside `shelf` by artist, then title — the same
    /// order the shelves are sorted by. 1-based; after the last record if it
    /// sorts behind everything already there.
    static func position(for copy: RecordCopy, in shelf: Shelf) -> Int {
        let items = ordered(shelf, excluding: copy.id)
        let target = key(copy)
        let index = items.firstIndex { key($0).localizedStandardCompare(target) == .orderedDescending } ?? items.count
        return index + 1
    }

    /// Where `copy` belongs in the whole rack. Shelves follow each other in
    /// the alphabetical run of their contents (as in `ShelfRangeLabels`), not
    /// by their place in the furniture. Usually one spot; two when the record
    /// falls between two shelves — the end of the one and the start of the
    /// next fit equally, and only the person at the shelf can tell which has
    /// room. Empty when no shelf holds records yet.
    static func spots(for copy: RecordCopy, in shelves: [Shelf]) -> [Spot] {
        // Usually a record without a shelf: then no shelf holds it, and the
        // records of all shelves needn't be checked against it.
        let excluded = copy.shelf == nil ? nil : copy.id
        let runs = runs(of: shelves, excluding: excluded)
        guard let lastRun = runs.last else { return [] }
        // Only the one or two shelves the record ends up beside are put in order.
        func items(_ run: Run) -> [RecordCopy] { ordered(run.shelf, excluding: excluded) }

        let target = key(copy)
        guard let index = runs.firstIndex(where: { target.localizedStandardCompare($0.last) != .orderedDescending }) else {
            let last = items(lastRun)
            return [Spot(shelf: lastRun.shelf, position: last.count + 1, before: last.last, after: nil)]
        }
        let run = runs[index]
        let runItems = items(run)
        if target.localizedStandardCompare(run.first) == .orderedAscending {
            let previous = index > 0 ? items(runs[index - 1]) : []
            let start = Spot(shelf: run.shelf, position: 1, before: previous.last, after: runItems.first)
            guard index > 0 else { return [start] }
            let end = Spot(shelf: runs[index - 1].shelf, position: previous.count + 1, before: previous.last, after: runItems.first)
            return [end, start]
        }
        let position = position(for: copy, in: run.shelf)
        return [Spot(
            shelf: run.shelf,
            position: position,
            before: position > 1 ? runItems[position - 2] : nil,
            after: position <= runItems.count ? runItems[position - 1] : nil
        )]
    }

    /// Which of `spots(for:in:)` to take when nobody chose. Two spots only at
    /// a shelf boundary, where the end of one shelf and the start of the next
    /// fit equally; they may stand in two cabinets (KALLAX ends with „V“,
    /// EKET starts with „Y“). Then, in this order: the side where the same
    /// artist already stands next to it, the compartment that is open, a
    /// compartment of the cabinet shown, else the first – before, every
    /// boundary went to the earlier shelf, even with the other cabinet open.
    static func preferredIndex(_ spots: [Spot], for copy: RecordCopy, openShelf: UUID? = nil, cabinet: UUID? = nil) -> Int {
        guard spots.count > 1 else { return 0 }
        // `[end of the earlier shelf, start of the later one]`; both name the
        // same two records: `before` ends the earlier shelf, `after` starts the later.
        let artist = artistKey(copy)
        func sameArtist(_ neighbour: RecordCopy?) -> Bool {
            neighbour.map { artistKey($0).localizedStandardCompare(artist) == .orderedSame } ?? false
        }
        let besideBefore = sameArtist(spots[0].before), besideAfter = sameArtist(spots[0].after)
        if besideAfter && !besideBefore { return 1 }
        if besideBefore && !besideAfter { return 0 }
        if let openShelf, let index = spots.firstIndex(where: { $0.shelf.id == openShelf }) { return index }
        if let cabinet, let index = spots.firstIndex(where: { $0.shelf.cabinet?.id == cabinet }) { return index }
        return 0
    }

    /// The artist part of the sort key (see `SortingService.sortKey`).
    private static func artistKey(_ copy: RecordCopy) -> Substring {
        let key = key(copy)
        return key.prefix { $0 != "\t" }
    }

    /// The shelves each of `copies` (without a shelf) fits alphabetically,
    /// by copy ID – the shelves of `spots`, for many records in one go.
    static func fittingShelves(for copies: [RecordCopy], in shelves: [Shelf]) -> [UUID: [Shelf]] {
        let runs = runs(of: shelves, excluding: nil)
        guard let lastRun = runs.last else { return [:] }
        var result: [UUID: [Shelf]] = [:]
        for copy in copies {
            let target = key(copy)
            guard let index = runs.firstIndex(where: { target.localizedStandardCompare($0.last) != .orderedDescending }) else {
                result[copy.id] = [lastRun.shelf]
                continue
            }
            let run = runs[index]
            // Between two shelves: the end of the one fits as well as the start of the next.
            if index > 0 && target.localizedStandardCompare(run.first) == .orderedAscending {
                result[copy.id] = [runs[index - 1].shelf, run.shelf]
            } else {
                result[copy.id] = [run.shelf]
            }
        }
        return result
    }

    /// Where a placed `copy` stands right now and between which records — to
    /// put it back after taking it out. At either end of its shelf the
    /// neighbour comes from the shelf before or after it in the alphabetical
    /// run. `nil` for a copy without a shelf.
    static func current(for copy: RecordCopy, in shelves: [Shelf]) -> Spot? {
        guard let shelf = copy.shelf else { return nil }
        let items = ordered(shelf, excluding: copy.id)
        let index = min(max(copy.positionInShelf - 1, 0), items.count)
        // The copy itself counts here, so a shelf holding only this copy keeps its place in the run.
        let runs = runs(of: shelves, excluding: nil)
        let runIndex = runs.firstIndex { $0.shelf.id == shelf.id }
        let previous = runIndex.flatMap { $0 > 0 ? ordered(runs[$0 - 1].shelf, excluding: nil).last : nil }
        let next = runIndex.flatMap { $0 + 1 < runs.count ? ordered(runs[$0 + 1].shelf, excluding: nil).first : nil }
        return Spot(
            shelf: shelf,
            position: index + 1,
            before: index > 0 ? items[index - 1] : previous,
            after: index < items.count ? items[index] : next
        )
    }

    private struct Run { let shelf: Shelf; let first: String; let last: String }

    /// Occupied, unreserved shelves in the alphabetical order of their
    /// contents. Only their ends: callers put just the shelves they need in
    /// order – sorting every shelf was most of opening "Platte hinzufügen".
    private static func runs(of shelves: [Shelf], excluding id: UUID?) -> [Run] {
        shelves.compactMap { shelf -> Run? in
            guard !shelf.isReserved else { return nil }
            let copies = id.map { id in shelf.copies.filter { $0.id != id } } ?? shelf.copies
            // Only the ends matter: one pass instead of sorting every key.
            let keys = copies.map(key)
            guard let first = keys.min(by: ascending), let last = keys.max(by: ascending) else { return nil }
            return Run(shelf: shelf, first: first, last: last)
        }
        // Same start in two shelves (one artist and title across both): the
        // end decides, then the place in the rack, so the run never flips.
        .sorted { a, b in
            let first = a.first.localizedStandardCompare(b.first)
            if first != .orderedSame { return first == .orderedAscending }
            let last = a.last.localizedStandardCompare(b.last)
            if last != .orderedSame { return last == .orderedAscending }
            return a.shelf.readingOrder.lexicographicallyPrecedes(b.shelf.readingOrder)
        }
    }

    private static func ordered(_ shelf: Shelf, excluding id: UUID?) -> [RecordCopy] {
        PositionService.inShelfOrder(shelf.copies, excluding: id)
    }

    static func ascending(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
}
