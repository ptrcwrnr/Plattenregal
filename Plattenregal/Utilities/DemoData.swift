import AppKit
import CoreText
import Foundation
import SwiftData

/// The sample collection of the demo (see `DemoMode`): about fifty well-known
/// albums across genres, two cabinets, a few records still without a place,
/// a locked compartment, a wantlist and a year and a half of value history –
/// enough for every page to show what it does. Every state of a record has
/// an example: on the search list ("Gesucht"), on the sale list, "Ohne
/// Regalplatz", still in a compartment but no longer in the collection, and
/// changes in the shelf's "Verlauf" (one already undone). Kept in memory only.
enum DemoData {
    static let owner = "Demo-Sammlung"

    private struct Album {
        let artist: String, title: String, year: Int, label: String, country: String
        let genres: [String], styles: [String]
    }

    private static let albums: [Album] = [
        .init(artist: "A Tribe Called Quest", title: "The Low End Theory", year: 1991, label: "Jive", country: "US", genres: ["Hip Hop"], styles: ["Conscious", "Jazzy Hip-Hop"]),
        .init(artist: "ABBA", title: "Arrival", year: 1976, label: "Polar", country: "Sweden", genres: ["Pop"], styles: ["Europop"]),
        .init(artist: "Air", title: "Moon Safari", year: 1998, label: "Virgin", country: "France", genres: ["Electronic"], styles: ["Downtempo"]),
        .init(artist: "Aphex Twin", title: "Selected Ambient Works 85-92", year: 1992, label: "Apollo", country: "UK", genres: ["Electronic"], styles: ["Ambient", "IDM"]),
        .init(artist: "Beastie Boys", title: "Paul's Boutique", year: 1989, label: "Capitol", country: "US", genres: ["Hip Hop"], styles: ["Boom Bap"]),
        .init(artist: "Björk", title: "Homogenic", year: 1997, label: "One Little Indian", country: "Iceland", genres: ["Electronic", "Pop"], styles: ["Trip Hop", "Art Pop"]),
        .init(artist: "Boards of Canada", title: "Music Has the Right to Children", year: 1998, label: "Warp", country: "UK", genres: ["Electronic"], styles: ["IDM", "Downtempo"]),
        .init(artist: "Bonobo", title: "Migration", year: 2017, label: "Ninja Tune", country: "UK", genres: ["Electronic"], styles: ["Downtempo"]),
        .init(artist: "Can", title: "Tago Mago", year: 1971, label: "United Artists", country: "Germany", genres: ["Rock"], styles: ["Krautrock"]),
        .init(artist: "Daft Punk", title: "Discovery", year: 2001, label: "Virgin", country: "France", genres: ["Electronic"], styles: ["House", "Disco"]),
        .init(artist: "Daft Punk", title: "Homework", year: 1997, label: "Virgin", country: "France", genres: ["Electronic"], styles: ["House"]),
        .init(artist: "Dave Brubeck Quartet", title: "Time Out", year: 1959, label: "Columbia", country: "US", genres: ["Jazz"], styles: ["Cool Jazz"]),
        .init(artist: "David Bowie", title: "Low", year: 1977, label: "RCA", country: "UK", genres: ["Rock", "Electronic"], styles: ["Art Rock"]),
        .init(artist: "Depeche Mode", title: "Music for the Masses", year: 1987, label: "Mute", country: "UK", genres: ["Electronic"], styles: ["Synth-pop"]),
        .init(artist: "Depeche Mode", title: "Violator", year: 1990, label: "Mute", country: "UK", genres: ["Electronic"], styles: ["Synth-pop"]),
        .init(artist: "Dr. Dre", title: "2001", year: 1999, label: "Aftermath", country: "US", genres: ["Hip Hop"], styles: ["G-Funk"]),
        .init(artist: "Fleetwood Mac", title: "Rumours", year: 1977, label: "Warner Bros.", country: "US", genres: ["Rock"], styles: ["Soft Rock"]),
        .init(artist: "Herbie Hancock", title: "Head Hunters", year: 1973, label: "Columbia", country: "US", genres: ["Jazz", "Funk / Soul"], styles: ["Jazz-Funk"]),
        .init(artist: "Jean-Michel Jarre", title: "Oxygène", year: 1976, label: "Disques Dreyfus", country: "France", genres: ["Electronic"], styles: ["Ambient"]),
        .init(artist: "John Coltrane", title: "A Love Supreme", year: 1965, label: "Impulse!", country: "US", genres: ["Jazz"], styles: ["Hard Bop", "Modal"]),
        .init(artist: "Joy Division", title: "Unknown Pleasures", year: 1979, label: "Factory", country: "UK", genres: ["Rock"], styles: ["Post-Punk"]),
        .init(artist: "Kate Bush", title: "Hounds of Love", year: 1985, label: "EMI", country: "UK", genres: ["Pop", "Rock"], styles: ["Art Pop"]),
        .init(artist: "Kendrick Lamar", title: "To Pimp a Butterfly", year: 2015, label: "Top Dawg", country: "US", genres: ["Hip Hop", "Jazz"], styles: ["Conscious"]),
        .init(artist: "Kraftwerk", title: "Computerwelt", year: 1981, label: "Kling Klang", country: "Germany", genres: ["Electronic"], styles: ["Electro", "Synth-pop"]),
        .init(artist: "Kraftwerk", title: "Trans Europa Express", year: 1977, label: "Kling Klang", country: "Germany", genres: ["Electronic"], styles: ["Electro", "Krautrock"]),
        .init(artist: "Marvin Gaye", title: "What's Going On", year: 1971, label: "Tamla", country: "US", genres: ["Funk / Soul"], styles: ["Soul"]),
        .init(artist: "Massive Attack", title: "Mezzanine", year: 1998, label: "Virgin", country: "UK", genres: ["Electronic"], styles: ["Trip Hop"]),
        .init(artist: "Michael Jackson", title: "Thriller", year: 1982, label: "Epic", country: "US", genres: ["Pop", "Funk / Soul"], styles: ["Disco"]),
        .init(artist: "Miles Davis", title: "Kind of Blue", year: 1959, label: "Columbia", country: "US", genres: ["Jazz"], styles: ["Modal"]),
        .init(artist: "Moby", title: "Play", year: 1999, label: "Mute", country: "US", genres: ["Electronic"], styles: ["Downtempo"]),
        .init(artist: "Moderat", title: "II", year: 2013, label: "Monkeytown", country: "Germany", genres: ["Electronic"], styles: ["Techno", "Downtempo"]),
        .init(artist: "Nena", title: "Nena", year: 1983, label: "CBS", country: "Germany", genres: ["Pop"], styles: ["Neue Deutsche Welle"]),
        .init(artist: "Neu!", title: "Neu!", year: 1972, label: "Brain", country: "Germany", genres: ["Rock"], styles: ["Krautrock"]),
        .init(artist: "New Order", title: "Power, Corruption & Lies", year: 1983, label: "Factory", country: "UK", genres: ["Electronic", "Rock"], styles: ["Synth-pop", "New Wave"]),
        .init(artist: "Nils Frahm", title: "Spaces", year: 2013, label: "Erased Tapes", country: "Germany", genres: ["Classical", "Electronic"], styles: ["Modern Classical"]),
        .init(artist: "Ólafur Arnalds", title: "Re:member", year: 2018, label: "Mercury KX", country: "Iceland", genres: ["Classical"], styles: ["Modern Classical"]),
        .init(artist: "Orbital", title: "Orbital 2", year: 1993, label: "Internal", country: "UK", genres: ["Electronic"], styles: ["Techno"]),
        .init(artist: "Paul Kalkbrenner", title: "Berlin Calling", year: 2008, label: "BPitch Control", country: "Germany", genres: ["Electronic"], styles: ["Techno"]),
        .init(artist: "Pet Shop Boys", title: "Actually", year: 1987, label: "Parlophone", country: "UK", genres: ["Electronic", "Pop"], styles: ["Synth-pop"]),
        .init(artist: "Pink Floyd", title: "The Dark Side of the Moon", year: 1973, label: "Harvest", country: "UK", genres: ["Rock"], styles: ["Prog Rock"]),
        .init(artist: "Pink Floyd", title: "Wish You Were Here", year: 1975, label: "Harvest", country: "UK", genres: ["Rock"], styles: ["Prog Rock"]),
        .init(artist: "Portishead", title: "Dummy", year: 1994, label: "Go! Beat", country: "UK", genres: ["Electronic"], styles: ["Trip Hop"]),
        .init(artist: "Prince", title: "Purple Rain", year: 1984, label: "Warner Bros.", country: "US", genres: ["Funk / Soul", "Rock"], styles: ["Pop Rock"]),
        .init(artist: "Radiohead", title: "Kid A", year: 2000, label: "Parlophone", country: "UK", genres: ["Rock", "Electronic"], styles: ["Alternative Rock", "IDM"]),
        .init(artist: "Radiohead", title: "OK Computer", year: 1997, label: "Parlophone", country: "UK", genres: ["Rock"], styles: ["Alternative Rock"]),
        .init(artist: "Röyksopp", title: "Melody A.M.", year: 2001, label: "Wall of Sound", country: "Norway", genres: ["Electronic"], styles: ["Downtempo"]),
        .init(artist: "Stevie Wonder", title: "Songs in the Key of Life", year: 1976, label: "Tamla", country: "US", genres: ["Funk / Soul"], styles: ["Soul"]),
        .init(artist: "Talking Heads", title: "Remain in Light", year: 1980, label: "Sire", country: "US", genres: ["Rock"], styles: ["New Wave"]),
        .init(artist: "The Beatles", title: "Abbey Road", year: 1969, label: "Apple", country: "UK", genres: ["Rock"], styles: ["Pop Rock"]),
        .init(artist: "The Chemical Brothers", title: "Dig Your Own Hole", year: 1997, label: "Virgin", country: "UK", genres: ["Electronic"], styles: ["Big Beat"]),
        .init(artist: "The Cure", title: "Disintegration", year: 1989, label: "Fiction", country: "UK", genres: ["Rock"], styles: ["New Wave"]),
        .init(artist: "Tycho", title: "Dive", year: 2011, label: "Ghostly International", country: "US", genres: ["Electronic"], styles: ["Downtempo"]),
        .init(artist: "Underworld", title: "Second Toughest in the Infants", year: 1996, label: "Junior Boy's Own", country: "UK", genres: ["Electronic"], styles: ["Techno"]),
        .init(artist: "Wu-Tang Clan", title: "Enter the Wu-Tang (36 Chambers)", year: 1993, label: "Loud", country: "US", genres: ["Hip Hop"], styles: ["Boom Bap"]),
        .init(artist: "Yello", title: "Stella", year: 1985, label: "Elektra", country: "Switzerland", genres: ["Electronic"], styles: ["Synth-pop"]),
    ]

