import Foundation
import Testing
import SwiftData
@testable import Plattenregal

/// Whole flows against the real services, each on its own in-memory store:
/// a sync without network (and the next one with it), Discogs slowing the
/// app down, records and compartments deleted while a view still holds
/// them, and a very large collection. Never the real store, keychain or
/// settings.
extension AllTests {
    @MainActor struct ScenarioTests {
        private func api() -> DiscogsAPIClient {
            .stubbed(ScenarioProtocol.self, token: "scenario")
        }
        private func waitUntilIdle(_ sync: DiscogsSyncService) async throws {
            for _ in 0..<600 where sync.isRunning { try await Task.sleep(for: .milliseconds(100)) }
            #expect(!sync.isRunning)
        }

        // MARK: Network

        @Test func syncWithoutNetworkChangesNothingAndTheNextOneWorks() async throws {
            ScenarioProtocol.reset(online: false)
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let sync = DiscogsSyncService(api: api())
            sync.start(.collection, container: c)
            #expect(sync.busy)
            // A second click (other window, ⌘R) while it runs starts nothing.
            sync.start(.all, container: c)
            try await waitUntilIdle(sync)
            #expect(sync.error == DiscogsError.offline.errorDescription)
            #expect(sync.status == "Synchronisierung fehlgeschlagen")
            #expect(try c.mainContext.fetchCount(FetchDescriptor<RecordCopy>()) == 0)
            #expect(try c.mainContext.fetchCount(FetchDescriptor<DiscogsAccount>()) == 0)
            // Three attempts per request before giving up.
            #expect(ScenarioProtocol.requests == 3)

            ScenarioProtocol.reset(online: true)
            sync.start(.collection, container: c)
            try await waitUntilIdle(sync)
            #expect(sync.error == nil)
            let copies = try c.mainContext.fetch(FetchDescriptor<RecordCopy>())
            #expect(copies.count == 2)
            #expect(copies.allSatisfy { $0.release?.tracks.map(\.title) == ["Intro"] })
            #expect(try c.mainContext.fetchCount(FetchDescriptor<CollectionValueSnapshot>()) == 1)
        }

        @Test func networkLostDuringTracklistsIsReportedAndResumedLater() async throws {
            ScenarioProtocol.reset(online: true)
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let sync = DiscogsSyncService(api: api())
            let snapshot = try await sync.fetch(.collection, container: c)
            _ = try DiscogsSyncService.merge(snapshot, container: c)
            ScenarioProtocol.reset(online: false)
            #expect(await sync.loadTracklists(container: c, quiet: false))
            #expect(sync.error?.contains("2 fehlen") == true)
            // Nothing was stamped: the next run asks again.
            ScenarioProtocol.reset(online: true)
            #expect(await sync.loadTracklists(container: c, quiet: false))
            #expect(try c.mainContext.fetch(FetchDescriptor<Release>()).allSatisfy { !$0.tracks.isEmpty })
        }

        /// The "x" right after the click: nothing saved, no line left
        /// behind, and the next sync runs as usual.
        @Test func cancelledSyncSavesNothingAndClearsItsStatus() async throws {
            ScenarioProtocol.reset(online: true)
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let sync = DiscogsSyncService(api: api())
            sync.start(.collection, container: c)
            sync.cancel()
            try await waitUntilIdle(sync)
            #expect(!sync.hasStatus && sync.error == nil)
            #expect(try c.mainContext.fetchCount(FetchDescriptor<RecordCopy>()) == 0)
            #expect(try c.mainContext.fetchCount(FetchDescriptor<DiscogsAccount>()) == 0)

            sync.start(.collection, container: c)
            try await waitUntilIdle(sync)
            #expect(sync.error == nil)
            #expect(try c.mainContext.fetchCount(FetchDescriptor<RecordCopy>()) == 2)
        }

