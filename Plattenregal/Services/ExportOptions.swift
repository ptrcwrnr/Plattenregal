import Foundation
import UniformTypeIdentifiers

// MARK: - Options

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv, pdf
    var id: Self { self }
    var title: String {
        switch self {
        case .csv: "CSV"
        case .pdf: "PDF"
        }
    }
    var contentType: UTType {
        switch self {
        case .csv: .commaSeparatedText
        case .pdf: .pdf
        }
    }
}

enum ExportSource: String, CaseIterable, Identifiable {
    /// `sale`: only the records on the "Verkauf" list (settings tab "Listen"),
    /// with the same columns and orders as the collection.
    case collection, wantlist, sale
    var id: Self { self }
    var title: String {
        switch self {
        case .collection: String(localized: "Collection")
        case .wantlist: String(localized: "Wantlist")
        case .sale: String(localized: "Verkaufsliste")
        }
    }
    /// Records standing in shelves (collection, "Verkauf" list) – not the wantlist.
    var hasPlaces: Bool { self != .wantlist }
    /// What the export tab offers: no "Verkauf" list while it is switched off.
    static var offered: [Self] {
        allCases.filter { $0 != .sale || DisplaySettings.saleListEnabled }
    }
}

enum ExportOrder: String, CaseIterable, Identifiable {
    case shelf, artist
    var id: Self { self }
    var title: String {
        switch self {
        case .shelf: String(localized: "Wie im Regal")
        case .artist: String(localized: "Alphabetisch")
        }
    }
}

nonisolated enum ExportDelimiter: String, CaseIterable, Identifiable {
    case semicolon, comma
    var id: Self { self }
    var character: Character { self == .semicolon ? ";" : "," }
    var title: String { self == .semicolon ? String(localized: "Semikolon") : String(localized: "Komma") }
    /// What Excel expects here: a semicolon where the comma is the decimal
    /// separator (German settings), otherwise a comma.
    static var standard: Self { Locale.current.decimalSeparator == "," ? .semicolon : .comma }
}

/// Optional column blocks on top of the release data (artist, title, year …),
/// which every export contains.
enum ExportColumnGroup: String, CaseIterable, Identifiable {
    case location, copy, discogs, tracklist
    var id: Self { self }
    var title: String {
        switch self {
        case .location: String(localized: "Standort im Regal")
        case .copy: String(localized: "Exemplar")
        case .discogs: String(localized: "Discogs-Verweise")
        case .tracklist: String(localized: "Tracklist")
        }
    }
    var hint: String {
        switch self {
        case .location: String(localized: "Regal, Fach und Position")
        case .copy: String(localized: "Discogs-Ordner und Hinzufügedatum")
        case .discogs: String(localized: "Release-ID, Master-ID und Link")
        case .tracklist: String(localized: "Alle Titel in einer Spalte")
        }
    }
    func hint(for source: ExportSource) -> String {
        self == .copy && source == .wantlist ? String(localized: "Hinzufügedatum") : hint
    }
    /// The wantlist has no shelf places.
    func applies(to source: ExportSource) -> Bool { source.hasPlaces || self != .location }
}

struct ExportOptions {
    var source: ExportSource = .collection
    var order: ExportOrder = .shelf
    var groups: Set<ExportColumnGroup> = []
    var delimiter: ExportDelimiter = .standard
}

// MARK: - Table

/// What an export contains, independent of the file format. `section` is the
/// shelf a row belongs to when exporting in shelf order (the PDF's headings).
nonisolated struct ExportTable: Sendable {
    /// `place` is a short "Regal · Fach" for the PDF's column, "–" without one.
    struct Row: Sendable { var section: String?; var values: [String]; var place: String? = nil }
    var columns: [String]
    var rows: [Row]
    func column(_ name: String) -> Int? { columns.firstIndex(of: name) }
}

nonisolated enum ExportColumn {
    static let artist = String(localized: "Interpret"), title = String(localized: "Titel"), year = String(localized: "Jahr"), label = String(localized: "Label")
    static let catalogNumber = String(localized: "Katalognummer"), format = String(localized: "Format"), country = String(localized: "Land")
    static let styles = String(localized: "Stile")
    static let cabinet = String(localized: "Regal"), shelf = String(localized: "Fach"), position = String(localized: "Position")
    static let folder = String(localized: "Ordner"), added = String(localized: "Hinzugefügt")
    static let releaseID = String(localized: "Release-ID"), masterID = String(localized: "Master-ID"), link = String(localized: "Discogs-Link")
    static let tracklist = String(localized: "Tracklist")
}