    /// Just added and not yet in the shelf – the "Einsortieren" workflow.
    private static let unplaced: Set<String> = ["Bonobo", "Kendrick Lamar", "Ólafur Arnalds", "Tycho", "Nils Frahm"]
    /// Standing in the hallway cabinet rather than the living room.
    private static let hallway: Set<String> = ["Dave Brubeck Quartet", "Herbie Hancock", "John Coltrane", "Miles Davis"]
    /// Set aside on purpose ("Ohne Regalplatz"), e.g. lent out.
    private static let setAside: Set<String> = ["ABBA"]

    private static let wants: [(artist: String, title: String, year: Int, label: String)] = [
        ("Aphex Twin", "Richard D. James Album", 1996, "Warp"),
        ("Brian Eno", "Ambient 1: Music for Airports", 1978, "Polydor"),
        ("Burial", "Untrue", 2007, "Hyperdub"),
        ("Can", "Ege Bamyasi", 1972, "United Artists"),
        ("J Dilla", "Donuts", 2006, "Stones Throw"),
        ("Kate Bush", "The Kick Inside", 1978, "EMI"),
        ("Kraftwerk", "Die Mensch-Maschine", 1978, "Kling Klang"),
        ("Massive Attack", "Blue Lines", 1991, "Wild Bunch"),
        ("Sade", "Diamond Life", 1984, "Epic"),
        ("Talk Talk", "Spirit of Eden", 1988, "Parlophone"),
    ]

