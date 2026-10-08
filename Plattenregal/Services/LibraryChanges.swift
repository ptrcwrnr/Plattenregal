import Foundation
import Observation
import SwiftData

/// What changed in the store, for pages that cache what they derive from it
/// (sorted lists, search indexes, shelf labels). Comparing `@Query` arrays
/// doesn't catch changed metadata on the same objects, so every write path
/// reports here what kind of data it touched, and pages rebuild on that:
///
/// - `PositionService.save` (and with it every shelf, cabinet, backup and
///   reset write) reports placements,
/// - `CabinetService` and restoring a backup report shelves,
/// - the Discogs sync, single-release reloads and resets report the library,
/// - the tracklist download reports tracks.
@Observable final class LibraryChanges {
    static let shared = LibraryChanges()

    /// Bumped after records or their metadata changed (sync, reloading
    /// single releases, reset). Collection lists and search indexes rebuild.
    private(set) var libraryVersion = 0
    /// Bumped whenever stored tracklists changed, so search indexes pick them up.
    private(set) var tracksVersion = 0
    /// Bumped when cabinets or compartments change (added, resized, renamed,
    /// switched on/off, removed, restored). Only shelf labels depend on that –
    /// the collection lists and search indexes don't need a rebuild.
    private(set) var shelvesVersion = 0
    /// Bumped after every committed position change (sorting in, moving,
    /// taking out). Range labels follow the records in the compartments, so
    /// pages caching them refresh – without the heavier `shelvesVersion` work.
    private(set) var placementsVersion = 0

    /// Records and their tracklists may have changed.
    func libraryDidChange() { libraryVersion += 1; tracksVersion += 1 }
    /// A sync committed: records and metadata, but no tracklists (those
    /// follow in the background and report themselves).
    func syncDidCommit() { libraryVersion += 1 }
    func tracksDidChange() { tracksVersion += 1 }
    func shelvesDidChange() { shelvesVersion += 1 }
    func placementsDidChange() { placementsVersion += 1 }
}

/// What a store holds, fetched once for all pages. With an `@Query` each,
/// SwiftData fetched every list anew for every page after every save – a
/// moved record, ten stored tracklists – and re-ran each page with all its
/// cover cells: about a third of a second each time for a collection of 900
/// records, the hidden pages included. Pages only need these lists for which
/// objects exist; changed data reaches them through Observation of the models
/// and `LibraryChanges`.
/// - Records and wantlist entries are fetched again only when a save inserted
///   or deleted some, from any context (the sync merges in the background).
/// - The small lists are read again after every save, but only replaced when
///   they differ, so the pages showing them don't re-run for nothing.
@Observable final class LibraryRecords {
    private(set) var copies: [RecordCopy] = []
    private(set) var wants: [WantlistEntry] = []
    /// By number.
    private(set) var shelves: [Shelf] = []
    /// By their order on the shelf page.
    private(set) var cabinets: [Cabinet] = []
    private(set) var exclusions: [OptimizationExclusion] = []
    private(set) var missingMarks: [MissingCopyMark] = []
    private(set) var accounts: [DiscogsAccount] = []
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private static var stores: [ObjectIdentifier: LibraryRecords] = [:]

    /// The lists of the store `context` belongs to (its main context's objects).
    static func of(_ context: ModelContext) -> LibraryRecords {
        let key = ObjectIdentifier(context.container)
        if let store = stores[key] { return store }
        let store = LibraryRecords(context: context.container.mainContext)
        stores[key] = store
        return store
    }

    private init(context: ModelContext) {
        self.context = context
        copies = (try? context.fetch(FetchDescriptor<RecordCopy>())) ?? []
        wants = (try? context.fetch(FetchDescriptor<WantlistEntry>())) ?? []
        reloadSmallLists()
        let container = ObjectIdentifier(context.container), main = ObjectIdentifier(context)
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] note in
            guard let saved = note.object as? ModelContext, ObjectIdentifier(saved.container) == container else { return }
            let changed = Self.membershipChanged(note)
            // Saved elsewhere (sync, tracklist download): the main context
            // keeps its old values of objects it holds until it fetches them
            // again – the per-page queries used to do that on every save.
            let updated = ObjectIdentifier(saved) == main ? [] : Self.identifiers(note, .updatedIdentifiers)
            // A save on the main context is reported right away, so no page
            // renders a record it deleted; a background save once it's merged.
            if Thread.isMainThread { MainActor.assumeIsolated { self?.saved(changed, updated: updated) } }
            else { DispatchQueue.main.async { self?.saved(changed, updated: updated) } }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    nonisolated private static func identifiers(_ note: Notification, _ key: ModelContext.NotificationKey) -> [PersistentIdentifier] {
        (note.userInfo?[key.rawValue] as? [PersistentIdentifier]) ?? []
    }

    nonisolated private static func membershipChanged(_ note: Notification) -> (copies: Bool, wants: Bool) {
        let entities = Set((identifiers(note, .insertedIdentifiers) + identifiers(note, .deletedIdentifiers)).map(\.entityName))
        return (entities.contains(Schema.entityName(for: RecordCopy.self)), entities.contains(Schema.entityName(for: WantlistEntry.self)))
    }

    private func saved(_ changed: (copies: Bool, wants: Bool), updated: [PersistentIdentifier]) {
        refetch(updated)
        reload(changed)
    }

    /// Fetches the given objects again, so the main context takes their saved values.
    private func refetch(_ ids: [PersistentIdentifier]) {
        guard !ids.isEmpty else { return }
        func refetch<T: PersistentModel>(_ type: T.Type) {
            let name = Schema.entityName(for: T.self)
            let wanted = ids.filter { $0.entityName == name }
            guard !wanted.isEmpty else { return }
            _ = try? context.fetch(FetchDescriptor<T>(predicate: #Predicate { wanted.contains($0.persistentModelID) }))
        }
        refetch(Release.self)
        refetch(RecordCopy.self)
        refetch(WantlistEntry.self)
        refetch(DiscogsAccount.self)
        refetch(DiscogsFolder.self)
        refetch(Shelf.self)
        refetch(Cabinet.self)
    }

    private func reload(_ changed: (copies: Bool, wants: Bool)) {
        if changed.copies { copies = (try? context.fetch(FetchDescriptor<RecordCopy>())) ?? [] }
        if changed.wants { wants = (try? context.fetch(FetchDescriptor<WantlistEntry>())) ?? [] }
        reloadSmallLists()
    }

    private func reloadSmallLists() {
        func update<T: PersistentModel>(_ list: ReferenceWritableKeyPath<LibraryRecords, [T]>, _ descriptor: FetchDescriptor<T>) {
            guard let fresh = try? context.fetch(descriptor), fresh != self[keyPath: list] else { return }
            self[keyPath: list] = fresh
        }
        update(\.shelves, FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\.number)]))
        update(\.cabinets, FetchDescriptor<Cabinet>(sortBy: [SortDescriptor(\.sortOrder)]))
        update(\.exclusions, FetchDescriptor<OptimizationExclusion>())
        update(\.missingMarks, FetchDescriptor<MissingCopyMark>())
        update(\.accounts, FetchDescriptor<DiscogsAccount>())
    }
}
