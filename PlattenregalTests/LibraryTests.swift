import AppKit
import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

/// Parent of all suites. Serialized like XCTest was: the suites share
/// URLProtocol stubs and app singletons.
@Suite(.serialized) enum AllTests {}

extension AllTests {
    struct LibraryTests {
        private func fixture() throws -> (ModelContainer, [Shelf], PositionService) {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let shelves = try container.mainContext.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
            return (container, shelves, PositionService(context: container.mainContext))
        }
        @discardableResult private func add(_ service: PositionService, _ shelf: Shelf, _ artist: String, _ title: String = "Album", at position: Int? = nil) throws -> RecordCopy {
            try service.insert(release: Release(artist: artist, title: title), shelf: shelf, position: position ?? shelf.copies.count + 1)
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
                    return cached[shelf.id] == full[shelf.id] && stats.count == fresh.count && stats.spineStyles == fresh.spineStyles
                }
            }
            #expect(matchesFullRecompute())
            #expect(ShelfRangeLabels.compute(for: shelves, ends: cache.ends)[shelves[1].id] == "M")
            // Sorting in changes both shelves involved; both are read again.
            try service.move(can, to: shelves[1], position: 1)
            #expect(matchesFullRecompute())
            #expect(ShelfRangeLabels.compute(for: shelves, ends: cache.ends)[shelves[1].id] == "C – M")
            // Metadata is followed via the library version, like on the shelf page.
            can.release?.artist = "Zapp"
            #expect(matchesFullRecompute(version: 1))
            #expect(ShelfRangeLabels.compute(for: shelves, ends: cache.ends)[shelves[1].id] == "M – Z")
        }
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
            // "Nicht im Regal" and deleting leave nothing to look for.
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
        @Test func errorsReachTheUserInPlainGerman() {
            // The app's own errors keep their text.
            #expect(LibraryError.reserved.userMessage == LibraryError.reserved.errorDescription)
            #expect(DiscogsError.offline.userMessage == DiscogsError.offline.errorDescription)
            // System errors never show their English wording or codes.
            let saveFailure = NSError(domain: NSCocoaErrorDomain, code: 134030)
            #expect(saveFailure.userMessage == ErrorMessages.saveFailed)
            // A failed "Vermisst" names the action instead of a general save error.
            let mark = LibraryError.missingMarkNotSaved(found: false, saveFailure).userMessage
            #expect(mark.hasPrefix("„Vermisst“ konnte nicht gespeichert werden"))
            #expect(LibraryError.missingMarkNotSaved(found: true, saveFailure).userMessage.hasPrefix("„Wieder gefunden“"))
            // "Reihenfolge übernehmen" says the shelf is unchanged, not a general save error.
            let order = LibraryError.orderNotSaved(saveFailure).userMessage
            #expect(order.hasPrefix("Die neue Reihenfolge konnte nicht gespeichert werden"))
            #expect(!order.contains("134030"))
            #expect(!mark.contains("134030"))
            #expect(URLError(.notConnectedToInternet).userMessage == DiscogsError.offline.errorDescription)
            #expect(NSError(domain: "Other", code: 1).userMessage == ErrorMessages.generic)
            // 4xx is not a server problem.
            #expect(DiscogsError.http(418).userMessage.contains("abgelehnt"))
            #expect(DiscogsError.http(503).userMessage.contains("Problem"))
            #expect(DiscogsError.rateLimited(1).userMessage.contains("einer Sekunde"))
            // Files: the backup's own texts, and no "couldn't save the change" for a file.
            #expect(ShelfBackupError.unreadable.userMessage == ShelfBackupError.unreadable.errorDescription)
            #expect(FileTransferError.readFailed(saveFailure).userMessage.contains("geöffnet"))
            #expect(FileTransferError.writeFailed(saveFailure).userMessage != ErrorMessages.saveFailed)
            #expect(String(describing: FileTransferError.restoreFailed(saveFailure)).contains("134030"))
            #expect(CocoaError(.userCancelled).isUserCancellation)
            #expect(!saveFailure.isUserCancellation)
            // Cabinet and reset errors used to fall back to the generic text.
            #expect(CabinetError.lastActive.userMessage == CabinetError.lastActive.errorDescription)
            #expect(ResetError.tokenNotRemoved.userMessage == ResetError.tokenNotRemoved.errorDescription)
            #expect(StorageError.alreadyOpen.userMessage == StorageError.alreadyOpen.errorDescription)
            #expect(FileTransferError.folderUnavailable.userMessage.contains("nicht erreichbar"))
            #expect(URLError(.timedOut).userMessage.contains("rechtzeitig"))
        }
        /// The demo's sample collection: every page has something to show, and
        /// the layout is consistent (as a sync and the shelf page expect it).
        @Test func demoCollectionIsCompleteAndConsistent() throws {
            #expect(!DemoMode.isActive)
            #expect(AppDefaults.store === UserDefaults.standard)
            let container = try DemoData.makeContainer()
            let context = container.mainContext
            let copies = try context.fetch(FetchDescriptor<RecordCopy>())
            let account = DiscogsAccount.current(in: try context.fetch(FetchDescriptor<DiscogsAccount>()))
            #expect(account?.username == DemoData.owner)
            #expect(copies.count > 40 && copies.allSatisfy { $0.isInCurrentCollection(owner: DemoData.owner) })
            #expect(copies.filter { $0.shelf == nil }.count >= 5)
            let cabinets = try context.fetch(FetchDescriptor<Cabinet>())
            #expect(cabinets.count == 2)
            let shelves = try context.fetch(FetchDescriptor<Shelf>())
            #expect(shelves.contains { $0.isReserved && $0.copies.isEmpty })
            for shelf in shelves where !shelf.copies.isEmpty {
                #expect(shelf.copies.map(\.positionInShelf).sorted() == Array(1...shelf.copies.count))
            }
            #expect(Set(copies.map(\.discogsInstanceID)).count == copies.count)
            #expect(try context.fetchCount(FetchDescriptor<WantlistEntry>()) == 10)
            #expect(try context.fetchCount(FetchDescriptor<CollectionValueSnapshot>()) == 18)
            #expect(try context.fetchCount(FetchDescriptor<OptimizationExclusion>()) == 1)
        }
        @Test func onlyAFreshRequestStartsTheDemo() {
            let now = Date.now
            #expect(DemoMode.accepts(request: now.addingTimeInterval(-2), now: now, isTest: false))
            #expect(!DemoMode.accepts(request: nil, now: now, isTest: false))
            // A relaunch that failed long ago must not turn a normal start into a demo.
            #expect(!DemoMode.accepts(request: now.addingTimeInterval(-600), now: now, isTest: false))
            // A clock set back doesn't keep an old request alive.
            #expect(!DemoMode.accepts(request: now.addingTimeInterval(600), now: now, isTest: false))
            #expect(!DemoMode.accepts(request: now, now: now, isTest: true))
            #expect(DemoMode.fileSuffix.isEmpty)
            #expect(ScheduledExport.fileName(for: ExportSettings()) == "Plattenregal Collection.csv")
        }
        @Test func scheduledExportIsDueAfterAClockSetBack() {
            let now = Date(timeIntervalSince1970: 1_790_000_000)
            #expect(ScheduledExport.nextRun(after: nil, interval: .weekly, now: now) == now)
            #expect(ScheduledExport.nextRun(after: now.addingTimeInterval(-86400), interval: .daily, now: now)
                    == ExportInterval.daily.next(after: now.addingTimeInterval(-86400)))
            // Written while the clock stood years ahead: due now, not only in years.
            #expect(ScheduledExport.nextRun(after: now.addingTimeInterval(3 * 365 * 86400), interval: .monthly, now: now) == now)
        }
        @Test func crashOfThePreviousSessionIsFoundInTheLog() throws {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("crash-\(UUID()).log")
            defer { try? FileManager.default.removeItem(at: url) }
            // An old crash before the last start doesn't count.
            let crashed = """
            ──── Start · Version 1.0 (1)
            ==== ABSTURZ: SIGABRT (abgebrochen) · Unix-Zeit 1000 ====
            ──── Start · Version 1.0 (2)
            [Regal] irgendwas
            ==== ABSTURZ: SIGSEGV (ungültiger Speicherzugriff) · Unix-Zeit 1790000000 · Version 1.0 (2) ====
            0 Plattenregal 0x0000000100001234 main + 52
            ==== Ende Absturz ====

            """
            try Data(crashed.utf8).write(to: url)
            let crash = try #require(AppLog.previousCrash(in: url))
            #expect(crash.reason == "SIGSEGV (ungültiger Speicherzugriff)")
            #expect(crash.date == Date(timeIntervalSince1970: 1_790_000_000))
            try Data("──── Start · Version 1.0 (1)\n==== ABSTURZ: SIGABRT (abgebrochen) · Unix-Zeit 1000 ====\n──── Start · Version 1.0 (2)\nBeendet\n".utf8).write(to: url)
            #expect(AppLog.previousCrash(in: url) == nil)
        }
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
            #expect(ShelfStatistics(shelf: shelf).isReserved)
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
        @Test func discogsMappingWithOptionalFields() throws {
            let data = Data(#"{"id":123,"title":"Computerwelt","year":1981,"artists":[{"name":"Kraftwerk (2)","anv":"Kraftwerk"}],"labels":[{"name":"EMI","catno":"1C 064"}],"formats":[{"name":"Vinyl","qty":"1","descriptions":["LP"]}],"genres":["Electronic"],"tracklist":[{"position":"A1","title":"Computerwelt","duration":"5:05"}],"images":[{"type":"primary","uri":"https://example.com/cover.jpg"}]}"#.utf8)
            let release = try JSONDecoder().decode(DiscogsReleaseDTO.self, from: data).mappedRelease()
            #expect(release.artist == "Kraftwerk"); #expect(release.discogsID == 123)
            #expect(release.catalogNumber == "1C 064"); #expect(release.tracks.count == 1)
            #expect(release.format == "1 · Vinyl · LP"); #expect(release.isFresh)
            let minimal = try JSONDecoder().decode(DiscogsReleaseDTO.self, from: Data(#"{"id":1,"title":"Untitled","year":0}"#.utf8)).mappedRelease()
            #expect(minimal.year == nil); #expect(minimal.tracks.isEmpty)
            #expect(minimal.artist == "Unbekannter Interpret")
            release.fetchedAt = Date().addingTimeInterval(-21601)
            #expect(!release.isFresh)
            #expect(release.displayArtist == "Kraftwerk")
            #expect(release.displayTitle == "Computerwelt")
            #expect(release.coverURL == "https://example.com/cover.jpg")
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
        @Test func normalization() throws {
            let (container, shelves, service) = try fixture(); _ = container
            let a = try add(service, shelves[0], "A")
            let b = try add(service, shelves[0], "B")
            try service.save { a.positionInShelf = 7; b.positionInShelf = 12 }
            try service.normalize(shelves[0])
            #expect(service.ordered(shelves[0]).map(\.positionInShelf) == [1, 2])
        }
        @Test func persistentStoreCanBeReopened() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let schema = Schema(versionedSchema: LibrarySchemaV15.self)
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
}


nonisolated final class DiscogsStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let code = Int(url.lastPathComponent) ?? 200
        if code == 901 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let status = [401, 429, 500].contains(code) ? code : 200
        var body = #"{"id":1,"title":"Test"}"#
        if code == 900 { body = "not json" }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Retry-After": "1"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension AllTests {
    struct DiscogsClientTests {
        private func client(token: String? = "fixture") -> DiscogsAPIClient {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [DiscogsStubProtocol.self]
            return DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { token })
        }
        @Test func missingToken() async {
            do { _ = try await client(token: nil).release(id: 1); Issue.record("Expected missing token") }
            catch DiscogsError.missingToken {} catch { Issue.record("Unexpected: \(error)") }
        }
        @Test func unauthorized() async {
            do { _ = try await client().release(id: 401); Issue.record("Expected unauthorized") }
            catch DiscogsError.unauthorized {} catch { Issue.record("Unexpected: \(error)") }
        }
        @Test func rateLimit() async {
            do { _ = try await client().release(id: 429); Issue.record("Expected rate limit") }
            catch DiscogsError.rateLimited(let seconds) { #expect(seconds == 1) }
            catch { Issue.record("Unexpected: \(error)") }
        }
        @Test func hTTPError() async {
            do { _ = try await client().release(id: 500); Issue.record("Expected HTTP failure") }
            catch DiscogsError.http(let code) { #expect(code == 500) }
            catch { Issue.record("Unexpected: \(error)") }
        }
        @Test func invalidResponse() async {
            do { _ = try await client().release(id: 900); Issue.record("Expected invalid JSON") }
            catch DiscogsError.invalidResponse {} catch { Issue.record("Unexpected: \(error)") }
        }
        @Test func offline() async {
            do { _ = try await client().release(id: 901); Issue.record("Expected offline") }
            catch DiscogsError.offline {} catch { Issue.record("Unexpected: \(error)") }
        }
    }
}

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
    @Test func styleSharesCountFamilies() throws {
        let (container, shelves, service) = try fixture(); _ = container
        for (artist, style) in [("A", "Trance"), ("B", "Trance"), ("C", "Progressive Trance"), ("D", "Disco")] {
            try add(service, shelves[0], artist).release?.styles = [style]
        }
        let shares = ShelfStatistics(shelf: shelves[0]).styleShares
        #expect(shares.map(\.style) == ["Trance", "Disco"])
        #expect(shares[0].count == 3 && shares[0].members == ["Trance", "Progressive Trance"])
        #expect(shares[1].colorStyle == "")

        try add(service, shelves[0], "E").release?.styles = ["Funk"]
        let other = try #require(ShelfStatistics(shelf: shelves[0]).styleShares.first { $0.style == StylePalette.otherFamily })
        #expect(other.count == 2 && Set(other.members) == ["Disco", "Funk"])
    }
}

private extension DiscogsReleaseDTO {
    /// A fresh release filled from this DTO, the way a sync applies it.
    @MainActor func mappedRelease() -> Release {
        let release = Release(artist: "", title: title)
        apply(to: release); return release
    }
}

extension AllTests {
    struct DiscogsNameTests {
        @Test func dropsNumericDisambiguationOnly() {
            #expect(DiscogsName.clean("Systematic (3)") == "Systematic")
            #expect(DiscogsName.clean("Moby (2) & Kid (3), Other (14)") == "Moby & Kid, Other")
            // Words in parentheses and numbers that aren't a separate suffix stay.
            #expect(DiscogsName.clean("Kontor Records (Germany)") == "Kontor Records (Germany)")
            #expect(DiscogsName.clean("(3)") == "(3)")
            #expect(DiscogsName.clean("Sash!(2)") == "Sash!(2)")
            #expect(DiscogsName.clean("Systematic") == "Systematic")
        }
        /// The hand-written scan behaves exactly like the regex it replaced.
        @Test func matchesTheFormerRegex() {
            let inputs = ["Systematic (3)", "Moby (2) & Kid (3), Other (14)", "A  (2)", "A (2)(3)", "A (2) (3)", "A (2),B", "A (2)x",
                          "A (x)", "A ()", "A (12", " (3)", "(3) A", "A\t(4)\nB", "A (2) ", "Ä (٣)", "A ((2))", "A (2)) ", "",
                          "Sigur Rós (5), Björk (2) & Røyksopp", "Name (1999)", "A (2)\u{00A0}B", "A\u{00A0}(2)", "A (²)", "A (1٣2), B", "A\r\n(2)"]
            for input in inputs {
                #expect(DiscogsName.clean(input) == input.replacing(/\s+\(\d+\)(?=\s|,|$)/, with: ""), "\(input.debugDescription)")
            }
        }
    }
}

extension AllTests {
    struct DisplaySettingsTests {
        @Test func coverSizeStaysInRange() {
            #expect(DisplaySettings.coverSize(.nan) == DisplaySettings.defaultCoverSize)
            #expect(DisplaySettings.coverSize(.infinity) == DisplaySettings.defaultCoverSize)
            #expect(DisplaySettings.coverSize(-50) == DisplaySettings.coverSizeRange.lowerBound)
            #expect(DisplaySettings.coverSize(10_000) == DisplaySettings.coverSizeRange.upperBound)
            #expect(DisplaySettings.coverSize(180) == 180)
        }

        @Test func columnCountSurvivesOddMinimum() {
            #expect(CoverGrid.columnCount(available: 800, minimum: -8) == 1)
            #expect(CoverGrid.columnCount(available: 800, minimum: .nan) == 1)
            #expect(CoverGrid.columnCount(available: 800, minimum: 0) == 1)
            #expect(CoverGrid.columnCount(available: 800, minimum: 155) == 4)
        }
    }
}

extension AllTests {
    struct AccentContrastTests {
        /// Contrast of white text on the accent (selected segments, primary
        /// buttons), in light and dark mode.
        private func contrastWithWhite(_ color: Color, _ name: NSAppearance.Name) -> Double {
            var rgb = NSColor.white
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                rgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
            }
            func linear(_ c: CGFloat) -> Double {
                let c = Double(c)
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
            return 1.05 / (luminance + 0.05)
        }

        @Test func whiteTextStaysReadableOnEveryAccent() {
            for choice in AccentChoice.allCases where choice != .system {
                for name in [NSAppearance.Name.aqua, .darkAqua] {
                    let contrast = contrastWithWhite(choice.color, name)
                    #expect(contrast >= 3, "\(choice.title) in \(name.rawValue): \(contrast)")
                }
            }
        }
    }
}
