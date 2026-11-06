import Foundation
import SwiftData
import Testing
@testable import Plattenregal

extension AllTests {
    /// Sorting in at a boundary between two cabinets, and the "Verlauf".
    @MainActor struct ShelfHistoryTests {
        /// The rack of the report from 23.10.2026: KALLAX ends with
        /// "Various", EKET starts with "Yakooza".
        private struct Rack {
            let container: ModelContainer
            let positions: PositionService
            let kallax: Shelf
            let eket: Shelf
            var context: ModelContext { container.mainContext }
            var inUse: [Shelf] { Shelf.inUse((try? context.fetch(FetchDescriptor<Shelf>())) ?? []) }
        }

        private func rack() throws -> Rack {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let cabinets = CabinetService(context: container.mainContext)
            let positions = PositionService(context: container.mainContext)
            let first = try #require(try cabinets.cabinets().first)
            let eketCabinet = try cabinets.add(name: "EKET", columns: 1, rows: 1)
            let kallax = first.orderedShelves[0], eket = eketCabinet.orderedShelves[0]
            for (artist, title) in [("Abba", "Gold"), ("Various", "Anjunabeats Archive 02")] {
                try positions.insert(release: Release(artist: artist, title: title), shelf: kallax, position: kallax.copies.count + 1)
            }
            for (artist, title) in [("Yakooza", "Stronger"), ("Zombie Nation", "Kernkraft 400")] {
                try positions.insert(release: Release(artist: artist, title: title), shelf: eket, position: eket.copies.count + 1)
            }
            return Rack(container: container, positions: positions, kallax: kallax, eket: eket)
        }

        private func loose(_ rack: Rack, _ artist: String, _ title: String) throws -> RecordCopy {
            try rack.positions.insert(release: Release(artist: artist, title: title), shelf: nil)
        }

        // MARK: Sorting into the cabinet shown

        @Test func recordsGoIntoTheCabinetShown() throws {
            let rack = try rack()
            let cocaine = try loose(rack, "Yakooza", "Cocaine (Remixes)")
            // KALLAX shown: its end, though the other Yakooza stands in EKET.
            let inKallax = AlphabeticalPlacement.spots(for: cocaine, in: rack.inUse, cabinet: rack.kallax.cabinet?.id)
            #expect(inKallax.map(\.shelf.id) == [rack.kallax.id] && inKallax.map(\.position) == [3])
            // EKET shown: at its start, before "Yakooza – Stronger".
            let inEket = AlphabeticalPlacement.spots(for: cocaine, in: rack.inUse, cabinet: rack.eket.cabinet?.id)
            #expect(inEket.map(\.shelf.id) == [rack.eket.id] && inEket.map(\.position) == [1])
            #expect(inEket[0].before == nil && inEket[0].after?.release?.title == "Stronger")
            // No cabinet shown (search in the menu bar, widget): the first one, as the shelf page opens.
            #expect(AlphabeticalPlacement.spots(for: cocaine, in: rack.inUse).map(\.shelf.id) == [rack.kallax.id])
            #expect(AlphabeticalPlacement.fittingShelves(for: [cocaine], in: rack.inUse)[cocaine.id]?.map(\.id) == [rack.kallax.id])
            #expect(AlphabeticalPlacement.fittingShelves(for: [cocaine], in: rack.inUse, cabinet: rack.eket.cabinet?.id)[cocaine.id]?.map(\.id) == [rack.eket.id])

            // The round button's "Einsortieren" and the placement card agree.
            let placement = Placement(copy: cocaine, shelves: rack.inUse, openShelf: rack.eket.id, cabinet: rack.eket.cabinet?.id)
            #expect(placement.spots.count == 1 && placement.spot?.shelf.id == rack.eket.id)
            let session = ShelfAssignmentSession(shelf: nil, openShelf: rack.eket.id, shownCabinet: rack.eket.cabinet?.id)
            session.load(rack.context, owner: "Demo", labels: ShelfLabels())
            session.add(cocaine, in: rack.context)
            #expect(cocaine.shelf?.id == rack.eket.id && cocaine.positionInShelf == 1)
        }

