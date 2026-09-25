import Foundation

nonisolated struct DiscogsIdentity: Decodable, Sendable { let id: Int; let username: String }
nonisolated struct DiscogsFoldersResponse: Decodable, Sendable { let folders: [DiscogsFolderDTO] }
nonisolated struct DiscogsFolderDTO: Codable, Sendable { let id: Int; let name: String; let count: Int }
nonisolated struct DiscogsBasicInformation: Codable, Sendable {
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

    /// "A & B", "A, B", "A Feat. B": Discogs puts the joining word on the
    /// artist before it – a comma sticks to the name, anything else stands
    /// between spaces, and a missing one reads as a comma.
    static func artistLine(_ artists: [Artist]) -> String {
        var line = ""
        for (index, artist) in artists.enumerated() {
            line += artist.displayName
            guard index < artists.count - 1 else { break }
            let join = (artist.join ?? "").trimmingCharacters(in: .whitespaces)
            line += join.isEmpty || join == "," ? ", " : " \(join) "
        }
        return line
    }

    func apply(to release: Release, at date: Date) throws {
        release.discogsID = id; release.title = title
        release.artist = Self.artistLine(artists ?? [])
        release.year = year.flatMap { $0 > 0 ? $0 : nil }
        release.label = (labels ?? []).map(\.name).joined(separator: ", ")
        release.catalogNumber = (labels ?? []).compactMap(\.catno).joined(separator: ", ")
        release.format = (formats ?? []).map { ([$0.qty, $0.name] + ($0.descriptions ?? []).map { Optional($0) }).compactMap { $0 }.joined(separator: " · ") }.joined(separator: ", ")
        release.genres = genres ?? []; release.styles = styles ?? []
        release.coverURL = cover_image
        release.masterID = master_id
        release.basicInformation = try DiscogsEncoding.data(self)
        release.fetchedAt = date
        // Basic information does not contain tracks/country: preserve previously fetched details.
    }
}
nonisolated struct DiscogsCollectionDTO: Decodable, Sendable {
    let id: Int
    let instance_id: Int
    let folder_id: Int
    let date_added: String
    let basic_information: DiscogsBasicInformation
}
nonisolated struct DiscogsWantDTO: Decodable, Sendable {
    let id: Int
    let date_added: String
    let notes: String?
    let basic_information: DiscogsBasicInformation
}
nonisolated struct DiscogsPagination: Decodable, Sendable {
    let page: Int
    let pages: Int
    let per_page: Int
    let items: Int
}
nonisolated struct DiscogsCollectionPage: Decodable, Sendable {
    let pagination: DiscogsPagination
    let releases: [DiscogsCollectionDTO]
}
nonisolated struct DiscogsWantPage: Decodable, Sendable {
    let pagination: DiscogsPagination
    let wants: [DiscogsWantDTO]
}

// Stable representation prevents JSON object key order from reporting false updates.
nonisolated enum DiscogsEncoding {
    static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

/// Discogs timestamps ("2026-09-20T08:00:00-07:00", sometimes with fractional
/// seconds) and plain days ("2026-09-20", read as local midnight).
nonisolated enum DiscogsDate {
    static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return (try? Date.ISO8601FormatStyle().parse(raw))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw))
            ?? (try? Date.ISO8601FormatStyle(timeZone: .current).year().month().day().parse(raw))
    }
}
