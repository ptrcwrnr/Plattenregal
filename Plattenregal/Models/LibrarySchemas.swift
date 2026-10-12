import Foundation
import SwiftData
import OSLog

// Every version of the SwiftData store, oldest first, and the plan that
// migrates between them. The app opens the store with the newest version
// (see LibraryStorage); the typealiases after V15 name its current models.
// Released versions stay frozen: changes go into a new VersionedSchema.

// Freeze V1 when shipping. Future changes belong in a new VersionedSchema.
enum LibrarySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Release.self, RecordCopy.self, Shelf.self] }

    @Model final class Release {
        @Attribute(.unique) var id: UUID
        var discogsID: Int?
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
        var discogsURL: String?
        var fetchedAt: Date?
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.release) var copies: [RecordCopy] = []
        init(artist: String, title: String) {
            id = UUID(); self.artist = artist; self.title = title
            label = ""; catalogNumber = ""; country = ""; format = "Vinyl"
            genres = []; styles = []; tracks = []
        }
        func updateMetadata(from other: Release) {
            artist = other.artist; title = other.title; year = other.year; label = other.label
            catalogNumber = other.catalogNumber; country = other.country; format = other.format
            genres = other.genres; styles = other.styles; tracks = other.tracks
            coverURL = other.coverURL; discogsURL = other.discogsURL; fetchedAt = other.fetchedAt
        }
        var isFresh: Bool { discogsID == nil || (fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false) }
        // Freshness decides when Discogs should be contacted again. It must never hide
        // the last successfully stored metadata while the app is offline or starting up.
        var displayArtist: String { artist.isEmpty ? "Unbekannter Interpret" : artist }
        var displayTitle: String { title.isEmpty ? "Release #\(discogsID ?? 0)" : title }
        var sourceURL: URL? { discogsID.flatMap { URL(string: "https://www.discogs.com/release/\($0)") } }
    }

    @Model final class RecordCopy {
        @Attribute(.unique) var id: UUID
        var release: Release?
        var shelf: Shelf?
        var positionInShelf: Int
        var condition: String
        var purchasePrice: Decimal?
        var purchaseDate: Date?
        var notes: String
        var favorite: Bool
        var dateAdded: Date
        init(release: Release, shelf: Shelf, position: Int) {
            id = UUID(); self.release = release; self.shelf = shelf
            positionInShelf = position; condition = "Nicht bewertet"; notes = ""
            favorite = false; dateAdded = .now
        }
        var location: String { "Fach \(shelf?.number ?? 0) · Position \(positionInShelf)" }
    }

    @Model final class Shelf {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var number: Int
        var row: Int
        var column: Int
        var name: String
        var capacity: Int
        var sortOrder: Int
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.shelf) var copies: [RecordCopy] = []
        init(number: Int, capacity: Int = 90) {
            id = UUID(); self.number = number; row = (number - 1) / ShelfGeometry.columns + 1
            column = (number - 1) % ShelfGeometry.columns + 1; name = ""; self.capacity = capacity; sortOrder = number
        }
        var title: String { name.isEmpty ? "Fach \(number)" : "Fach \(number) · \(name)" }
    }
}
enum LibrarySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Release.self, RecordCopy.self, Shelf.self, DiscogsFolder.self, WantlistEntry.self, DiscogsAccount.self] }

    @Model final class Release {
        @Attribute(.unique) var id: UUID
        var discogsID: Int?
        var masterID: Int?
        var resourceURL: String?
        var thumbURL: String?
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
        var discogsURL: String?
        var fetchedAt: Date?
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.release) var copies: [RecordCopy] = []
        init(artist: String, title: String) {
            id = UUID(); self.artist = artist; self.title = title
            label = ""; catalogNumber = ""; country = ""; format = "Vinyl"
            genres = []; styles = []; tracks = []
        }
        func updateMetadata(from other: Release) {
            // Preserve the structured identities when refreshing an existing imported release.
            if let basic = other.basicInformation { basicInformation = basic }
            masterID = other.masterID; resourceURL = other.resourceURL; thumbURL = other.thumbURL
            artist = other.artist; title = other.title; year = other.year; label = other.label
            catalogNumber = other.catalogNumber; country = other.country; format = other.format
            genres = other.genres; styles = other.styles; tracks = other.tracks
            coverURL = other.coverURL; discogsURL = other.discogsURL; fetchedAt = other.fetchedAt
        }
        var isFresh: Bool { discogsID == nil || (fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false) }
        // Freshness decides when Discogs should be contacted again. It must never hide
        // the last successfully stored metadata while the app is offline or starting up.
        var displayArtist: String { artist.isEmpty ? "Unbekannter Interpret" : artist }
        var displayTitle: String { title.isEmpty ? "Release #\(discogsID ?? 0)" : title }
        var sourceURL: URL? { discogsID.flatMap { URL(string: "https://www.discogs.com/release/\($0)") } }
    }

    @Model final class RecordCopy {
        @Attribute(.unique) var id: UUID
        var release: Release?
        var shelf: Shelf?
        var discogsInstanceID: Int?
        var discogsOwner: String?
        var discogsFolderID: Int?
        var discogsDateAdded: String?
        var discogsRating: Int?
        var discogsNotes: Data?
        var lastDiscogsSync: Date?
        var discogsActive: Bool?
        var positionInShelf: Int
        var condition: String
        var purchasePrice: Decimal?
        var purchaseDate: Date?
        var notes: String
        var favorite: Bool
        var dateAdded: Date
        init(release: Release, shelf: Shelf? = nil, position: Int = 0) {
            id = UUID(); self.release = release; self.shelf = shelf
            positionInShelf = position; condition = "Nicht bewertet"; notes = ""
            favorite = false; dateAdded = .now
        }
        var location: String { guard let shelf else { return "Noch keinem Fach zugeordnet" }; return "\(shelf.title) · Position \(positionInShelf)" }
    }

    @Model final class Shelf {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var number: Int
        var row: Int
        var column: Int
        var name: String
        var capacity: Int
        var sortOrder: Int
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.shelf) var copies: [RecordCopy] = []
        init(number: Int, capacity: Int = 90) {
            id = UUID(); self.number = number; row = (number - 1) / ShelfGeometry.columns + 1
            column = (number - 1) % ShelfGeometry.columns + 1; name = ""; self.capacity = capacity; sortOrder = number
        }
        var title: String { name.isEmpty ? "Fach \(number)" : name }
    }

    @Model final class DiscogsFolder {
        @Attribute(.unique) var key: String
        var owner: String
        var folderID: Int
        var name: String
        var count: Int
        var lastSync: Date?
        init(owner: String, id: Int, name: String, count: Int) {
            self.owner = owner; folderID = id; self.name = name; self.count = count
            key = "\(owner)-\(id)"
        }
    }
    @Model final class WantlistEntry {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var release: Release?
        var dateAdded: String?
        var rating: Int?
        var notes: String?
        var lastDiscogsSync: Date?
        init(owner: String, release: Release, releaseID: Int) {
            self.owner = owner; self.release = release; self.releaseID = releaseID
            key = "\(owner)-\(releaseID)"
        }
    }
    @Model final class DiscogsAccount {
        @Attribute(.unique) var username: String
        var userID: Int?
        var credentialFingerprint: String?
        var lastCollectionSync: Date?
        var lastWantlistSync: Date?
        var lastFolderSync: Date?
        var lastFullSync: Date?
        init(username: String) { self.username = username }
    }
}

