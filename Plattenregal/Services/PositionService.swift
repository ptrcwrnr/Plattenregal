import Foundation
import SwiftData

enum LibraryError: LocalizedError {
    case reserved, invalidPosition, missingRelease, reservedNotEmpty
    /// Saving "Gesucht" / "Wieder gefunden" failed; the database
    /// error is kept for the protocol.
    case missingMarkNotSaved(found: Bool, any Error)
    /// "Reihenfolge übernehmen" (Sortierung prüfen) couldn't be saved.
    case orderNotSaved(any Error)
    /// A history entry that can't be undone (any more), see `ShelfHistory.Blocker`.
    case undoNotPossible(ShelfHistory.Blocker)
    var errorDescription: String? {
        switch self {
        case .undoNotPossible(let blocker): blocker.message
        case .orderNotSaved:
            String(localized: "Die neue Reihenfolge konnte nicht gespeichert werden – das Fach ist unverändert. Bitte versuche es noch einmal. Klappt es weiterhin nicht, starte Plattenregal neu.")
        case .missingMarkNotSaved(let found, _):
            String(localized: "\(found ? String(localized: "„Wieder gefunden“") : String(localized: "„Gesucht“")) konnte nicht gespeichert werden – die Platte ist unverändert. Bitte versuche es noch einmal. Klappt es weiterhin nicht, starte Plattenregal neu.")
        case .reserved: String(localized: "Dieses Fach ist gesperrt und nimmt keine Platten auf. Per Rechtsklick auf das Fach lässt es sich entsperren.")
        case .invalidPosition: String(localized: "Diese Position gibt es in dem Fach nicht. Wähle eine Zahl zwischen 1 und der Stelle direkt hinter der letzten Platte.")
        case .missingRelease: String(localized: "Die Platte oder das Fach gibt es nicht mehr – vielleicht wurde gerade etwas geändert. Bitte versuche es noch einmal.")
        case .reservedNotEmpty: String(localized: "Ein Fach mit Platten lässt sich nicht sperren. Nimm die Platten zuerst heraus.")
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
    /// Takes the copies out of their shelves and closes the gaps they leave
    /// behind, each affected shelf once. Runs inside a `save`.
    private func takeOut(_ copies: [RecordCopy]) {
        let ids = Set(copies.map(\.id))
        let sources = Dictionary(copies.compactMap { c in c.shelf.map { ($0.id, $0) } }, uniquingKeysWith: { a, _ in a }).values
        for copy in copies { copy.shelf = nil; copy.positionInShelf = 0 }
        for shelf in sources { renumber(ordered(shelf).filter { !ids.contains($0.id) }) }
    }
    /// `layoutChanged: false` for writes that touch neither places nor
    /// anything a backup holds ("Gesucht" marks): no backup run, no new labels.
    func save(layoutChanged: Bool = true, _ action: () throws -> Void) throws {
        do { try action(); try context.save() }
        catch { context.rollback(); throw error }
        guard layoutChanged else { return }
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
    /// so a "Gesucht" mark goes in the same transaction. Plain
    /// moves (quick editor) keep the mark. Every move goes into the history
    /// ("Verlauf", see `ShelfHistory`), in the same transaction.
    func move(_ copy: RecordCopy, to shelf: Shelf, position: Int, found: Bool = false) throws {
        try validate(shelf: shelf, position: position, excluding: copy.id)
        let from = copy.shelf.map { "\(Self.name($0)), Position \(copy.positionInShelf)" } ?? "ohne Fach"
        var foundAgain = false
        try save {
            let oldShelf = copy.shelf, oldPosition = copy.positionInShelf
            var destination = ordered(shelf, excluding: copy.id)
            copy.shelf = shelf
            destination.insert(copy, at: position - 1)
            if let oldShelf, oldShelf.id != shelf.id { renumber(ordered(oldShelf, excluding: copy.id)) }
            renumber(destination)
            let wasExcluded = try markExcluded([copy.id], false)
            if found { foundAgain = try markMissing([copy.id], false) }
            // Put down where it stood: nothing happened.
            if oldShelf?.id != shelf.id || oldPosition != position {
                record(copy, from: oldShelf, position: oldPosition, to: shelf, position: position,
                       clearedMissing: foundAgain, clearedExclusion: wasExcluded)
            }
        }
        AppLog.info("Regal", "\(Self.name(copy)): \(from) → \(Self.name(shelf)), Position \(position)\(foundAgain ? " · nicht mehr auf der Suchliste" : "")")
    }
    /// The history entry it wrote, for the "Aus Fach entfernt" toast.
    @discardableResult func unplace(_ copy: RecordCopy) throws -> ShelfHistoryEntry? {
        let from = copy.shelf.map(Self.name) ?? "ohne Fach"
        var entry: ShelfHistoryEntry?
        try save {
            let oldShelf = copy.shelf, oldPosition = copy.positionInShelf
            copy.shelf = nil; copy.positionInShelf = 0
            if let oldShelf {
                renumber(ordered(oldShelf, excluding: copy.id))
                entry = record(copy, from: oldShelf, position: oldPosition, to: nil, position: 0)
            }
        }
        AppLog.info("Regal", "\(Self.name(copy)) aus \(from) genommen")
        return entry
    }
    /// Takes several copies out of their shelves in one transaction: either all
    /// of them leave and every affected shelf closes its gaps, or none does.
    func unplace(_ copies: [RecordCopy]) throws {
        // The confirmation may come after the last one left by other means.
        guard !copies.isEmpty else { return }
        try save {
            for copy in copies {
                if let shelf = copy.shelf { record(copy, from: shelf, position: copy.positionInShelf, to: nil, position: 0) }
            }
            takeOut(copies)
        }
        AppLog.info("Regal", "\(copies.count) Platte(n) gesammelt aus dem Regal genommen: \(copies.map(Self.name).joined(separator: ", "))")
    }
    /// Takes copies out of the shelf allocation entirely ("Ohne Regalplatz") or
    /// back in. Excluded copies are removed from their shelf and no longer count
    /// as waiting to be sorted in. Stored as `OptimizationExclusion` rows.
    func setExcluded(_ copies: [RecordCopy], _ excluded: Bool) throws {
        try save {
            if excluded { takeOut(copies) }
            try markExcluded(Set(copies.map(\.id)), excluded)
            // Deliberately kept out of the shelves: nothing left to look for.
            if excluded, try markMissing(Set(copies.map(\.id)), false) {
                AppLog.info("Regal", "Von der Suchliste genommen, weil „Ohne Regalplatz“ gesetzt wurde")
            }
        }
        AppLog.info("Regal", "\(excluded ? "Ohne Regalplatz" : "Wieder fürs Regal vorgesehen"): \(copies.map(Self.name).joined(separator: ", "))")
    }
    /// Whether any mark changed (a move into a shelf lifts "Ohne Regalplatz";
    /// the history keeps that, so undoing puts it back).
    @discardableResult private func markExcluded(_ ids: Set<UUID>, _ excluded: Bool) throws -> Bool {
        let existing = try context.fetch(FetchDescriptor<OptimizationExclusion>())
        if excluded {
            let added = ids.subtracting(existing.map(\.copyID))
            for id in added { context.insert(OptimizationExclusion(copyID: id)) }
            return !added.isEmpty
        }
        let cleared = existing.filter { ids.contains($0.copyID) }
        for row in cleared { context.delete(row) }
        return !cleared.isEmpty
    }
    /// Marks copies as "Gesucht" (they should stand in their shelf
    /// but weren't found there) or as found again. Only a note for the shelf
    /// page: shelf and position stay untouched. Stored as `MissingCopyMark` rows.
    func setMissing(_ copies: [RecordCopy], _ missing: Bool) throws {
        // Marks aren't part of a backup, and no place changes.
        do { try save(layoutChanged: false) { _ = try markMissing(Set(copies.map(\.id)), missing) } }
        catch { throw LibraryError.missingMarkNotSaved(found: !missing, error) }
        AppLog.info("Regal", "\(missing ? "Auf die Suchliste" : "Wieder gefunden"): \(copies.map(Self.name).joined(separator: ", "))")
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
    /// Puts copies on the "Verkauf" list (to be sold some day) or takes them
    /// off it. Only a note: shelf and position stay untouched, and it isn't
    /// part of a backup. Stored as `SaleCopyMark` rows.
    func setForSale(_ copies: [RecordCopy], _ forSale: Bool) throws {
        try save(layoutChanged: false) { try markForSale(Set(copies.map(\.id)), forSale) }
        AppLog.info("Regal", "\(forSale ? "Zum Verkauf vorgemerkt" : "Nicht mehr zum Verkauf"): \(copies.map(Self.name).joined(separator: ", "))")
    }
    private func markForSale(_ ids: Set<UUID>, _ forSale: Bool) throws {
        let existing = try context.fetch(FetchDescriptor<SaleCopyMark>())
        if forSale {
            for id in ids.subtracting(existing.map(\.copyID)) { context.insert(SaleCopyMark(copyID: id)) }
        } else {
            for row in existing where ids.contains(row.copyID) { context.delete(row) }
        }
    }
    /// "Verkauft": the whole "Verkauf" list at once. The records leave
    /// their shelves and are kept out of them ("Ohne Regalplatz"), so they
    /// aren't offered for sorting in while they are still in the Discogs
    /// collection; the list is emptied. One transaction.
    func sellAllForSale() throws {
        var sold: [RecordCopy] = []
        try save {
            let marks = try context.fetch(FetchDescriptor<SaleCopyMark>())
            let ids = Set(marks.map(\.copyID))
            sold = try context.fetch(FetchDescriptor<RecordCopy>()).filter { ids.contains($0.id) }
            takeOut(sold)
            try markExcluded(Set(sold.map(\.id)), true)
            try markMissing(ids, false)
            // Marks of records a sync removed meanwhile go as well.
            for row in marks { context.delete(row) }
        }
        AppLog.info("Regal", "Verkauf abgeschlossen, aus dem Regal genommen und „Ohne Regalplatz“: \(sold.map(Self.name).joined(separator: ", "))")
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
            try markForSale([copy.id], false)
            renumber(remaining)
            if isLast, let release {
                let wants = try context.fetch(FetchDescriptor<WantlistEntry>())
                if !wants.contains(where: { $0.release?.id == release.id }) { context.delete(release) }
            }
        }
        AppLog.info("Regal", "Gelöscht: \(description)")
    }
    /// Puts the shelf's records in alphabetical order (artist, then the
    /// chosen order for one artist's records, see `ShelfSecondaryOrder`).
    func sortAlphabetically(_ shelf: Shelf, by order: ShelfSecondaryOrder = .current) throws {
        let sorted = ShelfSortCheck.sortedCopies(shelf.copies, by: order)
        let moved = sorted.enumerated().filter { $1.positionInShelf != $0 + 1 }.count
        do { try save { renumber(sorted) } }
        catch { throw LibraryError.orderNotSaved(error) }
        AppLog.info("Regal", "\(Self.name(shelf)) sortiert nach Interpret, dann \(order.title): \(moved) von \(sorted.count) Positionen geändert")
    }
    func configure(_ shelf: Shelf, name: String, isReserved: Bool) throws {
        guard !isReserved || shelf.copies.isEmpty else { throw LibraryError.reservedNotEmpty }
        try save {
            shelf.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            shelf.isReserved = isReserved
        }
        AppLog.info("Regal", "\(Self.name(shelf)): \(isReserved ? "gesperrt" : "nicht gesperrt")\(shelf.name.isEmpty ? "" : ", Name „\(shelf.name)“")")
    }

    // MARK: History ("Verlauf")

    /// Notes a change of place in the history; runs inside a `save`.
    @discardableResult private func record(_ copy: RecordCopy, from: Shelf?, position fromPosition: Int, to: Shelf?, position toPosition: Int,
                                           clearedMissing: Bool = false, clearedExclusion: Bool = false) -> ShelfHistoryEntry {
        let entry = ShelfHistoryEntry(
            copyID: copy.id, artist: copy.release?.displayArtist ?? "", title: copy.release?.displayTitle ?? "",
            fromShelfID: from?.id, fromPosition: from == nil ? 0 : fromPosition, fromName: from.map(Self.name) ?? "",
            toShelfID: to?.id, toPosition: to == nil ? 0 : toPosition, toName: to.map(Self.name) ?? "",
            clearedMissing: clearedMissing, clearedExclusion: clearedExclusion)
        context.insert(entry)
        return entry
    }

    /// Takes a change back: the record returns to where it stood before –
    /// its old compartment and position (or out of the shelves again, with
    /// "Gesucht" or "Ohne Regalplatz" as before). Only while the record still
    /// stands where the change put it, and only the newest change of a
    /// record; the entry stays in the history, marked as undone. One transaction.
    func undo(_ entry: ShelfHistoryEntry) throws {
        let check = try ShelfHistory.check(entry, in: context)
        if let blocker = check.blocker { throw LibraryError.undoNotPossible(blocker) }
        guard let copy = check.copy else { throw LibraryError.undoNotPossible(.recordGone) }
        let back = check.fromShelf
        var position = 0
        try save {
            let current = copy.shelf
            if let back {
                var destination = ordered(back, excluding: copy.id)
                position = min(max(entry.fromPosition, 1), destination.count + 1)
                copy.shelf = back
                destination.insert(copy, at: position - 1)
                if let current, current.id != back.id { renumber(ordered(current, excluding: copy.id)) }
                renumber(destination)
            } else {
                copy.shelf = nil; copy.positionInShelf = 0
                if let current { renumber(ordered(current, excluding: copy.id)) }
            }
            if entry.clearedMissing { try markMissing([copy.id], true) }
            if entry.clearedExclusion { try markExcluded([copy.id], true) }
            entry.undoneAt = .now
        }
        let to = back.map { "\(Self.name($0)), Position \(position)" } ?? "ohne Fach"
        AppLog.info("Regal", "Rückgängig: \(Self.name(copy)) wieder \(to)\(entry.clearedMissing ? " · wieder auf der Suchliste" : "")\(entry.clearedExclusion ? " · wieder „Ohne Regalplatz“" : "")")
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
