import SwiftUI
import SwiftData

/// One physical copy, even when several copies share the same release.
/// Both presentations use this snapshot, so a menu always acts on the copy
/// whose position is shown rather than on a release's first copy.
nonisolated struct ShelfCopyItem: Identifiable {
    let copy: RecordCopy
    let id: UUID
    let position: Int
    let artist: String
    let title: String
    /// 0 when unknown, so it sorts to one end instead of breaking the comparator.
    let year: Int
    let label: String
    let genre: String
    let sold: Bool
    let missing: Bool
    /// On the "Verkauf" list.
    let forSale: Bool

    init(_ copy: RecordCopy, release: ShelfCopyReleaseFields, owner: String?, missing: Bool, forSale: Bool) {
        self.copy = copy
        id = copy.id
        position = copy.positionInShelf
        artist = release.artist
        title = release.title
        year = release.year
        label = release.label
        genre = release.genre
        sold = copy.leftCurrentCollection(owner: owner)
        self.missing = missing
        self.forSale = forSale
    }

    /// SwiftData may publish the two sides of a relationship at different
    /// times after a move. The copy's current shelf is the final authority.
    @MainActor static func snapshot(for shelf: Shelf, owner: String?, missing: Set<UUID>, forSale: Set<UUID>) -> [ShelfCopyItem] {
        // By the model's identifier, read once: see `Shelf.recordCount`.
        let me = shelf.persistentModelID
        let copies = shelf.copies.filter { !$0.isDeleted && $0.shelf?.persistentModelID == me }
        return PositionService.inShelfOrder(copies).map {
            ShelfCopyItem($0, release: .of($0), owner: owner, missing: missing.contains($0.id), forSale: forSale.contains($0.id))
        }
    }
}

/// What a compartment's tiles and table rows show of a record's release,
/// kept per record until record data changes (`libraryVersion`, like
/// `ShelfSortKeys`). After every save SwiftData fetches each release again
/// one by one on the next read: sorting in a record or moving one with the
/// position slider re-read the whole compartment behind it (~20 ms for 150).
nonisolated struct ShelfCopyReleaseFields {
    let artist: String
    let title: String
    /// 0 when unknown, so it sorts to one end instead of breaking the comparator.
    let year: Int
    let label: String
    let genre: String

    @MainActor private static var cache: [PersistentIdentifier: ShelfCopyReleaseFields] = [:]
    @MainActor private static var version: Int?

    @MainActor static func of(_ copy: RecordCopy) -> ShelfCopyReleaseFields {
        let current = LibraryChanges.shared.libraryVersion
        if version != current { cache = [:]; version = current }
        let id = copy.persistentModelID
        if let fields = cache[id] { return fields }
        let release = copy.release
        let fields = ShelfCopyReleaseFields(artist: release?.displayArtist ?? "—", title: release?.displayTitle ?? "—",
                                            year: release?.year ?? 0, label: release?.displayLabel ?? "",
                                            genre: release?.primaryStyle ?? "")
        cache[id] = fields
        return fields
    }
}

/// Kept by the shelf page, including while an empty or reserved compartment
/// replaces this view. Scroll positions belong to one compartment and one
/// presentation; switching between them never overwrites the other's place.
@Observable final class ShelfContentsSession {
    // Not observed: the scroll views write them whenever another row reaches
    // the top, and an observed change re-ran the whole cover grid each time.
    // Restoring a place scrolls explicitly (`ScrollViewProxy`, the table's
    // scroll bridge), so no view needs to follow them.
    @ObservationIgnored var gridScrollPositions: [UUID: UUID] = [:]
    @ObservationIgnored var listScrollPositions: [UUID: UUID] = [:]
    var tableSortOrder = [KeyPathComparator(\ShelfCopyItem.position)]
}
