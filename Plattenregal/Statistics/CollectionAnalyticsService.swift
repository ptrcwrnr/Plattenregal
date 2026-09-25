import Foundation

nonisolated struct AnalyticsItem: Sendable {
    struct Named: Hashable, Sendable {
        let id: String; let name: String
        /// Discogs' placeholder artist for compilations (ID 194) — mixed artists, not a real one.
        var isVariousArtists: Bool { id == "artist:194" || name.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Various") == .orderedSame }
    }
    let id: UUID
    let releaseKey: String
    let year: Int?
    let genres: [String]
    let styles: [String]
    let artists: [Named]
    let labels: [Named]
    let formats: [String]
    let country: String
    let added: Date?
    /// Discogs data has the odd typo ("197", "20015"). Such a year would make
    /// "Ältestes Release" and the timeline (one bar per year in between)
    /// meaningless, so it counts as unknown — like in the record editor.
    static func plausibleYear(_ year: Int) -> Int? {
        (1877...Calendar.current.component(.year, from: .now) + 1).contains(year) ? year : nil
    }
    /// What a copy contributes, read on the main actor without any decoding —
    /// cheap enough for large collections. The JSON in `basicInformation` is
    /// decoded later, off the main actor (`AnalyticsItem.init(_: Raw)`).
    struct Raw: Sendable {
        let id: UUID
        let releaseKey: String
        let year: Int?
        let genres: [String], styles: [String]
        let country: String
        let basicInformation: Data?
        let legacyArtist: String?, legacyArtistName: String?
        let legacyLabel: String?, legacyLabelName: String?
        let added: Date?

        init(_ copy: RecordCopy) {
            let release = copy.release
            id = copy.id
            releaseKey = release.map { "discogs:\($0.discogsID)" } ?? copy.id.uuidString
            year = release?.year; genres = release?.genres ?? []; styles = release?.styles ?? []
            country = release?.country ?? ""
            basicInformation = release?.basicInformation
            legacyArtist = release?.artist; legacyArtistName = release?.displayArtist
            legacyLabel = release?.label; legacyLabelName = release?.displayLabel
            // Do not substitute the import timestamp for an unknown Discogs acquisition date.
            added = DiscogsDate.parse(copy.discogsDateAdded)
        }
    }

    init(_ copy: RecordCopy) { self.init(Raw(copy)) }

    init(_ raw: Raw) {
        id = raw.id
        releaseKey = raw.releaseKey
        year = raw.year.flatMap(Self.plausibleYear)
        genres = raw.genres; styles = raw.styles; country = raw.country
        let basic = raw.basicInformation.flatMap { try? JSONDecoder().decode(DiscogsBasicInformation.self, from: $0) }
        let basicArtists: [DiscogsBasicInformation.Artist] = basic?.artists ?? []
        // Grouped by Discogs ID under the artist's canonical name, not the name
        // variation a single release credits ("Biesmans" for Joris Biesmans):
        // otherwise the group's name would depend on which copy came first.
        artists = basicArtists.isEmpty
            ? (raw.legacyArtist.map { [Named(id: "legacy:\($0)", name: raw.legacyArtistName ?? $0)] } ?? [])
            : basicArtists.map { artist in
                artist.id.map { Named(id: "artist:\($0)", name: DiscogsName.clean(artist.name)) }
                    ?? Named(id: "name:\(artist.displayName)", name: DiscogsName.clean(artist.displayName))
            }
        labels = basic?.labels?.map { Named(id: $0.id.map { "label:\($0)" } ?? "name:\($0.name)", name: DiscogsName.clean($0.name)) }
            ?? (raw.legacyLabel.map { [Named(id: "legacy:\($0)", name: raw.legacyLabelName ?? $0)] } ?? [])
        formats = (basic?.formats ?? []).flatMap { format in
            ["Medium: \(format.name)"] + (format.descriptions ?? []).map { "Merkmal: \($0)" }
        }
        added = raw.added
    }
}
nonisolated struct StatisticGroup: Identifiable, Sendable {
    let id: String
    let name: String
    var copyIDs: Set<UUID>
    var count: Int { copyIDs.count }
    func percentage(of total: Int) -> String { total > 0 ? (Double(count) / Double(total)).formatted(.percent.precision(.fractionLength(0))) : "—" }
}
nonisolated struct AcquisitionBin: Identifiable, Sendable { let date: Date; let count: Int; var id: Date { date } }
nonisolated struct CollectionStatistics: Sendable {
    var totalItems = 0, uniqueReleases = 0
    var genres: [StatisticGroup] = [], styles: [StatisticGroup] = [], artists: [StatisticGroup] = []
    var labels: [StatisticGroup] = [], years: [StatisticGroup] = [], decades: [StatisticGroup] = []
    var formats: [StatisticGroup] = [], countries: [StatisticGroup] = []
    var recentlyAdded: [UUID] = []
    var months: [AcquisitionBin] = [], acquisitionYears: [AcquisitionBin] = []
    var oldest: Int?, newest: Int?
    var missingYear = 0, missingStyle = 0
    /// Records without any genre, country or format detail ("Merkmal"), so
    /// the donut can say how many of its percentages rest on nothing.
    var missingGenre = 0, missingCountry = 0, missingFormatDetail = 0
    /// Added this calendar year so far, and in the same stretch of last year
    /// (1 January up to the same day) — a fair comparison early in the year.
    var addedThisYear = 0, addedLastYearToDate = 0
}
nonisolated enum CollectionAnalyticsService {
    // Pure value inputs: no API client, ModelContext or network work in the calculation.
    static func calculate(_ items: [AnalyticsItem], calendar: Calendar = .current, now: Date = .now) -> CollectionStatistics {
        func groups(_ values: (AnalyticsItem) -> [AnalyticsItem.Named]) -> [StatisticGroup] {
            var result: [String: StatisticGroup] = [:]
            for item in items {
                for value in values(item) where !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if result[value.id] == nil { result[value.id] = StatisticGroup(id: value.id, name: value.name, copyIDs: []) }
                    result[value.id]?.copyIDs.insert(item.id)
                }
            }
            return result.values.sorted { $0.count == $1.count ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.count > $1.count }
        }
        func named(_ values: [String]) -> [AnalyticsItem.Named] { values.map { .init(id: $0, name: $0) } }
        var s = CollectionStatistics(); s.totalItems = items.count; s.uniqueReleases = Set(items.map(\.releaseKey)).count
        s.genres = groups { named($0.genres) }; s.styles = groups { named($0.styles) }
        s.artists = mergingLegacy(groups { $0.artists.filter { !$0.isVariousArtists } })
        s.labels = mergingLegacy(groups { $0.labels })
        s.formats = groups { named($0.formats) }; s.countries = groups { named([$0.country]) }
        s.years = groups { named($0.year.map { [String($0)] } ?? []) }.sorted { $0.id < $1.id }
        s.decades = groups { named($0.year.map { ["\($0 / 10 * 10)er"] } ?? []) }.sorted { $0.id < $1.id }
        s.oldest = items.compactMap(\.year).min(); s.newest = items.compactMap(\.year).max()
        s.missingYear = items.filter { $0.year == nil }.count
        s.missingStyle = items.filter { $0.styles.isEmpty }.count
        s.missingGenre = items.filter { $0.genres.isEmpty }.count
        s.missingCountry = items.filter { $0.country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        s.missingFormatDetail = items.filter { !$0.formats.contains { $0.hasPrefix("Merkmal: ") } }.count
        let dated = items.filter { $0.added != nil }.sorted { $0.added == $1.added ? $0.id.uuidString < $1.id.uuidString : $0.added! > $1.added! }
        s.recentlyAdded = dated.prefix(10).map(\.id)
        func bins(_ component: Calendar.Component) -> [AcquisitionBin] {
            let dates = dated.compactMap { $0.added.flatMap { calendar.dateInterval(of: component, for: $0)?.start } }
            return Dictionary(grouping: dates, by: { $0 }).map { AcquisitionBin(date: $0.key, count: $0.value.count) }.sorted { $0.date < $1.date }
        }
        s.months = bins(.month); s.acquisitionYears = bins(.year)
        if let thisYear = calendar.dateInterval(of: .year, for: now),
           let lastYearStart = calendar.date(byAdding: .year, value: -1, to: thisYear.start),
           let lastYearNow = calendar.date(byAdding: .year, value: -1, to: now) {
            for date in dated.compactMap(\.added) {
                if date >= thisYear.start && date <= now { s.addedThisYear += 1 }
                else if date >= lastYearStart && date <= lastYearNow { s.addedLastYearToDate += 1 }
            }
        }
        return s
    }

    /// Records without stored Discogs data count under their name only
    /// ("legacy:Moby"). Where exactly one Discogs-ID group has that name,
    /// they belong to it — otherwise Moby would be listed twice.
    static func mergingLegacy(_ groups: [StatisticGroup]) -> [StatisticGroup] {
        func key(_ name: String) -> String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        var result = groups.filter { !$0.id.hasPrefix("legacy:") }
        let byName = Dictionary(grouping: result.indices, by: { key(result[$0].name) })
        for legacy in groups where legacy.id.hasPrefix("legacy:") {
            if let matches = byName[key(legacy.name)], matches.count == 1 {
                result[matches[0]].copyIDs.formUnion(legacy.copyIDs)
            } else {
                result.append(legacy)
            }
        }
        return result.sorted { $0.count == $1.count ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.count > $1.count }
    }
}
