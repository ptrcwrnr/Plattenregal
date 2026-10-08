import AppKit
import Foundation
import SwiftData

/// Everything about the shelf that exists only in this app and not at
/// Discogs: which copy stands where, locked compartments and records marked
/// "Nicht im Regal". Copies are identified by their Discogs instance ID,
/// which survives a lost database and a fresh sync.
nonisolated struct ShelfBackup: Codable, Equatable, Sendable {
    struct ShelfSetting: Codable, Equatable, Sendable {
        var number: Int
        var isReserved: Bool
        var name: String
    }
    /// A cabinet and its compartments (shelf numbers in reading order).
    /// Missing in backups from before cabinets: those restore into the
    /// cabinets as they are.
    struct CabinetSetting: Codable, Equatable, Sendable {
        var name: String
        var columns: Int
        var rows: Int
        var isActive: Bool
        var shelves: [Int]

        /// The size a restore builds (clamped like the settings allow).
        @MainActor var size: (columns: Int, rows: Int) {
            let range = ShelfGeometry.sizeRange
            return (min(max(columns, range.lowerBound), range.upperBound), min(max(rows, range.lowerBound), range.upperBound))
        }
        /// The compartments a restore recreates: as many as the grid holds.
        @MainActor var restoredShelves: ArraySlice<Int> { shelves.prefix(size.columns * size.rows) }
    }
    struct Placement: Codable, Equatable, Sendable {
        var instanceID: Int
        var shelf: Int
        var position: Int
        /// Only for reading the file; restoring goes by `instanceID`.
        var record: String?
    }

    static let currentVersion = 1

    var version = ShelfBackup.currentVersion
    var owner: String?
    var createdAt: Date
    var shelves: [ShelfSetting]
    var cabinets: [CabinetSetting]?
    var placements: [Placement]
    var notInShelf: [Int]

    /// Same layout, whenever it was taken.
    func hasSameLayout(as other: ShelfBackup) -> Bool {
        shelves == other.shelves && cabinets == other.cabinets && notInShelf == other.notInShelf
            && placements.map { [$0.instanceID, $0.shelf, $0.position] } == other.placements.map { [$0.instanceID, $0.shelf, $0.position] }
    }

    /// Nothing worth keeping: no record placed, no shelf locked, nothing set aside.
    var isEmpty: Bool { placements.isEmpty && !shelves.contains(where: \.isReserved) && notInShelf.isEmpty }

    /// The placements a restore can apply: shelves that exist and aren't
    /// locked, each copy once (the first entry wins in hand-edited files).
    @MainActor var applicablePlacements: [Placement] {
        let reserved = Set(shelves.filter(\.isReserved).map(\.number))
        // With cabinets in the file, only their compartments exist after a
        // restore (as many as each grid holds – the same rule as `rebuild`);
        // older files, and hand-edited ones without cabinets, address 1…12.
        let known = cabinets.flatMap { $0.isEmpty ? nil : Set($0.flatMap(\.restoredShelves)) } ?? Set(1...ShelfGeometry.count)
        var seen = Set<Int>()
        return placements.filter {
            known.contains($0.shelf) && !reserved.contains($0.shelf) && seen.insert($0.instanceID).inserted
        }
    }

    @MainActor var summary: String {
        if isEmpty { return String(localized: "Noch keine Platte eingeräumt") }
        let occupied = Set(placements.map(\.shelf)).count
        var parts = [String(localized: "\(AppStyle.records(placements.count)) in \(occupied == 1 ? String(localized: "1 Fach") : String(localized: "\(occupied) Fächern"))")]
        let locked = shelves.filter(\.isReserved).count
        if locked > 0 { parts.append(locked == 1 ? String(localized: "1 gesperrtes Fach") : String(localized: "\(locked) gesperrte Fächer")) }
        if !notInShelf.isEmpty { parts.append(String(localized: "\(notInShelf.count) nicht im Regal")) }
        if let cabinets, cabinets.count > 1 { parts.append(String(localized: "\(cabinets.count) Regale")) }
        return parts.joined(separator: " · ")
    }
}

