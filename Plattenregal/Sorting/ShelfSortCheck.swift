import Foundation

/// "Sortierung prüfen": which records of a shelf are out of order, against
/// the shelf's stored positions.
enum ShelfSortCheck {
    /// One move at the shelf: take `copy` from where it stands and put it
    /// right behind `before` (or, at the very front, right before `after`).
    struct Step: Identifiable {
        let copy: RecordCopy
        /// 1-based, as stored: where it stands now, counted from the left.
        let position: Int
        /// Already in its right place when this step comes up: the records
        /// in front of it are the steps before plus the ones never moved.
        let before: RecordCopy?
        /// The next record that isn't moved at all.
        let after: RecordCopy?
        var id: UUID { copy.id }
    }

    /// The fewest records that have to move so `ordered` (the shelf in its
    /// stored order) follows `order`: all but a longest run already in the
    /// right order. In the order of their target places, so each step only
    /// refers to records that already stand right. Empty when in order.
    static func steps(_ ordered: [RecordCopy], by order: ShelfSecondaryOrder) -> [Step] {
        let sorted = sortedCopies(ordered, by: order)
        guard sorted.count > 1 else { return [] }
        let rank = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.id, $0) })
        let ranks = ordered.map { rank[$0.id] ?? 0 }
        let keep = longestIncreasing(ranks)
        let kept = Set(keep.map { ordered[$0].id })
        let position = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0 + 1) })
        return sorted.enumerated().compactMap { target, copy in
            guard !kept.contains(copy.id) else { return nil }
            let after = sorted[(target + 1)...].first { kept.contains($0.id) }
            return Step(copy: copy, position: position[copy.id] ?? 0,
                        before: target > 0 ? sorted[target - 1] : nil, after: after)
        }
    }

    /// Like `SortingService.sorted`, by the given order. Records with the same
    /// key (two copies of one album) keep their order in the shelf: either
    /// order is right, so neither the check nor sorting asks to swap them.
    /// Keys from `ShelfSortKeys`, the ones sorting in and the shelf labels
    /// use: the check can't disagree with them, and ticking off a move (which
    /// checks again) doesn't read every record's release once more.
    static func sortedCopies(_ copies: [RecordCopy], by order: ShelfSecondaryOrder) -> [RecordCopy] {
        copies.map { (copy: $0, key: ShelfSortKeys.key($0, by: order), position: $0.positionInShelf) }
            .sorted { a, b in
                let comparison = a.key.localizedStandardCompare(b.key)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                if a.position != b.position { return a.position < b.position }
                // Same record twice at one place: only then is the ID read.
                return a.copy.id.uuidString < b.copy.id.uuidString
            }
            .map(\.copy)
    }

    /// Indexes of one longest strictly increasing subsequence (O(n log n)).
    private static func longestIncreasing(_ values: [Int]) -> Set<Int> {
        var tails: [Int] = []          // index into `values` ending each length
        var previous = Array(repeating: -1, count: values.count)
        for (index, value) in values.enumerated() {
            var low = 0, high = tails.count
            while low < high {
                let mid = (low + high) / 2
                if values[tails[mid]] < value { low = mid + 1 } else { high = mid }
            }
            if low > 0 { previous[index] = tails[low - 1] }
            if low == tails.count { tails.append(index) } else { tails[low] = index }
        }
        var result = Set<Int>()
        var index = tails.last ?? -1
        while index >= 0 { result.insert(index); index = previous[index] }
        return result
    }
}