        /// The report from 06.11.2026: EKET held records from "Agoria" to
        /// "Zombie Nation", so as one run with KALLAX it covered every name
        /// and took every new record – "Elektrochemie LK" too, though KALLAX
        /// has a compartment "De – Ev".
        @Test func aCabinetFromAToZNoLongerTakesEveryRecord() throws {
            let rack = try rack()
            for (artist, title) in [("Agoria", "Code 1026"), ("DJ Hitch Hiker", "Cabal"), ("Johannes Heil", "From Within")] {
                try rack.positions.insert(release: Release(artist: artist, title: title), shelf: rack.eket, position: 1)
            }
            let first = try #require(rack.kallax.cabinet)
            // KALLAX: Abba, DJ 7ranceport, Evensloped, Various.
            let dj = try rack.positions.insert(release: Release(artist: "DJ 7ranceport", title: "Trance"), shelf: rack.kallax, position: 2)
            let even = try rack.positions.insert(release: Release(artist: "Evensloped", title: "Sky"), shelf: rack.kallax, position: 3)
            let schall = try loose(rack, "Elektrochemie LK, Thomas Schumacher", "Schall (Revisited)")
            let spots = AlphabeticalPlacement.spots(for: schall, in: rack.inUse, cabinet: first.id)
            #expect(spots.map(\.shelf.id) == [rack.kallax.id] && spots.map(\.position) == [3])
            #expect(spots.first?.before?.id == dj.id && spots.first?.after?.id == even.id)
            #expect(AlphabeticalPlacement.spots(for: schall, in: rack.inUse).map(\.shelf.id) == [rack.kallax.id])
            // Only with EKET shown does it go there, by EKET's own order.
            #expect(AlphabeticalPlacement.spots(for: schall, in: rack.inUse, cabinet: rack.eket.cabinet?.id).map(\.shelf.id) == [rack.eket.id])
        }

        @Test func boundaryInsideACabinetFollowsTheArtistThenTheOpenCompartment() throws {
            let rack = try rack()
            let cabinet = try #require(rack.kallax.cabinet)
            let next = cabinet.orderedShelves[1]
            try rack.positions.insert(release: Release(artist: "Yakooza", title: "Stronger"), shelf: next, position: 1)
            let cocaine = try loose(rack, "Yakooza", "Cocaine (Remixes)")
            let spots = AlphabeticalPlacement.spots(for: cocaine, in: rack.inUse, cabinet: cabinet.id)
            #expect(spots.map(\.shelf.id) == [rack.kallax.id, next.id])
            // Even with the first compartment open: the other Yakooza stands in the next.
            #expect(AlphabeticalPlacement.preferredIndex(spots, for: cocaine, openShelf: rack.kallax.id) == 1)

            let voigt = try loose(rack, "Wolfgang Voigt", "Ampère")
            let between = AlphabeticalPlacement.spots(for: voigt, in: rack.inUse, cabinet: cabinet.id)
            #expect(between.map(\.shelf.id) == [rack.kallax.id, next.id])
            #expect(AlphabeticalPlacement.preferredIndex(between, for: voigt) == 0)
            #expect(AlphabeticalPlacement.preferredIndex(between, for: voigt, openShelf: next.id) == 1)
        }

        /// Inside one cabinet a compartment may hold records from all over
        /// the alphabet too (put in by hand). It covered every name between
        /// its ends and took them all; now the compartment where the record
        /// fits with nothing between its neighbours wins.
        @Test func aMixedCompartmentDoesNotTakeRecordsThatFitCloserElsewhere() throws {
            let rack = try rack()
            let cabinet = try #require(rack.kallax.cabinet)
            // KALLAX: compartment 1 "Abba … Various", compartment 2 "DJ 7ranceport … Evensloped".
            let second = cabinet.orderedShelves[1]
            let dj = try rack.positions.insert(release: Release(artist: "DJ 7ranceport", title: "Trance"), shelf: second, position: 1)
            let even = try rack.positions.insert(release: Release(artist: "Evensloped", title: "Sky"), shelf: second, position: 2)
            let abba = try #require(rack.kallax.copies.first { $0.release?.artist == "Abba" })
            let various = try #require(rack.kallax.copies.first { $0.release?.artist == "Various" })

            let schall = try loose(rack, "Elektrochemie LK, Thomas Schumacher", "Schall (Revisited)")
            let inside = AlphabeticalPlacement.spots(for: schall, in: rack.inUse, cabinet: cabinet.id)
            #expect(inside.map(\.shelf.id) == [second.id] && inside.map(\.position) == [2])
            #expect(inside.first?.before?.id == dj.id && inside.first?.after?.id == even.id)

            // Before "DJ": the start of compartment 2, its left neighbour the record before it in the cabinet.
            let beck = try loose(rack, "Beck", "Odelay")
            let start = AlphabeticalPlacement.spots(for: beck, in: rack.inUse, cabinet: cabinet.id)
            #expect(start.map(\.shelf.id) == [second.id] && start.map(\.position) == [1])
            #expect(start.first?.before?.id == abba.id && start.first?.after?.id == dj.id)

            // Behind everything: the end of compartment 1, after "Various".
            let zappa = try loose(rack, "Zappa", "Hot Rats")
            let end = AlphabeticalPlacement.spots(for: zappa, in: rack.inUse, cabinet: cabinet.id)
            #expect(end.map(\.shelf.id) == [rack.kallax.id] && end.map(\.position) == [3])
            #expect(end.first?.before?.id == various.id && end.first?.after == nil)

            // Many at once ("Noch nicht einsortiert", widget): the same compartments.
            let batch = [schall, beck, zappa]
            let fitting = AlphabeticalPlacement.fittingShelves(for: batch, in: rack.inUse, cabinet: cabinet.id)
            for copy in batch {
                #expect(fitting[copy.id]?.map(\.id) == AlphabeticalPlacement.spots(for: copy, in: rack.inUse, cabinet: cabinet.id).map(\.shelf.id))
            }
        }

