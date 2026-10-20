import Foundation
import Testing
import SwiftData
import Synchronization
@testable import Plattenregal

extension AllTests {
    struct DiscogsSyncTests {
        func basic(_ id: Int = 42, title: String = "Album") -> DiscogsBasicInformation {
            DiscogsBasicInformation(id: id, title: title, artists: [.init(id: 1, name: "Artist", join: nil)], year: 1999,
                labels: [.init(id: 2, name: "Label", catno: "CAT-1")], formats: [.init(name: "Vinyl", qty: "1", descriptions: ["LP"])],
                genres: ["Electronic"], styles: ["Trance"], cover_image: "https://example.com/cover", thumb: "https://example.com/thumb", resource_url: "https://api.discogs.com/releases/\(id)", master_id: 123)
        }
        func entry(_ instance: Int = 100, release: Int = 42, folder: Int = 1) -> DiscogsCollectionDTO {
            .init(id: release, instance_id: instance, folder_id: folder, date_added: "2026-09-20T08:00:00+02:00", basic_information: basic(release))
        }
        func want(_ id: Int = 42) -> DiscogsWantDTO {
            .init(id: id, date_added: "2026-09-20T08:00:00+02:00", notes: "Want note", basic_information: basic(id))
        }
        @discardableResult func merge(_ container: ModelContainer, collection: [DiscogsCollectionDTO]? = nil, wants: [DiscogsWantDTO]? = nil,
            folders: [DiscogsFolderDTO]? = nil, scope: DiscogsSyncScope = .all, owner: String = "fixture") throws -> DiscogsSyncSummary {
            try DiscogsSyncService.merge(.init(username: owner, userID: 7, fingerprint: "fixture", scope: scope, folders: folders, collection: collection, wants: wants), container: container)
        }
        func copies(_ container: ModelContainer) throws -> [RecordCopy] { try ModelContext(container).fetch(FetchDescriptor<RecordCopy>()) }
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
        /// A sync that only confirms the store lets the pages keep what they derived.
        @Test func unchangedSyncReportsNoChanges() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let folders = [DiscogsFolderDTO(id: 1, name: "Alles", count: 1)]
            #expect(try merge(c, collection: [entry()], wants: [want(43)], folders: folders).hasChanges)
            #expect(try !merge(c, collection: [entry()], wants: [want(43)], folders: folders).hasChanges)
        }
        /// … and writes none of them again: only the account takes the new
        /// sync dates. Every rewritten record is read again by the main
        /// context afterwards (`LibraryRecords.refetch`).
        @Test func unchangedSyncRewritesNoRecords() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let folders = [DiscogsFolderDTO(id: 1, name: "Alles", count: 2)]
            let items = [entry(100, release: 42), entry(101, release: 43)]
            try merge(c, collection: items, wants: [want(44)], folders: folders)
            let written = Mutex<[String]>([])
            let observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { note in
                guard (note.object as? ModelContext)?.container === c else { return }
                let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
                let ids = keys.flatMap { (note.userInfo?[$0.rawValue] as? [PersistentIdentifier]) ?? [] }
                written.withLock { $0 += ids.map(\.entityName) }
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            try merge(c, collection: items, wants: [want(44)], folders: folders)
            #expect(written.withLock { $0 } == [Schema.entityName(for: DiscogsAccount.self)])
            // One release renamed on Discogs: that release, nothing around it.
            written.withLock { $0 = [] }
            let renamed = DiscogsCollectionDTO(id: 43, instance_id: 101, folder_id: 1, date_added: "2026-09-20T08:00:00+02:00", basic_information: basic(43, title: "Neu"))
            let summary = try merge(c, collection: [items[0], renamed], wants: [want(44)], folders: folders)
            #expect(summary.collectionUpdated == 1)
            #expect(Set(written.withLock { $0 }) == [Schema.entityName(for: DiscogsAccount.self), Schema.entityName(for: Release.self)])
            #expect(written.withLock { $0 }.count == 2)
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
        /// Changes on records the counts don't name still reach the pages.
        @Test func collectionDetailsCountAsChanges() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let folders = [DiscogsFolderDTO(id: 1, name: "Eins", count: 1), DiscogsFolderDTO(id: 2, name: "Zwei", count: 0)]
            try merge(c, collection: [entry(folder: 1)], folders: folders)
            // Moved to another folder on Discogs.
            #expect(try merge(c, collection: [entry(folder: 2)], folders: folders).hasChanges)
            #expect(try copies(c).first?.discogsFolderID == 2)
            #expect(try !merge(c, collection: [entry(folder: 2)], folders: folders).hasChanges)
            // Taken out of the collection.
            #expect(try merge(c, collection: [], folders: folders).hasChanges)
            #expect(try !merge(c, collection: [], folders: folders).hasChanges)
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
            let api = DiscogsAPIClient.stubbed(SyncPaginationProtocol.self, token: "wantfailure")
            let sync = DiscogsSyncService(api: api)
            do { _ = try await sync.fetch(.all, container: c); Issue.record("Expected wantlist failure") }
            catch DiscogsError.offline {}
            #expect(try copies(c).first?.discogsInstanceID == 100)
            #expect(try ModelContext(c).fetchCount(FetchDescriptor<WantlistEntry>()) == 1)
        }
    }
}
