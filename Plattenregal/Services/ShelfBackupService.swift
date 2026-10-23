import Foundation
import SwiftData

struct ShelfBackupService {
    let context: ModelContext

    // MARK: Backup

    func makeBackup(at date: Date = .now) throws -> ShelfBackup {
        try Self.makeBackup(of: context, at: date)
    }

    /// Also off the main actor, with a context of its own (see `ShelfAutoBackup`).
    nonisolated static func makeBackup(of context: ModelContext, at date: Date = .now) throws -> ShelfBackup {
        let owner = DiscogsAccount.current(in: try context.fetch(FetchDescriptor<DiscogsAccount>()))?.username
        let shelves = try context.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
        let cabinets = try context.fetch(FetchDescriptor<Cabinet>(sortBy: [SortDescriptor(\Cabinet.sortOrder)]))
        let copies = try context.fetch(RecordCopy.fetchingReleases())
        let excluded = Set(try context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID))
        let placements = copies.compactMap { copy -> ShelfBackup.Placement? in
            guard let shelf = copy.shelf else { return nil }
            let record = copy.release.map { "\($0.displayArtist) – \($0.displayTitle)" }
            return .init(instanceID: copy.discogsInstanceID, shelf: shelf.number, position: copy.positionInShelf, record: record)
        }
        .sorted { ($0.shelf, $0.position, $0.instanceID) < ($1.shelf, $1.position, $1.instanceID) }
        return ShelfBackup(
            owner: owner, createdAt: date,
            shelves: shelves.map { .init(number: $0.number, isReserved: $0.isReserved, name: $0.name) },
            cabinets: cabinets.map { .init(name: $0.name, columns: $0.columns, rows: $0.rows, isActive: $0.isActive,
                                           shelves: $0.orderedShelves.map(\.number)) },
            placements: placements,
            notInShelf: copies.filter { excluded.contains($0.id) && $0.shelf == nil }.map(\.discogsInstanceID).sorted())
    }

    nonisolated static func encode(_ backup: ShelfBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    /// Far above any real layout (a few hundred bytes per record); keeps a
    /// wrongly picked file from being loaded whole.
    nonisolated static let maximumFileSize = 20_000_000

    nonisolated static func read(_ url: URL) throws -> ShelfBackup {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumFileSize else { throw ShelfBackupError.tooLarge }
        return try decode(try Data(contentsOf: url))
    }

    nonisolated static func decode(_ data: Data) throws -> ShelfBackup {
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let header = try? decoder.decode(Header.self, from: data) else { throw ShelfBackupError.unreadable }
        guard header.version <= ShelfBackup.currentVersion else { throw ShelfBackupError.newerVersion }
        guard let backup = try? decoder.decode(ShelfBackup.self, from: data) else { throw ShelfBackupError.unreadable }
        return backup
    }

    // MARK: Restore

    func preview(_ backup: ShelfBackup) throws -> ShelfRestorePreview {
        let owner = DiscogsAccount.current(in: try context.fetch(FetchDescriptor<DiscogsAccount>()))?.username
        let copies = try context.fetch(FetchDescriptor<RecordCopy>())
        let known = Set(copies.map(\.discogsInstanceID))
        let placeable = backup.applicablePlacements
        let current = try? makeBackup()
        let covered = Set(placeable.map(\.instanceID)).union(backup.notInShelf)
        // Nothing would get its place back, but every current place would be
        // cleared – typically restoring before the first sync after data loss.
        guard placeable.contains(where: { known.contains($0.instanceID) }) || backup.notInShelf.contains(where: known.contains) else {
            throw ShelfBackupError.noMatchingRecords
        }
        return ShelfRestorePreview(
            backup: backup,
            placed: placeable.filter { known.contains($0.instanceID) }.count,
            missing: placeable.filter { !known.contains($0.instanceID) }.count,
            unplaced: copies.filter { $0.isInCurrentCollection(owner: owner) && !covered.contains($0.discogsInstanceID) }.count,
            otherAccount: backup.owner != nil && owner != nil && backup.owner != owner,
            unchanged: current?.hasSameLayout(as: backup) == true,
            changesCabinets: backup.cabinets?.isEmpty == false && current.map { Self.cabinetShape($0) != Self.cabinetShape(backup) } == true)
    }

    /// What `rebuild` restores of the cabinets – not which compartment number sits where.
    private static func cabinetShape(_ backup: ShelfBackup) -> [String] {
        (backup.cabinets ?? []).map { "\($0.name)|\($0.columns)|\($0.rows)|\($0.isActive)" }
    }

    /// Replaces the whole layout in one transaction: shelf locks and names,
    /// every copy's place and the "Ohne Regalplatz" marks. Positions are
    /// renumbered 1…n per shelf in the backup's order, closing the gaps left
    /// by copies that are gone.
    func restore(_ backup: ShelfBackup) throws {
        // The sync writes copies in the background; a restore in between
        // could be overwritten or place copies the sync is about to change.
        // (`busy`: the tracklist download afterwards only touches releases.)
        guard !DiscogsSyncService.shared.busy else { throw ShelfBackupError.syncRunning }
        do { try apply(backup) } catch { throw FileTransferError.restoreFailed(error) }
        // Cabinets may have been rebuilt; the compartment labels follow.
        LibraryChanges.shared.shelvesDidChange()
        AppLog.info("Sicherung", "Fach-Belegung wiederhergestellt (Stand \(backup.createdAt.formatted(.iso8601))): \(backup.summary)")
    }

    private func apply(_ backup: ShelfBackup) throws {
        var shelves = try context.fetch(FetchDescriptor<Shelf>())
        let copies = try context.fetch(FetchDescriptor<RecordCopy>())
        let byInstance = Dictionary(copies.map { ($0.discogsInstanceID, $0) }, uniquingKeysWith: { first, _ in first })
        let settings = Dictionary(backup.shelves.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        let placements = backup.applicablePlacements
        let placed = Set(placements.map(\.instanceID))

        try PositionService(context: context).save {
            for copy in copies { copy.shelf = nil; copy.positionInShelf = 0 }
            if let cabinets = backup.cabinets, !cabinets.isEmpty { shelves = try rebuild(cabinets, from: shelves) }
            for shelf in shelves {
                let setting = settings[shelf.number]
                shelf.isReserved = setting?.isReserved ?? false
                shelf.name = setting?.name ?? ""
            }
            let byNumber = Dictionary(shelves.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
            for (number, placements) in Dictionary(grouping: placements, by: \.shelf) {
                guard let shelf = byNumber[number] else { continue }
                let present = placements.sorted { ($0.position, $0.instanceID) < ($1.position, $1.instanceID) }
                    .compactMap { byInstance[$0.instanceID] }
                for (index, copy) in present.enumerated() { copy.shelf = shelf; copy.positionInShelf = index + 1 }
            }
            for row in try context.fetch(FetchDescriptor<OptimizationExclusion>()) { context.delete(row) }
            var excluded = Set<UUID>()
            for id in Set(backup.notInShelf).subtracting(placed) {
                if let copy = byInstance[id] { context.insert(OptimizationExclusion(copyID: copy.id)); excluded.insert(copy.id) }
            }
            // "Gesucht" isn't part of a backup and stays, except on
            // records the backup keeps out of the shelves ("Ohne Regalplatz").
            let cleared = try context.fetch(FetchDescriptor<MissingCopyMark>()).filter { excluded.contains($0.copyID) }
            for row in cleared { context.delete(row) }
            if !cleared.isEmpty { AppLog.info("Sicherung", "Suchliste: \(cleared.count) Platte(n) entfernt – laut Sicherung „Ohne Regalplatz“") }
            // Every place is the backup's now; the history's no longer hold.
            try ShelfHistory.clear(in: context)
        }
    }
}

extension ShelfBackupService {
    /// Recreates the backup's cabinets: compartments keep their numbers
    /// (reused where they exist, created where not); compartments and
    /// cabinets the backup doesn't know are removed. Runs after every copy
    /// left its shelf, so nothing stands in a removed compartment.
    fileprivate func rebuild(_ settings: [ShelfBackup.CabinetSetting], from shelves: [Shelf]) throws -> [Shelf] {
        let byNumber = Dictionary(shelves.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        var used = Set<Int>()
        var result: [Shelf] = []
        var created: [Cabinet] = []
        for cabinet in try context.fetch(FetchDescriptor<Cabinet>()) { cabinet.shelves = []; context.delete(cabinet) }
        for (order, setting) in settings.enumerated() {
            let (columns, rows) = setting.size
            let name = setting.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cabinet = Cabinet(name: name.isEmpty ? String(localized: "Regal \(order + 1)") : name, rows: rows, columns: columns, sortOrder: order)
            cabinet.isActive = setting.isActive
            context.insert(cabinet)
            created.append(cabinet)
            for (index, number) in setting.restoredShelves.enumerated() where used.insert(number).inserted {
                let slot = index + 1
                let shelf = byNumber[number] ?? {
                    Shelf.insert(number: number, cabinet: cabinet, slot: slot, in: context)
                }()
                shelf.cabinet = cabinet
                shelf.sortOrder = slot
                shelf.row = (slot - 1) / columns + 1
                shelf.column = (slot - 1) % columns + 1
                result.append(shelf)
            }
        }
        for shelf in shelves where !used.contains(shelf.number) { context.delete(shelf) }
        if !settings.contains(where: \.isActive), let first = created.first { first.isActive = true }
        // Gaps (a file with fewer numbers than the grid) are filled like at launch.
        return result + LibraryStorage.fillCabinets(created, shelves: result, numbersAbove: shelves.map(\.number).max() ?? 0, in: context)
    }
}