        /// The sorted compartments are kept between calls; a record put in or
        /// taken out, or new record data, must show at once.
        @Test func keptCompartmentsFollowEveryChange() throws {
            let rack = try rack()
            let cabinet = try #require(rack.kallax.cabinet)
            let beck = try loose(rack, "Beck", "Odelay")
            #expect(AlphabeticalPlacement.spots(for: beck, in: rack.inUse, cabinet: cabinet.id).first?.position == 2)

            let bach = try rack.positions.insert(release: Release(artist: "Bach", title: "Goldberg"), shelf: rack.kallax, position: 2)
            let afterInsert = AlphabeticalPlacement.spots(for: beck, in: rack.inUse, cabinet: cabinet.id)
            #expect(afterInsert.first?.position == 3 && afterInsert.first?.before?.id == bach.id)

            try rack.positions.unplace(bach)
            let afterRemoval = AlphabeticalPlacement.spots(for: beck, in: rack.inUse, cabinet: cabinet.id)
            #expect(afterRemoval.first?.position == 2 && afterRemoval.first?.before?.release?.artist == "Abba")

            // A sync renames "Abba" to "Zz Top": Beck now comes first.
            let abba = try #require(rack.kallax.copies.first { $0.release?.artist == "Abba" })
            abba.release?.artist = "Zz Top"
            try rack.context.save()
            LibraryChanges.shared.syncDidCommit()
            let renamed = AlphabeticalPlacement.spots(for: beck, in: rack.inUse, cabinet: cabinet.id)
            #expect(renamed.first?.position == 1 && renamed.first?.before == nil)

            // A placed record alone in its compartment leaves itself out: that
            // compartment counts as empty, its place is among the others.
            let second = cabinet.orderedShelves[1]
            let solo = try rack.positions.insert(release: Release(artist: "Moloko", title: "Statues"), shelf: second, position: 1)
            let again = AlphabeticalPlacement.spots(for: solo, in: rack.inUse, cabinet: cabinet.id)
            #expect(again.map(\.shelf.id) == [rack.kallax.id])
            // KALLAX stands "Zz Top", "Various" since the renaming: Moloko goes first.
            #expect(again.first?.position == 1 && again.first?.before == nil && again.first?.after?.release?.artist == "Zz Top")
            #expect(AlphabeticalPlacement.current(for: solo, in: rack.inUse)?.shelf.id == second.id)
        }

        /// Labels are letters of one cabinet's alphabet: the jazz compartment
        /// in the hallway (as in the demo) no longer shapes the living room's.
        @Test func labelsComeFromEachCabinetAlone() throws {
            let rack = try rack()
            let cabinet = try #require(rack.kallax.cabinet)
            try rack.positions.unplace(rack.kallax.copies)
            try rack.positions.unplace(rack.eket.copies)
            let first = cabinet.orderedShelves[0], second = cabinet.orderedShelves[1]
            for (artist, shelf) in [("Daft Punk", first), ("Depeche Mode", first), ("Dj Koze", second), ("Juno Reactor", second)] {
                try rack.positions.insert(release: Release(artist: artist, title: "Album"), shelf: shelf, position: shelf.copies.count + 1)
            }
            for artist in ["Dave Brubeck", "Miles Davis"] {
                try rack.positions.insert(release: Release(artist: artist, title: "Album"), shelf: rack.eket, position: rack.eket.copies.count + 1)
            }
            let all = try rack.context.fetch(FetchDescriptor<Shelf>())
            let labels = ShelfRangeLabels.compute(for: all)
            // As one run, "Dave Brubeck" stood between them: "Da – De" and "D – J".
            #expect(labels[first.id] == "Da – De")
            #expect(labels[second.id] == "Dj – J")
            #expect(labels[rack.eket.id] == "D – M")
        }

