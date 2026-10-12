import Foundation

/// A full Discogs release (`/releases/<id>`). Only what the collection sync's
/// basic information lacks is read from it – tracklist and country; everything
/// else comes with the sync (`DiscogsBasicInformation`).
nonisolated struct DiscogsReleaseDTO: Decodable, Sendable {
    struct TrackDTO: Decodable, Sendable { let position: String?; let title: String; let duration: String? }
    let id: Int
    let country: String?
    let tracklist: [TrackDTO]?
    /// Leaves everything else (and `basicInformation`) untouched, so the next
    /// collection sync doesn't see the release as changed.
    func applyDetails(to release: Release) {
        release.tracks = (tracklist ?? []).map { Track(position: $0.position ?? "", title: $0.title, duration: $0.duration ?? "") }
        release.country = country ?? ""
        release.detailsFetchedAt = .now
    }
}
