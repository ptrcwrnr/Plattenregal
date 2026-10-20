import Foundation
import SwiftData

nonisolated enum StorageError: LocalizedError {
    case alreadyOpen
    var errorDescription: String? {
        String(localized: "Plattenregal ist bereits geöffnet – zum Beispiel aus Xcode oder ein zweites Mal aus dem Finder. Damit nie zwei Instanzen gleichzeitig in deine Sammlung schreiben, öffnet diese hier sie nicht. Beende die andere Instanz und starte Plattenregal dann neu.")
    }
}

enum LibraryStorage {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV16.self)
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let url = try storeURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try acquireInstanceLock(next: url)
            config = ModelConfiguration("Plattenregal", schema: schema, url: url, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
        container.mainContext.autosaveEnabled = false
        try prepareShelves(in: container.mainContext)
        pruneHistory(in: container.mainContext)
        return container
    }

    /// The app's one real store; test and demo stores live elsewhere.
    nonisolated static func storeURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Plattenregal/Collection.store")
    }

    /// Kept open for the whole session; the system lifts the lock when the
    /// process ends, also after a crash.
    nonisolated(unsafe) private static var lockDescriptor: Int32 = -1

    /// Only one instance may open the real store (Xcode and Finder at the same
    /// time, `open -n`). The demo never opens it, so switching into or out of
    /// the demo – with the old instance still quitting – isn't affected. A
    /// previous instance that is just quitting gets a few seconds to let go.
    static func acquireInstanceLock(next storeURL: URL, wait: Duration = .seconds(5)) throws {
        guard lockDescriptor < 0 else { return }
        let path = storeURL.deletingLastPathComponent().appendingPathComponent(".Plattenregal.lock").path
        let fd = open(path, O_RDWR | O_CREAT, 0o644)
        // No lock file possible: the store itself will report what is wrong.
        guard fd >= 0 else { return }
        let deadline = ContinuousClock.now + wait
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ContinuousClock.now < deadline else {
                close(fd)
                AppLog.error("Datenbank", "Sammlung nicht geöffnet: eine andere Instanz hält sie offen")
                throw StorageError.alreadyOpen
            }
            usleep(100_000)
        }
        lockDescriptor = fd
    }

    /// SwiftData records every save in a change history that is never read
    /// here (no widgets, extensions or sync consume it); clear it at launch so
    /// it does not grow with every Discogs sync. Failure only costs space.
    static func pruneHistory(in context: ModelContext) {
        do { try context.deleteHistory(HistoryDescriptor<DefaultHistoryTransaction>()) }
        catch { AppLog.warning("Datenbank", "Änderungsverlauf konnte nicht bereinigt werden: \(error)") }
    }

    static func prepareShelves(in context: ModelContext) throws {
        var cabinets = try context.fetch(FetchDescriptor<Cabinet>(sortBy: [SortDescriptor(\Cabinet.sortOrder)]))
        var existing = try context.fetch(FetchDescriptor<Shelf>())
        // A fresh store gets one KALLAX holding the compartments 1…12; a
        // compartment without a cabinet joins the first, keeping its place.
        if cabinets.isEmpty {
            let cabinet = Cabinet(name: String(localized: "Regal"), rows: ShelfGeometry.rows, columns: ShelfGeometry.columns, sortOrder: 0)
            context.insert(cabinet)
            cabinets = [cabinet]
        }
        for shelf in existing where shelf.cabinet == nil {
            shelf.cabinet = cabinets[0]
            shelf.sortOrder = shelf.number
        }
        existing += fillCabinets(cabinets, shelves: existing, in: context)
        if !cabinets.contains(where: \.isActive) { cabinets[0].isActive = true }
        // Every shelf's positions must run 1…n without gaps or doubles: the spine
        // strip and the table address records by position. All writes keep it
        // that way; this only heals older data, keeping the physical order.
        for shelf in existing {
            let ordered = shelf.copies.sorted {
                if $0.positionInShelf != $1.positionInShelf { return $0.positionInShelf < $1.positionInShelf }
                return $0.id.uuidString < $1.id.uuidString
            }
            for (index, copy) in ordered.enumerated() where copy.positionInShelf != index + 1 {
                copy.positionInShelf = index + 1
            }
        }
        try context.save()
    }

    /// Geometry describes each cabinet; copy positions and shelf identities
    /// are preserved. Missing compartments are added with fresh numbers.
    /// Returns the compartments it added. Takes the models instead of
    /// fetching them, so it also sees ones inserted in the same transaction.
    /// New numbers start above `numbersAbove` as well – numbers of shelves
    /// deleted in the same transaction must not be handed out again.
    @discardableResult static func fillCabinets(_ cabinets: [Cabinet], shelves: [Shelf], numbersAbove: Int = 0,
                                                in context: ModelContext) -> [Shelf] {
        var existing = shelves
        var added: [Shelf] = []
        var nextNumber = max(existing.map(\.number).max() ?? 0, numbersAbove) + 1
        for cabinet in cabinets {
            let own = existing.filter { $0.cabinet?.id == cabinet.id }
            for slot in 1...max(1, cabinet.count) where !own.contains(where: { $0.sortOrder == slot }) {
                let shelf = Shelf.insert(number: nextNumber, cabinet: cabinet, slot: slot, in: context)
                nextNumber += 1
                existing.append(shelf)
                added.append(shelf)
            }
            for shelf in existing where shelf.cabinet?.id == cabinet.id {
                shelf.row = (shelf.sortOrder - 1) / max(1, cabinet.columns) + 1
                shelf.column = (shelf.sortOrder - 1) % max(1, cabinet.columns) + 1
            }
        }
        return added
    }
}
