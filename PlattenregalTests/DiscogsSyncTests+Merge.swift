import Foundation
import Testing
import SwiftData
import Synchronization
@testable import Plattenregal

extension AllTests.DiscogsSyncTests {
    @Test func initialCollectionImport() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let summary = try merge(c, collection: [entry()])
        let copy = try #require(copies(c).first)
        #expect(summary.collectionAdded == 1); #expect(copy.discogsInstanceID == 100)
        #expect(copy.release?.discogsID == 42); #expect(copy.release?.masterID == 123)
        #expect(copy.shelf == nil); #expect(copy.positionInShelf == 0)
    }
    @Test func collectionSyncUsesArtistNameVariationShownOnRelease() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let displayedArtist = DiscogsBasicInformation(id: 42, title: "Trains, Planes & Automobiles",
            artists: [.init(id: 4711, name: "Joris Biesmans", anv: "Biesmans", join: nil)], year: 2021,
            labels: nil, formats: nil, genres: nil, styles: nil, cover_image: nil, thumb: nil,
            resource_url: nil, master_id: nil)
        let item = DiscogsCollectionDTO(id: 42, instance_id: 100, folder_id: 1, date_added: "2022-10-21",
            basic_information: displayedArtist)

        try merge(c, collection: [item])

        let synced = try #require(copies(c).first)
        #expect(synced.release?.artist == "Biesmans")
        let caribou = RecordCopy(release: Release(artist: "Caribou", title: "Album"), instanceID: 2, owner: "fixture")
        #expect(SortingService.sorted([caribou, synced]).compactMap { $0.release?.artist } == ["Biesmans", "Caribou"])
    }
    @Test func collectionSyncFallsBackToCanonicalArtistForBlankVariation() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let displayedArtist = DiscogsBasicInformation(id: 42, title: "Album",
            artists: [.init(id: 4711, name: "Canonical Artist", anv: "  ", join: nil)], year: nil,
            labels: nil, formats: nil, genres: nil, styles: nil, cover_image: nil, thumb: nil,
            resource_url: nil, master_id: nil)
        let item = DiscogsCollectionDTO(id: 42, instance_id: 100, folder_id: 1, date_added: "2026-09-21",
            basic_information: displayedArtist)

        try merge(c, collection: [item])

        #expect(try copies(c).first?.release?.artist == "Canonical Artist")
    }
    @Test func repeatedSyncIsIdempotent() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()]); let id = try copies(c).first?.id
        let summary = try merge(c, collection: [entry()])
        #expect(try copies(c).count == 1); #expect(try copies(c).first?.id == id)
        #expect(summary.collectionAdded == 0); #expect(summary.collectionUpdated == 0)
    }
    @Test func newReleaseAdded() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()]); try merge(c, collection: [entry(), entry(200, release: 43)])
        #expect(try copies(c).count == 2)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<Release>()) == 2)
    }
    @Test func removedCollectionRetainsLocalCopyAndRelease() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()], wants: [want()]); try merge(c, collection: [])
        #expect(try copies(c).first?.discogsActive == false)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<Release>()) == 1)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()) == 1)
    }
    @Test func newFolder() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, folders: [.init(id: 9, name: "Trance", count: 1)])
        let f = try #require(ModelContext(c).fetch(FetchDescriptor<DiscogsFolder>()).first)
        #expect(f.folderID == 9); #expect(f.name == "Trance"); #expect(f.count == 1)
    }
    @Test func renamedFolderPreservesStableIdentity() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, folders: [.init(id: 9, name: "Trance", count: 1)])
        try merge(c, folders: [.init(id: 9, name: "Techno", count: 2)])
        let folders = try ModelContext(c).fetch(FetchDescriptor<DiscogsFolder>())
        #expect(folders.count == 1); #expect(folders.first?.name == "Techno"); #expect(folders.first?.folderID == 9)
    }
    @Test func deletedFolderClearsOnlyAssignment() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry(folder: 9)], folders: [.init(id: 9, name: "Trance", count: 1)])
        try merge(c, folders: [])
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<DiscogsFolder>()) == 0)
        #expect(try copies(c).first?.discogsFolderID == nil); #expect(try copies(c).first?.discogsActive == true)
    }
    @Test func wantlistAddedUsesSharedRelease() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()], wants: [want()])
        let wants = try ModelContext(c).fetch(FetchDescriptor<WantlistEntry>())
        #expect(wants.count == 1); try #expect(wants.first?.release?.id == copies(c).first?.release?.id)
        #expect(wants.first?.notes == "Want note")
    }
    @Test func duplicatesAlreadyInTheStoreDoNotStopTheSync() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let context = ModelContext(c)
        let release = Release(discogsID: 42, artist: "Artist", title: "Album")
        context.insert(release)
        for _ in 0..<2 { context.insert(WantlistEntry(owner: "fixture", release: release, releaseID: 42)) }
        for _ in 0..<2 { context.insert(DiscogsFolder(owner: "fixture", id: 1, name: "Alt", count: 0)) }
        try context.save()
        // Used to trap building its lookup tables; now the first of each is updated.
        try merge(c, wants: [want()], folders: [.init(id: 1, name: "Neu", count: 1)])
        let folders = try ModelContext(c).fetch(FetchDescriptor<DiscogsFolder>())
        #expect(folders.contains { $0.name == "Neu" })
    }
    @Test func valueRefreshAfterWantlistOnlySyncIsNoError() async throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let account = DiscogsAccount(username: "fixture")
        account.credentialFingerprint = DiscogsAPIClient.fingerprint(of: "token")
        account.lastWantlistSync = .now
        c.mainContext.insert(account); try c.mainContext.save()
        // No collection synced yet: nothing to value, and not "account changed".
        try await CollectionValueHistoryService().refresh(owner: "fixture", container: c,
            api: DiscogsAPIClient(tokenProvider: { "token" }))
    }
    @Test func wantlistRemovedDeletesUnownedRelease() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, wants: [want(), want(43)]); try merge(c, wants: [want(43)])
        let releases = try ModelContext(c).fetch(FetchDescriptor<Release>())
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()) == 1)
        #expect(releases.map(\.discogsID) == [43])
    }
    @Test func storeKeepsOneReleasePerDiscogsID() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let context = ModelContext(c)
        for title in ["First", "Second"] { context.insert(Release(discogsID: 42, artist: "A", title: title)) }
        context.insert(Release(discogsID: 43, artist: "B", title: "Other"))
        try context.save()
        let releases = try ModelContext(c).fetch(FetchDescriptor<Release>())
        #expect(releases.filter { $0.discogsID == 42 }.count == 1)
        #expect(releases.count == 2)
    }
    @Test func wantlistRemovedRetainsOwnedRelease() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()], wants: [want()]); try merge(c, collection: [entry()], wants: [])
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<Release>()) == 1)
        #expect(try copies(c).first?.release?.discogsID == 42)
    }
    @Test func twoInstancesShareMetadataRemainSeparate() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry(), entry(200)])
        let items = try copies(c)
        #expect(Set(items.map(\.discogsInstanceID)) == [100, 200])
        #expect(Set(items.compactMap { $0.release?.id }).count == 1)
    }
    @Test func shelfPlaceSurvivesUpdateAndRemoval() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let shelf = try #require(c.mainContext.fetch(FetchDescriptor<Shelf>()).first)
        try merge(c, collection: [entry()])
        let copy = try #require(c.mainContext.fetch(FetchDescriptor<RecordCopy>()).first)
        try PositionService(context: c.mainContext).move(copy, to: shelf, position: 1)
        let id = copy.id; let shelfID = shelf.id
        try merge(c, collection: [entry()]); try merge(c, collection: [entry(folder: 9)]); try merge(c, collection: [])
        let restored = try #require(copies(c).first { $0.id == id })
        #expect(restored.shelf?.id == shelfID); #expect(restored.positionInShelf == 1)
        #expect(restored.discogsActive == false)
        try merge(c, collection: [entry()]); #expect(try copies(c).count == 1)
    }
    @Test func folderSyncDoesNotRemoveCollectionMembershipOrOtherFolders() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry(), entry(200, folder: 9)])
        try merge(c, collection: [], scope: .folder(1))
        let items = try copies(c)
        #expect(items.allSatisfy { $0.discogsActive == true })
        #expect(items.first { $0.discogsInstanceID == 100 }?.discogsFolderID == nil)
        #expect(items.first { $0.discogsInstanceID == 200 }?.discogsFolderID == 9)
    }
    @Test func wantlistToCollectionTransition() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, wants: [want()]); try merge(c, collection: [entry()], wants: [])
        #expect(try copies(c).count == 1)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()) == 0)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<Release>()) == 1)
    }
    @Test func accountIsolation() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()]); try merge(c, collection: [], owner: "other")
        #expect(try copies(c).first?.discogsActive == true)
    }
    @Test func mostRecentSyncOfAnyKindPicksTheCurrentAccount() {
        let day = { (n: Double) in Date(timeIntervalSince1970: n * 86400) }
        // A: full sync on day 1, B: collection on day 2, then A again, only its collection, on day 3.
        let a = DiscogsAccount(username: "a"); a.lastFullSync = day(1); a.lastCollectionSync = day(3)
        let b = DiscogsAccount(username: "b"); b.lastCollectionSync = day(2); b.lastWantlistSync = day(2)
        #expect(DiscogsAccount.current(in: [a, b])?.username == "a")
        #expect(DiscogsAccount.current(in: [b, a])?.username == "a")
        b.lastWantlistSync = day(4)
        #expect(DiscogsAccount.current(in: [a, b])?.username == "b")
        #expect(DiscogsAccount.current(in: []) == nil)
    }
}
