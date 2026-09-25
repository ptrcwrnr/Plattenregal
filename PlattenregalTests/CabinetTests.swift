import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests {
    @MainActor struct CabinetTests {
        private func fixture() throws -> (ModelContainer, CabinetService, PositionService) {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            return (container, CabinetService(context: container.mainContext), PositionService(context: container.mainContext))
        }
        @discardableResult private func add(_ service: PositionService, _ shelf: Shelf, _ artist: String, instanceID: Int = .random(in: 1...Int(Int32.max))) throws -> RecordCopy {
            try service.insert(release: Release(artist: artist, title: "Album"), shelf: shelf, position: shelf.copies.count + 1, instanceID: instanceID)
        }

        @Test func freshStoreHasOneKallaxWithTwelveCompartments() throws {
            let (container, cabinets, _) = try fixture()
            let all = try cabinets.cabinets()
            #expect(all.count == 1)
            let cabinet = try #require(all.first)
            #expect(cabinet.columns == 4 && cabinet.rows == 3 && cabinet.isActive)
            #expect(cabinet.orderedShelves.map(\.number) == Array(1...12))
            #expect(cabinet.orderedShelves.map(\.sortOrder) == Array(1...12))
            _ = container
        }

        @Test func v11StoreMovesItsCompartmentsIntoTheFirstCabinet() throws {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let url = dir.appendingPathComponent("Migration.store")
            let copyID: UUID = try autoreleasepool {
                let schema = Schema(versionedSchema: LibrarySchemaV11.self)
                let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
                let context = container.mainContext
                var shelves: [LibrarySchemaV11.Shelf] = []
                for number in 1...12 { let shelf = LibrarySchemaV11.Shelf(number: number); context.insert(shelf); shelves.append(shelf) }
                shelves[6].isReserved = true; shelves[6].name = "Deko"
                let release = LibrarySchemaV11.Release(discogsID: 7, artist: "Kraftwerk", title: "Computerwelt")
                context.insert(release)
                let copy = LibrarySchemaV11.RecordCopy(release: release, instanceID: 70, owner: "fixture")
                context.insert(copy)
                copy.shelf = shelves[5]; copy.positionInShelf = 1
                try context.save()
                return copy.id
            }
            let schema = Schema(versionedSchema: LibrarySchemaV13.self)
            let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
                                               configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            try LibraryStorage.prepareShelves(in: container.mainContext)
            let context = container.mainContext
            let cabinets = try context.fetch(FetchDescriptor<Cabinet>())
            #expect(cabinets.count == 1)
            #expect(try context.fetchCount(FetchDescriptor<Shelf>()) == 12)
            let copy = try #require(context.fetch(FetchDescriptor<RecordCopy>()).first { $0.id == copyID })
            #expect(copy.shelf?.number == 6 && copy.shelf?.sortOrder == 6 && copy.shelf?.cabinet?.id == cabinets.first?.id)
            #expect(copy.shelf?.row == 2 && copy.shelf?.column == 2)
            let deko = try #require(context.fetch(FetchDescriptor<Shelf>()).first { $0.number == 7 })
            #expect(deko.isReserved && deko.name == "Deko")
        }

        @Test func addedCabinetGetsItsOwnCompartmentsWithFreshNumbers() throws {
            let (container, cabinets, _) = try fixture(); _ = container
            let second = try cabinets.add(name: "Flur", columns: 2, rows: 4)
            #expect(second.name == "Flur" && second.sortOrder == 1)
            let shelves = second.orderedShelves
            #expect(shelves.map(\.number) == Array(13...20))
            #expect(shelves.map(\.sortOrder) == Array(1...8))
            #expect(shelves[2].row == 2 && shelves[2].column == 1)
            #expect(cabinets.suggestedName() == "Regal 2")
        }

        @Test func shrinkingNeedsEmptyCompartmentsAndKeepsReadingOrder() throws {
            let (container, cabinets, positions) = try fixture(); _ = container
            let cabinet = try #require(try cabinets.cabinets().first)
            let last = try #require(cabinet.orderedShelves.last)
            try add(positions, last, "Zappa")
            #expect(throws: CabinetError.self) { try cabinets.resize(cabinet, columns: 2, rows: 2) }
            #expect(cabinet.count == 12)

            try positions.unplace(last.copies)
            let third = cabinet.orderedShelves[2]
            try add(positions, third, "Can")
            try cabinets.resize(cabinet, columns: 2, rows: 2)
            #expect(cabinet.orderedShelves.count == 4)
            // The third compartment keeps its record and moves to row 2, column 1.
            #expect(third.sortOrder == 3 && third.row == 2 && third.column == 1 && third.copies.count == 1)

            try cabinets.resize(cabinet, columns: 5, rows: 5)
            #expect(cabinet.orderedShelves.count == 25)
            #expect(Set(cabinet.orderedShelves.map(\.number)).count == 25)
        }

        @Test func oneCabinetStaysActiveAndOnlyEmptyOnesCanGo() throws {
            let (container, cabinets, positions) = try fixture(); _ = container
            let first = try #require(try cabinets.cabinets().first)
            #expect(throws: CabinetError.self) { try cabinets.setActive(first, false) }
            #expect(throws: CabinetError.self) { try cabinets.delete(first) }

            let second = try cabinets.add(name: "Keller", columns: 1, rows: 4)
            try add(positions, second.orderedShelves[0], "Beck")
            try cabinets.setActive(first, false)
            #expect(!first.isActive)
            #expect(throws: CabinetError.self) { try cabinets.setActive(second, false) }
            #expect(throws: CabinetError.self) { try cabinets.delete(second) }

            try cabinets.setActive(first, true)
            try positions.unplace(second.orderedShelves[0].copies)
            try cabinets.delete(second)
            #expect(try cabinets.cabinets().count == 1)
            #expect(try container.mainContext.fetchCount(FetchDescriptor<Shelf>()) == 12)
        }

        @Test func inactiveCabinetsAreSkippedWhenSortingIn() throws {
            let (container, cabinets, positions) = try fixture()
            let first = try #require(try cabinets.cabinets().first)
            let storage = try cabinets.add(name: "Keller", columns: 1, rows: 2)
            try add(positions, first.orderedShelves[0], "Abba")
            try add(positions, storage.orderedShelves[0], "Moby")
            try cabinets.setActive(storage, false)

            let all = try container.mainContext.fetch(FetchDescriptor<Shelf>())
            let inUse = Shelf.inUse(all)
            #expect(inUse.count == 12)
            #expect(inUse.map(\.number) == Array(1...12))
            let newcomer = try positions.insert(release: Release(artist: "Nena", title: "99"), shelf: nil)
            let spots = AlphabeticalPlacement.spots(for: newcomer, in: inUse)
            #expect(spots.map(\.shelf.id) == [first.orderedShelves[0].id])

            // The put-away cabinet keeps its own range and says where it is.
            let labels = ShelfRangeLabels.compute(for: all)
            #expect(labels[first.orderedShelves[0].id] == "A")
            #expect(labels[storage.orderedShelves[0].id] == "M")
            let moby = try #require(storage.orderedShelves[0].copies.first)
            #expect(ShelfRangeLabels.location(of: moby, labels: labels) == "Keller (inaktiv) · M · Position 1")

            // "Im Regal anzeigen" names the put-away cabinet instead of a spot off this page.
            let shown = Placement(copy: moby, shelves: inUse)
            #expect(shown.found && shown.spot == nil && shown.putAwayIn == "Keller")
            #expect(Placement(copy: newcomer, shelves: inUse).putAwayIn == nil)
        }

        @Test func numberLabelsNameEveryOpenCompartment() throws {
            let (container, cabinets, positions) = try fixture()
            let first = try #require(try cabinets.cabinets().first)
            try add(positions, first.orderedShelves[1], "Beck")
            try positions.configure(first.orderedShelves[2], name: "Deko", isReserved: true)
            let shelves = try container.mainContext.fetch(FetchDescriptor<Shelf>())
            let labels = ShelfRangeLabels.compute(for: shelves, style: .number)
            #expect(labels[first.orderedShelves[0].id] == "Fach 1")
            #expect(labels[first.orderedShelves[1].id] == "Fach 2")
            #expect(labels[first.orderedShelves[2].id] == nil)
            let beck = try #require(first.orderedShelves[1].copies.first)
            // One cabinet: no cabinet name in front.
            #expect(ShelfRangeLabels.location(of: beck, labels: labels) == "Fach 2 · Position 1")
        }

        @Test func backupBringsBackCabinetsAndTheirRecords() throws {
            let (container, cabinets, positions) = try fixture()
            let context = container.mainContext
            let second = try cabinets.add(name: "Flur", columns: 2, rows: 2)
            try cabinets.setActive(second, false)
            let copy = try add(positions, second.orderedShelves[3], "Air", instanceID: 501)
            let numbers = second.orderedShelves.map(\.number)
            let backup = try ShelfBackupService.decode(ShelfBackupService.encode(ShelfBackupService(context: context).makeBackup()))
            #expect(backup.cabinets?.count == 2)
            #expect(backup.cabinets?.last?.shelves == numbers)

            try positions.unplace([copy])
            try cabinets.setActive(second, true)
            try cabinets.delete(second)
            #expect(try cabinets.cabinets().count == 1)

            try ShelfBackupService(context: context).restore(backup)
            let restored = try cabinets.cabinets()
            #expect(restored.map(\.name) == ["Regal", "Flur"])
            let flur = try #require(restored.last)
            #expect(!flur.isActive && flur.columns == 2 && flur.rows == 2)
            #expect(flur.orderedShelves.map(\.number) == numbers)
            #expect(copy.shelf?.id == flur.orderedShelves[3].id && copy.positionInShelf == 1)
            #expect(try context.fetchCount(FetchDescriptor<Shelf>()) == 16)
        }

        @Test func oldBackupsWithoutCabinetsStillRestore() throws {
            let (container, cabinets, positions) = try fixture()
            let context = container.mainContext
            let first = try #require(try cabinets.cabinets().first)
            let copy = try add(positions, first.orderedShelves[4], "Blur", instanceID: 77)
            var backup = try ShelfBackupService(context: context).makeBackup()
            backup.cabinets = nil
            try cabinets.add(name: "Flur", columns: 1, rows: 2)
            try positions.unplace([copy])
            try ShelfBackupService(context: context).restore(backup)
            #expect(copy.shelf?.number == 5)
            // The cabinets stay as they are.
            #expect(try cabinets.cabinets().count == 2)
        }

        @Test func resetLocationsEmptiesTheShelvesButKeepsTheCabinets() throws {
            let (container, cabinets, positions) = try fixture()
            let context = container.mainContext
            let first = try #require(try cabinets.cabinets().first)
            try cabinets.add(name: "Flur", columns: 1, rows: 2)
            let a = try add(positions, first.orderedShelves[0], "A")
            let b = try positions.insert(release: Release(artist: "B", title: "2"), shelf: nil)
            try positions.setExcluded([b], true)
            try positions.configure(first.orderedShelves[3], name: "Deko", isReserved: true)
            try ResetService(context: context).resetLocations()
            #expect(a.shelf == nil && a.positionInShelf == 0)
            #expect(try context.fetchCount(FetchDescriptor<OptimizationExclusion>()) == 0)
            #expect(!first.orderedShelves[3].isReserved && first.orderedShelves[3].name.isEmpty)
            #expect(try cabinets.cabinets().count == 2)
        }

        @Test func deleteLibraryLeavesAFreshStoreInOneGo() throws {
            let (container, cabinets, positions) = try fixture()
            let context = container.mainContext
            let first = try #require(try cabinets.cabinets().first)
            try cabinets.add(name: "Flur", columns: 2, rows: 2)
            let a = try add(positions, first.orderedShelves[0], "A")
            let b = try positions.insert(release: Release(artist: "B", title: "2"), shelf: nil)
            try positions.setExcluded([b], true)
            try positions.setMissing([a], true)
            let wanted = Release(artist: "C", title: "3")
            context.insert(wanted)
            context.insert(WantlistEntry(owner: "Demo", release: wanted, releaseID: wanted.discogsID))
            context.insert(DiscogsAccount(username: "Demo"))
            try context.save()

            try ResetService(context: context).deleteLibrary()

            #expect(try context.fetchCount(FetchDescriptor<RecordCopy>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<Release>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<WantlistEntry>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<OptimizationExclusion>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<MissingCopyMark>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<DiscogsAccount>()) == 0)
            let fresh = try cabinets.cabinets()
            #expect(fresh.count == 1)
            #expect(fresh.first?.columns == 4 && fresh.first?.rows == 3 && fresh.first?.isActive == true)
            #expect(fresh.first?.orderedShelves.count == 12)
            #expect(!context.hasChanges)
        }

        @Test func kallaxPresetsCarryTheBoxMeasures() {
            #expect(KallaxPreset.all.count == 11)
            #expect(KallaxPreset.matching(columns: 2, rows: 4)?.title == "2 × 4 · 77 × 147 cm")
            #expect(KallaxPreset.matching(columns: 4, rows: 3)?.title == "4 × 3 · 147 × 112 cm")
            #expect(KallaxPreset.matching(columns: 5, rows: 5)?.title == "5 × 5 · 182 × 182 cm")
            #expect(KallaxPreset.matching(columns: 1, rows: 4)?.orientation == "hochkant")
            #expect(KallaxPreset.matching(columns: 4, rows: 1)?.orientation == "quer")
            #expect(KallaxPreset.matching(columns: 3, rows: 3) == nil)
        }

        @Test func retentionWithoutDailyStatesKeepsOnlyTheLatest() {
            let now = Date(timeIntervalSince1970: 1_790_000_000)
            let dates = (0..<30).map { now.addingTimeInterval(-Double($0) * 86_400) }
            #expect(ShelfAutoBackup.retained(dates, keptCount: 5, keptDays: 0) == Array(0..<5))
            #expect(ShelfAutoBackup.retained(dates, keptCount: 5, keptDays: 7) == Array(0..<7))
        }

        @Test func exportIntervalsStepByCalendar() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
            let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 9))!
            #expect(ExportInterval.daily.next(after: start, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 9)))
            #expect(ExportInterval.weekly.next(after: start, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 2, day: 7, hour: 9)))
            #expect(ExportInterval.monthly.next(after: start, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 2, day: 28, hour: 9)))
        }
    }
}
