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
        // The mark for "known" (0) or "missing" (1) stands alone before a tab:
        // glued to the value it formed one number with its digits – "01999"
        // counted as 1999 and sorted behind the "1" of a record without a
        // year, "04AD" behind every label starting with a letter.
        switch self {
        case .title:
            return release.displayTitle
        case .year:
            let year = release.year.map { "0\t" + String(format: "%04d", $0) } ?? "1\t"
            return year + "\t" + release.displayTitle
        case .label:
            let label = release.label.trimmingCharacters(in: .whitespacesAndNewlines)
            return (label.isEmpty ? "1\t" : "0\t" + label) + "\t" + release.catalogNumber + "\t" + release.displayTitle
        }
    }
}
