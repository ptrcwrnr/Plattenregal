import Foundation

/// Where a click on a track in the popover leads: the video Discogs lists for
/// exactly that track, or else a YouTube search for it.
nonisolated enum TrackVideoLink {
    /// One address per track, in the tracklist's order.
    static func urls(for tracks: [Track], videos: [ReleaseVideo], artist: String) -> [URL] {
        let matched = TrackVideoMatcher.match(tracks: tracks, videos: videos, artist: artist)
        return tracks.indices.map { index in
            matched[index].flatMap { URL(string: $0.url) } ?? search(tracks[index], artist: artist)
        }
    }

    /// Whether the address opens a video found on Discogs (not a search).
    static func isSearch(_ url: URL) -> Bool { url.host() == searchHost && url.path() == "/results" }

    private static let searchHost = "www.youtube.com"

    /// "Artist Title" on YouTube; without the artist on compilations, whose
    /// release artist ("Various") isn't the track's.
    static func search(_ track: Track, artist: String) -> URL {
        let name = DiscogsName.clean(artist)
        let isVarious = name.isEmpty || name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Various") == .orderedSame
        var components = URLComponents()
        components.scheme = "https"; components.host = searchHost; components.path = "/results"
        components.queryItems = [URLQueryItem(name: "search_query", value: isVarious ? track.title : "\(name) \(track.title)")]
        return components.url!
    }
}

