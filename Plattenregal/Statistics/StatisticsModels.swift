import Foundation
import SwiftData

// V1 and V2 remain frozen. The existing model types and relationships are unchanged.
enum LibrarySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        LibrarySchemaV2.models + [CollectionValueSnapshot.self, ReleaseMarketValue.self]
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
typealias CollectionValueSnapshot = LibrarySchemaV3.CollectionValueSnapshot
typealias ReleaseMarketValue = LibrarySchemaV3.ReleaseMarketValue

// V4 adds durable local-only optimization preferences without changing the
// frozen Discogs collection models from V2.
enum LibrarySchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        LibrarySchemaV3.models + [OptimizationExclusion.self]
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
typealias OptimizationExclusion = LibrarySchemaV4.OptimizationExclusion

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
typealias ShelfCustomization = LibrarySchemaV5.ShelfCustomization

// V6 drops the "favorite" flag now that the feature has been removed. Release
// and Shelf are brought forward unchanged, since their relationships to
// RecordCopy must point at this version's RecordCopy type.
enum LibrarySchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Release.self, RecordCopy.self, Shelf.self,
         LibrarySchemaV2.DiscogsFolder.self, WantlistEntry.self, LibrarySchemaV2.DiscogsAccount.self,
         CollectionValueSnapshot.self, ReleaseMarketValue.self,
         OptimizationExclusion.self, ShelfCustomization.self]
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
typealias Release = LibrarySchemaV6.Release
typealias RecordCopy = LibrarySchemaV6.RecordCopy
typealias Shelf = LibrarySchemaV6.Shelf
typealias WantlistEntry = LibrarySchemaV6.WantlistEntry

struct DiscogsMoney: Equatable, Sendable {
    let amount: Decimal
    let currency: String
    static func parse(_ raw: String) throws -> Self {
        let upper = raw.uppercased()
        let codes = ["EUR", "USD", "GBP", "CAD", "AUD", "JPY", "CHF", "SEK", "NOK", "DKK", "NZD", "BRL", "MXN", "ZAR", "HKD", "SGD", "PLN", "CZK", "HUF", "INR", "KRW", "TRY", "CNY"]
        let currency: String
        if let code = codes.first(where: { upper.contains($0) }) { currency = code }
        else if raw.contains("€") { currency = "EUR" }
        else if raw.contains("£") { currency = "GBP" }
        else if upper.contains("CA$") || upper.contains("C$") { currency = "CAD" }
        else if upper.contains("A$") || upper.contains("AU$") { currency = "AUD" }
        else if upper.contains("NZ$") { currency = "NZD" }
        else if upper.contains("HK$") { currency = "HKD" }
        else if upper.contains("US$") { currency = "USD" }
        else if upper.contains("S$") { currency = "SGD" }
        else if upper.contains("R$") { currency = "BRL" }
        else if raw.contains("$") { currency = "USD" }
        else if raw.contains("¥") { currency = "JPY" }
        else { throw DiscogsError.invalidResponse }
        var number = raw.filter { "0123456789.,-".contains($0) }
        guard number.range(of: #"^(?:[0-9]+|[0-9]{1,3}(?:[.,][0-9]{3})+)(?:[.,][0-9]{1,2})?$"#, options: .regularExpression) != nil else { throw DiscogsError.invalidResponse }
        let comma = number.lastIndex(of: ","), dot = number.lastIndex(of: ".")
        let separator: Character?
        if let comma, let dot { separator = comma > dot ? "," : "." }
        else if let index = comma ?? dot {
            let trailing = number.distance(from: number.index(after: index), to: number.endIndex)
            separator = trailing == 1 || trailing == 2 ? number[index] : nil
        } else { separator = nil }
        if let separator, let last = number.lastIndex(of: separator) {
            let integer = number[..<last].filter { $0 != "," && $0 != "." }
            let fraction = number[number.index(after: last)...]
            number = integer + "." + fraction
        } else { number = number.filter { $0 != "," && $0 != "." } }
        guard let amount = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")), amount >= 0 else { throw DiscogsError.invalidResponse }
        return Self(amount: amount, currency: currency)
    }
    static func format(_ amount: Decimal, currency: String, locale: Locale = .current) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency
        formatter.locale = locale; formatter.currencyCode = currency
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—"
    }
}
struct DiscogsCollectionValue: Decodable, Sendable {
    let minimum: DiscogsMoney
    let median: DiscogsMoney
    let maximum: DiscogsMoney
    enum CodingKeys: String, CodingKey { case minimum, median, maximum }
    init(minimum: DiscogsMoney, median: DiscogsMoney, maximum: DiscogsMoney) throws {
        guard minimum.currency == median.currency, median.currency == maximum.currency,
              minimum.amount <= median.amount, median.amount <= maximum.amount else { throw DiscogsError.invalidResponse }
        self.minimum = minimum; self.median = median; self.maximum = maximum
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(minimum: DiscogsMoney.parse(c.decode(String.self, forKey: .minimum)),
                      median: DiscogsMoney.parse(c.decode(String.self, forKey: .median)),
                      maximum: DiscogsMoney.parse(c.decode(String.self, forKey: .maximum)))
    }
}
struct DiscogsPrice: Decodable, Sendable { let value: Decimal; let currency: String }
struct DiscogsMarketplaceStats: Decodable, Sendable { let lowest_price: DiscogsPrice? }
