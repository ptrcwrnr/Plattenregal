import Foundation

struct DiscogsIdentity: Decodable, Sendable { let id: Int; let username: String }
struct DiscogsFoldersResponse: Decodable, Sendable { let folders: [DiscogsFolderDTO] }
struct DiscogsFolderDTO: Codable, Sendable { let id: Int; let name: String; let count: Int }
struct DiscogsNote: Codable, Sendable, Equatable { let field_id: Int; let value: String }
struct DiscogsBasicInformation: Codable, Sendable {
    struct Artist: Codable, Sendable {
        let id: Int?
        let name: String
        let anv: String?
        let join: String?

        init(id: Int?, name: String, anv: String? = nil, join: String?) {
            self.id = id; self.name = name; self.anv = anv; self.join = join
        }

        var displayName: String {
            let variation = anv?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return variation.isEmpty ? name : variation
        }
    }
    struct Label: Codable, Sendable { let id: Int?; let name: String; let catno: String? }
    struct Format: Codable, Sendable { let name: String; let qty: String?; let descriptions: [String]? }
    let id: Int
    let title: String
    let artists: [Artist]?
    let year: Int?
    let labels: [Label]?
    let formats: [Format]?
    let genres: [String]?
    let styles: [String]?
    let cover_image: String?
    let thumb: String?
    let resource_url: String?
    let master_id: Int?

    func apply(to release: Release, at date: Date) throws {
        release.discogsID = id; release.title = title
        let artists = artists ?? []
        release.artist = artists.enumerated().map { index, artist in
            artist.displayName + (index < artists.count - 1 ? " \(artist.join ?? ",") " : "")
        }.joined()
        release.year = year.flatMap { $0 > 0 ? $0 : nil }
        release.label = (labels ?? []).map(\.name).joined(separator: ", ")
        release.catalogNumber = (labels ?? []).compactMap(\.catno).joined(separator: ", ")
        release.format = (formats ?? []).map { ([$0.qty, $0.name] + ($0.descriptions ?? []).map { Optional($0) }).compactMap { $0 }.joined(separator: " · ") }.joined(separator: ", ")
        release.genres = genres ?? []; release.styles = styles ?? []
        release.coverURL = cover_image; release.thumbURL = thumb
        release.resourceURL = resource_url; release.masterID = master_id
        release.basicInformation = try DiscogsEncoding.data(self)
        release.discogsURL = "https://www.discogs.com/release/\(id)"; release.fetchedAt = date
        // Basic information does not contain tracks/country: preserve previously fetched details.
    }
}
struct DiscogsCollectionDTO: Decodable, Sendable {
    let id: Int
    let instance_id: Int
    let folder_id: Int
    let date_added: String
    let rating: Int
    let notes: [DiscogsNote]?
    let basic_information: DiscogsBasicInformation
}
struct DiscogsWantDTO: Decodable, Sendable {
    let id: Int
    let date_added: String
    let rating: Int
    let notes: String?
    let basic_information: DiscogsBasicInformation
}
struct DiscogsPagination: Decodable, Sendable {
    let page: Int
    let pages: Int
    let per_page: Int
    let items: Int
}
struct DiscogsCollectionPage: Decodable, Sendable {
    let pagination: DiscogsPagination
    let releases: [DiscogsCollectionDTO]
}
struct DiscogsWantPage: Decodable, Sendable {
    let pagination: DiscogsPagination
    let wants: [DiscogsWantDTO]
}

// Stable representation prevents JSON object key order from reporting false updates.
enum DiscogsEncoding {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
