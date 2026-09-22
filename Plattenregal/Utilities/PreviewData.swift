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
@MainActor enum PreviewData {
    static var statisticsContainer: ModelContainer {
        let container = container
        let context = container.mainContext
        do {
            let copies = try context.fetch(FetchDescriptor<RecordCopy>())
            let account = DiscogsAccount(username: "Demo · Beispieldaten")
            context.insert(account)
            for (index, copy) in copies.enumerated() {
                copy.discogsInstanceID = index + 1; copy.discogsOwner = account.username; copy.discogsActive = true
                copy.discogsDateAdded = "2026-0\(index + 4)-15T12:00:00+02:00"
                copy.release?.discogsID = index + 1; copy.release?.fetchedAt = .now
                copy.release?.genres = index == 1 ? ["Electronic", "Rock"] : ["Electronic"]
                copy.release?.styles = index == 0 ? ["Synth-pop"] : ["House", "Downtempo"]
                copy.release?.country = "Germany"; copy.release?.label = "Demo Label"
                context.insert(ReleaseMarketValue(owner: account.username, releaseID: index + 1, value: Decimal((index + 1) * 24), currency: "EUR", condition: "Very Good Plus (VG+)", source: "priceSuggestion"))
            }
            for index in 0..<12 {
                let amount = Decimal(80 + index * 8)
                let value = try DiscogsCollectionValue(minimum: .init(amount: amount / 2, currency: "EUR"), median: .init(amount: amount, currency: "EUR"), maximum: .init(amount: amount * 2, currency: "EUR"))
                let date = Calendar.current.date(byAdding: .month, value: index - 11, to: Date())!
                context.insert(CollectionValueSnapshot(owner: account.username, date: date, value: value, count: 4, unique: 4, signature: "demo"))
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
                let release = Release(artist: item.0, title: item.1); release.year = item.2
                release.styles = [["Electro"], ["Synth-pop"], ["Trip Hop"], ["House"]][index]
                release.label = ["Kling Klang", "Mute", "Virgin", "Virgin"][index]
                try PositionService(context: context).insert(release: release, shelf: shelves[index], position: 1)
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
                let release = Release(artist: item.0, title: item.1)
                release.discogsID = 10_000 + index
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
#Preview("Sammlung") { RootView().modelContainer(PreviewData.container).frame(width: 1250, height: 850) }
#Preview("KALLAX") { KallaxView(highlight: .constant(nil)).modelContainer(PreviewData.container).frame(width: 1000, height: 800) }
#Preview("Schallplatte hinzufügen") { RecordEditor().modelContainer(PreviewData.container) }
#endif
