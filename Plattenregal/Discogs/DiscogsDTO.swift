import Foundation

struct DiscogsSearchResponse: Decodable, Sendable {
    struct Pagination: Decodable, Sendable { let page: Int; let pages: Int }
    let pagination: Pagination
    let results: [DiscogsSearchResult]
}
struct DiscogsSearchResult: Decodable, Identifiable, Sendable {
    let id: Int
    let title: String
    let type: String
    let year: String?
    let label: [String]?
    let catno: String?
    let country: String?
    let format: [String]?
    let thumb: String?
    var sourceURL: URL { URL(string: "https://www.discogs.com/release/\(id)")! }
}
struct DiscogsReleaseDTO: Decodable, Sendable {
    struct Artist: Decodable, Sendable {
        let id: Int?
        let name: String
        let anv: String?
        let join: String?

        var displayName: String {
            let variation = anv?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return variation.isEmpty ? name : variation
        }
    }
    struct Label: Decodable, Sendable { let id: Int?; let name: String; let catno: String? }
    struct Format: Decodable, Sendable { let name: String; let qty: String?; let descriptions: [String]? }
    struct Image: Decodable, Sendable { let type: String?; let uri: String }
    struct TrackDTO: Decodable, Sendable { let position: String?; let title: String; let duration: String? }
    let id: Int
    let title: String
    let artists: [Artist]?
    let year: Int?
    let labels: [Label]?
    let country: String?
    let formats: [Format]?
    let genres: [String]?
    let styles: [String]?
    let tracklist: [TrackDTO]?
    let images: [Image]?
    let uri: String?
    let master_id: Int?
    let resource_url: String?
    @MainActor func mappedRelease() -> Release {
        let release = Release(artist: "", title: title)
        apply(to: release); return release
    }
    func apply(to release: Release) {
        release.discogsID = id; release.title = title
        let basic = DiscogsBasicInformation(id: id, title: title,
            artists: (artists ?? []).map { .init(id: $0.id, name: $0.name, anv: $0.anv, join: $0.join) }, year: year,
            labels: labels?.map { .init(id: $0.id, name: $0.name, catno: $0.catno) },
            formats: formats?.map { .init(name: $0.name, qty: $0.qty, descriptions: $0.descriptions) },
            genres: genres, styles: styles, cover_image: images?.first?.uri, thumb: release.thumbURL,
            resource_url: resource_url, master_id: master_id)
        if let data = try? DiscogsEncoding.data(basic) { release.basicInformation = data }
        release.masterID = master_id; release.resourceURL = resource_url
        release.artist = (artists ?? []).enumerated().map { index, artist in
            artist.displayName + (index < (artists?.count ?? 0) - 1 ? " \(artist.join ?? ",") " : "")
        }.joined()
        if release.artist.isEmpty { release.artist = "Unbekannter Interpret" }
        release.year = year.flatMap { $0 > 0 ? $0 : nil }
        release.label = (labels ?? []).map(\.name).joined(separator: ", ")
        release.catalogNumber = (labels ?? []).compactMap(\.catno).joined(separator: ", ")
        release.country = country ?? ""
        release.format = (formats ?? []).map { ([$0.qty, $0.name] + ($0.descriptions ?? []).map { Optional($0) }).compactMap { $0 }.joined(separator: " · ") }.joined(separator: ", ")
        release.genres = genres ?? []; release.styles = styles ?? []
        release.tracks = (tracklist ?? []).map { Track(position: $0.position ?? "", title: $0.title, duration: $0.duration ?? "") }
        release.coverURL = (images?.first(where: { $0.type == "primary" }) ?? images?.first)?.uri
        release.discogsURL = "https://www.discogs.com/release/\(id)"; release.fetchedAt = .now
    }
}
