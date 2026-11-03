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
    var numberText: String { String(localized: "Fach \(sortOrder)") }

    /// The records standing in it, without `excluded` – the same ones the
    /// grid and table count (see `ShelfCopyItem.snapshot`).
    func recordCount(excluding excluded: UUID? = nil) -> Int {
        // By the model's identifier: reading the `id` of every record and of
        // its shelf took twice as long (90 records: 0.26 against 0.15 ms
        // in Debug), and the shelf page counts on every redraw.
        let me = persistentModelID
        return copies.filter { !$0.isDeleted && $0.shelf?.persistentModelID == me && (excluded == nil || $0.id != excluded) }.count
    }

    /// "Pos. 41 von 87": where a record stands and out of how many, so one
    /// can tell the middle from an end. `joining`: the record isn't in yet
    /// and would be one more. Never fewer than the position itself.
    /// `count`: `recordCount()` when the caller already has it.
    func positionText(_ position: Int, joining: Bool = false, count: Int? = nil) -> String {
        let total = max((count ?? recordCount()) + (joining ? 1 : 0), position)
        return String(localized: "Pos. \(position) von \(total)")
    }

    /// Every shelf in use, cabinet by cabinet, each in reading order.
    /// Each shelf's cabinet is read once, not in every comparison of the
    /// sort: the shelf page builds this list on every render.
    static func inUse(_ shelves: [Shelf]) -> [Shelf] {
        shelves.compactMap { shelf -> (key: (Int, Int, Int), shelf: Shelf)? in
            let cabinet = shelf.cabinet
            // Same rule as `isInUse` and order as `physicalOrder`.
            guard cabinet?.isActive ?? true else { return nil }
            return ((cabinet?.sortOrder ?? 0, shelf.sortOrder, shelf.number), shelf)
        }
        .sorted { $0.key < $1.key }
        .map(\.shelf)
    }
    /// A new compartment in `cabinet`. The cabinet is linked only after the
    /// insert: SwiftData mishandles relationships set on a model it doesn't know yet.
    @discardableResult static func insert(number: Int, cabinet: Cabinet, slot: Int, in context: ModelContext) -> Shelf {
        let shelf = Shelf(number: number, cabinet: cabinet, slot: slot)
        context.insert(shelf)
        shelf.cabinet = cabinet
        return shelf
    }
    /// Cabinet, place in it, number – what `physicalOrder` compares.
    var readingOrder: [Int] { [cabinet?.sortOrder ?? 0, sortOrder, number] }
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

    /// Two labels of one release often share the number ("ASOT018, ASOT018"); listed once.
    /// Discogs writes "none" for a release without one.
    static func catalogNumber(_ raw: String) -> String {
        listedOnce(raw) { $0.caseInsensitiveCompare("none") != .orderedSame }
    }

    /// "Positiva, Positiva" (one label with two numbers) → "Positiva"; "DOS 202, dos 202" → "DOS 202".
    static func listedOnce(_ list: String, keeping keep: (String) -> Bool = { _ in true }) -> String {
        var seen = Set<String>()
        return list.components(separatedBy: ", ")
            .filter { !$0.isEmpty && keep($0) && seen.insert($0.lowercased()).inserted }
            .joined(separator: ", ")
    }

    /// Discogs names the quantity first ("1 · Vinyl · 12\""): a single disc goes without it,
    /// more read as a count ("2 × Vinyl · LP").
    static func format(_ raw: String) -> String {
        raw.components(separatedBy: ", ").map { part in
            guard let dot = part.range(of: " · "), let quantity = Int(part[..<dot.lowerBound]) else { return part }
            let rest = part[dot.upperBound...]
            return quantity == 1 ? String(rest) : "\(quantity) × \(rest)"
        }
        .joined(separator: ", ")
    }
}

/// What the record card, the random find and the export show of a release –
/// the stored values stay as Discogs sent them (sync and search compare them).
extension Release {
    /// Each label once, without Discogs' "(2)".
    var shownLabel: String { DiscogsName.listedOnce(displayLabel) }
    /// Each catalog number once, without "none".
    var shownCatalogNumber: String { DiscogsName.catalogNumber(catalogNumber) }
    /// "Vinyl · LP · Album", "2 × Vinyl · LP".
    var shownFormat: String { DiscogsName.format(format) }
}

nonisolated struct Track: Codable, Hashable, Sendable {
    var position: String
    var title: String
    var duration: String
}

/// A video Discogs lists for a release (almost always on YouTube).
nonisolated struct ReleaseVideo: Codable, Hashable, Sendable {
    var title: String
    var url: String
}

extension ReleaseVideoList {
    /// Stores what Discogs listed for the release, replacing an older list.
    /// An empty list is stored too: it marks the release as asked.
    static func store(_ videos: [ReleaseVideo], for discogsID: Int, in context: ModelContext) throws {
        if let row = try context.fetch(FetchDescriptor<ReleaseVideoList>(predicate: #Predicate { $0.discogsID == discogsID })).first {
            if row.videos != videos { row.videos = videos }
        } else {
            context.insert(ReleaseVideoList(discogsID: discogsID, videos: videos))
        }
    }
}

extension DiscogsAccount {
    /// The account the app currently mirrors: the one synced most recently.
    /// Copies of an earlier account stay in the store but aren't shown.
    static func current(in accounts: [DiscogsAccount]) -> DiscogsAccount? {
        accounts.max { $0.lastSync < $1.lastSync }
    }
    /// The latest of its syncs, whichever kind: a collection sync after an
    /// older full sync makes the account current again.
    var lastSync: Date { [lastFullSync, lastCollectionSync, lastWantlistSync].compactMap { $0 }.max() ?? .distantPast }
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
