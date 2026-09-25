import Foundation
import SwiftData

/// Grid of the first cabinet, created on first launch (a KALLAX 4 × 3), and
/// the limits for cabinets set up in the settings.
nonisolated enum ShelfGeometry {
    static let rows = 3
    static let columns = 4
    static let count = rows * columns
    static let sizeRange = 1...6
}

extension Cabinet {
    var count: Int { rows * columns }
    /// Its compartments in reading order.
    var orderedShelves: [Shelf] { shelves.sorted { ($0.sortOrder, $0.number) < ($1.sortOrder, $1.number) } }
    var recordCount: Int { shelves.reduce(0) { $0 + $1.copies.count } }
    var sizeText: String { "\(columns) × \(rows)" }
}

extension Shelf {
    /// Shown on the shelf page and used when sorting in: no cabinet yet
    /// (only before `prepareShelves`) counts as in use.
    var isInUse: Bool { cabinet?.isActive ?? true }
    var numberText: String { "Fach \(sortOrder)" }

    /// Every shelf in use, cabinet by cabinet, each in reading order.
    static func inUse(_ shelves: [Shelf]) -> [Shelf] {
        shelves.filter(\.isInUse).sorted(by: physicalOrder)
    }
    /// A new compartment in `cabinet`. The cabinet is linked only after the
    /// insert: SwiftData mishandles relationships set on a model it doesn't know yet.
    @discardableResult static func insert(number: Int, cabinet: Cabinet, slot: Int, in context: ModelContext) -> Shelf {
        let shelf = Shelf(number: number, cabinet: cabinet, slot: slot)
        context.insert(shelf)
        shelf.cabinet = cabinet
        return shelf
    }
    static func physicalOrder(_ a: Shelf, _ b: Shelf) -> Bool {
        (a.cabinet?.sortOrder ?? 0, a.sortOrder, a.number) < (b.cabinet?.sortOrder ?? 0, b.sortOrder, b.number)
    }
}

/// Discogs tells same-named artists and labels apart with a running number in
/// parentheses ("Systematic (3)"). That number is bookkeeping, not part of the
/// name, so views drop it. Only a purely numeric "(n)" after a space is removed —
/// words in parentheses can be a real part of a name and stay untouched. Works on
/// joined strings too ("Moby (2) & Kid (3), Other (4)").
nonisolated enum DiscogsName {
    /// Same as `name.replacing(/\s+\(\d+\)(?=\s|,|$)/, with: "")`, but a plain
    /// scan: the regex took ~60 µs a call, and every shown artist and label,
    /// shelf label, sort and placement runs through here – seconds on the
    /// main thread for a large collection.
    static func clean(_ name: String) -> String {
        guard name.contains("(") else { return name }
        let chars = Array(name)
        var result = ""
        result.reserveCapacity(name.utf8.count)
        var i = 0
        while i < chars.count {
            guard chars[i].isWhitespace else { result.append(chars[i]); i += 1; continue }
            var j = i
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            // Whitespace, "(", digits, ")" and then whitespace, a comma or the end.
            // `isNumber` is exactly what `\d` matched on characters (also "٣", "²").
            if j < chars.count, chars[j] == "(" {
                var k = j + 1
                while k < chars.count, chars[k].isNumber { k += 1 }
                if k > j + 1, k < chars.count, chars[k] == ")",
                   k + 1 == chars.count || chars[k + 1].isWhitespace || chars[k + 1] == "," {
                    i = k + 1
                    continue
                }
            }
            result.append(contentsOf: chars[i..<j])
            i = j
        }
        return result
    }
}

nonisolated struct Track: Codable, Hashable, Sendable {
    var position: String
    var title: String
    var duration: String
}

extension DiscogsAccount {
    /// The account the app currently mirrors: the one synced most recently.
    /// Copies of an earlier account stay in the store but aren't shown.
    static func current(in accounts: [DiscogsAccount]) -> DiscogsAccount? {
        accounts.max { $0.lastSync < $1.lastSync }
    }
    var lastSync: Date { lastFullSync ?? lastCollectionSync ?? lastWantlistSync ?? .distantPast }
}

extension RecordCopy {
    /// Every copy, with its release and compartment loaded in the same go.
    /// Walking thousands of copies otherwise loads each release on its own
    /// the first time a name is read.
    static func fetchingReleases() -> FetchDescriptor<RecordCopy> {
        var descriptor = FetchDescriptor<RecordCopy>()
        descriptor.relationshipKeyPathsForPrefetching = [\.release, \.shelf]
        return descriptor
    }

    /// In the Discogs collection the app currently mirrors: active, and from
    /// the current account (`owner`, see `DiscogsAccount.current`). `nil`
    /// owner = no account synced yet, any active copy counts.
    func isInCurrentCollection(owner: String?) -> Bool {
        discogsActive && (owner == nil || discogsOwner == owner)
    }

    /// Came from Discogs but isn't in the current collection any more: sold,
    /// given away, or from another account.
    func leftCurrentCollection(owner: String?) -> Bool {
        !isInCurrentCollection(owner: owner)
    }
}
