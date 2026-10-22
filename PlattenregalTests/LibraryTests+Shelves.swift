import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests.LibraryTests {
    /// The pages' shared lists follow records saved in another context
    /// (the sync), and the main context takes values saved there – the
    /// pages no longer fetch everything again after each save.
    @Test @MainActor func sharedRecordsFollowSavesFromOtherContexts() throws {
        let container = try LibraryStorage.makeContainer(inMemory: true)
        let records = LibraryRecords.of(container.mainContext)
        #expect(records.copies.isEmpty)
        let other = ModelContext(container)
        let release = Release(artist: "Moby", title: "Play")
        other.insert(release)
        other.insert(RecordCopy(release: release, instanceID: 1, owner: "test"))
        try other.save()
        #expect(records.copies.count == 1)
        let shown = try #require(records.copies.first?.release)
        #expect(shown.title == "Play")
        release.title = "Play (Remastered)"
        release.tracks = [Track(position: "A1", title: "Porcelain", duration: "")]
        try other.save()
        #expect(shown.title == "Play (Remastered)")
        #expect(shown.tracks.map(\.title) == ["Porcelain"])
        // Gone in the other context: gone from the list.
        for copy in try other.fetch(FetchDescriptor<RecordCopy>()) { other.delete(copy) }
        try other.save()
        #expect(records.copies.isEmpty)
    }

    /// A released container's lists don't take a new container's saves for
    /// their own, even at the same address (crash report of 08.10.2026).
    @Test @MainActor func sharedRecordsOfReleasedContainersStayOut() throws {
        for _ in 0..<40 {
            try autoreleasepool {
                let container = try LibraryStorage.makeContainer(inMemory: true)
                _ = LibraryRecords.of(container.mainContext)
            }
        }
        let container = try LibraryStorage.makeContainer(inMemory: true)
        let records = LibraryRecords.of(container.mainContext)
        let release = Release(artist: "Moby", title: "Play")
        container.mainContext.insert(release)
        container.mainContext.insert(RecordCopy(release: release, instanceID: 1, owner: "test"))
        try container.mainContext.save()
        #expect(records.copies.count == 1)
    }

    /// The collection's index follows tracklists, new records and its own page's rebuilds.
    @Test func sharedSearchIndexFollowsChanges() throws {
        let container = try LibraryStorage.makeContainer(inMemory: true)
        let context = container.mainContext
        let service = PositionService(context: context)
        let first = try service.insert(release: Release(artist: "Moby", title: "Play"), shelf: nil)
        // A fresh state, whatever other tests built before.
        LibraryChanges.shared.libraryDidChange()
        func index() throws -> SearchIndex<UUID> {
            let copies = try context.fetch(FetchDescriptor<RecordCopy>())
            return LibrarySearchIndexes.shared.collection(copies)
        }
        #expect(try index().matches(first.id, ["moby"]))
        #expect(try !index().matches(first.id, ["porcelain"]))
        first.release?.tracks = [Track(position: "A1", title: "Porcelain", duration: "")]
        LibraryChanges.shared.tracksDidChange()
        #expect(try index().matches(first.id, ["porcelain"]))
        let second = try service.insert(release: Release(artist: "Air", title: "Moon Safari"), shelf: nil)
        #expect(try index().matches(second.id, ["safari"]))
        // Changed without any report (e.g. read before the page saw it): a page rebuild catches up.
        second.release?.label = "Source"
        #expect(try !index().matches(second.id, ["source"]))
        // The wantlist's rebuild leaves the collection's index alone; its own page's catches up.
        LibrarySearchIndexes.shared.invalidate(.wantlist)
        #expect(try !index().matches(second.id, ["source"]))
        LibrarySearchIndexes.shared.invalidate(.collection)
        #expect(try index().matches(second.id, ["source"]))
    }
    /// Kept ends give the same labels as computing everything afresh, also after moves.
    @Test func cachedShelfLabelsMatchFullComputation() throws {
        let container = try LibraryStorage.makeContainer(inMemory: true)
        let context = container.mainContext
        let shelves = try context.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\.number)]))
        let service = PositionService(context: context)
        for (index, artist) in ["Air", "Bjork", "Cher", "Daft Punk"].enumerated() {
            try service.insert(release: Release(artist: artist, title: "X"), shelf: shelves[index / 2], position: index % 2 + 1)
        }
        let cache = ShelfLabelsCache()
        #expect(cache.labels(for: shelves, style: .range).labels == ShelfRangeLabels.compute(for: shelves, style: .range).labels)
        let cher = try #require(shelves[1].copies.first { $0.release?.artist == "Cher" })
        try service.move(cher, to: shelves[0], position: 3)
        let moved = cache.labels(for: shelves, style: .range).labels
        #expect(moved == ShelfRangeLabels.compute(for: shelves, style: .range).labels)
        #expect(moved[shelves[1].id] == "D")
    }
    @Test func shelfGeometry() throws {
        let (container, shelves, _) = try fixture(); _ = container
        #expect(shelves.count == 12)
        #expect(shelves.map(\.number) == Array(1...12))
        #expect(shelves[4].row == 2); #expect(shelves[4].column == 1)
        #expect(shelves[11].row == 3); #expect(shelves[11].column == 4)
    }
    @Test func insertionBetweenCopies() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "A")
        let c = try add(service, shelves[0], "C")
        let b = try add(service, shelves[0], "B", at: 2)
        #expect(service.ordered(shelves[0]).map(\.id) == [a.id, b.id, c.id])
        #expect(service.ordered(shelves[0]).map(\.positionInShelf) == [1, 2, 3])
    }
    @Test func moveWithinAndAcrossShelves() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B")
        let c = try add(service, shelves[0], "C")
        try service.move(c, to: shelves[0], position: 1)
        #expect(service.ordered(shelves[0]).map(\.id) == [c.id, a.id, b.id])
        try service.move(a, to: shelves[1], position: 1)
        #expect(service.ordered(shelves[0]).map(\.positionInShelf) == [1, 2])
        #expect(service.ordered(shelves[1]).map(\.id) == [a.id])
        #expect(ShelfRangeLabels.location(of: a, labels: ShelfRangeLabels.compute(for: shelves)) == "A · Position 1")
    }
    /// One artist across shelves: numbered by title (as sorting in sees
    /// them), then by place in the rack – never by the order they come in.
    @Test func labelsOfShelvesStartingAlikeAreStable() throws {
        let (container, shelves, service) = try fixture(); _ = container
        try add(service, shelves[2], "The Beatles", "Let It Be")
        try add(service, shelves[6], "The Beatles", "Abbey Road")
        try add(service, shelves[4], "The Beatles", "Abbey Road")
        for input in [shelves, shelves.reversed(), shelves.shuffled()] {
            let labels = ShelfRangeLabels.compute(for: Array(input))
            #expect(labels[shelves[4].id] == "Th · 1")
            #expect(labels[shelves[6].id] == "Th · 2")
            #expect(labels[shelves[2].id] == "Th · 3")
        }
    }
    @Test func shelfContentCacheMatchesAFullRecompute() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let can = try add(service, shelves[0], "Can", "Tago Mago")
        try add(service, shelves[0], "Björk", "Post")
        try add(service, shelves[1], "Moby", "Play")
        let cache = ShelfContentCache()
        func matchesFullRecompute(version: Int = 0) -> Bool {
            cache.refresh(shelves, version: version)
            let cached = ShelfRangeLabels.compute(for: shelves, ends: cache.ends)
            let full = ShelfRangeLabels.compute(for: shelves)
            return shelves.allSatisfy { shelf in
                let stats = cache.stats(for: shelf), fresh = ShelfStatistics(shelf: shelf)
                return cached[shelf.id] == full[shelf.id] && stats.count == fresh.count
            }
        }
        #expect(matchesFullRecompute())
        #expect(ShelfRangeLabels.compute(for: shelves, ends: cache.ends)[shelves[1].id] == "M")
        // Sorting in changes both shelves involved; both are read again.
        try service.move(can, to: shelves[1], position: 1)
        #expect(matchesFullRecompute())
        #expect(ShelfRangeLabels.compute(for: shelves, ends: cache.ends)[shelves[1].id] == "C – M")
        // Metadata is followed via the library version, like on the shelf
        // page; every write path reports it (here: as a sync would).
        can.release?.artist = "Zapp"
        LibraryChanges.shared.libraryDidChange()
        #expect(matchesFullRecompute(version: LibraryChanges.shared.libraryVersion))
        #expect(ShelfRangeLabels.compute(for: shelves, ends: cache.ends)[shelves[1].id] == "M – Z")
    }
}
