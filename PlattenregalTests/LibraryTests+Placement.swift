import SwiftUI
import Foundation
import Testing
@testable import Plattenregal

extension AllTests.LibraryTests {
    @Test func alphabeticalPositionInsideShelf() throws {
        let (container, shelves, service) = try fixture(); let context = container.mainContext
        try add(service, shelves[0], "Abba")
        try add(service, shelves[0], "Can")
        let loose = RecordCopy(release: Release(artist: "Beck", title: "Odelay"), instanceID: 1, owner: "fixture", shelf: nil, position: 0)
        context.insert(loose)
        #expect(AlphabeticalPlacement.position(for: loose, in: shelves[0]) == 2)
        let last = RecordCopy(release: Release(artist: "Zappa", title: "Album"), instanceID: 1, owner: "fixture", shelf: nil, position: 0)
        context.insert(last)
        #expect(AlphabeticalPlacement.position(for: last, in: shelves[0]) == 3)
        #expect(AlphabeticalPlacement.position(for: last, in: shelves[1]) == 1)
    }
    @Test func rackPlacementFollowsAlphabeticalRunOfShelves() throws {
        let (container, shelves, service) = try fixture(); let context = container.mainContext
        // Physical order differs from the alphabet: shelf 9 starts it, shelf 2 continues.
        let abba = try add(service, shelves[8], "Abba")
        let can = try add(service, shelves[8], "Can")
        let daft = try add(service, shelves[1], "Daft Punk")
        let moby = try add(service, shelves[1], "Moby")
        try service.configure(shelves[4], name: "Deko", isReserved: true)
        func loose(_ artist: String) -> RecordCopy {
            let copy = RecordCopy(release: Release(artist: artist, title: "Album"), instanceID: 1, owner: "fixture", shelf: nil, position: 0)
            context.insert(copy)
            return copy
        }

        let inside = AlphabeticalPlacement.spots(for: loose("Beck"), in: shelves)
        #expect(inside.count == 1)
        #expect(inside[0].shelf.id == shelves[8].id && inside[0].position == 2)
        #expect(inside[0].before?.id == abba.id && inside[0].after?.id == can.id)

        // Between two shelves: end of the first and start of the next both fit.
        let boundary = AlphabeticalPlacement.spots(for: loose("Cure"), in: shelves)
        #expect(boundary.map(\.shelf.id) == [shelves[8].id, shelves[1].id])
        #expect(boundary.map(\.position) == [3, 1])
        #expect(boundary.allSatisfy { $0.before?.id == can.id && $0.after?.id == daft.id })

        let first = AlphabeticalPlacement.spots(for: loose("2raumwohnung"), in: shelves)
        #expect(first.count == 1 && first[0].shelf.id == shelves[8].id && first[0].position == 1)
        #expect(first[0].before == nil && first[0].after?.id == abba.id)

        let last = AlphabeticalPlacement.spots(for: loose("Zappa"), in: shelves)
        #expect(last.count == 1 && last[0].shelf.id == shelves[1].id && last[0].position == 3)
        #expect(last[0].before?.id == moby.id && last[0].after == nil)

        // "Platte hinzufügen" asks for many records at once: the same shelves as `spots`.
        let batch = ["Beck", "Cure", "2raumwohnung", "Zappa", "Mouse on Mars"].map(loose)
        let fitting = AlphabeticalPlacement.fittingShelves(for: batch, in: shelves)
        for copy in batch {
            #expect(fitting[copy.id]?.map(\.id) == AlphabeticalPlacement.spots(for: copy, in: shelves).map(\.shelf.id))
        }
        #expect(AlphabeticalPlacement.fittingShelves(for: batch, in: [shelves[4]]).isEmpty)

        // A copy that already stands somewhere doesn't count as its own neighbour.
        let again = AlphabeticalPlacement.spots(for: can, in: shelves)
        #expect(again.count == 2 && again[0].position == 2 && again[0].before?.id == abba.id)
    }
    @Test func currentSpotOfPlacedCopyShowsItsNeighbours() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let abba = try add(service, shelves[8], "Abba")
        let can = try add(service, shelves[8], "Can")
        let daft = try add(service, shelves[1], "Daft Punk")
        let moby = try add(service, shelves[1], "Moby")

        let middle = try #require(AlphabeticalPlacement.current(for: daft, in: shelves))
        #expect(middle.shelf.id == shelves[1].id && middle.position == 1)
        // First in its shelf: the left neighbour is the last record of the shelf before it.
        #expect(middle.before?.id == can.id && middle.after?.id == moby.id)

        let end = try #require(AlphabeticalPlacement.current(for: moby, in: shelves))
        #expect(end.position == 2 && end.before?.id == daft.id && end.after == nil)

        let start = try #require(AlphabeticalPlacement.current(for: abba, in: shelves))
        #expect(start.before == nil && start.after?.id == can.id)

