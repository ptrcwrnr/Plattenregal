import AppKit
import Foundation
import SwiftData

// MARK: - Automatic backups

/// Keeps the last few layouts as files in the app's own folder, written a
/// few seconds after the shelf last changed. Unchanged layouts aren't written again.
@Observable final class ShelfAutoBackup {
    static let shared = ShelfAutoBackup()
    static let enabledKey = "shelfAutoBackupEnabled"
    /// The most recent states, plus the last state of each of the past
    /// `keptDays` days – so a burst of changes (e.g. re-sorting after data
    /// loss) never pushes out every backup from before. Both can be set in
    /// the settings.
    static let keptCountKey = "shelfBackupKeptCount"
    static let keptDaysKey = "shelfBackupKeptDays"
    static let defaultKeptCount = 10
    static let defaultKeptDays = 14
    static let keptCountOptions = [5, 10, 20, 50]
    static let keptDaysOptions = [0, 7, 14, 30, 90]
    static var keptCount: Int { (AppDefaults.store.object(forKey: keptCountKey) as? Int).map { max(1, $0) } ?? defaultKeptCount }
    static var keptDays: Int { (AppDefaults.store.object(forKey: keptDaysKey) as? Int).map { max(0, $0) } ?? defaultKeptDays }
    /// Another folder than the app's own (e.g. iCloud Drive), if chosen.
    nonisolated static let folder = FolderAccess(key: "shelfBackupFolder")

    struct Entry: Identifiable {
        let url: URL
        let backup: ShelfBackup
        var id: URL { url }
    }

    /// Bumped after every write, so the settings list reloads.
    private(set) var version = 0
    /// Set when the last automatic backup failed, cleared by the next success.
    private(set) var lastFailure: Date?
    private var pending: Task<Void, Never>?
    private var pendingContainer: ModelContainer?
    /// Files already read, by their modification date: the list reloads after
    /// every change and sync, and up to ~140 files of a large collection
    /// (maybe in iCloud) must not be parsed again each time.
    /// An unreadable file is kept as `nil`, so it isn't read and logged again.
    private var cache: [URL: (modified: Date?, backup: ShelfBackup?)] = [:]
    private var observesTermination = false

    var isEnabled: Bool {
        AppDefaults.store.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// The app's own folder inside its container.
    nonisolated static var defaultDirectory: URL? {
        // The demo never lists, prunes or writes the real backups.
        if DemoMode.isActive { return DemoMode.temporaryDirectory.appendingPathComponent("Sicherungen", isDirectory: true) }
        return try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Plattenregal/Sicherungen", isDirectory: true)
    }

    /// Where backups are written and listed: the chosen folder, or the
    /// app's own one when none is chosen or it can't be found any more.
    var directory: URL? { Self.folder.url ?? Self.defaultDirectory }
    var usesCustomFolder: Bool { Self.folder.url != nil }

    /// Runs `body` with the backup folder open for reading and writing.
    nonisolated private static func inDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        if Self.folder.url != nil { return try Self.folder.withAccess(body) }
        guard let directory = Self.defaultDirectory else { throw CocoaError(.fileNoSuchFile) }
        return try body(directory)
    }

    /// Switches to another folder (`nil` = the app's own). Existing backups
    /// are copied over, so the list and the retention carry on; the old
    /// folder keeps its copies.
    func moveBackups(to url: URL?) throws {
        // The demo's retention must never reach a folder holding real backups.
        guard !DemoMode.isActive else { return }
        let old = entries()
        let previousBookmark = AppDefaults.store.data(forKey: Self.folder.key)
        if let url { try Self.folder.set(url) } else { Self.folder.clear() }
        do {
            try Self.inDirectory { directory in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for entry in old {
                    let target = directory.appendingPathComponent(entry.url.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: target.path) {
                        try ShelfBackupService.encode(entry.backup).write(to: target, options: .atomic)
                    }
                }
            }
        } catch {
            // Not writable (or full): stay with the old folder instead of
            // switching to one that holds only part of the backups.
            AppDefaults.store.set(previousBookmark, forKey: Self.folder.key)
            AppLog.error("Sicherung", "Speicherort nicht gewechselt, Sicherungen ließen sich nicht kopieren: \(error)")
            throw error
        }
        AppLog.info("Sicherung", "Speicherort der automatischen Sicherung: \(url.map(FolderAccess.displayName) ?? "Standard")")
        prune()
        version += 1
    }

    /// How many existing files a retention of `keptCount`/`keptDays` would delete.
    func filesRemoved(keptCount: Int, keptDays: Int) -> Int {
        let all = Self.ownFiles()
        return all.count - Set(Self.retained(all.map(\.date), keptCount: keptCount, keptDays: keptDays)).count
    }