    /// Sold on Discogs, still on the shelf ("nicht in der Collection").
    private static let leftCollection = "Fleetwood Mac"

    /// A few changes in the "Verlauf", matching where the records stand now,
    /// so each can be undone: sorted in an hour ago, moved yesterday, taken
    /// out two days ago – and one sorted in and undone again.
    private static func insertHistory(copies: [RecordCopy], living: [Shelf], hall: [Shelf], now: Date, in context: ModelContext) {
        func copy(_ artist: String) -> RecordCopy? { copies.first { $0.release?.artist == artist } }
        func hoursAgo(_ hours: Int) -> Date { now.addingTimeInterval(-Double(hours) * 3_600) }
        func entry(_ copy: RecordCopy, from: Shelf?, _ fromPosition: Int, to: Shelf?, _ toPosition: Int, at date: Date) -> ShelfHistoryEntry {
            let entry = ShelfHistoryEntry(copyID: copy.id, artist: copy.release?.displayArtist ?? "", title: copy.release?.displayTitle ?? "",
                                          fromShelfID: from?.id, fromPosition: from == nil ? 0 : fromPosition, fromName: from.map(PositionService.name) ?? "",
                                          toShelfID: to?.id, toPosition: to == nil ? 0 : toPosition, toName: to.map(PositionService.name) ?? "",
                                          date: date)
            context.insert(entry)
            return entry
        }
        if let miles = copy("Miles Davis"), let shelf = miles.shelf {
            _ = entry(miles, from: nil, 0, to: shelf, miles.positionInShelf, at: hoursAgo(1))
        }
        if let nils = copy("Nils Frahm"), living.count > 2 {
            entry(nils, from: nil, 0, to: living[2], 1, at: hoursAgo(3)).undoneAt = hoursAgo(2)
        }
        if let daft = copies.first(where: { $0.release?.title == "Homework" }), let shelf = daft.shelf,
           let other = living.first(where: { $0.id != shelf.id }) {
            _ = entry(daft, from: other, 2, to: shelf, daft.positionInShelf, at: hoursAgo(26))
        }
        if let tycho = copy("Tycho"), let last = living.last {
            _ = entry(tycho, from: last, 3, to: nil, 0, at: hoursAgo(50))
        }
    }

