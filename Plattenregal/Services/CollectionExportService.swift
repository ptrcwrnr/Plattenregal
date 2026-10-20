import Foundation
import SwiftData

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
        case .sale: return try collectionTable(owner: owner, options: options, only: try saleIDs())
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
        case .sale:
            // Counted in the store as well: the export tab asks on every redraw.
            guard let ids = (try? saleIDs()).map(Array.init), !ids.isEmpty else { return 0 }
            return (try? context.fetchCount(FetchDescriptor<RecordCopy>(predicate: #Predicate { ids.contains($0.id) }))) ?? 0
        }
    }

    private func saleIDs() throws -> Set<UUID> {
        Set(try context.fetch(FetchDescriptor<SaleCopyMark>()).map(\.copyID))
    }

    /// `only`: just these copies – the "Verkauf" list, as the settings show
    /// it (every marked record, also one that has left the Discogs collection
    /// meanwhile: it is still to be sold).
    private func collectionTable(owner: String?, options: ExportOptions, only: Set<UUID>? = nil) throws -> ExportTable {
        let copies = try context.fetch(RecordCopy.fetchingReleases()).filter { copy in
            only.map { $0.contains(copy.id) } ?? copy.isInCurrentCollection(owner: owner)
        }
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

        let rows = ordered(copies, by: options.order, excluded: excluded).map { copy in
            var values = Self.releaseValues(copy.release)
            if groups.contains(.location) {
                if let shelf = copy.shelf {
                    values += [shelf.cabinet?.name ?? "", "\(shelf.sortOrder)", shelf.isReserved ? "" : "\(copy.positionInShelf)"]
                } else {
                    // "Ohne Regalplatz" or "Noch nicht einsortiert" instead of an empty place.
                    values += ["", ShelfRangeLabels.location(of: copy, labels: labels, excluded: excluded.contains(copy.id)), ""]
                }
            }
            if groups.contains(.copy) {
                values += [copy.discogsFolderID.flatMap { folders["\(copy.discogsOwner)-\($0)"] } ?? "",
                           Self.date(copy.discogsDateAdded)]
            }
            if groups.contains(.discogs) { values += Self.discogsValues(copy.release) }
            if groups.contains(.tracklist) { values.append(Self.tracklist(copy.release)) }
            // Kept out of the shelves on purpose is not "waiting to be sorted in": a heading of its own.
            let section = options.order == .shelf ? copy.shelf.map { sectionTitle($0, labels: labels) }
                ?? (excluded.contains(copy.id) ? String(localized: "Ohne Regalplatz") : String(localized: "Noch nicht einsortiert")) : nil
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
    /// back; records without a place follow alphabetically – first those still
    /// to be sorted in, then those kept out of the shelves ("Ohne Regalplatz"),
    /// so each group stands under its own heading.
    private func ordered(_ copies: [RecordCopy], by order: ExportOrder, excluded: Set<UUID>) -> [RecordCopy] {
        // Same order as the collection page (alphabet index sections, then artist and title).
        guard order == .shelf else { return SortingService.sortedByAlphabetSection(copies) }
        // Sort keys read once per record, not per comparison (`Shelf.physicalOrder`
        // plus the position; shelf numbers are unique).
        let placed = copies.compactMap { copy in
            copy.shelf.map { shelf in (copy: copy, key: (shelf.cabinet?.sortOrder ?? 0, shelf.sortOrder, shelf.number, copy.positionInShelf)) }
        }
        .sorted { $0.key < $1.key }
        .map(\.copy)
        // Only the records without a place are put in alphabetical order.
        let unplaced = copies.filter { $0.shelf == nil }
        return placed + SortingService.sortedByAlphabetSection(unplaced.filter { !excluded.contains($0.id) })
            + SortingService.sortedByAlphabetSection(unplaced.filter { excluded.contains($0.id) })
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
