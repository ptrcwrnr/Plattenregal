import Foundation

/// One style family's share of a shelf's copies (see `StylePalette.family`),
/// used for the compartment's dot and the legend in the shelf detail view.
struct ShelfStyleShare: Identifiable, Hashable {
    var id: String { style }
    /// Family name, or the style itself when "Sonstige" holds just one.
    let style: String
    /// A style with the family's color, for `StylePalette.color(for:)`.
    let colorStyle: String
    /// The styles counted here, most frequent first.
    let members: [String]
    let count: Int
    let fraction: Double
}

/// Count and style-distribution statistics for one shelf, derived from its
/// current copies. Never persisted — always recomputed from the live collection
/// so it can't drift from the actual shelf contents.
struct ShelfStatistics {
    let shelfID: UUID
    let count: Int
    /// Reserved compartments hold no records (e.g. a named slot for something else).
    let isReserved: Bool
    let styleShares: [ShelfStyleShare]
    /// Primary style of every copy in physical order (left → right), "" when unknown.
    /// Drives the spine rendering on shelf cards and in the detail pane.
    let spineStyles: [String]

    init(shelf: Shelf) {
        shelfID = shelf.id
        count = shelf.copies.count
        isReserved = shelf.isReserved
        spineStyles = PositionService.inShelfOrder(shelf.copies).map { $0.release?.primaryStyle ?? "" }
        // Same styles, without decoding each record's style list a second time.
        let styles = spineStyles.filter { !$0.isEmpty }
        let total = styles.count
        styleShares = Dictionary(grouping: styles, by: { StylePalette.family(of: $0).name })
            .map { name, styles in
                let members = Dictionary(grouping: styles, by: { $0 }).mapValues(\.count)
                    .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                    .map(\.key)
                // "Sonstige" is only a name for several unrelated styles; a single one keeps its own.
                let label = name == StylePalette.otherFamily && members.count == 1 ? members[0] : name
                return ShelfStyleShare(style: label, colorStyle: StylePalette.family(of: styles[0]).colorStyle, members: members,
                                       count: styles.count, fraction: total > 0 ? Double(styles.count) / Double(total) : 0)
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.style.localizedStandardCompare($1.style) == .orderedAscending
            }
    }

    /// Color of the family most records on the shelf belong to.
    var dominantColorStyle: String? { styleShares.first?.colorStyle }
}

/// Automatic shelf labels ("0 – B", "Ce – Di", "R – T", "B") derived from the
/// contents, never stored. Each occupied shelf spans from the first to the last
/// artist by the same key the shelves are sorted by (artist, then title, via
/// `localizedStandardCompare`). Where two neighbouring shelves meet inside the
/// same letter, both sides get a second letter — never more, so a label stays
/// a letter range and never turns into an artist name.
/// What the compartments are called: the letter range of their contents
/// ("A – Be", the default) or their number in the cabinet ("Fach 3").
enum ShelfLabelStyle: String, CaseIterable, Identifiable {
    case range, number
    static let key = "shelfLabelStyle"
    var id: Self { self }
    var title: String { self == .range ? "Buchstabenbereich" : "Fachnummer" }
    var example: String { self == .range ? "z. B. „A – Be“, „Ce – Di“" : "z. B. „Fach 1“, „Fach 2“" }
}

/// Labels for a set of shelves, plus where needed the cabinet's name for
/// telling cabinets apart in location texts.
struct ShelfLabels {
    fileprivate(set) var labels: [UUID: String] = [:]
    /// Only filled when there is more than one cabinet.
    fileprivate(set) var cabinetNames: [UUID: String] = [:]
    subscript(_ id: UUID) -> String? { labels[id] }
    /// "Regal 2 · " or "".
    func prefix(for shelf: Shelf) -> String {
        guard let name = cabinetNames[shelf.id] else { return "" }
        return shelf.isInUse ? "\(name) · " : "\(name) (inaktiv) · "
    }
}

