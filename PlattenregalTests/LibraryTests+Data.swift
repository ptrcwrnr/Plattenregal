import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests.LibraryTests {
    @Test func basicInformationWithOptionalFields() throws {
        let data = Data(#"{"id":123,"title":"Computerwelt","year":0,"artists":[{"name":"Kraftwerk (2)","anv":"Kraftwerk"}],"labels":[{"name":"EMI","catno":"1C 064"}],"formats":[{"name":"Vinyl","qty":"1","descriptions":["LP"]}],"genres":["Electronic"],"cover_image":"","thumb":"https://example.com/thumb.jpg"}"#.utf8)
        let release = Release(artist: "", title: "")
        try JSONDecoder().decode(DiscogsBasicInformation.self, from: data).apply(to: release, at: .now)
        #expect(release.artist == "Kraftwerk"); #expect(release.discogsID == 123)
        #expect(release.catalogNumber == "1C 064"); #expect(release.year == nil)
        #expect(release.format == "1 · Vinyl · LP"); #expect(release.fetchedAt != nil)
        #expect(release.displayArtist == "Kraftwerk")
        #expect(release.displayTitle == "Computerwelt")
        // Discogs sends "" without an image; the thumbnail stands in.
        #expect(release.coverURL == "https://example.com/thumb.jpg")
        let minimal = Release(artist: "", title: "")
        try JSONDecoder().decode(DiscogsBasicInformation.self, from: Data(#"{"id":1,"title":"Untitled"}"#.utf8)).apply(to: minimal, at: .now)
        #expect(minimal.artist.isEmpty && minimal.label.isEmpty && minimal.coverURL == nil)
        #expect(minimal.displayArtist == String(localized: "Unbekannter Interpret"))
    }
    @Test func releaseDetailsOnlyTouchTracklistAndCountry() throws {
        let data = Data(#"{"id":123,"title":"Computerwelt","country":"Germany","tracklist":[{"position":"A1","title":"Computerwelt","duration":"5:05"},{"title":"Nummern"}]}"#.utf8)
        let release = Release(artist: "Kraftwerk", title: "Computerwelt")
        try JSONDecoder().decode(DiscogsReleaseDTO.self, from: data).applyDetails(to: release)
        #expect(release.tracks.map(\.title) == ["Computerwelt", "Nummern"])
        #expect(release.tracks[0].position == "A1" && release.tracks[1].position.isEmpty && release.tracks[1].duration.isEmpty)
        #expect(release.country == "Germany"); #expect(release.detailsFetchedAt != nil)
        // What the collection sync wrote stays.
        #expect(release.artist == "Kraftwerk" && release.title == "Computerwelt")
        let minimal = Release(artist: "", title: "Untitled")
        try JSONDecoder().decode(DiscogsReleaseDTO.self, from: Data(#"{"id":1}"#.utf8)).applyDetails(to: minimal)
        #expect(minimal.tracks.isEmpty && minimal.country.isEmpty && minimal.detailsFetchedAt != nil)
    }
    @Test func artistLineFollowsDiscogsJoins() {
        typealias A = DiscogsBasicInformation.Artist
        func line(_ artists: [A]) -> String { DiscogsBasicInformation.artistLine(artists) }
        #expect(line([A(id: 1, name: "Moby", join: ","), A(id: 2, name: "Kid", join: "")]) == "Moby, Kid")
        #expect(line([A(id: 1, name: "A", join: "&"), A(id: 2, name: "B", join: nil)]) == "A & B")
        #expect(line([A(id: 1, name: "A", join: "Feat."), A(id: 2, name: "B", join: "")]) == "A Feat. B")
        #expect(line([A(id: 1, name: "A", join: ""), A(id: 2, name: "B", join: nil)]) == "A, B")
        #expect(line([A(id: 1, name: "Solo", join: "")]) == "Solo")
        #expect(line([]) == "")
    }
    /// What Discogs sends as "date_added", and what older stores hold.
    @Test func discogsDatesAreReadInEveryForm() throws {
        let stamp = try #require(DiscogsDate.parse("2026-09-20T08:00:00-07:00"))
        #expect(stamp == (try Date.ISO8601FormatStyle().parse("2026-09-20T15:00:00Z")))
        #expect(DiscogsDate.parse("2026-09-20T15:00:00.250Z")?.timeIntervalSince(stamp) == 0.25)
        // A plain day is the local midnight, so it stays that day in every list.
        let day = try #require(DiscogsDate.parse("2026-09-20"))
        #expect(Calendar.current.dateComponents([.year, .month, .day, .hour], from: day) == DateComponents(year: 2026, month: 9, day: 20, hour: 0))
        #expect(DiscogsDate.parse(nil) == nil)
        #expect(DiscogsDate.parse("") == nil)
        #expect(DiscogsDate.parse("unknown") == nil)
    }
    @Test func emptyCoverFallsBackToThumbnailOrNothing() throws {
        func cover(_ image: String?, _ thumb: String?) throws -> String? {
            let basic = DiscogsBasicInformation(id: 1, title: "T", artists: nil, year: nil, labels: nil, formats: nil,
                genres: nil, styles: nil, cover_image: image, thumb: thumb, resource_url: nil, master_id: nil)
            let release = Release(discogsID: 1, artist: "", title: "")
            try basic.apply(to: release, at: .now)
            return release.coverURL
        }
        #expect(try cover("https://example.com/c.jpg", "https://example.com/t.jpg") == "https://example.com/c.jpg")
        #expect(try cover("", "https://example.com/t.jpg") == "https://example.com/t.jpg")
        #expect(try cover(" ", nil) == nil)
        #expect(try cover(nil, "") == nil)
    }
    @Test func positionsSurviveReload() throws {
        let (container, shelves, service) = try fixture()
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B", at: 1)
        let secondContext = ModelContext(container)
        let restored = try secondContext.fetch(FetchDescriptor<RecordCopy>(sortBy: [SortDescriptor(\RecordCopy.positionInShelf)]))
        #expect(restored.map(\.id) == [b.id, a.id])
        #expect(restored.map(\.positionInShelf) == [1, 2])
    }
    @Test func rollbackRestoresPositions() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "A")
        #expect(throws: (any Error).self) { try service.save {
            a.positionInShelf = 99
            throw LibraryError.invalidPosition
        } }
        #expect(a.positionInShelf == 1)
    }
    /// V15 is the oldest store the plan knows; V16 only adds the sale list,
    /// V17 the release videos.
    @Test func v15StoreMigratesToV17KeepingEverything() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Migration.store")
        let (placedID, missingID): (UUID, UUID) = try autoreleasepool {
            let schema = Schema(versionedSchema: LibrarySchemaV15.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = container.mainContext
            let cabinet = Cabinet(name: "Kallax", rows: 1, columns: 2, sortOrder: 0)
            context.insert(cabinet)
            let shelf = Shelf(number: 1, cabinet: cabinet, slot: 1)
            context.insert(shelf)
            shelf.cabinet = cabinet
            let release = Release(discogsID: 42, artist: "Air", title: "Moon Safari")
            context.insert(release)
            let placed = RecordCopy(release: release, instanceID: 1, owner: "fixture", shelf: shelf, position: 1)
            let missing = RecordCopy(release: release, instanceID: 2, owner: "fixture", shelf: shelf, position: 2)
            context.insert(placed); context.insert(missing)
            context.insert(MissingCopyMark(copyID: missing.id))
            context.insert(OptimizationExclusion(copyID: placed.id))
            context.insert(WantlistEntry(owner: "fixture", release: release, releaseID: 42))
            context.insert(DiscogsAccount(username: "fixture"))
            try context.save()
            return (placed.id, missing.id)
        }
        let schema = Schema(versionedSchema: LibrarySchemaV17.self)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = container.mainContext
        let copies = try context.fetch(FetchDescriptor<RecordCopy>())
        #expect(copies.count == 2)
        let placed = try #require(copies.first { $0.id == placedID })
        #expect(placed.shelf?.number == 1 && placed.positionInShelf == 1 && placed.release?.discogsID == 42)
        #expect(placed.shelf?.cabinet?.name == "Kallax")
        #expect(try context.fetch(FetchDescriptor<MissingCopyMark>()).map(\.copyID) == [missingID])
        #expect(try context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID) == [placedID])
        #expect(try context.fetchCount(FetchDescriptor<WantlistEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<DiscogsAccount>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SaleCopyMark>()) == 0)
        context.insert(SaleCopyMark(copyID: placedID))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<SaleCopyMark>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ReleaseVideoList>()) == 0)
        try ReleaseVideoList.store([ReleaseVideo(title: "Air - Sexy Boy", url: "https://www.youtube.com/watch?v=1")], for: 42, in: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<ReleaseVideoList>()).first?.videos.map(\.title) == ["Air - Sexy Boy"])
    }
    /// A V16 store (every store the released app wrote lately) opens as V17
    /// with its records, tracklists and sale marks; the new list starts empty.
    @Test func v16StoreMigratesToV17KeepingEverything() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Migration.store")
        let copyID: UUID = try autoreleasepool {
            let schema = Schema(versionedSchema: LibrarySchemaV16.self)
            let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                               configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = container.mainContext
            let release = Release(discogsID: 34491154, artist: "Rank 1", title: "Airwave")
            release.tracks = [Track(position: "A1", title: "Airwave (Original Mix)", duration: "8:23")]
            release.detailsFetchedAt = .now
            context.insert(release)
            let copy = RecordCopy(release: release, instanceID: 1, owner: "fixture")
            context.insert(copy)
            context.insert(SaleCopyMark(copyID: copy.id))
            try context.save()
            return copy.id
        }
        let schema = Schema(versionedSchema: LibrarySchemaV17.self)
        let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = container.mainContext
        let release = try #require(try context.fetch(FetchDescriptor<Release>()).first)
        #expect(release.tracks.map(\.title) == ["Airwave (Original Mix)"] && release.detailsFetchedAt != nil)
        #expect(release.copies.map(\.id) == [copyID])
        #expect(try context.fetch(FetchDescriptor<SaleCopyMark>()).map(\.copyID) == [copyID])
        #expect(try context.fetchCount(FetchDescriptor<ReleaseVideoList>()) == 0)
    }
    /// Popover and background download may store the videos of the same
    /// release at once, each in its own context: one row stays, no error.
    @Test func videoListsFromTwoContextsDontClash() throws {
        let c = try LibraryStorage.makeContainer(inMemory: true)
        let popover = ModelContext(c), download = ModelContext(c)
        let older = [ReleaseVideo(title: "A - B", url: "https://www.youtube.com/watch?v=1")]
        let newer = older + [ReleaseVideo(title: "A - C", url: "https://www.youtube.com/watch?v=2")]
        try ReleaseVideoList.store(older, for: 7, in: download)
        try ReleaseVideoList.store(newer, for: 7, in: popover)
        try popover.save()
        try download.save()
        let rows = try ModelContext(c).fetch(FetchDescriptor<ReleaseVideoList>())
        #expect(rows.count == 1)
        #expect(rows.first?.discogsID == 7)
        // And storing again updates the row instead of adding one.
        let again = ModelContext(c)
        try ReleaseVideoList.store(newer, for: 7, in: again)
        try again.save()
        #expect(try ModelContext(c).fetch(FetchDescriptor<ReleaseVideoList>()).map(\.videos) == [newer])
    }
    @Test func persistentStoreCanBeReopened() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: LibrarySchemaV17.self)
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Test.store"), cloudKitDatabase: .none)
        let id: UUID = try autoreleasepool {
            let first = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
            let shelf = Shelf(number: 4); first.mainContext.insert(shelf)
            let copy = try PositionService(context: first.mainContext).insert(release: Release(artist: "Kraftwerk", title: "Computerwelt"), shelf: shelf, position: 1)
            return copy.id
        }
        let reopened = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
        let copies = try reopened.mainContext.fetch(FetchDescriptor<RecordCopy>())
        #expect(copies.count == 1)
        #expect(copies.first?.id == id)
        let shelves = try reopened.mainContext.fetch(FetchDescriptor<Shelf>())
        let copy = try #require(copies.first)
        #expect(ShelfRangeLabels.location(of: copy, labels: ShelfRangeLabels.compute(for: shelves)) == "K · Position 1")
    }
}
