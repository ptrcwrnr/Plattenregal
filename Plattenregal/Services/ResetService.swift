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
            "Gerade läuft eine Synchronisierung mit Discogs. Warte, bis sie fertig ist, und setze dann zurück."
        case .tokenNotRemoved:
            "Alles andere ist zurückgesetzt, aber der Discogs-Token ließ sich nicht aus dem Schlüsselbund löschen. Entferne ihn unter „Discogs“ oder in der Schlüsselbundverwaltung."
        }
    }
}

/// The three ways back to a clean state in the settings. Each one that
/// touches the shelf writes a backup of the current layout first; without
/// that safety net nothing is reset.
struct ResetService {
    let context: ModelContext

    /// Every record leaves its compartment, locks and names are lifted and
    /// "Nicht im Regal" and "Nicht auffindbar" marks are dropped. Cabinets and their sizes stay.
    func resetLocations() throws {
        guard !DiscogsSyncService.shared.busy else { throw ResetError.syncRunning }
        try safetyBackup()
        try PositionService(context: context).save {
            for copy in try context.fetch(FetchDescriptor<RecordCopy>()) { copy.shelf = nil; copy.positionInShelf = 0 }
            for shelf in try context.fetch(FetchDescriptor<Shelf>()) { shelf.isReserved = false; shelf.name = "" }
            for row in try context.fetch(FetchDescriptor<OptimizationExclusion>()) { context.delete(row) }
            for row in try context.fetch(FetchDescriptor<MissingCopyMark>()) { context.delete(row) }
        }
        DiscogsSyncService.shared.libraryDidChange()
        DiscogsSyncService.shared.shelvesDidChange()
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
        defer {
            sync.dismissStatus()
            sync.libraryDidChange()
            sync.shelvesDidChange()
            NotificationCenter.default.post(name: .plattenregalDidReset, object: nil)
        }
        do {
            // Copies first: releases and shelves refuse to go while copies point at them.
            for copy in try context.fetch(FetchDescriptor<RecordCopy>()) {
                copy.shelf = nil; copy.release = nil
                context.delete(copy)
            }
            for entry in try context.fetch(FetchDescriptor<WantlistEntry>()) { entry.release = nil; context.delete(entry) }
            try context.save()
            try context.delete(model: Release.self)
            try context.delete(model: OptimizationExclusion.self)
            try context.delete(model: MissingCopyMark.self)
            try context.delete(model: CollectionValueSnapshot.self)
            try context.delete(model: ReleaseMarketValue.self)
            try context.delete(model: DiscogsFolder.self)
            try context.delete(model: DiscogsAccount.self)
            for cabinet in try context.fetch(FetchDescriptor<Cabinet>()) { context.delete(cabinet) }
            for shelf in try context.fetch(FetchDescriptor<Shelf>()) where !shelf.isDeleted { context.delete(shelf) }
            try context.save()
            try LibraryStorage.prepareShelves(in: context)
        } catch {
            // Unsaved deletions must not linger in the context and be saved
            // later by some unrelated change.
            context.rollback()
            AppLog.error("Zurücksetzen", "Alles zurücksetzen abgebrochen: \(error)")
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
        await CoverCache.shared.clear()
        AppLog.warning("Zurücksetzen", "Alles zurückgesetzt: Sammlung, Wantlist, Statistik-Verlauf, Discogs-Konto, Cover und Einstellungen")
        if let tokenError {
            AppLog.error("Zurücksetzen", "Discogs-Token ließ sich nicht löschen: \(tokenError)")
            throw ResetError.tokenNotRemoved
        }
    }

    /// Only for the app's real store (demo and test stores have nothing to lose).
    private func safetyBackup() throws {
        guard ShelfAutoBackup.isAppStore(context.container) else { return }
        do { try ShelfAutoBackup.shared.backUpNow(ShelfBackupService(context: context)) }
        catch { throw FileTransferError.safetyBackupFailed(error) }
    }
}