    /// Applies a changed retention right away.
    func applyRetention() {
        prune()
        version += 1
    }

    /// Called after every committed shelf change. Only the app's real store
    /// is backed up – never test or demo stores.
    func scheduleBackup(of container: ModelContainer) {
        guard isEnabled, Self.isAppStore(container) else { return }
        observeTermination()
        pending?.cancel()
        pendingContainer = container
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.runPendingInBackground()
        }
    }

    nonisolated static func isAppStore(_ container: ModelContainer) -> Bool {
        guard let store = try? LibraryStorage.storeURL() else { return false }
        return container.configurations.contains { !$0.isStoredInMemoryOnly && $0.url.standardizedFileURL == store.standardizedFileURL }
    }

    /// On quit: synchronously, or the app would be gone before the file is written.
    private func runPending() {
        guard let container = pendingContainer else { return }
        pending?.cancel(); pending = nil; pendingContainer = nil
        // Switched off while waiting.
        guard isEnabled else { return }
        recordOutcome { try backUpNow(ShelfBackupService(context: container.mainContext), skipEmpty: true) }
    }

    /// A few seconds after the last change: the file is compared and written
    /// off the main actor, so a slow folder (iCloud, network) never holds up the shelf.
    private func runPendingInBackground() async {
        guard let container = pendingContainer else { return }
        guard isEnabled else { pendingContainer = nil; return }
        do {
            try await backUpInBackground(container)
            lastFailure = nil
        } catch {
            lastFailure = .now
            AppLog.error("Sicherung", "Automatische Sicherung fehlgeschlagen: \(error)")
        }
        // Only now: quitting while the file is still being written writes it
        // once more on the way out. A newer change has scheduled its own run.
        if !Task.isCancelled { pending = nil; pendingContainer = nil }
    }

    private func recordOutcome(_ body: () throws -> Void) {
        do {
            try body()
            lastFailure = nil
        } catch {
            lastFailure = .now
            AppLog.error("Sicherung", "Automatische Sicherung fehlgeschlagen: \(error)")
        }
    }

    /// Quitting within the delay would lose the last change.
    private func observeTermination() {
        guard !observesTermination else { return }
        observesTermination = true
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ShelfAutoBackup.shared.runPending() }
        }
    }

    /// Writes the current layout unless the newest file already holds it.
    /// Returns `false` when nothing had to be written.
    /// `skipEmpty`: an empty shelf (fresh install, lost database) is never
    /// worth an automatic backup of its own.
    @discardableResult func backUpNow(_ service: ShelfBackupService, skipEmpty: Bool = false) throws -> Bool {
        guard let backup = try Self.take(service, skipEmpty: skipEmpty) else { return false }
        return written(try Self.write(backup, keptCount: Self.keptCount, keptDays: Self.keptDays), backup)
    }

    /// `backUpNow` entirely off the main actor: the layout is read in a
    /// context of its own (for 900 records ~75 ms, a hitch while sorting on),
    /// then the files are read and written.
    private func backUpInBackground(_ container: ModelContainer) async throws {
        let keptCount = Self.keptCount, keptDays = Self.keptDays
        let result = try await Task.detached(priority: .utility) { () throws -> (name: String?, backup: ShelfBackup)? in
            guard ShelfAutoBackup.isAppStore(container) else { return nil }
            let backup = try ShelfBackupService.makeBackup(of: ModelContext(container))
            guard !backup.isEmpty else { return nil }
            return (try Self.write(backup, keptCount: keptCount, keptDays: keptDays), backup)
        }.value
        if let result { written(result.name, result.backup) }
    }

    private static func take(_ service: ShelfBackupService, skipEmpty: Bool) throws -> ShelfBackup? {
        // Demo and test stores never mix into the real backups.
        guard isAppStore(service.context.container) else { return nil }
        let backup = try service.makeBackup()
        return skipEmpty && backup.isEmpty ? nil : backup
    }

    /// Writes `backup` unless the newest file already holds its layout, then
    /// clears out old files. Returns the new file's name, `nil` when nothing
    /// had to be written.
    nonisolated private static func write(_ backup: ShelfBackup, keptCount: Int, keptDays: Int) throws -> String? {
        // Only the newest file is read – not every backup after each shelf change.
        if let newest = ownFiles().first,
           let latest = try? Self.inDirectory({ _ in try ShelfBackupService.read(newest.url) }),
           latest.hasSameLayout(as: backup) { return nil }
        let name = fileName(for: backup.createdAt)
        try Self.inDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ShelfBackupService.encode(backup).write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        prune(keptCount: keptCount, keptDays: keptDays)
        return name
    }

    @discardableResult private func written(_ name: String?, _ backup: ShelfBackup) -> Bool {
        guard let name else { return false }
        AppLog.info("Sicherung", "Automatisch gesichert: \(name) · \(backup.summary)")
        version += 1
        return true
    }

    /// Newest first.
    func entries() -> [Entry] {
        let files = (try? Self.inDirectory { directory in
            // Only the app's own files: anything else in the folder is neither
            // listed nor ever deleted when old backups are cleared.
            try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { Self.isOwnFile($0.lastPathComponent) }
                .map { url in (url: url, modified: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) }
        }) ?? []
        // Forget files that are gone (pruned, other folder).
        let listed = Set(files.map(\.url))
        cache = cache.filter { listed.contains($0.key) }
        let unread = files.filter { file in cache[file.url].map { $0.modified != file.modified || file.modified == nil } ?? true }
        if !unread.isEmpty {
            try? Self.inDirectory { _ in
                for file in unread {
                    do { cache[file.url] = (file.modified, try ShelfBackupService.read(file.url)) }
                    catch {
                        cache[file.url] = (file.modified, nil)
                        AppLog.warning("Sicherung", "Automatische Sicherung \(file.url.lastPathComponent) nicht lesbar, wird übergangen: \(error)")
                    }
                }
            }
        }
        return files.compactMap { file in cache[file.url]?.backup.map { Entry(url: file.url, backup: $0) } }
            .sorted { $0.backup.createdAt > $1.backup.createdAt }
    }

    /// The app's own files, newest first, dated by their name – without
    /// reading them. Runs after every backup, so it must stay cheap.
    nonisolated private static func ownFiles() -> [(url: URL, date: Date)] {
        let urls = (try? Self.inDirectory { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }) ?? []
        return urls.compactMap { url in Self.fileDate(of: url.lastPathComponent).map { (url, $0) } }
            .sorted { $0.date > $1.date }
    }

    private func prune() { Self.prune(keptCount: Self.keptCount, keptDays: Self.keptDays) }

    nonisolated private static func prune(keptCount: Int, keptDays: Int) {
        guard !DemoMode.isActive else { return }
        let all = ownFiles()
        let kept = Set(retained(all.map(\.date), keptCount: keptCount, keptDays: keptDays))
        for (index, file) in all.enumerated() where !kept.contains(index) {
            do { try Self.inDirectory { _ in try FileManager.default.removeItem(at: file.url) } }
            catch { AppLog.warning("Sicherung", "Alte Sicherung \(file.url.lastPathComponent) ließ sich nicht löschen: \(error)") }
        }
    }

    /// Indices (in `dates`, newest first) of the backups to keep.
    nonisolated static func retained(_ dates: [Date], keptCount: Int, keptDays: Int, calendar: Calendar = .current) -> [Int] {
        var kept = Array(dates.indices.prefix(keptCount))
        var days = Set<DateComponents>()
        for (index, date) in dates.enumerated() {
            let day = calendar.dateComponents([.year, .month, .day], from: date)
            guard days.count < keptDays || days.contains(day) else { break }
            if days.insert(day).inserted, index >= keptCount { kept.append(index) }
        }
        return kept
    }

    nonisolated private static let filePrefix = "Belegung "

    /// "Belegung 2026-09-24 10-41-05 +0200.json": local time, readable in the
    /// Finder, with its offset – the newest file and the retention go by this
    /// time, and without the offset the repeated hour when the clocks go back
    /// (or a trip to another time zone) would put a newer file behind older ones.
    nonisolated static func fileName(for date: Date, in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss Z"
        return filePrefix + formatter.string(from: date) + ".json"
    }

    /// Own files, including those from before the offset was added
    /// ("Belegung 2026-09-24 10-41-05.json", read as local time).
    nonisolated static func isOwnFile(_ name: String) -> Bool { fileDate(of: name) != nil }

    /// The time in an own file's name; `nil` for any other file.
    nonisolated static func fileDate(of name: String) -> Date? {
        guard name.hasPrefix(filePrefix), name.hasSuffix(".json") else { return nil }
        let stamp = String(name.dropFirst(filePrefix.count).dropLast(".json".count))
        return withOffset.date(from: stamp) ?? localTime.date(from: stamp)
    }

    // Only ever read after setup; DateFormatter is thread-safe for that.
    nonisolated private static let withOffset = posixFormatter("yyyy-MM-dd HH-mm-ss Z")
    nonisolated private static let localTime = posixFormatter("yyyy-MM-dd HH-mm-ss")
    nonisolated private static func posixFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