        /// Which releases the download after a sync asks Discogs for: those
        /// never asked, those asked before videos were stored, and those asked
        /// long ago – not the rest, every time.
        @Test func tracklistsAreLoadedOnlyWhenDue() async throws {
            ScenarioProtocol.reset(online: true)
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let context = ModelContext(c)
            func release(_ id: Int, tracks: [String], asked: Date?, videos: Bool = true) throws {
                let release = Release(discogsID: id, artist: "Artist", title: "Album \(id)")
                release.tracks = tracks.map { Track(position: "", title: $0, duration: "") }
                release.detailsFetchedAt = asked
                context.insert(release)
                context.insert(RecordCopy(release: release, instanceID: id, owner: "scenario"))
                if videos { try ReleaseVideoList.store([], for: id, in: context) }
            }
            try release(1, tracks: ["Alt"], asked: .now.addingTimeInterval(-DiscogsSyncService.tracklistRefreshAge - 86_400))
            // Loaded before the date was kept: dated, not asked again.
            try release(2, tracks: ["Bleibt"], asked: nil)
            // Asked the other day, Discogs has no tracklist for it.
            try release(3, tracks: [], asked: .now.addingTimeInterval(-86_400))
            // Asked the other day, before videos were stored: once more.
            try release(4, tracks: ["Ohne Videos"], asked: .now.addingTimeInterval(-86_400), videos: false)
            // Videos of a release that is gone.
            try ReleaseVideoList.store([], for: 99, in: context)
            try context.save()

            let sync = DiscogsSyncService(api: api())
            #expect(await sync.loadTracklists(container: c, quiet: true))
            #expect(ScenarioProtocol.requests == 2)
            let check = ModelContext(c)
            let releases = Dictionary(uniqueKeysWithValues: try check.fetch(FetchDescriptor<Release>()).map { ($0.discogsID, $0) })
            #expect(releases[1]?.tracks.map(\.title) == ["Intro"])
            #expect(releases[2]?.tracks.map(\.title) == ["Bleibt"] && releases[2]?.detailsFetchedAt != nil)
            #expect(releases[3]?.tracks.isEmpty == true)
            #expect(releases[4]?.tracks.map(\.title) == ["Intro"])
            #expect(Set(try check.fetch(FetchDescriptor<ReleaseVideoList>()).map(\.discogsID)) == [1, 2, 3, 4])
            // Nothing is due any more.
            #expect(await sync.loadTracklists(container: c, quiet: true) == false)
            #expect(ScenarioProtocol.requests == 2)
        }

        @Test func discogsRateLimitIsWaitedOut() async throws {
            ScenarioProtocol.reset(online: true, throttleFirst: true)
            let started = ContinuousClock.now
            let identity = try await api().identity()
            #expect(identity.username == "scenario")
            // Retry-After: 1 was respected, no error reached the user.
            #expect(ContinuousClock.now - started >= .seconds(1))
            #expect(ScenarioProtocol.requests == 2)
        }

        // MARK: Deleted under an open view

        /// The guards in the shelf page's undo and the record editor rely on
        /// a deleted model reporting it – checked here for every way the app
        /// deletes compartments and copies.
        @Test func modelsDeletedElsewhereReportIt() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let context = c.mainContext
            let cabinets = CabinetService(context: context)
            let cabinet = try cabinets.add(name: "Flur", columns: 2, rows: 2)
            let dropped = try #require(cabinet.orderedShelves.last)
            try cabinets.resize(cabinet, columns: 1, rows: 1)
            #expect(dropped.isDeleted || dropped.modelContext == nil)

            let positions = PositionService(context: context)
            let first = try #require(cabinet.orderedShelves.first)
            let sold = try positions.insert(release: Release(artist: "A", title: "B"), shelf: first)
            sold.discogsActive = false
            try positions.delete(sold)
            #expect(sold.isDeleted || sold.modelContext == nil)

