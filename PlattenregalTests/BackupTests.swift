import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests {
    @MainActor struct BackupTests {
        private func fixture() throws -> (ModelContainer, [Shelf], PositionService) {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let shelves = try container.mainContext.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
            return (container, shelves, PositionService(context: container.mainContext))
        }

        /// The automatic backup reads the layout in a context of its own, off
        /// the main actor; it must hold exactly what the main context sees.
        @Test func backupTakenOffTheMainActorMatches() async throws {
            let (container, shelves, service) = try fixture()
            try service.insert(release: Release(artist: "A", title: "1"), shelf: shelves[0], position: 1, instanceID: 11)
            try service.insert(release: Release(artist: "B", title: "2"), shelf: shelves[1], position: 1, instanceID: 12)
            let d = try service.insert(release: Release(artist: "D", title: "4"), shelf: nil, instanceID: 14)
            try service.setExcluded([d], true)
            try service.configure(shelves[5], name: "Deko", isReserved: true)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let onMain = try ShelfBackupService(context: container.mainContext).makeBackup(at: date)
            let beside = try await Task.detached { try ShelfBackupService.makeBackup(of: ModelContext(container), at: date) }.value
            #expect(beside == onMain)
            #expect(beside.placements.map(\.instanceID) == [11, 12])
            #expect(beside.notInShelf == [14])
        }

        @Test func roundTripRestoresPlacesLocksAndExclusions() throws {
            let (container, shelves, service) = try fixture()
            let a = try service.insert(release: Release(artist: "A", title: "1"), shelf: shelves[0], position: 1, instanceID: 11)
            let b = try service.insert(release: Release(artist: "B", title: "2"), shelf: shelves[0], position: 2, instanceID: 12)
            let c = try service.insert(release: Release(artist: "C", title: "3"), shelf: shelves[2], position: 1, instanceID: 13)
            let d = try service.insert(release: Release(artist: "D", title: "4"), shelf: nil, instanceID: 14)
            try service.setExcluded([d], true)
            try service.configure(shelves[5], name: "Deko", isReserved: true)

            let backupService = ShelfBackupService(context: container.mainContext)
            let data = try ShelfBackupService.encode(try backupService.makeBackup())
            let backup = try ShelfBackupService.decode(data)
            #expect(backup.placements.map(\.instanceID) == [11, 12, 13])
            #expect(backup.notInShelf == [14])

            // Lose the layout.
            try service.unplace([a, b, c])
            try service.setExcluded([d], false)
            try service.configure(shelves[5], name: "", isReserved: false)
            try service.move(c, to: shelves[5], position: 1)

            let preview = try backupService.preview(backup)
            #expect(preview.placed == 3)
            #expect(preview.missing == 0)
            #expect(preview.unplaced == 0)

            try backupService.restore(backup)
            #expect(a.shelf?.number == 1 && a.positionInShelf == 1)
            #expect(b.shelf?.number == 1 && b.positionInShelf == 2)
            #expect(c.shelf?.number == 3 && c.positionInShelf == 1)
            #expect(d.shelf == nil)
            #expect(shelves[5].isReserved && shelves[5].name == "Deko")
            let exclusions = try container.mainContext.fetch(FetchDescriptor<OptimizationExclusion>())
            #expect(exclusions.map(\.copyID) == [d.id])
        }

        @Test func restoreKeepsMissingMarksExceptOnRecordsKeptOut() throws {
            let (container, shelves, service) = try fixture()
            let a = try service.insert(release: Release(artist: "A", title: "1"), shelf: shelves[0], position: 1, instanceID: 41)
            let b = try service.insert(release: Release(artist: "B", title: "2"), shelf: nil, instanceID: 42)
            try service.setExcluded([b], true)
            let backupService = ShelfBackupService(context: container.mainContext)
            let backup = try backupService.makeBackup()

            try service.setExcluded([b], false)
            try service.setMissing([a, b], true)
            try backupService.restore(backup)
            let marks = try container.mainContext.fetch(FetchDescriptor<MissingCopyMark>()).map(\.copyID)
            #expect(marks == [a.id])
            #expect(a.shelf?.number == 1)
        }

        @Test func goneCopiesAreSkippedAndGapsClose() throws {
            let (container, shelves, service) = try fixture()
            try service.insert(release: Release(artist: "A", title: "1"), shelf: shelves[0], position: 1, instanceID: 21)
            let gone = try service.insert(release: Release(artist: "B", title: "2"), shelf: shelves[0], position: 2, instanceID: 22)
            let c = try service.insert(release: Release(artist: "C", title: "3"), shelf: shelves[0], position: 3, instanceID: 23)
            let backupService = ShelfBackupService(context: container.mainContext)
            let backup = try backupService.makeBackup()

            try service.delete(gone)
            let fresh = try service.insert(release: Release(artist: "N", title: "neu"), shelf: nil, instanceID: 24)
            let preview = try backupService.preview(backup)
            #expect(preview.placed == 2)
            #expect(preview.missing == 1)
            #expect(preview.unplaced == 1)

            try backupService.restore(backup)
            #expect(c.shelf?.number == 1 && c.positionInShelf == 2)
            #expect(fresh.shelf == nil)
        }

        @Test func duplicateAndLockedPlacementsInAFileStayConsistent() throws {
            let (container, shelves, service) = try fixture()
            let a = try service.insert(release: Release(artist: "A", title: "1"), shelf: nil, instanceID: 31)
            let b = try service.insert(release: Release(artist: "B", title: "2"), shelf: nil, instanceID: 32)
            let c = try service.insert(release: Release(artist: "C", title: "3"), shelf: nil, instanceID: 33)
            // Hand-edited file: A twice, C in a locked shelf and also "nicht im Regal".
            let backup = ShelfBackup(owner: nil, createdAt: .now,
                shelves: [.init(number: 4, isReserved: true, name: "Deko")],
                placements: [.init(instanceID: 31, shelf: 1, position: 1), .init(instanceID: 32, shelf: 1, position: 2),
                             .init(instanceID: 31, shelf: 2, position: 1), .init(instanceID: 33, shelf: 4, position: 1)],
                notInShelf: [33])
            let backupService = ShelfBackupService(context: container.mainContext)
            #expect(try backupService.preview(backup).placed == 2)
            try backupService.restore(backup)
            #expect(a.shelf?.number == 1 && a.positionInShelf == 1)
            #expect(b.shelf?.number == 1 && b.positionInShelf == 2)
            #expect(shelves[1].copies.isEmpty)
            #expect(c.shelf == nil)
            let exclusions = try container.mainContext.fetch(FetchDescriptor<OptimizationExclusion>())
            #expect(exclusions.map(\.copyID) == [c.id])
        }

        @Test func previewAndRestoreAgreeOnTheCompartments() throws {
            let (container, _, service) = try fixture()
            let a = try service.insert(release: Release(artist: "A", title: "1"), shelf: nil, instanceID: 61)
            let b = try service.insert(release: Release(artist: "B", title: "2"), shelf: nil, instanceID: 62)
            let backupService = ShelfBackupService(context: container.mainContext)
            // Hand-edited: a 1 × 1 cabinet listing two compartments – only the first is rebuilt.
            let overfull = ShelfBackup(owner: nil, createdAt: .now, shelves: [],
                cabinets: [.init(name: "Klein", columns: 1, rows: 1, isActive: true, shelves: [1, 2])],
                placements: [.init(instanceID: 61, shelf: 1, position: 1), .init(instanceID: 62, shelf: 2, position: 1)],
                notInShelf: [])
            #expect(try backupService.preview(overfull).placed == 1)
            try backupService.restore(overfull)
            #expect(a.shelf?.number == 1 && b.shelf == nil)
            // An empty cabinet list is no list: the file addresses compartments 1…12 like older ones.
            let noCabinets = ShelfBackup(owner: nil, createdAt: .now, shelves: [], cabinets: [],
                placements: [.init(instanceID: 62, shelf: 1, position: 1)], notInShelf: [])
            #expect(try backupService.preview(noCabinets).placed == 1)
        }

        @Test func restoringTheCurrentLayoutNeedsNoConfirmation() throws {
            let (container, shelves, service) = try fixture()
            try service.insert(release: Release(artist: "A", title: "1"), shelf: shelves[0], instanceID: 71)
            let backupService = ShelfBackupService(context: container.mainContext)
            let backup = try backupService.makeBackup()
            #expect(try backupService.preview(backup).unchanged)
            #expect(try !backupService.preview(backup).changesCabinets)
            try service.configure(shelves[1], name: "", isReserved: true)
            #expect(try !backupService.preview(backup).unchanged)
            // A differently sized cabinet in the file is announced.
            var resized = backup
            resized.cabinets?[0].columns += 1
            let preview = try backupService.preview(resized)
            #expect(preview.changesCabinets && preview.message.contains("Auch die Regale"))
        }

        @Test func emptyLayoutIsRecognised() throws {
            let (container, shelves, service) = try fixture()
            let backupService = ShelfBackupService(context: container.mainContext)
            #expect(try backupService.makeBackup().isEmpty)
            try service.configure(shelves[0], name: "", isReserved: true)
            #expect(try !backupService.makeBackup().isEmpty)
        }

        @Test func retentionKeepsRecentAndOnePerDay() {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
            let now = Date(timeIntervalSince1970: 1_790_000_000)
            // 30 changes today, newest first, then one backup on each of 20 earlier days.
            let today = (0..<30).map { now.addingTimeInterval(-Double($0) * 60) }
            let earlier = (1...20).map { now.addingTimeInterval(-Double($0) * 86_400) }
            let kept = ShelfAutoBackup.retained(today + earlier, keptCount: 10, keptDays: 14, calendar: calendar)
            #expect(Array(kept.prefix(10)) == Array(0..<10))
            // Today already counts as a day: 13 earlier days survive, the burst doesn't push them out.
            #expect(Set(kept) == Set(Array(0..<10) + Array(30..<43)))
        }

        @Test func restoreBeforeSyncIsRefusedAndLeavesTheShelfAlone() throws {
            let (container, shelves, service) = try fixture()
            let current = try service.insert(release: Release(artist: "A", title: "1"), shelf: shelves[0], instanceID: 41)
            // A backup whose records aren't here (not synced yet, or another account).
            let foreign = ShelfBackup(owner: "other", createdAt: .now,
                shelves: [.init(number: 1, isReserved: true, name: "Deko")],
                placements: [.init(instanceID: 999, shelf: 2, position: 1)], notInShelf: [])
            let backupService = ShelfBackupService(context: container.mainContext)
            #expect(throws: ShelfBackupError.noMatchingRecords) { try backupService.preview(foreign) }
            #expect(current.shelf?.number == 1)
            #expect(!shelves[0].isReserved)
        }

        @Test func previewWarnsWhenMostRecordsAreMissing() throws {
            let (container, _, service) = try fixture()
            try service.insert(release: Release(artist: "A", title: "1"), shelf: nil, instanceID: 51)
            let backup = ShelfBackup(owner: nil, createdAt: .now, shelves: [],
                placements: [.init(instanceID: 51, shelf: 1, position: 1), .init(instanceID: 52, shelf: 1, position: 2),
                             .init(instanceID: 53, shelf: 1, position: 3)], notInShelf: [])
            let preview = try ShelfBackupService(context: container.mainContext).preview(backup)
            #expect(preview.placed == 1 && preview.missing == 2)
            #expect(preview.message.contains("Mehr als die Hälfte"))
        }

        @Test func demoStoresNeverWriteRealBackups() throws {
            let (container, _, _) = try fixture()
            #expect(try ShelfAutoBackup.shared.backUpNow(ShelfBackupService(context: container.mainContext)) == false)
        }

        @Test func onlyOwnFilesCountAsAutomaticBackups() {
            #expect(ShelfAutoBackup.isOwnFile("Belegung 2026-09-24 10-41-05.json"))
            #expect(ShelfAutoBackup.isOwnFile("Belegung 2026-09-24 10-41-05 +0200.json"))
            #expect(!ShelfAutoBackup.isOwnFile("Belegung Kopie.json"))
            #expect(!ShelfAutoBackup.isOwnFile("Plattenregal Belegung 2026-09-24.json"))
            #expect(!ShelfAutoBackup.isOwnFile("Belegung 2026-09-24 10-41-05.json.bak"))
        }

        /// Pruning and the "unchanged?" check go by the time in the name, without reading the files.
        @Test func fileNamesCarryTheirTimeInOrder() throws {
            let earlier = try #require(ShelfAutoBackup.fileDate(of: "Belegung 2026-09-24 09-59-59.json"))
            let later = try #require(ShelfAutoBackup.fileDate(of: "Belegung 2026-09-24 10-00-00.json"))
            #expect(later.timeIntervalSince(earlier) == 1)
            #expect(ShelfAutoBackup.fileDate(of: "Belegung Kopie.json") == nil)
            // With the offset: the repeated hour in autumn keeps its order.
            let summer = try #require(ShelfAutoBackup.fileDate(of: "Belegung 2026-10-25 02-30-00 +0200.json"))
            let winter = try #require(ShelfAutoBackup.fileDate(of: "Belegung 2026-10-25 02-10-00 +0100.json"))
            #expect(winter.timeIntervalSince(summer) == 40 * 60)
            let date = Date(timeIntervalSince1970: 1_790_000_000)
            let berlin = ShelfAutoBackup.fileName(for: date, in: TimeZone(identifier: "Europe/Berlin")!)
            let newYork = ShelfAutoBackup.fileName(for: date, in: TimeZone(identifier: "America/New_York")!)
            #expect(berlin != newYork && ShelfAutoBackup.isOwnFile(berlin))
            #expect(ShelfAutoBackup.fileDate(of: berlin) == date && ShelfAutoBackup.fileDate(of: newYork) == date)
        }

        @Test func foreignAndNewerFilesAreRejected() {
            #expect(throws: ShelfBackupError.self) { try ShelfBackupService.decode(Data("{\"foo\":1}".utf8)) }
            #expect(throws: ShelfBackupError.self) { try ShelfBackupService.decode(Data("{\"version\":99}".utf8)) }
        }

        @Test func sameLayoutIgnoresTime() throws {
            let (container, _, _) = try fixture()
            let service = ShelfBackupService(context: container.mainContext)
            let first = try service.makeBackup(at: .distantPast)
            let second = try service.makeBackup()
            #expect(first.hasSameLayout(as: second))
            #expect(first != second)
        }
    }
}