        @Test func anEmptyCabinetShownFallsBackToTheFirstWithRecords() throws {
            let rack = try rack()
            let cabinets = CabinetService(context: rack.context)
            let empty = try cabinets.add(name: "Leer", columns: 1, rows: 1)
            let beck = try loose(rack, "Beck", "Odelay")
            let spots = AlphabeticalPlacement.spots(for: beck, in: rack.inUse, cabinet: empty.id)
            #expect(spots.map(\.shelf.id) == [rack.kallax.id] && spots.map(\.position) == [2])
        }

        // MARK: History

        @Test func sortingInIsRecordedAndUndone() throws {
            let rack = try rack()
            let copy = try loose(rack, "Yakooza", "Drugs")
            try rack.positions.move(copy, to: rack.eket, position: 1, found: true)
            let entry = try #require(try ShelfHistory.entries(in: rack.context).first)
            #expect(ShelfHistory.kind(of: entry) == .sortedIn)
            #expect(entry.copyID == copy.id && entry.toShelfID == rack.eket.id && entry.toPosition == 1)
            #expect(entry.artist == "Yakooza" && entry.title == "Drugs" && entry.toName == "EKET · Fach 1")
            #expect(try ShelfHistory.check(entry, in: rack.context).blocker == nil)

            try rack.positions.undo(entry)
            #expect(copy.shelf == nil && copy.positionInShelf == 0)
            #expect(PositionService.inShelfOrder(rack.eket.copies).map(\.positionInShelf) == [1, 2])
            #expect(entry.undoneAt != nil)
            // Undoing writes no entry of its own, and can't be done twice.
            #expect(try ShelfHistory.entries(in: rack.context).count == 1)
            #expect(throws: LibraryError.self) { try rack.positions.undo(entry) }
        }

        @Test func changesOfOneRecordAreUndoneNewestFirst() throws {
            let rack = try rack()
            let copy = try loose(rack, "Yakooza", "French Kiss")
            try rack.positions.move(copy, to: rack.kallax, position: 3)
            try rack.positions.move(copy, to: rack.eket, position: 2)
            let entries = try ShelfHistory.entries(in: rack.context)
            #expect(entries.map { ShelfHistory.kind(of: $0) } == [.moved, .sortedIn])
            let (moved, sortedIn) = (entries[0], entries[1])
            #expect(try ShelfHistory.check(sortedIn, in: rack.context).blocker == .changedSince)

            try rack.positions.undo(moved)
            #expect(copy.shelf?.id == rack.kallax.id && copy.positionInShelf == 3)
            #expect(try ShelfHistory.check(sortedIn, in: rack.context).blocker == nil)
            try rack.positions.undo(sortedIn)
            #expect(copy.shelf == nil)

            // The list asks for all entries at once and agrees.
            let records = LibraryRecords.of(rack.context)
            let blockers = ShelfHistory.blockers(try ShelfHistory.entries(in: rack.context),
                                                 copies: Dictionary(uniqueKeysWithValues: records.copies.map { ($0.id, $0) }),
                                                 shelves: Dictionary(uniqueKeysWithValues: records.shelves.map { ($0.id, $0) }),
                                                 excluded: [])
            #expect(blockers[moved.id] == .undone && blockers[sortedIn.id] == .undone)
        }

        @Test func moveByHandAfterSortingInBlocksTheOlderEntry() throws {
            let rack = try rack()
            let copy = try loose(rack, "Yakooza", "Cocaine")
            try rack.positions.move(copy, to: rack.kallax, position: 3)
            let sortedIn = try #require(try ShelfHistory.entries(in: rack.context).first)
            // Taken out again, as on 23.10.: the newest entry is the taking out.
            try rack.positions.unplace(copy)
            #expect(try ShelfHistory.check(sortedIn, in: rack.context).blocker == .changedSince)
        }