            // Restoring a layout without that cabinet removes its compartments.
            let held = try #require(cabinet.orderedShelves.first)
            var backup = try ShelfBackupService(context: context).makeBackup()
            backup.cabinets = backup.cabinets.map { Array($0.prefix(1)) }
            let keeper = try positions.insert(release: Release(artist: "C", title: "D"), shelf: try #require(
                try cabinets.cabinets().first?.orderedShelves.first), instanceID: 99)
            backup.placements = [.init(instanceID: 99, shelf: keeper.shelf!.number, position: 1)]
            try ShelfBackupService(context: context).restore(backup)
            #expect(held.isDeleted || held.modelContext == nil)
            #expect(keeper.shelf != nil)
        }

        @Test func addingRecordsKeepsWorkingAfterTheLocationsWereReset() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let context = c.mainContext
            let positions = PositionService(context: context)
            let a = try positions.insert(release: Release(artist: "Air", title: "Moon Safari"), shelf: nil)
            let b = try positions.insert(release: Release(artist: "Björk", title: "Post"), shelf: nil)
            let shelf = try #require(try context.fetch(FetchDescriptor<Shelf>()).first { $0.sortOrder == 1 })
            let session = ShelfAssignmentSession(shelf: shelf)
            session.load(context, owner: nil, labels: ShelfLabels())
            session.add(a, in: context)
            #expect(a.shelf?.id == shelf.id)
            // "Standorte zurücksetzen" in the settings window while the sheet is open.
            try ResetService(context: context).resetLocations()
            session.add(b, in: context)
            #expect(session.error == nil)
            #expect(b.shelf?.id == shelf.id && b.positionInShelf == 1)
        }

        /// The list is a snapshot: a record sold meanwhile (a sync) is not placed.
        @Test func recordThatLeftTheCollectionIsNotSortedIn() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let context = c.mainContext
            let sold = try PositionService(context: context).insert(release: Release(artist: "Air", title: "Moon Safari"), shelf: nil)
            let shelf = try #require(try context.fetch(FetchDescriptor<Shelf>()).first { $0.sortOrder == 1 })
            let session = ShelfAssignmentSession(shelf: shelf)
            session.load(context, owner: nil, labels: ShelfLabels())
            #expect(session.candidates.map(\.id) == [sold.id])
            sold.discogsActive = false
            session.add(sold, in: context)
            #expect(sold.shelf == nil && session.addedCount == 0)
            #expect(session.error?.contains("nicht mehr in der Collection") == true)
            #expect(session.candidates.isEmpty)
        }

        @Test func addingListsFittingRecordsFirstPausedInPlace() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let context = c.mainContext
            let positions = PositionService(context: context)
            let shelves = try context.fetch(FetchDescriptor<Shelf>())
            let first = try #require(shelves.first { $0.sortOrder == 1 })
            let second = try #require(shelves.first { $0.sortOrder == 2 })
            try positions.insert(release: Release(artist: "Air", title: "Moon Safari"), shelf: first)
            try positions.insert(release: Release(artist: "Moby", title: "Play"), shelf: second)
            let zappa = try positions.insert(release: Release(artist: "Zappa", title: "Apostrophe"), shelf: nil)
            let abba = try positions.insert(release: Release(artist: "Abba", title: "Arrival"), shelf: nil)
            let aphex = try positions.insert(release: Release(artist: "Aphex Twin", title: "Drukqs"), shelf: nil)
            try positions.setMissing([aphex], true)

            let session = ShelfAssignmentSession(shelf: first)
            session.load(context, owner: nil, labels: ShelfLabels())
            // Fits here, then belongs elsewhere; a paused one keeps its place
            // (the view lists it under "Gesucht"), so found again it returns there.
            #expect(session.candidates.map(\.id) == [abba.id, aphex.id, zappa.id])
            #expect(session.missing == [aphex.id])
            #expect(session.belongsElsewhere[zappa.id] != nil)
            #expect(session.belongsElsewhere[abba.id] == nil && session.belongsElsewhere[aphex.id] == nil)

            // "+" puts a record at its alphabetical place, not at the end.
            session.add(abba, in: context)
            #expect(abba.shelf?.id == first.id && abba.positionInShelf == 1)
        }

        @Test func sortingInPutsEachRecordIntoItsOwnShelf() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let context = c.mainContext
            let positions = PositionService(context: context)
            let shelves = try context.fetch(FetchDescriptor<Shelf>())
            let first = try #require(shelves.first { $0.sortOrder == 1 })
            let second = try #require(shelves.first { $0.sortOrder == 2 })
            try positions.insert(release: Release(artist: "Air", title: "Moon Safari"), shelf: first)
            try positions.insert(release: Release(artist: "Can", title: "Tago Mago"), shelf: first, position: 2)
            try positions.insert(release: Release(artist: "Moby", title: "Play"), shelf: second)
            let zappa = try positions.insert(release: Release(artist: "Zappa", title: "Apostrophe"), shelf: nil)
            let björk = try positions.insert(release: Release(artist: "Björk", title: "Post"), shelf: nil)

            // The round button: no shelf of its own, simply by artist.
            let session = ShelfAssignmentSession(shelf: nil)
            session.load(context, owner: nil, labels: ShelfLabels())
            #expect(session.candidates.map(\.id) == [björk.id, zappa.id])
            #expect(session.belongsElsewhere[björk.id] != nil && session.belongsElsewhere[zappa.id] != nil)

            session.add(björk, in: context)
            session.add(zappa, in: context)
            #expect(session.error == nil)
            #expect(björk.shelf?.id == first.id && björk.positionInShelf == 2)
            #expect(zappa.shelf?.id == second.id && zappa.positionInShelf == 2)
            #expect(session.lastAddedHere?.id == zappa.id)
            #expect(session.candidates.isEmpty)
        }

        // MARK: Large collection

        @Test func tenThousandRecords() throws {
            let c = try LibraryStorage.makeContainer(inMemory: true)
            let context = c.mainContext
            let clock = ContinuousClock()
            var timings: [(String, Duration)] = []
            func measure<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
                let start = clock.now
                let result = try body()
                timings.append((name, clock.now - start)); return result
            }
            let names = ["Äther", "Björk", "Can", "Daft Punk", "Ëlla", "Four Tet", "Ghost", "Holger Czukay", "Isolée",
                         "Jóhann Jóhannsson", "Kraftwerk", "Łona", "Moby (2)", "Neu!", "Øystein", "Pole", "Queen",
                         "Röyksopp", "Sigur Rós", "The Orb", "Ulver", "Various", "Wire", "Xela", "Yello", "Zero 7", "808 State"]
            let entries = (1...10_000).map { index in
                let release = index <= 8000 ? index : index - 8000
                let basic = DiscogsBasicInformation(id: release, title: "Album \(release)",
                    artists: [.init(id: release % names.count + 1, name: "\(names[release % names.count]) \(release / 97)", join: nil)],
                    year: 1960 + release % 65, labels: [.init(id: release % 300, name: "=Label \(release % 300)", catno: "CAT-\(release)")],
                    formats: [.init(name: "Vinyl", qty: "1", descriptions: ["LP", "Album"])], genres: release % 2 == 0 ? ["Electronic"] : ["Electronic", "Rock"],
                    styles: [["Ambient", "Techno"], ["Krautrock"], []][release % 3], cover_image: nil, thumb: nil, resource_url: nil, master_id: nil)
                return DiscogsCollectionDTO(id: release, instance_id: index, folder_id: 1, date_added: "2020-01-01T10:00:00+01:00",
                                            basic_information: basic)
            }
            let snapshot = DiscogsSyncSnapshot(username: "big", userID: 1, fingerprint: "big", scope: .collection,
                                               folders: [.init(id: 0, name: "All", count: 10_000), .init(id: 1, name: "Uncategorized", count: 10_000)],
                                               collection: entries)
            let first = try measure("Erster Abgleich (Merge)") { try DiscogsSyncService.merge(snapshot, container: c) }
            #expect(first.collectionAdded == 10_000)
            let again = try measure("Wiederholter Abgleich") { try DiscogsSyncService.merge(snapshot, container: c) }
            #expect(again.collectionAdded == 0 && again.collectionUpdated == 0)

            // Two more cabinets: 12 + 36 + 36 compartments.
            let cabinets = CabinetService(context: context)
            try cabinets.add(name: "Wohnzimmer", columns: 6, rows: 6)
            try cabinets.add(name: "Keller", columns: 6, rows: 6)
            let shelves = Shelf.inUse(try context.fetch(FetchDescriptor<Shelf>()))
            let copies = try context.fetch(FetchDescriptor<RecordCopy>())
            let sorted = measure("Alphabetisch sortieren") { SortingService.sorted(copies) }
            // All but 100 placed alphabetically, as someone sorting in by hand would.
            let placed = Array(sorted.prefix(9_900))
            let perShelf = Int((Double(placed.count) / Double(shelves.count)).rounded(.up))
            var backup = try ShelfBackupService(context: context).makeBackup()
            backup.placements = placed.enumerated().map { index, copy in
                .init(instanceID: copy.discogsInstanceID, shelf: shelves[index / perShelf].number, position: index % perShelf + 1)
            }
            try measure("Belegung wiederherstellen") { try ShelfBackupService(context: context).restore(backup) }
            #expect(try context.fetchCount(FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.shelf != nil })) == 9_900)

            let labels = measure("Fach-Beschriftungen") { ShelfRangeLabels.compute(for: shelves) }
            #expect(shelves.allSatisfy { labels[$0.id] != nil })
            let unplaced = try #require(sorted.last)
            let spots = measure("Platz finden (eine Platte)") { AlphabeticalPlacement.spots(for: unplaced, in: shelves) }
            #expect(!spots.isEmpty)

            let saved = try measure("Sicherung erstellen + JSON") { try ShelfBackupService.encode(try ShelfBackupService(context: context).makeBackup()) }
            let decoded = try measure("Sicherung lesen") { try ShelfBackupService.decode(saved) }
            #expect(decoded.placements.count == 9_900)

            let index = measure("Suchindex aufbauen") { SearchIndex(copies, id: \.id, text: SortingService.searchText) }
            let words = SearchIndex<UUID>.words("royksopp 12")
            let hits = measure("Suche (ein Tastendruck)") { copies.filter { index.matches($0.id, words) } }
            #expect(!hits.isEmpty)

            let stats = measure("Statistik berechnen") { CollectionAnalyticsService.calculate(copies.map(AnalyticsItem.init)) }
            #expect(stats.totalItems == 10_000 && stats.uniqueReleases == 8_000)

            let service = CollectionExportService(context: context)
            let table = try measure("Export-Tabelle (alle Spalten)") {
                try service.table(ExportOptions(source: .collection, order: .shelf, groups: Set(ExportColumnGroup.allCases)))
            }
            #expect(table.rows.count == 10_000)
            let csv = measure("CSV schreiben") { CSVWriter.data(for: table, delimiter: .semicolon) }
            // Cells starting with "=" stay text in Excel.
            #expect(String(decoding: csv, as: UTF8.self).contains("'=Label 1"))
            let pdf = try measure("PDF schreiben") { try PDFListWriter.data(for: table, title: "Test", subtitle: "10.000") }
            #expect(pdf.count > 100_000)

            let report = timings.map { "  \($0.0): \($0.1.formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))" }
            print("⏱ 10.000 Platten, \(shelves.count) Fächer, CSV \(csv.count / 1024) KB, PDF \(pdf.count / 1024) KB\n" + report.joined(separator: "\n"))
            // Generous bounds: this is about nothing hanging, not about benchmarks.
            #expect(timings.allSatisfy { $0.1 < .seconds(30) })
        }
    }
}
