import Foundation
import SwiftData

// The versions of the SwiftData store and the plan that migrates between
// them. The app opens the store with the newest version (see LibraryStorage);
// the typealiases after V16 name its current models. Released versions stay
// frozen: changes go into a new VersionedSchema with a stage in the plan.
//
// V1–V14 (and their migrations) are gone: every store ever opened by a
// released build is V15 or newer. An older store can't be opened any more
// (SwiftData reports `unknownDataStoreSchema`, the app shows its error page).

// V15 keeps only what the app uses; compared with V14 it dropped
// the copy's Discogs rating, notes and sync date; the wantlist entry's rating
// and sync date; the folder's and account's folder-sync dates; the snapshot's
// unique-release count; the creation dates of "Ohne Regalplatz" and
// "Gesucht"; and `ReleaseMarketValue`, which was never filled.
enum LibrarySchemaV15: VersionedSchema {
    static let versionIdentifier = Schema.Version(15, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Release.self, RecordCopy.self, Shelf.self, Cabinet.self, WantlistEntry.self,
         DiscogsFolder.self, DiscogsAccount.self, CollectionValueSnapshot.self,
         OptimizationExclusion.self, MissingCopyMark.self]
    }

    @Model final class Cabinet {
        @Attribute(.unique) var id: UUID
        var name: String
        var rows: Int
        var columns: Int
        /// Inactive cabinets keep their records but are hidden on the shelf
        /// page and skipped when sorting in (e.g. records put into storage).
        var isActive: Bool = true
        var sortOrder: Int
        @Relationship(deleteRule: .cascade, inverse: \Shelf.cabinet) var shelves: [Shelf] = []
        init(name: String, rows: Int, columns: Int, sortOrder: Int) {
            id = UUID(); self.name = name; self.rows = rows; self.columns = columns
            self.sortOrder = sortOrder; isActive = true
        }
    }

    @Model final class Release {
        // One release per Discogs ID.
        #Unique<Release>([\.discogsID])
        @Attribute(.unique) var id: UUID
        var discogsID: Int = 0
        var masterID: Int?
        var basicInformation: Data?
        var artist: String
        var title: String
        var year: Int?
        var label: String
        var catalogNumber: String
        var country: String
        var format: String
        var genres: [String]
        var styles: [String]
        var tracks: [Track]
        var coverURL: String?
        var fetchedAt: Date?
        /// When the full Discogs release (tracklist, country) was last loaded.
        /// `nil` = never; decides which tracklists to (re)load after a sync.
        var detailsFetchedAt: Date?
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.release) var copies: [RecordCopy] = []
        init(discogsID: Int, artist: String, title: String) {
            id = UUID(); self.discogsID = discogsID; self.artist = artist; self.title = title
            label = ""; catalogNumber = ""; country = ""; format = "Vinyl"
            genres = []; styles = []; tracks = []
        }
        // Stored names keep Discogs' "(3)" suffix (search and re-sync rely on the
        // raw value); only what is shown drops it.
        var displayArtist: String { artist.isEmpty ? String(localized: "Unbekannter Interpret") : DiscogsName.clean(artist) }
        var displayLabel: String { DiscogsName.clean(label) }
        var displayTitle: String { title.isEmpty ? String(localized: "Release #\(String(discogsID))") : title }
        /// None in the demo: its sample IDs belong to unrelated releases on Discogs.
        var sourceURL: URL? { DemoMode.isActive ? nil : URL(string: "https://www.discogs.com/release/\(discogsID)") }
    }

    @Model final class RecordCopy {
        @Attribute(.unique) var id: UUID
        var release: Release?
        var shelf: Shelf?
        var discogsInstanceID: Int = 0
        var discogsOwner: String = ""
        var discogsFolderID: Int?
        var discogsDateAdded: String?
        /// `false` once the copy left the collection (sold, other account); it
        /// keeps its shelf place until removed on the shelf page.
        var discogsActive: Bool = true
        var positionInShelf: Int
        init(release: Release, instanceID: Int, owner: String, shelf: Shelf? = nil, position: Int = 0) {
            id = UUID(); self.release = release; self.shelf = shelf
            discogsInstanceID = instanceID; discogsOwner = owner; discogsActive = true
            positionInShelf = position
        }
    }

    @Model final class Shelf {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var number: Int
        var row: Int
        var column: Int
        var name: String
        /// Not meant for records (e.g. "Vivian"); skipped when sorting in.
        var isReserved: Bool = false
        /// Place inside the cabinet, 1…rows × columns in reading order.
        var sortOrder: Int
        var cabinet: Cabinet?
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.shelf) var copies: [RecordCopy] = []
        init(number: Int, cabinet: Cabinet? = nil, slot: Int? = nil) {
            let slot = slot ?? number
            let columns = cabinet?.columns ?? ShelfGeometry.columns
            id = UUID(); self.number = number; sortOrder = slot
            row = (slot - 1) / columns + 1; column = (slot - 1) % columns + 1; name = ""
        }
        var title: String { name.isEmpty ? String(localized: "Fach \(sortOrder)") : name }
    }

    @Model final class WantlistEntry {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var release: Release?
        var dateAdded: String?
        var notes: String?
        init(owner: String, release: Release, releaseID: Int) {
            self.owner = owner; self.release = release; self.releaseID = releaseID
            key = "\(owner)-\(releaseID)"
        }
    }

    @Model final class DiscogsFolder {
        @Attribute(.unique) var key: String
        var owner: String
        var folderID: Int
        var name: String
        var count: Int
        init(owner: String, id: Int, name: String, count: Int) {
            self.owner = owner; folderID = id; self.name = name; self.count = count
            key = "\(owner)-\(id)"
        }
    }

    @Model final class DiscogsAccount {
        @Attribute(.unique) var username: String
        var userID: Int?
        var credentialFingerprint: String?
        var lastCollectionSync: Date?
        var lastWantlistSync: Date?
        var lastFullSync: Date?
        init(username: String) { self.username = username }
    }

    @Model final class CollectionValueSnapshot {
        @Attribute(.unique) var id: UUID
        var owner: String
        var date: Date
        var minimumValue: Decimal
        var medianValue: Decimal
        var maximumValue: Decimal
        var currency: String
        var collectionItemCount: Int
        var collectionSignature: String
        init(owner: String, date: Date, value: DiscogsCollectionValue, count: Int, signature: String) {
            id = UUID(); self.owner = owner; self.date = date
            minimumValue = value.minimum.amount; medianValue = value.median.amount; maximumValue = value.maximum.amount
            currency = value.median.currency; collectionItemCount = count; collectionSignature = signature
        }
        // A collection statistic, not the mean realized sale price of its releases.
        var averagePerItem: Decimal? { collectionItemCount > 0 ? medianValue / Decimal(collectionItemCount) : nil }
    }

    /// "Ohne Regalplatz": kept out of the shelf allocation.
    @Model final class OptimizationExclusion {
        @Attribute(.unique) var copyID: UUID
        init(copyID: UUID) { self.copyID = copyID }
    }

    /// "Gesucht": should stand in a shelf but wasn't found there.
    @Model final class MissingCopyMark {
        @Attribute(.unique) var copyID: UUID
        init(copyID: UUID) { self.copyID = copyID }
    }
}