// V1 and V2 remain frozen. The existing model types and relationships are unchanged.
enum LibrarySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        LibrarySchemaV2.models + [LibrarySchemaV3.CollectionValueSnapshot.self, LibrarySchemaV3.ReleaseMarketValue.self]
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
        var uniqueReleaseCount: Int
        var collectionSignature: String
        init(owner: String, date: Date, value: DiscogsCollectionValue, count: Int, unique: Int, signature: String) {
            id = UUID(); self.owner = owner; self.date = date
            minimumValue = value.minimum.amount; medianValue = value.median.amount; maximumValue = value.maximum.amount
            currency = value.median.currency; collectionItemCount = count; uniqueReleaseCount = unique; collectionSignature = signature
        }
        // A collection statistic, not the mean realized sale price of its releases.
        var averagePerItem: Decimal? { collectionItemCount > 0 ? medianValue / Decimal(collectionItemCount) : nil }
    }
    @Model final class ReleaseMarketValue {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var estimatedValue: Decimal?
        var currency: String
        var condition: String
        var source: String
        var updatedAt: Date
        init(owner: String, releaseID: Int, value: Decimal?, currency: String, condition: String, source: String, date: Date = .now) {
            key = "\(owner)|\(releaseID)|\(source)"; self.owner = owner; self.releaseID = releaseID
            estimatedValue = value; self.currency = currency; self.condition = condition; self.source = source; updatedAt = date
        }
        var stale: Bool { Date().timeIntervalSince(updatedAt) >= 7 * 86400 }
    }
}

// V4 adds durable local-only optimization preferences without changing the
// frozen Discogs collection models from V2.
enum LibrarySchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        LibrarySchemaV3.models + [LibrarySchemaV4.OptimizationExclusion.self]
    }

    @Model final class OptimizationExclusion {
        @Attribute(.unique) var copyID: UUID
        var createdAt: Date

        init(copyID: UUID, createdAt: Date = .now) {
            self.copyID = copyID
            self.createdAt = createdAt
        }
    }
}

// V5 keeps the established Shelf model intact and stores the new descriptive
// text separately. Shelf.name can therefore become the full visible title,
// while existing values (for example "A-B") are migrated losslessly into
// ShelfCustomization.infoText by LibraryStorage.
enum LibrarySchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        LibrarySchemaV4.models + [ShelfCustomization.self]
    }

    @Model final class ShelfCustomization {
        @Attribute(.unique) var shelfID: UUID
        var infoText: String

        init(shelfID: UUID, infoText: String = "") {
            self.shelfID = shelfID
            self.infoText = infoText
        }
    }
}

