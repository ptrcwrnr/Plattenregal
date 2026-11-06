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
    static func position(for copy: RecordCopy, in shelf: Shelf) -> Int { spot(for: copy, in: shelf).position }

    /// Its place in `shelf` and the records it would stand between there; at
    /// either end of the shelf `previous` or `next` (from the shelves around it).
    static func spot(for copy: RecordCopy, in shelf: Shelf, previous: RecordCopy? = nil, next: RecordCopy? = nil) -> Spot {
        let items = ordered(shelf, excluding: copy.id)
        let target = key(copy)
        let index = items.firstIndex { key($0).localizedStandardCompare(target) == .orderedDescending } ?? items.count
        return Spot(shelf: shelf, position: index + 1,
                    before: index > 0 ? items[index - 1] : previous,
                    after: index < items.count ? items[index] : next)
    }

    /// Where `copy` belongs in one cabinet: the one shown (`cabinet`, see
    /// `sortingShelves`). Each cabinet is an alphabet of its own – with the
    /// whole rack as one run, a compartment holding records from A to Z (a
    /// small second cabinet) covered every name and took every new record.
    /// Inside the cabinet the compartment where the record fits closest
    /// (`fits`): usually one spot; two when the record falls between two
    /// compartments — the end of the one and the start of the next fit
    /// equally, and only the person at the shelf can tell which has room.
    /// Empty when no compartment holds records yet.
    static func spots(for copy: RecordCopy, in shelves: [Shelf], cabinet: UUID? = nil) -> [Spot] {
        // Usually a record without a shelf; a placed one leaves itself out of its own.
        let excluded = copy.shelf == nil ? nil : copy
        let index = index(of: sortingShelves(shelves, cabinet: cabinet, excluding: excluded), excluding: excluded)
        let target = key(copy)
        // The records just before and after it in the whole cabinet: the
        // neighbours at the edge of a compartment.
        let split = upperBound(index.keys, target)
        let previous = split > 0 ? index.copies[split - 1] : nil
        let next = split < index.copies.count ? index.copies[split] : nil
        return fits(target, in: index).map { spot(for: copy, in: index.columns[$0].shelf, previous: previous, next: next) }
    }

    /// Which of `spots(for:in:)` to take when nobody chose. Two spots only at
    /// a boundary between two compartments of one cabinet, where the end of
    /// one and the start of the next fit equally. Then, in this order: the
    /// side where the same artist already stands next to it, the compartment
    /// that is open, else the first.
    static func preferredIndex(_ spots: [Spot], for copy: RecordCopy, openShelf: UUID? = nil) -> Int {
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
        return 0
    }

    /// The artist part of the sort key (see `SortingService.sortKey`).
    private static func artistKey(_ copy: RecordCopy) -> Substring {
        let key = key(copy)
        return key.prefix { $0 != "\t" }
    }

    /// The shelves each of `copies` (without a shelf) fits alphabetically,
    /// by copy ID – the shelves of `spots`, for many records in one go.
    static func fittingShelves(for copies: [RecordCopy], in shelves: [Shelf], cabinet: UUID? = nil) -> [UUID: [Shelf]] {
        let index = index(of: sortingShelves(shelves, cabinet: cabinet, excluding: nil), excluding: nil)
        guard !index.columns.isEmpty else { return [:] }
        var result: [UUID: [Shelf]] = [:]
        for copy in copies {
            result[copy.id] = fits(key(copy), in: index).map { index.columns[$0].shelf }
        }
        return result
    }

    /// Where a placed `copy` stands right now and between which records — to
    /// put it back after taking it out. At either end of its shelf the
    /// neighbour comes from the shelf before or after it in the alphabetical
    /// run of its cabinet. `nil` for a copy without a shelf.
    static func current(for copy: RecordCopy, in shelves: [Shelf]) -> Spot? {
        guard let shelf = copy.shelf else { return nil }
        let items = ordered(shelf, excluding: copy.id)
        let slot = min(max(copy.positionInShelf - 1, 0), items.count)
        // The copy itself counts here, so a shelf holding only this copy keeps its place in the run.
        let cabinet = shelf.cabinet?.id
        let runs = index(of: shelves.filter { $0.cabinet?.id == cabinet }, excluding: nil).columns
        let runIndex = runs.firstIndex { $0.shelf.id == shelf.id }
        let previous = runIndex.flatMap { $0 > 0 ? ordered(runs[$0 - 1].shelf, excluding: nil).last : nil }
        let next = runIndex.flatMap { $0 + 1 < runs.count ? ordered(runs[$0 + 1].shelf, excluding: nil).first : nil }
        return Spot(
            shelf: shelf,
            position: slot + 1,
            before: slot > 0 ? items[slot - 1] : previous,
            after: slot < items.count ? items[slot] : next
        )
    }

    /// The compartments of the cabinet records are sorted into: `cabinet`
    /// (the one shown) when it holds records, else the first cabinet in the
    /// rack's order that does – what the shelf page shows when nothing is
    /// chosen, and the answer where no cabinet is shown (search in the menu
    /// bar, widget). Empty when no compartment holds a record.
    private static func sortingShelves(_ shelves: [Shelf], cabinet: UUID?, excluding copy: RecordCopy?) -> [Shelf] {
        let own = copy?.shelf?.persistentModelID
        // A shelf holding only the copy left out counts as empty.
        func holdsRecords(_ shelf: Shelf) -> Bool {
            !shelf.isReserved && shelf.copies.count > (shelf.persistentModelID == own ? 1 : 0)
        }
        let occupied = shelves.filter(holdsRecords)
        let shown = cabinet.flatMap { cabinet in occupied.first { $0.cabinet?.id == cabinet } }
        guard let pick = shown ?? occupied.min(by: { $0.readingOrder.lexicographicallyPrecedes($1.readingOrder) }) else { return [] }
        let chosen = pick.cabinet?.id
        return shelves.filter { $0.cabinet?.id == chosen }
    }

    /// Which compartments `target` fits best, in the order of the run. For
    /// each compartment the place it would take there, between its records
    /// `lower` and `upper`; it fits the worse the more records of other
    /// compartments sort between those two – they would have to stand
    /// there too. In a tidy cabinet one compartment fits with none between,
    /// or two at a boundary (the end of one, the start of the next). A
    /// compartment that holds records from all over the alphabet (a mixed
    /// box, records put in by hand) then never takes a record that has a
    /// closer place: before, the first compartment whose range covered the
    /// name took it, and a compartment from A to Z took every one.
    private static func fits(_ target: String, in index: Index) -> [Int] {
        let split = upperBound(index.keys, target)
        var best: [Int] = [], fewest = Int.max
        for (number, column) in index.columns.enumerated() {
            let place = upperBound(column.keys, target)
            // Records of the whole cabinet in (lower, target] and (target, upper).
            var between = 0
            if place > 0 { between += split - upperBound(index.keys, column.keys[place - 1]) }
            if place < column.keys.count { between += lowerBound(index.keys, column.keys[place]) - split }
            if between < fewest { fewest = between; best = [number] }
            else if between == fewest { best.append(number) }
        }
        return best
    }

    /// One compartment's records sorted by their keys.
    private struct Column { let shelf: Shelf; let keys: [String]; let copies: [RecordCopy] }

    /// The compartments of one cabinet in the alphabetical run of their
    /// contents (as in `ShelfRangeLabels`), and all their records in one
    /// sorted list.
    private struct Index { let columns: [Column]; let keys: [String]; let copies: [RecordCopy] }

    /// Sorted compartments, kept while their records and keys stay the same:
    /// every tile in "Noch nicht einsortiert" asks for its place, and sorting
    /// a cabinet each time took milliseconds per record. After sorting in one
    /// record only its compartment is sorted again. Per cabinet, as the shelf
    /// page (cabinet shown) and the widget (first cabinet) may ask in turn.
    private static var columns: [ObjectIdentifier: (fingerprint: Int, column: Column)] = [:]
    private static var indexes: [UUID?: (fingerprint: Int, index: Index)] = [:]

    /// The occupied, unreserved compartments of `shelves` – `excluded` (a
    /// placed copy looking for its place) left out of its own, uncached.
    private static func index(of shelves: [Shelf], excluding excluded: RecordCopy?) -> Index {
        let version = LibraryChanges.shared.libraryVersion, order = ShelfSecondaryOrder.current
        var kept: [ObjectIdentifier: (fingerprint: Int, column: Column)] = [:]
        var built: [Column] = []
        var whole = Hasher()
        // Only its own shelf can hold it: no other record's ID is read.
        let own = excluded?.shelf?.persistentModelID
        let id = excluded?.id
        for shelf in shelves where !shelf.isReserved {
            let leavesOut = own != nil && shelf.persistentModelID == own
            let copies = leavesOut ? shelf.copies.filter { $0.id != id } : shelf.copies
            guard !copies.isEmpty else { continue }
            // Which records, by identity – no property read – and the state their keys come from.
            var hasher = Hasher()
            hasher.combine(version); hasher.combine(order); hasher.combine(copies.count)
            var sum = 0
            for copy in copies { sum &+= ObjectIdentifier(copy).hashValue }
            hasher.combine(sum)
            let fingerprint = hasher.finalize()
            let object = ObjectIdentifier(shelf)
            let column: Column
            if !leavesOut, let entry = columns[object], entry.fingerprint == fingerprint {
                column = entry.column
            } else {
                let sorted = copies.map { (key: key($0), copy: $0) }.sorted { ascending($0.key, $1.key) }
                column = Column(shelf: shelf, keys: sorted.map(\.key), copies: sorted.map(\.copy))
            }
            if !leavesOut { kept[object] = (fingerprint, column) }
            whole.combine(object); whole.combine(fingerprint); whole.combine(leavesOut)
            built.append(column)
        }
        // A deleted compartment (reset, cabinet made smaller) doesn't linger.
        columns.merge(kept) { _, new in new }
        columns = columns.filter { !$0.value.column.shelf.isDeleted && $0.value.column.shelf.modelContext != nil }
        indexes = indexes.filter { $0.value.index.columns.allSatisfy { !$0.shelf.isDeleted && $0.shelf.modelContext != nil } }

        let fingerprint = whole.finalize()
        let cabinet = built.first?.shelf.cabinet?.id
        if excluded == nil, let kept = indexes[cabinet], kept.fingerprint == fingerprint { return kept.index }
        // Same start in two compartments (one artist and title across both):
        // the end decides, then the place in the rack, so the run never flips.
        let run = built.sorted { a, b in
            let first = a.keys[0].localizedStandardCompare(b.keys[0])
            if first != .orderedSame { return first == .orderedAscending }
            let last = a.keys[a.keys.count - 1].localizedStandardCompare(b.keys[b.keys.count - 1])
            if last != .orderedSame { return last == .orderedAscending }
            return a.shelf.readingOrder.lexicographicallyPrecedes(b.shelf.readingOrder)
        }
        // The compartments are sorted already: merging them is a few comparisons per record.
        let all = run.flatMap { zip($0.keys, $0.copies).map { (key: $0, copy: $1) } }.sorted { ascending($0.key, $1.key) }
        let index = Index(columns: run, keys: all.map(\.key), copies: all.map(\.copy))
        if excluded == nil { indexes[cabinet] = (fingerprint, index) }
        return index
    }

    /// The first index whose key sorts after `key`.
    private static func upperBound(_ keys: [String], _ key: String) -> Int {
        var low = 0, high = keys.count
        while low < high {
            let mid = (low + high) / 2
            if key.localizedStandardCompare(keys[mid]) == .orderedAscending { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// The first index whose key doesn't sort before `key`.
    private static func lowerBound(_ keys: [String], _ key: String) -> Int {
        var low = 0, high = keys.count
        while low < high {
            let mid = (low + high) / 2
            if keys[mid].localizedStandardCompare(key) == .orderedAscending { low = mid + 1 } else { high = mid }
        }
        return low
    }

    private static func ordered(_ shelf: Shelf, excluding id: UUID?) -> [RecordCopy] {
        PositionService.inShelfOrder(shelf.copies, excluding: id)
    }

    static func ascending(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
}
