import Foundation
import SwiftData

enum LibraryError: LocalizedError {
    case reserved, invalidPosition, missingRelease, reservedNotEmpty
    /// Saving "Nicht auffindbar" / "Wieder gefunden" failed; the database
    /// error is kept for the protocol.
    case missingMarkNotSaved(found: Bool, any Error)
    var errorDescription: String? {
        switch self {
        case .missingMarkNotSaved(let found, _):
            "\(found ? "„Wieder gefunden“" : "„Nicht auffindbar“") konnte nicht gespeichert werden – die Platte ist unverändert. Bitte versuche es noch einmal. Klappt es weiterhin nicht, starte Plattenregal neu."
        case .reserved: "Dieses Fach ist gesperrt und nimmt keine Platten auf. Die Sperre lässt sich in den Fachoptionen aufheben."
        case .invalidPosition: "Diese Position gibt es in dem Fach nicht. Wähle eine Zahl zwischen 1 und der Stelle direkt hinter der letzten Platte."
        case .missingRelease: "Die Platte oder das Fach gibt es nicht mehr – vielleicht wurde gerade etwas geändert. Bitte versuche es noch einmal."
        case .reservedNotEmpty: "Ein Fach mit Platten lässt sich nicht sperren. Nimm die Platten zuerst heraus."
        }
    }
}