// V6 drops the "favorite" flag now that the feature has been removed. Release
// and Shelf are brought forward unchanged, since their relationships to
// RecordCopy must point at this version's RecordCopy type.
enum LibrarySchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Release.self, RecordCopy.self, Shelf.self,
         LibrarySchemaV2.DiscogsFolder.self, WantlistEntry.self, LibrarySchemaV2.DiscogsAccount.self,
         LibrarySchemaV3.CollectionValueSnapshot.self, LibrarySchemaV3.ReleaseMarketValue.self,
         LibrarySchemaV4.OptimizationExclusion.self, LibrarySchemaV5.ShelfCustomization.self]
    }

    @Model final class Release {
        @Attribute(.unique) var id: UUID
        var discogsID: Int?
        var masterID: Int?
        var resourceURL: String?
        var thumbURL: String?
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
        var discogsURL: String?
        var fetchedAt: Date?
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.release) var copies: [RecordCopy] = []
        init(artist: String, title: String) {
            id = UUID(); self.artist = artist; self.title = title
            label = ""; catalogNumber = ""; country = ""; format = "Vinyl"
            genres = []; styles = []; tracks = []
        }
        func updateMetadata(from other: Release) {
            if let basic = other.basicInformation { basicInformation = basic }
            masterID = other.masterID; resourceURL = other.resourceURL; thumbURL = other.thumbURL
            artist = other.artist; title = other.title; year = other.year; label = other.label
            catalogNumber = other.catalogNumber; country = other.country; format = other.format
            genres = other.genres; styles = other.styles; tracks = other.tracks
            coverURL = other.coverURL; discogsURL = other.discogsURL; fetchedAt = other.fetchedAt
        }
        var isFresh: Bool { discogsID == nil || (fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false) }
        var displayArtist: String { artist.isEmpty ? "Unbekannter Interpret" : artist }
        var displayTitle: String { title.isEmpty ? "Release #\(discogsID ?? 0)" : title }
        var sourceURL: URL? { discogsID.flatMap { URL(string: "https://www.discogs.com/release/\($0)") } }
    }

    @Model final class RecordCopy {
        @Attribute(.unique) var id: UUID
        var release: Release?
        var shelf: Shelf?
        var discogsInstanceID: Int?
        var discogsOwner: String?
        var discogsFolderID: Int?
        var discogsDateAdded: String?
        var discogsRating: Int?
        var discogsNotes: Data?
        var lastDiscogsSync: Date?
        var discogsActive: Bool?
        var positionInShelf: Int
        var condition: String
        var purchasePrice: Decimal?
        var purchaseDate: Date?
        var notes: String
        var dateAdded: Date
        init(release: Release, shelf: Shelf? = nil, position: Int = 0) {
            id = UUID(); self.release = release; self.shelf = shelf
            positionInShelf = position; condition = "Nicht bewertet"; notes = ""
            dateAdded = .now
        }
        var location: String { guard let shelf else { return "Noch keinem Fach zugeordnet" }; return "\(shelf.title) · Position \(positionInShelf)" }
    }

    @Model final class Shelf {
        @Attribute(.unique) var id: UUID
        @Attribute(.unique) var number: Int
        var row: Int
        var column: Int
        var name: String
        var capacity: Int
        var sortOrder: Int
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.shelf) var copies: [RecordCopy] = []
        init(number: Int, capacity: Int = 90) {
            id = UUID(); self.number = number; row = (number - 1) / ShelfGeometry.columns + 1
            column = (number - 1) % ShelfGeometry.columns + 1; name = ""; self.capacity = capacity; sortOrder = number
        }
        var title: String { name.isEmpty ? "Fach \(number)" : name }
    }

    // Brought forward from V2 unchanged, other than pointing at this version's Release.
    @Model final class WantlistEntry {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var release: Release?
        var dateAdded: String?
        var rating: Int?
        var notes: String?
        var lastDiscogsSync: Date?
        init(owner: String, release: Release, releaseID: Int) {
            self.owner = owner; self.release = release; self.releaseID = releaseID
            key = "\(owner)-\(releaseID)"
        }
    }
}
// V7 drops ShelfCustomization (the per-shelf info text): shelf labels are now
// derived from the contents. Existing info texts are discarded; every other
// model is carried over unchanged.
enum LibrarySchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] {
        [LibrarySchemaV6.Release.self, LibrarySchemaV6.RecordCopy.self, LibrarySchemaV6.Shelf.self,
         LibrarySchemaV2.DiscogsFolder.self, LibrarySchemaV6.WantlistEntry.self, LibrarySchemaV2.DiscogsAccount.self,
         LibrarySchemaV3.CollectionValueSnapshot.self, LibrarySchemaV3.ReleaseMarketValue.self, LibrarySchemaV4.OptimizationExclusion.self]
    }
}

