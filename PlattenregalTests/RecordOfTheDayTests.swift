import AppKit
import Foundation
import SwiftData
import SwiftUI
import Testing
import WidgetKit
@testable import Plattenregal

extension AllTests {
    /// The widget „Platte des Tages“: which record a day gets, what the app
    /// writes for the widget, the link back into the shelf and the widget's views.
    @MainActor struct RecordOfTheDayTests {
        private static func candidates(_ count: Int) -> [(id: UUID, key: UInt64)] {
            (0..<count).map { (UUID(), UInt64($0 + 1)) }
        }

        // MARK: Picking

        @Test func picksAreTheSameForTheSameDaysAndRecords() {
            let candidates = Self.candidates(50)
            let days = Array(1_000..<1_014)
            let first = RecordOfTheDayPublisher.picks(for: days, candidates: candidates, kept: [:], history: [])
            let second = RecordOfTheDayPublisher.picks(for: days, candidates: candidates.reversed(), kept: [:], history: [])
            #expect(first == second)
            #expect(first.count == days.count)
        }

        @Test func noRecordComesBackWithinTheGap() {
            let candidates = Self.candidates(200)
            let days = Array(5_000..<5_000 + RecordOfTheDayPublisher.repeatGap + 1)
            let picks = RecordOfTheDayPublisher.picks(for: days, candidates: candidates, kept: [:], history: [])
            #expect(Set(picks.values).count == days.count)
        }

