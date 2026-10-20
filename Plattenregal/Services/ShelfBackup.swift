import Foundation

/// Everything about the shelf that exists only in this app and not at
/// Discogs: which copy stands where, locked compartments and records marked
/// "Ohne Regalplatz". Copies are identified by their Discogs instance ID,
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
        if !notInShelf.isEmpty { parts.append(String(localized: "\(notInShelf.count) ohne Regalplatz")) }
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
        if unplaced > 0 { lines.append(String(localized: "\(unplaced) Platten kommen in der Sicherung nicht vor und sind danach noch nicht einsortiert.")) }
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
