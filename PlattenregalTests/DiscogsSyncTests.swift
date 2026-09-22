import XCTest
import SwiftData
@testable import Plattenregal

@MainActor final class DiscogsSyncTests: XCTestCase {
    private func basic(_ id: Int = 42, title: String = "Album") -> DiscogsBasicInformation {
        DiscogsBasicInformation(id: id, title: title, artists: [.init(id: 1, name: "Artist", join: nil)], year: 1999,
            labels: [.init(id: 2, name: "Label", catno: "CAT-1")], formats: [.init(name: "Vinyl", qty: "1", descriptions: ["LP"])],
            genres: ["Electronic"], styles: ["Trance"], cover_image: "https://example.com/cover", thumb: "https://example.com/thumb", resource_url: "https://api.discogs.com/releases/\(id)", master_id: 123)
    }
    private func entry(_ instance: Int = 100, release: Int = 42, folder: Int = 1) -> DiscogsCollectionDTO {
        .init(id: release, instance_id: instance, folder_id: folder, date_added: "2026-09-20T08:00:00+02:00", rating: 4, notes: [.init(field_id: 3, value: "Discogs note")], basic_information: basic(release))
    }
    private func want(_ id: Int = 42) -> DiscogsWantDTO {
        .init(id: id, date_added: "2026-09-20T08:00:00+02:00", rating: 3, notes: "Want note", basic_information: basic(id))
    }
    @discardableResult private func merge(_ container: ModelContainer, collection: [DiscogsCollectionDTO]? = nil, wants: [DiscogsWantDTO]? = nil,
        folders: [DiscogsFolderDTO]? = nil, scope: DiscogsSyncScope = .all, owner: String = "fixture") throws -> DiscogsSyncSummary {
        try DiscogsSyncService.merge(.init(username: owner, userID: 7, fingerprint: "fixture", scope: scope, folders: folders, collection: collection, wants: wants), container: container)
    }
    private func copies(_ container: ModelContainer) throws -> [RecordCopy] { try ModelContext(container).fetch(FetchDescriptor<RecordCopy>()) }
    func testRetryAfterSecondsAndHTTPDate() {
        XCTAssertEqual(DiscogsAPIClient.retryDelay("12"), 12)
        XCTAssertEqual(DiscogsAPIClient.retryDelay(nil), 60)
        XCTAssertEqual(DiscogsAPIClient.retryDelay("Thu, 01 Jan 1970 00:01:00 GMT", now: Date(timeIntervalSince1970: 0)), 60)
    }
    func testLargeCollectionMergeAndRepeat() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let items = (1...2000).map { entry($0, release: $0) }
        try merge(c, collection: items)
        let repeated = try merge(c, collection: items)
        XCTAssertEqual(try copies(c).count, 2000)
        XCTAssertEqual(repeated.collectionAdded, 0); XCTAssertEqual(repeated.collectionUpdated, 0)
    }
    func testCancelledMergeDoesNotWrite() async throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()])
        let snapshot = DiscogsSyncSnapshot(username: "fixture", userID: 7, fingerprint: "fixture", scope: .collection, collection: [])
        let task = Task { @MainActor in
            try Task.checkCancellation()
            return try DiscogsSyncService.merge(snapshot, container: c)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        XCTAssertEqual(try copies(c).first?.discogsActive, true)
    }
    func testUnplacedCopyCanBeEditedAndPlaced() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()])
        let copy = try XCTUnwrap(c.mainContext.fetch(FetchDescriptor<RecordCopy>()).first)
        let service = PositionService(context: c.mainContext)
        try service.unplace(copy) { copy.notes = "Local unplaced note" }
        let shelf = try XCTUnwrap(c.mainContext.fetch(FetchDescriptor<Shelf>()).first)
        try service.move(copy, to: shelf, position: 1)
        XCTAssertEqual(copy.positionInShelf, 1); XCTAssertEqual(copy.notes, "Local unplaced note")
        XCTAssertEqual(copy.discogsInstanceID, 100)
    }
    func testWantlistFailureAfterCompleteCollectionDoesNotCommit() async throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()], wants: [want()], owner: "wantfailure")
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncPaginationProtocol.self]
        let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "wantfailure" })
        let sync = DiscogsSyncService(api: api)
        do { _ = try await sync.fetch(.all, container: c); XCTFail("Expected wantlist failure") }
        catch DiscogsError.offline {}
        XCTAssertEqual(try copies(c).first?.discogsInstanceID, 100)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()), 1)
    }
    func testInitialCollectionImport() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let summary = try merge(c, collection: [entry()])
        let copy = try XCTUnwrap(copies(c).first)
        XCTAssertEqual(summary.collectionAdded, 1); XCTAssertEqual(copy.discogsInstanceID, 100)
        XCTAssertEqual(copy.release?.discogsID, 42); XCTAssertEqual(copy.release?.masterID, 123)
        XCTAssertEqual(copy.discogsRating, 4); XCTAssertNil(copy.shelf); XCTAssertEqual(copy.positionInShelf, 0)
    }
    func testCollectionSyncUsesArtistNameVariationShownOnRelease() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let displayedArtist = DiscogsBasicInformation(id: 42, title: "Trains, Planes & Automobiles",
            artists: [.init(id: 4711, name: "Joris Biesmans", anv: "Biesmans", join: nil)], year: 2021,
            labels: nil, formats: nil, genres: nil, styles: nil, cover_image: nil, thumb: nil,
            resource_url: nil, master_id: nil)
        let item = DiscogsCollectionDTO(id: 42, instance_id: 100, folder_id: 1, date_added: "2022-10-21", rating: 0,
            notes: nil, basic_information: displayedArtist)

        try merge(c, collection: [item])

        let synced = try XCTUnwrap(copies(c).first)
        XCTAssertEqual(synced.release?.artist, "Biesmans")
        let caribou = RecordCopy(release: Release(artist: "Caribou", title: "Album"))
        XCTAssertEqual(SortingService.sorted([caribou, synced], by: .artistAZ).compactMap { $0.release?.artist }, ["Biesmans", "Caribou"])
    }
    func testCollectionSyncFallsBackToCanonicalArtistForBlankVariation() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let displayedArtist = DiscogsBasicInformation(id: 42, title: "Album",
            artists: [.init(id: 4711, name: "Canonical Artist", anv: "  ", join: nil)], year: nil,
            labels: nil, formats: nil, genres: nil, styles: nil, cover_image: nil, thumb: nil,
            resource_url: nil, master_id: nil)
        let item = DiscogsCollectionDTO(id: 42, instance_id: 100, folder_id: 1, date_added: "2026-09-21", rating: 0,
            notes: nil, basic_information: displayedArtist)

        try merge(c, collection: [item])

        XCTAssertEqual(try copies(c).first?.release?.artist, "Canonical Artist")
    }
    func testRepeatedSyncIsIdempotent() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()]); let id = try copies(c).first?.id
        let summary = try merge(c, collection: [entry()])
        XCTAssertEqual(try copies(c).count, 1); XCTAssertEqual(try copies(c).first?.id, id)
        XCTAssertEqual(summary.collectionAdded, 0); XCTAssertEqual(summary.collectionUpdated, 0)
    }
    func testNewReleaseAdded() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()]); try merge(c, collection: [entry(), entry(200, release: 43)])
        XCTAssertEqual(try copies(c).count, 2)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<Release>()), 2)
    }
    func testRemovedCollectionRetainsLocalCopyAndRelease() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()], wants: [want()]); try merge(c, collection: [])
        XCTAssertEqual(try copies(c).first?.discogsActive, false)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<Release>()), 1)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()), 1)
    }
    func testFolderMove() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()]); try merge(c, collection: [entry(folder: 9)])
        XCTAssertEqual(try copies(c).first?.discogsFolderID, 9)
    }
    func testNewFolder() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, folders: [.init(id: 9, name: "Trance", count: 1)])
        let f = try XCTUnwrap(ModelContext(c).fetch(FetchDescriptor<DiscogsFolder>()).first)
        XCTAssertEqual(f.folderID, 9); XCTAssertEqual(f.name, "Trance"); XCTAssertNotNil(f.lastSync)
    }
    func testRenamedFolderPreservesStableIdentity() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, folders: [.init(id: 9, name: "Trance", count: 1)])
        try merge(c, folders: [.init(id: 9, name: "Techno", count: 2)])
        let folders = try ModelContext(c).fetch(FetchDescriptor<DiscogsFolder>())
        XCTAssertEqual(folders.count, 1); XCTAssertEqual(folders.first?.name, "Techno"); XCTAssertEqual(folders.first?.folderID, 9)
    }
    func testDeletedFolderClearsOnlyAssignment() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry(folder: 9)], folders: [.init(id: 9, name: "Trance", count: 1)])
        try merge(c, folders: [])
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<DiscogsFolder>()), 0)
        XCTAssertNil(try copies(c).first?.discogsFolderID); XCTAssertEqual(try copies(c).first?.discogsActive, true)
    }
    func testWantlistAddedUsesSharedRelease() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()], wants: [want()])
        let wants = try ModelContext(c).fetch(FetchDescriptor<WantlistEntry>())
        XCTAssertEqual(wants.count, 1); XCTAssertEqual(wants.first?.release?.id, try copies(c).first?.release?.id)
        XCTAssertEqual(wants.first?.notes, "Want note")
    }
    func testWantlistRemovedRetainsRelease() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, wants: [want()]); try merge(c, wants: [])
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()), 0)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<Release>()), 1)
    }
    func testTwoInstancesShareMetadataRemainSeparate() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry(), entry(200)])
        let items = try copies(c)
        XCTAssertEqual(Set(items.compactMap(\.discogsInstanceID)), [100, 200])
        XCTAssertEqual(Set(items.compactMap { $0.release?.id }).count, 1)
    }
    func testKallaxAndAllLocalFieldsSurviveUpdateAndRemoval() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let shelf = try XCTUnwrap(c.mainContext.fetch(FetchDescriptor<Shelf>()).first)
        let release = Release(artist: "Old", title: "Old"); release.discogsID = 42
        let copy = try PositionService(context: c.mainContext).insert(release: release, shelf: shelf, position: 1) {
            $0.notes = "LOCAL"; $0.condition = "Mint"; $0.purchasePrice = 37.5
            $0.purchaseDate = Date(timeIntervalSince1970: 123); $0.dateAdded = Date(timeIntervalSince1970: 456)
        }
        let id = copy.id; let shelfID = shelf.id
        try merge(c, collection: [entry()]); try merge(c, collection: [entry(folder: 9)]); try merge(c, collection: [])
        let restored = try XCTUnwrap(copies(c).first { $0.id == id })
        XCTAssertEqual(restored.shelf?.id, shelfID); XCTAssertEqual(restored.positionInShelf, 1)
        XCTAssertEqual(restored.notes, "LOCAL"); XCTAssertEqual(restored.condition, "Mint")
        XCTAssertEqual(restored.purchasePrice, 37.5); XCTAssertEqual(restored.purchaseDate, Date(timeIntervalSince1970: 123))
        XCTAssertEqual(restored.dateAdded, Date(timeIntervalSince1970: 456)); XCTAssertEqual(restored.discogsActive, false)
        try merge(c, collection: [entry()]); XCTAssertEqual(try copies(c).count, 1)
    }
    func testFolderSyncDoesNotRemoveCollectionMembershipOrOtherFolders() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry(), entry(200, folder: 9)])
        try merge(c, collection: [], scope: .folder(1))
        let items = try copies(c)
        XCTAssertTrue(items.allSatisfy { $0.discogsActive == true })
        XCTAssertNil(items.first { $0.discogsInstanceID == 100 }?.discogsFolderID)
        XCTAssertEqual(items.first { $0.discogsInstanceID == 200 }?.discogsFolderID, 9)
    }
    func testWantlistToCollectionTransition() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, wants: [want()]); try merge(c, collection: [entry()], wants: [])
        XCTAssertEqual(try copies(c).count, 1)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()), 0)
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<Release>()), 1)
    }
    func testAccountIsolation() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()]); try merge(c, collection: [], owner: "other")
        XCTAssertEqual(try copies(c).first?.discogsActive, true)
    }
    func testV1MigrationPreservesLocalData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Migration.store")
        let id: UUID = try autoreleasepool {
            let schema = Schema(versionedSchema: LibrarySchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let shelf = LibrarySchemaV1.Shelf(number: 6)
            let release = LibrarySchemaV1.Release(artist: "Artist", title: "Album"); release.discogsID = 42
            let copy = LibrarySchemaV1.RecordCopy(release: release, shelf: shelf, position: 37)
            copy.notes = "Preserve"; copy.purchasePrice = 12
            container.mainContext.insert(copy); try container.mainContext.save(); return copy.id
        }
        let schema = Schema(versionedSchema: LibrarySchemaV6.self)
        let migrated = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let copy = try XCTUnwrap(copies(migrated).first)
        XCTAssertEqual(copy.id, id); XCTAssertEqual(copy.positionInShelf, 37); XCTAssertEqual(copy.shelf?.number, 6)
        XCTAssertEqual(copy.notes, "Preserve"); XCTAssertEqual(copy.purchasePrice, 12)
        try merge(migrated, collection: [entry()])
        XCTAssertEqual(try copies(migrated).first?.notes, "Preserve")
    }
    func testPaginationFailureDoesNotModifyAnyScope() async throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        try merge(c, collection: [entry()], wants: [want()], folders: [.init(id: 1, name: "Original", count: 1)])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncPaginationProtocol.self]
        let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "fixture" })
        let sync = DiscogsSyncService(api: api)
        do { _ = try await sync.fetch(.all, container: c); XCTFail("Expected page 2 failure") }
        catch DiscogsError.offline {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertEqual(try copies(c).count, 1); XCTAssertEqual(try copies(c).first?.discogsActive, true)
        XCTAssertEqual(try ModelContext(c).fetch(FetchDescriptor<DiscogsFolder>()).first?.name, "Original")
        XCTAssertEqual(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()), 1)
    }
    func testCompletePaginationAndDuplicateDetection() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncPaginationProtocol.self]
        let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "fixture" })
        let collection = try await api.collection(username: "success")
        XCTAssertEqual(collection.count, 2); XCTAssertEqual(collection.map(\.instance_id), [1, 2])
        do { _ = try await api.collection(username: "duplicate"); XCTFail("Duplicate accepted") }
        catch DiscogsError.incompletePagination {} catch { XCTFail("Unexpected \(error)") }
    }
    func testCompleteWantlistPagination() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncPaginationProtocol.self]
        let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "fixture" })
        let wants = try await api.wants(username: "success")
        XCTAssertEqual(wants.map(\.id), [1, 2])
    }
    func testWantlistPresentationSortsNewestFirst() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let olderRelease = Release(artist: "Older Artist", title: "Earlier")
        let older = WantlistEntry(owner: "fixture", release: olderRelease, releaseID: 1)
        older.dateAdded = "2026-09-21T12:00:00+02:00"
        let newerRelease = Release(artist: "Newer Artist", title: "Later")
        let newer = WantlistEntry(owner: "fixture", release: newerRelease, releaseID: 2)
        newer.dateAdded = "2026-09-21T10:30:00Z"
        c.mainContext.insert(older); c.mainContext.insert(newer)

        XCTAssertEqual(WantlistPresentation.entries([older, newer], matching: "").map(\.releaseID), [2, 1])
    }
    func testWantlistPresentationSearchesMetadataCaseAndAccentInsensitively() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let release = Release(artist: "Röyksopp", title: "Melody A.M.")
        release.label = "Wall of Sound"
        let entry = WantlistEntry(owner: "fixture", release: release, releaseID: 17)
        c.mainContext.insert(entry)

        XCTAssertEqual(WantlistPresentation.entries([entry], matching: "royksopp").map(\.releaseID), [17])
        XCTAssertEqual(WantlistPresentation.entries([entry], matching: "WALL").map(\.releaseID), [17])
        XCTAssertTrue(WantlistPresentation.entries([entry], matching: "missing").isEmpty)
    }
    func testSyncSummaryOnlyMentionsTheRequestedScope() {
        var summary = DiscogsSyncSummary()
        summary.collectionAdded = 2; summary.wantsAdded = 3; summary.foldersChanged = 1

        XCTAssertEqual(summary.description(for: .collection), "Collection: +2, 0 aktualisiert, −0 · Ordner: 1 geändert")
        XCTAssertEqual(summary.description(for: .wantlist), "Wantlist: +3, −0")
        XCTAssertFalse(summary.description(for: .collection).contains("Wantlist"))
    }
}

final class SyncPaginationProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let page = Int(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "page" }?.value ?? "1") ?? 1
        let body: String
        if url.path == "/oauth/identity" { body = request.value(forHTTPHeaderField: "Authorization") == "Discogs token=wantfailure" ? #"{"id":7,"username":"wantfailure"}"# : #"{"id":7,"username":"fixture"}"# }
        else if url.path.hasSuffix("/folders") { body = #"{"folders":[{"id":1,"name":"Changed","count":2}]}"# }
        else {
            if (page == 2 && url.path.contains("/fixture/")) || (url.path.contains("/wantfailure/") && url.path.hasSuffix("/wants")) {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            }
            let id = url.path.contains("/duplicate/") ? 1 : page
            let item = """
            {"id":\(id),"instance_id":\(id),"folder_id":1,"date_added":"2026-09-20","rating":0,"basic_information":{"id":\(id),"title":"Album","artists":[]}}
            """
            let key = url.path.hasSuffix("/wants") ? "wants" : "releases"
            body = """
            {"pagination":{"page":\(page),"pages":2,"per_page":1,"items":2},"\(key)":[\(item)]}
            """
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