        @Test func historyAndKeptDaysBlockRepeats() {
            let candidates = Self.candidates(30)
            let history = (0..<10).map { RecordOfTheDay.Pick(day: 90 + $0, copyID: candidates[$0].id) }
            let kept = [101: candidates[10].id]
            let picks = RecordOfTheDayPublisher.picks(for: Array(100..<114), candidates: candidates, kept: kept, history: history)
            #expect(picks[101] == candidates[10].id)
            let recent = Set(history.map(\.copyID)).union([candidates[10].id])
            for day in 100..<114 where day != 101 { #expect(!recent.contains(picks[day]!)) }
            // A small collection: 30 records, gap 29 – no repeats in 14 days.
            #expect(Set(picks.values).count == 14)
        }

        @Test func aKeptDayIsPickedAgainOnlyWhenItsRecordIsGone() {
            let candidates = Self.candidates(20)
            let gone = UUID()
            let picks = RecordOfTheDayPublisher.picks(for: [7, 8], candidates: candidates,
                                                      kept: [7: candidates[3].id, 8: gone], history: [])
            #expect(picks[7] == candidates[3].id)
            #expect(picks[8] != nil && picks[8] != gone)
        }

        @Test func smallCollectionsRepeatAsLittleAsTheyCan() {
            #expect(RecordOfTheDayPublisher.picks(for: [1, 2, 3], candidates: [], kept: [:], history: []).isEmpty)
            let one = Self.candidates(1)
            #expect(Set(RecordOfTheDayPublisher.picks(for: [1, 2, 3], candidates: one, kept: [:], history: []).values) == [one[0].id])
            let three = Self.candidates(3)
            let picks = RecordOfTheDayPublisher.picks(for: Array(1...9), candidates: three, kept: [:], history: [])
            // Gap 2: any three days in a row show three different records.
            for day in 1...7 { #expect(Set([picks[day], picks[day + 1], picks[day + 2]]).count == 3) }
        }

        @Test func historyKeepsOnlyRecentPastDaysInOrder() {
            let id = UUID()
            let picks = [RecordOfTheDay.Pick(day: 500, copyID: id), RecordOfTheDay.Pick(day: 400, copyID: id),
                         RecordOfTheDay.Pick(day: 200, copyID: id), RecordOfTheDay.Pick(day: 501, copyID: id)]
            #expect(RecordOfTheDayPublisher.trimmed(picks, before: 501).map(\.day) == [500])
            #expect(RecordOfTheDayPublisher.trimmed(picks, before: 460).map(\.day) == [400])
        }

        // MARK: Snapshot and link

        @Test func theDayShownFollowsTheClock() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let days = (0..<3).map { offset in
                RecordOfTheDay.Day(day: offset, date: start.addingTimeInterval(Double(offset) * 86_400), copyID: UUID(),
                                   artist: "A\(offset)", title: "T", seed: offset, details: "", place: "", isPlaced: false,
                                   rack: nil, cover: nil)
            }
            let snapshot = RecordOfTheDay(days: days, history: [])
            #expect(snapshot.day(at: start.addingTimeInterval(-10))?.day == 0)
            #expect(snapshot.day(at: start.addingTimeInterval(86_400 + 5))?.day == 1)
            #expect(snapshot.day(at: start.addingTimeInterval(30 * 86_400))?.day == 2)
            #expect(snapshot.days(from: start.addingTimeInterval(86_400)).map(\.day) == [1, 2])
        }

        @Test func linkLeadsBackToTheCopy() {
            let id = UUID()
            let link = RecordOfTheDay.link(to: id)
            #expect(link.absoluteString == "plattenregal://platte/\(id.uuidString)")
            #expect(RecordOfTheDay.copyID(from: link) == id)
            #expect(RecordOfTheDay.copyID(from: URL(string: "plattenregal://andere/\(id.uuidString)")!) == nil)
            #expect(RecordOfTheDay.copyID(from: URL(string: "https://platte/\(id.uuidString)")!) == nil)
            #expect(RecordOfTheDay.copyID(from: URL(string: "plattenregal://platte/kaputt")!) == nil)
        }

        @Test func thePositionStaysWithItsNumber() {
            #expect(WidgetPlace.keepingNumber("KALLAX · B – De · Position 14") == "KALLAX · B – De · Position\u{00A0}14")
            #expect(WidgetPlace.keepingNumber("Gehört in „Ma – Mo“") == "Gehört in „Ma – Mo“")
            #expect(WidgetPlace.keepingNumber("Fach 3") == "Fach\u{00A0}3")
        }

        /// The widget's timeline: today from now, later days from their
        /// start, read again when the last one begins – or at midnight at the
        /// end of what was written; empty without days, read again in an hour.
        @Test func theTimelineCoversTheNextDaysAndKnowsWhenToReadAgain() throws {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
            let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
            let days = (0..<5).map { offset in
                RecordOfTheDay.Day(day: offset, date: calendar.date(byAdding: .day, value: offset, to: start)!, copyID: UUID(),
                                   artist: "A\(offset)", title: "T", seed: offset, details: "", place: "", isPlaced: false,
                                   rack: nil, cover: nil)
            }
            let snapshot = RecordOfTheDay(days: days, history: [])
            let noon = start.addingTimeInterval(12 * 3600)
            let plan = RecordOfTheDay.plan(snapshot, now: noon, count: 3, calendar: calendar)
            #expect(plan.entries.map(\.day?.day) == [0, 1, 2])
            #expect(plan.entries.map(\.date) == [noon, days[1].date, days[2].date])
            #expect(plan.refresh == days[2].date)
            // On the last day written: that one, read again at midnight.
            let lastNoon = days[4].date.addingTimeInterval(12 * 3600)
            let end = RecordOfTheDay.plan(snapshot, now: lastNoon, count: 3, calendar: calendar)
            #expect(end.entries.map(\.day?.day) == [4])
            #expect(end.refresh == calendar.date(byAdding: .day, value: 5, to: start))
            // Weeks later without the app: the last day stays.
            let late = RecordOfTheDay.plan(snapshot, now: start.addingTimeInterval(40 * 86_400), count: 3, calendar: calendar)
            #expect(late.entries.map(\.day?.day) == [4])
            // Clock before the first day: the first.
            #expect(RecordOfTheDay.plan(snapshot, now: start.addingTimeInterval(-3600), count: 3, calendar: calendar).entries.first?.day?.day == 0)
            // Nothing written, or no days: one empty entry, again in an hour.
            for empty in [nil, RecordOfTheDay(days: [], history: [])] {
                let none = RecordOfTheDay.plan(empty, now: noon, count: 3, calendar: calendar)
                #expect(none.entries.count == 1 && none.entries[0].day == nil)
                #expect(none.refresh == noon.addingTimeInterval(RecordOfTheDay.emptyRefresh))
            }
        }

        /// A file of the earlier format (with the app's design, no racks) is
        /// not read: the widget waits for the app's new one instead of failing.
        @Test func anOlderFileIsNotRead() throws {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Format-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let old = #"{"formatVersion":1,"design":"modern","classicFrame":"sleeve","days":[],"history":[]}"#
            try Data(old.utf8).write(to: folder.appendingPathComponent(RecordOfTheDay.fileName))
            #expect(RecordOfTheDay.load(from: folder) == nil)
            try Data("kaputt".utf8).write(to: folder.appendingPathComponent(RecordOfTheDay.fileName))
            #expect(RecordOfTheDay.load(from: folder) == nil)
            try RecordOfTheDay(days: [], history: []).save(to: folder)
            #expect(RecordOfTheDay.load(from: folder)?.days.isEmpty == true)
        }

        /// The rack's cells always fit the same box, never larger than in the mockup.
        @Test func rackCellsFitEveryCabinetSize() {
            for columns in ShelfGeometry.sizeRange {
                for rows in ShelfGeometry.sizeRange {
                    let cell = RackMetrics.cell(columns: columns, rows: rows)
                    let width = CGFloat(columns) * cell.width + CGFloat(columns - 1) * RackMetrics.gap + 2 * RackMetrics.inset
                    let height = CGFloat(rows) * cell.height + CGFloat(rows - 1) * RackMetrics.gap + 2 * RackMetrics.inset
                    #expect(width <= RackMetrics.boxWidth + 0.001 && height <= RackMetrics.boxHeight + 0.001, "\(columns) × \(rows)")
                    #expect(cell.height <= RackMetrics.cellHeight && cell.height > 2, "\(columns) × \(rows)")
                }
            }
            #expect(RackMetrics.cell(columns: 4, rows: 3).height == RackMetrics.cellHeight)
            #expect(RackMetrics.cell(columns: 0, rows: 0).height > 0)
        }

        // MARK: Writing for the widget

        private final class Clock: @unchecked Sendable { var now = Date() }

        private func fixture() throws -> (ModelContainer, PositionService, URL) {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("PlatteDesTages-\(UUID().uuidString)", isDirectory: true)
            return (container, PositionService(context: container.mainContext), folder)
        }

        @Test func writesTwoWeeksWithCoversAndReloadsOnlyOnChange() async throws {
            let (container, positions, folder) = try fixture()
            defer { try? FileManager.default.removeItem(at: folder) }
            let shelves = try container.mainContext.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
            for (index, artist) in ["Air", "Beak", "Can", "Daft Punk", "Eno", "Faust"].enumerated() {
                try positions.insert(release: Release(artist: artist, title: "Album \(index)"), shelf: shelves[0],
                                     position: index + 1, instanceID: 100 + index)
            }
            try positions.insert(release: Release(artist: "Moderat", title: "II"), shelf: nil, instanceID: 200)
            var reloads = 0
            let clock = Clock()
            let publisher = RecordOfTheDayPublisher(folder: folder, reload: { reloads += 1 }, now: { clock.now })
            publisher.attach(container)

            await publisher.publish()
            let first = try #require(RecordOfTheDay.load(from: folder))
            #expect(first.days.count == RecordOfTheDayPublisher.daysAhead)
            #expect(reloads == 1)
            // Records without a Discogs image get a drawn cover, written as a file.
            for day in first.days {
                let name = try #require(day.cover)
                #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path))
            }
            // Seven records: no repeats within six days.
            for start in 0..<(first.days.count - 6) {
                #expect(Set(first.days[start..<start + 7].map(\.copyID)).count == 7)
            }
            let moderat = first.days.first { $0.artist == "Moderat" }
            #expect(moderat?.isPlaced == false)
            #expect(moderat?.place.hasPrefix("Gehört in") == true)
            // It belongs in the only compartment with records: the first of the 4 × 3.
            #expect(moderat?.rack == RecordOfTheDay.Rack(columns: 4, rows: 3, compartment: 0, locked: [],
                                                        label: moderat?.rack?.label ?? "", position: nil))
            let air = first.days.first { $0.artist == "Air" }
            #expect(air?.place.contains("Position 1") == true)
            #expect(air?.rack?.compartment == 0 && air?.rack?.position == 1)
            #expect(air.map { $0.place.contains($0.rack?.label ?? "-") } == true)

