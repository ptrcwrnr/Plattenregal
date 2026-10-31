import AppKit
import CryptoKit
import ImageIO
import Observation
import SwiftData
import UniformTypeIdentifiers
import WidgetKit

/// Keeps the widget „Platte des Tages“ current: picks a record from the
/// collection for today and each of the next days, writes them with their
/// covers into the folder the widget reads (`RecordOfTheDay`) and asks the
/// widget to reload – only when what it shows changed.
///
/// The picks stay put: a day keeps its record while it is still in the
/// collection, however the collection changes meanwhile, and no record comes
/// back within `repeatGap` days. Which record a day gets follows from the
/// day and the record alone (`picks`), so it is the same on every launch.
///
/// Never in the demo or in tests: their collections aren't the user's.
@MainActor final class RecordOfTheDayPublisher {
    static let shared = RecordOfTheDayPublisher()
    /// Today and the days after it: the widget goes on that long without the app.
    static let daysAhead = 14
    /// How many days no record comes back (fewer in a small collection).
    nonisolated static let repeatGap = 60
    /// Past picks kept for that.
    nonisolated static let historyLength = repeatGap
    /// Edge of the covers written for the widget: sharp on the large one.
    static let coverPixels = 640
    nonisolated static let coverQuality = 0.85
    /// Tracks written per day: more than the large widget has room for, it
    /// counts the rest.
    static let trackCount = 24
    /// Changes within this time go out together.
    static let pause: Duration = .seconds(2)
    /// After a cover couldn't be loaded (no network), the next try.
    static let retryPause: Duration = .seconds(30 * 60)

    private let folder: URL?
    private let reload: () -> Void
    private let now: () -> Date
    private var container: ModelContainer?
    private var pending: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    /// Counts the runs; a run that a newer one overtook doesn't write.
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private let labelsCache = ShelfLabelsCache()
    /// The records to pick from, kept while the collection stays the same:
    /// sorting in – the most frequent change – leaves them as they are, and
    /// reading every record's properties took a third of a run (5 000 records).
    private var candidates: Candidates?
    /// The covers that couldn't be loaded when last logged: offline, every
    /// run would log them again.
    private var loggedMissing: Set<String> = []
    /// The settings outside `AppPreferences` that change what the widget
    /// shows; compared on every change of the user defaults.
    private var settingsState: [String] = []