// V8 replaces the per-shelf capacity with an explicit `isReserved` flag: shelves
// hold as many records as physically fit, and capacity 0 (the old way to mark a
// reserved compartment) becomes isReserved = true during migration.
enum LibrarySchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Release.self, RecordCopy.self, Shelf.self,
         LibrarySchemaV2.DiscogsFolder.self, WantlistEntry.self, LibrarySchemaV2.DiscogsAccount.self,
         LibrarySchemaV3.CollectionValueSnapshot.self, LibrarySchemaV3.ReleaseMarketValue.self,
         LibrarySchemaV4.OptimizationExclusion.self]
    }

    @Model final class Release {
        @Attribute(.unique) var id: UUID
        var discogsID: Int?
        var masterID: Int?
        var resourceURL: String?
        var thumbURL: String?
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
        var discogsURL: String?
        var fetchedAt: Date?
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.release) var copies: [RecordCopy] = []
        init(artist: String, title: String) {
            id = UUID(); self.artist = artist; self.title = title
            label = ""; catalogNumber = ""; country = ""; format = "Vinyl"
            genres = []; styles = []; tracks = []
        }
        func updateMetadata(from other: Release) {
            if let basic = other.basicInformation { basicInformation = basic }
            masterID = other.masterID; resourceURL = other.resourceURL; thumbURL = other.thumbURL
            artist = other.artist; title = other.title; year = other.year; label = other.label
            catalogNumber = other.catalogNumber; country = other.country; format = other.format
            genres = other.genres; styles = other.styles; tracks = other.tracks
            coverURL = other.coverURL; discogsURL = other.discogsURL; fetchedAt = other.fetchedAt
        }
        var isFresh: Bool { discogsID == nil || (fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false) }
        var displayArtist: String { artist.isEmpty ? "Unbekannter Interpret" : artist }
        var displayTitle: String { title.isEmpty ? "Release #\(discogsID ?? 0)" : title }
        var sourceURL: URL? { discogsID.flatMap { URL(string: "https://www.discogs.com/release/\($0)") } }
    }

    @Model final class RecordCopy {
        @Attribute(.unique) var id: UUID
        var release: Release?
        var shelf: Shelf?
        var discogsInstanceID: Int?
        var discogsOwner: String?
        var discogsFolderID: Int?
        var discogsDateAdded: String?
        var discogsRating: Int?
        var discogsNotes: Data?
        var lastDiscogsSync: Date?
        var discogsActive: Bool?
        var positionInShelf: Int
        var condition: String
        var purchasePrice: Decimal?
        var purchaseDate: Date?
        var notes: String
        var dateAdded: Date
        init(release: Release, shelf: Shelf? = nil, position: Int = 0) {
            id = UUID(); self.release = release; self.shelf = shelf
            positionInShelf = position; condition = "Nicht bewertet"; notes = ""
            dateAdded = .now
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
        var sortOrder: Int
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.shelf) var copies: [RecordCopy] = []
        init(number: Int) {
            id = UUID(); self.number = number; row = (number - 1) / ShelfGeometry.columns + 1
            column = (number - 1) % ShelfGeometry.columns + 1; name = ""; sortOrder = number
        }
        var title: String { name.isEmpty ? "Fach \(number)" : name }
    }

    // Brought forward from V2 unchanged, other than pointing at this version's Release.
    @Model final class WantlistEntry {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var release: Release?
        var dateAdded: String?
        var rating: Int?
        var notes: String?
        var lastDiscogsSync: Date?
        init(owner: String, release: Release, releaseID: Int) {
            self.owner = owner; self.release = release; self.releaseID = releaseID
            key = "\(owner)-\(releaseID)"
        }
    }
}

