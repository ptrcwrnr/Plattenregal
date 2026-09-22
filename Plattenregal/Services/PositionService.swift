import Foundation
import SwiftData

enum LibraryError: LocalizedError {
    case full, invalidPosition, missingRelease, invalidMetadata, invalidCapacity, staleData
    var errorDescription: String? {
        switch self {
        case .full: "Das Zielfach ist voll. Wähle ein anderes Fach oder erhöhe seine Kapazität."
        case .invalidPosition: "Diese Position ist ungültig. Wähle einen Platz zwischen 1 und dem Fachende."
        case .missingRelease: "Die Veröffentlichung oder das Fach konnte nicht gefunden werden."
        case .invalidMetadata: "Interpret und Titel sind erforderlich. Jahr und Kaufpreis müssen gültig sein."
        case .invalidCapacity: "Die Kapazität muss positiv sein und mindestens der aktuellen Belegung entsprechen."
        case .staleData: "Bitte aktualisiere zuerst die Discogs-Daten, um nach Metadaten zu sortieren."
        }
    }
}

// All position writes run on the main actor and are saved as one transaction.
@MainActor struct PositionService {
    let context: ModelContext
    func ordered(_ shelf: Shelf, excluding id: UUID? = nil) -> [RecordCopy] {
        shelf.copies.filter { $0.id != id }.sorted {
            if $0.positionInShelf != $1.positionInShelf { return $0.positionInShelf < $1.positionInShelf }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    private func renumber(_ copies: [RecordCopy]) {
        for (index, copy) in copies.enumerated() { copy.positionInShelf = index + 1 }
    }
    func save(_ action: () throws -> Void) throws {
        do { try action(); try context.save() }
        catch { context.rollback(); throw error }
    }
    func validate(shelf: Shelf, position: Int, excluding id: UUID? = nil) throws {
        let count = ordered(shelf, excluding: id).count
        guard count < shelf.capacity else { throw LibraryError.full }
        guard (1...(count + 1)).contains(position) else { throw LibraryError.invalidPosition }
    }
    @discardableResult func insert(release: Release, shelf: Shelf, position: Int,
                                    configure: (RecordCopy) -> Void = { _ in }) throws -> RecordCopy {
        try validate(shelf: shelf, position: position)
        var result: RecordCopy!
        try save {
            var copies = ordered(shelf)
            context.insert(release)
            let copy = RecordCopy(release: release, shelf: shelf, position: position)
            context.insert(copy); configure(copy)
            copies.insert(copy, at: position - 1); renumber(copies); result = copy
        }
        return result
    }
    func move(_ copy: RecordCopy, to shelf: Shelf, position: Int, edit: () -> Void = {}) throws {
        try validate(shelf: shelf, position: position, excluding: copy.id)
        try save {
            let oldShelf = copy.shelf
            var destination = ordered(shelf, excluding: copy.id)
            copy.shelf = shelf
            destination.insert(copy, at: position - 1)
            if let oldShelf, oldShelf.id != shelf.id { renumber(ordered(oldShelf, excluding: copy.id)) }
            renumber(destination); edit()
        }
    }
    func assign(_ copies: [RecordCopy], to shelf: Shelf) throws {
        var seenIDs = Set<UUID>()
        let orderedSelection = copies.filter { seenIDs.insert($0.id).inserted }
        guard !orderedSelection.isEmpty else { return }
        let selectedIDs = Set(orderedSelection.map(\.id))
        let destination = ordered(shelf).filter { !selectedIDs.contains($0.id) }
        guard destination.count + orderedSelection.count <= shelf.capacity else { throw LibraryError.full }
        let sourceShelves = Dictionary(
            orderedSelection.compactMap { copy in copy.shelf.map { ($0.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        ).values.filter { $0.id != shelf.id }

        try save {
            for copy in orderedSelection { copy.shelf = shelf }
            renumber(destination + orderedSelection)
            for source in sourceShelves {
                renumber(ordered(source).filter { !selectedIDs.contains($0.id) })
            }
        }
    }
    func unplace(_ copy: RecordCopy, edit: () -> Void = {}) throws {
        try save {
            let oldShelf = copy.shelf
            copy.shelf = nil; copy.positionInShelf = 0
            if let oldShelf { renumber(ordered(oldShelf, excluding: copy.id)) }
            edit()
        }
    }
    func delete(_ copy: RecordCopy) throws {
        try save {
            let shelf = copy.shelf; let release = copy.release
            let remaining = shelf.map { ordered($0, excluding: copy.id) } ?? []
            let isLast = release?.copies.filter { $0.id != copy.id }.isEmpty ?? false
            copy.shelf = nil; copy.release = nil; context.delete(copy)
            renumber(remaining)
            if isLast, let release {
                let wants = try context.fetch(FetchDescriptor<WantlistEntry>())
                if !wants.contains(where: { $0.release?.id == release.id }) { context.delete(release) }
            }
        }
    }
    func normalize(_ shelf: Shelf) throws { try save { renumber(ordered(shelf)) } }
    func sort(_ shelf: Shelf, by order: RecordSort) throws {
        try save { renumber(SortingService.sorted(shelf.copies, by: order)) }
    }
    func configure(_ shelf: Shelf, title: String, infoText: String, capacity: Int) throws {
        guard capacity > 0, capacity >= shelf.copies.count else { throw LibraryError.invalidCapacity }
        try save {
            shelf.name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            shelf.capacity = capacity
            let existing = try context.fetch(FetchDescriptor<ShelfCustomization>())
                .first { $0.shelfID == shelf.id }
            let customization = existing ?? ShelfCustomization(shelfID: shelf.id)
            if existing == nil { context.insert(customization) }
            customization.infoText = infoText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
