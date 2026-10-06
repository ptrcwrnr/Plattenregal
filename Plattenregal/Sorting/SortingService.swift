import Foundation
import SwiftData

enum SortingService {
    static let alphabetNavigationSymbols = ["#"] + (65...90).compactMap(UnicodeScalar.init).map(String.init)

    /// By artist name: the transform below costs microseconds, and every sort
    /// and alphabet section of collection and wantlist asks for the same names again.
    private static var sections: [String: String] = [:]

    static func alphabetSection(for artist: String) -> String {
        if let cached = sections[artist] { return cached }
        let section = computeAlphabetSection(for: artist)
        sections[artist] = section
        return section
    }

    private static func computeAlphabetSection(for artist: String) -> String {
        // Latin-ASCII also maps letters without a decomposable accent
        // ("Øystein" → O, "Æther" → A, "Łona" → L), which plain diacritic
        // folding would leave under "#".
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) ?? trimmed)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
        guard let first = normalized.unicodeScalars.first,
              (65...90).contains(Int(first.value)) else { return "#" }
        return String(first)
    }

    /// By artist, then title (`sortKey`); ties by ID, so the order is stable.
    static func sorted(_ copies: [RecordCopy]) -> [RecordCopy] {
        // Everything the comparison needs is read once per item: a SwiftData
        // property read costs microseconds, and a sort does ~n·log n comparisons
        // (10 000 records: 1.5 s before, most of it reading `id`).
        let order = ShelfSecondaryOrder.current
        let items = copies.map { copy in (copy: copy, key: sortKey(copy, by: order), tie: copy.id.uuidString) }
        return items.sorted { a, b in
            let comparison = a.key.localizedStandardCompare(b.key)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return a.tie < b.tie
        }
        .map(\.copy)
    }
    /// Sorted by artist like `sorted(_:)`, but grouped by the
    /// alphabet sections ("#" first, then A–Z), so every record sits under
    /// its letter — also names the collation puts
    /// elsewhere ("Þeyr" behind Z, non-Latin scripts at the end).
    static func sortedByAlphabetSection(_ copies: [RecordCopy]) -> [RecordCopy] {
        let order = Dictionary(uniqueKeysWithValues: alphabetNavigationSymbols.enumerated().map { ($1, $0) })
        let sections = copies.map { order[alphabetSection(for: $0.release?.displayArtist ?? "")] ?? 0 }
        let rank = Dictionary(zip(copies.map(\.id), sections), uniquingKeysWith: { a, _ in a })
        var buckets = Array(repeating: [RecordCopy](), count: alphabetNavigationSymbols.count)
        for copy in sorted(copies) { buckets[rank[copy.id] ?? 0].append(copy) }
        return buckets.flatMap { $0 }
    }
    /// Artist, then – for the same artist – the chosen `ShelfSecondaryOrder`
    /// (title by default): the one key every alphabetical order in the app
    /// uses (collection, "Sortierung prüfen", sorting in, shelf labels), so
    /// they never disagree about where a record belongs.
    static func sortKey(_ copy: RecordCopy, by order: ShelfSecondaryOrder = .current) -> String {
        guard let r = copy.release else { return "" }
        return r.displayArtist.trimmingCharacters(in: .whitespacesAndNewlines) + "\t" + order.key(r)
    }
    /// Everything a collection search looks at, including the track titles.
    static func searchText(_ copy: RecordCopy) -> String {
        guard let r = copy.release else { return "" }
        return [r.artist, r.title, r.label, r.catalogNumber, r.year.map(String.init) ?? "", r.country, r.format,
                r.genres.joined(separator: " "), r.styles.joined(separator: " "),
                r.tracks.map(\.title).joined(separator: " ")].joined(separator: " ")
    }
}

/// Search texts folded (case/diacritics) once when the data changes, so a
/// keystroke only runs plain substring checks instead of rebuilding and
/// Unicode-comparing every record's text.
struct SearchIndex<ID: Hashable> {
    private var texts: [ID: String] = [:]

    init() {}
    init<S: Sequence>(_ items: S, id: (S.Element) -> ID, text: (S.Element) -> String) {
        for item in items { texts[id(item)] = Self.fold(text(item)) }
    }