// V9 adds `Release.detailsFetchedAt`, so tracklists are loaded once (even when
// Discogs has none) and refreshed after a while. Otherwise identical to V8;
// the new optional attribute migrates lightweight.
enum LibrarySchemaV9: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Release.self, RecordCopy.self, Shelf.self,
         LibrarySchemaV2.DiscogsFolder.self, WantlistEntry.self, LibrarySchemaV2.DiscogsAccount.self,
         LibrarySchemaV3.CollectionValueSnapshot.self, LibrarySchemaV3.ReleaseMarketValue.self,
         LibrarySchemaV4.OptimizationExclusion.self]
    }

    @Model final class Release {
        @Attribute(.unique) var id: UUID
        var discogsID: Int?
        var masterID: Int?
        var resourceURL: String?
        var thumbURL: String?
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
        var discogsURL: String?
        var fetchedAt: Date?
        /// When the full Discogs release (tracklist, country) was last loaded.
        /// `nil` = never; decides which tracklists to (re)load after a sync.
        var detailsFetchedAt: Date?
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.release) var copies: [RecordCopy] = []
        init(artist: String, title: String) {
            id = UUID(); self.artist = artist; self.title = title
            label = ""; catalogNumber = ""; country = ""; format = "Vinyl"
            genres = []; styles = []; tracks = []
        }
        func updateMetadata(from other: Release) {
            if let basic = other.basicInformation { basicInformation = basic }
            masterID = other.masterID; resourceURL = other.resourceURL; thumbURL = other.thumbURL
            artist = other.artist; title = other.title; year = other.year; label = other.label
            catalogNumber = other.catalogNumber; country = other.country; format = other.format
            genres = other.genres; styles = other.styles; tracks = other.tracks
            coverURL = other.coverURL; discogsURL = other.discogsURL; fetchedAt = other.fetchedAt
            detailsFetchedAt = other.detailsFetchedAt
        }
        var isFresh: Bool { discogsID == nil || (fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false) }
        var displayArtist: String { artist.isEmpty ? "Unbekannter Interpret" : artist }
        var displayTitle: String { title.isEmpty ? "Release #\(discogsID ?? 0)" : title }
        var sourceURL: URL? { discogsID.flatMap { URL(string: "https://www.discogs.com/release/\($0)") } }
    }

    @Model final class RecordCopy {
        @Attribute(.unique) var id: UUID
        var release: Release?
        var shelf: Shelf?
        var discogsInstanceID: Int?
        var discogsOwner: String?
        var discogsFolderID: Int?
        var discogsDateAdded: String?
        var discogsRating: Int?
        var discogsNotes: Data?
        var lastDiscogsSync: Date?
        var discogsActive: Bool?
        var positionInShelf: Int
        var condition: String
        var purchasePrice: Decimal?
        var purchaseDate: Date?
        var notes: String
        var dateAdded: Date
        init(release: Release, shelf: Shelf? = nil, position: Int = 0) {
            id = UUID(); self.release = release; self.shelf = shelf
            positionInShelf = position; condition = "Nicht bewertet"; notes = ""
            dateAdded = .now
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
        var sortOrder: Int
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.shelf) var copies: [RecordCopy] = []
        init(number: Int) {
            id = UUID(); self.number = number; row = (number - 1) / ShelfGeometry.columns + 1
            column = (number - 1) % ShelfGeometry.columns + 1; name = ""; sortOrder = number
        }
        var title: String { name.isEmpty ? "Fach \(number)" : name }
    }

    // Brought forward from V2 unchanged, other than pointing at this version's Release.
    @Model final class WantlistEntry {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var release: Release?
        var dateAdded: String?
        var rating: Int?
        var notes: String?
        var lastDiscogsSync: Date?
        init(owner: String, release: Release, releaseID: Int) {
            self.owner = owner; self.release = release; self.releaseID = releaseID
            key = "\(owner)-\(releaseID)"
        }
    }
}

// V10 drops Release.thumbURL (never read), discogsURL and resourceURL (both
// derivable from discogsID; the raw values remain in basicInformation), and
// lets the store itself keep one release per Discogs ID (#Unique) instead of
// relying on the sync alone.
enum LibrarySchemaV10: VersionedSchema {
    static let versionIdentifier = Schema.Version(10, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Release.self, RecordCopy.self, Shelf.self,
         LibrarySchemaV2.DiscogsFolder.self, WantlistEntry.self, LibrarySchemaV2.DiscogsAccount.self,
         LibrarySchemaV3.CollectionValueSnapshot.self, LibrarySchemaV3.ReleaseMarketValue.self,
         LibrarySchemaV4.OptimizationExclusion.self]
    }

    @Model final class Release {
        // One release per Discogs ID; manual releases (nil) are not constrained.
        #Unique<Release>([\.discogsID])
        @Attribute(.unique) var id: UUID
        var discogsID: Int?
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
        init(artist: String, title: String) {
            id = UUID(); self.artist = artist; self.title = title
            label = ""; catalogNumber = ""; country = ""; format = "Vinyl"
            genres = []; styles = []; tracks = []
        }
        var isFresh: Bool { discogsID == nil || (fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false) }
        // Stored names keep Discogs' "(3)" suffix (search and re-sync rely on the
        // raw value); only what is shown drops it.
        var displayArtist: String { artist.isEmpty ? "Unbekannter Interpret" : DiscogsName.clean(artist) }
        var displayLabel: String { DiscogsName.clean(label) }
        var displayTitle: String { title.isEmpty ? "Release #\(discogsID ?? 0)" : title }
        var sourceURL: URL? { discogsID.flatMap { URL(string: "https://www.discogs.com/release/\($0)") } }
    }

    @Model final class RecordCopy {
        @Attribute(.unique) var id: UUID
        var release: Release?
        var shelf: Shelf?
        var discogsInstanceID: Int?
        var discogsOwner: String?
        var discogsFolderID: Int?
        var discogsDateAdded: String?
        var discogsRating: Int?
        var discogsNotes: Data?
        var lastDiscogsSync: Date?
        var discogsActive: Bool?
        var positionInShelf: Int
        var condition: String
        var purchasePrice: Decimal?
        var purchaseDate: Date?
        var notes: String
        var dateAdded: Date
        init(release: Release, shelf: Shelf? = nil, position: Int = 0) {
            id = UUID(); self.release = release; self.shelf = shelf
            positionInShelf = position; condition = "Nicht bewertet"; notes = ""
            dateAdded = .now
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
        var sortOrder: Int
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.shelf) var copies: [RecordCopy] = []
        init(number: Int) {
            id = UUID(); self.number = number; row = (number - 1) / ShelfGeometry.columns + 1
            column = (number - 1) % ShelfGeometry.columns + 1; name = ""; sortOrder = number
        }
        var title: String { name.isEmpty ? "Fach \(number)" : name }
    }

    // Brought forward from V2 unchanged, other than pointing at this version's Release.
    @Model final class WantlistEntry {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var release: Release?
        var dateAdded: String?
        var rating: Int?
        var notes: String?
        var lastDiscogsSync: Date?
        init(owner: String, release: Release, releaseID: Int) {
            self.owner = owner; self.release = release; self.releaseID = releaseID
            key = "\(owner)-\(releaseID)"
        }
    }
}

