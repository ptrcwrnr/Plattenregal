import AppKit
import Foundation
import SwiftData
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
    case collection, wantlist
    var id: Self { self }
    var title: String {
        switch self {
        case .collection: String(localized: "Collection")
        case .wantlist: String(localized: "Wantlist")
        }
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
    func applies(to source: ExportSource) -> Bool { source == .collection || self != .location }
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

/// Builds exports of the collection the app currently mirrors (same account
/// and copies as the collection page) or of that account's wantlist.
struct CollectionExportService {
    let context: ModelContext
    /// How the PDF's shelf headings name the compartments.
    var labelStyle: ShelfLabelStyle = .range

    func table(_ options: ExportOptions) throws -> ExportTable {
        let owner = DiscogsAccount.current(in: try context.fetch(FetchDescriptor<DiscogsAccount>()))?.username
        switch options.source {
        case .collection: return try collectionTable(owner: owner, options: options)
        case .wantlist: return try wantlistTable(owner: owner, options: options)
        }
    }

    /// Number of records an export of `source` would contain.
    func count(_ source: ExportSource) -> Int {
        let owner = DiscogsAccount.current(in: (try? context.fetch(FetchDescriptor<DiscogsAccount>())) ?? [])?.username
        switch source {
        // Counted in the store (same rule as `isInCurrentCollection`), not by loading every copy.
        case .collection:
            var descriptor = FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.discogsActive })
            if let owner {
                descriptor.predicate = #Predicate { $0.discogsActive && $0.discogsOwner == owner }
            }
            return (try? context.fetchCount(descriptor)) ?? 0
        case .wantlist:
            var descriptor = FetchDescriptor<WantlistEntry>()
            if let owner { descriptor.predicate = #Predicate { $0.owner == owner } }
            return (try? context.fetchCount(descriptor)) ?? 0
        }
    }

    private func collectionTable(owner: String?, options: ExportOptions) throws -> ExportTable {
        let copies = try context.fetch(RecordCopy.fetchingReleases()).filter { $0.isInCurrentCollection(owner: owner) }
        let shelves = try context.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
        let labels = ShelfRangeLabels.compute(for: shelves, style: labelStyle)
        let excluded = Set(try context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID))
        let folders = Dictionary(try context.fetch(FetchDescriptor<DiscogsFolder>()).map { ($0.key, $0.name) },
                                 uniquingKeysWith: { first, _ in first })
        let groups = options.groups

        var columns = Self.releaseColumns
        if groups.contains(.location) {
            columns += [ExportColumn.cabinet, ExportColumn.shelf, ExportColumn.position]
        }
        if groups.contains(.copy) {
            columns += [ExportColumn.folder, ExportColumn.added]
        }
        if groups.contains(.discogs) { columns += [ExportColumn.releaseID, ExportColumn.masterID, ExportColumn.link] }
        if groups.contains(.tracklist) { columns.append(ExportColumn.tracklist) }

        let rows = ordered(copies, by: options.order).map { copy in
            var values = Self.releaseValues(copy.release)
            if groups.contains(.location) {
                if let shelf = copy.shelf {
                    values += [shelf.cabinet?.name ?? "", "\(shelf.sortOrder)", shelf.isReserved ? "" : "\(copy.positionInShelf)"]
                } else {
                    // "Nicht im Regal" or "Noch keinem Fach zugeordnet" instead of an empty place.
                    values += ["", ShelfRangeLabels.location(of: copy, labels: labels, excluded: excluded.contains(copy.id)), ""]
                }
            }
            if groups.contains(.copy) {
                values += [copy.discogsFolderID.flatMap { folders["\(copy.discogsOwner)-\($0)"] } ?? "",
                           Self.date(copy.discogsDateAdded)]
            }
            if groups.contains(.discogs) { values += Self.discogsValues(copy.release) }
            if groups.contains(.tracklist) { values.append(Self.tracklist(copy.release)) }
            let section = options.order == .shelf ? copy.shelf.map { sectionTitle($0, labels: labels) } ?? String(localized: "Ohne Fach") : nil
            let place = groups.contains(.location) ? copy.shelf.map { labels.prefix(for: $0) + "\($0.sortOrder)" } ?? "–" : nil
            return ExportTable.Row(section: section, values: values, place: place)
        }
        return ExportTable(columns: columns, rows: rows)
    }

    private func wantlistTable(owner: String?, options: ExportOptions) throws -> ExportTable {
        let entries = try context.fetch(FetchDescriptor<WantlistEntry>()).filter { owner == nil || $0.owner == owner }
        let groups = options.groups
        var columns = Self.releaseColumns
        if groups.contains(.copy) { columns.append(ExportColumn.added) }
        if groups.contains(.discogs) { columns += [ExportColumn.releaseID, ExportColumn.masterID, ExportColumn.link] }
        if groups.contains(.tracklist) { columns.append(ExportColumn.tracklist) }

        // Alphabetical, as the wantlist page in that order (random and
        // "Neueste zuerst" mean nothing in a list to keep).
        let rows = WantlistPresentation.sorted(entries).map { entry in
            var values = Self.releaseValues(entry.release)
            if groups.contains(.copy) {
                values.append(Self.date(entry.dateAdded))
            }
            if groups.contains(.discogs) { values += Self.discogsValues(entry.release) }
            if groups.contains(.tracklist) { values.append(Self.tracklist(entry.release)) }
            return ExportTable.Row(section: nil, values: values)
        }
        return ExportTable(columns: columns, rows: rows)
    }

    /// Shelf order walks cabinet by cabinet, the compartments in reading order and each one front to
    /// back; records without a place follow alphabetically.
    private func ordered(_ copies: [RecordCopy], by order: ExportOrder) -> [RecordCopy] {
        // Same order as the collection page (alphabet index sections, then artist and title).
        let alphabetical = SortingService.sortedByAlphabetSection(copies)
        guard order == .shelf else { return alphabetical }
        // Sort keys read once per record, not per comparison (`Shelf.physicalOrder`
        // plus the position; shelf numbers are unique).
        let placed = copies.compactMap { copy in
            copy.shelf.map { shelf in (copy: copy, key: (shelf.cabinet?.sortOrder ?? 0, shelf.sortOrder, shelf.number, copy.positionInShelf)) }
        }
        .sorted { $0.key < $1.key }
        .map(\.copy)
        return placed + alphabetical.filter { $0.shelf == nil }
    }

    private func shelfLabel(_ shelf: Shelf, labels: ShelfLabels) -> String {
        shelf.isReserved ? (shelf.name.isEmpty ? String(localized: "Gesperrtes Fach") : shelf.name) : labels[shelf.id] ?? ""
    }

    private func sectionTitle(_ shelf: Shelf, labels: ShelfLabels) -> String {
        let label = shelfLabel(shelf, labels: labels)
        let name = labels.prefix(for: shelf) + shelf.numberText
        return label.isEmpty || label == shelf.numberText ? name : "\(name) · \(label)"
    }

    // MARK: Values

    private static let releaseColumns = [ExportColumn.artist, ExportColumn.title, ExportColumn.year, ExportColumn.label,
                                         ExportColumn.catalogNumber, ExportColumn.format, ExportColumn.country,
                                         ExportColumn.styles]

    private static func releaseValues(_ release: Release?) -> [String] {
        guard let release else { return Array(repeating: "", count: releaseColumns.count) }
        return [release.displayArtist, release.displayTitle, release.year.map(String.init) ?? "",
                listedOnce(release.displayLabel), catalogNumber(release.catalogNumber), format(release.format), release.country,
                release.styles.joined(separator: ", ")]
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

    private static func discogsValues(_ release: Release?) -> [String] {
        guard let release else { return ["", "", ""] }
        // Discogs sends master ID 0 for a release without a master.
        return ["\(release.discogsID)", release.masterID.flatMap { $0 > 0 ? String($0) : nil } ?? "", release.sourceURL?.absoluteString ?? ""]
    }

    private static func tracklist(_ release: Release?) -> String {
        (release?.tracks ?? []).map { track in
            let head = [track.position, track.title].filter { !$0.isEmpty }.joined(separator: " ")
            return track.duration.isEmpty ? head : "\(head) (\(track.duration))"
        }
        .joined(separator: " / ")
    }

    /// ISO dates sort and import cleanly in every spreadsheet app. The local
    /// day, as the app shows it – the ISO style alone would use UTC.
    private static func date(_ raw: String?) -> String {
        DiscogsDate.parse(raw).map { ExportDate.day($0) } ?? ""
    }
}

