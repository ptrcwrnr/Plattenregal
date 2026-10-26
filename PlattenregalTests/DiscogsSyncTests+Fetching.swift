import Foundation
import Testing
import SwiftData
import Synchronization
@testable import Plattenregal

extension AllTests.DiscogsSyncTests {
    @Test func paginationFailureDoesNotModifyAnyScope() async throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()], wants: [want()], folders: [.init(id: 1, name: "Original", count: 1)])
        let api = DiscogsAPIClient.stubbed(SyncPaginationProtocol.self)
        let sync = DiscogsSyncService(api: api)
        do { _ = try await sync.fetch(.all, container: c); Issue.record("Expected page 2 failure") }
        catch DiscogsError.offline {} catch { Issue.record("Unexpected \(error)") }
        #expect(try copies(c).count == 1); #expect(try copies(c).first?.discogsActive == true)
        #expect(try ModelContext(c).fetch(FetchDescriptor<DiscogsFolder>()).first?.name == "Original")
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()) == 1)
    }
    @Test func completePaginationAndDuplicateDetection() async throws {
        let api = DiscogsAPIClient.stubbed(SyncPaginationProtocol.self)
        let collection = try await api.collection(username: "success")
        #expect(collection.count == 2); #expect(collection.map(\.instance_id) == [1, 2])
        do { _ = try await api.collection(username: "duplicate"); Issue.record("Duplicate accepted") }
        catch DiscogsError.incompletePagination {} catch { Issue.record("Unexpected \(error)") }
    }
    @Test func completeWantlistPagination() async throws {
        let api = DiscogsAPIClient.stubbed(SyncPaginationProtocol.self)
        let wants = try await api.wants(username: "success")
        #expect(wants.map(\.id) == [1, 2])
    }
    /// An empty collection or wantlist is complete, not a failed download –
    /// whether Discogs counts it as one empty page or as none.
    @Test func emptyListsAreComplete() async throws {
        let api = DiscogsAPIClient.stubbed(SyncPaginationProtocol.self)
        #expect(try await api.collection(username: "empty1").isEmpty)
        #expect(try await api.collection(username: "empty0").isEmpty)
        #expect(try await api.wants(username: "empty1").isEmpty)
        // Emptied on Discogs: the records leave the collection, the wantlist goes.
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()], wants: [want(43)])
        let summary = try merge(c, collection: try await api.collection(username: "empty1"), wants: try await api.wants(username: "empty1"))
        #expect(summary.collectionRemoved == 1 && summary.wantsRemoved == 1)
        #expect(try copies(c).first?.discogsActive == false)
    }
    @Test func wantlistPresentationSortsByArtistForAlphabetNavigation() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let olderRelease = Release(artist: "Zeta Artist", title: "Earlier")
        let older = WantlistEntry(owner: "fixture", release: olderRelease, releaseID: 1)
        older.dateAdded = "2026-09-21T12:00:00+02:00"
        let newerRelease = Release(artist: "Äther Artist", title: "Later")
        let newer = WantlistEntry(owner: "fixture", release: newerRelease, releaseID: 2)
        newer.dateAdded = "2026-09-21T10:30:00Z"
        c.mainContext.insert(older); c.mainContext.insert(newer)

        #expect(WantlistPresentation.sorted([older, newer]).map(\.releaseID) == [2, 1])
        #expect(SortingService.alphabetSection(for: newerRelease.displayArtist) == "A")
    }
    @Test func wantlistPresentationSearchesMetadataCaseAndAccentInsensitively() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let release = Release(artist: "Röyksopp", title: "Melody A.M.")
        release.label = "Wall of Sound"
        let entry = WantlistEntry(owner: "fixture", release: release, releaseID: 17)
        c.mainContext.insert(entry)

        // The wantlist page searches a `SearchIndex` over `searchText`.
        func finds(_ query: String) -> Bool {
            SearchIndex([entry], id: \.releaseID, text: WantlistPresentation.searchText)
                .matches(17, SearchIndex<Int>.words(query))
        }
        #expect(finds("royksopp"))
        #expect(finds("WALL"))
        #expect(!finds("missing"))
        // Words in any order, "ss" finds "ß".
        #expect(finds("sound royksopp"))
        release.tracks = [Track(position: "A1", title: "So Easy", duration: ""), Track(position: "B2", title: "Straßenbahn", duration: "")]
        #expect(finds("strassenbahn"))
        #expect(release.track(matching: "strassenbahn")?.position == "B2")
        #expect(release.track(matching: "royksopp") == nil)
    }
    @Test func releasesGoneFromDiscogsAreNotAskedAgainAtEveryLaunch() async throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry(1, release: 404), entry(2, release: 403), entry(3, release: 200)])
        let sync = DiscogsSyncService(api: .stubbed(TracklistStatusProtocol.self))
        #expect(await sync.loadTracklists(container: c, quiet: true))
        let releases = Dictionary(uniqueKeysWithValues: try ModelContext(c).fetch(FetchDescriptor<Release>()).map { ($0.discogsID, $0) })
        #expect(releases[200]?.tracks.map(\.title) == ["Intro"])
        // Removed on Discogs: stamped, so the next launch has nothing to do for it.
        #expect(releases[404]?.detailsFetchedAt != nil)
        // 403 may be the token, not the release: tried again next time.
        #expect(releases[403]?.detailsFetchedAt == nil)
        // Videos come with the same request; the removed release counts as asked.
        let lists = Dictionary(uniqueKeysWithValues: try ModelContext(c).fetch(FetchDescriptor<ReleaseVideoList>()).map { ($0.discogsID, $0.videos) })
        #expect(lists[200]?.map(\.url) == ["https://www.youtube.com/watch?v=intro"])
        #expect(lists[404] == [])
        #expect(lists[403] == nil)
    }
    /// A refused release (403) may be about that release – but several in a
    /// row mean the token or an outage: the download stops instead of asking
    /// every remaining release, and leaves them for next time.
    @Test func tracklistsStopAfterRefusalsInARow() async throws {
        let refused = (1...8).map { entry($0, release: $0) }
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: refused)
        RefusingReleasesProtocol.releaseRequests.withLock { $0 = 0 }
        let sync = DiscogsSyncService(api: .stubbed(RefusingReleasesProtocol.self))
        #expect(await sync.loadTracklists(container: c, quiet: false))
        #expect(RefusingReleasesProtocol.releaseRequests.withLock { $0 } == DiscogsSyncService.tracklistRefusalLimit)
        #expect(sync.error?.contains("später automatisch nachgeholt") == true)
        #expect(try ModelContext(c).fetch(FetchDescriptor<Release>()).allSatisfy { $0.detailsFetchedAt == nil })

        // Fewer refusals than the limit, between good answers: every release is asked.
        let mixed = try LibraryStorage.makeContainer(inMemory: true)
        try merge(mixed, collection: (1...4).map { entry($0, release: $0) } + [entry(5, release: 1005)])
        RefusingReleasesProtocol.releaseRequests.withLock { $0 = 0 }
        let quiet = DiscogsSyncService(api: .stubbed(RefusingReleasesProtocol.self))
        #expect(await quiet.loadTracklists(container: mixed, quiet: false))
        #expect(RefusingReleasesProtocol.releaseRequests.withLock { $0 } == 5)
        #expect(quiet.error == nil)
    }

    /// The popover fetches the videos of a release loaded before videos were
    /// stored. Gone from Discogs: an empty list, so it isn't asked at every
    /// opening; a 403 may be the token: left for later.
    @Test @MainActor func popoverLoadsMissingVideosQuietly() async throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry(1, release: 404), entry(2, release: 403), entry(3, release: 200)])
        let context = c.mainContext
        let releases = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Release>()).map { ($0.discogsID, $0) })
        let sync = DiscogsSyncService(api: .stubbed(TracklistStatusProtocol.self))
        for id in [404, 403, 200] { await sync.loadVideos(for: try #require(releases[id]), context: context) }
        let lists = Dictionary(uniqueKeysWithValues: try ModelContext(c).fetch(FetchDescriptor<ReleaseVideoList>()).map { ($0.discogsID, $0.videos) })
        #expect(lists[200]?.map(\.title) == ["Artist - Intro"])
        #expect(releases[200]?.tracks.map(\.title) == ["Intro"])
        #expect(lists[404] == [])
        #expect(lists[403] == nil)
    }
    /// At launch the download runs unseen: no status line while it loads and
    /// no "abgeschlossen" afterwards. Only a sync the user starts shows it.
    @Test @MainActor func tracklistsResumedAtLaunchStayInvisible() async throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry(1, release: 200)])
        let sync = DiscogsSyncService(api: .stubbed(TracklistStatusProtocol.self))
        sync.startTracklists(container: c, fromSync: false)
        var everShown = false
        func loaded() throws -> Bool { try ModelContext(c).fetch(FetchDescriptor<Release>()).first?.tracks.isEmpty == false }
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            everShown = everShown || sync.hasStatus || sync.isRunning
            if try loaded(), !sync.isWorking { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try loaded())
        #expect(!everShown)
        // "abgeschlossen" would have been set right at the end.
        try await Task.sleep(for: .milliseconds(100))
        #expect(!sync.hasStatus && !sync.isWorking)
    }
    /// The "x" while the collection value is fetched: the merge is saved
    /// by then, so there is no error to show – and no tracklist download
    /// starting behind a status that is gone.
    @Test @MainActor func cancellingAfterTheMergeIsNoErrorAndLoadsNoTracklists() async throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let sync = DiscogsSyncService(api: .stubbed(CancelDuringValueProtocol.self))
        CancelDuringValueProtocol.onValueRequest.withLock { $0 = { Task { @MainActor in sync.cancel() } } }
        sync.start(.collection, container: c)
        let deadline = ContinuousClock.now + .seconds(10)
        while sync.busy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!sync.busy)
        #expect(try copies(c).map(\.discogsInstanceID) == [1])
        #expect(sync.error == nil)
        #expect(!sync.hasStatus && !sync.isRunning)
        try await Task.sleep(for: .milliseconds(100))
        #expect(CancelDuringValueProtocol.releaseRequests.withLock { $0 } == 0)
    }
    @Test func syncSummaryOnlyMentionsTheRequestedScope() {
        var summary = DiscogsSyncSummary()
        summary.collectionAdded = 2; summary.wantsAdded = 3; summary.foldersChanged = 1

        #expect(summary.description(for: .collection) == "2 hinzugefügt")
        #expect(summary.description(for: .wantlist) == "3 hinzugefügt")
        #expect(summary.description(for: .all) == "Collection: 2 hinzugefügt\nWantlist: 3 hinzugefügt")
        #expect(DiscogsSyncSummary().description(for: .collection) == "Nichts hinzugefügt")
    }
}