    /// Every word of the query must occur somewhere in the record's text.
    func matches(_ id: ID, _ words: [String]) -> Bool {
        guard let text = texts[id] else { return false }
        return words.allSatisfy { text.contains($0) }
    }

    nonisolated static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
    }

    nonisolated static func fold(_ value: String) -> String {
        // Case folding keeps "ß", so "Strasse" would miss "Straße".
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ß", with: "ss")
    }
}

/// The search texts of all records and wantlist entries, folded once and
/// shared by collection and wantlist: each page searches its own list and
/// counts the other's hits, so each index used to be built twice. Built on
/// the first search after a change, not with every change – the tracklist
/// download reports every few seconds, mostly while nobody searches.
///
/// Every record is in it, whichever account and whether still in the
/// collection: the pages only look up the ones they show, so an index never
/// depends on which records count as current right now.
final class LibrarySearchIndexes {
    static let shared = LibrarySearchIndexes()

    /// What an index was built from: the counts of all records and entries
    /// (what the pages' queries hold), the reported changes, and the pages'
    /// own data rebuilds (`invalidate`).
    private struct Key: Equatable { let generation: Int; let library: Int; let tracks: Int; let count: Int }
    private var generation = 0
    private var collection: (key: Key, index: SearchIndex<UUID>)?
    private var wantlist: (key: Key, index: SearchIndex<PersistentIdentifier>)?

    /// A page rebuilt from changed data: the next search builds afresh.
    func invalidate() { generation += 1 }

    private func key(count: Int) -> Key {
        Key(generation: generation, library: LibraryChanges.shared.libraryVersion, tracks: LibraryChanges.shared.tracksVersion, count: count)
    }

    /// `copies`: every record, only read when the index has to be built.
    func collection(_ copies: [RecordCopy]) -> SearchIndex<UUID> {
        let key = key(count: copies.count)
        if let collection, collection.key == key { return collection.index }
        let index = SearchIndex(copies, id: \.id, text: SortingService.searchText)
        collection = (key, index)
        return index
    }

    /// `entries`: every wantlist entry.
    func wantlist(_ entries: [WantlistEntry]) -> SearchIndex<PersistentIdentifier> {
        let key = key(count: entries.count)
        if let wantlist, wantlist.key == key { return wantlist.index }
        let index = SearchIndex(entries, id: \.persistentModelID, text: WantlistPresentation.searchText)
        wantlist = (key, index)
        return index
    }
}

extension Release {
    /// The track a search found this release by, shown on its card — `nil`
    /// when the query already matches artist and title (or no track at all).
    /// Folded like the search index, so a record the search kept also shows
    /// the track it was found by ("strasse" → "Straße").
    func track(matching query: String) -> Track? {
        let words = SearchIndex<Int>.words(query)
        guard !words.isEmpty, !tracks.isEmpty else { return nil }
        let name = SearchIndex<Int>.fold(artist + " " + title)
        if words.allSatisfy({ name.contains($0) }) { return nil }
        return tracks.first { track in
            let title = SearchIndex<Int>.fold(track.title)
            return words.allSatisfy { title.contains($0) }
        }
    }
}

extension Release {
    // Discogs-Releases können mehrere Styles besitzen. Für die Regalorganisation wird
    // hier bewusst der erste gespeicherte Style als "Haupt-Style" verwendet, da Discogs
    // Styles in absteigender Relevanz liefert. Diese Zuordnung ist bewusst an einer
    // Stelle gekapselt, damit sie später z.B. durch eine Priorisierungsliste oder eine
    // "häufigster Style im Fach"-Heuristik ersetzt werden kann, ohne Aufrufer anzupassen.
    var primaryStyle: String { styles.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
}

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

    static func key(_ copy: RecordCopy) -> String { SortingService.sortKey(copy) }

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
        let runs = runs(of: shelves, excluding: copy.id)
        guard let lastRun = runs.last else { return [] }