nonisolated enum ShelfBackupError: LocalizedError {
    case unreadable, newerVersion, syncRunning, tooLarge, noMatchingRecords
    var errorDescription: String? {
        switch self {
        case .tooLarge: String(localized: "Diese Datei ist viel zu groß für eine Sicherung der Fach-Belegung. Wähle eine Datei, die Plattenregal erstellt hat.")
        case .noMatchingRecords: String(localized: "Keine Platte aus dieser Sicherung ist gerade in deiner Sammlung. Synchronisiere zuerst die Collection mit Discogs – oder die Sicherung gehört zu einem anderen Discogs-Konto. Es wurde nichts verändert.")
        case .syncRunning: String(localized: "Gerade läuft eine Synchronisierung mit Discogs. Warte, bis sie fertig ist, und stelle die Belegung dann wieder her.")
        case .unreadable: String(localized: "Diese Datei ist keine Sicherung der Fach-Belegung oder sie ist beschädigt. Wähle eine Datei, die Plattenregal mit „Sichern unter …“ oder automatisch erstellt hat.")
        case .newerVersion: String(localized: "Diese Sicherung stammt aus einer neueren Version von Plattenregal. Aktualisiere die App zuerst und versuche es dann noch einmal.")
        }
    }
}

/// What a restore would do, shown before anything changes.
struct ShelfRestorePreview {
    let backup: ShelfBackup
    /// Copies that get their place back.
    let placed: Int
    /// In the backup, but no longer in the library (sold, other account).
    let missing: Int
    /// In the collection now, but without a place in the backup: they end up "ohne Fach".
    let unplaced: Int
    let otherAccount: Bool
    /// The shelf already looks exactly like this.
    var unchanged = false
    /// The backup's cabinets (count, size, names) differ from today's; a restore rebuilds them.
    var changesCabinets = false

    var message: String {
        if unchanged { return String(localized: "Die Belegung entspricht bereits dieser Sicherung – es würde sich nichts ändern.") }
        var lines = [String(localized: "\(placed) Platten werden wieder einsortiert.")]
        if unplaced > 0 { lines.append(String(localized: "\(unplaced) Platten kommen in der Sicherung nicht vor und stehen danach ohne Fach.")) }
        if missing > 0 { lines.append(String(localized: "\(missing) Platten aus der Sicherung sind nicht mehr in der Sammlung und werden übersprungen.")) }
        if missing > placed {
            lines.append(String(localized: "Mehr als die Hälfte der Platten aus der Sicherung fehlt. Ist die Collection noch nicht vollständig synchronisiert, brich ab und synchronisiere zuerst."))
        }
        if changesCabinets { lines.append(String(localized: "Auch die Regale werden auf den Stand der Sicherung gebracht – Anzahl, Größe und Namen.")) }
        if otherAccount, let owner = backup.owner { lines.append(String(localized: "Achtung: Die Sicherung gehört zum Discogs-Konto „\(owner)“.")) }
        // The demo never writes backups (see `ShelfAutoBackup.isAppStore`).
        lines.append(DemoMode.isActive ? String(localized: "Die aktuelle Belegung wird ersetzt.")
                     : String(localized: "Die aktuelle Belegung wird ersetzt. Sie wird vorher automatisch gesichert."))
        return lines.joined(separator: "\n")
    }
}

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
    /// every copy's place and the "Nicht im Regal" marks. Positions are
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
            // "Vermisst" isn't part of a backup and stays, except on
            // records the backup keeps out of the shelves ("Nicht im Regal").
            let cleared = try context.fetch(FetchDescriptor<MissingCopyMark>()).filter { excluded.contains($0.copyID) }
            for row in cleared { context.delete(row) }
            if !cleared.isEmpty { AppLog.info("Sicherung", "„Vermisst“ bei \(cleared.count) Platte(n) aufgehoben – laut Sicherung „Nicht im Regal“") }
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

// MARK: - Automatic backups

/// Keeps the last few layouts as files in the app's own folder, written a
/// few seconds after the shelf last changed. Unchanged layouts aren't written again.
@Observable final class ShelfAutoBackup {
    static let shared = ShelfAutoBackup()
    static let enabledKey = "shelfAutoBackupEnabled"
    /// The most recent states, plus the last state of each of the past
    /// `keptDays` days – so a burst of changes (e.g. re-sorting after data
    /// loss) never pushes out every backup from before. Both can be set in
    /// the settings.
    static let keptCountKey = "shelfBackupKeptCount"
    static let keptDaysKey = "shelfBackupKeptDays"
    static let defaultKeptCount = 10
    static let defaultKeptDays = 14
    static let keptCountOptions = [5, 10, 20, 50]
    static let keptDaysOptions = [0, 7, 14, 30, 90]
    static var keptCount: Int { (AppDefaults.store.object(forKey: keptCountKey) as? Int).map { max(1, $0) } ?? defaultKeptCount }
    static var keptDays: Int { (AppDefaults.store.object(forKey: keptDaysKey) as? Int).map { max(0, $0) } ?? defaultKeptDays }
    /// Another folder than the app's own (e.g. iCloud Drive), if chosen.
    nonisolated static let folder = FolderAccess(key: "shelfBackupFolder")

