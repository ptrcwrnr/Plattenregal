import Foundation
import SwiftData

/// The export as set on the settings' "Export" tab, read from the user
/// defaults – used by the manual and the automatic export alike.
struct ExportSettings {
    static let formatKey = "exportFormat", sourceKey = "exportSource", orderKey = "exportOrder"
    static let delimiterKey = "exportDelimiter", groupsKey = "exportGroups"

    var format = ExportFormat.csv
    var source = ExportSource.collection
    var order = ExportOrder.shelf
    var delimiter = ExportDelimiter.semicolon
    var groups: Set<ExportColumnGroup> = []

    static var stored: ExportSettings {
        let defaults = AppDefaults.store
        var settings = ExportSettings()
        if let value = defaults.string(forKey: formatKey).flatMap(ExportFormat.init) { settings.format = value }
        if let value = defaults.string(forKey: sourceKey).flatMap(ExportSource.init) { settings.source = value }
        if let value = defaults.string(forKey: orderKey).flatMap(ExportOrder.init) { settings.order = value }
        if let value = defaults.string(forKey: delimiterKey).flatMap(ExportDelimiter.init) { settings.delimiter = value }
        if let value = defaults.string(forKey: groupsKey) { settings.groups = parseGroups(value) }
        return settings
    }

    static func parseGroups(_ value: String) -> Set<ExportColumnGroup> {
        Set(value.split(separator: ",").compactMap { ExportColumnGroup(rawValue: String($0)) })
    }

    var fileExtension: String { format == .csv ? "csv" : "pdf" }

    /// Reads everything the file will list from the store. Cheap next to
    /// `ExportJob.render()`, which can then run off the main actor.
    func prepare(context: ModelContext, labelStyle: ShelfLabelStyle) throws -> ExportJob {
        // The PDF always shows where each record stands.
        var options = ExportOptions(source: source, order: source == .collection ? order : .artist,
                                    groups: format == .pdf ? [.location] : groups, delimiter: delimiter)
        if source == .wantlist { options.groups.remove(.location) }
        let table = try CollectionExportService(context: context, labelStyle: labelStyle).table(options)
        switch format {
        case .csv:
            return ExportJob(table: table, kind: .csv(delimiter))
        case .pdf:
            let subtitle = String(localized: "\(AppStyle.records(table.rows.count)) · \(options.order.title) · Stand \(Date.now.formatted(date: .long, time: .shortened))")
            return ExportJob(table: table, kind: .pdf(title: String(localized: "Plattenregal – \(source.title)"), subtitle: subtitle))
        }
    }
}

/// An export read from the store and ready to be turned into a file – a
/// plain value, so a large PDF is drawn without holding up the interface.
nonisolated struct ExportJob: Sendable {
    enum Kind: Sendable { case csv(ExportDelimiter), pdf(title: String, subtitle: String) }
    let table: ExportTable
    let kind: Kind
    var rows: Int { table.rows.count }

    func render() throws -> Data {
        switch kind {
        case .csv(let delimiter): CSVWriter.data(for: table, delimiter: delimiter)
        case .pdf(let title, let subtitle): try PDFListWriter.data(for: table, title: title, subtitle: subtitle)
        }
    }

    /// `render()` on a background thread.
    func renderedInBackground() async throws -> Data {
        try await Task.detached(priority: .userInitiated) { try render() }.value
    }
}

enum ExportInterval: String, CaseIterable, Identifiable {
    case daily, weekly, monthly
    var id: Self { self }
    var title: String {
        switch self {
        case .daily: String(localized: "Täglich")
        case .weekly: String(localized: "Wöchentlich")
        case .monthly: String(localized: "Monatlich")
        }
    }
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily: calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly: calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .monthly: calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
}

/// Writes the export on its own at a fixed interval into a chosen folder,
/// always into the same file ("Plattenregal Collection.csv"), which is
/// replaced each time. Checked at launch and every half hour while the app
/// runs; a missed date is caught up on the next check.
@Observable final class ScheduledExport {
    static let shared = ScheduledExport()

    static let enabledKey = "autoExportEnabled"
    static let intervalKey = "autoExportInterval"
    static let lastRunKey = "autoExportLastRun"
    static let folder = FolderAccess(key: "autoExportFolder")

