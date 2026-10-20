import AppKit
import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests.LibraryTests {
    @Test func placementAndShelfSortShareOneKey() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let abba = try add(service, shelves[0], "Abba")
        let zappa = try add(service, shelves[0], "Zappa")
        let loose = try add(service, shelves[1], " Beatles")
        try service.unplace(loose)
        // Leading spaces are ignored alike: between Abba and Zappa, where
        // "Fach sortieren" would put it too.
        #expect(AlphabeticalPlacement.position(for: loose, in: shelves[0]) == 2)
        try service.move(loose, to: shelves[0], position: 3)
        try service.sortAlphabetically(shelves[0])
        #expect(service.ordered(shelves[0]).map(\.id) == [abba.id, loose.id, zappa.id])
    }
    @Test func shelfNameAndReservationAreStored() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let shelf = shelves[8]
        try service.configure(shelf, name: "  Vivian ", isReserved: true)
        #expect(shelf.name == "Vivian")
        #expect(shelf.isReserved)
    }
    @Test func deletionCompactsAndPreservesOtherCopyOfRelease() throws {
        let (container, shelves, service) = try fixture()
        let a = try add(service, shelves[0], "A")
        let release = try #require(a.release)
        let b = try service.insert(release: release, shelf: shelves[0], position: 2)
        try service.delete(a)
        #expect(b.positionInShelf == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Release>()) == 1)
        try service.delete(b)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Release>()) == 0)
    }
    @Test func coverGridGroupsCopiesWithoutChangingCollectionItems() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let first = try add(service, shelves[0], "Artist", "Record")
        let release = try #require(first.release)
        release.discogsID = 42
        let second = try service.insert(release: release, shelf: shelves[1], position: 1)
        let sameDiscogsRelease = Release(artist: "Artist", title: "Record")
        sameDiscogsRelease.discogsID = 42
        let third = try service.insert(release: sameDiscogsRelease, shelf: shelves[2], position: 1)
        let separateLocalRelease = try add(service, shelves[3], "Artist", "Record")
        let items = [first, second, third, separateLocalRelease]

        let groups = CollectionCoverGroup.make(from: items)
        #expect(groups.count == 2)
        #expect(groups[0].copies.map(\.id) == [first.id, second.id, third.id])
        #expect(groups[1].copies.map(\.id) == [separateLocalRelease.id])
        #expect(items.count == 4)
    }
    @Test func shelfCoverSnapshotKeepsPhysicalCopiesStatusesAndCurrentLocations() throws {
        let (container, shelves, service) = try fixture()
        let context = container.mainContext
        let release = Release(discogsID: 42, artist: "Artist", title: "Record")
        // Created first, but physically second: shelf order must win over creation order.
        let second = try service.insert(release: release, shelf: shelves[0], position: 1, owner: "old")
        let first = try service.insert(release: release, shelf: shelves[0], position: 1, owner: "me")
        let unknown = try service.insert(release: Release(discogsID: 43, artist: "", title: ""),
                                         shelf: shelves[0], position: 3, owner: "me") {
            $0.discogsActive = false
        }
        let withoutRelease = try service.insert(release: Release(discogsID: 44, artist: "Lost", title: "Metadata"),
                                                shelf: shelves[0], position: 4, owner: "me")
        try service.save { withoutRelease.release = nil }
        try service.setMissing([second], true)
        let missing = Set(try context.fetch(FetchDescriptor<MissingCopyMark>()).map(\.copyID))

        let items = ShelfCopyItem.snapshot(for: shelves[0], owner: "me", missing: missing, forSale: [])
        try #require(items.count == 4)
        #expect(items.map(\.id) == [first.id, second.id, unknown.id, withoutRelease.id])
        #expect(items.map(\.position) == [1, 2, 3, 4])
        #expect(items.map(\.missing) == [false, true, false, false])
        #expect(items.map(\.sold) == [false, true, true, false])
        #expect(items[0].copy === first && items[1].copy === second)
        #expect(items[0].artist == "Artist" && items[1].title == "Record")
        #expect(items[2].artist == "Unbekannter Interpret" && items[2].title == "Release #43")
        #expect(items[2].year == 0 && items[2].genre.isEmpty)
        #expect(items[3].artist == "—" && items[3].title == "—")
        #expect(items[3].year == 0 && items[3].genre.isEmpty)

        // Without a synced account, active copies from any owner count as current.
        let withoutAccount = ShelfCopyItem.snapshot(for: shelves[0], owner: nil, missing: missing, forSale: [])
        #expect(withoutAccount.map(\.sold) == [false, false, true, false])

        try service.move(second, to: shelves[1], position: 1)
        let source = ShelfCopyItem.snapshot(for: shelves[0], owner: "me", missing: missing, forSale: [])
        #expect(source.map(\.id) == [first.id, unknown.id, withoutRelease.id])
        #expect(source.map(\.position) == [1, 2, 3])
        #expect(source.allSatisfy { !$0.missing })
        let destination = ShelfCopyItem.snapshot(for: shelves[1], owner: "me", missing: missing, forSale: [])
        #expect(destination.map(\.id) == [second.id])
        #expect(destination.map(\.position) == [1])
        #expect(destination.first?.missing == true && destination.first?.sold == true)
    }
    @Test func shelfLabelSortUsesDisplayNamesWithoutChangingPhysicalPositions() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let zetaRelease = Release(discogsID: 42, artist: "Artist", title: "First")
        zetaRelease.label = "Zeta (2), Acme (4)"
        let first = try service.insert(release: zetaRelease, shelf: shelves[0], position: 1)
        let alphaRelease = Release(discogsID: 43, artist: "Artist", title: "Second")
        alphaRelease.label = "Alpha (17), Kontor Records (Germany)"
        let second = try service.insert(release: alphaRelease, shelf: shelves[0], position: 2)
        let unknown = try service.insert(release: Release(discogsID: 44, artist: "", title: ""),
                                         shelf: shelves[0], position: 3)
        let withoutRelease = try service.insert(release: Release(discogsID: 45, artist: "Lost", title: "Metadata"),
                                                shelf: shelves[0], position: 4)
        try service.save { withoutRelease.release = nil }

        let items = ShelfCopyItem.snapshot(for: shelves[0], owner: nil, missing: [], forSale: [])
        #expect(items.map(\.label) == ["Zeta, Acme", "Alpha, Kontor Records (Germany)", "", ""])
        #expect(zetaRelease.label == "Zeta (2), Acme (4)")
        let sorted = items.sorted(using: [KeyPathComparator(\ShelfCopyItem.label), KeyPathComparator(\ShelfCopyItem.position)])
        #expect(sorted.map(\.id) == [unknown.id, withoutRelease.id, second.id, first.id])
        #expect(sorted.map(\.position) == [3, 4, 2, 1])
        #expect(sorted.allSatisfy { $0.id == $0.copy.id && $0.position == $0.copy.positionInShelf })
        let physicalIDs = service.ordered(shelves[0]).map(\.id)
        let expectedPhysicalIDs: [UUID] = [first.id, second.id, unknown.id, withoutRelease.id]
        #expect(physicalIDs == expectedPhysicalIDs)
    }
    @Test func alphabeticalSortAndSearchAcrossWords() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let z = try add(service, shelves[0], "ZZ Top")
        let k = try add(service, shelves[0], "kraftwerk", "Computerwelt")
        let d = try add(service, shelves[0], "Depeche Mode", "Violator")
        #expect(SortingService.sorted([z, k, d]).map(\.id) == [d.id, k.id, z.id])
        let index = SearchIndex([z, k, d], id: \.id, text: SortingService.searchText)
        #expect(index.matches(d.id, SearchIndex<UUID>.words("depeche violator")))
        #expect(!index.matches(k.id, SearchIndex<UUID>.words("violator")))
        try service.sortAlphabetically(shelves[0])
        #expect(service.ordered(shelves[0]).map(\.id) == [d.id, k.id, z.id])
    }
    @Test func sortCheckMovesFewestRecordsInTargetOrder() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let a = try add(service, shelves[0], "Air")
        let c = try add(service, shelves[0], "Cure")
        let b = try add(service, shelves[0], "Björk")
        let d = try add(service, shelves[0], "Daft Punk")
        let steps = ShelfSortCheck.steps(service.ordered(shelves[0]), by: .title)
        // One record out of place: the rest already runs A, B, D.
        #expect(steps.count == 1)
        #expect(steps.first?.copy.id == c.id)
        #expect(steps.first?.position == 2)
        #expect(steps.first?.before?.id == b.id)
        #expect(steps.first?.after?.id == d.id)
        _ = a
        try service.sortAlphabetically(shelves[0], by: .title)
        #expect(ShelfSortCheck.steps(service.ordered(shelves[0]), by: .title).isEmpty)
    }
    /// Two copies of one album: either order is right, whatever their IDs.
    @Test func sortCheckKeepsEqualRecordsInPlace() throws {
        for _ in 0..<8 {
            let (container, shelves, service) = try fixture(); _ = container
            let first = try add(service, shelves[0], "Moby", "Play")
            let second = try add(service, shelves[0], "Moby", "Play")
            let air = try add(service, shelves[0], "Air")
            let steps = ShelfSortCheck.steps(service.ordered(shelves[0]), by: .title)
            #expect(steps.map(\.copy.id) == [air.id])
            try service.sortAlphabetically(shelves[0], by: .title)
            #expect(service.ordered(shelves[0]).map(\.id) == [air.id, first.id, second.id])
        }
    }
    @Test func sortCheckByYearWithinArtist() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let newer = try add(service, shelves[0], "Kraftwerk", "Autobahn")
        newer.release?.year = 1990
        let older = try add(service, shelves[0], "Kraftwerk", "Computerwelt")
        older.release?.year = 1981
        #expect(ShelfSortCheck.steps(service.ordered(shelves[0]), by: .title).isEmpty)
        #expect(ShelfSortCheck.steps(service.ordered(shelves[0]), by: .year).count == 1)
        try service.sortAlphabetically(shelves[0], by: .year)
        #expect(service.ordered(shelves[0]).map(\.id) == [older.id, newer.id])
    }
    /// Without a year or label a record goes behind the artist's others,
    /// and labels starting with a digit stay in front of the letters.
    @Test func recordsWithoutYearOrLabelSortBehindTheOthers() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let undated = try add(service, shelves[0], "Kraftwerk", "Autobahn")
        undated.release?.year = nil
        let dated = try add(service, shelves[0], "Kraftwerk", "Computerwelt")
        dated.release?.year = 1981
        #expect(ShelfSortCheck.sortedCopies(shelves[0].copies, by: .year).map(\.id) == [dated.id, undated.id])

        let unlabelled = try add(service, shelves[1], "Pixies", "Bossanova")
        unlabelled.release?.label = ""
        let letters = try add(service, shelves[1], "Pixies", "Doolittle")
        letters.release?.label = "Elektra"
        let digits = try add(service, shelves[1], "Pixies", "Surfer Rosa")
        digits.release?.label = "4AD"
        #expect(ShelfSortCheck.sortedCopies(shelves[1].copies, by: .label).map(\.id) == [digits.id, letters.id, unlabelled.id])
    }
    @Test func alphabetNavigationNormalizesArtistsAndGroupsNonLetters() {
        #expect(SortingService.alphabetNavigationSymbols.first == "#")
        #expect(SortingService.alphabetNavigationSymbols.count == 27)
        #expect(SortingService.alphabetSection(for: "  Ätna") == "A")
        #expect(SortingService.alphabetSection(for: "kraftwerk") == "K")
        #expect(SortingService.alphabetSection(for: "4 Strings") == "#")
        #expect(SortingService.alphabetSection(for: "") == "#")
        #expect(SortingService.alphabetSection(for: "Øystein Sevåg") == "O")
        #expect(SortingService.alphabetSection(for: "Æther") == "A")
        #expect(SortingService.alphabetSection(for: "Łona") == "L")
        #expect(SortingService.alphabetSection(for: "Кино") == "#")
    }
    @Test func collectionOrderFollowsAlphabetSections() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let names = ["Zappa", "Þeyr", "Кино", "10cc", "Abba", "Øystein", "Pink Floyd", " Beatles"]
        let copies = try names.map { try add(service, shelves[0], $0) }
        let sorted = SortingService.sortedByAlphabetSection(copies)
        let sections = sorted.map { SortingService.alphabetSection(for: $0.release?.displayArtist ?? "") }
        let order = SortingService.alphabetNavigationSymbols
        // Every record sits in its index section, in index order.
        #expect(sections == sections.sorted { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! })
        #expect(sections.first == "#")
        #expect(sorted.map { $0.release!.artist }.firstIndex(of: " Beatles")! > sorted.map { $0.release!.artist }.firstIndex(of: "Abba")!)
    }
    @Test func searchFoldsSharpSAndCoversYear() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let copy = try add(service, shelves[0], "Kraftwerk", "Straße")
        copy.release?.year = 1979
        let index = SearchIndex([copy], id: \.id, text: SortingService.searchText)
        #expect(index.matches(copy.id, SearchIndex<UUID>.words("strasse")))
        #expect(index.matches(copy.id, SearchIndex<UUID>.words("Straße 1979")))
        #expect(!index.matches(copy.id, SearchIndex<UUID>.words("1980")))
    }
    /// Letters without a decomposable accent are found with the plain one.
    @Test func searchFoldsLatinLettersWithoutAccentMarks() throws {
        let (container, shelves, service) = try fixture(); _ = container
        let mo = try add(service, shelves[0], "MØ", "Forever Neverland")
        let lona = try add(service, shelves[0], "Łona", "Album")
        let index = SearchIndex([mo, lona], id: \.id, text: SortingService.searchText)
        #expect(index.matches(mo.id, SearchIndex<UUID>.words("mo forever")))
        #expect(index.matches(mo.id, SearchIndex<UUID>.words("Mø")))
        #expect(index.matches(lona.id, SearchIndex<UUID>.words("lona")))
        #expect(!index.matches(lona.id, SearchIndex<UUID>.words("mo")))
    }
}
