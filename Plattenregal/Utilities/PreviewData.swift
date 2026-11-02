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
#Preview("Hauptfenster") { RootView().modelContainer(PreviewData.container).frame(width: 1250, height: 850) }
#Preview("KALLAX") { KallaxView(requests: ShelfRequests(), search: ShelfSearch()).modelContainer(PreviewData.container).frame(width: 1000, height: 800) }
#endif

#if DEBUG
/// `--snapshot=name.png`: draws the main window into a PNG in the app's
/// temporary folder (in the container) and quits – a few seconds after the
/// window is shown, or after 30 seconds without one (noted in the protocol).
/// Works while the screen is locked, where `screencapture` gets nothing; the
/// window's own glass and toolbar may look flatter than on screen.
enum DebugSnapshot {
    static func scheduleIfRequested() {
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--snapshot=") }) else { return }
        waitForWindow(name: String(raw.dropFirst("--snapshot=".count)), since: .now)
    }

    private static func waitForWindow(name: String, since start: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let window = NSApp.windows.filter(\.isVisible).max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            if let window {
                // Time for covers and charts to come in.
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { capture(window, name: name, waited: Date.now.timeIntervalSince(start)) }
            } else if Date.now.timeIntervalSince(start) > 30 {
                AppLog.error("App", "Schnappschuss \(name): nach 30 s kein Fenster")
                NSApp.terminate(nil)
            } else {
                waitForWindow(name: name, since: start)
            }
        }
    }

    private static func capture(_ window: NSWindow, name: String, waited: TimeInterval) {
        // --preview-quicksearch=…: the panel of the menu bar instead of the main window.
        // --preview-update=…: the update window.
        let window = NSApp.windows.first { $0.identifier?.rawValue == ShelfQuickSearch.windowID && $0.isVisible }
            ?? NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(UpdateView.windowID) == true && $0.isVisible } ?? window
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if let view = window.contentView?.superview ?? window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            do {
                try rep.representation(using: .png, properties: [:])?.write(to: url)
                AppLog.info("App", "Schnappschuss \(name), Fenster nach \(Int(waited)) s")
            } catch {
                AppLog.error("App", "Schnappschuss \(name) nicht gespeichert: \(error)")
            }
        }
        NSApp.terminate(nil)
    }
}
#endif