// V16 adds a local-only "Verkauf" mark for records meant to be sold some
// day. Stored separately like "Gesucht", so every model of V15 is carried
// over unchanged.
enum LibrarySchemaV16: VersionedSchema {
    static let versionIdentifier = Schema.Version(16, 0, 0)
    static var models: [any PersistentModel.Type] {
        LibrarySchemaV15.models + [SaleCopyMark.self]
    }

    /// "Verkauf": to be sold some day; stays where it stands until then.
    @Model final class SaleCopyMark {
        @Attribute(.unique) var copyID: UUID
        init(copyID: UUID) { self.copyID = copyID }
    }
}

// V17 adds the YouTube videos Discogs lists for a release (`ReleaseVideoList`),
// again as a model of its own, so V15 and V16 are carried over unchanged.
enum LibrarySchemaV17: VersionedSchema {
    static let versionIdentifier = Schema.Version(17, 0, 0)
    static var models: [any PersistentModel.Type] {
        LibrarySchemaV16.models + [ReleaseVideoList.self]
    }

    /// The videos of one Discogs release, as Discogs lists them. Stored raw,
    /// matched to the tracks when the popover shows them (`TrackVideoMatcher`).
    /// A row without videos means: asked, Discogs has none.
    @Model final class ReleaseVideoList {
        @Attribute(.unique) var discogsID: Int
        var videos: [ReleaseVideo]
        init(discogsID: Int, videos: [ReleaseVideo]) { self.discogsID = discogsID; self.videos = videos }
    }
}

