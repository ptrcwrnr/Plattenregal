import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests {
    struct DiscogsSyncTests {
        private func basic(_ id: Int = 42, title: String = "Album") -> DiscogsBasicInformation {
            DiscogsBasicInformation(id: id, title: title, artists: [.init(id: 1, name: "Artist", join: nil)], year: 1999,
                labels: [.init(id: 2, name: "Label", catno: "CAT-1")], formats: [.init(name: "Vinyl", qty: "1", descriptions: ["LP"])],
                genres: ["Electronic"], styles: ["Trance"], cover_image: "https://example.com/cover", thumb: "https://example.com/thumb", resource_url: "https://api.discogs.com/releases/\(id)", master_id: 123)
        }
        private func entry(_ instance: Int = 100, release: Int = 42, folder: Int = 1) -> DiscogsCollectionDTO {
            .init(id: release, instance_id: instance, folder_id: folder, date_added: "2026-09-20T08:00:00+02:00", basic_information: basic(release))
        }
        private func want(_ id: Int = 42) -> DiscogsWantDTO {
            .init(id: id, date_added: "2026-09-20T08:00:00+02:00", notes: "Want note", basic_information: basic(id))
        }
        @discardableResult private func merge(_ container: ModelContainer, collection: [DiscogsCollectionDTO]? = nil, wants: [DiscogsWantDTO]? = nil,
            folders: [DiscogsFolderDTO]? = nil, scope: DiscogsSyncScope = .all, owner: String = "fixture") throws -> DiscogsSyncSummary {
            try DiscogsSyncService.merge(.init(username: owner, userID: 7, fingerprint: "fixture", scope: scope, folders: folders, collection: collection, wants: wants), container: container)
        }
        private func copies(_ container: ModelContainer) throws -> [RecordCopy] { try ModelContext(container).fetch(FetchDescriptor<RecordCopy>()) }
        @Test func retryAfterSecondsAndHTTPDate() {
            #expect(DiscogsAPIClient.retryDelay("12") == 12)
            #expect(DiscogsAPIClient.retryDelay(nil) == 60)
            #expect(DiscogsAPIClient.retryDelay("Thu, 01 Jan 1970 00:01:00 GMT", now: Date(timeIntervalSince1970: 0)) == 60)
            // Past dates wait a second, absurd values no longer than the cap.
            #expect(DiscogsAPIClient.retryDelay("Thu, 01 Jan 1970 00:01:00 GMT", now: Date(timeIntervalSince1970: 3600)) == 1)
            #expect(DiscogsAPIClient.retryDelay("9999999") == DiscogsAPIClient.maximumRetryDelay)
            #expect(DiscogsAPIClient.retryDelay("-5") == 1)
            #expect(DiscogsAPIClient.retryDelay("bald") == 60)
        }
        @Test func largeCollectionMergeAndRepeat() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let items = (1...2000).map { entry($0, release: $0) }
            try merge(c, collection: items)
            let repeated = try merge(c, collection: items)
            #expect(try copies(c).count == 2000)
            #expect(repeated.collectionAdded == 0); #expect(repeated.collectionUpdated == 0)
        }
        /// A sync that only confirms the store lets the pages keep what they derived.
        @Test func unchangedSyncReportsNoChanges() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let folders = [DiscogsFolderDTO(id: 1, name: "Alles", count: 1)]
            #expect(try merge(c, collection: [entry()], wants: [want(43)], folders: folders).hasChanges)
            #expect(try !merge(c, collection: [entry()], wants: [want(43)], folders: folders).hasChanges)
        }
        @Test func wantlistDetailsCountAsChanges() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            try merge(c, wants: [want(43)])
            let noted = DiscogsWantDTO(id: 43, date_added: "2026-09-20T08:00:00+02:00", notes: "Neue Notiz", basic_information: basic(43))
            #expect(try merge(c, wants: [noted]).hasChanges)
            let renamed = DiscogsWantDTO(id: 43, date_added: "2026-09-20T08:00:00+02:00", notes: "Neue Notiz", basic_information: basic(43, title: "Neu"))
            #expect(try merge(c, wants: [renamed]).hasChanges)
            #expect(try !merge(c, wants: [renamed]).hasChanges)
        }
        @Test func anotherAccountCountsAsChange() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            try merge(c, collection: [entry()], owner: "erstes")
            try merge(c, collection: [entry()], owner: "zweites")
            #expect(try !merge(c, collection: [entry()], owner: "zweites").hasChanges)
            // Back to the first one, whose records are all there already.
            #expect(try merge(c, collection: [entry()], owner: "erstes").hasChanges)
        }
        @Test func cancelledMergeDoesNotWrite() async throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            try merge(c, collection: [entry()])
            let snapshot = DiscogsSyncSnapshot(username: "fixture", userID: 7, fingerprint: "fixture", scope: .collection, collection: [])
            let task = Task {
                try Task.checkCancellation()
                return try DiscogsSyncService.merge(snapshot, container: c)
            }
            task.cancel()
            do { _ = try await task.value; Issue.record("Expected cancellation") }
            catch is CancellationError {}
            #expect(try copies(c).first?.discogsActive == true)
        }
        @Test func unplacedCopyCanBePlaced() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            try merge(c, collection: [entry()])
            let copy = try #require(c.mainContext.fetch(FetchDescriptor<RecordCopy>()).first)
            let service = PositionService(context: c.mainContext)
            try service.unplace(copy)
            let shelf = try #require(c.mainContext.fetch(FetchDescriptor<Shelf>()).first)
            try service.move(copy, to: shelf, position: 1)
            #expect(copy.positionInShelf == 1)
            #expect(copy.discogsInstanceID == 100)
        }
        @Test func wantlistFailureAfterCompleteCollectionDoesNotCommit() async throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            try merge(c, collection: [entry()], wants: [want()], owner: "wantfailure")
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncPaginationProtocol.self]
            let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "wantfailure" })
            let sync = DiscogsSyncService(api: api)
            do { _ = try await sync.fetch(.all, container: c); Issue.record("Expected wantlist failure") }
            catch DiscogsError.offline {}
            #expect(try copies(c).first?.discogsInstanceID == 100)
            #expect(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()) == 1)
        }
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
        @Test func folderMove() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            try merge(c, collection: [entry()]); try merge(c, collection: [entry(folder: 9)])
            #expect(try copies(c).first?.discogsFolderID == 9)
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
            #expect(Set(items.compactMap(\.discogsInstanceID)) == [100, 200])
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
        /// From V2 on, the oldest store with synced copies, all the way to the current schema.
        @Test func oldStoreMigrationPreservesLocalData() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("Migration.store")
            let id: UUID = try autoreleasepool {
                let schema = Schema(versionedSchema: LibrarySchemaV2.self)
                let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
                let shelf = LibrarySchemaV2.Shelf(number: 6)
                let release = LibrarySchemaV2.Release(artist: "Artist", title: "Album"); release.discogsID = 42
                let copy = LibrarySchemaV2.RecordCopy(release: release, shelf: shelf, position: 37)
                copy.discogsInstanceID = 100; copy.discogsOwner = "fixture"; copy.discogsActive = true
                copy.notes = "Preserve"; copy.purchasePrice = 12
                container.mainContext.insert(copy); try container.mainContext.save(); return copy.id
            }
            let schema = Schema(versionedSchema: LibrarySchemaV15.self)
            let migrated = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let copy = try #require(copies(migrated).first)
            #expect(copy.id == id); #expect(copy.positionInShelf == 37); #expect(copy.shelf?.number == 6)
            try merge(migrated, collection: [entry()])
            #expect(try copies(migrated).first?.positionInShelf == 37)
        }
        @Test func v11MigrationDropsOnlyRecordsWithoutDiscogsIDs() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("Migration.store")
            let syncedID: UUID = try autoreleasepool {
                let schema = Schema(versionedSchema: LibrarySchemaV10.self)
                let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
                let context = container.mainContext
                let shelf = LibrarySchemaV10.Shelf(number: 3); context.insert(shelf)
                let synced = LibrarySchemaV10.Release(artist: "Synced", title: "Album"); synced.discogsID = 42
                let copy = LibrarySchemaV10.RecordCopy(release: synced, shelf: shelf, position: 1)
                copy.discogsInstanceID = 100; copy.discogsOwner = "fixture"; copy.discogsActive = false; copy.notes = "BLEIBT"
                context.insert(copy)
                let wanted = LibrarySchemaV10.Release(artist: "Wanted", title: "Album"); wanted.discogsID = 43
                context.insert(LibrarySchemaV10.WantlistEntry(owner: "fixture", release: wanted, releaseID: 43))
                // Added by hand in an early version: no Discogs IDs anywhere.
                let manual = LibrarySchemaV10.Release(artist: "Manual", title: "Album")
                context.insert(LibrarySchemaV10.RecordCopy(release: manual, shelf: shelf, position: 2))
                try context.save(); return copy.id
            }
            let schema = Schema(versionedSchema: LibrarySchemaV15.self)
            let migrated = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                              configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(migrated)
            let copies = try context.fetch(FetchDescriptor<RecordCopy>())
            #expect(copies.map(\.id) == [syncedID])
            #expect(copies.first?.discogsInstanceID == 100); #expect(copies.first?.discogsOwner == "fixture")
            #expect(copies.first?.discogsActive == false)
            #expect(copies.first?.shelf?.number == 3)
            #expect(Set(try context.fetch(FetchDescriptor<Release>()).map(\.discogsID)) == [42, 43])
            #expect(try context.fetchCount(FetchDescriptor<WantlistEntry>()) == 1)
        }
        @Test func paginationFailureDoesNotModifyAnyScope() async throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            try merge(c, collection: [entry()], wants: [want()], folders: [.init(id: 1, name: "Original", count: 1)])
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncPaginationProtocol.self]
            let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "fixture" })
            let sync = DiscogsSyncService(api: api)
            do { _ = try await sync.fetch(.all, container: c); Issue.record("Expected page 2 failure") }
            catch DiscogsError.offline {} catch { Issue.record("Unexpected \(error)") }
            #expect(try copies(c).count == 1); #expect(try copies(c).first?.discogsActive == true)
            #expect(try ModelContext(c).fetch(FetchDescriptor<DiscogsFolder>()).first?.name == "Original")
            #expect(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()) == 1)
        }
        @Test func completePaginationAndDuplicateDetection() async throws {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncPaginationProtocol.self]
            let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "fixture" })
            let collection = try await api.collection(username: "success")
            #expect(collection.count == 2); #expect(collection.map(\.instance_id) == [1, 2])
            do { _ = try await api.collection(username: "duplicate"); Issue.record("Duplicate accepted") }
            catch DiscogsError.incompletePagination {} catch { Issue.record("Unexpected \(error)") }
        }
        @Test func completeWantlistPagination() async throws {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyncPaginationProtocol.self]
            let api = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "fixture" })
            let wants = try await api.wants(username: "success")
            #expect(wants.map(\.id) == [1, 2])
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
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [TracklistStatusProtocol.self]
            let sync = DiscogsSyncService(api: DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { "fixture" }))
            #expect(await sync.loadTracklists(container: c, quiet: true))
            let releases = Dictionary(uniqueKeysWithValues: try ModelContext(c).fetch(FetchDescriptor<Release>()).map { ($0.discogsID, $0) })
            #expect(releases[200]?.tracks.map(\.title) == ["Intro"])
            // Removed on Discogs: stamped, so the next launch has nothing to do for it.
            #expect(releases[404]?.detailsFetchedAt != nil)
            // 403 may be the token, not the release: tried again next time.
            #expect(releases[403]?.detailsFetchedAt == nil)
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
}

nonisolated final class SyncPaginationProtocol: URLProtocol, @unchecked Sendable {
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

/// `/releases/<status>` answers with that HTTP status; 200 with a one-track release.
nonisolated final class TracklistStatusProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let status = Int(url.lastPathComponent) ?? 500
        let body = status == 200 ? #"{"id":200,"title":"Album","tracklist":[{"position":"A1","title":"Intro","duration":"1:00"}]}"# : "{}"
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
