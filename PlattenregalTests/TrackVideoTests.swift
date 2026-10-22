import Foundation
import Testing
@testable import Plattenregal

extension AllTests {
    struct TrackVideoTests {
        private func track(_ position: String, _ title: String) -> Track { Track(position: position, title: title, duration: "") }
        private func video(_ title: String, _ id: String) -> ReleaseVideo { ReleaseVideo(title: title, url: "https://www.youtube.com/watch?v=\(id)") }
        /// Titles of the matched videos per track, `nil` where none fits.
        private func matched(_ tracks: [Track], _ videos: [ReleaseVideo], artist: String) -> [String?] {
            let result = TrackVideoMatcher.match(tracks: tracks, videos: videos, artist: artist)
            return tracks.indices.map { result[$0]?.title }
        }

        /// Four versions of one title: each video only to its own mix.
        @Test func remixesGoToTheirOwnTrack() {
            let tracks = [track("A1", "Airwave (Original Mix)"), track("A2", "Airwave (Guiseppe Ottaviani Extended Remix)"),
                          track("B1", "Airwave (Rank 1 vs. Dutch Force Remix)"), track("B2", "Airwave (Sunset Mix)")]
            let videos = [video("Rank 1 - Airwave (Sunset Mix)", "s"), video("Rank 1 - Airwave (Original Mix) [Be Yourself Music]", "o"),
                          video("Rank 1 - Airwave (Rank 1 vs. Dutch Force Remix)", "d")]
            #expect(matched(tracks, videos, artist: "Rank 1") == [
                "Rank 1 - Airwave (Original Mix) [Be Yourself Music]", nil,
                "Rank 1 - Airwave (Rank 1 vs. Dutch Force Remix)", "Rank 1 - Airwave (Sunset Mix)"])
        }
        /// A plain video is the original, never one of the remixes.
        @Test func plainVideoIsTheOriginal() {
            let tracks = [track("A", "Airwave"), track("B", "Airwave (Sunset Mix)")]
            #expect(matched(tracks, [video("Rank 1 – Airwave (Official Video)", "1")], artist: "Rank 1") == ["Rank 1 – Airwave (Official Video)", nil])
            // And a remix video doesn't stand in for the original.
            #expect(matched([track("A", "Airwave")], [video("Rank 1 - Airwave (Some Remix)", "2")], artist: "Rank 1") == [nil])
            #expect(matched([track("A", "Airwave")], [video("Rank 1 - Airwave (Radio Edit)", "3")], artist: "Rank 1") == [nil])
        }
        /// The title must be a whole part of the video's title, not just in it.
        @Test func titleMustMatchExactly() {
            let tracks = [track("A1", "Love"), track("A2", "One")]
            let videos = [video("Artist - Love Me Tender", "1"), video("Artist - Number One Hit", "2")]
            #expect(matched(tracks, videos, artist: "Artist") == [nil, nil])
        }
        /// Artist and title the other way round, without a dash, accents and case.
        @Test func toleratesCommonTitleForms() {
            let tracks = [track("A1", "Trans-Europa Express"), track("A2", "Spiegelsaal"), track("A3", "Schaufensterpuppen"), track("B1", "Café del Mar")]
            let videos = [video("Trans-Europa Express | Kraftwerk", "1"), video("Kraftwerk Spiegelsaal", "2"),
                          video("KRAFTWERK - SCHAUFENSTERPUPPEN (Remastered) HD", "3"), video("Kraftwerk - Cafe Del Mar", "4")]
            #expect(matched(tracks, videos, artist: "Kraftwerk") == [
                "Trans-Europa Express | Kraftwerk", "Kraftwerk Spiegelsaal", "KRAFTWERK - SCHAUFENSTERPUPPEN (Remastered) HD", "Kraftwerk - Cafe Del Mar"])
        }
        /// The part that is only the artist isn't a title – unless the track is named like the artist.
        @Test func artistAloneIsNoTitle() {
            #expect(matched([track("A", "Rank 1"), track("B", "Airwave")], [video("Rank 1 - Airwave", "1")], artist: "Rank 1") == [nil, "Rank 1 - Airwave"])
            #expect(matched([track("A", "Rank 1")], [video("Rank 1 - Rank 1", "2")], artist: "Rank 1") == ["Rank 1 - Rank 1"])
        }
        /// A mix named after the artist isn't the "Original Mix" – all its
        /// words are in the video's artist part, but the video says original.
        @Test func originalVideoIsNoArtistMix() {
            let tracks = [track("A1", "Flatliner (Original Mix)"), track("B1", "Flatliner (Roul De Chile Mix)"), track("B2", "Flatliner (DJ Arne L II Mix)")]
            let videos = [video("DJ Arne L II vs. Reactor - Flatliner (Original Mix) [HQ]", "1"), video("DJ Arne L2 vs. Reactor - Flatliner (Roul de Chile Rmx)", "2")]
            #expect(matched(tracks, videos, artist: "DJ Arne L II vs. Reactor") == [
                "DJ Arne L II vs. Reactor - Flatliner (Original Mix) [HQ]", "DJ Arne L2 vs. Reactor - Flatliner (Roul de Chile Rmx)", nil])
        }
        /// The remixer named in the artist part doesn't make it their remix.
        @Test func mixWordsCountOnlyAfterTheTitle() {
            let tracks = [track("A", "Horizon (Peter Luts Remix)"), track("B1", "Horizon (Jimmy Goldschmitz Remix)"), track("B2", "Horizon (Original Mix)")]
            let videos = [video("Jimmy Goldschmitz Vs Peter Luts - Horizon (Peter Luts Remix) [HQ]", "1")]
            #expect(matched(tracks, videos, artist: "Jimmy Goldschmitz Vs Peter Luts") == ["Jimmy Goldschmitz Vs Peter Luts - Horizon (Peter Luts Remix) [HQ]", nil, nil])
            // A mix after the title without parentheses still counts.
            #expect(matched([track("A", "Horizon (Peter Luts Remix)")], [video("Jimmy Goldschmitz - Horizon - Peter Luts Remix", "2")], artist: "Jimmy Goldschmitz")
                    == ["Jimmy Goldschmitz - Horizon - Peter Luts Remix"])
        }
        /// Full albums and live sets aren't a track.
        @Test func albumAndLiveVideosStayUnmatched() {
            let tracks = [track("A1", "Airwave")]
            let videos = [video("Rank 1 - Airwave (Full Album)", "1"), video("Rank 1 - Airwave (Live at Trance Energy 2002)", "2")]
            #expect(matched(tracks, videos, artist: "Rank 1") == [nil])
        }
        /// Featured artists and "Original Mix" on either side don't matter;
        /// of two fitting videos the one with less extra goes first.
        @Test func featuringAndOriginalMixAreIgnored() {
            let tracks = [track("1", "Silence (feat. Sarah McLachlan)")]
            let videos = [video("Delerium - Silence (Original Mix) [Nettwerk 1999]", "1"), video("Delerium feat. Sarah McLachlan - Silence", "2")]
            #expect(matched(tracks, videos, artist: "Delerium") == ["Delerium feat. Sarah McLachlan - Silence"])
        }
        @Test func linksFallBackToSearch() throws {
            let tracks = [track("A1", "Airwave (Original Mix)"), track("A2", "Airwave (Sunset Mix)")]
            let urls = TrackVideoLink.urls(for: tracks, videos: [video("Rank 1 - Airwave", "abc")], artist: "Rank 1 (2)")
            #expect(urls[0].absoluteString == "https://www.youtube.com/watch?v=abc")
            #expect(!TrackVideoLink.isSearch(urls[0]))
            #expect(TrackVideoLink.isSearch(urls[1]))
            let query = try #require(URLComponents(url: urls[1], resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
            #expect(query == "Rank 1 Airwave (Sunset Mix)")
            // Compilations: the track alone.
            let various = TrackVideoLink.search(track("1", "Dreamer"), artist: "Various")
            #expect(URLComponents(url: various, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "Dreamer")
        }
        @Test func releaseVideosKeepOnlyWebAddresses() throws {
            let data = Data(#"{"id":1,"videos":[{"uri":"https://www.youtube.com/watch?v=a","title":"A - B"},{"uri":"javascript:alert(1)","title":"x"},{"title":"no uri"}]}"#.utf8)
            let dto = try JSONDecoder().decode(DiscogsReleaseDTO.self, from: data)
            #expect(dto.releaseVideos == [ReleaseVideo(title: "A - B", url: "https://www.youtube.com/watch?v=a")])
            #expect(try JSONDecoder().decode(DiscogsReleaseDTO.self, from: Data(#"{"id":1}"#.utf8)).releaseVideos.isEmpty)
        }
    }
}