// V18 adds the shelf page's history ("Verlauf"): every record sorted in,
// moved or taken out, so it can be undone later – a model of its own, so
// V15–V17 are carried over unchanged.
enum LibrarySchemaV18: VersionedSchema {
    static let versionIdentifier = Schema.Version(18, 0, 0)
    static var models: [any PersistentModel.Type] {
        LibrarySchemaV17.models + [ShelfHistoryEntry.self]
    }

    /// One change of a record's place: from a compartment (or none) to a
    /// compartment (or none). Names and titles are kept as they were, so the
    /// entry still reads right once the record or compartment is gone.
    @Model final class ShelfHistoryEntry {
        @Attribute(.unique) var id: UUID
        var date: Date
        var copyID: UUID
        var artist: String
        var title: String
        /// `nil`: the record had no compartment before (sorted in).
        var fromShelfID: UUID?
        var fromPosition: Int
        /// „KALLAX · Fach 4“ at the time.
        var fromName: String
        /// `nil`: the record left the shelves (taken out).
        var toShelfID: UUID?
        var toPosition: Int
        var toName: String
        /// Sorting in lifted „Gesucht“ / „Ohne Regalplatz“; undoing restores them.
        var clearedMissing: Bool
        var clearedExclusion: Bool
        /// Set once it was undone; the entry stays, marked as such.
        var undoneAt: Date?

        init(copyID: UUID, artist: String, title: String,
             fromShelfID: UUID?, fromPosition: Int, fromName: String,
             toShelfID: UUID?, toPosition: Int, toName: String,
             clearedMissing: Bool = false, clearedExclusion: Bool = false, date: Date = .now) {
            id = UUID()
            self.date = date
            self.copyID = copyID
            self.artist = artist
            self.title = title
            self.fromShelfID = fromShelfID
            self.fromPosition = fromPosition
            self.fromName = fromName
            self.toShelfID = toShelfID
            self.toPosition = toPosition
            self.toName = toName
            self.clearedMissing = clearedMissing
            self.clearedExclusion = clearedExclusion
        }
    }
}

// The current schema is V18 (see `LibraryStorage`); its models are those of
// V15 plus `SaleCopyMark`, `ReleaseVideoList` and `ShelfHistoryEntry`.
typealias Release = LibrarySchemaV15.Release
typealias RecordCopy = LibrarySchemaV15.RecordCopy
typealias Shelf = LibrarySchemaV15.Shelf
typealias Cabinet = LibrarySchemaV15.Cabinet
typealias WantlistEntry = LibrarySchemaV15.WantlistEntry
typealias DiscogsFolder = LibrarySchemaV15.DiscogsFolder
typealias DiscogsAccount = LibrarySchemaV15.DiscogsAccount
typealias CollectionValueSnapshot = LibrarySchemaV15.CollectionValueSnapshot
typealias OptimizationExclusion = LibrarySchemaV15.OptimizationExclusion
typealias MissingCopyMark = LibrarySchemaV15.MissingCopyMark
typealias SaleCopyMark = LibrarySchemaV16.SaleCopyMark
typealias ReleaseVideoList = LibrarySchemaV17.ReleaseVideoList
typealias ShelfHistoryEntry = LibrarySchemaV18.ShelfHistoryEntry

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV15.self, LibrarySchemaV16.self, LibrarySchemaV17.self, LibrarySchemaV18.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LibrarySchemaV15.self, toVersion: LibrarySchemaV16.self),
         .lightweight(fromVersion: LibrarySchemaV16.self, toVersion: LibrarySchemaV17.self),
         .lightweight(fromVersion: LibrarySchemaV17.self, toVersion: LibrarySchemaV18.self)]
    }
}
