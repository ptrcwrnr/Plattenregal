import Darwin
import Foundation

/// What the widget „Platte des Tages“ shows: one record for each of the next
/// days, written by the app into a folder it shares with the widget, read by
/// the widget. Part of the app and of the widget alike.
///
/// An app group would be the usual way, but it needs a provisioning profile,
/// which an ad hoc signed app does not have. Instead both sandboxes have an
/// exception for this one folder: the app may write there, the widget only
/// read (`Plattenregal.entitlements`, `PlattenregalWidget.entitlements`).
nonisolated struct RecordOfTheDay: Codable, Equatable, Sendable {
    /// The shared folder below the home folder; must match the exceptions.
    static let folderPath = "Library/Application Support/Plattenregal Widget"
    static let fileName = "platte-des-tages.json"
    /// Raised when the format changes in a way an older widget can't read.
    static let formatVersion = 1
    /// The address the widget opens: the shelf page with the card for the record.
    static let linkScheme = "plattenregal"
    static let linkHost = "platte"

    /// One day's record, already in words: the widget formats nothing.
    struct Day: Codable, Equatable, Sendable, Identifiable {
        /// The day as a running number (`RecordOfTheDay.dayNumber`).
        let day: Int
        /// Its start, in the time zone the app wrote it in.
        let date: Date
        /// The copy (`RecordCopy.id`) – for the link into the shelf.
        let copyID: UUID
        let artist: String
        let title: String
        /// The release's Discogs ID: the color of the drawn cover the widget
        /// shows while it has no image, the same as the app's drawn covers.
        let seed: Int
        /// The first tracks, for the large widget.
        let tracks: [TrackLine]
        /// „1998 · Warp“, as under the covers; may be empty.
        let details: String
        /// Where it stands („KALLAX · A – Be · Position 3“), where it belongs
        /// („Gehört in A – Be“) or „Ohne Regalplatz“.
        let place: String
        /// Stands in a compartment (`place` says where), or doesn't.
        let isPlaced: Bool
        /// The cover's file in the shared folder; nil while it couldn't be
        /// loaded (no network), the widget then draws the record instead.
        var cover: String?
        var id: Int { day }
    }

    /// A track as the record's popover lists it.
    struct TrackLine: Codable, Equatable, Sendable {
        let position: String
        let title: String
    }

    /// The design of the app, so the widget looks like it.
    enum Design: String, Codable, Sendable {
        case classic, modern
    }

    /// A color as sRGB components, in light and in dark mode.
    struct Tint: Codable, Equatable, Sendable {
        let light: [Double]
        let dark: [Double]
    }

    /// A day's pick, kept a while so the next days don't repeat it.
    struct Pick: Codable, Equatable, Sendable {
        let day: Int
        let copyID: UUID
    }

    var formatVersion = Self.formatVersion
    /// The design the app is set to; a widget can be set to the other one.
    var design: Design
    /// How Klassisch frames its covers (sleeve or passepartout); Modern
    /// always lays them on its mat.
    var classicFrame: RecordFrame
    /// Modern's accent, also while the app shows Klassisch; nil = the system's.
    var accent: Tint?
    /// Today and the next days, in order.
    var days: [Day]
    /// Days already past, newest last, for picks without repeats.
    var history: [Pick]

    /// The entry for `date`: the last day that has begun – or, before the
    /// first one (clock turned back), the first. After the last day the last
    /// one stays, until the app writes new days.
    func day(at date: Date) -> Day? {
        days.last { $0.date <= date } ?? days.first
    }

    /// The days from the one shown at `date` on.
    func days(from date: Date) -> [Day] {
        guard let current = day(at: date), let index = days.firstIndex(of: current) else { return [] }
        return Array(days[index...])
    }

    /// A running number for the day `date` falls on, in `calendar`.
    static func dayNumber(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    // MARK: Link

    static func link(to copyID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = linkScheme
        components.host = linkHost
        components.path = "/" + copyID.uuidString
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// The copy a link from the widget points to; nil for anything else.
    static func copyID(from url: URL) -> UUID? {
        guard url.scheme == linkScheme, url.host == linkHost else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    // MARK: Files

    /// In the sandbox the home folder is the app's own container; the
    /// exception names a path below the account's real home folder.
    static var folderURL: URL? {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent(folderPath, isDirectory: true)
    }

    static func load(from folder: URL? = folderURL) -> RecordOfTheDay? {
        guard let folder, let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)),
              let snapshot = try? JSONDecoder().decode(RecordOfTheDay.self, from: data),
              snapshot.formatVersion == formatVersion else { return nil }
        return snapshot
    }

    /// Writes the file in one go, so the widget never reads half of it.
    func save(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }

    static func coverURL(_ name: String, in folder: URL? = folderURL) -> URL? {
        folder?.appendingPathComponent(name, isDirectory: false)
    }
}