    struct Entry: Identifiable {
        let url: URL
        let backup: ShelfBackup
        var id: URL { url }
    }

    /// Bumped after every write, so the settings list reloads.
    private(set) var version = 0
    /// Set when the last automatic backup failed, cleared by the next success.
    private(set) var lastFailure: Date?
    private var pending: Task<Void, Never>?
    private var pendingContainer: ModelContainer?
    /// Files already read, by their modification date: the list reloads after
    /// every change and sync, and up to ~140 files of a large collection
    /// (maybe in iCloud) must not be parsed again each time.
    /// An unreadable file is kept as `nil`, so it isn't read and logged again.
    private var cache: [URL: (modified: Date?, backup: ShelfBackup?)] = [:]
    private var observesTermination = false

    var isEnabled: Bool {
        AppDefaults.store.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// The app's own folder inside its container.
    nonisolated static var defaultDirectory: URL? {
        // The demo never lists, prunes or writes the real backups.
        if DemoMode.isActive { return DemoMode.temporaryDirectory.appendingPathComponent("Sicherungen", isDirectory: true) }
        return try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Plattenregal/Sicherungen", isDirectory: true)
    }

    /// Where backups are written and listed: the chosen folder, or the
    /// app's own one when none is chosen or it can't be found any more.
    var directory: URL? { Self.folder.url ?? Self.defaultDirectory }
    var usesCustomFolder: Bool { Self.folder.url != nil }

    /// Runs `body` with the backup folder open for reading and writing.
    nonisolated private static func inDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        if Self.folder.url != nil { return try Self.folder.withAccess(body) }
        guard let directory = Self.defaultDirectory else { throw CocoaError(.fileNoSuchFile) }
        return try body(directory)
    }

    /// Switches to another folder (`nil` = the app's own). Existing backups
    /// are copied over, so the list and the retention carry on; the old
    /// folder keeps its copies.
    func moveBackups(to url: URL?) throws {
        // The demo's retention must never reach a folder holding real backups.
        guard !DemoMode.isActive else { return }
        let old = entries()
        let previousBookmark = AppDefaults.store.data(forKey: Self.folder.key)
        if let url { try Self.folder.set(url) } else { Self.folder.clear() }
        do {
            try Self.inDirectory { directory in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for entry in old {
                    let target = directory.appendingPathComponent(entry.url.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: target.path) {
                        try ShelfBackupService.encode(entry.backup).write(to: target, options: .atomic)
                    }
                }
            }
        } catch {
            // Not writable (or full): stay with the old folder instead of
            // switching to one that holds only part of the backups.
            AppDefaults.store.set(previousBookmark, forKey: Self.folder.key)
            AppLog.error("Sicherung", "Speicherort nicht gewechselt, Sicherungen ließen sich nicht kopieren: \(error)")
            throw error
        }
        AppLog.info("Sicherung", "Speicherort der automatischen Sicherung: \(url.map(FolderAccess.displayName) ?? "Standard")")
        prune()
        version += 1
    }

    /// How many existing files a retention of `keptCount`/`keptDays` would delete.
    func filesRemoved(keptCount: Int, keptDays: Int) -> Int {
        let all = Self.ownFiles()
        return all.count - Set(Self.retained(all.map(\.date), keptCount: keptCount, keptDays: keptDays)).count
    }

    /// Applies a changed retention right away.
    func applyRetention() {
        prune()
        version += 1
    }

