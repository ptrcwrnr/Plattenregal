import Foundation

nonisolated struct DiscogsReleaseDTO: Decodable, Sendable {
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
    /// A full reload of one release: the same fields as the collection sync
    /// (through `DiscogsBasicInformation`, so both always agree), plus the
    /// details the sync lacks.
    func apply(to release: Release) {
        let cover = (images?.first(where: { $0.type == "primary" }) ?? images?.first)?.uri
        let basic = DiscogsBasicInformation(id: id, title: title,
            artists: (artists ?? []).map { .init(id: $0.id, name: $0.name, anv: $0.anv, join: $0.join) }, year: year,
            labels: labels?.map { .init(id: $0.id, name: $0.name, catno: $0.catno) },
            formats: formats?.map { .init(name: $0.name, qty: $0.qty, descriptions: $0.descriptions) },
            genres: genres, styles: styles, cover_image: cover,
            thumb: release.basicInformation.flatMap { try? JSONDecoder().decode(DiscogsBasicInformation.self, from: $0) }?.thumb,
            resource_url: resource_url, master_id: master_id)
        // Encoding plain values can't fail; should it, the old snapshot stays.
        let previous = release.basicInformation
        do { try basic.apply(to: release, at: .now) } catch { release.basicInformation = previous }
        if release.artist.isEmpty { release.artist = String(localized: "Unbekannter Interpret") }
        applyDetails(to: release)
    }
    /// Only what the collection sync's basic information lacks — tracklist
    /// and country. Leaves everything else (and `basicInformation`) untouched,
    /// so the next collection sync doesn't see the release as changed.
    func applyDetails(to release: Release) {
        release.tracks = (tracklist ?? []).map { Track(position: $0.position ?? "", title: $0.title, duration: $0.duration ?? "") }
        release.country = country ?? ""
        release.detailsFetchedAt = .now
    }
}