// Every record comes from the Discogs sync: the Discogs IDs that used to be
// optional (nil = added by hand) are required. Defaults only serve the migration.
enum LibrarySchemaV11: VersionedSchema {
    static let versionIdentifier = Schema.Version(11, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Release.self, RecordCopy.self, Shelf.self,
         LibrarySchemaV2.DiscogsFolder.self, WantlistEntry.self, LibrarySchemaV2.DiscogsAccount.self,
         LibrarySchemaV3.CollectionValueSnapshot.self, LibrarySchemaV3.ReleaseMarketValue.self,
         LibrarySchemaV4.OptimizationExclusion.self]
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
        var isFresh: Bool { fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false }
        // Stored names keep Discogs' "(3)" suffix (search and re-sync rely on the
        // raw value); only what is shown drops it.
        var displayArtist: String { artist.isEmpty ? "Unbekannter Interpret" : DiscogsName.clean(artist) }
        var displayLabel: String { DiscogsName.clean(label) }
        var displayTitle: String { title.isEmpty ? "Release #\(discogsID)" : title }
        var sourceURL: URL? { URL(string: "https://www.discogs.com/release/\(discogsID)") }
    }

    @Model final class RecordCopy {
        @Attribute(.unique) var id: UUID
        var release: Release?
        var shelf: Shelf?
        var discogsInstanceID: Int = 0
        var discogsOwner: String = ""
        var discogsFolderID: Int?
        var discogsDateAdded: String?
        var discogsRating: Int?
        var discogsNotes: Data?
        var lastDiscogsSync: Date?
        /// `false` once the copy left the collection (sold, other account); it
        /// keeps its shelf place until removed on the shelf page.
        var discogsActive: Bool = true
        var positionInShelf: Int
        var condition: String
        var purchasePrice: Decimal?
        var purchaseDate: Date?
        var notes: String
        var dateAdded: Date
        init(release: Release, instanceID: Int, owner: String, shelf: Shelf? = nil, position: Int = 0) {
            id = UUID(); self.release = release; self.shelf = shelf
            discogsInstanceID = instanceID; discogsOwner = owner; discogsActive = true
            positionInShelf = position; condition = "Nicht bewertet"; notes = ""
            dateAdded = .now
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
        var sortOrder: Int
        @Relationship(deleteRule: .deny, inverse: \RecordCopy.shelf) var copies: [RecordCopy] = []
        init(number: Int) {
            id = UUID(); self.number = number; row = (number - 1) / ShelfGeometry.columns + 1
            column = (number - 1) % ShelfGeometry.columns + 1; name = ""; sortOrder = number
        }
        var title: String { name.isEmpty ? "Fach \(number)" : name }
    }

    // Brought forward from V2 unchanged, other than pointing at this version's Release.
    @Model final class WantlistEntry {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var release: Release?
        var dateAdded: String?
        var rating: Int?
        var notes: String?
        var lastDiscogsSync: Date?
        init(owner: String, release: Release, releaseID: Int) {
            self.owner = owner; self.release = release; self.releaseID = releaseID
            key = "\(owner)-\(releaseID)"
        }
    }
}

