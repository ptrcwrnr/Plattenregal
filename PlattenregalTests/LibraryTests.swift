import XCTest
import SwiftData
@testable import Plattenregal

@MainActor final class LibraryTests: XCTestCase {
    private func fixture() throws -> (ModelContainer, [Shelf], PositionService) {
        let container = try LibraryStorage.makeContainer(inMemory: true)
        let shelves = try container.mainContext.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
        return (container, shelves, PositionService(context: container.mainContext))
    }
    @discardableResult private func add(_ service: PositionService, _ shelf: Shelf, _ artist: String, _ title: String = "Album", at position: Int? = nil) throws -> RecordCopy {
        try service.insert(release: Release(artist: artist, title: title), shelf: shelf, position: position ?? shelf.copies.count + 1)
    }
    func testShelfGeometry() throws {
        let (container, shelves, _) = try fixture(); _ = container
        XCTAssertEqual(shelves.count, 12)
        XCTAssertEqual(shelves.map(\.number), Array(1...12))
        XCTAssertEqual(shelves[4].row, 2); XCTAssertEqual(shelves[4].column, 1)
        XCTAssertEqual(shelves[11].row, 3); XCTAssertEqual(shelves[11].column, 4)
    }
    func testInsertionBetweenCopies() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "A")
        let c = try add(service, shelves[0], "C")
        let b = try add(service, shelves[0], "B", at: 2)
        XCTAssertEqual(service.ordered(shelves[0]).map(\.id), [a.id, b.id, c.id])
        XCTAssertEqual(service.ordered(shelves[0]).map(\.positionInShelf), [1, 2, 3])
    }
    func testMoveWithinAndAcrossShelves() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B")
        let c = try add(service, shelves[0], "C")
        try service.move(c, to: shelves[0], position: 1)
        XCTAssertEqual(service.ordered(shelves[0]).map(\.id), [c.id, a.id, b.id])
        try service.move(a, to: shelves[1], position: 1)
        XCTAssertEqual(service.ordered(shelves[0]).map(\.positionInShelf), [1, 2])
        XCTAssertEqual(service.ordered(shelves[1]).map(\.id), [a.id])
        XCTAssertEqual(a.location, "Fach 2 · Position 1")
    }
    func testAssignedCopyDoesNotReappearInShelfAssignment() throws {
        let (container, shelves, service) = try fixture()
        let assigned = try add(service, shelves[0], "Already There")
        let available = try add(service, shelves[1], "Still Available")

        XCTAssertEqual(
            ShelfAssignmentPresentation.availableCopies(
                [assigned, available],
                for: shelves[0],
                matching: ""
            ).map(\.id),
            [available.id]
        )

        let secondContext = ModelContext(container)
        let restoredShelves = try secondContext.fetch(
            FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)])
        )
        let restoredCopies = try secondContext.fetch(FetchDescriptor<RecordCopy>())
        XCTAssertFalse(
            ShelfAssignmentPresentation.availableCopies(
                restoredCopies,
                for: restoredShelves[0],
                matching: ""
            ).contains { $0.id == assigned.id }
        )
    }
    func testBulkAssignmentIsOrderedAndAtomic() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B")
        let fixed = try add(service, shelves[1], "Fixed")

        try service.assign([b, a], to: shelves[2])
        XCTAssertEqual(service.ordered(shelves[2]).map(\.id), [b.id, a.id])
        XCTAssertTrue(service.ordered(shelves[0]).isEmpty)
        XCTAssertEqual(service.ordered(shelves[1]).map(\.id), [fixed.id])

        try service.configure(shelves[3], title: "Klein", infoText: "", capacity: 1)
        XCTAssertThrowsError(try service.assign([a, b], to: shelves[3]))
        XCTAssertEqual(service.ordered(shelves[2]).map(\.id), [b.id, a.id])
        XCTAssertTrue(service.ordered(shelves[3]).isEmpty)
    }
    func testCapacityAndInvalidPositionDoNotMutate() throws {
        let (container, shelves, service) = try fixture(); _ = container
        try service.configure(shelves[0], title: "", infoText: "", capacity: 1)
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[1], "B")
        XCTAssertThrowsError(try service.move(b, to: shelves[0], position: 1))
        XCTAssertEqual(b.shelf?.id, shelves[1].id)
        XCTAssertThrowsError(try add(service, shelves[0], "C"))
        XCTAssertThrowsError(try service.move(a, to: shelves[1], position: 5))
        XCTAssertEqual(a.positionInShelf, 1)
        // Reordering a full shelf is valid because the moving copy is excluded from capacity.
        try service.move(a, to: shelves[0], position: 1)
        XCTAssertThrowsError(try service.configure(shelves[1], title: "", infoText: "", capacity: 0))
    }
    func testShelfTitleAndInfoAreStoredSeparately() throws {
        let (container, shelves, service) = try fixture()
        let shelf = shelves[8]

        try service.configure(shelf, title: "Drum & Bass", infoText: "A–B · Lieblingsplatten", capacity: 95)

        XCTAssertEqual(shelf.title, "Drum & Bass")
        XCTAssertEqual(shelf.capacity, 95)
        let customization = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ShelfCustomization>()).first { $0.shelfID == shelf.id }
        )
        XCTAssertEqual(customization.infoText, "A–B · Lieblingsplatten")
    }
    func testDeletionCompactsAndPreservesOtherCopyOfRelease() throws {
        let (container, shelves, service) = try fixture()
        let a = try add(service, shelves[0], "A")
        let release = try XCTUnwrap(a.release)
        let b = try service.insert(release: release, shelf: shelves[0], position: 2)
        try service.delete(a)
        XCTAssertEqual(b.positionInShelf, 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Release>()), 1)
        try service.delete(b)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Release>()), 0)
    }
    func testAlphabeticalSortAndSearchAcrossWords() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let z = try add(service, shelves[0], "ZZ Top")
        let k = try add(service, shelves[0], "kraftwerk", "Computerwelt")
        let d = try add(service, shelves[0], "Depeche Mode", "Violator")
        XCTAssertEqual(SortingService.sorted([z, k, d], by: .artistAZ).map(\.id), [d.id, k.id, z.id])
        XCTAssertEqual(SortingService.sorted([z, k, d], by: .artistZA).map(\.id), [z.id, k.id, d.id])
        XCTAssertTrue(SortingService.matches(d, query: "depeche violator"))
        XCTAssertFalse(SortingService.matches(k, query: "violator"))
        try service.sort(shelves[0], by: .artistAZ)
        XCTAssertEqual(service.ordered(shelves[0]).map(\.id), [d.id, k.id, z.id])
    }
    func testAlphabetNavigationNormalizesArtistsAndGroupsNonLetters() {
        XCTAssertEqual(SortingService.alphabetNavigationSymbols.first, "#")
        XCTAssertEqual(SortingService.alphabetNavigationSymbols.count, 27)
        XCTAssertEqual(SortingService.alphabetSection(for: "  Ätna"), "A")
        XCTAssertEqual(SortingService.alphabetSection(for: "kraftwerk"), "K")
        XCTAssertEqual(SortingService.alphabetSection(for: "4 Strings"), "#")
        XCTAssertEqual(SortingService.alphabetSection(for: ""), "#")
    }
    func testDiscogsMappingWithOptionalFields() throws {
        let data = Data(#"{"id":123,"title":"Computerwelt","year":1981,"artists":[{"name":"Kraftwerk (2)","anv":"Kraftwerk"}],"labels":[{"name":"EMI","catno":"1C 064"}],"formats":[{"name":"Vinyl","qty":"1","descriptions":["LP"]}],"genres":["Electronic"],"tracklist":[{"position":"A1","title":"Computerwelt","duration":"5:05"}],"images":[{"type":"primary","uri":"https://example.com/cover.jpg"}]}"#.utf8)
        let release = try JSONDecoder().decode(DiscogsReleaseDTO.self, from: data).mappedRelease()
        XCTAssertEqual(release.artist, "Kraftwerk"); XCTAssertEqual(release.discogsID, 123)
        XCTAssertEqual(release.catalogNumber, "1C 064"); XCTAssertEqual(release.tracks.count, 1)
        XCTAssertEqual(release.format, "1 · Vinyl · LP"); XCTAssertTrue(release.isFresh)
        let minimal = try JSONDecoder().decode(DiscogsReleaseDTO.self, from: Data(#"{"id":1,"title":"Untitled","year":0}"#.utf8)).mappedRelease()
        XCTAssertNil(minimal.year); XCTAssertTrue(minimal.tracks.isEmpty)
        XCTAssertEqual(minimal.artist, "Unbekannter Interpret")
        release.fetchedAt = Date().addingTimeInterval(-21601)
        XCTAssertFalse(release.isFresh)
        XCTAssertEqual(release.displayArtist, "Kraftwerk")
        XCTAssertEqual(release.displayTitle, "Computerwelt")
        XCTAssertEqual(release.coverURL, "https://example.com/cover.jpg")
    }
    func testPositionsSurviveReload() throws {
        let (container, shelves, service) = try fixture()
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B", at: 1)
        let secondContext = ModelContext(container)
        let restored = try secondContext.fetch(FetchDescriptor<RecordCopy>(sortBy: [SortDescriptor(\RecordCopy.positionInShelf)]))
        XCTAssertEqual(restored.map(\.id), [b.id, a.id])
        XCTAssertEqual(restored.map(\.positionInShelf), [1, 2])
    }
    func testRollbackRestoresPositionsAndMetadata() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "A")
        XCTAssertThrowsError(try service.save {
            a.positionInShelf = 99; a.notes = "should not persist"
            throw LibraryError.invalidPosition
        })
        XCTAssertEqual(a.positionInShelf, 1)
        XCTAssertEqual(a.notes, "")
    }
    func testNormalizationAndPlacementSuggestion() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B")
        try service.save { a.positionInShelf = 7; b.positionInShelf = 12 }
        try service.normalize(shelves[0])
        XCTAssertEqual(service.ordered(shelves[0]).map(\.positionInShelf), [1, 2])
        try service.configure(shelves[0], title: "Voll", infoText: "", capacity: 2)
        let suggestion = FirstAvailablePlacement().suggest(for: try XCTUnwrap(a.release), shelves: shelves)
        XCTAssertEqual(suggestion?.shelfNumber, 2)
        XCTAssertEqual(suggestion?.position, 1)
    }
    func testPersistentStoreCanBeReopened() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: LibrarySchemaV6.self)
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Test.store"), cloudKitDatabase: .none)
        let id: UUID = try autoreleasepool {
            let first = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
            let shelf = Shelf(number: 4); first.mainContext.insert(shelf)
            let copy = try PositionService(context: first.mainContext).insert(release: Release(artist: "Kraftwerk", title: "Computerwelt"), shelf: shelf, position: 1)
            return copy.id
        }
        let reopened = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
        let copies = try reopened.mainContext.fetch(FetchDescriptor<RecordCopy>())
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(copies.first?.id, id)
        XCTAssertEqual(copies.first?.location, "Fach 4 · Position 1")
    }

}


