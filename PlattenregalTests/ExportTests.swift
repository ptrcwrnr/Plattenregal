import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests {
    @MainActor struct ExportTests {
        private func fixture() throws -> (ModelContainer, [Shelf], PositionService) {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let shelves = try container.mainContext.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
            return (container, shelves, PositionService(context: container.mainContext))
        }

        @Test func csvEscaping() {
            #expect(CSVWriter.escape("Plain", delimiter: ";") == "Plain")
            #expect(CSVWriter.escape("A; B", delimiter: ";") == "\"A; B\"")
            #expect(CSVWriter.escape("A, B", delimiter: ";") == "A, B")
            #expect(CSVWriter.escape("A, B", delimiter: ",") == "\"A, B\"")
            #expect(CSVWriter.escape("12\" Single", delimiter: ";") == "\"12\"\" Single\"")
            #expect(CSVWriter.escape("Zeile\nzwei", delimiter: ";") == "\"Zeile\nzwei\"")
            #expect(CSVWriter.escape(" Leerzeichen", delimiter: ";") == "\" Leerzeichen\"")
        }

        @Test func csvKeepsFormulasAsText() {
            #expect(CSVWriter.escape("-M-", delimiter: ";") == "'-M-")
            #expect(CSVWriter.escape("=HYPERLINK(\"x\")", delimiter: ";") == "\"'=HYPERLINK(\"\"x\"\")\"")
            #expect(CSVWriter.escape("@Home", delimiter: ";") == "'@Home")
            #expect(CSVWriter.escape("+44", delimiter: ";") == "+44")
            #expect(CSVWriter.escape("-5", delimiter: ";") == "-5")
            #expect(CSVWriter.escape("Moby", delimiter: ";") == "Moby")
        }

        @Test func countMatchesTheExportedRows() throws {
            let (container, shelves, service) = try fixture()
            try service.insert(release: Release(artist: "A", title: "1"), shelf: shelves[0], owner: "me")
            try service.insert(release: Release(artist: "B", title: "2"), shelf: nil, owner: "me")
            let gone = try service.insert(release: Release(artist: "C", title: "3"), shelf: nil, owner: "me")
            gone.discogsActive = false
            try container.mainContext.save()
            let exporter = CollectionExportService(context: container.mainContext)
            #expect(exporter.count(.collection) == 2)
            #expect(try exporter.table(ExportOptions()).rows.count == 2)
            #expect(exporter.count(.wantlist) == 0)
        }

        @Test func datesUseTheLocalDay() throws {
            // 00:30 in Berlin is still the previous day in UTC.
            let date = try Date.ISO8601FormatStyle().parse("2026-09-23T22:30:00Z")
            #expect(ExportDate.day(date, in: TimeZone(identifier: "Europe/Berlin")!) == "2026-09-24")
            #expect(ExportDate.day(date, in: TimeZone(identifier: "UTC")!) == "2026-09-23")
        }

        @Test func csvStartsWithByteOrderMarkAndUsesCRLF() {
            let table = ExportTable(columns: ["Interpret", "Titel"], rows: [.init(section: nil, values: ["Björk", "Post"])])
            let data = CSVWriter.data(for: table, delimiter: .semicolon)
            #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
            #expect(String(decoding: data.dropFirst(3), as: UTF8.self) == "Interpret;Titel\r\nBjörk;Post\r\n")
        }

        @Test func shelfOrderWalksShelvesThenUnplaced() throws {
            let (container, shelves, service) = try fixture()
            try service.insert(release: Release(artist: "Zappa", title: "Z"), shelf: nil)
            try service.insert(release: Release(artist: "Beta", title: "B"), shelf: shelves[1], position: 1)
            try service.insert(release: Release(artist: "Alpha", title: "A"), shelf: shelves[0], position: 1)
            try service.insert(release: Release(artist: "Amber", title: "A2"), shelf: shelves[0], position: 2)
            try service.insert(release: Release(artist: "Abba", title: "U"), shelf: nil)

            let table = try CollectionExportService(context: container.mainContext)
                .table(ExportOptions(source: .collection, order: .shelf, groups: [.location]))
            let artist = try #require(table.column(ExportColumn.artist))
            let shelf = try #require(table.column(ExportColumn.shelf))
            let position = try #require(table.column(ExportColumn.position))
            #expect(table.rows.map { $0.values[artist] } == ["Alpha", "Amber", "Beta", "Abba", "Zappa"])
            #expect(table.rows.map { $0.values[shelf] } == ["1", "1", "2", "", ""])
            #expect(table.rows.map { $0.values[position] } == ["1", "2", "1", "", ""])
            #expect(table.rows.last?.section == "Ohne Fach")
            #expect(table.rows.first?.section?.hasPrefix("Fach 1") == true)
        }

        @Test func columnGroupsAreOptional() throws {
            let (container, shelves, service) = try fixture()
            let release = Release(artist: "Moby (2)", title: "Play")
            release.tracks = [Track(position: "A1", title: "Honey", duration: "3:27")]
            try service.insert(release: release, shelf: shelves[0])

            let exporter = CollectionExportService(context: container.mainContext)
            let plain = try exporter.table(ExportOptions(source: .collection, order: .artist, groups: []))
            #expect(plain.column(ExportColumn.shelf) == nil)
            #expect(plain.column(ExportColumn.tracklist) == nil)
            #expect(plain.rows.first?.values.first == "Moby")
            #expect(plain.rows.allSatisfy { $0.section == nil })

            let full = try exporter.table(ExportOptions(source: .collection, order: .artist, groups: Set(ExportColumnGroup.allCases)))
            #expect(full.rows.allSatisfy { $0.values.count == full.columns.count })
            let tracklist = try #require(full.column(ExportColumn.tracklist))
            #expect(full.rows.first?.values[tracklist] == "A1 Honey (3:27)")
            // The copy group holds only what Discogs provides.
            #expect(full.column(ExportColumn.folder) != nil && full.column(ExportColumn.added) != nil)
            #expect(full.columns.allSatisfy { !["Zustand Platte", "Zustand Hülle", "Notizen", "Bewertung"].contains($0) })
            let link = try #require(full.column(ExportColumn.link))
            #expect(full.rows.first?.values[link] == "https://www.discogs.com/release/\(release.discogsID)")
        }

        @Test func pdfIsProduced() throws {
            let (container, shelves, service) = try fixture()
            try service.insert(release: Release(artist: "Alpha", title: "A"), shelf: shelves[0])
            let table = try CollectionExportService(context: container.mainContext)
                .table(ExportOptions(source: .collection, order: .shelf, groups: [.location]))
            let data = try PDFListWriter.data(for: table, title: "Test", subtitle: "Untertitel")
            #expect(data.starts(with: Array("%PDF".utf8)))
        }
    }
}