    init(folder: URL? = RecordOfTheDay.folderURL,
         reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() },
         now: @escaping () -> Date = Date.init) {
        self.folder = folder
        self.reload = reload
        self.now = now
    }

    /// The collection to pick from, without following its changes (tests
    /// call `publish` themselves).
    func attach(_ container: ModelContainer) {
        self.container = container
    }

    /// Called once the collection is open (see `PlattenregalApp`).
    func start(container: ModelContainer) {
        guard self.container == nil else { return }
        attach(container)
        settingsState = Self.settings()
        follow()
        let center = NotificationCenter.default
        // A new day (also after sleep, a changed clock or time zone): the
        // days move on and a new one is picked.
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        })
        // Label style and order of a compartment are plain user defaults.
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsMayHaveChanged() }
        })
        schedule()
    }

    /// Follows what the widget shows of the collection and the design.
    private func follow() {
        guard let context = container?.mainContext else { return }
        withObservationTracking {
            let changes = LibraryChanges.shared
            // Tracklists arrive after a sync, in the background: the large
            // widget lists them. Many changes in a row go out once (`pause`).
            _ = (changes.libraryVersion, changes.tracksVersion, changes.placementsVersion, changes.shelvesVersion)
            let records = LibraryRecords.of(context)
            _ = (records.copies, records.exclusions, records.accounts)
            let preferences = AppPreferences.shared
            _ = (preferences.drawnCovers, preferences.signatureDesign, preferences.accent)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.follow()
                self?.schedule()
            }
        }
    }

    private static func settings() -> [String] {
        [ShelfRangeLabels.currentStyle.rawValue, ShelfSecondaryOrder.current.rawValue, AtelierCoverFrame.current.rawValue]
    }

    private func settingsMayHaveChanged() {
        let state = Self.settings()
        guard state != settingsState else { return }
        settingsState = state
        schedule()
    }

    /// Publishes after a short pause; changes meanwhile go out with it.
    func schedule() {
        guard container != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            await self?.publish()
        }
    }

    /// Picks the days, writes what is missing and reloads the widget if
    /// anything it shows changed. A failure is logged, never shown.
    func publish() async {
        guard let container, let folder else { return }
        generation += 1
        let run = generation
        let previous = RecordOfTheDay.load(from: folder)
        let (draft, sources) = makeSnapshot(context: container.mainContext, previous: previous, at: now())
        var snapshot = draft
        var missing: [String: Error] = [:]
        for (index, day) in snapshot.days.enumerated() {
            guard let source = sources[day.day] else { continue }
            if let error = await writeCover(source, in: folder) {
                missing[source.name] = error
            } else {
                snapshot.days[index].cover = source.name
            }
            // A newer run took over (or the app reset meanwhile).
            guard run == generation else { return }
        }
        if Set(missing.keys) != loggedMissing {
            loggedMissing = Set(missing.keys)
            if let error = missing.values.first {
                AppLog.warning("Widget", "\(missing.count) Cover für Platte des Tages nicht geladen: \(error.localizedDescription)")
            }
        }
        if snapshot != previous {
            do {
                try snapshot.save(to: folder)
                reload()
                AppLog.info("Widget", "Platte des Tages: \(snapshot.days.count) Tage geschrieben"
                            + (missing.isEmpty ? "" : ", \(missing.count) Cover fehlen noch"))
            } catch {
                AppLog.error("Widget", "Platte des Tages nicht geschrieben: \(error)")
                return
            }
        }
        removeUnusedCovers(keeping: Set(snapshot.days.compactMap(\.cover)), in: folder)
        retry?.cancel()
        if !missing.isEmpty {
            retry = Task { [weak self] in
                try? await Task.sleep(for: Self.retryPause)
                guard !Task.isCancelled else { return }
                self?.schedule()
            }
        }
    }

    // MARK: Picking

    /// Where a day's cover comes from and the file it goes into.
    struct CoverSource: Equatable {
        let url: URL
        let name: String
    }

    /// The records in the collection the app shows, with what picking needs.
    private struct Candidates {
        /// The collection's state they were read in.
        let library: Int
        let owner: String?
        let count: Int
        let byID: [UUID: RecordCopy]
        let keys: [(id: UUID, key: UInt64)]
    }

    /// Only records still there (a reset may be under way) and in the
    /// collection the app shows. Read again when the collection changed
    /// (a sync, a reset, records added or removed).
    private func currentCandidates(_ records: LibraryRecords, owner: String?) -> Candidates {
        let library = LibraryChanges.shared.libraryVersion
        if let candidates, candidates.library == library, candidates.owner == owner, candidates.count == records.copies.count {
            return candidates
        }
        let copies = records.copies.filter {
            !$0.isDeleted && $0.modelContext != nil && $0.release != nil && $0.isInCurrentCollection(owner: owner)
        }
        let fresh = Candidates(library: library, owner: owner, count: records.copies.count,
                               byID: Dictionary(copies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                               keys: copies.map { ($0.id, Self.key(of: $0)) })
        candidates = fresh
        return fresh
    }

    /// The snapshot for `date`, without covers yet, and where to get them.
    func makeSnapshot(context: ModelContext, previous: RecordOfTheDay?, at date: Date) -> (RecordOfTheDay, [Int: CoverSource]) {
        let calendar = Calendar.current
        let records = LibraryRecords.of(context)
        let owner = DiscogsAccount.current(in: records.accounts)?.username
        let current = currentCandidates(records, owner: owner)
        let byID = current.byID
        let today = calendar.startOfDay(for: date)
        let todayNumber = RecordOfTheDay.dayNumber(today, calendar: calendar)
        let dates = (0..<Self.daysAhead).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let numbers = dates.map { RecordOfTheDay.dayNumber($0, calendar: calendar) }

        // The days already picked stay; the past ones go into the history.
        let kept = Dictionary((previous?.days ?? []).filter { $0.day >= todayNumber }.map { ($0.day, $0.copyID) },
                              uniquingKeysWith: { first, _ in first })
        let past = (previous?.history ?? []) + (previous?.days ?? []).filter { $0.day < todayNumber }.map {
            RecordOfTheDay.Pick(day: $0.day, copyID: $0.copyID)
        }
        let history = Self.trimmed(past, before: todayNumber)
        // Every day already has its record (the usual case: sorting in, a
        // sync without news): no need to weigh the whole collection.
        let complete = numbers.allSatisfy { kept[$0].map { byID[$0] != nil } ?? false }
        let picks = complete ? kept : Self.picks(for: numbers, candidates: current.keys, kept: kept, history: history)

        let shelves = records.shelves
        let inUse = Shelf.inUse(shelves)
        let labels = labelsCache.labels(for: shelves, style: ShelfRangeLabels.currentStyle)
        let excluded = Set(records.exclusions.map(\.copyID))
        // Where the picked records without a shelf belong, all in one go:
        // one at a time walked every shelf for each.
        let homeless = Set(numbers.compactMap { picks[$0] }).compactMap { byID[$0] }
            .filter { !$0.isDeleted && $0.modelContext != nil && $0.shelf == nil && !excluded.contains($0.id) }
        let fitting = AlphabeticalPlacement.fittingShelves(for: homeless, in: inUse)
        var sources: [Int: CoverSource] = [:]
        var days: [RecordOfTheDay.Day] = []
        for (number, dayDate) in zip(numbers, dates) {
            // A record may have gone since the list was read (a reset not
            // reported yet): its day stays empty until the next run.
            guard let id = picks[number], let copy = byID[id], !copy.isDeleted, copy.modelContext != nil,
                  let release = copy.release else { continue }
            let (place, placed) = Self.place(of: copy, labels: labels, inUse: inUse, fitting: fitting[id], excluded: excluded.contains(id))
            let details = [release.year.map(String.init), release.label.isEmpty ? nil : release.displayLabel]
                .compactMap { $0 }.joined(separator: " · ")
            // A record without a Discogs image gets a drawn one, as everywhere.
            let address = release.shownCoverURL
                ?? DemoCover.url(artist: release.displayArtist, title: release.displayTitle, seed: release.discogsID)
            if let url = URL(string: address) {
                sources[number] = CoverSource(url: url, name: Self.coverName(address))
            }
            days.append(RecordOfTheDay.Day(day: number, date: dayDate, copyID: id, artist: release.displayArtist,
                                           title: release.displayTitle, seed: release.discogsID,
                                           tracks: release.tracks.filter { !$0.title.isEmpty }.prefix(Self.trackCount)
                                               .map { RecordOfTheDay.TrackLine(position: $0.position, title: $0.title) },
                                           details: details, place: place,
                                           isPlaced: placed, cover: nil))
        }
        // Both designs' details: a widget may be set to the one the app isn't.
        let snapshot = RecordOfTheDay(design: AppStyle.isAtelier ? .classic : .modern,
                                      classicFrame: AtelierCoverFrame.classicFrame,
                                      accent: Self.tint(AppPreferences.shared.accent),
                                      days: days, history: history)
        return (snapshot, sources)
    }

    /// The record of each day in `days`: a kept one while it is still a
    /// candidate, otherwise the candidate with the lowest score for that day
    /// among those not shown within `repeatGap` days before or after it.
    nonisolated static func picks(for days: [Int], candidates: [(id: UUID, key: UInt64)],
                                  kept: [Int: UUID], history: [RecordOfTheDay.Pick]) -> [Int: UUID] {
        guard !candidates.isEmpty else { return [:] }
        let valid = Set(candidates.map(\.id))
        // A small collection can't go long without repeats.
        let gap = min(repeatGap, candidates.count - 1)
        var shown: [Int: UUID] = [:]
        for pick in history { shown[pick.day] = pick.copyID }
        for (day, id) in kept where valid.contains(id) && days.contains(day) { shown[day] = id }
        var result: [Int: UUID] = [:]
        for day in days.sorted() {
            if let id = kept[day], valid.contains(id) {
                result[day] = id
                continue
            }
            let blocked = Set(shown.compactMap { abs($0.key - day) <= gap && $0.key != day ? $0.value : nil })
            let pick = candidates.lazy.filter { !blocked.contains($0.id) }.min { score(day, $0.key) < score(day, $1.key) }
                ?? candidates.min { score(day, $0.key) < score(day, $1.key) }
            if let pick {
                result[day] = pick.id
                shown[day] = pick.id
            }
        }
        return result
    }

    /// A number that orders the candidates differently each day, the same on
    /// every launch (Swift's `Hasher` is seeded anew per process).
    nonisolated static func score(_ day: Int, _ key: UInt64) -> UInt64 {
        var z = UInt64(bitPattern: Int64(day)) &* 0x9E37_79B9_7F4A_7C15 ^ key
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A record's identity across launches and resets: its Discogs instance.
    static func key(of copy: RecordCopy) -> UInt64 {
        if copy.discogsInstanceID != 0 { return UInt64(bitPattern: Int64(copy.discogsInstanceID)) }
        return withUnsafeBytes(of: copy.id.uuid) { $0.load(as: UInt64.self) }
    }

    nonisolated static func trimmed(_ picks: [RecordOfTheDay.Pick], before today: Int) -> [RecordOfTheDay.Pick] {
        var byDay: [Int: UUID] = [:]
        for pick in picks where pick.day < today && pick.day >= today - historyLength { byDay[pick.day] = pick.copyID }
        return byDay.keys.sorted().map { RecordOfTheDay.Pick(day: $0, copyID: byDay[$0]!) }
    }

    /// Where the record stands, in words like on the statistics' random pick
    /// – or where it belongs: `fitting`, the shelves it fits
    /// (`AlphabeticalPlacement.fittingShelves`). At the border of two the
    /// placement card's own choice decides, so both name the same shelf.
    static func place(of copy: RecordCopy, labels: ShelfLabels, inUse: [Shelf], fitting: [Shelf]?, excluded: Bool) -> (String, Bool) {
        if copy.shelf != nil { return (ShelfRangeLabels.location(of: copy, labels: labels, excluded: excluded), true) }
        if excluded { return (String(localized: "Ohne Regalplatz"), false) }
        let fitting = fitting ?? []
        let chosen = fitting.count > 1 ? Placement(copy: copy, shelves: inUse).spot?.shelf : fitting.first
        guard let shelf = chosen else {
            return (String(localized: "Noch nicht einsortiert"), false)
        }
        let name = labels.prefix(for: shelf) + (labels[shelf.id] ?? shelf.title)
        return (String(localized: "Gehört in „\(name)“"), false)
    }

    /// Modern's accent in light and dark; nil for the system's, which the
    /// widget takes itself.
    static func tint(_ choice: AccentChoice) -> RecordOfTheDay.Tint? {
        guard choice != .system else { return nil }
        let color = NSColor(choice.color)
        func components(_ name: NSAppearance.Name) -> [Double] {
            var result: [Double] = []
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
                if let rgb = color.usingColorSpace(.sRGB) {
                    result = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map(Double.init)
                }
            }
            return result
        }
        let light = components(.aqua), dark = components(.darkAqua)
        guard light.count == 3, dark.count == 3 else { return nil }
        return RecordOfTheDay.Tint(light: light, dark: dark)
    }

    // MARK: Covers

    /// One file per cover address: a new cover on Discogs or switching to
    /// drawn covers gives a new file, an unchanged one is written once.
    nonisolated static func coverName(_ address: String) -> String {
        SHA256.hash(data: Data(address.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    /// The cover in the shared folder: already there, or loaded (from the
    /// cover cache, Discogs or drawn) and written. The error if it couldn't be.
    private func writeCover(_ source: CoverSource, in folder: URL) async -> Error? {
        let file = folder.appendingPathComponent(source.name)
        if FileManager.default.fileExists(atPath: file.path) { return nil }
        do {
            let payload = try await CoverCache.shared.imageForExport(source.url, maximumPixelSize: Self.coverPixels)
            try await Self.writeJPEG(payload, to: file)
            return nil
        } catch {
            return error
        }
    }

    @concurrent nonisolated private static func writeJPEG(_ payload: CoverCache.ImagePayload, to file: URL) async throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, payload.image, [kCGImageDestinationLossyCompressionQuality: coverQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try (data as Data).write(to: file, options: .atomic)
    }

    /// Covers of days gone by or of records no longer picked.
    private func removeUnusedCovers(keeping used: Set<String>, in folder: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "jpg" && !used.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// MARK: - Link from the widget

extension RecordOfTheDayPublisher {
    /// A click on the widget: the shelf page with the card for the record
    /// („Hier steht …“ or „Einsortieren …“), as ↩ in the menu bar search.
    /// False for addresses that aren't the widget's.
    @discardableResult static func open(_ url: URL) -> Bool {
        guard let id = RecordOfTheDay.copyID(from: url) else { return false }
        let search = ShelfQuickSearch.shared
        let copy = search.container.flatMap {
            try? $0.mainContext.fetch(FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.id == id })).first
        }
        AppLog.info("Widget", copy == nil ? "Platte des Tages geöffnet, Platte nicht mehr da" : "Platte des Tages im Regal gezeigt")
        if search.openMainWindow == nil {
            // Launched by the click: the main window is on its way and takes
            // the record when it appears (`RootView`).
            search.pendingCopy = copy?.id
            NSApp.activate()
        } else if let copy {
            search.showInShelf(copy)
        } else {
            search.showMainWindow()
        }
        return true
    }
}