final class DiscogsStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let code = Int(url.lastPathComponent) ?? 200
        if code == 901 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let status = [401, 429, 500].contains(code) ? code : 200
        var body = #"{"id":1,"title":"Test"}"#
        if code == 900 { body = "not json" }
        if url.path == "/database/search" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard query.contains(URLQueryItem(name: "type", value: "release")),
                  query.contains(URLQueryItem(name: "format", value: "Vinyl")),
                  request.value(forHTTPHeaderField: "Authorization") == "Discogs token=fixture" else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
            }
            body = #"{"pagination":{"page":1,"pages":1},"results":[{"id":42,"title":"Artist - Title","type":"release"}]}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "1"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@MainActor final class DiscogsClientTests: XCTestCase {
    private func client(token: String? = "fixture") -> DiscogsAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiscogsStubProtocol.self]
        return DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { token })
    }
    func testSearchRequestsConcreteVinylReleases() async throws {
        let result = try await client().search("Artist Title")
        XCTAssertEqual(result.results.first?.id, 42)
        XCTAssertEqual(result.results.first?.type, "release")
    }
    func testMissingToken() async {
        do { _ = try await client(token: nil).release(id: 1); XCTFail("Expected missing token") }
        catch DiscogsError.missingToken {} catch { XCTFail("Unexpected: \(error)") }
    }
    func testUnauthorized() async {
        do { _ = try await client().release(id: 401); XCTFail("Expected unauthorized") }
        catch DiscogsError.unauthorized {} catch { XCTFail("Unexpected: \(error)") }
    }
    func testRateLimit() async {
        do { _ = try await client().release(id: 429); XCTFail("Expected rate limit") }
        catch DiscogsError.rateLimited(let seconds) { XCTAssertEqual(seconds, 1) }
        catch { XCTFail("Unexpected: \(error)") }
    }
    func testHTTPError() async {
        do { _ = try await client().release(id: 500); XCTFail("Expected HTTP failure") }
        catch DiscogsError.http(let code) { XCTAssertEqual(code, 500) }
        catch { XCTFail("Unexpected: \(error)") }
    }
    func testInvalidResponse() async {
        do { _ = try await client().release(id: 900); XCTFail("Expected invalid JSON") }
        catch DiscogsError.invalidResponse {} catch { XCTFail("Unexpected: \(error)") }
    }
    func testOffline() async {
        do { _ = try await client().release(id: 901); XCTFail("Expected offline") }
        catch DiscogsError.offline {} catch { XCTFail("Unexpected: \(error)") }
    }
}
