import Foundation
import SwiftData

/// The KALLAX sizes IKEA sells, as columns × rows. The narrow and wide ones
/// stand upright or on their side.
nonisolated struct KallaxPreset: Identifiable, Hashable {
    let columns: Int
    let rows: Int
    var id: String { "\(columns)x\(rows)" }
    var count: Int { columns * rows }

    /// "2 × 4" – columns first, like IKEA's width × height.
    var title: String { "\(columns) × \(rows)" }
    var orientation: String? {
        if columns == rows { return nil }
        return columns < rows ? "hochkant" : "quer"
    }

    static let all: [KallaxPreset] = [
        .init(columns: 1, rows: 1),
        .init(columns: 1, rows: 2), .init(columns: 2, rows: 1),
        .init(columns: 2, rows: 2),
        .init(columns: 1, rows: 4), .init(columns: 4, rows: 1),
        .init(columns: 2, rows: 4), .init(columns: 4, rows: 2),
        .init(columns: 4, rows: 3), .init(columns: 3, rows: 4),
        .init(columns: 4, rows: 4),
        .init(columns: 5, rows: 5),
    ]

    static func matching(columns: Int, rows: Int) -> KallaxPreset? {
        all.first { $0.columns == columns && $0.rows == rows }
    }
}

enum CabinetError: LocalizedError {
    case shelvesNotEmpty(Int), lastActive, lastCabinet, notEmpty, invalidSize
    var errorDescription: String? {
        switch self {
        case .shelvesNotEmpty(let count):
            "So klein geht es gerade nicht: In den Fächern, die wegfallen würden, \(count == 1 ? "steht noch 1 Platte" : "stehen noch \(count) Platten"). Nimm sie zuerst heraus oder wähle eine größere Variante."
        case .lastActive: "Mindestens ein Regal muss aktiv bleiben – sonst gäbe es keinen Platz zum Einsortieren."
        case .lastCabinet: "Das letzte Regal lässt sich nicht löschen."
        case .notEmpty: "Nur leere Regale lassen sich löschen. Nimm die Platten zuerst heraus oder deaktiviere das Regal stattdessen."
        case .invalidSize: "Ein Regal hat 1 bis 6 Reihen und Spalten."
        }
    }
}

/// Adding, resizing, switching and removing cabinets. Every write goes
/// through `PositionService.save`, so it is one transaction and triggers
/// the automatic backup like any other change to the shelf.
struct CabinetService {
    let context: ModelContext
    private var positions: PositionService { PositionService(context: context) }

    /// Pages that cache shelf labels refresh on `shelvesVersion`. Not
    /// `libraryDidChange()`: that rebuilds every collection list and search
    /// index, although no record changed.
    private func save(_ action: () throws -> Void) throws {
        try positions.save(action)
        LibraryChanges.shared.shelvesDidChange()
    }

    func cabinets() throws -> [Cabinet] {
        try context.fetch(FetchDescriptor<Cabinet>(sortBy: [SortDescriptor(\Cabinet.sortOrder)]))
    }

    /// "Regal 2", "Regal 3" … – the first free one.
    func suggestedName() -> String {
        let names = Set(((try? cabinets()) ?? []).map(\.name))
        return (2...).lazy.map { "Regal \($0)" }.first { !names.contains($0) }!
    }

    @discardableResult func add(name: String, columns: Int, rows: Int) throws -> Cabinet {
        try validate(columns: columns, rows: rows)
        var result: Cabinet!
        try save {
            let order = (try cabinets().map(\.sortOrder).max() ?? -1) + 1
            let cabinet = Cabinet(name: cleaned(name, fallback: "Regal \(order + 1)"), rows: rows, columns: columns, sortOrder: order)
            context.insert(cabinet)
            var number = try nextNumber()
            for slot in 1...(rows * columns) {
                Shelf.insert(number: number, cabinet: cabinet, slot: slot, in: context)
                number += 1
            }
            result = cabinet
        }
        AppLog.info("Regal", "Regal „\(result.name)“ angelegt (\(columns) × \(rows))")
        return result
    }

