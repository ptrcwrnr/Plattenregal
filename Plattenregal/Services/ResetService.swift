import Foundation
import SwiftData

extension Notification.Name {
    /// Posted after "Alles zurücksetzen", so views holding their own copy of
    /// removed state (e.g. the token field) let go of it.
    static let plattenregalDidReset = Notification.Name("PlattenregalDidReset")
}

enum ResetError: LocalizedError {
    case syncRunning, tokenNotRemoved
    var errorDescription: String? {
        switch self {
        case .syncRunning:
            String(localized: "Gerade läuft eine Synchronisierung mit Discogs. Warte, bis sie fertig ist, und setze dann zurück.")
        case .tokenNotRemoved:
            String(localized: "Alles andere ist zurückgesetzt, aber der Discogs-Token ließ sich nicht aus dem Schlüsselbund löschen. Entferne ihn unter „Discogs“ oder in der Schlüsselbundverwaltung.")
        }
    }
}

/// The three ways back to a clean state in the settings. Each one that
/// touches the shelf writes a backup of the current layout first; without
/// that safety net nothing is reset.
struct ResetService {
    let context: ModelContext

    /// Every record leaves its compartment, locks and names are lifted and
    /// "Ohne Regalplatz" and "Gesucht" marks are dropped. Cabinets and their sizes stay.
    func resetLocations() throws {
        guard !DiscogsSyncService.shared.busy else { throw ResetError.syncRunning }
        try safetyBackup()
        try PositionService(context: context).save {
            for copy in try context.fetch(FetchDescriptor<RecordCopy>()) { copy.shelf = nil; copy.positionInShelf = 0 }
            for shelf in try context.fetch(FetchDescriptor<Shelf>()) { shelf.isReserved = false; shelf.name = "" }
            for row in try context.fetch(FetchDescriptor<OptimizationExclusion>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<MissingCopyMark>()) { context.delete(row) }
        }
        LibraryChanges.shared.libraryDidChange()
        LibraryChanges.shared.shelvesDidChange()
        AppLog.warning("Zurücksetzen", "Standorte zurückgesetzt: alle Platten ohne Fach, Sperren aufgehoben")
    }

    /// Kept by every reset: where the layout backups live and how many are
    /// kept. Dropping the folder would hide every backup written there (the
    /// safety backup of the reset included), and a smaller default retention
    /// would delete older ones with the next write.
    static let preservedKeys: Set<String> = [
        ShelfAutoBackup.folder.key, ShelfAutoBackup.keptCountKey, ShelfAutoBackup.keptDaysKey,
    ]

    /// All preferences back to their defaults. The collection, the shelf
    /// layout, the Discogs token and the backups (with their folder and
    /// retention) stay.
    static func resetSettings() {
        let defaults = AppDefaults.store
        // In the demo its own domain – the real settings stay untouched.
        if let domain = AppDefaults.domainName, let stored = defaults.persistentDomain(forName: domain) {
            // The system's own entries (window sizes, panels) are left alone.
            for key in stored.keys where !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple")
                && !preservedKeys.contains(key) {
                defaults.removeObject(forKey: key)
            }
        }
        AppPreferences.shared.reset()
        AppPreferences.shared.applyAppearance()
        ScheduledExport.shared.settingsChanged()
        AppLog.warning("Zurücksetzen", "Einstellungen auf Standard zurückgesetzt")
    }

    /// Back to a fresh install: every record, the wantlist, the value
    /// history, the Discogs account and token, cached covers, extra cabinets
    /// and all settings. Backups of the layout are kept (and one more is
    /// written first), so a later restore after a new sync is possible.
    func resetEverything() async throws {
        let sync = DiscogsSyncService.shared
        guard !sync.busy else { throw ResetError.syncRunning }
        // The tracklist download after a sync still works on the releases
        // deleted below; it has to stop first. From here on nothing is awaited
        // until the token is gone, so no new sync can slip in.
        await sync.stopTracklists()
        guard !sync.busy else { throw ResetError.syncRunning }
        try safetyBackup()
        // Whatever happened to the store, the views must see its real state.
        func tellViews() {
            sync.dismissStatus()
            LibraryChanges.shared.libraryDidChange()
            LibraryChanges.shared.shelvesDidChange()
            NotificationCenter.default.post(name: .plattenregalDidReset, object: nil)
        }
        do { try deleteLibrary() } catch {
            AppLog.error("Zurücksetzen", "Alles zurücksetzen abgebrochen: \(error)")
            tellViews()
            throw error
        }

        // The records are gone now; the rest is done in any case, so the
        // app never stays half reset. A token that can't be removed is reported.
        // Settings before the first await: the automatic export would
        // otherwise overwrite the last good file with the now empty list.
        var tokenError: Error?
        do { try KeychainStore.store("") } catch { tokenError = error }
        sync.tokenChanged()
        Self.resetSettings()
        // Also before the first await: while the covers are cleared the pages
        // draw again, and none may still hold a deleted record by then.
        tellViews()
        await CoverCache.shared.clear()
        AppLog.warning("Zurücksetzen", "Alles zurückgesetzt: Sammlung, Wantlist, Statistik-Verlauf, Discogs-Konto, Cover und Einstellungen")
        if let tokenError {
            AppLog.error("Zurücksetzen", "Discogs-Token ließ sich nicht löschen: \(tokenError)")
            throw ResetError.tokenNotRemoved
        }
    }

    /// The store part of `resetEverything`: every record, the wantlist, the
    /// value history, the Discogs account, and all cabinets but a fresh first
    /// one. One transaction – either everything is gone or nothing is.
    /// Internal for the tests (unlike `resetEverything`, it leaves the
    /// keychain and the settings alone).
    func deleteLibrary() throws {
        do {
            // Links first: releases and shelves refuse to go while copies point at them.
            let copies = try context.fetch(FetchDescriptor<RecordCopy>())
            for copy in copies { copy.shelf = nil; copy.release = nil }
            let wants = try context.fetch(FetchDescriptor<WantlistEntry>())
            for entry in wants { entry.release = nil }
            for copy in copies { context.delete(copy) }
            for entry in wants { context.delete(entry) }
            for release in try context.fetch(FetchDescriptor<Release>()) { context.delete(release) }
            for row in try context.fetch(FetchDescriptor<OptimizationExclusion>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<MissingCopyMark>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<SaleCopyMark>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<CollectionValueSnapshot>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<DiscogsFolder>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<DiscogsAccount>()) { context.delete(row) }
            for cabinet in try context.fetch(FetchDescriptor<Cabinet>()) { context.delete(cabinet) }
            for shelf in try context.fetch(FetchDescriptor<Shelf>()) where !shelf.isDeleted { context.delete(shelf) }
            try context.save()
        } catch {
            // Unsaved deletions must not linger in the context and be saved
            // later by some unrelated change.
            context.rollback()
            throw error
        }
        // The fresh first cabinet. Should this fail, the next launch creates
        // it the same way – the store is empty either way.
        do { try LibraryStorage.prepareShelves(in: context) }
        catch {
            context.rollback()
            AppLog.warning("Zurücksetzen", "Erstes Regal wird beim nächsten Start angelegt: \(error)")
        }
    }

    /// Only for the app's real store (demo and test stores have nothing to lose).
    private func safetyBackup() throws {
        guard ShelfAutoBackup.isAppStore(context.container) else { return }
        do { try ShelfAutoBackup.shared.backUpNow(ShelfBackupService(context: context)) }
        catch { throw FileTransferError.safetyBackupFailed(error) }
    }
}
