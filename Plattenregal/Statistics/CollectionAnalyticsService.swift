import Foundation

struct AnalyticsItem: Sendable {
    struct Named: Hashable, Sendable { let id: String; let name: String }
    let id: UUID
    let releaseKey: String
    let releaseID: Int?
    let year: Int?
    let genres: [String]
    let styles: [String]
    let artists: [Named]
    let labels: [Named]
    let formats: [String]
    let country: String
    let added: Date?
    init(_ copy: RecordCopy) {
        let release = copy.release
        id = copy.id; releaseID = release?.discogsID
        releaseKey = release?.discogsID.map { "discogs:\($0)" } ?? release?.id.uuidString ?? copy.id.uuidString
        year = release?.year.flatMap { $0 > 0 ? $0 : nil }
        genres = release?.genres ?? []; styles = release?.styles ?? []; country = release?.country ?? ""
        let basic = release?.basicInformation.flatMap { try? JSONDecoder().decode(DiscogsBasicInformation.self, from: $0) }
        let basicArtists: [DiscogsBasicInformation.Artist] = basic?.artists ?? []
        artists = basicArtists.isEmpty
            ? (release.map { [Named(id: "legacy:\($0.artist)", name: $0.artist)] } ?? [])
            : basicArtists.map { Named(id: $0.id.map { "artist:\($0)" } ?? "name:\($0.displayName)", name: $0.displayName) }
        labels = basic?.labels?.map { Named(id: $0.id.map { "label:\($0)" } ?? "name:\($0.name)", name: $0.name) }
            ?? (release.map { [Named(id: "legacy:\($0.label)", name: $0.label)] } ?? [])
        formats = (basic?.formats ?? []).flatMap { format in
            ["Medium: \(format.name)"] + (format.descriptions ?? []).map { "Merkmal: \($0)" }
        }
        // Do not substitute the import timestamp for an unknown Discogs acquisition date.
        added = copy.discogsInstanceID == nil ? copy.dateAdded : Self.date(copy.discogsDateAdded)
    }
    static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        if let date = formatter.date(from: raw) { return date }
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "yyyy-MM-dd"
        return day.date(from: raw)
    }
}
struct StatisticGroup: Identifiable, Sendable {
    let id: String
    let name: String
    var copyIDs: Set<UUID>
    var count: Int { copyIDs.count }
    func percentage(of total: Int) -> String { total > 0 ? (Double(count) / Double(total)).formatted(.percent.precision(.fractionLength(0))) : "—" }
}
struct AcquisitionBin: Identifiable, Sendable { let date: Date; let count: Int; var id: Date { date } }
struct CollectionStatistics: Sendable {
    var totalItems = 0, uniqueReleases = 0
    var genres: [StatisticGroup] = [], styles: [StatisticGroup] = [], artists: [StatisticGroup] = []
    var labels: [StatisticGroup] = [], years: [StatisticGroup] = [], decades: [StatisticGroup] = []
    var formats: [StatisticGroup] = [], countries: [StatisticGroup] = []
    var recentlyAdded: [UUID] = []
    var months: [AcquisitionBin] = [], acquisitionYears: [AcquisitionBin] = []
    var oldest: Int?, newest: Int?
    var missingYear = 0, missingGenre = 0, missingStyle = 0
    var highlights: [String] = []
}
enum CollectionAnalyticsService {
    // Pure value inputs: no API client, ModelContext or network work in the calculation.
    static func calculate(_ items: [AnalyticsItem], uniqueReleases: Bool = false, now: Date = .now, calendar: Calendar = .current) -> CollectionStatistics {
        var seen: Set<String> = []
        let items = uniqueReleases ? items.filter { seen.insert($0.releaseKey).inserted } : items
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
        s.artists = groups { $0.artists }; s.labels = groups { $0.labels }
        s.formats = groups { named($0.formats) }; s.countries = groups { named([$0.country]) }
        s.years = groups { named($0.year.map { [String($0)] } ?? []) }.sorted { $0.id < $1.id }
        s.decades = groups { named($0.year.map { ["\($0 / 10 * 10)er"] } ?? []) }.sorted { $0.id < $1.id }
        s.oldest = items.compactMap(\.year).min(); s.newest = items.compactMap(\.year).max()
        s.missingYear = items.filter { $0.year == nil }.count
        s.missingGenre = items.filter { $0.genres.isEmpty }.count; s.missingStyle = items.filter { $0.styles.isEmpty }.count
        let dated = items.filter { $0.added != nil }.sorted { $0.added == $1.added ? $0.id.uuidString < $1.id.uuidString : $0.added! > $1.added! }
        s.recentlyAdded = dated.prefix(10).map(\.id)
        func bins(_ component: Calendar.Component) -> [AcquisitionBin] {
            let dates = dated.compactMap { $0.added.flatMap { calendar.dateInterval(of: component, for: $0)?.start } }
            return Dictionary(grouping: dates, by: { $0 }).map { AcquisitionBin(date: $0.key, count: $0.value.count) }.sorted { $0.date < $1.date }
        }
        s.months = bins(.month); s.acquisitionYears = bins(.year)
        if let artist = s.artists.first { s.highlights.append("Häufigster Künstler: \(artist.name) · \(artist.count) Exemplare") }
        if let style = s.styles.first { s.highlights.append("Häufigster Style: \(style.name) · \(style.count) Exemplare") }
        if let decade = s.decades.max(by: { $0.count < $1.count }) { s.highlights.append("Stärkstes Jahrzehnt: \(decade.name) · \(decade.count) Exemplare") }
        if let year = s.years.max(by: { $0.count < $1.count }) { s.highlights.append("Häufigstes Erscheinungsjahr: \(year.name) · \(year.count) Exemplare") }
        let thisYear = dated.filter { calendar.isDate($0.added!, equalTo: now, toGranularity: .year) }.count
        s.highlights.append("Dieses Jahr hinzugefügt: \(thisYear) Exemplare")
        let previousYear = calendar.component(.year, from: now) - 1
        let lastYear = dated.filter { calendar.component(.year, from: $0.added!) == previousYear }.count
        s.highlights.append("Letztes Jahr hinzugefügt: \(lastYear) Exemplare")
        return s
    }
}