            // Nothing changed: nothing written, no reload.
            await publisher.publish()
            #expect(reloads == 1)

            // The next day: the days move on, yesterday goes into the history,
            // today keeps the record it had as tomorrow.
            clock.now = try #require(Calendar.current.date(byAdding: .day, value: 1, to: clock.now))
            await publisher.publish()
            let second = try #require(RecordOfTheDay.load(from: folder))
            #expect(reloads == 2)
            #expect(second.days.first?.copyID == first.days[1].copyID)
            #expect(second.history.last?.copyID == first.days[0].copyID)
            #expect(Array(second.days.dropLast()).map(\.copyID) == Array(first.days.dropFirst()).map(\.copyID))
            // Yesterday's cover is gone unless another day shows it too.
            let used = Set(second.days.compactMap(\.cover))
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".jpg") }
            #expect(Set(files) == used)
        }

        @Test func aMovedRecordShowsItsNewPlace() async throws {
            let (container, positions, folder) = try fixture()
            defer { try? FileManager.default.removeItem(at: folder) }
            let shelves = try container.mainContext.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
            let only = try positions.insert(release: Release(artist: "Air", title: "Moon Safari"), shelf: shelves[0], position: 1, instanceID: 1)
            // Not today's record (marked „Ohne Regalplatz“ would still be one):
            // only there so the compartment's name changes with the move.
            let neighbour = try positions.insert(release: Release(artist: "Beak", title: ">>"), shelf: shelves[0], position: 2, instanceID: 2)
            var reloads = 0
            let publisher = RecordOfTheDayPublisher(folder: folder, reload: { reloads += 1 })
            publisher.attach(container)
            await publisher.publish()
            let snapshot = try #require(RecordOfTheDay.load(from: folder))
            let before = try #require(snapshot.days.first { $0.copyID == only.id })
            #expect(before.isPlaced && before.place.contains("A – B"))
            #expect(snapshot.days.contains { $0.copyID == neighbour.id })

            try positions.move(only, to: shelves[1], position: 1)
            await publisher.publish()
            let after = try #require(RecordOfTheDay.load(from: folder)?.days.first { $0.day == before.day })
            #expect(after.copyID == only.id)
            #expect(after.place != before.place)
            #expect(reloads == 2)
        }

        @Test func aRecordThatLeftTheCollectionIsReplaced() async throws {
            let (container, positions, folder) = try fixture()
            defer { try? FileManager.default.removeItem(at: folder) }
            let records = try (0..<5).map {
                try positions.insert(release: Release(artist: "Artist \($0)", title: "T"), shelf: nil, instanceID: 10 + $0)
            }
            let publisher = RecordOfTheDayPublisher(folder: folder, reload: {})
            publisher.attach(container)
            await publisher.publish()
            let today = try #require(RecordOfTheDay.load(from: folder)?.days.first)
            let sold = try #require(records.first { $0.id == today.copyID })
            sold.discogsActive = false
            try container.mainContext.save()
            // As a sync reports it.
            LibraryChanges.shared.syncDidCommit()
            await publisher.publish()
            let snapshot = try #require(RecordOfTheDay.load(from: folder))
            #expect(!snapshot.days.contains { $0.copyID == sold.id })
            #expect(snapshot.days.count == RecordOfTheDayPublisher.daysAhead)
        }

        /// The rack as the shelf page lays it out: place = `sortOrder`, locked
        /// compartments and places without one hollow, the record's never.
        @Test func theRackMatchesTheShelfPage() throws {
            let (container, positions, _) = try fixture()
            let context = container.mainContext
            let cabinets = CabinetService(context: context)
            let kallax = try #require(try cabinets.cabinets().first)
            let shelves = kallax.orderedShelves
            try positions.configure(shelves[0], name: "Mäusi", isReserved: true)
            try positions.configure(shelves[1], name: "", isReserved: true)
            let record = try positions.insert(release: Release(artist: "Blank&Jones", title: "The Extended Singles"),
                                              shelf: shelves[9], position: 1, instanceID: 1)
            var rack = try #require(RecordOfTheDayPublisher.rack(for: shelves[9], labels: ShelfLabels(), position: record.positionInShelf))
            #expect(rack.columns == 4 && rack.rows == 3 && rack.compartment == 9 && rack.position == 1)
            #expect(rack.locked == [0, 1])
            #expect(rack.label == shelves[9].title)
            // A locked compartment names itself.
            #expect(RecordOfTheDayPublisher.rack(for: shelves[0], labels: ShelfLabels(), position: nil)?.label == "Mäusi")
            #expect(RecordOfTheDayPublisher.rack(for: shelves[1], labels: ShelfLabels(), position: nil)?.label == "Gesperrtes Fach")
            // A place without a compartment (not possible through the app) stays hollow, nothing shifts.
            context.delete(shelves[5])
            try context.save()
            rack = try #require(RecordOfTheDayPublisher.rack(for: shelves[9], labels: ShelfLabels(), position: 1))
            #expect(rack.compartment == 9 && rack.locked == [0, 1, 5])
            // A second cabinet has its own grid.
            let eket = try cabinets.add(name: "EKET", columns: 2, rows: 2)
            let last = try #require(eket.orderedShelves.last)
            #expect(RecordOfTheDayPublisher.rack(for: last, labels: ShelfLabels(), position: nil)
                    == RecordOfTheDay.Rack(columns: 2, rows: 2, compartment: 3, locked: [], label: last.title, position: nil))
            // A place outside the grid (inconsistent store): no rack rather than a wrong one.
            last.sortOrder = 9
            #expect(RecordOfTheDayPublisher.rack(for: last, labels: ShelfLabels(), position: nil) == nil)
        }

        /// What the widget gets in the cases without a compartment, after
        /// resizing and switching off a cabinet, and after deleting one.
        @Test func edgeCasesOfThePlace() async throws {
            let (container, positions, folder) = try fixture()
            defer { try? FileManager.default.removeItem(at: folder) }
            let cabinets = CabinetService(context: container.mainContext)
            let publisher = RecordOfTheDayPublisher(folder: folder, reload: {})
            publisher.attach(container)
            // One record without a shelf, no compartment holds records yet:
            // nowhere to belong.
            let lonely = try positions.insert(release: Release(artist: "Air", title: "Moon Safari"), shelf: nil, instanceID: 1)
            await publisher.publish()
            var today = try #require(RecordOfTheDay.load(from: folder)?.days.first)
            #expect(today.copyID == lonely.id && today.rack == nil && !today.isPlaced)
            #expect(today.place == "Noch nicht einsortiert")
            // „Ohne Regalplatz“: no rack either.
            try positions.setExcluded([lonely], true)
            await publisher.publish()
            today = try #require(RecordOfTheDay.load(from: folder)?.days.first)
            #expect(today.rack == nil && today.place == "Ohne Regalplatz")
            // Placed, then the cabinet grows: the rack follows.
            let kallax = try #require(try cabinets.cabinets().first)
            try positions.move(lonely, to: kallax.orderedShelves[6], position: 1)
            await publisher.publish()
            today = try #require(RecordOfTheDay.load(from: folder)?.days.first)
            #expect(today.rack?.compartment == 6 && today.rack?.position == 1 && today.isPlaced)
            try cabinets.resize(kallax, columns: 5, rows: 3)
            await publisher.publish()
            today = try #require(RecordOfTheDay.load(from: folder)?.days.first)
            #expect(today.rack?.columns == 5 && today.rack?.compartment == 6)
            // Switched off (records put into storage): still shown where it
            // stands. The app keeps one cabinet active, so a second one first.
            try cabinets.add(name: "EKET", columns: 2, rows: 2)
            try cabinets.setActive(kallax, false)
            await publisher.publish()
            today = try #require(RecordOfTheDay.load(from: folder)?.days.first)
            #expect(today.rack?.position == 1)
            // Taken out and the cabinet deleted: back to nowhere, no crash on
            // the deleted compartments.
            try positions.unplace(lonely)
            try cabinets.delete(kallax)
            await publisher.publish()
            today = try #require(RecordOfTheDay.load(from: folder)?.days.first)
            #expect(today.copyID == lonely.id && today.rack == nil)
        }

        @Test func anEmptyCollectionWritesNoDays() async throws {
            let (container, _, folder) = try fixture()
            defer { try? FileManager.default.removeItem(at: folder) }
            let publisher = RecordOfTheDayPublisher(folder: folder, reload: {})
            publisher.attach(container)
            await publisher.publish()
            #expect(RecordOfTheDay.load(from: folder)?.days.isEmpty == true)
        }

        // MARK: The widget's views

        /// The widget in every case – standing, belonging, small and large
        /// cabinets, long names, no rack, nothing written – light and dark,
        /// drawn into images at the size macOS 27 gives it on the desktop
        /// (344 × 164 pt, read from the system log). With
        /// `PLATTENREGAL_WIDGET_RENDERS` set (`TEST_RUNNER_PLATTENREGAL_WIDGET_RENDERS=1`
        /// for xcodebuild) they are kept to look at, in the test host's temporary folder.
        @Test func widgetViewDrawsEveryCase() throws {
            let size = CGSize(width: 344, height: 164)
            func day(_ artist: String, _ title: String, place: String, placed: Bool, rack: RecordOfTheDay.Rack?) -> RecordOfTheDay.Day {
                RecordOfTheDay.Day(day: 1, date: Date(), copyID: UUID(), artist: artist, title: title, seed: artist.count * 97,
                                   details: "1998 · Warp", place: place, isPlaced: placed, rack: rack, cover: nil)
            }
            let cases: [(String, RecordOfTheDay.Day?)] = [
                ("steht", day("Boards of Canada", "Music Has the Right to Children", place: "KALLAX · A – Be · Position 12", placed: true,
                              rack: .init(columns: 4, rows: 3, compartment: 9, locked: [0, 1], label: "A – Be", position: 12))),
                ("gehoert-hin", day("Moderat", "II", place: "Gehört in „Ma – Mo“", placed: false,
                                    rack: .init(columns: 2, rows: 2, compartment: 3, locked: [], label: "Ma – Mo", position: nil))),
                ("6x6", day("Aphex Twin", "Selected Ambient Works 85–92", place: "Fach 36 · Position 3", placed: true,
                            rack: .init(columns: 6, rows: 6, compartment: 35, locked: [0, 7, 14], label: "Fach 36", position: 3))),
                ("1x1", day("Can", "Tago Mago", place: "Fach 1 · Position 1", placed: true,
                            rack: .init(columns: 1, rows: 1, compartment: 0, locked: [], label: "Fach 1", position: 1))),
                ("lange-namen", day("The Avalanches featuring Very Long Guest Artist Names", "Since I Left You (Deluxe Anniversary Edition)",
                                    place: "EKET · Mäusis Lieblingsfach mit sehr langem Namen · Position 128", placed: true,
                                    rack: .init(columns: 3, rows: 2, compartment: 4, locked: [5], label: "Mäusis Lieblingsfach mit sehr langem Namen", position: 128))),
                ("ohne-regalplatz", day("Air", "Moon Safari", place: "Ohne Regalplatz", placed: false, rack: nil)),
                ("leer", nil)
            ]
            // Inside the sandbox of the test host: its temporary folder.
            let keep = ProcessInfo.processInfo.environment["PLATTENREGAL_WIDGET_RENDERS"] == nil ? nil
                : FileManager.default.temporaryDirectory.appendingPathComponent("WidgetRenders", isDirectory: true)
            if let keep { try? FileManager.default.removeItem(at: keep) }
            for dark in [false, true] {
                for (name, shown) in cases {
                    let view = RecordOfTheDayView(snapshot: shown.map { RecordOfTheDay(days: [$0], history: []) }, day: shown, folder: nil)
                        .frame(width: size.width, height: size.height)
                        .background(AtelierPalette.paper)
                        .environment(\.colorScheme, dark ? .dark : .light)
                    var image: CGImage?
                    NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        image = renderer.cgImage
                    }
                    let drawn = try #require(image)
                    #expect(drawn.width == Int(size.width * 2) && drawn.height == Int(size.height * 2))
                    if let keep {
                        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
                        let file = keep.appendingPathComponent("\(dark ? "dunkel" : "hell")-\(name).png")
                        try NSBitmapImageRep(cgImage: drawn).representation(using: .png, properties: [:])?.write(to: file)
                    }
                }
            }
        }
    }
}