    /// Bumped after every run, so the settings refresh.
    private(set) var version = 0
    private(set) var lastError: String?
    /// A run is drawing or writing the file; a second one waits for the next check.
    private(set) var isRunning = false
    private var loop: Task<Void, Never>?
    private var container: ModelContainer?
    private var soon: Task<Void, Never>?

    var isEnabled: Bool { AppDefaults.store.bool(forKey: Self.enabledKey) }
    var interval: ExportInterval {
        AppDefaults.store.string(forKey: Self.intervalKey).flatMap(ExportInterval.init) ?? .weekly
    }
    var lastRun: Date? { AppDefaults.store.object(forKey: Self.lastRunKey) as? Date }
    var nextRun: Date? {
        guard isEnabled, Self.folder.isSet else { return nil }
        return Self.nextRun(after: lastRun, interval: interval)
    }
    /// Never run: now. A last run in the future (the Mac's clock was wrong at
    /// the time) would hold the export back until then; it counts as due.
    static func nextRun(after lastRun: Date?, interval: ExportInterval, now: Date = .now) -> Date {
        guard let lastRun, lastRun <= now else { return now }
        return interval.next(after: lastRun)
    }

    static func fileName(for settings: ExportSettings) -> String {
        "Plattenregal \(settings.source.title)\(DemoMode.fileSuffix).\(settings.fileExtension)"
    }

    /// Once per launch, for the app's real store only.
    func start(container: ModelContainer) {
        guard loop == nil, ShelfAutoBackup.isAppStore(container) else { return }
        self.container = container
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                await self?.runIfDue(container: container)
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    func runIfDue(container: ModelContainer) async {
        // Never in the demo: it would write sample data into a real folder.
        guard !DemoMode.isActive, !isRunning, let next = nextRun, next <= .now else { return }
        // A sync in progress would leave a half-updated list; try on the next check.
        guard !DiscogsSyncService.shared.busy else { return }
        // An empty list (before the first sync, after "Alles zurücksetzen" or
        // a lost database) must never replace the last good file. Tried again
        // on the next check.
        guard CollectionExportService(context: container.mainContext).count(ExportSettings.stored.source) > 0 else {
            AppLog.warning("Export", "Automatischer Export übersprungen: keine Platten in der \(ExportSettings.stored.source.title)")
            return
        }
        _ = try? await run(container: container)
    }

    /// Writes the file now. Returns its name. The records are read here;
    /// drawing the file and writing it (maybe to a slow network or iCloud
    /// folder) happen off the main actor.
    @discardableResult func run(container: ModelContainer) async throws -> String {
        guard !isRunning else { throw CancellationError() }
        isRunning = true
        defer { isRunning = false }
        let settings = ExportSettings.stored
        let name = Self.fileName(for: settings)
        do {
            let job: ExportJob
            do { job = try settings.prepare(context: container.mainContext, labelStyle: ShelfRangeLabels.currentStyle) }
            catch { throw FileTransferError.exportFailed(error) }
            let folder = Self.folder
            try await Task.detached(priority: .utility) {
                let data: Data
                do { data = try job.render() } catch { throw FileTransferError.exportFailed(error) }
                try folder.withAccess { folder in
                    try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                }
            }.value
            AppDefaults.store.set(Date.now, forKey: Self.lastRunKey)
            lastError = nil
            AppLog.info("Export", "Automatischer Export geschrieben: \(name), \(AppStyle.records(job.rows))")
        } catch {
            // `reportedMessage` also writes the technical detail to the log –
            // once: a folder that stays unreachable fails every half hour.
            let failure = error as? FileTransferError ?? .writeFailed(error)
            lastError = failure.userMessage == lastError ? failure.userMessage : failure.reportedMessage()
            version += 1
            throw error
        }
        version += 1
        return name
    }

    /// Switched on, folder chosen or interval changed: a now due export is
    /// written within seconds instead of at the next half-hourly check.
    func settingsChanged() {
        version += 1
        guard let container else { return }
        soon?.cancel()
        soon = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.runIfDue(container: container)
        }
    }
}