// Several shelves ("Regale"): every compartment belongs to a cabinet with its
// own grid, name and on/off switch. `Shelf.number` stays the app-wide key
// (backups, exports); `sortOrder` is the compartment's place inside its
// cabinet, reading order from the top left.
enum LibrarySchemaV12: VersionedSchema {
    static let versionIdentifier = Schema.Version(12, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Release.self, RecordCopy.self, Shelf.self,
         LibrarySchemaV2.DiscogsFolder.self, WantlistEntry.self, LibrarySchemaV2.DiscogsAccount.self,
         LibrarySchemaV3.CollectionValueSnapshot.self, LibrarySchemaV3.ReleaseMarketValue.self,
         LibrarySchemaV4.OptimizationExclusion.self, Cabinet.self]
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
        var isFresh: Bool { fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false }
        // Stored names keep Discogs' "(3)" suffix (search and re-sync rely on the
        // raw value); only what is shown drops it.
        var displayArtist: String { artist.isEmpty ? "Unbekannter Interpret" : DiscogsName.clean(artist) }
        var displayLabel: String { DiscogsName.clean(label) }
        var displayTitle: String { title.isEmpty ? "Release #\(discogsID)" : title }
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
        var discogsRating: Int?
        var discogsNotes: Data?
        var lastDiscogsSync: Date?
        /// `false` once the copy left the collection (sold, other account); it
        /// keeps its shelf place until removed on the shelf page.
        var discogsActive: Bool = true
        var positionInShelf: Int
        var condition: String
        var purchasePrice: Decimal?
        var purchaseDate: Date?
        var notes: String
        var dateAdded: Date
        init(release: Release, instanceID: Int, owner: String, shelf: Shelf? = nil, position: Int = 0) {
            id = UUID(); self.release = release; self.shelf = shelf
            discogsInstanceID = instanceID; discogsOwner = owner; discogsActive = true
            positionInShelf = position; condition = "Nicht bewertet"; notes = ""
            dateAdded = .now
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
        var title: String { name.isEmpty ? "Fach \(sortOrder)" : name }
    }

    // Brought forward from V2 unchanged, other than pointing at this version's Release.
    @Model final class WantlistEntry {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var release: Release?
        var dateAdded: String?
        var rating: Int?
        var notes: String?
        var lastDiscogsSync: Date?
        init(owner: String, release: Release, releaseID: Int) {
            self.owner = owner; self.release = release; self.releaseID = releaseID
            key = "\(owner)-\(releaseID)"
        }
    }
}

// V13 adds a local-only "Vermisst" mark for records that should stand
// in a shelf but weren't found there while sorting. Stored separately (like
// OptimizationExclusion), so every existing model is carried over unchanged.
enum LibrarySchemaV13: VersionedSchema {
    static let versionIdentifier = Schema.Version(13, 0, 0)
    static var models: [any PersistentModel.Type] {
        LibrarySchemaV12.models + [MissingCopyMark.self]
    }

    @Model final class MissingCopyMark {
        @Attribute(.unique) var copyID: UUID
        var markedAt: Date

        init(copyID: UUID, markedAt: Date = .now) {
            self.copyID = copyID
            self.markedAt = markedAt
        }
    }
}

// V14 drops the copy's own purchase data (condition, price, purchase date,
// notes, date added): Discogs is the only source, and the app no longer shows
// or edits them. Only `RecordCopy` changes; the models around it are carried
// over from V12 because their relationships point at this version's classes.
enum LibrarySchemaV14: VersionedSchema {
    static let versionIdentifier = Schema.Version(14, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Release.self, RecordCopy.self, Shelf.self,
         LibrarySchemaV2.DiscogsFolder.self, WantlistEntry.self, LibrarySchemaV2.DiscogsAccount.self,
         LibrarySchemaV3.CollectionValueSnapshot.self, LibrarySchemaV3.ReleaseMarketValue.self,
         LibrarySchemaV4.OptimizationExclusion.self, Cabinet.self, LibrarySchemaV13.MissingCopyMark.self]
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
        var isFresh: Bool { fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false }
        // Stored names keep Discogs' "(3)" suffix (search and re-sync rely on the
        // raw value); only what is shown drops it.
        var displayArtist: String { artist.isEmpty ? "Unbekannter Interpret" : DiscogsName.clean(artist) }
        var displayLabel: String { DiscogsName.clean(label) }
        var displayTitle: String { title.isEmpty ? "Release #\(discogsID)" : title }
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
        var discogsRating: Int?
        var discogsNotes: Data?
        var lastDiscogsSync: Date?
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
        var title: String { name.isEmpty ? "Fach \(sortOrder)" : name }
    }

    // Carried over from V12 unchanged, other than pointing at this version's Release.
    @Model final class WantlistEntry {
        @Attribute(.unique) var key: String
        var owner: String
        var releaseID: Int
        var release: Release?
        var dateAdded: String?
        var rating: Int?
        var notes: String?
        var lastDiscogsSync: Date?
        init(owner: String, release: Release, releaseID: Int) {
            self.owner = owner; self.release = release; self.releaseID = releaseID
            key = "\(owner)-\(releaseID)"
        }
    }
}


// V15 is complete in itself and keeps only what the app uses. Dropped:
// the copy's Discogs rating, notes and sync date; the wantlist entry's rating
// and sync date; the folder's and account's folder-sync dates; the snapshot's
// unique-release count; the creation dates of "Nicht im Regal" and
// "Vermisst"; and `ReleaseMarketValue`, which was never filled.
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

    /// "Nicht im Regal": kept out of the shelf allocation.
    @Model final class OptimizationExclusion {
        @Attribute(.unique) var copyID: UUID
        init(copyID: UUID) { self.copyID = copyID }
    }

    /// "Vermisst": should stand in a shelf but wasn't found there.
    @Model final class MissingCopyMark {
        @Attribute(.unique) var copyID: UUID
        init(copyID: UUID) { self.copyID = copyID }
    }
}

