import SwiftUI
import SwiftData

#if DEBUG
enum PreviewData {
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