// All position writes run on the main actor and are saved as one transaction.
struct PositionService {
    let context: ModelContext
    func ordered(_ shelf: Shelf, excluding id: UUID? = nil) -> [RecordCopy] {
        Self.inShelfOrder(shelf.copies, excluding: id)
    }
    /// By position, ties by ID. Position and ID are read once per record, not
    /// per comparison: every SwiftData property read goes through the store.
    static func inShelfOrder(_ copies: [RecordCopy], excluding id: UUID? = nil) -> [RecordCopy] {
        copies.compactMap { copy -> (copy: RecordCopy, position: Int, id: UUID)? in
            let copyID = copy.id
            return copyID == id ? nil : (copy, copy.positionInShelf, copyID)
        }
        .sorted { $0.position != $1.position ? $0.position < $1.position : $0.id.uuidString < $1.id.uuidString }
        .map(\.copy)
    }
    /// Writes only positions that change: an unchanged record stays out of the
    /// save, so SwiftData doesn't reload its release for the next reader.
    private func renumber(_ copies: [RecordCopy]) {
        for (index, copy) in copies.enumerated() where copy.positionInShelf != index + 1 { copy.positionInShelf = index + 1 }
    }
    func save(_ action: () throws -> Void) throws {
        do { try action(); try context.save() }
        catch { context.rollback(); throw error }
        ShelfAutoBackup.shared.scheduleBackup(of: context.container)
        LibraryChanges.shared.placementsDidChange()
    }
    func validate(shelf: Shelf, position: Int, excluding id: UUID? = nil) throws {
        let count = ordered(shelf, excluding: id).count
        guard !shelf.isReserved else { throw LibraryError.reserved }
        guard (1...(count + 1)).contains(position) else { throw LibraryError.invalidPosition }
    }
    #if DEBUG
    /// Adds a new copy – for previews and tests only: in the app every record
    /// comes from the Discogs sync. Without a shelf it starts out "ohne Fach".
    @discardableResult func insert(release: Release, shelf: Shelf?, position: Int = 1,
                                    instanceID: Int = .random(in: 1...Int(Int32.max)), owner: String = "Demo",
                                    configure: (RecordCopy) -> Void = { _ in }) throws -> RecordCopy {
        if let shelf { try validate(shelf: shelf, position: position) }
        var result: RecordCopy!
        try save {
            var copies = shelf.map { ordered($0) } ?? []
            context.insert(release)
            let copy = RecordCopy(release: release, instanceID: instanceID, owner: owner,
                                  shelf: shelf, position: shelf == nil ? 0 : position)
            context.insert(copy); configure(copy)
            if shelf != nil { copies.insert(copy, at: position - 1); renumber(copies) }
            result = copy
        }
        return result
    }
    #endif
    /// `found`: the record was just taken in hand and put there (sorting in),
    /// so a "Nicht auffindbar" mark goes in the same transaction. Plain
    /// moves (quick editor, undo) keep the mark.
    func move(_ copy: RecordCopy, to shelf: Shelf, position: Int, found: Bool = false, edit: () -> Void = {}) throws {
        try validate(shelf: shelf, position: position, excluding: copy.id)
        let from = copy.shelf.map { "\(Self.name($0)), Position \(copy.positionInShelf)" } ?? "ohne Fach"
        var foundAgain = false
        try save {
            let oldShelf = copy.shelf
            var destination = ordered(shelf, excluding: copy.id)
            copy.shelf = shelf
            destination.insert(copy, at: position - 1)
            if let oldShelf, oldShelf.id != shelf.id { renumber(ordered(oldShelf, excluding: copy.id)) }
            renumber(destination); edit()
            try markExcluded([copy.id], false)
            if found { foundAgain = try markMissing([copy.id], false) }
        }
        AppLog.info("Regal", "\(Self.name(copy)): \(from) → \(Self.name(shelf)), Position \(position)\(foundAgain ? " · nicht mehr „Nicht auffindbar“" : "")")
    }
    func unplace(_ copy: RecordCopy, edit: () -> Void = {}) throws {
        let from = copy.shelf.map(Self.name) ?? "ohne Fach"
        try save {
            let oldShelf = copy.shelf
            copy.shelf = nil; copy.positionInShelf = 0
            if let oldShelf { renumber(ordered(oldShelf, excluding: copy.id)) }
            edit()
        }
        AppLog.info("Regal", "\(Self.name(copy)) aus \(from) genommen")
    }
    /// Takes several copies out of their shelves in one transaction: either all
    /// of them leave and every affected shelf closes its gaps, or none does.
    func unplace(_ copies: [RecordCopy]) throws {
        try save {
            let ids = Set(copies.map(\.id))
            let sources = Dictionary(copies.compactMap { c in c.shelf.map { ($0.id, $0) } }, uniquingKeysWith: { a, _ in a }).values
            for copy in copies { copy.shelf = nil; copy.positionInShelf = 0 }
            for shelf in sources { renumber(ordered(shelf).filter { !ids.contains($0.id) }) }
        }
        AppLog.info("Regal", "\(copies.count) Platte(n) gesammelt aus dem Regal genommen: \(copies.map(Self.name).joined(separator: ", "))")
    }
    /// Takes copies out of the shelf allocation entirely ("Nicht im Regal") or
    /// back in. Excluded copies are removed from their shelf and no longer count
    /// as waiting to be sorted in. Stored as `OptimizationExclusion` rows.
    func setExcluded(_ copies: [RecordCopy], _ excluded: Bool, edit: () -> Void = {}) throws {
        try save {
            if excluded {
                let sources = Dictionary(copies.compactMap { c in c.shelf.map { ($0.id, $0) } }, uniquingKeysWith: { a, _ in a }).values
                let ids = Set(copies.map(\.id))
                for copy in copies { copy.shelf = nil; copy.positionInShelf = 0 }
                for shelf in sources { renumber(ordered(shelf).filter { !ids.contains($0.id) }) }
            }
            try markExcluded(Set(copies.map(\.id)), excluded)
            // Deliberately kept out of the shelves: nothing left to look for.
            if excluded, try markMissing(Set(copies.map(\.id)), false) {
                AppLog.info("Regal", "„Nicht auffindbar“ aufgehoben, weil „Nicht im Regal“ gesetzt wurde")
            }
            edit()
        }
        AppLog.info("Regal", "\(excluded ? "Nicht im Regal" : "Wieder fürs Regal vorgesehen"): \(copies.map(Self.name).joined(separator: ", "))")
    }
    private func markExcluded(_ ids: Set<UUID>, _ excluded: Bool) throws {
        let existing = try context.fetch(FetchDescriptor<OptimizationExclusion>())
        if excluded {
            let present = Set(existing.map(\.copyID))
            for id in ids.subtracting(present) { context.insert(OptimizationExclusion(copyID: id)) }
        } else {
            for row in existing where ids.contains(row.copyID) { context.delete(row) }
        }
    }
    /// Marks copies as "Nicht auffindbar" (they should stand in their shelf
    /// but weren't found there) or as found again. Only a note for the shelf
    /// page: shelf and position stay untouched. Stored as `MissingCopyMark` rows.
    func setMissing(_ copies: [RecordCopy], _ missing: Bool) throws {
        do { try save { _ = try markMissing(Set(copies.map(\.id)), missing) } }
        catch { throw LibraryError.missingMarkNotSaved(found: !missing, error) }
        AppLog.info("Regal", "\(missing ? "Nicht auffindbar" : "Wieder gefunden"): \(copies.map(Self.name).joined(separator: ", "))")
    }
    /// Whether any mark changed, so callers can note it in the protocol.
    @discardableResult private func markMissing(_ ids: Set<UUID>, _ missing: Bool) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<MissingCopyMark>())
        if missing {
            let added = ids.subtracting(existing.map(\.copyID))
            for id in added { context.insert(MissingCopyMark(copyID: id)) }
            return !added.isEmpty
        }
        let cleared = existing.filter { ids.contains($0.copyID) }
        for row in cleared { context.delete(row) }
        return !cleared.isEmpty
    }
    func delete(_ copy: RecordCopy) throws {
        let description = "\(Self.name(copy)) aus \(copy.shelf.map(Self.name) ?? "ohne Fach")"
        try save {
            let shelf = copy.shelf; let release = copy.release
            let remaining = shelf.map { ordered($0, excluding: copy.id) } ?? []
            let isLast = release?.copies.filter { $0.id != copy.id }.isEmpty ?? false
            copy.shelf = nil; copy.release = nil; context.delete(copy)
            try markExcluded([copy.id], false)
            try markMissing([copy.id], false)
            renumber(remaining)
            if isLast, let release {
                let wants = try context.fetch(FetchDescriptor<WantlistEntry>())
                if !wants.contains(where: { $0.release?.id == release.id }) { context.delete(release) }
            }
        }
        AppLog.info("Regal", "Gelöscht: \(description)")
    }
    func normalize(_ shelf: Shelf) throws { try save { renumber(ordered(shelf)) } }
    func sort(_ shelf: Shelf, by order: RecordSort) throws {
        try save { renumber(SortingService.sorted(shelf.copies, by: order)) }
        AppLog.info("Regal", "\(Self.name(shelf)) neu sortiert (\(order))")
    }
    func configure(_ shelf: Shelf, name: String, isReserved: Bool) throws {
        guard !isReserved || shelf.copies.isEmpty else { throw LibraryError.reservedNotEmpty }
        try save {
            shelf.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            shelf.isReserved = isReserved
        }
        AppLog.info("Regal", "\(Self.name(shelf)): \(isReserved ? "gesperrt" : "nicht gesperrt")\(shelf.name.isEmpty ? "" : ", Name „\(shelf.name)“")")
    }

    /// For the protocol: which record, which compartment.
    static func name(_ copy: RecordCopy) -> String {
        "„\(copy.release?.displayArtist ?? "?") – \(copy.release?.displayTitle ?? "?")“"
    }
    static func name(_ shelf: Shelf) -> String {
        shelf.cabinet.map { "\($0.name) · \(shelf.numberText)" } ?? shelf.numberText
    }
}

#if DEBUG
extension Release {
    /// Previews and tests: a release with a random Discogs ID (in the app
    /// every release comes from Discogs with its real one).
    convenience init(artist: String, title: String) {
        self.init(discogsID: .random(in: 1_000_000...Int(Int32.max)), artist: artist, title: title)
    }
}
#endif
