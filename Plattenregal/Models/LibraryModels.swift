import Foundation
import SwiftData

enum ShelfGeometry {
    static let rows = 3
    static let columns = 4
    static let count = rows * columns
}

struct Track: Codable, Hashable, Sendable {
    var position: String
    var title: String
    var duration: String
}

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

typealias DiscogsFolder = LibrarySchemaV2.DiscogsFolder
typealias DiscogsAccount = LibrarySchemaV2.DiscogsAccount

enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self, LibrarySchemaV2.self, LibrarySchemaV3.self, LibrarySchemaV4.self, LibrarySchemaV5.self, LibrarySchemaV6.self]
    }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self),
         .lightweight(fromVersion: LibrarySchemaV2.self, toVersion: LibrarySchemaV3.self),
         .lightweight(fromVersion: LibrarySchemaV3.self, toVersion: LibrarySchemaV4.self),
         .lightweight(fromVersion: LibrarySchemaV4.self, toVersion: LibrarySchemaV5.self),
         .lightweight(fromVersion: LibrarySchemaV5.self, toVersion: LibrarySchemaV6.self)]
    }
}