    /// Called after every committed shelf change. Only the app's real store
    /// is backed up – never test or demo stores.
    func scheduleBackup(of container: ModelContainer) {
        guard isEnabled, Self.isAppStore(container) else { return }
        observeTermination()
        pending?.cancel()
        pendingContainer = container
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.runPendingInBackground()
        }
    }

    nonisolated static func isAppStore(_ container: ModelContainer) -> Bool {
        guard let store = try? LibraryStorage.storeURL() else { return false }
        return container.configurations.contains { !$0.isStoredInMemoryOnly && $0.url.standardizedFileURL == store.standardizedFileURL }
    }

    /// On quit: synchronously, or the app would be gone before the file is written.
    private func runPending() {
        guard let container = pendingContainer else { return }
        pending?.cancel(); pending = nil; pendingContainer = nil
        // Switched off while waiting.
        guard isEnabled else { return }
        recordOutcome { try backUpNow(ShelfBackupService(context: container.mainContext), skipEmpty: true) }
    }

    /// A few seconds after the last change: the file is compared and written
    /// off the main actor, so a slow folder (iCloud, network) never holds up the shelf.
    private func runPendingInBackground() async {
        guard let container = pendingContainer else { return }
        guard isEnabled else { pendingContainer = nil; return }
        do {
            try await backUpInBackground(container)
            lastFailure = nil
        } catch {
            lastFailure = .now
            AppLog.error("Sicherung", "Automatische Sicherung fehlgeschlagen: \(error)")
        }
        // Only now: quitting while the file is still being written writes it
        // once more on the way out. A newer change has scheduled its own run.
        if !Task.isCancelled { pending = nil; pendingContainer = nil }
    }

    private func recordOutcome(_ body: () throws -> Void) {
        do {
            try body()
            lastFailure = nil
        } catch {
            lastFailure = .now
            AppLog.error("Sicherung", "Automatische Sicherung fehlgeschlagen: \(error)")
        }
    }

    /// Quitting within the delay would lose the last change.
    private func observeTermination() {
        guard !observesTermination else { return }
        observesTermination = true
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ShelfAutoBackup.shared.runPending() }
        }
    }

    /// Writes the current layout unless the newest file already holds it.
    /// Returns `false` when nothing had to be written.
    /// `skipEmpty`: an empty shelf (fresh install, lost database) is never
    /// worth an automatic backup of its own.
    @discardableResult func backUpNow(_ service: ShelfBackupService, skipEmpty: Bool = false) throws -> Bool {
        guard let backup = try Self.take(service, skipEmpty: skipEmpty) else { return false }
        return written(try Self.write(backup, keptCount: Self.keptCount, keptDays: Self.keptDays), backup)
    }

    /// `backUpNow` entirely off the main actor: the layout is read in a
    /// context of its own (for 900 records ~75 ms, a hitch while sorting on),
    /// then the files are read and written.
    private func backUpInBackground(_ container: ModelContainer) async throws {
        let keptCount = Self.keptCount, keptDays = Self.keptDays
        let result = try await Task.detached(priority: .utility) { () throws -> (name: String?, backup: ShelfBackup)? in
            guard ShelfAutoBackup.isAppStore(container) else { return nil }
            let backup = try ShelfBackupService.makeBackup(of: ModelContext(container))
            guard !backup.isEmpty else { return nil }
            return (try Self.write(backup, keptCount: keptCount, keptDays: keptDays), backup)
        }.value
        if let result { written(result.name, result.backup) }
    }

    private static func take(_ service: ShelfBackupService, skipEmpty: Bool) throws -> ShelfBackup? {
        // Demo and test stores never mix into the real backups.
        guard isAppStore(service.context.container) else { return nil }
        let backup = try service.makeBackup()
        return skipEmpty && backup.isEmpty ? nil : backup
    }

    /// Writes `backup` unless the newest file already holds its layout, then
    /// clears out old files. Returns the new file's name, `nil` when nothing
    /// had to be written.
    nonisolated private static func write(_ backup: ShelfBackup, keptCount: Int, keptDays: Int) throws -> String? {
        // Only the newest file is read – not every backup after each shelf change.
        if let newest = ownFiles().first,
           let latest = try? Self.inDirectory({ _ in try ShelfBackupService.read(newest.url) }),
           latest.hasSameLayout(as: backup) { return nil }
        let name = fileName(for: backup.createdAt)
        try Self.inDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ShelfBackupService.encode(backup).write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        prune(keptCount: keptCount, keptDays: keptDays)
        return name
    }

    @discardableResult private func written(_ name: String?, _ backup: ShelfBackup) -> Bool {
        guard let name else { return false }
        AppLog.info("Sicherung", "Automatisch gesichert: \(name) · \(backup.summary)")
        version += 1
        return true
    }

    /// Newest first.
    func entries() -> [Entry] {
        let files = (try? Self.inDirectory { directory in
            // Only the app's own files: anything else in the folder is neither
            // listed nor ever deleted when old backups are cleared.
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { Self.isOwnFile($0.lastPathComponent) }
                .map { url in (url: url, modified: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) }
        }) ?? []
        // Forget files that are gone (pruned, other folder).
        let listed = Set(files.map(\.url))
        cache = cache.filter { listed.contains($0.key) }
        let unread = files.filter { file in cache[file.url].map { $0.modified != file.modified || file.modified == nil } ?? true }
        if !unread.isEmpty {
            try? Self.inDirectory { _ in
                for file in unread {
                    do { cache[file.url] = (file.modified, try ShelfBackupService.read(file.url)) }
                    catch {
                        cache[file.url] = (file.modified, nil)
                        AppLog.warning("Sicherung", "Automatische Sicherung \(file.url.lastPathComponent) nicht lesbar, wird übergangen: \(error)")
                    }
                }
            }
        }
        return files.compactMap { file in cache[file.url]?.backup.map { Entry(url: file.url, backup: $0) } }
            .sorted { $0.backup.createdAt > $1.backup.createdAt }
    }

    /// The app's own files, newest first, dated by their name – without
    /// reading them. Runs after every backup, so it must stay cheap.
    nonisolated private static func ownFiles() -> [(url: URL, date: Date)] {
        let urls = (try? Self.inDirectory { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }) ?? []
        return urls.compactMap { url in Self.fileDate(of: url.lastPathComponent).map { (url, $0) } }
            .sorted { $0.date > $1.date }
    }

    private func prune() { Self.prune(keptCount: Self.keptCount, keptDays: Self.keptDays) }

    nonisolated private static func prune(keptCount: Int, keptDays: Int) {
        guard !DemoMode.isActive else { return }
        let all = ownFiles()
        let kept = Set(retained(all.map(\.date), keptCount: keptCount, keptDays: keptDays))
        for (index, file) in all.enumerated() where !kept.contains(index) {
            do { try Self.inDirectory { _ in try FileManager.default.removeItem(at: file.url) } }
            catch { AppLog.warning("Sicherung", "Alte Sicherung \(file.url.lastPathComponent) ließ sich nicht löschen: \(error)") }
        }
    }

    /// Indices (in `dates`, newest first) of the backups to keep.
    nonisolated static func retained(_ dates: [Date], keptCount: Int, keptDays: Int, calendar: Calendar = .current) -> [Int] {
        var kept = Array(dates.indices.prefix(keptCount))
        var days = Set<DateComponents>()
        for (index, date) in dates.enumerated() {
            let day = calendar.dateComponents([.year, .month, .day], from: date)
            guard days.count < keptDays || days.contains(day) else { break }
            if days.insert(day).inserted, index >= keptCount { kept.append(index) }
        }
        return kept
    }

    nonisolated private static let filePrefix = "Belegung "

    /// "Belegung 2026-09-24 10-41-05 +0200.json": local time, readable in the
    /// Finder, with its offset – the newest file and the retention go by this
    /// time, and without the offset the repeated hour when the clocks go back
    /// (or a trip to another time zone) would put a newer file behind older ones.
    nonisolated static func fileName(for date: Date, in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss Z"
        return filePrefix + formatter.string(from: date) + ".json"
    }

    /// Own files, including those from before the offset was added
    /// ("Belegung 2026-09-24 10-41-05.json", read as local time).
    nonisolated static func isOwnFile(_ name: String) -> Bool { fileDate(of: name) != nil }

    /// The time in an own file's name; `nil` for any other file.
    nonisolated static func fileDate(of name: String) -> Date? {
        guard name.hasPrefix(filePrefix), name.hasSuffix(".json") else { return nil }
        let stamp = String(name.dropFirst(filePrefix.count).dropLast(".json".count))
        return withOffset.date(from: stamp) ?? localTime.date(from: stamp)
    }

    // Only ever read after setup; DateFormatter is thread-safe for that.
    nonisolated private static let withOffset = posixFormatter("yyyy-MM-dd HH-mm-ss Z")
    nonisolated private static let localTime = posixFormatter("yyyy-MM-dd HH-mm-ss")
    nonisolated private static func posixFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