/// Statistics and alphabetical ends per shelf, kept while the shelf's records
/// stay the same. Both read every record's release, and after each save the
/// shelf page's query hands back records whose releases SwiftData loads one
/// by one again (~0.1 s for 850 records). Sorting a record in changes one
/// shelf, so only that one is read again. Release metadata is followed via
/// `version` (`libraryVersion`), like the rest of the shelf page.
@MainActor final class ShelfContentCache {
    private struct Entry { let fingerprint: Int; let stats: ShelfStatistics; let ends: ShelfRangeLabels.Ends? }
    private var entries: [UUID: Entry] = [:]

    func refresh(_ shelves: [Shelf], version: Int) {
        var fresh: [UUID: Entry] = [:]
        for shelf in shelves {
            var hasher = Hasher()
            hasher.combine(version)
            hasher.combine(shelf.isReserved)
            for copy in shelf.copies { hasher.combine(copy.id); hasher.combine(copy.positionInShelf) }
            let fingerprint = hasher.finalize()
            if let entry = entries[shelf.id], entry.fingerprint == fingerprint { fresh[shelf.id] = entry; continue }
            fresh[shelf.id] = Entry(fingerprint: fingerprint, stats: ShelfStatistics(shelf: shelf), ends: ShelfRangeLabels.ends(of: shelf))
        }
        entries = fresh
    }

    func stats(for shelf: Shelf) -> ShelfStatistics { entries[shelf.id]?.stats ?? ShelfStatistics(shelf: shelf) }
    func ends(of shelf: Shelf) -> ShelfRangeLabels.Ends? { entries[shelf.id].map(\.ends) ?? ShelfRangeLabels.ends(of: shelf) }
}

/// Labels computed once for a view instead of in every `body`: they read
/// every placed record, over a second for a collection of 10 000 – each
/// toggle in a popover would hang that long. Recomputed only for another
/// label style or when the shown record moved to another compartment.
@MainActor final class ShelfLabelCache {
    private var key: (style: ShelfLabelStyle, shelf: UUID?)?
    private var value = ShelfLabels()
    func labels(for shelves: [Shelf], style: ShelfLabelStyle, showing shelf: Shelf?) -> ShelfLabels {
        if let key, key.style == style, key.shelf == shelf?.id { return value }
        value = ShelfRangeLabels.compute(for: shelves, style: style)
        key = (style, shelf?.id)
        return value
    }
}

enum ShelfRangeLabels {
    /// `ends`: a shelf's first and last artist, reduced to `letters`; the shelf
    /// page passes the ones it kept for shelves whose records didn't change.
    static func compute(for shelves: [Shelf], style: ShelfLabelStyle = .range, ends: @MainActor (Shelf) -> Ends? = ends(of:)) -> ShelfLabels {
        var result = ShelfLabels()
        let cabinets = Set(shelves.compactMap { $0.cabinet?.id })
        if cabinets.count > 1 {
            for shelf in shelves { if let cabinet = shelf.cabinet { result.cabinetNames[shelf.id] = cabinet.name } }
        }
        if style == .number {
            for shelf in shelves where !shelf.isReserved { result.labels[shelf.id] = shelf.numberText }
            return result
        }
        // Cabinets in use form one alphabetical run; an inactive one (records
        // put away) has a run of its own, so it never splits the others' ranges.
        let groups = Dictionary(grouping: shelves) { $0.isInUse ? nil : $0.cabinet?.id }
        for group in groups.values { result.labels.merge(rangeLabels(for: group, ends: ends)) { a, _ in a } }
        return result
    }

    /// The label style chosen in the settings.
    static var currentStyle: ShelfLabelStyle {
        AppDefaults.store.string(forKey: ShelfLabelStyle.key).flatMap(ShelfLabelStyle.init) ?? .range
    }

    struct Ends: Equatable { let first: String; let last: String }

