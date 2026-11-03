import CoreGraphics
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

        @Test func releaseValuesAreTidied() {
            #expect(DiscogsName.catalogNumber("ASOT018, ASOT018") == "ASOT018")
            #expect(DiscogsName.catalogNumber("AQL 010, AQL 010 X") == "AQL 010, AQL 010 X")
            #expect(DiscogsName.catalogNumber("none, 1725773, none") == "1725773")
            #expect(DiscogsName.catalogNumber("None") == "")
            #expect(DiscogsName.catalogNumber("") == "")
            #expect(DiscogsName.listedOnce("Dance Division, Epic, Epic") == "Dance Division, Epic")
            #expect(DiscogsName.catalogNumber("DOS 202, dos 202") == "DOS 202")
            #expect(DiscogsName.format("1 · Vinyl · 12\" · 45 RPM") == "Vinyl · 12\" · 45 RPM")
            #expect(DiscogsName.format("2 · Vinyl · LP, 1 · CD · Album") == "2 × Vinyl · LP, CD · Album")
            #expect(DiscogsName.format("5 · Vinyl · 12\" · Album, 1 · Box Set") == "5 × Vinyl · 12\" · Album, Box Set")
            #expect(DiscogsName.format("") == "")
            #expect(DiscogsName.format("Vinyl, LP, Album") == "Vinyl, LP, Album")
        }

        @Test func recordCardAndExportShowTheSameTidyValues() {
            let release = Release(discogsID: 1, artist: "Moby", title: "Play")
            release.label = "Mute (2), Mute, V2"
            release.catalogNumber = "none, STUMM 172, STUMM 172"
            release.format = "1 · Vinyl · LP · Album"
            #expect(release.shownLabel == "Mute, V2")
            #expect(release.shownCatalogNumber == "STUMM 172")
            #expect(release.shownFormat == "Vinyl · LP · Album")
            // Nothing known: empty, so the card leaves the row out.
            let bare = Release(discogsID: 2, artist: "", title: "")
            bare.format = ""; bare.catalogNumber = "none"
            #expect(bare.shownLabel.isEmpty && bare.shownCatalogNumber.isEmpty && bare.shownFormat.isEmpty)
        }

        @Test func locationIsOffByDefaultAndCompact() throws {
            #expect(ExportOptions().groups.isEmpty && ExportSettings().groups.isEmpty)
            let (container, shelves, service) = try fixture()
            try service.insert(release: Release(artist: "A", title: "1"), shelf: shelves[0], owner: "me")
            let table = try CollectionExportService(context: container.mainContext)
                .table(ExportOptions(source: .collection, order: .shelf, groups: [.location]))
            #expect(Array(table.columns.suffix(3)) == [ExportColumn.cabinet, ExportColumn.shelf, ExportColumn.position])
            #expect(!table.columns.contains("Genres"))
            // The PDF's Fach column names the compartment; without one a dash, not the long status.
            #expect(table.rows.first?.place == "\(shelves[0].sortOrder)")
            #expect(ExportColumnGroup.copy.hint(for: .wantlist) == "Hinzufügedatum")
        }

        @Test func wantlistHasNoPlacesAndMatchingRows() throws {
            let (container, _, _) = try fixture()
            let context = container.mainContext
            for (id, artist) in [(1, "Zappa"), (2, "ABBA"), (3, "Þeyr")] {
                let release = Release(artist: artist, title: "T")
                release.discogsID = id
                context.insert(release)
                context.insert(WantlistEntry(owner: "me", release: release, releaseID: id))
            }
            try context.save()
            let table = try CollectionExportService(context: context)
                .table(ExportOptions(source: .wantlist, groups: Set(ExportColumnGroup.allCases)))
            #expect(table.column(ExportColumn.shelf) == nil && table.column(ExportColumn.folder) == nil)
            #expect(table.rows.allSatisfy { $0.values.count == table.columns.count && $0.section == nil })
            // Like the wantlist page: "Þeyr" after Z, as in the alphabet index.
            let artist = try #require(table.column(ExportColumn.artist))
            #expect(table.rows.map { $0.values[artist] } == WantlistPresentation.sorted(try context.fetch(FetchDescriptor<WantlistEntry>())).map { $0.release?.displayArtist ?? "" })
        }

        @Test func pdfSpansPagesAndHandlesEmptyLists() throws {
            let rows = (0..<200).map { index in
                ExportTable.Row(section: "Fach \(index / 70 + 1)",
                                values: [String(repeating: "Sehr langer Interpret ", count: 10), "Titel \(index)", "\(index + 1)"])
            }
            let table = ExportTable(columns: [ExportColumn.artist, ExportColumn.title, ExportColumn.position], rows: rows)
            let data = try PDFListWriter.data(for: table, title: "Test", subtitle: "")
            #expect(data.starts(with: Array("%PDF".utf8)))
            let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
            #expect(document.numberOfPages > 3)
            let empty = try PDFListWriter.data(for: ExportTable(columns: [ExportColumn.artist], rows: []), title: "Leer", subtitle: "")
            #expect(CGPDFDocument(CGDataProvider(data: empty as CFData)!)?.numberOfPages == 1)
        }

        @Test func trashedFolderCountsAsGone() {
            #expect(FolderAccess.isInTrash(URL(fileURLWithPath: "/Users/x/.Trash/Export")))
            #expect(FolderAccess.isInTrash(URL(fileURLWithPath: "/Volumes/Stick/.Trashes/501/Export")))
            #expect(!FolderAccess.isInTrash(URL(fileURLWithPath: "/Users/x/Library/Mobile Documents/com~apple~CloudDocs/Export")))
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

        @Test func saleListExportsOnlyMarkedRecords() throws {
            let (container, shelves, service) = try fixture()
            try service.insert(release: Release(artist: "Alpha", title: "A"), shelf: shelves[0], owner: "me")
            let placed = try service.insert(release: Release(artist: "Beta", title: "B"), shelf: shelves[1], owner: "me")
            let waiting = try service.insert(release: Release(artist: "Abba", title: "U"), shelf: nil, owner: "me")
            let exporter = CollectionExportService(context: container.mainContext)
            #expect(exporter.count(.sale) == 0)
            #expect(try exporter.table(ExportOptions(source: .sale)).rows.isEmpty)

            try service.setForSale([placed, waiting], true)
            #expect(exporter.count(.sale) == 2)
            let table = try exporter.table(ExportOptions(source: .sale, order: .shelf, groups: [.location]))
            let artist = try #require(table.column(ExportColumn.artist))
            let shelf = try #require(table.column(ExportColumn.shelf))
            #expect(table.rows.map { $0.values[artist] } == ["Beta", "Abba"])
            #expect(table.rows.map { $0.values[shelf] } == ["2", "Noch nicht einsortiert"])
            #expect(try exporter.table(ExportOptions(source: .sale, order: .artist)).rows.map { $0.values[artist] } == ["Abba", "Beta"])
            // The collection export stays complete.
            #expect(exporter.count(.collection) == 3)

            // Both files are built from it, as the export tab does.
            let pdf = try ExportSettings(format: .pdf, source: .sale).prepare(context: container.mainContext, labelStyle: .range)
            #expect(pdf.rows == 2)
            #expect(try pdf.render().starts(with: Array("%PDF".utf8)))
            let csv = try ExportSettings(format: .csv, source: .sale, order: .artist, delimiter: .semicolon)
                .prepare(context: container.mainContext, labelStyle: .range).render()
            let lines = String(decoding: csv.dropFirst(3), as: UTF8.self).components(separatedBy: "\r\n")
            #expect(lines.count == 4 && lines[1].hasPrefix("Abba;U;") && lines[2].hasPrefix("Beta;B;"))

            try service.sellAllForSale()
            #expect(exporter.count(.sale) == 0)
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
            #expect(table.rows.map { $0.values[shelf] } == ["1", "1", "2", "Noch nicht einsortiert", "Noch nicht einsortiert"])
            #expect(table.rows.map { $0.values[position] } == ["1", "2", "1", "", ""])
            #expect(table.rows.last?.section == "Noch nicht einsortiert")

            // Kept out of the shelves on purpose: after those still to be sorted in, under its own heading.
            let abba = try #require(try container.mainContext.fetch(FetchDescriptor<RecordCopy>()).first { $0.release?.artist == "Abba" })
            try service.setExcluded([abba], true)
            let later = try CollectionExportService(context: container.mainContext)
                .table(ExportOptions(source: .collection, order: .shelf, groups: [.location]))
            #expect(later.rows.map { $0.values[artist] } == ["Alpha", "Amber", "Beta", "Zappa", "Abba"])
            #expect(later.rows.suffix(2).map(\.section) == ["Noch nicht einsortiert", "Ohne Regalplatz"])
            #expect(later.rows.last?.values[shelf] == "Ohne Regalplatz")
            #expect(table.rows.first?.section?.hasPrefix("Fach 1") == true)
        }

        @Test func columnGroupsAreOptional() throws {
            let (container, shelves, service) = try fixture()
            let release = Release(artist: "Moby (2)", title: "Play")
            release.masterID = 0
            release.tracks = [Track(position: "A1", title: "Honey", duration: "3:27")]
            let copy = try service.insert(release: release, shelf: shelves[0])
            copy.discogsFolderID = 3; copy.discogsDateAdded = "2026-09-24T00:30:00+02:00"
            container.mainContext.insert(DiscogsFolder(owner: copy.discogsOwner, id: 3, name: "Kiste", count: 1))
            try container.mainContext.save()

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
            #expect(full.rows.first?.values[try #require(full.column(ExportColumn.folder))] == "Kiste")
            #expect(full.rows.first?.values[try #require(full.column(ExportColumn.added))]
                    == ExportDate.day(try #require(DiscogsDate.parse(copy.discogsDateAdded))))
            #expect(full.columns.allSatisfy { !["Zustand Platte", "Zustand Hülle", "Notizen", "Bewertung"].contains($0) })
            let link = try #require(full.column(ExportColumn.link))
            #expect(full.rows.first?.values[link] == "https://www.discogs.com/release/\(release.discogsID)")
            // Master ID 0 means "no master" at Discogs.
            #expect(full.rows.first?.values[try #require(full.column(ExportColumn.masterID))] == "")
        }

        @Test func scheduledExportWritesItsOwnChoiceOfLists() throws {
            // Stored in a fixed order, whatever order they were switched on in; unknown names are dropped.
            #expect(ScheduledExport.joined([.wantlist, .collection]) == "collection,wantlist")
            #expect(ScheduledExport.parseSources("wantlist,unbekannt,collection") == [.collection, .wantlist])
            #expect(ScheduledExport.parseSources("").isEmpty)

            // Only lists that hold records are written: an empty one keeps its last file.
            let (container, shelves, service) = try fixture()
            let context = container.mainContext
            #expect(ScheduledExport.nonEmpty([.collection, .wantlist, .sale], in: context).isEmpty)
            let copy = try service.insert(release: Release(artist: "A", title: "1"), shelf: shelves[0], owner: "me")
            #expect(ScheduledExport.nonEmpty([.collection, .wantlist, .sale], in: context) == [.collection])
            try service.setForSale([copy], true)
            #expect(ScheduledExport.nonEmpty([.collection, .wantlist, .sale], in: context) == [.collection, .sale])
            #expect(ScheduledExport.nonEmpty([.wantlist], in: context).isEmpty)
        }

        @Test func scheduledExportIsDueAfterAClockSetBack() {
            let now = Date(timeIntervalSince1970: 1_790_000_000)
            #expect(ScheduledExport.nextRun(after: nil, interval: .weekly, now: now) == now)
            #expect(ScheduledExport.nextRun(after: now.addingTimeInterval(-86400), interval: .daily, now: now)
                    == ExportInterval.daily.next(after: now.addingTimeInterval(-86400)))
            // Written while the clock stood years ahead: due now, not only in years.
            #expect(ScheduledExport.nextRun(after: now.addingTimeInterval(3 * 365 * 86400), interval: .monthly, now: now) == now)
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
