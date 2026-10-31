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
                                   artist: "A\(offset)", title: "T", seed: offset, tracks: [], details: "", place: "", isPlaced: false, cover: nil)
            }
            let snapshot = RecordOfTheDay(design: .classic, classicFrame: .sleeve, accent: nil, days: days, history: [])
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

        @Test func modernAccentIsStoredForLightAndDark() throws {
            #expect(RecordOfTheDayPublisher.tint(.system) == nil)
            let green = try #require(RecordOfTheDayPublisher.tint(.green))
            #expect(green.light.count == 3 && green.dark.count == 3)
            #expect(abs(green.light[1] - 0.62) < 0.01)
        }

        @Test func thePositionStaysWithItsNumber() {
            #expect(WidgetPlace.keepingNumber("KALLAX · B – De · Position 14") == "KALLAX · B – De · Position\u{00A0}14")
            #expect(WidgetPlace.keepingNumber("Gehört in „Ma – Mo“") == "Gehört in „Ma – Mo“")
            #expect(WidgetPlace.keepingNumber("Fach 3") == "Fach\u{00A0}3")
        }

        @Test func aWidgetCanShowTheOtherDesign() {
            let snapshot = RecordOfTheDay(design: .classic, classicFrame: .classicMat,
                                          accent: RecordOfTheDayPublisher.tint(.green), days: [], history: [])
            let app = WidgetLook(snapshot)
            #expect(app.isClassic && app.frame == .classicMat)
            let modern = WidgetLook(snapshot, design: .modern)
            #expect(!modern.isClassic && modern.frame == .modernMat)
            let classic = WidgetLook(RecordOfTheDay(design: .modern, classicFrame: .sleeve, accent: nil, days: [], history: []), design: .classic)
            #expect(classic.isClassic && classic.frame == .sleeve)
            // Nothing written yet: Klassisch.
            #expect(WidgetLook(nil).isClassic)
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
            #expect(first.days.first { $0.artist == "Air" }?.place.contains("Position 1") == true)

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

        @Test func anEmptyCollectionWritesNoDays() async throws {
            let (container, _, folder) = try fixture()
            defer { try? FileManager.default.removeItem(at: folder) }
            let publisher = RecordOfTheDayPublisher(folder: folder, reload: {})
            publisher.attach(container)
            await publisher.publish()
            #expect(RecordOfTheDay.load(from: folder)?.days.isEmpty == true)
        }

        // MARK: The widget's views

        /// The widget in each size and design, light and dark, drawn into
        /// images – they must have content of their own size. With
        /// `PLATTENREGAL_WIDGET_RENDERS` set (`TEST_RUNNER_PLATTENREGAL_WIDGET_RENDERS=1`
        /// for xcodebuild) they are kept to look at, in the test host's temporary folder.
        @Test func widgetViewsDrawInEverySizeAndDesign() throws {
            let sizes: [(WidgetFamily, CGSize)] = [(.systemSmall, CGSize(width: 170, height: 170)),
                                                    (.systemMedium, CGSize(width: 364, height: 170)),
                                                    (.systemLarge, CGSize(width: 364, height: 382))]
            let day = RecordOfTheDay.Day(day: 1, date: Date(), copyID: UUID(), artist: "Boards of Canada",
                                         title: "Music Has the Right to Children", seed: 7,
                                         tracks: (1...14).map { RecordOfTheDay.TrackLine(position: "A\($0)", title: "Track Nummer \($0) mit einem langen Titel") },
                                         details: "1998 · Warp",
                                         place: "KALLAX · A – Be · Position 12", isPlaced: true, cover: nil)
            let unplaced = RecordOfTheDay.Day(day: 1, date: Date(), copyID: UUID(), artist: "Moderat",
                                              title: "II", seed: 99, tracks: [], details: "2013 · Monkeytown Records",
                                              place: "Gehört in „KALLAX · Ma – Mo“", isPlaced: false, cover: nil)
            // Inside the sandbox of the test host: its temporary folder.
            let keep = ProcessInfo.processInfo.environment["PLATTENREGAL_WIDGET_RENDERS"] == nil ? nil
                : FileManager.default.temporaryDirectory.appendingPathComponent("WidgetRenders", isDirectory: true)
            // The app set to Klassisch; each widget in its own design.
            let snapshot = RecordOfTheDay(design: .classic, classicFrame: .sleeve,
                                          accent: RecordOfTheDayPublisher.tint(.purple), days: [day], history: [])
            for design in [RecordOfTheDay.Design.classic, .modern] {
                for (dark, tinted) in [(false, false), (true, false), (false, true)] {
                    for (family, size) in sizes {
                        for (name, shown) in [("platte", day as RecordOfTheDay.Day?), ("ohne-fach", unplaced), ("leer", nil)] {
                            let view = RecordOfTheDayView(snapshot: shown == nil ? nil : snapshot, day: shown, family: family,
                                                          design: design, folder: nil,
                                                          renderingMode: tinted ? .accented : .fullColor)
                                .frame(width: size.width, height: size.height)
                                .background(WidgetLook(snapshot, design: design).background)
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
                                let file = keep.appendingPathComponent("\(design.rawValue)-\(tinted ? "glas" : dark ? "dunkel" : "hell")-\(family.description)-\(name).png")
                                let rep = NSBitmapImageRep(cgImage: drawn)
                                try rep.representation(using: .png, properties: [:])?.write(to: file)
                            }
                        }
                    }
                }
            }
        }
    }
}
