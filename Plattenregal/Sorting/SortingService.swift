import Foundation

enum RecordSort {
    case artistAZ, year
}

enum SortingService {
    static let alphabetNavigationSymbols = ["#"] + (65...90).compactMap(UnicodeScalar.init).map(String.init)

    static func alphabetSection(for artist: String) -> String {
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

    static func sorted(_ copies: [RecordCopy], by order: RecordSort) -> [RecordCopy] {
        // Everything the comparison needs is read once per item: a SwiftData
        // property read costs microseconds, and a sort does ~n·log n comparisons
        // (10 000 records: 1.5 s before, most of it reading `id` and `year`).
        let items = copies.map { copy in
            (copy: copy, key: sortKey(copy), year: order == .year ? copy.release?.year ?? Int.max : 0, tie: copy.id.uuidString)
        }
        return items.sorted { a, b in
            if a.year != b.year { return a.year < b.year }
            let comparison = a.key.localizedStandardCompare(b.key)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return a.tie < b.tie
        }
        .map(\.copy)
    }
    /// Sorted by artist like `sorted(_:by: .artistAZ)`, but grouped by the
    /// alphabet index's sections ("#" first, then A–Z), so every record sits
    /// under the letter the index jumps to — also names the collation puts
    /// elsewhere ("Þeyr" behind Z, non-Latin scripts at the end).
    static func sortedByAlphabetSection(_ copies: [RecordCopy]) -> [RecordCopy] {
        let order = Dictionary(uniqueKeysWithValues: alphabetNavigationSymbols.enumerated().map { ($1, $0) })
        let sections = copies.map { order[alphabetSection(for: $0.release?.displayArtist ?? "")] ?? 0 }
        let rank = Dictionary(zip(copies.map(\.id), sections), uniquingKeysWith: { a, _ in a })
        var buckets = Array(repeating: [RecordCopy](), count: alphabetNavigationSymbols.count)
        for copy in sorted(copies, by: .artistAZ) { buckets[rank[copy.id] ?? 0].append(copy) }
        return buckets.flatMap { $0 }
    }
    /// Artist, then title — the one key every alphabetical order in the app
    /// uses (collection, "Fach sortieren", sorting in, shelf labels), so they
    /// never disagree about where a record belongs.
    static func sortKey(_ copy: RecordCopy) -> String {
        guard let r = copy.release else { return "" }
        return r.displayArtist.trimmingCharacters(in: .whitespacesAndNewlines) + "\t" + r.displayTitle
    }
    static func matches(_ copy: RecordCopy, query: String) -> Bool {
        guard copy.release != nil else { return false }
        let text = searchText(copy)
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains(String($0)) }
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