    static func makeContainer() throws -> ModelContainer {
        let container = try LibraryStorage.makeContainer(inMemory: true)
        let context = container.mainContext
        let now = Date.now
        let calendar = Calendar.current

        let account = DiscogsAccount(username: owner)
        account.lastCollectionSync = now
        account.lastWantlistSync = now
        context.insert(account)

        // The living room: the cabinet every store starts with.
        let cabinets = try context.fetch(FetchDescriptor<Cabinet>(sortBy: [SortDescriptor(\Cabinet.sortOrder)]))
        guard let livingRoom = cabinets.first else { throw LibraryError.missingRelease }
        livingRoom.name = String(localized: "Wohnzimmer")
        try context.save()
        let hall = try CabinetService(context: context).add(name: String(localized: "Flur"), columns: 2, rows: 2)

        var copies: [(copy: RecordCopy, album: Album)] = []
        for (index, album) in albums.enumerated() {
            let release = Release(discogsID: 1_000 + index, artist: album.artist, title: album.title)
            release.year = album.year; release.label = album.label; release.country = album.country
            release.genres = album.genres; release.styles = album.styles
            release.format = "Vinyl, LP, Album"
            release.catalogNumber = "DEMO \(100 + index)"
            release.fetchedAt = now; release.detailsFetchedAt = now
            release.coverURL = DemoCover.url(artist: album.artist, title: album.title, seed: index)
            context.insert(release)
            let copy = RecordCopy(release: release, instanceID: 50_000 + index, owner: owner)
            // Added over the last three years, the unplaced ones most recently.
            let daysAgo = unplaced.contains(album.artist) ? index % 20 + 1 : (index * 37) % 1_050 + 25
            let added = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            copy.discogsDateAdded = added.formatted(.iso8601)
            copy.discogsFolderID = album.genres.contains("Electronic") ? 2 : album.year < 1980 ? 3 : 1
            context.insert(copy)
            copies.append((copy, album))
        }
        // A second copy of a classic, to show two copies of one release.
        if let kindOfBlue = copies.first(where: { $0.album.title == "Kind of Blue" }), let release = kindOfBlue.copy.release {
            let second = RecordCopy(release: release, instanceID: 59_999, owner: owner)
            second.discogsDateAdded = calendar.date(byAdding: .day, value: -400, to: now)?.formatted(.iso8601)
            second.discogsFolderID = 3
            context.insert(second)
            copies.append((second, kindOfBlue.album))
        }
        // Folder 1 has this name on Discogs in every language. Counts as Discogs reports them.
        for (id, name) in [(1, "Uncategorized"), (2, String(localized: "Elektronisch")), (3, String(localized: "Klassiker"))] {
            let count = copies.filter { $0.copy.discogsFolderID == id }.count
            context.insert(DiscogsFolder(owner: owner, id: id, name: name, count: count))
        }

        // Alphabetically into the living room, a few per compartment; jazz in the hallway.
        let living = livingRoom.orderedShelves
        let placed = copies.filter { !unplaced.contains($0.album.artist) && !hallway.contains($0.album.artist) && !setAside.contains($0.album.artist) }
            .sorted { ($0.album.artist, $0.album.year) < ($1.album.artist, $1.album.year) }
        let perShelf = Int((Double(placed.count) / Double(living.count)).rounded(.up))
        for (index, item) in placed.enumerated() {
            item.copy.shelf = living[min(index / perShelf, living.count - 1)]
            item.copy.positionInShelf = index % perShelf + 1
        }
        let hallShelves = hall.orderedShelves
        for (index, item) in copies.filter({ hallway.contains($0.album.artist) }).enumerated() {
            item.copy.shelf = hallShelves[0]
            item.copy.positionInShelf = index + 1
        }
        // One compartment holds the record player's accessories.
        if let deko = hallShelves.last { deko.isReserved = true; deko.name = String(localized: "Deko") }
        for item in copies where setAside.contains(item.album.artist) {
            context.insert(OptimizationExclusion(copyID: item.copy.id))
        }
        // One record in the living room wasn't found while sorting.
        if placed.count > 2 { context.insert(MissingCopyMark(copyID: placed[2].copy.id)) }
        // Two are meant to be sold some day.
        for item in placed.dropFirst(5).prefix(2) { context.insert(SaleCopyMark(copyID: item.copy.id)) }
        // One was sold on Discogs but still stands in its compartment.
        copies.first { $0.album.artist == leftCollection }?.copy.discogsActive = false
        insertHistory(copies: copies.map(\.copy), living: living, hall: hallShelves, now: now, in: context)

        for (index, want) in wants.enumerated() {
            let release = Release(discogsID: 5_000 + index, artist: want.artist, title: want.title)
            release.year = want.year; release.label = want.label
            release.format = "Vinyl, LP, Album"
            release.fetchedAt = now
            release.coverURL = DemoCover.url(artist: want.artist, title: want.title, seed: 100 + index * 3)
            let entry = WantlistEntry(owner: owner, release: release, releaseID: 5_000 + index)
            entry.dateAdded = calendar.date(byAdding: .day, value: -(index * 11 + 3), to: now)?.formatted(.iso8601)
            context.insert(entry)
        }

        // Eighteen months of collection value, growing with the collection.
        let count = copies.count
        for month in 0..<18 {
            let median = Decimal(1_150 + month * 38 + (month % 3) * 25)
            let value = try DiscogsCollectionValue(minimum: .init(amount: median * Decimal(0.6), currency: "EUR"),
                                                   median: .init(amount: median, currency: "EUR"),
                                                   maximum: .init(amount: median * Decimal(1.8), currency: "EUR"))
            let date = calendar.date(byAdding: .month, value: month - 17, to: now) ?? now
            let records = max(1, count - (17 - month))
            context.insert(CollectionValueSnapshot(owner: owner, date: date, value: value, count: records, signature: "demo-\(month)"))
        }
        try context.save()
        return container
    }
}