        // Alone in its shelf: both neighbours come from the shelves around it.
        let zappa = try add(service, shelves[3], "Zappa")
        let kraftwerk = try add(service, shelves[5], "Kraftwerk")
        let alone = try #require(AlphabeticalPlacement.current(for: kraftwerk, in: shelves))
        #expect(alone.before?.id == moby.id && alone.after?.id == zappa.id)

        try service.unplace(abba)
        #expect(AlphabeticalPlacement.current(for: abba, in: shelves) == nil)
    }
    /// Sorting in and the compartment contents keep what they read of the
    /// releases; a sync that renames an artist must reach both.
    @Test func placementAndShelfContentsFollowChangedMetadata() throws {
        let (container, shelves, service) = try fixture(); let context = container.mainContext
        try add(service, shelves[8], "Abba")
        let can = try add(service, shelves[8], "Can")
        try add(service, shelves[1], "Daft Punk")
        let loose = try service.insert(release: Release(artist: "Beck", title: "Odelay"), shelf: nil)
        LibraryChanges.shared.libraryDidChange()
        #expect(AlphabeticalPlacement.spots(for: loose, in: shelves).map(\.position) == [2])
        #expect(ShelfCopyItem.snapshot(for: shelves[8], owner: nil, missing: [], forSale: []).map(\.artist) == ["Abba", "Can"])

        // The sync renames "Can" to "Aaron": the loose record now comes after
        // the whole shelf, at the boundary to the next one.
        can.release?.artist = "Aaron"
        try context.save()
        LibraryChanges.shared.syncDidCommit()
        #expect(AlphabeticalPlacement.spots(for: loose, in: shelves).map(\.position) == [3, 1])
        #expect(AlphabeticalPlacement.fittingShelves(for: [loose], in: shelves)[loose.id]?.map(\.id) == [shelves[8].id, shelves[1].id])
        #expect(ShelfCopyItem.snapshot(for: shelves[8], owner: nil, missing: [], forSale: []).map(\.artist) == ["Abba", "Aaron"])
    }
    @Test func rackPlacementNeedsAnOccupiedShelf() throws {
        let (container, shelves, _) = try fixture(); let context = container.mainContext
        let copy = RecordCopy(release: Release(artist: "Beck", title: "Odelay"), instanceID: 1, owner: "fixture", shelf: nil, position: 0)
        context.insert(copy)
        #expect(AlphabeticalPlacement.spots(for: copy, in: shelves).isEmpty)
    }
    @Test func rangeLabelsDeriveFromContentsAndDisambiguateBoundaries() throws {
        let (container, shelves, service) = try fixture(); _ = container
        for artist in ["2raumwohnung", "Abba", "Beck"] { try add(service, shelves[0], artist) }
        for artist in ["Dj Koze", "Excess"] { try add(service, shelves[1], artist) }
        for artist in ["Exos", "Faithless"] { try add(service, shelves[2], artist) }
        for artist in ["Moby", "Muse"] { try add(service, shelves[3], artist) }
        for artist in ["Cerrone", "Dido"] { try add(service, shelves[5], artist) }
        try service.configure(shelves[4], name: "Vivian", isReserved: true)

        let labels = ShelfRangeLabels.compute(for: shelves)
        #expect(labels[shelves[0].id] == "0 – B")
        #expect(labels[shelves[5].id] == "C – Di")
        #expect(labels[shelves[1].id] == "Dj – Ex")
        #expect(labels[shelves[2].id] == "Ex – F")
        #expect(labels[shelves[3].id] == "M")
        #expect(labels[shelves[4].id] == nil)
        #expect(labels[shelves[6].id] == nil)
    }
    @Test func rangeBoundaryLabels() {
        #expect(ShelfRangeLabels.boundaryLabel("DAFTPUNK", against: nil) == "D")
        #expect(ShelfRangeLabels.boundaryLabel("EXCESS", against: "EXOS") == "Ex")
        #expect(ShelfRangeLabels.boundaryLabel("2RAUMWOHNUNG", against: nil) == "0")
        #expect(ShelfRangeLabels.boundaryLabel("!!!", against: nil) == "#")
        #expect(ShelfRangeLabels.letters("Ëx-Otago\tAlbum") == "EXOTAGO")
        #expect(ShelfRangeLabels.letters("Øystein Sevåg\tAlbum") == "OYSTEINSEVAG")
    }
    @Test func identicalRangeLabelsGetARunningNumber() throws {
        let (container, shelves, service) = try fixture(); _ = container
        for artist in ["The Beatles", "The Cure"] { try add(service, shelves[0], artist) }
        for artist in ["The Doors", "The Hives"] { try add(service, shelves[1], artist) }
        for artist in ["The Who", "The Xx"] { try add(service, shelves[2], artist) }
        for artist in ["Underworld"] { try add(service, shelves[3], artist) }

        let labels = ShelfRangeLabels.compute(for: shelves)
        #expect(labels[shelves[0].id] == "Th · 1")
        #expect(labels[shelves[1].id] == "Th · 2")
        #expect(labels[shelves[2].id] == "Th · 3")
        #expect(labels[shelves[3].id] == "U")
    }
}