// V16 adds a local-only "Verkauf" mark for records meant to be sold some
// day. Stored separately like "Vermisst", so every model of V15 is carried
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

// The current schema is V16 (see `LibraryStorage`); its models are those of
// V15 plus `SaleCopyMark`.
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

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self, LibrarySchemaV2.self, LibrarySchemaV3.self, LibrarySchemaV4.self, LibrarySchemaV5.self, LibrarySchemaV6.self, LibrarySchemaV7.self, LibrarySchemaV8.self, LibrarySchemaV9.self, LibrarySchemaV10.self, LibrarySchemaV11.self, LibrarySchemaV12.self, LibrarySchemaV13.self, LibrarySchemaV14.self, LibrarySchemaV15.self, LibrarySchemaV16.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self),
         .lightweight(fromVersion: LibrarySchemaV2.self, toVersion: LibrarySchemaV3.self),
         .lightweight(fromVersion: LibrarySchemaV3.self, toVersion: LibrarySchemaV4.self),
         .lightweight(fromVersion: LibrarySchemaV4.self, toVersion: LibrarySchemaV5.self),
         .lightweight(fromVersion: LibrarySchemaV5.self, toVersion: LibrarySchemaV6.self),
         .lightweight(fromVersion: LibrarySchemaV6.self, toVersion: LibrarySchemaV7.self),
         migrateV7toV8,
         .lightweight(fromVersion: LibrarySchemaV8.self, toVersion: LibrarySchemaV9.self),
         .lightweight(fromVersion: LibrarySchemaV9.self, toVersion: LibrarySchemaV10.self),
         migrateV10toV11,
         // Cabinets are created (and existing compartments assigned to the
         // first one) in `LibraryStorage.prepareShelves`.
         .lightweight(fromVersion: LibrarySchemaV11.self, toVersion: LibrarySchemaV12.self),
         .lightweight(fromVersion: LibrarySchemaV12.self, toVersion: LibrarySchemaV13.self),
         .lightweight(fromVersion: LibrarySchemaV13.self, toVersion: LibrarySchemaV14.self),
         .lightweight(fromVersion: LibrarySchemaV14.self, toVersion: LibrarySchemaV15.self),
         .lightweight(fromVersion: LibrarySchemaV15.self, toVersion: LibrarySchemaV16.self)]
    }

    // The Discogs IDs become required. Records without them (added by hand in
    // early versions) can't exist in a pure Discogs mirror; they are removed
    // first so the stricter columns can be filled. Synced data is untouched.
    static let migrateV10toV11 = MigrationStage.custom(
        fromVersion: LibrarySchemaV10.self,
        toVersion: LibrarySchemaV11.self,
        willMigrate: { context in
            let copies = try context.fetch(FetchDescriptor<LibrarySchemaV10.RecordCopy>())
            AppLog.info("Datenbank", "Migration auf Schema V11 beginnt")
            let unlinked = copies.filter { $0.discogsInstanceID == nil || $0.discogsOwner == nil || $0.discogsActive == nil || $0.release?.discogsID == nil }
            let releases = try context.fetch(FetchDescriptor<LibrarySchemaV10.Release>()).filter { $0.discogsID == nil }
            let wants = try context.fetch(FetchDescriptor<LibrarySchemaV10.WantlistEntry>()).filter { $0.release?.discogsID == nil }
            guard !unlinked.isEmpty || !releases.isEmpty || !wants.isEmpty else { return }
            AppLog.warning("Datenbank", "Migration V11 entfernt Einträge ohne Discogs-IDs: \(unlinked.count) Exemplare, \(releases.count) Releases, \(wants.count) Wantlist-Einträge")
            for copy in unlinked { context.delete(copy) }
            for want in wants { context.delete(want) }
            try context.save()
            for release in releases { context.delete(release) }
            try context.save()
        },
        didMigrate: { _ in AppLog.info("Datenbank", "Migration auf Schema V11 abgeschlossen") }
    )

    // Capacity 0 used to mean "reserved". Remember those shelves before the
    // column is dropped, then flag them on the new schema.
    nonisolated(unsafe) private static var reservedShelfIDs: Set<UUID> = []
    static let migrateV7toV8 = MigrationStage.custom(
        fromVersion: LibrarySchemaV7.self,
        toVersion: LibrarySchemaV8.self,
        willMigrate: { context in
            let shelves = try context.fetch(FetchDescriptor<LibrarySchemaV6.Shelf>())
            reservedShelfIDs = Set(shelves.filter { $0.capacity == 0 }.map(\.id))
        },
        didMigrate: { context in
            for shelf in try context.fetch(FetchDescriptor<LibrarySchemaV8.Shelf>()) where reservedShelfIDs.contains(shelf.id) {
                shelf.isReserved = true
            }
            try context.save()
            reservedShelfIDs = []
        }
    )
}