/// "2026-09-24" in the given (by default the user's) time zone, for file
/// names and date cells.
enum ExportDate {
    static func day(_ date: Date, in timeZone: TimeZone = .current) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
    }
}

// MARK: - CSV

nonisolated enum CSVWriter {
    /// RFC 4180 with a byte order mark, so Excel opens umlauts correctly.
    /// Semicolons are what Excel expects with German regional settings.
    static func data(for table: ExportTable, delimiter: ExportDelimiter) -> Data {
        var text = line(table.columns, delimiter: delimiter.character)
        for row in table.rows { text += line(row.values, delimiter: delimiter.character) }
        return Data("\u{FEFF}".utf8) + Data(text.utf8)
    }

    static func line(_ values: [String], delimiter: Character) -> String {
        values.map { escape($0, delimiter: delimiter) }.joined(separator: String(delimiter)) + "\r\n"
    }

    static func escape(_ value: String, delimiter: Character) -> String {
        let value = defused(value)
        let needsQuotes = value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r")
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Excel and Numbers evaluate cells starting with = + - @ as formulas:
    /// an artist like "-M-" would turn into an error, a note like
    /// "=HYPERLINK(…)" into a live link. A leading apostrophe keeps them text.
    /// Plain numbers ("-5") stay untouched.
    static func defused(_ value: String) -> String {
        guard let first = value.first, "=+-@".contains(first) || first == "\t" || first == "\r" else { return value }
        if first == "-" || first == "+", Double(value) != nil { return value }
        return "'" + value
    }
}

// MARK: - PDF

/// A printable list on A4 landscape: title, then the records as a table.
/// In shelf order every compartment gets its own heading; long values are
/// cut to one line so the list stays scannable.
nonisolated enum PDFListWriter {
    private static let page = CGRect(x: 0, y: 0, width: 842, height: 595)
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 15
    private static let sectionHeight: CGFloat = 26

    /// Columns and their share of the line width; only those present in the table are drawn.
    private static let layout: [(name: String, width: CGFloat)] = [
        (ExportColumn.position, 0.05), (ExportColumn.artist, 0.21), (ExportColumn.title, 0.23),
        (ExportColumn.year, 0.04), (ExportColumn.label, 0.15), (ExportColumn.catalogNumber, 0.11),
        (ExportColumn.format, 0.15), (ExportColumn.shelf, 0.08),
    ]

    static func data(for table: ExportTable, title: String, subtitle: String) throws -> Data {
        let grouped = table.rows.contains { $0.section != nil }
        // Grouped by shelf, the heading already names the shelf.
        let columns = layout.filter { grouped ? $0.name != ExportColumn.shelf : $0.name != ExportColumn.position }
            .compactMap { column in table.column(column.name).map { (column.name, column.width, $0) } }
        let total = columns.reduce(0) { $0 + $1.1 }
        let width = page.width - 2 * margin
        var x = margin
        let cells = columns.map { name, share, index in
            defer { x += width * share / total }
            return (name: name, index: index, x: x, width: width * share / total - 6)
        }

        let data = NSMutableData()
        var box = page
        let info = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Plattenregal"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, info) else { throw CocoaError(.fileWriteUnknown) }
        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }

        var pageNumber = 0
        var y: CGFloat = 0
        let bottom = page.height - margin - 14

        func endPage() {
            draw(String(localized: "Seite \(pageNumber)"), in: CGRect(x: margin, y: page.height - margin, width: width, height: 12),
                 font: .systemFont(ofSize: 8), color: .secondaryLabelColor, alignment: .right)
            pdf.endPDFPage()
        }
        func beginPage() {
            if pageNumber > 0 { endPage() }
            pageNumber += 1
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: 0, y: page.height)
            pdf.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)
            y = margin
            if pageNumber == 1 {
                draw(title, in: CGRect(x: margin, y: y, width: width, height: 24), font: .boldSystemFont(ofSize: 18))
                y += 24
                draw(subtitle, in: CGRect(x: margin, y: y, width: width, height: 14), font: .systemFont(ofSize: 9), color: .secondaryLabelColor)
                y += 24
            }
            header()
        }
        func header() {
            for cell in cells {
                draw(cell.name, in: CGRect(x: cell.x, y: y, width: cell.width, height: rowHeight), font: .boldSystemFont(ofSize: 8), color: .secondaryLabelColor)
            }
            y += rowHeight
            pdf.setFillColor(NSColor(white: 0.75, alpha: 1).cgColor)
            pdf.fill(CGRect(x: margin, y: y - 3, width: width, height: 0.5))
        }
        func section(_ title: String) {
            y += 6
            draw(title, in: CGRect(x: margin, y: y, width: width, height: 16), font: .boldSystemFont(ofSize: 11))
            y += sectionHeight - 6
        }

        beginPage()
        var currentSection: String?
        var stripe = false
        for row in table.rows {
            let startsSection = grouped && row.section != currentSection
            // Keep a heading together with its first record.
            if y + rowHeight + (startsSection ? sectionHeight : 0) > bottom {
                beginPage()
                if grouped, !startsSection, let currentSection { section(currentSection + String(localized: " (Fortsetzung)")) }
            }
            if startsSection {
                currentSection = row.section
                section(row.section ?? "")
                stripe = false
            }
            if stripe {
                pdf.setFillColor(NSColor.black.withAlphaComponent(0.04).cgColor)
                pdf.fill(CGRect(x: margin - 4, y: y - 1, width: width + 8, height: rowHeight))
            }
            stripe.toggle()
            for cell in cells {
                let value = cell.name == ExportColumn.shelf ? row.place ?? row.values[cell.index] : row.values[cell.index]
                draw(value, in: CGRect(x: cell.x, y: y, width: cell.width, height: rowHeight), font: .systemFont(ofSize: 8.5))
            }
            y += rowHeight
        }
        if table.rows.isEmpty {
            draw(String(localized: "Keine Einträge"), in: CGRect(x: margin, y: y + 8, width: width, height: 14), font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
        }
        endPage()
        pdf.closePDF()
        return data as Data
    }

    private static func draw(_ text: String, in rect: CGRect, font: NSFont, color: NSColor = .black,
                             alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = alignment
        // Fixed colours: a printout has no dark mode.
        let resolved = color == .secondaryLabelColor ? NSColor(white: 0.4, alpha: 1) : color
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: resolved, .paragraphStyle: style])
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
