import SwiftUI
import SwiftData

private struct MetadataClockKey: EnvironmentKey {
    static let defaultValue = Date.now
}
extension EnvironmentValues {
    var metadataClock: Date {
        get { self[MetadataClockKey.self] }
        set { self[MetadataClockKey.self] = newValue }
    }
}

#if DEBUG
enum PreviewData {
    static var statisticsContainer: ModelContainer {
        let container = container
        let context = container.mainContext
        do {
            // A few dozen extra records so charts and the donut have something to show.
            let shelves = try context.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
            let artists = ["Kraftwerk", "Depeche Mode", "Moderat", "Röyksopp", "Air", "Boards of Canada", "Aphex Twin", "Portishead"]
            for index in 0..<36 {
                let release = Release(discogsID: index + 1, artist: artists[index % artists.count], title: "Demo-Album \(index + 1)")
                release.year = 1972 + (index * 7) % 53
                try PositionService(context: context).insert(release: release, shelf: shelves[index % shelves.count], position: 1)
            }
            // A second cabinet, so the shelf page shows its cabinet switcher.
            let flur = try CabinetService(context: context).add(name: "Flur", columns: 2, rows: 4)
            for (index, artist) in ["Moby", "Nena", "Orbital", "Pet Shop Boys", "Yello", "Zola Jesus"].enumerated() {
                let release = Release(discogsID: 900 + index, artist: artist, title: "Flur-Album")
                try PositionService(context: context).insert(release: release, shelf: flur.orderedShelves[index / 2], position: index % 2 + 1)
            }
            // Exercise the grouped cover tile and its per-copy popover in previews.
            let firstCopy = try context.fetch(FetchDescriptor<RecordCopy>()).first!
            try PositionService(context: context).insert(release: firstCopy.release!, shelf: shelves[1], position: 1)
            let copies = try context.fetch(FetchDescriptor<RecordCopy>())
            let account = DiscogsAccount(username: "Demo · Beispieldaten")
            context.insert(account)
            for (index, copy) in copies.enumerated() {
                copy.discogsInstanceID = index + 1; copy.discogsOwner = account.username; copy.discogsActive = true
                let month = String(format: "%02d", index % 12 + 1)
                copy.discogsDateAdded = "\(2024 + index % 3)-\(month)-15T12:00:00+02:00"
                copy.release?.fetchedAt = .now
                copy.release?.genres = [["Electronic"], ["Electronic", "Rock"], ["Electronic", "Pop"], ["Hip Hop"], ["Jazz"]][index % 5]
                copy.release?.styles = [["Synth-pop"], ["House", "Downtempo"], ["Techno"], ["Ambient"], ["Trip Hop"], ["IDM"], ["Electro"], ["Krautrock"], ["Deep House"]][index % 9]
                copy.release?.country = ["Germany", "UK", "France", "US"][index % 4]; copy.release?.label = ["Mute", "Warp", "Kling Klang", "Virgin", "Monkeytown"][index % 5]
            }
            for index in 0..<12 {
                let amount = Decimal(80 + index * 8)
                let value = try DiscogsCollectionValue(minimum: .init(amount: amount / 2, currency: "EUR"), median: .init(amount: amount, currency: "EUR"), maximum: .init(amount: amount * 2, currency: "EUR"))
                let date = Calendar.current.date(byAdding: .month, value: index - 11, to: Date())!
                context.insert(CollectionValueSnapshot(owner: account.username, date: date, value: value, count: 30 + index, unique: 30 + index, signature: "demo"))
            }
            try context.save(); return container
        } catch { fatalError("Statistics preview failed: \(error)") }
    }
    static var container: ModelContainer {
        do {
            let container = try LibraryStorage.makeContainer(inMemory: true)
            let context = container.mainContext
            let shelves = try context.fetch(FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\Shelf.number)]))
            let examples = [("Kraftwerk", "Computerwelt", 1981), ("Depeche Mode", "Violator", 1990),
                            ("Massive Attack", "Mezzanine", 1998), ("Daft Punk", "Discovery", 2001)]
            for (index, item) in examples.enumerated() {
                let release = Release(discogsID: 100 + index, artist: item.0, title: item.1); release.year = item.2
                release.styles = [["Electro"], ["Synth-pop"], ["Trip Hop"], ["House"]][index]
                release.label = ["Kling Klang", "Mute", "Virgin", "Virgin"][index]
                try PositionService(context: context).insert(release: release, shelf: shelves[index], position: 1)
            }
            // Unassigned copies make the shelf assignment sheet inspectable in previews.
            let looseExamples = [
                ("Charlotte de Witte", "Return To Nowhere EP"),
                ("Dee Mark", "Moonwalker"),
                ("DJ Hyperactive", "Len Faki DJ-Edits Volume I"),
                ("DJ Natron & Reverb Present Flutlicht", "Mutterkorn"),
                ("DJ Shog", "This Is My Sound"),
                ("DuMonde Vs. Lange", "Memory"),
                ("Fabian Schumann & Black Vel", "Alcutia E.P."),
                ("Fahrenheit 66", "Contact")
            ]
            for (index, item) in looseExamples.enumerated() {
                let copy = RecordCopy(release: Release(discogsID: 20_000 + index, artist: item.0, title: item.1),
                                      instanceID: 20_000 + index, owner: "Demo")
                context.insert(copy)
            }
            let wantExamples = [
                ("040 Featuring Erica Baxter", "Dreams", "Perfecto", "2026-09-21T09:20:00+02:00"),
                ("2 Players", "Signet Remixes", "Afterglow", "2026-09-20T18:45:00+02:00"),
                ("4 Strings", "Take Me Away (Into The Night)", "Liquid", "2026-09-18T12:10:00+02:00"),
                ("4 Strings", "Catch A Fall", "Nebula", "2026-09-15T08:30:00+02:00"),
                ("@dam", "Pure Energy", "Mid-Town", "2026-09-12T20:05:00+02:00"),
                ("A*S*Y*S", "Acid Nightmare / DJ's Nightmare", "Tracid Traxxx", "2026-09-10T14:00:00+02:00")
            ]
            for (index, item) in wantExamples.enumerated() {
                let release = Release(discogsID: 10_000 + index, artist: item.0, title: item.1)
                release.label = item.2
                let entry = WantlistEntry(owner: "Demo", release: release, releaseID: 10_000 + index)
                entry.dateAdded = item.3
                entry.rating = index.isMultiple(of: 3) ? 4 : 0
                context.insert(entry)
            }
            try context.save()
            return container
        } catch { fatalError("In-memory preview failed: \(error)") }
    }
}
#Preview("Übersicht") { RootView().modelContainer(PreviewData.container).frame(width: 1250, height: 850) }
#Preview("KALLAX") { KallaxView(highlight: .constant(nil), placing: .constant(nil)).modelContainer(PreviewData.container).frame(width: 1000, height: 800) }
#Preview("Exemplar bearbeiten") {
    let container = PreviewData.container
    let copy = try! container.mainContext.fetch(FetchDescriptor<RecordCopy>()).first!
    return RecordEditor(copy: copy).modelContainer(container)
}
#endif
