import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests {
    struct StatisticsTests {
        private func value(_ median: Decimal = 100, currency: String = "EUR") throws -> DiscogsCollectionValue {
            try .init(minimum: .init(amount: median / 2, currency: currency), median: .init(amount: median, currency: currency), maximum: .init(amount: median * 2, currency: currency))
        }
        private func makeCopy(id: Int = 42, instance: Int = 1, year: Int? = 1998, date: String = "2026-09-20T12:00:00+02:00", genres: [String] = ["Electronic", "Pop", "Electronic"], styles: [String] = ["Trance", "Trance"]) throws -> RecordCopy {
            let release = Release(artist: "A & B", title: "Fixture")
            let basic = DiscogsBasicInformation(id: id, title: "Fixture", artists: [.init(id: 1, name: "A", join: "&"), .init(id: 2, name: "B", join: nil), .init(id: 1, name: "A", join: nil)], year: year,
                labels: [.init(id: 3, name: "Label", catno: nil), .init(id: 3, name: "Label", catno: nil)], formats: [.init(name: "Vinyl", qty: "2", descriptions: ["12\"", "EP", "EP"])], genres: genres, styles: styles, cover_image: nil, thumb: nil, resource_url: nil, master_id: 55)
            try basic.apply(to: release, at: .now)
            let copy = RecordCopy(release: release, instanceID: instance, owner: "fixture"); copy.discogsDateAdded = date
            return copy
        }
        @Test func implausibleYearsCountAsUnknown() {
            #expect(AnalyticsItem.plausibleYear(1997) == 1997)
            #expect(AnalyticsItem.plausibleYear(1877) == 1877)
            #expect(AnalyticsItem.plausibleYear(197) == nil)
            #expect(AnalyticsItem.plausibleYear(20015) == nil)
            #expect(AnalyticsItem.plausibleYear(Calendar.current.component(.year, from: .now) + 1) != nil)
        }
        @Test func artistsGroupUnderTheirCanonicalName() throws {
            func copy(anv: String?, instance: Int) throws -> RecordCopy {
                let release = Release(artist: "", title: "Fixture")
                let basic = DiscogsBasicInformation(id: 40 + instance, title: "Fixture", artists: [.init(id: 4711, name: "Joris Biesmans", anv: anv, join: nil)], year: 2021,
                    labels: nil, formats: nil, genres: nil, styles: nil, cover_image: nil, thumb: nil, resource_url: nil, master_id: nil)
                try basic.apply(to: release, at: .now)
                let copy = RecordCopy(release: release, instanceID: instance, owner: "fixture")
                return copy
            }
            // Whichever copy comes first, the group carries the canonical name.
            for order in [[nil, "Biesmans"], ["Biesmans", nil]] {
                let copies = try order.enumerated().map { try copy(anv: $1, instance: $0 + 1) }
                let artists = CollectionAnalyticsService.calculate(copies.map(AnalyticsItem.init)).artists
                #expect(artists.map(\.name) == ["Joris Biesmans"])
                #expect(artists.first?.count == 2)
            }
        }
        @Test func legacyArtistsJoinTheirDiscogsGroup() throws {
            let id = UUID(), legacyID = UUID(), otherID = UUID()
            let groups = CollectionAnalyticsService.mergingLegacy([
                StatisticGroup(id: "artist:1", name: "Moby", copyIDs: [id]),
                StatisticGroup(id: "legacy:moby", name: "moby", copyIDs: [legacyID]),
                StatisticGroup(id: "legacy:Unbekannt", name: "Unbekannt", copyIDs: [otherID]),
            ])
            #expect(groups.map(\.id) == ["artist:1", "legacy:Unbekannt"])
            #expect(groups[0].copyIDs == [id, legacyID])
        }
        @Test func missingValuesAreCountedPerDimension() throws {
            let full = try makeCopy(instance: 1)
            full.release?.country = "Germany"
            let empty = try makeCopy(instance: 2, genres: [], styles: [])
            let stats = CollectionAnalyticsService.calculate([full, empty].map(AnalyticsItem.init))
            #expect(stats.missingGenre == 1)
            #expect(stats.missingStyle == 1)
            #expect(stats.missingCountry == 1)
            #expect(stats.missingFormatDetail == 0)
        }
        @Test func layoutSpanIsNeverNegative() {
            #expect(StatisticsLayout.span(2, of: 5, in: 0) == 0)
            #expect(StatisticsLayout.span(2, of: 5, in: 1000) > 0)
        }
        @Test func additionsThisYearCompareWithSameStretchLastYear() throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let now = try #require(ISO8601DateFormatter().date(from: "2026-03-01T12:00:00Z"))
            let dates = ["2026-01-10T00:00:00Z", "2026-02-20T00:00:00Z",   // this year so far
                         "2025-02-01T00:00:00Z",                           // same stretch last year
                         "2025-06-01T00:00:00Z", "2025-12-24T00:00:00Z",   // later last year
                         "2026-05-01T00:00:00Z"]                           // after "now"
            let copies = try dates.enumerated().map { index, date in
                let copy = try makeCopy(instance: index + 1); copy.discogsDateAdded = date; return copy
            }
            let stats = CollectionAnalyticsService.calculate(copies.map(AnalyticsItem.init), calendar: calendar, now: now)
            #expect(stats.addedThisYear == 2)
            #expect(stats.addedLastYearToDate == 1)
        }
        @Test func acquisitionYearsIncludeBoundariesAndExcludeUnknownDates() throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let dates: [String?] = ["2024-12-31T23:59:59Z", "2025-01-01T00:00:00Z",
                                    "2025-12-31T23:59:59Z", "2026-01-01T00:00:00Z", nil]
            let copies = try dates.enumerated().map { index, date in
                let copy = try makeCopy(instance: index + 1)
                copy.discogsDateAdded = date
                return copy
            }
            let stats = CollectionAnalyticsService.calculate(copies.map(AnalyticsItem.init), calendar: calendar)
            let perYear = Dictionary(uniqueKeysWithValues: stats.acquisitionYears.map { (calendar.component(.year, from: $0.date), $0.count) })
            #expect(perYear == [2024: 1, 2025: 2, 2026: 1])
        }

        @Test func collectionValueParsingAndGermanMoney() throws {
            let data = Data(#"{"minimum":"5.612,08 €","median":"€11,175.79","maximum":"EUR 23.995,70"}"#.utf8)
            let parsed = try JSONDecoder().decode(DiscogsCollectionValue.self, from: data)
            #expect(parsed.minimum.amount == Decimal(string: "5612.08"))
            #expect(parsed.median.amount == Decimal(string: "11175.79"))
            #expect(parsed.maximum.amount == Decimal(string: "23995.70"))
            #expect(parsed.median.currency == "EUR")
        }
        @Test func moneyFormatsAndCurrencyPreservation() throws {
            for raw in ["1.234,56 €", "EUR 1,234.56", "1 234,56 EUR", "1\u{202F}234,56 €", "€1234.56"] {
                #expect(try DiscogsMoney.parse(raw).amount == Decimal(string: "1234.56"))
            }
            #expect(try DiscogsMoney.parse("CA$1,234.56").currency == "CAD")
            #expect(try DiscogsMoney.parse("£9.99").currency == "GBP")
            #expect(try DiscogsMoney.parse("€1.234").amount == 1234)
            #expect(try DiscogsMoney.parse("€0.00").amount == 0)
            #expect(throws: (any Error).self) { try DiscogsMoney.parse("not available") }
            #expect(throws: (any Error).self) { try DiscogsMoney.parse("€-12") }
            #expect(throws: (any Error).self) { try DiscogsMoney.parse("€1.2.3") }
            #expect(try DiscogsMoney.parse("NZ$12.34").currency == "NZD")
            #expect(try DiscogsMoney.parse("US$12.34").currency == "USD")
            #expect(throws: (any Error).self) { try DiscogsCollectionValue(minimum: .init(amount: 1, currency: "EUR"), median: .init(amount: 2, currency: "USD"), maximum: .init(amount: 3, currency: "EUR")) }
        }
        @Test func localizedEURFormatting() {
            let formatted = DiscogsMoney.format(Decimal(string: "11175.79")!, currency: "EUR", locale: Locale(identifier: "de_DE"))
            #expect(formatted.contains("11.175,79")); #expect(formatted.contains("€"))
        }
        @Test func snapshotPersistenceDailyDedupAndChangedCollection() throws {
            let context = ModelContext(try LibraryStorage.makeContainer(inMemory: true))
            let a = try makeCopy(); context.insert(a)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            #expect(try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [a], context: context, date: date))
            #expect(!(try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [a], context: context, date: date.addingTimeInterval(1))))
            #expect(!(try CollectionValueHistoryService.store(value: value(Decimal(string: "100.10")!), owner: "fixture", copies: [a], context: context, date: date.addingTimeInterval(2))))
            #expect(try context.fetch(FetchDescriptor<CollectionValueSnapshot>()).first?.medianValue == Decimal(string: "100.10"))
            #expect(try CollectionValueHistoryService.store(value: value(110), owner: "fixture", copies: [a], context: context, date: date.addingTimeInterval(3)))
            let b = try makeCopy(instance: 2); context.insert(b)
            #expect(try CollectionValueHistoryService.store(value: value(110), owner: "fixture", copies: [a, b], context: context, date: date.addingTimeInterval(4)))
            #expect(try CollectionValueHistoryService.store(value: value(110), owner: "fixture", copies: [a, b], context: context, date: date.addingTimeInterval(86400)))
            let stored = try ModelContext(context.container).fetch(FetchDescriptor<CollectionValueSnapshot>(sortBy: [SortDescriptor(\.date)]))
            #expect(stored.count == 4); #expect(stored.last?.collectionItemCount == 2)
            #expect(stored.last?.uniqueReleaseCount == 1); #expect(stored.last?.averagePerItem == 55)
        }
        @Test func snapshotReplacementSameCountAndCurrencyIsolation() throws {
            let context = ModelContext(try LibraryStorage.makeContainer(inMemory: true))
            let a = try makeCopy(), b = try makeCopy(id: 99, instance: 2); context.insert(a); context.insert(b)
            let date = Date()
            try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [a], context: context, date: date)
            #expect(try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [b], context: context, date: date))
            #expect(try CollectionValueHistoryService.store(value: value(currency: "USD"), owner: "fixture", copies: [b], context: context, date: date))
            #expect(try CollectionValueHistoryService.store(value: value(), owner: "other", copies: [b], context: context, date: date))
        }
        @Test func averageWithoutItemsIsMissing() throws {
            let snapshot = CollectionValueSnapshot(owner: "x", date: .now, value: try value(), count: 0, unique: 0, signature: "")
            #expect(snapshot.averagePerItem == nil)
        }
        @Test func genresMultiGenresStylesAndDuplicates() throws {
            let stats = CollectionAnalyticsService.calculate([try makeCopy(), try makeCopy(instance: 2)].map(AnalyticsItem.init))
            #expect(stats.totalItems == 2); #expect(stats.uniqueReleases == 1)
            #expect(stats.genres.count == 2); #expect(stats.genres.allSatisfy { $0.count == 2 })
            #expect(stats.styles.first?.name == "Trance"); #expect(stats.styles.first?.count == 2)
        }
        @Test func artistLabelIdentityAndMultipleArtists() throws {
            let stats = CollectionAnalyticsService.calculate([AnalyticsItem(try makeCopy())])
            #expect(stats.artists.map(\.name) == ["A", "B"])
            #expect(stats.artists.map(\.count) == [1, 1]); #expect(stats.artists.first?.id == "artist:1")
            #expect(stats.labels.count == 1); #expect(stats.labels.first?.count == 1)
            #expect(stats.formats.count == 3)
        }
        @Test func variousArtistsIsNotCountedAsArtist() throws {
            func compilation(instance: Int) throws -> RecordCopy {
                let release = Release(artist: "Various", title: "Compilation")
                let basic = DiscogsBasicInformation(id: 100 + instance, title: "Compilation", artists: [.init(id: 194, name: "Various", join: nil)], year: 2001,
                    labels: nil, formats: nil, genres: nil, styles: nil, cover_image: nil, thumb: nil, resource_url: nil, master_id: nil)
                try basic.apply(to: release, at: .now)
                let copy = RecordCopy(release: release, instanceID: instance, owner: "fixture")
                return copy
            }
            let copies = [try compilation(instance: 1), try compilation(instance: 2), try compilation(instance: 3), try makeCopy(instance: 4)]
            let stats = CollectionAnalyticsService.calculate(copies.map(AnalyticsItem.init))
            #expect(stats.artists.map(\.name) == ["A", "B"])
        }
        @Test func yearsDecadesAndConcreteReissueYear() throws {
            let stats = CollectionAnalyticsService.calculate([try makeCopy(year: 1998), try makeCopy(id: 43, instance: 2, year: 2020)].map(AnalyticsItem.init))
            #expect(stats.years.map(\.id) == ["1998", "2020"])
            #expect(stats.decades.map(\.id) == ["1990er", "2020er"])
            #expect(stats.oldest == 1998); #expect(stats.newest == 2020)
        }
        @Test func missingMetadataAndInvalidDates() throws {
            let c = try makeCopy(year: nil, date: "unknown", genres: [], styles: [])
            let stats = CollectionAnalyticsService.calculate([AnalyticsItem(c)])
            #expect(stats.years.isEmpty); #expect(stats.genres.isEmpty); #expect(stats.styles.isEmpty)
            #expect(stats.recentlyAdded.isEmpty); #expect(stats.missingYear == 1)
            #expect(CollectionAnalyticsService.calculate([]).totalItems == 0)
        }
        @Test func latestTenUseDiscogsDateAndCountInstances() throws {
            let copies = try (1...12).map { try makeCopy(instance: $0, date: String(format: "2026-09-%02dT12:00:00+02:00", $0)) }
            let stats = CollectionAnalyticsService.calculate(copies.map(AnalyticsItem.init))
            #expect(stats.recentlyAdded == Array(copies.reversed().prefix(10)).map(\.id))
            #expect(stats.months.first?.count == 12); #expect(stats.acquisitionYears.first?.count == 12)
        }
        @Test func historicalChangeAndZeroDenominator() {
            let change = CollectionValueHistoryService.change(current: 110, previous: 100)
            #expect(change.amount == 10); #expect(change.percent == 10)
            #expect(CollectionValueHistoryService.change(current: 90, previous: 100).percent == -10)
            #expect(CollectionValueHistoryService.change(current: 10, previous: 0).percent == nil)
        }
        @Test func analyticsDoesNotRequestNetworkAndHandlesThousands() throws {
            let items = try (1...2000).map { try makeCopy(id: $0 % 100 + 1, instance: $0) }.map(AnalyticsItem.init)
            StatisticsURLProtocol.log.clear()
            let stats = CollectionAnalyticsService.calculate(items)
            #expect(stats.totalItems == 2000); #expect(stats.uniqueReleases == 100)
            #expect(StatisticsURLProtocol.log.paths.isEmpty)
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
        /// The page's records live in a context of their own, which can't
        /// load anything deleted elsewhere. After "Alles zurücksetzen" the
        /// model must hold none of them any more – before the page is drawn.
        @Test @MainActor func statisticsForgetTheirRecordsOnReset() async throws {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            container.mainContext.insert(try makeCopy()); try container.mainContext.save()
            let model = StatisticsViewModel()
            await model.reload(container: container)
            #expect(model.copies.count == 1)
            let version = model.version
            try ResetService(context: container.mainContext).deleteLibrary()
            NotificationCenter.default.post(name: .plattenregalDidReset, object: nil)
            #expect(model.copies.isEmpty && model.copiesByID.isEmpty && model.history.isEmpty)
            #expect(model.version > version)
            #expect(!model.calculating)
        }
        @Test func collectionValueAPIAndDailyOpenDoesNotRepeatRequest() async throws {
            let api = api(), container = try await authenticatedContainer(api)
            StatisticsURLProtocol.log.clear()
            let history = CollectionValueHistoryService()
            try await history.refresh(owner: "fixture", container: container, api: api)
            try await history.refresh(owner: "fixture", container: container, api: api)
            #expect(StatisticsURLProtocol.log.paths == ["/users/fixture/collection/value"])
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<CollectionValueSnapshot>()) == 1)
        }
        @Test func syncRefreshesValueAfterCommit() async throws {
            let api = api(), container = try await authenticatedContainer(api)
            StatisticsURLProtocol.log.clear()
            let sync = DiscogsSyncService(api: api)
            sync.start(.collection, container: container)
            while sync.busy { try await Task.sleep(for: .milliseconds(10)) }
            #expect(sync.error == nil)
            #expect(StatisticsURLProtocol.log.paths.contains("/users/fixture/collection/value"))
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<CollectionValueSnapshot>()) == 1)
            #expect(try ModelContext(container).fetch(FetchDescriptor<RecordCopy>()).first?.discogsActive == true)
        }
        @Test func unavailableValueDoesNotRollBackSuccessfulSync() async throws {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StatisticsURLProtocol.self]
            let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "denied-value" })
            let container = try await authenticatedContainer(api)
            let sync = DiscogsSyncService(api: api)
            sync.start(.collection, container: container)
            while sync.busy { try await Task.sleep(for: .milliseconds(10)) }
            #expect(sync.error?.contains("Die Sammlung ist aktualisiert") == true)
            #expect(sync.summary != nil)
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<CollectionValueSnapshot>()) == 0)
            #expect(try ModelContext(container).fetch(FetchDescriptor<RecordCopy>()).first?.discogsActive == true)
        }
        @Test func v2ToV6MigrationPreservesCollectionKallaxWantlistAndAccounts() throws {
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
            let schema = Schema(versionedSchema: LibrarySchemaV13.self)
            let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = container.mainContext
            let c = try #require(context.fetch(FetchDescriptor<RecordCopy>()).first)
            #expect(c.id == id); #expect(c.positionInShelf == 23); #expect(c.shelf?.number == 7)
            #expect(c.notes == "LOCAL"); #expect(c.purchasePrice == Decimal(string: "23.45"))
            #expect(c.discogsInstanceID == 1); #expect(c.discogsOwner == "fixture")
            #expect(try context.fetchCount(FetchDescriptor<WantlistEntry>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<DiscogsAccount>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<DiscogsFolder>()) == 1)
            try CollectionValueHistoryService.store(value: value(), owner: "fixture", copies: [c], context: context)
            #expect(try context.fetchCount(FetchDescriptor<CollectionValueSnapshot>()) == 1)
        }
        @Test func v3ToV6MigrationAddsOptimizationExclusionSchemaWithoutDataLoss() throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("Migration.store")
            let copyID: UUID = try autoreleasepool {
                let schema = Schema(versionedSchema: LibrarySchemaV3.self)
                let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: config)
                let release = LibrarySchemaV2.Release(artist: "A & B", title: "Fixture"); release.discogsID = 42
                let copy = LibrarySchemaV2.RecordCopy(release: release, shelf: LibrarySchemaV2.Shelf(number: 4), position: 12)
                copy.discogsInstanceID = 1; copy.discogsOwner = "fixture"; copy.discogsActive = true
                copy.notes = "BLEIBT"
                container.mainContext.insert(copy)
                container.mainContext.insert(CollectionValueSnapshot(owner: "fixture", date: .now, value: try value(), count: 1, unique: 1, signature: "seed"))
                try container.mainContext.save()
                return copy.id
            }
            let schema = Schema(versionedSchema: LibrarySchemaV13.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
            let context = container.mainContext
            let copy = try #require(context.fetch(FetchDescriptor<RecordCopy>()).first)
            #expect(copy.id == copyID); #expect(copy.shelf?.number == 4); #expect(copy.positionInShelf == 12); #expect(copy.notes == "BLEIBT")
            #expect(try context.fetchCount(FetchDescriptor<CollectionValueSnapshot>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<OptimizationExclusion>()) == 0)
            context.insert(OptimizationExclusion(copyID: copyID))
            try context.save()
            #expect(try context.fetch(FetchDescriptor<OptimizationExclusion>()).first?.copyID == copyID)
        }
        @Test func v6ToV8MigrationDropsInfoTextAndTurnsCapacityZeroIntoReserved() throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("Migration.store")
            let (reservedID, normalID): (UUID, UUID) = try autoreleasepool {
                let schema = Schema(versionedSchema: LibrarySchemaV6.self)
                let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: config)
                let reserved = LibrarySchemaV6.Shelf(number: 9, capacity: 0)
                reserved.name = "Vivian"
                let normal = LibrarySchemaV6.Shelf(number: 10, capacity: 90)
                container.mainContext.insert(reserved)
                container.mainContext.insert(normal)
                container.mainContext.insert(LibrarySchemaV5.ShelfCustomization(shelfID: reserved.id, infoText: "A-B"))
                try container.mainContext.save()
                return (reserved.id, normal.id)
            }

            let schema = Schema(versionedSchema: LibrarySchemaV13.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
            try LibraryStorage.prepareShelves(in: container.mainContext)

            let shelves = try container.mainContext.fetch(FetchDescriptor<Shelf>())
            let reserved = try #require(shelves.first { $0.id == reservedID })
            let normal = try #require(shelves.first { $0.id == normalID })
            #expect(reserved.name == "Vivian")
            #expect(reserved.isReserved)
            #expect(!normal.isReserved)
            #expect(shelves.count == ShelfGeometry.count)
        }
    }
}
nonisolated final class StatisticsRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return entries }
    func append(_ path: String) { lock.lock(); defer { lock.unlock() }; entries.append(path) }
    func clear() { lock.lock(); defer { lock.unlock() }; entries.removeAll() }
}
nonisolated final class StatisticsURLProtocol: URLProtocol, @unchecked Sendable {
    static let log = StatisticsRequestLog()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!; Self.log.append(url.path)
        let body: String
        if url.path.hasSuffix("/folders") { body = #"{"folders":[{"id":1,"name":"All","count":1}]}"# }
        else if url.path.contains("/collection/folders/") { body = #"{"pagination":{"page":1,"pages":1,"per_page":100,"items":1},"releases":[{"id":42,"instance_id":1,"folder_id":1,"date_added":"2026-09-20T12:00:00+02:00","rating":0,"basic_information":{"id":42,"title":"Synced","artists":[]}}]}"# }
        else if url.path.hasSuffix("/value") { body = #"{"minimum":"€50.00","median":"€100.00","maximum":"€200.00"}"# }
        else { body = "{}" }
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let status = token == "Discogs token=denied" || (token == "Discogs token=denied-value" && url.path.hasSuffix("/value")) ? 403 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
