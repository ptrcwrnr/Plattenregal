import Foundation
import SwiftData

enum LibraryStorage {
    @MainActor static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV6.self)
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Plattenregal", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            config = ModelConfiguration("Plattenregal", schema: schema,
                url: directory.appendingPathComponent("Collection.store"), cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
        container.mainContext.autosaveEnabled = false
        try prepareShelves(in: container.mainContext)
        return container
    }

    // Gates the one-time V4→V5 name migration on a durable flag rather than on
    // "no ShelfCustomization row exists yet" — the latter also matches a row that
    // was legitimately created later and lost (partial sync, restore), which would
    // otherwise cause the user's real current shelf name to be wiped again.
    // Scoped per store file/identifier so that unrelated ModelContainers (different
    // stores, in-memory previews, tests) never contaminate one another's flag.
    private static func legacyNameMigrationKey(for container: ModelContainer) -> String {
        let identity = container.configurations.first?.url.absoluteString ?? "in-memory"
        return "LibraryStorage.legacyShelfNameMigratedV5:\(identity)"
    }

    @MainActor static func prepareShelves(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Shelf>())
        let customizations = try context.fetch(FetchDescriptor<ShelfCustomization>())
        var customizationByShelfID = Dictionary(
            customizations.map { ($0.shelfID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let migrationKey = legacyNameMigrationKey(for: context.container)
        let needsLegacyNameMigration = !UserDefaults.standard.bool(forKey: migrationKey)
        // Geometry describes the cabinet; copy positions and shelf identities are preserved.
        for shelf in existing {
            shelf.row = (shelf.number - 1) / ShelfGeometry.columns + 1
            shelf.column = (shelf.number - 1) % ShelfGeometry.columns + 1
            // Before V5 Shelf.name was shown as a secondary label. Move that
            // value into the new info field once, then reuse name as the full title.
            if let customization = customizationByShelfID[shelf.id] {
                if needsLegacyNameMigration, customization.infoText.isEmpty, !shelf.name.isEmpty {
                    customization.infoText = shelf.name
                    shelf.name = ""
                }
            } else {
                let infoText = needsLegacyNameMigration ? shelf.name : ""
                let customization = ShelfCustomization(shelfID: shelf.id, infoText: infoText)
                context.insert(customization)
                customizationByShelfID[shelf.id] = customization
                if needsLegacyNameMigration { shelf.name = "" }
            }
        }
        for number in 1...ShelfGeometry.count where !existing.contains(where: { $0.number == number }) {
            let shelf = Shelf(number: number)
            context.insert(shelf)
            context.insert(ShelfCustomization(shelfID: shelf.id))
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
        try context.save()
    }
}
