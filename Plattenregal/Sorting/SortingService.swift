import Foundation

enum RecordSort: String, CaseIterable, Identifiable {
    case artistAZ = "Interpret A–Z", artistZA = "Interpret Z–A", year = "Jahr"
    case genre = "Genre → Interpret", style = "Style → Interpret", label = "Label → Katalognummer"
    case physical = "Physische Reihenfolge"
    var id: String { rawValue }
}

enum SortingService {
    static let alphabetNavigationSymbols = ["#"] + (65...90).compactMap(UnicodeScalar.init).map(String.init)

    static func alphabetSection(for artist: String) -> String {
        let normalized = artist
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
        guard let first = normalized.unicodeScalars.first,
              (65...90).contains(Int(first.value)) else { return "#" }
        return String(first)
    }

    static func sorted(_ copies: [RecordCopy], by order: RecordSort) -> [RecordCopy] {
        // Decode metadata and build comparison strings once per item, not per comparison.
        let keys = Dictionary(copies.map { ($0.id, key($0, order)) }, uniquingKeysWith: { first, _ in first })
        return copies.sorted { a, b in
            if order == .physical {
                if a.shelf?.sortOrder != b.shelf?.sortOrder { return (a.shelf?.sortOrder ?? 0) < (b.shelf?.sortOrder ?? 0) }
                if a.positionInShelf != b.positionInShelf { return a.positionInShelf < b.positionInShelf }
            } else if order == .year, a.release?.year != b.release?.year {
                return (a.release?.year ?? Int.max) < (b.release?.year ?? Int.max)
            }
            let left = keys[a.id] ?? "", right = keys[b.id] ?? ""
            let comparison = left.localizedStandardCompare(right)
            if comparison != .orderedSame { return order == .artistZA ? comparison == .orderedDescending : comparison == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
    }
    private static func key(_ copy: RecordCopy, _ order: RecordSort) -> String {
        guard let r = copy.release else { return "" }
        let artist = r.displayArtist + "\t" + r.displayTitle
        switch order {
        case .genre: return (r.genres.first ?? "") + "\t" + artist
        case .style: return r.primaryStyle + "\t" + artist
        case .label: return r.label + "\t" + r.catalogNumber + "\t" + artist
        default: return artist
        }
    }
    static func matches(_ copy: RecordCopy, query: String) -> Bool {
        guard let r = copy.release else { return false }
        let text = [r.artist, r.title, r.label, r.catalogNumber, r.genres.joined(separator: " "), r.styles.joined(separator: " ")].joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains(String($0)) }
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

struct Placement: Equatable {
    let shelfID: UUID
    let shelfNumber: Int
    let position: Int
    var description: String { "Fach \(shelfNumber) · Position \(position)" }
}
protocol PlacementSuggesting {
    func suggest(for release: Release, shelves: [Shelf]) -> Placement?
}
struct FirstAvailablePlacement: PlacementSuggesting {
    func suggest(for release: Release, shelves: [Shelf]) -> Placement? {
        guard let shelf = shelves.sorted(by: { $0.sortOrder < $1.sortOrder }).first(where: { $0.copies.count < $0.capacity }) else { return nil }
        return Placement(shelfID: shelf.id, shelfNumber: shelf.number, position: shelf.copies.count + 1)
    }
}