        let target = key(copy)
        guard let index = runs.firstIndex(where: { target.localizedStandardCompare($0.last) != .orderedDescending }) else {
            return [Spot(shelf: lastRun.shelf, position: lastRun.items.count + 1, before: lastRun.items.last, after: nil)]
        }
        let run = runs[index]
        if target.localizedStandardCompare(run.first) == .orderedAscending {
            let start = Spot(shelf: run.shelf, position: 1, before: index > 0 ? runs[index - 1].items.last : nil, after: run.items.first)
            guard index > 0 else { return [start] }
            let previous = runs[index - 1]
            let end = Spot(shelf: previous.shelf, position: previous.items.count + 1, before: previous.items.last, after: run.items.first)
            return [end, start]
        }
        let position = position(for: copy, in: run.shelf)
        return [Spot(
            shelf: run.shelf,
            position: position,
            before: position > 1 ? run.items[position - 2] : nil,
            after: position <= run.items.count ? run.items[position - 1] : nil
        )]
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
        let previous = runIndex.flatMap { $0 > 0 ? runs[$0 - 1].items.last : nil }
        let next = runIndex.flatMap { $0 + 1 < runs.count ? runs[$0 + 1].items.first : nil }
        return Spot(
            shelf: shelf,
            position: index + 1,
            before: index > 0 ? items[index - 1] : previous,
            after: index < items.count ? items[index] : next
        )
    }

    private struct Run { let shelf: Shelf; let items: [RecordCopy]; let first: String; let last: String }

    /// Occupied, unreserved shelves in the alphabetical order of their contents.
    private static func runs(of shelves: [Shelf], excluding id: UUID?) -> [Run] {
        shelves.compactMap { shelf -> Run? in
            guard !shelf.isReserved else { return nil }
            let items = ordered(shelf, excluding: id)
            // Only the ends matter: one pass instead of sorting every key.
            let keys = items.map(key)
            guard let first = keys.min(by: ascending), let last = keys.max(by: ascending) else { return nil }
            return Run(shelf: shelf, items: items, first: first, last: last)
        }
        .sorted { $0.first.localizedStandardCompare($1.first) == .orderedAscending }
    }

    private static func ordered(_ shelf: Shelf, excluding id: UUID?) -> [RecordCopy] {
        PositionService.inShelfOrder(shelf.copies, excluding: id)
    }

    static func ascending(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
}

/// The order of one artist's records in a shelf. The artist always comes
/// first, so the shelves' letter ranges and every placement stay valid.
nonisolated enum ShelfSecondaryOrder: String, CaseIterable, Identifiable {
    case title, year, label
    static let key = "shelfSecondaryOrder"
    var id: Self { self }
    var title: String {
        switch self {
        case .title: String(localized: "Titel")
        case .year: String(localized: "Jahr")
        case .label: String(localized: "Label")
        }
    }
    var hint: String {
        switch self {
        case .title: String(localized: "Die Platten eines Interpreten nach Titel, von A bis Z.")
        case .year: String(localized: "Die Platten eines Interpreten nach Erscheinungsjahr, die älteste zuerst.")
        case .label: String(localized: "Die Platten eines Interpreten nach Label und Katalognummer.")
        }
    }

    /// Chosen in Einstellungen › Regal.
    static var current: Self {
        AppDefaults.store.string(forKey: key).flatMap(Self.init) ?? .title
    }

    /// The part of the sort key after the artist. Records without a year or
    /// label go behind the others; the title breaks every tie.
    func key(_ release: Release) -> String {
        switch self {
        case .title:
            return release.displayTitle
        case .year:
            let year = release.year.map { "0" + String(format: "%04d", $0) } ?? "1"
            return year + "\t" + release.displayTitle
        case .label:
            let label = release.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return (label.isEmpty ? "1" : "0" + label) + "\t" + release.catalogNumber + "\t" + release.displayTitle
        }
    }
}

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

    /// Like `SortingService.sorted`, by the given order.
    static func sortedCopies(_ copies: [RecordCopy], by order: ShelfSecondaryOrder) -> [RecordCopy] {
        copies.map { (copy: $0, key: SortingService.sortKey($0, by: order), tie: $0.id.uuidString) }
            .sorted { a, b in
                let comparison = a.key.localizedStandardCompare(b.key)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return a.tie < b.tie
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