/// Matches the videos of a release to its tracks by their titles. Discogs
/// lists videos per release, titled the way uploaders name them – mostly
/// "Artist - Title (Mix)", sometimes with a label or "Official Video".
///
/// A video belongs to a track when one part of its title (split at " - ",
/// "|" …) is exactly the track's title, and the mix in parentheses fits:
/// every word of the track's mix is in the video, and the video names no
/// other version (no "Remix", "Edit" … the track hasn't, no word of another
/// track's mix). "Original Mix" counts as no mix. Anything doubtful stays
/// unmatched – a search is better than the wrong video.
nonisolated enum TrackVideoMatcher {
    /// The matched video per track index; tracks without one are missing.
    static func match(tracks: [Track], videos: [ReleaseVideo], artist: String) -> [Int: ReleaseVideo] {
        guard !tracks.isEmpty, !videos.isEmpty else { return [:] }
        let artistWords = Set(words(DiscogsName.clean(artist)))
        let parsedTracks = tracks.map { parse($0.title) }
        let parsedVideos = videos.map { parseVideo($0.title, artistWords: artistWords) }
        var result: [Int: ReleaseVideo] = [:]
        for (index, track) in parsedTracks.enumerated() where !track.main.isEmpty {
            // Words that tell the other tracks' versions apart from this one.
            let others = Set(parsedTracks.enumerated().filter { $0.offset != index }.flatMap { $0.element.mix })
                .subtracting(track.mix).subtracting(track.main).subtracting(artistWords)
            var best: (video: Int, extra: Int)?
            for (videoIndex, video) in parsedVideos.enumerated() {
                // The part naming the track; its mix is in the parentheses or
                // after it, not in the artist part before ("Jimmy G vs. Peter L
                // - Horizon (Peter L Remix)" isn't the Jimmy G Remix).
                guard let part = video.parts.firstIndex(where: { $0.titles.contains(track.main) }),
                      track.mix.isSubset(of: video.extra.union(video.parts[(part + 1)...].flatMap(\.words))),
                      // "(Original Mix)" is the plain track, not a remix of it.
                      !(video.original && !track.mix.isEmpty) else { continue }
                let extra = video.extra.subtracting(track.mix).subtracting(track.main).subtracting(artistWords)
                guard extra.isDisjoint(with: versionWords), extra.isDisjoint(with: others) else { continue }
                if best == nil || extra.count < best!.extra { best = (videoIndex, extra.count) }
            }
            if let best { result[index] = videos[best.video] }
        }
        return result
    }

    // MARK: Parsing

    /// A title split into its words (`main`) and the words in parentheses or
    /// brackets (`mix`), without featured artists and "Original Mix".
    private struct Parsed { var main: [String]; var mix: Set<String>; var original = false }
    /// A video title: its parts (split at " - " …), the words in its
    /// parentheses (mix, label, "Official Video" …), and whether it says it is
    /// the original.
    private struct ParsedVideo { var parts: [VideoPart]; var extra: Set<String>; var original: Bool }
    /// One part of a video title: what it could name as a track title, and its words.
    private struct VideoPart { var titles: [[String]]; var words: Set<String> }

    private static func parse(_ title: String) -> Parsed {
        var main = "", inner: [String] = [], depth = 0, current = ""
        for character in title {
            switch character {
            case "(", "[":
                if depth == 0 { current = "" } else { current.append(" ") }
                depth += 1
            case ")", "]":
                guard depth > 0 else { main.append(" "); continue }
                depth -= 1
                if depth == 0 { inner.append(current) } else { current.append(" ") }
            default:
                if depth == 0 { main.append(character) } else { current.append(character) }
            }
        }
        if depth > 0 { inner.append(current) }
        var mix = Set<String>(), original = false
        for part in inner {
            let partWords = words(part)
            // "(feat. X)", "(Original Mix)": not a version of its own.
            guard let first = partWords.first, !featuring.contains(first) else { continue }
            if originalMixes.contains(partWords) { original = true; continue }
            mix.formUnion(partWords)
        }
        mix.subtract(noiseWords)
        return Parsed(main: dropFeaturing(words(main)).filter { !noiseWords.contains($0) }, mix: mix, original: original)
    }

    private static func parseVideo(_ title: String, artistWords: Set<String>) -> ParsedVideo {
        var parts: [VideoPart] = [], artistOnly: [(part: Int, title: [String])] = [], extra = Set<String>(), original = false
        for segment in title.split(separator: segmentSeparator).map(String.init) {
            let parsed = parse(segment)
            original = original || parsed.original
            extra.formUnion(parsed.mix)
            let main = parsed.main
            var part = VideoPart(titles: [], words: Set(words(segment)).subtracting(noiseWords))
            if Set(main).isSubset(of: artistWords) {
                // Just the artist ("Rank 1 - Airwave"): a title only when the
                // track is named after the artist too ("Rank 1 - Rank 1").
                if !main.isEmpty { artistOnly.append((parts.count, main)) }
            } else {
                part.titles.append(main)
                // "Rank 1 Airwave" without a dash: the artist in front.
                let artist = main.prefix { artistWords.contains($0) }
                if !artist.isEmpty { part.titles.append(Array(main.dropFirst(artist.count))) }
            }
            parts.append(part)
        }
        if artistOnly.count >= 2 || parts.allSatisfy(\.titles.isEmpty) {
            for (part, main) in artistOnly { parts[part].titles.append(main) }
        }
        return ParsedVideo(parts: parts, extra: extra, original: original)
    }

    /// " - ", " – ", " — ", "|" and " / " between artist, title and label.
    private static var segmentSeparator: Regex<Substring> { /\s+[-–—]\s+|\s*\|\s*|\s+\/\s+/ }

    /// Lowercased words without accents or punctuation ("Airwave (Sunset Mix)"
    /// → airwave, sunset, mix). Apostrophes join ("Don't" → dont); spellings
    /// of the same thing become one word ("Rmx", "Remix" → mix).
    static func words(_ text: String) -> [String] {
        SearchIndex<Int>.fold(text)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "&", with: " and ")
            .split { !$0.isLetter && !$0.isNumber }
            .map { synonyms[String($0)] ?? String($0) }
    }

    private static let synonyms: [String: String] = ["remix": "mix", "rmx": "mix", "rmix": "mix", "versus": "vs"]

    private static func dropFeaturing(_ words: [String]) -> [String] {
        guard let start = words.firstIndex(where: featuring.contains), start > 0 else { return words }
        return Array(words[..<start])
    }

    private static let featuring: Set<String> = ["feat", "ft", "featuring"]
    /// The plain track, however it is called.
    private static let originalMixes: [[String]] = [
        ["original"], ["original", "mix"], ["original", "version"], ["original", "edit"],
        ["album", "version"], ["lp", "version"], ["original", "album", "version"],
    ]
    /// Says nothing about the version; ignored in titles and mixes.
    private static let noiseWords: Set<String> = [
        "official", "video", "audio", "music", "musicvideo", "hd", "hq", "4k", "1080p", "720p",
        "remastered", "remaster", "vinyl", "rip", "lyrics", "visualizer", "clip", "upload",
    ]
    /// A video naming one of these (and the track not) is another version
    /// or more than the track.
    private static let versionWords: Set<String> = [
        "mix", "edit", "dub", "version", "rework", "remake", "live", "instrumental",
        "acapella", "vip", "extended", "radio", "club", "bootleg", "mashup", "cover", "reprise",
        "album", "full", "ep", "megamix", "medley", "continuous", "mixed", "minimix", "preview", "snippet",
    ]
}
