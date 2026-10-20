import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests.LibraryTests {
    @Test func assignedCopyDoesNotReappearInShelfAssignment() throws {
        let (container, shelves, service) = try fixture()
        let assigned = try add(service, shelves[0], "Already There")
        let elsewhere = try add(service, shelves[1], "In Another Shelf")
        let available = try add(service, shelves[1], "Still Available")
        // Only records in the Discogs collection are offered; a sold one never is.
        let sold = try add(service, shelves[1], "Sold")
        for copy in [assigned, elsewhere, available] { copy.discogsActive = true }
        sold.discogsActive = false
        try service.unplace(available)
        try service.unplace(sold)

        #expect(ShelfAssignmentPresentation.candidates(
                [assigned, elsewhere, available, sold], owner: nil, excluding: []
            ).map(\.id) == [available.id])

        let secondContext = ModelContext(container)
        let restoredCopies = try secondContext.fetch(FetchDescriptor<RecordCopy>())
        #expect(!(ShelfAssignmentPresentation.candidates(
                restoredCopies, owner: nil, excluding: []
            ).contains { $0.id == assigned.id }))
    }
    @Test func reservedShelfAndInvalidPositionDoNotMutate() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[1], "B")
        try service.configure(shelves[2], name: "Vivian", isReserved: true)
        #expect(throws: (any Error).self) { try service.move(b, to: shelves[2], position: 1) }
        #expect(b.shelf?.id == shelves[1].id)
        #expect(throws: (any Error).self) { try add(service, shelves[2], "C") }
        #expect(throws: (any Error).self) { try service.move(a, to: shelves[1], position: 5) }
        #expect(a.positionInShelf == 1)
        // Shelves have no size limit any more.
        for artist in (0..<120).map({ "Artist \($0)" }) { try add(service, shelves[0], artist) }
        #expect(shelves[0].copies.count == 121)
        // Only empty shelves can be reserved.
        #expect(throws: (any Error).self) { try service.configure(shelves[1], name: "", isReserved: true) }
        #expect(!shelves[1].isReserved)
    }
    @Test func excludedCopiesLeaveShelfAndAllocation() throws {
        let (container, shelves, service) = try fixture(); let context = container.mainContext
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B")
        let loose = try add(service, shelves[1], "Loose")
        try service.unplace(loose)

        try service.setExcluded([a, loose], true)
        #expect(a.shelf == nil)
        #expect(b.positionInShelf == 1)
        let excluded = Set(try context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID))
        #expect(excluded == [a.id, loose.id])
        #expect(ShelfAssignmentPresentation.candidates([a, b, loose], owner: nil, excluding: excluded).isEmpty)

        // Placing a copy again brings it back into the allocation.
        try service.move(a, to: shelves[2], position: 1)
        try service.setExcluded([loose], false)
        #expect(try context.fetch(FetchDescriptor<OptimizationExclusion>()).isEmpty)
    }
    @Test func missingMarkKeepsPlaceAndCanBeCleared() throws {
        let (container, shelves, service) = try fixture(); let context = container.mainContext
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B")

        try service.setMissing([b], true)
        try service.setMissing([b], true)
        #expect(try context.fetch(FetchDescriptor<MissingCopyMark>()).map(\.copyID) == [b.id])
        #expect(b.shelf?.id == shelves[0].id && b.positionInShelf == 2)
        #expect(a.positionInShelf == 1)

        try service.setMissing([b], false)
        #expect(try context.fetch(FetchDescriptor<MissingCopyMark>()).isEmpty)
    }
    @Test func saleMarkKeepsPlaceUntilAllAreSold() throws {
        let (container, shelves, service) = try fixture(); let context = container.mainContext
        let sale = { Set(try context.fetch(FetchDescriptor<SaleCopyMark>()).map(\.copyID)) }
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B")
        let c = try add(service, shelves[0], "C")
        let d = try add(service, shelves[1], "D")

        // Marking twice is one mark; the record stays where it stands.
        try service.setForSale([a, c, d], true)
        try service.setForSale([c], true)
        #expect(try sale() == [a.id, c.id, d.id])
        #expect(c.shelf?.id == shelves[0].id && c.positionInShelf == 3)
        try service.setForSale([d], false)
        #expect(try sale() == [a.id, c.id])
        #expect(d.shelf?.id == shelves[1].id)

        // "Verkauft": out of the shelves, kept out, list emptied; the rest moves up.
        try service.setMissing([a], true)
        try service.sellAllForSale()
        #expect(try sale().isEmpty)
        #expect(a.shelf == nil && c.shelf == nil)
        #expect(b.shelf?.id == shelves[0].id && b.positionInShelf == 1)
        #expect(d.shelf?.id == shelves[1].id && d.positionInShelf == 1)
        #expect(Set(try context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID)) == [a.id, c.id])
        #expect(try context.fetch(FetchDescriptor<MissingCopyMark>()).isEmpty)
    }
    @Test func missingMarkFollowsShelfActions() throws {
        let (container, shelves, service) = try fixture(); let context = container.mainContext
        let marks = { Set(try context.fetch(FetchDescriptor<MissingCopyMark>()).map(\.copyID)) }
        let a = try add(service, shelves[0], "A")
        let b = try add(service, shelves[0], "B")
        let c = try add(service, shelves[0], "C")
        try service.setMissing([a, b, c], true)

        // Taking it out or moving it around (undo, quick editor) keeps the mark.
        try service.unplace(a)
        try service.move(a, to: shelves[0], position: 1)
        #expect(try marks() == [a.id, b.id, c.id])
        // Sorted in by hand: found.
        try service.unplace(a)
        try service.move(a, to: shelves[1], position: 1, found: true)
        #expect(try marks() == [b.id, c.id])
        // "Ohne Regalplatz" and deleting leave nothing to look for.
        try service.setExcluded([b], true)
        try service.delete(c)
        #expect(try marks().isEmpty)
    }
    @Test func copiesOfAnotherAccountCountAsLeftCollection() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let current = try add(service, shelves[0], "Current")
        current.discogsOwner = "me"; current.discogsActive = true
        let other = try add(service, shelves[0], "Other")
        other.discogsOwner = "old"; other.discogsActive = true
        let sold = try add(service, shelves[0], "Sold")
        sold.discogsOwner = "me"; sold.discogsActive = false

        #expect(current.isInCurrentCollection(owner: "me"))
        #expect(!other.isInCurrentCollection(owner: "me"))
        #expect(other.leftCurrentCollection(owner: "me"))
        #expect(sold.leftCurrentCollection(owner: "me"))
        // Without a synced account, every active copy counts.
        #expect(other.isInCurrentCollection(owner: nil))

        try service.unplace([current, other])
        #expect(ShelfAssignmentPresentation.candidates([current, other], owner: "me", excluding: []).map(\.id) == [current.id])
    }
}
