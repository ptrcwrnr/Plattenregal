import XCTest
import SwiftData
@testable import Plattenregal

@MainActor final class StatisticsTests: XCTestCase {
    private func value(_ median: Decimal = 100, currency: String = "EUR") throws -> DiscogsCollectionValue {
        try .init(minimum: .init(amount: median / 2, currency: currency), median: .init(amount: median, currency: currency), maximum: .init(amount: median * 2, currency: currency))
    }
    private func makeCopy(id: Int = 42, instance: Int = 1, year: Int? = 1998, date: String = "2026-09-20T12:00:00+02:00", genres: [String] = ["Electronic", "Pop", "Electronic"], styles: [String] = ["Trance", "Trance"]) throws -> RecordCopy {
        let release = Release(artist: "A & B", title: "Fixture")
        let basic = DiscogsBasicInformation(id: id, title: "Fixture", artists: [.init(id: 1, name: "A", join: "&"), .init(id: 2, name: "B", join: nil), .init(id: 1, name: "A", join: nil)], year: year,
            labels: [.init(id: 3, name: "Label", catno: nil), .init(id: 3, name: "Label", catno: nil)], formats: [.init(name: "Vinyl", qty: "2", descriptions: ["12\"", "EP", "EP"])], genres: genres, styles: styles, cover_image: nil, thumb: nil, resource_url: nil, master_id: 55)
        try basic.apply(to: release, at: .now)
        let copy = RecordCopy(release: release); copy.discogsInstanceID = instance; copy.discogsOwner = "fixture"; copy.discogsActive = true; copy.discogsDateAdded = date
        return copy
    }
    func testPreviousCalendarYearHighlightIncludesBoundariesAndExcludesUnknownDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dates: [String?] = ["2024-12-31T23:59:59Z", "2025-01-01T00:00:00Z",
                                "2025-12-31T23:59:59Z", "2026-01-01T00:00:00Z", nil]
        let copies = try dates.enumerated().map { index, date in
            let copy = try makeCopy(instance: index + 1)
            copy.discogsDateAdded = date
            return copy
        }
        let now = try XCTUnwrap(AnalyticsItem.date("2026-09-20T12:00:00Z"))
        let stats = CollectionAnalyticsService.calculate(copies.map(AnalyticsItem.init), now: now, calendar: calendar)
        XCTAssertTrue(stats.highlights.contains("Letztes Jahr hinzugefügt: 2 Exemplare"))
        XCTAssertTrue(stats.highlights.contains("Dieses Jahr hinzugefügt: 1 Exemplare"))
    }

    func testCollectionValueParsingAndGermanMoney() throws {
        let data = Data(#"{"minimum":"5.612,08 €","median":"€11,175.79","maximum":"EUR 23.995,70"}"#.utf8)
        let parsed = try JSONDecoder().decode(DiscogsCollectionValue.self, from: data)
        XCTAssertEqual(parsed.minimum.amount, Decimal(string: "5612.08"))
        XCTAssertEqual(parsed.median.amount, Decimal(string: "11175.79"))
        XCTAssertEqual(parsed.maximum.amount, Decimal(string: "23995.70"))
        XCTAssertEqual(parsed.median.currency, "EUR")
    }
    func testMoneyFormatsAndCurrencyPreservation() throws {
        for raw in ["1.234,56 €", "EUR 1,234.56", "1 234,56 EUR", "1\u{202F}234,56 €", "€1234.56"] {
            XCTAssertEqual(try DiscogsMoney.parse(raw).amount, Decimal(string: "1234.56"))
        }
        XCTAssertEqual(try DiscogsMoney.parse("CA$1,234.56").currency, "CAD")
        XCTAssertEqual(try DiscogsMoney.parse("£9.99").currency, "GBP")
        XCTAssertEqual(try DiscogsMoney.parse("€1.234").amount, 1234)
        XCTAssertEqual(try DiscogsMoney.parse("€0.00").amount, 0)
        XCTAssertThrowsError(try DiscogsMoney.parse("not available"))
        XCTAssertThrowsError(try DiscogsMoney.parse("€-12"))
        XCTAssertThrowsError(try DiscogsMoney.parse("€1.2.3"))
        XCTAssertEqual(try DiscogsMoney.parse("NZ$12.34").currency, "NZD")
        XCTAssertEqual(try DiscogsMoney.parse("US$12.34").currency, "USD")
        XCTAssertThrowsError(try DiscogsCollectionValue(minimum: .init(amount: 1, currency: "EUR"), median: .init(amount: 2, currency: "USD"), maximum: .init(amount: 3, currency: "EUR")))
    }
    func testLocalizedEURFormatting() {
        let formatted = DiscogsMoney.format(Decimal(string: "11175.79")!, currency: "EUR", locale: Locale(identifier: "de_DE"))
        XCTAssertTrue(formatted.contains("11.175,79")); XCTAssertTrue(formatted.contains("€"))
    }
    func testSnapshotPersistenceDailyDedupAndChangedCollection() throws {
        let context = ModelContext(try LibraryStorage.makeContainer(inMemory: true))
        let a = try makeCopy(); context.insert(a)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [a], context: context, date: date))
        XCTAssertFalse(try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [a], context: context, date: date.addingTimeInterval(1)))
        XCTAssertFalse(try CollectionValueHistoryService.store(value: value(Decimal(string: "100.10")!), owner: "fixture", copies: [a], context: context, date: date.addingTimeInterval(2)))
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionValueSnapshot>()).first?.medianValue, Decimal(string: "100.10"))
        XCTAssertTrue(try CollectionValueHistoryService.store(value: value(110), owner: "fixture", copies: [a], context: context, date: date.addingTimeInterval(3)))
        let b = try makeCopy(instance: 2); context.insert(b)
        XCTAssertTrue(try CollectionValueHistoryService.store(value: value(110), owner: "fixture", copies: [a, b], context: context, date: date.addingTimeInterval(4)))
        XCTAssertTrue(try CollectionValueHistoryService.store(value: value(110), owner: "fixture", copies: [a, b], context: context, date: date.addingTimeInterval(86400)))
        let stored = try ModelContext(context.container).fetch(FetchDescriptor<CollectionValueSnapshot>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(stored.count, 4); XCTAssertEqual(stored.last?.collectionItemCount, 2)
        XCTAssertEqual(stored.last?.uniqueReleaseCount, 1); XCTAssertEqual(stored.last?.averagePerItem, 55)
    }
    func testSnapshotReplacementSameCountAndCurrencyIsolation() throws {
        let context = ModelContext(try LibraryStorage.makeContainer(inMemory: true))
        let a = try makeCopy(), b = try makeCopy(id: 99, instance: 2); context.insert(a); context.insert(b)
        let date = Date()
        try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [a], context: context, date: date)
        XCTAssertTrue(try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [b], context: context, date: date))
        XCTAssertTrue(try CollectionValueHistoryService.store(value: value(currency: "USD"), owner: "fixture", copies: [b], context: context, date: date))
        XCTAssertTrue(try CollectionValueHistoryService.store(value: value(), owner: "other", copies: [b], context: context, date: date))
    }
    func testAverageWithoutItemsIsMissing() throws {
        let snapshot = CollectionValueSnapshot(owner: "x", date: .now, value: try value(), count: 0, unique: 0, signature: "")
        XCTAssertNil(snapshot.averagePerItem)
    }
    func testGenresMultiGenresStylesAndDuplicates() throws {
        let stats = CollectionAnalyticsService.calculate([try makeCopy(), try makeCopy(instance: 2)].map(AnalyticsItem.init))
        XCTAssertEqual(stats.totalItems, 2); XCTAssertEqual(stats.uniqueReleases, 1)
        XCTAssertEqual(stats.genres.count, 2); XCTAssertTrue(stats.genres.allSatisfy { $0.count == 2 })
        XCTAssertEqual(stats.styles.first?.name, "Trance"); XCTAssertEqual(stats.styles.first?.count, 2)
    }
    func testArtistLabelIdentityAndMultipleArtists() throws {
        let stats = CollectionAnalyticsService.calculate([AnalyticsItem(try makeCopy())])
        XCTAssertEqual(stats.artists.map(\.name), ["A", "B"])
        XCTAssertEqual(stats.artists.map(\.count), [1, 1]); XCTAssertEqual(stats.artists.first?.id, "artist:1")
        XCTAssertEqual(stats.labels.count, 1); XCTAssertEqual(stats.labels.first?.count, 1)
        XCTAssertEqual(stats.formats.count, 3)
    }
    func testYearsDecadesAndConcreteReissueYear() throws {
        let stats = CollectionAnalyticsService.calculate([try makeCopy(year: 1998), try makeCopy(id: 43, instance: 2, year: 2020)].map(AnalyticsItem.init))
        XCTAssertEqual(stats.years.map(\.id), ["1998", "2020"])
        XCTAssertEqual(stats.decades.map(\.id), ["1990er", "2020er"])
        XCTAssertEqual(stats.oldest, 1998); XCTAssertEqual(stats.newest, 2020)
    }
    func testOptionalUniqueReleaseMode() throws {
        let stats = CollectionAnalyticsService.calculate([try makeCopy(), try makeCopy(instance: 2)].map(AnalyticsItem.init), uniqueReleases: true)
        XCTAssertEqual(stats.totalItems, 1); XCTAssertEqual(stats.styles.first?.count, 1)
    }
    func testMissingMetadataAndInvalidDates() throws {
        let c = try makeCopy(year: nil, date: "unknown", genres: [], styles: [])
        let stats = CollectionAnalyticsService.calculate([AnalyticsItem(c)])
        XCTAssertTrue(stats.years.isEmpty); XCTAssertTrue(stats.genres.isEmpty); XCTAssertTrue(stats.styles.isEmpty)
        XCTAssertTrue(stats.recentlyAdded.isEmpty); XCTAssertEqual(stats.missingYear, 1)
        XCTAssertEqual(CollectionAnalyticsService.calculate([]).totalItems, 0)
    }
    func testLatestTenUseDiscogsDateAndCountInstances() throws {
        let copies = try (1...12).map { try makeCopy(instance: $0, date: String(format: "2026-09-%02dT12:00:00+02:00", $0)) }
        let stats = CollectionAnalyticsService.calculate(copies.map(AnalyticsItem.init))
        XCTAssertEqual(stats.recentlyAdded, Array(copies.reversed().prefix(10)).map(\.id))
        XCTAssertEqual(stats.months.first?.count, 12); XCTAssertEqual(stats.acquisitionYears.first?.count, 12)
    }
    func testHistoricalChangeAndZeroDenominator() {
        let change = CollectionValueHistoryService.change(current: 110, previous: 100)
        XCTAssertEqual(change.amount, 10); XCTAssertEqual(change.percent, 10)
        XCTAssertEqual(CollectionValueHistoryService.change(current: 90, previous: 100).percent, -10)
        XCTAssertNil(CollectionValueHistoryService.change(current: 10, previous: 0).percent)
    }
    func testTopTenUsesOnlyComparablePricesAndUniqueReleases() throws {
        let copies = try (1...12).map { try makeCopy(id: $0, instance: $0) }
        let prices = (1...12).map { ReleaseMarketValue(owner: "fixture", releaseID: $0, value: Decimal($0), currency: "EUR", condition: "Very Good Plus (VG+)", source: "priceSuggestion") }
        let wrong = ReleaseMarketValue(owner: "fixture", releaseID: 1, value: 9999, currency: "USD", condition: "Mint (M)", source: "priceSuggestion")
        let lowest = ReleaseMarketValue(owner: "fixture", releaseID: 1, value: 8888, currency: "EUR", condition: "", source: "marketplaceLowestPrice")
        let top = MarketRanking.top(copies: copies + [copies[0]], prices: prices + [wrong, lowest], owner: "fixture", source: .priceSuggestion, currency: "EUR", condition: "Very Good Plus (VG+)")
        XCTAssertEqual(top.count, 10); XCTAssertEqual(top.map(\.id), Array((3...12).reversed()))
    }
    func testPriceSuggestionFallbackAndNegativeCacheAge() {
        let prices: [String: DiscogsPrice] = ["Very Good (VG)": .init(value: 10, currency: "EUR"), "Mint (M)": .init(value: 100, currency: "EUR")]
        XCTAssertEqual(MarketValueService.suggested(prices)?.0, "Very Good (VG)")
        XCTAssertNil(MarketValueService.suggested([:]))
        let missing = ReleaseMarketValue(owner: "fixture", releaseID: 42, value: nil, currency: "", condition: "", source: "priceSuggestion")
        XCTAssertFalse(missing.stale); missing.updatedAt = .now.addingTimeInterval(-8 * 86400); XCTAssertTrue(missing.stale)
    }
    func testAnalyticsDoesNotRequestNetworkAndHandlesThousands() throws {
        let items = try (1...2000).map { try makeCopy(id: $0 % 100 + 1, instance: $0) }.map(AnalyticsItem.init)
        StatisticsURLProtocol.log.clear()
        let stats = CollectionAnalyticsService.calculate(items)
        XCTAssertEqual(stats.totalItems, 2000); XCTAssertEqual(stats.uniqueReleases, 100)
        XCTAssertTrue(StatisticsURLProtocol.log.paths.isEmpty)
    }
    private func api() -> DiscogsAPIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StatisticsURLProtocol.self]
        return DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "fixture-token" })
    }
    private func authenticatedContainer(_ api: DiscogsAPIClient) async throws -> ModelContainer {
        let container = try LibraryStorage.makeContainer(inMemory: true)
        let account = DiscogsAccount(username: "fixture"); account.lastCollectionSync = .now
        account.credentialFingerprint = try await api.credentialFingerprint(); container.mainContext.insert(account)
        container.mainContext.insert(try makeCopy()); try container.mainContext.save()
        return container
    }
    func testCollectionValueAPIAndDailyOpenDoesNotRepeatRequest() async throws {
        let api = api(), container = try await authenticatedContainer(api)
        StatisticsURLProtocol.log.clear()
        let history = CollectionValueHistoryService()
        try await history.refresh(owner: "fixture", container: container, api: api)
        try await history.refresh(owner: "fixture", container: container, api: api)
        XCTAssertEqual(StatisticsURLProtocol.log.paths, ["/users/fixture/collection/value"])
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<CollectionValueSnapshot>()), 1)
    }
    func testPriceCacheReuseAndSeparateMarketplaceEndpoint() async throws {
        let api = api(), container = try await authenticatedContainer(api)
        let service = MarketValueService(); StatisticsURLProtocol.log.clear()
        service.start(owner: "fixture", releaseIDs: [42, 42], source: .priceSuggestion, force: false, container: container, api: api)
        while service.busy { try await Task.sleep(for: .milliseconds(10)) }
        service.start(owner: "fixture", releaseIDs: [42], source: .priceSuggestion, force: false, container: container, api: api)
        while service.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(StatisticsURLProtocol.log.paths, ["/marketplace/price_suggestions/42"])
        service.start(owner: "fixture", releaseIDs: [42], source: .marketplaceLowestPrice, force: false, container: container, api: api)
        while service.busy { try await Task.sleep(for: .milliseconds(10)) }
        let rows = try ModelContext(container).fetch(FetchDescriptor<ReleaseMarketValue>())
        XCTAssertEqual(rows.count, 2); XCTAssertEqual(Set(rows.map(\.source)), ["priceSuggestion", "marketplaceLowestPrice"])
    }
    func testMarketCancellationPreservesCompletedCache() async throws {
        let api = api(), container = try await authenticatedContainer(api)
        let service = MarketValueService()
        service.start(owner: "fixture", releaseIDs: [42, 43, 44], source: .priceSuggestion, force: false, container: container, api: api)
        while service.completed == 0 && service.busy { try await Task.sleep(for: .milliseconds(10)) }
        service.cancel()
        while service.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ReleaseMarketValue>()), 1)
        XCTAssertTrue(service.message?.contains("Abgebrochen") == true)
    }
    func testSyncRefreshesValueAfterCommit() async throws {
        let api = api(), container = try await authenticatedContainer(api)
        StatisticsURLProtocol.log.clear()
        let sync = DiscogsSyncService(api: api)
        sync.start(.collection, container: container)
        while sync.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(sync.error)
        XCTAssertTrue(StatisticsURLProtocol.log.paths.contains("/users/fixture/collection/value"))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<CollectionValueSnapshot>()), 1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<RecordCopy>()).first?.discogsActive, true)
    }
    func testUnauthorizedPricesDoNotCacheInventedValues() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StatisticsURLProtocol.self]
        let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "denied" })
        let container = try await authenticatedContainer(api)
        let service = MarketValueService()
        service.start(owner: "fixture", releaseIDs: [42], source: .priceSuggestion, force: false, container: container, api: api)
        while service.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<ReleaseMarketValue>()), 0)
        XCTAssertNotNil(service.message)
    }
    func testUnavailableValueDoesNotRollBackSuccessfulSync() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StatisticsURLProtocol.self]
        let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "denied-value" })
        let container = try await authenticatedContainer(api)
        let sync = DiscogsSyncService(api: api)
        sync.start(.collection, container: container)
        while sync.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(sync.error?.contains("Sammlung gespeichert") == true)
        XCTAssertNotNil(sync.summary)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<CollectionValueSnapshot>()), 0)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<RecordCopy>()).first?.discogsActive, true)
    }
    func testV2ToV6MigrationPreservesCollectionKallaxWantlistAndAccounts() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Migration.store")
        let id: UUID = try autoreleasepool {
            let schema = Schema(versionedSchema: LibrarySchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let release = LibrarySchemaV2.Release(artist: "A & B", title: "Fixture"); release.discogsID = 42
            let shelf = LibrarySchemaV2.Shelf(number: 7)
            let c = LibrarySchemaV2.RecordCopy(release: release, shelf: shelf, position: 23)
            c.notes = "LOCAL"; c.purchasePrice = Decimal(string: "23.45")
            c.discogsInstanceID = 1; c.discogsOwner = "fixture"; c.discogsActive = true
            container.mainContext.insert(c)
            container.mainContext.insert(LibrarySchemaV2.WantlistEntry(owner: "fixture", release: release, releaseID: 42))
            container.mainContext.insert(DiscogsAccount(username: "fixture"))
            container.mainContext.insert(DiscogsFolder(owner: "fixture", id: 1, name: "Folder", count: 1))
            try container.mainContext.save(); return c.id
        }
        let schema = Schema(versionedSchema: LibrarySchemaV6.self)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = container.mainContext
        let c = try XCTUnwrap(context.fetch(FetchDescriptor<RecordCopy>()).first)
        XCTAssertEqual(c.id, id); XCTAssertEqual(c.positionInShelf, 23); XCTAssertEqual(c.shelf?.number, 7)
        XCTAssertEqual(c.notes, "LOCAL"); XCTAssertEqual(c.purchasePrice, Decimal(string: "23.45"))
        XCTAssertEqual(c.discogsInstanceID, 1); XCTAssertEqual(c.discogsOwner, "fixture")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WantlistEntry>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DiscogsAccount>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DiscogsFolder>()), 1)
        try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [c], context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionValueSnapshot>()), 1)
    }
    func testV3ToV6MigrationAddsOptimizationExclusionSchemaWithoutDataLoss() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Migration.store")
        let copyID: UUID = try autoreleasepool {
            let schema = Schema(versionedSchema: LibrarySchemaV3.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: config)
            let release = LibrarySchemaV2.Release(artist: "A & B", title: "Fixture")
            let copy = LibrarySchemaV2.RecordCopy(release: release, shelf: LibrarySchemaV2.Shelf(number: 4), position: 12)
            copy.notes = "BLEIBT"
            container.mainContext.insert(copy)
            container.mainContext.insert(CollectionValueSnapshot(owner: "fixture", date: .now, value: try value(), count: 1, unique: 1, signature: "seed"))
            try container.mainContext.save()
            return copy.id
        }
        let schema = Schema(versionedSchema: LibrarySchemaV6.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
        let context = container.mainContext
        let copy = try XCTUnwrap(context.fetch(FetchDescriptor<RecordCopy>()).first)
        XCTAssertEqual(copy.id, copyID); XCTAssertEqual(copy.shelf?.number, 4); XCTAssertEqual(copy.positionInShelf, 12); XCTAssertEqual(copy.notes, "BLEIBT")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CollectionValueSnapshot>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<OptimizationExclusion>()), 0)
        context.insert(OptimizationExclusion(copyID: copyID))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<OptimizationExclusion>()).first?.copyID, copyID)
    }
    func testV4ToV6MigrationKeepsLegacyShelfNameAsInfoText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Migration.store")
        let shelfID: UUID = try autoreleasepool {
            let schema = Schema(versionedSchema: LibrarySchemaV4.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: config)
            let shelf = LibrarySchemaV2.Shelf(number: 9)
            shelf.name = "A-B"
            container.mainContext.insert(shelf)
            try container.mainContext.save()
            return shelf.id
        }

        let schema = Schema(versionedSchema: LibrarySchemaV6.self)
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
        try LibraryStorage.prepareShelves(in: container.mainContext)

        let shelf = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Shelf>()).first { $0.id == shelfID })
        let customization = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<ShelfCustomization>()).first { $0.shelfID == shelfID }
        )
        XCTAssertEqual(shelf.title, "Fach 9")
        XCTAssertEqual(customization.infoText, "A-B")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Shelf>()), ShelfGeometry.count)
    }
}
final class StatisticsRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return entries }
    func append(_ path: String) { lock.lock(); defer { lock.unlock() }; entries.append(path) }
    func clear() { lock.lock(); defer { lock.unlock() }; entries.removeAll() }
}
final class StatisticsURLProtocol: URLProtocol, @unchecked Sendable {
    static let log = StatisticsRequestLog()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!; Self.log.append(url.path)
        let body: String
        if url.path.hasSuffix("/folders") { body = #"{"folders":[{"id":1,"name":"All","count":1}]}"# }
        else if url.path.contains("/collection/folders/") { body = #"{"pagination":{"page":1,"pages":1,"per_page":100,"items":1},"releases":[{"id":42,"instance_id":1,"folder_id":1,"date_added":"2026-09-20T12:00:00+02:00","rating":0,"basic_information":{"id":42,"title":"Synced","artists":[]}}]}"# }
        else if url.path.hasSuffix("/value") { body = #"{"minimum":"€50.00","median":"€100.00","maximum":"€200.00"}"# }
        else if url.path.contains("price_suggestions") { body = #"{"Very Good Plus (VG+)":{"value":24.72,"currency":"EUR"}}"# }
        else { body = #"{"lowest_price":{"value":12.34,"currency":"EUR"}}"# }
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let status = token == "Discogs token=denied" || (token == "Discogs token=denied-value" && url.path.hasSuffix("/value")) ? 403 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