        @Test func undoingSortingInPutsMarksBack() throws {
            let rack = try rack()
            let copy = try loose(rack, "Yakooza", "Stronger (Remix)")
            rack.context.insert(MissingCopyMark(copyID: copy.id))
            rack.context.insert(OptimizationExclusion(copyID: copy.id))
            try rack.context.save()
            try rack.positions.move(copy, to: rack.eket, position: 2, found: true)
            #expect(try rack.context.fetchCount(FetchDescriptor<MissingCopyMark>()) == 0)
            #expect(try rack.context.fetchCount(FetchDescriptor<OptimizationExclusion>()) == 0)
            let entry = try #require(try ShelfHistory.entries(in: rack.context).first)
            #expect(entry.clearedMissing && entry.clearedExclusion)

            try rack.positions.undo(entry)
            #expect(try rack.context.fetch(FetchDescriptor<MissingCopyMark>()).map(\.copyID) == [copy.id])
            #expect(try rack.context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID) == [copy.id])
        }

        @Test func takingOutIsUndoneToTheOldPosition() throws {
            let rack = try rack()
            let various = try #require(PositionService.inShelfOrder(rack.kallax.copies).last)
            let entry = try #require(try rack.positions.unplace(various))
            #expect(ShelfHistory.kind(of: entry) == .takenOut && entry.fromPosition == 2)
            try rack.positions.undo(entry)
            #expect(various.shelf?.id == rack.kallax.id && various.positionInShelf == 2)
        }

        @Test func lockedOrKeptOutRecordsStayWhereTheyAre() throws {
            let rack = try rack()
            let abba = try #require(PositionService.inShelfOrder(rack.kallax.copies).first)
            let various = try #require(PositionService.inShelfOrder(rack.kallax.copies).last)
            let abbaOut = try #require(try rack.positions.unplace(abba))
            let variousOut = try #require(try rack.positions.unplace(various))
            try rack.positions.configure(rack.kallax, name: "Deko", isReserved: true)
            #expect(try ShelfHistory.check(abbaOut, in: rack.context).blocker == .shelfLocked)
            try rack.positions.configure(rack.kallax, name: "", isReserved: false)
            try rack.positions.setExcluded([various], true)
            #expect(try ShelfHistory.check(variousOut, in: rack.context).blocker == .keptOut)
            #expect(throws: LibraryError.self) { try rack.positions.undo(variousOut) }
            #expect(various.shelf == nil)
        }

        @Test func historyKeepsOnlyTheNewestEntries() throws {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let context = container.mainContext
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            for index in 0..<(ShelfHistory.keptCount + 5) {
                context.insert(ShelfHistoryEntry(copyID: UUID(), artist: "A\(index)", title: "", fromShelfID: nil, fromPosition: 0, fromName: "",
                                                 toShelfID: UUID(), toPosition: 1, toName: "", date: start.addingTimeInterval(Double(index))))
            }
            try context.save()
            ShelfHistory.prune(in: context)
            let kept = try ShelfHistory.entries(in: context)
            #expect(kept.count == ShelfHistory.keptCount)
            #expect(kept.first?.artist == "A\(ShelfHistory.keptCount + 4)" && kept.last?.artist == "A5")
        }

        /// A V17 store (the released 1.1.2) opens as V18 with everything in it; the history starts empty.
        @Test func v17StoreMigratesToV18() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("Migration.store")
            let copyID: UUID = try autoreleasepool {
                let schema = Schema(versionedSchema: LibrarySchemaV17.self)
                let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                                   configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
                let context = container.mainContext
                let shelf = Shelf(number: 1); context.insert(shelf)
                let release = Release(discogsID: 42, artist: "Yakooza", title: "Stronger")
                context.insert(release)
                let copy = RecordCopy(release: release, instanceID: 1, owner: "fixture", shelf: shelf, position: 1)
                context.insert(copy)
                context.insert(ReleaseVideoList(discogsID: 42, videos: []))
                try context.save()
                return copy.id
            }
            let schema = Schema(versionedSchema: LibrarySchemaV18.self)
            let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                               configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = container.mainContext
            let copy = try #require(try context.fetch(FetchDescriptor<RecordCopy>()).first)
            #expect(copy.id == copyID && copy.shelf?.number == 1 && copy.release?.discogsID == 42)
            #expect(try context.fetchCount(FetchDescriptor<ReleaseVideoList>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<ShelfHistoryEntry>()) == 0)
        }
    }
}