    /// Compartments keep their reading order (top left first); when the
    /// cabinet shrinks, the last ones go – only if they hold no records.
    func resize(_ cabinet: Cabinet, columns: Int, rows: Int) throws {
        try validate(columns: columns, rows: rows)
        guard columns != cabinet.columns || rows != cabinet.rows else { return }
        let ordered = cabinet.orderedShelves
        let count = columns * rows
        let dropped = ordered.dropFirst(count)
        let stranded = dropped.reduce(0) { $0 + $1.copies.count }
        guard stranded == 0 else { throw CabinetError.shelvesNotEmpty(stranded) }
        let before = cabinet.sizeText
        try save {
            for shelf in dropped { context.delete(shelf) }
            cabinet.columns = columns; cabinet.rows = rows
            for (index, shelf) in ordered.prefix(count).enumerated() { place(shelf, slot: index + 1, columns: columns) }
            if ordered.count < count {
                var number = try nextNumber()
                for slot in (ordered.count + 1)...count {
                    Shelf.insert(number: number, cabinet: cabinet, slot: slot, in: context)
                    number += 1
                }
            }
        }
        AppLog.info("Regal", "Regal „\(cabinet.name)“: \(before) → \(cabinet.sizeText)")
    }

    func rename(_ cabinet: Cabinet, to name: String) throws {
        let name = cleaned(name, fallback: cabinet.name)
        guard name != cabinet.name else { return }
        try save { cabinet.name = name }
        AppLog.info("Regal", "Regal umbenannt in „\(name)“")
    }

    /// Records in an inactive cabinet keep their places; they are only
    /// hidden on the shelf page and skipped when sorting in.
    func setActive(_ cabinet: Cabinet, _ active: Bool) throws {
        guard active != cabinet.isActive else { return }
        if !active, try !cabinets().contains(where: { $0.isActive && $0.id != cabinet.id }) { throw CabinetError.lastActive }
        try save { cabinet.isActive = active }
        AppLog.info("Regal", "Regal „\(cabinet.name)“ \(active ? "aktiviert" : "deaktiviert")")
    }

    func delete(_ cabinet: Cabinet) throws {
        let all = try cabinets()
        guard all.count > 1 else { throw CabinetError.lastCabinet }
        guard cabinet.recordCount == 0 else { throw CabinetError.notEmpty }
        if cabinet.isActive, !all.contains(where: { $0.isActive && $0.id != cabinet.id }) { throw CabinetError.lastActive }
        let name = cabinet.name
        try save {
            for shelf in cabinet.shelves { context.delete(shelf) }
            context.delete(cabinet)
        }
        AppLog.info("Regal", "Regal „\(name)“ gelöscht")
    }

    /// Moves a cabinet one place up (-1) or down (+1) in the list and on the shelf page.
    func move(_ cabinet: Cabinet, by offset: Int) throws {
        var all = try cabinets()
        guard let index = all.firstIndex(where: { $0.id == cabinet.id }), all.indices.contains(index + offset) else { return }
        all.swapAt(index, index + offset)
        try save { for (order, item) in all.enumerated() { item.sortOrder = order } }
    }

    private func place(_ shelf: Shelf, slot: Int, columns: Int) {
        shelf.sortOrder = slot
        shelf.row = (slot - 1) / columns + 1
        shelf.column = (slot - 1) % columns + 1
    }

    private func nextNumber() throws -> Int {
        (try context.fetch(FetchDescriptor<Shelf>()).map(\.number).max() ?? 0) + 1
    }

    private func validate(columns: Int, rows: Int) throws {
        guard ShelfGeometry.sizeRange.contains(columns), ShelfGeometry.sizeRange.contains(rows) else { throw CabinetError.invalidSize }
    }

    private func cleaned(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