    /// `nil` for a reserved or empty shelf.
    static func ends(of shelf: Shelf) -> Ends? {
        guard !shelf.isReserved else { return nil }
        // Only the ends matter: one pass instead of sorting every key.
        let keys = shelf.copies.map(SortingService.sortKey)
        guard let first = keys.min(by: AlphabeticalPlacement.ascending), let last = keys.max(by: AlphabeticalPlacement.ascending) else { return nil }
        return Ends(first: letters(first), last: letters(last))
    }

    private static func rangeLabels(for shelves: [Shelf], ends: @MainActor (Shelf) -> Ends?) -> [UUID: String] {
        struct Span { let id: UUID; let first: String; let last: String }
        let spans: [Span] = shelves.compactMap { shelf in
            ends(shelf).map { Span(id: shelf.id, first: $0.first, last: $0.last) }
        }
        // Neighbours in the alphabetical run, independent of the physical layout.
        .sorted { $0.first.localizedStandardCompare($1.first) == .orderedAscending }

        var labels: [UUID: String] = [:]
        for (index, span) in spans.enumerated() {
            var start = boundaryLabel(span.first, against: index > 0 ? spans[index - 1].last : nil)
            var end = boundaryLabel(span.last, against: index + 1 < spans.count ? spans[index + 1].first : nil)
            // "Bl – B" reads oddly: within one letter, give both ends the same depth ("Bl – Bo").
            if start.first == end.first, start.first?.isLetter == true, start.count != end.count {
                let depth = max(start.count, end.count)
                start = boundaryLabel(span.first, depth: depth)
                end = boundaryLabel(span.last, depth: depth)
            }
            labels[span.id] = start == end ? start : "\(start) – \(end)"
        }
        // Two letters at most can leave several shelves inside one range
        // ("Th" for a run of "The …"). Labels are the shelves' only names, so
        // those get a running number in alphabetical order: "Th · 1", "Th · 2".
        let order = spans.map(\.id)
        for (label, ids) in Dictionary(grouping: order, by: { labels[$0]! }) where ids.count > 1 {
            for (index, id) in ids.enumerated() { labels[id] = "\(label) · \(index + 1)" }
        }
        return labels
    }

    /// The artist reduced to comparable letters: case and diacritics folded,
    /// spaces and punctuation after the first character dropped
    /// ("Ex-Otago" → "EXOTAGO"). A leading non-letter stays so it can be grouped.
    static func letters(_ key: String) -> String {
        let artist = key.components(separatedBy: "\t").first ?? key
        // Latin-ASCII as in the alphabet index, so "Øystein" is an O here too.
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = (trimmed.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) ?? trimmed)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
        guard let head = folded.first else { return "" }
        return String(head) + folded.dropFirst().filter { $0.isLetter || $0.isNumber }
    }

    /// "0" for digits, "#" for other symbols, otherwise the first letter —
    /// plus a second one ("Ce") when the neighbouring shelf's boundary artist
    /// starts with the same letter.
    static func boundaryLabel(_ value: String, against neighbour: String?) -> String {
        guard let head = value.first else { return "#" }
        if head.isNumber { return "0" }
        guard head.isLetter else { return "#" }
        var length = 1
        if let neighbour, neighbour.first == head { length = min(value.count, 2) }
        return boundaryLabel(value, depth: length)
    }

    /// Where a copy stands, in words: "A – B · Position 12", a reserved
    /// shelf's name, "Nicht im Regal" or "Noch keinem Fach zugeordnet".
    static func location(of copy: RecordCopy, labels: ShelfLabels, excluded: Bool = false) -> String {
        guard let shelf = copy.shelf else { return excluded ? "Nicht im Regal" : "Noch keinem Fach zugeordnet" }
        let prefix = labels.prefix(for: shelf)
        if shelf.isReserved { return prefix + (shelf.name.isEmpty ? "Gesperrtes Fach" : shelf.name) }
        return "\(prefix)\(labels[shelf.id] ?? "Leeres Fach") · Position \(copy.positionInShelf)"
    }

    static func boundaryLabel(_ value: String, depth: Int) -> String {
        let prefix = value.prefix(depth)
        return prefix.prefix(1) + prefix.dropFirst().lowercased()
    }
}
