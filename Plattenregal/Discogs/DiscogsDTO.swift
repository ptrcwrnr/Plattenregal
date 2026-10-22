import Foundation

/// A full Discogs release (`/releases/<id>`). Only what the collection sync's
/// basic information lacks is read from it – tracklist, country and videos;
/// everything else comes with the sync (`DiscogsBasicInformation`).
nonisolated struct DiscogsReleaseDTO: Decodable, Sendable {
    struct TrackDTO: Decodable, Sendable { let position: String?; let title: String; let duration: String? }
    struct VideoDTO: Decodable, Sendable { let uri: String?; let title: String? }
    let id: Int
    let country: String?
    let tracklist: [TrackDTO]?
    let videos: [VideoDTO]?
    /// The videos with a usable web address, in Discogs' order. Stored apart
    /// from the release (`ReleaseVideoList.store`).
    var releaseVideos: [ReleaseVideo] {
        (videos ?? []).compactMap { video in
            guard let uri = video.uri, let url = URL(string: uri), url.scheme == "https" || url.scheme == "http" else { return nil }
            return ReleaseVideo(title: video.title ?? "", url: uri)
        }
    }
    /// Leaves everything else (and `basicInformation`) untouched, so the next
    /// collection sync doesn't see the release as changed.
    func applyDetails(to release: Release) {
        release.tracks = (tracklist ?? []).map { Track(position: $0.position ?? "", title: $0.title, duration: $0.duration ?? "") }
        release.country = country ?? ""
        release.detailsFetchedAt = .now
    }
}
