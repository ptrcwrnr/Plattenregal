import Foundation
import SwiftData

/// The shelf page's "Verlauf": every record sorted in, moved or taken out,
/// newest first. `PositionService` writes an entry in the same transaction as
/// the change itself and takes it back with `undo`. An entry can be undone
/// while the record still stands where the change put it and no later change
/// of the same record is open – so undoing walks a record's changes back one
/// by one, newest first.
///
/// Not in the history: what isn't one record's move by hand – "Ohne
/// Regalplatz", "Verkauft", sorting a compartment, a restored backup and the
/// resets (the last two empty it, its places no longer hold).
enum ShelfHistory {
    /// Kept at most; older entries go at launch (see `prune`).
    static let keptCount = 1000

    enum Kind { case sortedIn, moved, takenOut }

    static func kind(of entry: ShelfHistoryEntry) -> Kind {
        switch (entry.fromShelfID, entry.toShelfID) {
        case (nil, _): .sortedIn
        case (_, nil): .takenOut
        default: .moved
        }
    }

    /// Why an entry can't be undone (any more).
    nonisolated enum Blocker: Equatable, Sendable {
        case undone, changedSince, recordGone, shelfGone, shelfLocked, keptOut

        /// Short, for the entry's row.
        var title: String {
            switch self {
            case .undone: String(localized: "Rückgängig gemacht")
            case .changedSince: String(localized: "Seitdem bewegt")
            case .recordGone: String(localized: "Nicht mehr in der Sammlung")
            case .shelfGone: String(localized: "Fach gibt es nicht mehr")
            case .shelfLocked: String(localized: "Fach gesperrt")
            case .keptOut: String(localized: "Ohne Regalplatz")
            }
        }

        /// Whole sentence, for the tooltip and an error.
        var message: String {
            switch self {
            case .undone: String(localized: "Diese Änderung ist schon rückgängig gemacht.")
            case .changedSince: String(localized: "Die Platte wurde seitdem noch einmal bewegt. Mache zuerst die neuere Änderung rückgängig.")
            case .recordGone: String(localized: "Die Platte ist nicht mehr in der Sammlung.")
            case .shelfGone: String(localized: "Das Fach, in dem die Platte vorher stand, gibt es nicht mehr – etwa weil ein Regal verkleinert wurde.")
            case .shelfLocked: String(localized: "Das Fach, in dem die Platte vorher stand, ist inzwischen gesperrt. Entsperre es per Rechtsklick, dann geht es.")
            case .keptOut: String(localized: "Die Platte steht inzwischen auf „Ohne Regalplatz“ und kommt deshalb nicht zurück ins Fach.")
            }
        }
    }

    /// What `PositionService.undo` needs: the record, the compartment it goes
    /// back to (`nil`: out of the shelves) – or why it can't.
    struct Check {
        var copy: RecordCopy?
        var fromShelf: Shelf?
        var blocker: Blocker?
    }

    /// Every entry, newest first.
    static func entries(in context: ModelContext) throws -> [ShelfHistoryEntry] {
        try context.fetch(FetchDescriptor<ShelfHistoryEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
    }

    /// One entry, right before it is undone: fetches what it needs.
    static func check(_ entry: ShelfHistoryEntry, in context: ModelContext) throws -> Check {
        let copyID = entry.copyID
        let copy = try context.fetch(FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.id == copyID })).first
        var fromShelf: Shelf?
        if let fromID = entry.fromShelfID {
            fromShelf = try context.fetch(FetchDescriptor<Shelf>(predicate: #Predicate { $0.id == fromID })).first
        }
        let open = try context.fetch(FetchDescriptor<ShelfHistoryEntry>(
            predicate: #Predicate { $0.copyID == copyID && $0.undoneAt == nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]))
        let excluded = try context.fetchCount(FetchDescriptor<OptimizationExclusion>(predicate: #Predicate { $0.copyID == copyID })) > 0
        let blocker = blocker(entry, isNewest: open.first?.id == entry.id, copy: copy, fromShelf: fromShelf, excluded: excluded)
        return Check(copy: copy, fromShelf: fromShelf, blocker: blocker)
    }

    /// The list at once: for each entry (by ID) why it can't be undone;
    /// missing from the result means it can. `entries` newest first, as
    /// `entries(in:)` returns them.
    static func blockers(_ entries: [ShelfHistoryEntry], copies: [UUID: RecordCopy], shelves: [UUID: Shelf],
                         excluded: Set<UUID>) -> [UUID: Blocker] {
        var newestOpen: [UUID: UUID] = [:]
        for entry in entries where entry.undoneAt == nil && newestOpen[entry.copyID] == nil {
            newestOpen[entry.copyID] = entry.id
        }
        var result: [UUID: Blocker] = [:]
        for entry in entries {
            let blocker = blocker(entry, isNewest: newestOpen[entry.copyID] == entry.id, copy: copies[entry.copyID],
                                  fromShelf: entry.fromShelfID.flatMap { shelves[$0] },
                                  excluded: excluded.contains(entry.copyID))
            if let blocker { result[entry.id] = blocker }
        }
        return result
    }

    private static func blocker(_ entry: ShelfHistoryEntry, isNewest: Bool, copy: RecordCopy?, fromShelf: Shelf?, excluded: Bool) -> Blocker? {
        if entry.undoneAt != nil { return .undone }
        guard let copy, !copy.isDeleted, copy.modelContext != nil else { return .recordGone }
        guard isNewest, copy.shelf?.id == entry.toShelfID else { return .changedSince }
        if entry.fromShelfID != nil {
            guard let fromShelf, !fromShelf.isDeleted, fromShelf.modelContext != nil else { return .shelfGone }
            if fromShelf.isReserved { return .shelfLocked }
        }
        // Taken out, then "Ohne Regalplatz": stays out on purpose.
        if entry.toShelfID == nil && excluded { return .keptOut }
        return nil
    }

    /// At launch: only the newest `keptCount` entries stay. Failure only costs space.
    static func prune(in context: ModelContext) {
        var old = FetchDescriptor<ShelfHistoryEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        old.fetchOffset = keptCount
        do {
            let rows = try context.fetch(old)
            guard !rows.isEmpty else { return }
            for row in rows { context.delete(row) }
            try context.save()
            AppLog.info("Regal", "Verlauf: \(rows.count) ältere Einträge entfernt, die neuesten \(keptCount) bleiben")
        } catch {
            context.rollback()
            AppLog.warning("Regal", "Verlauf konnte nicht gekürzt werden: \(error)")
        }
    }

    /// Restore and resets: the places it names no longer hold. Runs inside their transaction.
    static func clear(in context: ModelContext) throws {
        for row in try context.fetch(FetchDescriptor<ShelfHistoryEntry>()) { context.delete(row) }
    }
}
