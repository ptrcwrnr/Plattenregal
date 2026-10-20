import Foundation
import SwiftData
import Observation
import OSLog

@Observable final class DiscogsSyncService {
    static let shared = DiscogsSyncService()
    var busy = false
    /// Fingerprint of a token Discogs turned down (401) during the last sync,
    /// so the settings don't keep saying "connected"; cleared by a good sync.
    private(set) var rejectedFingerprint: String?
    /// Bumped whenever the settings store or remove the token, so pages in
    /// other windows re-check it without reading the keychain on every activation.
    private(set) var tokenRevision = 0
    var status = ""
    var error: String?
    var summary: String?
    /// Progress of the tracklist download after a collection sync; `nil` when idle.
    var tracklistProgress: (done: Int, total: Int)?
    var task: Task<Bool, Never>?
    var tracklistTask: Task<Void, Never>?
    var tracklistRun: UUID?
    /// Whether there is anything for `DiscogsSyncStatusView` to show.
    var hasStatus: Bool { isRunning || !status.isEmpty || error != nil || summary != nil }
    /// The sync itself or the tracklist download after it is still running;
    /// only when both are done is the sync reported as finished.
    var isRunning: Bool { busy || (showsTracklists && !cancelledByUser) }
    /// The tracklist download is shown as part of the sync. After a sync it is
    /// shown right away; when resumed at launch only once there is work.
    var showsTracklists = false
    /// Set by the "x": whatever ends next clears the status instead of
    /// reporting "abgebrochen", so the lines slide away right after.
    private var cancelledByUser = false

    /// Removes the status lines (they animate out where they're shown).
    func dismissStatus() { status = ""; summary = nil; error = nil }
    func tokenChanged() { tokenRevision += 1 }
    /// A connection test succeeded with this token; forget that a sync saw it rejected.
    func tokenAccepted(fingerprint: String) {
        if rejectedFingerprint == fingerprint { rejectedFingerprint = nil }
    }

    /// The status after a successful sync; also how views recognise it.
    static let completedStatus = String(localized: "Synchronisierung abgeschlossen")

    /// Success: show "abgeschlossen" briefly, then let the lines go — unless
    /// something else (an error, a new sync) has taken over meanwhile.
    func finish() {
        status = Self.completedStatus
        Task {
            try? await Task.sleep(for: .seconds(5))
            if !isRunning, error == nil, status == Self.completedStatus { dismissStatus() }
        }
    }
    let api: DiscogsAPIClient
    init(api: DiscogsAPIClient = .shared) { self.api = api }
    func start(_ scope: DiscogsSyncScope, container: ModelContainer, expectedOwner: String? = nil) {
        guard !busy else { return }
        // The demo's sample collection must never be merged with a real one.
        guard !DemoMode.isActive else { status = ""; summary = nil; error = DiscogsError.demoMode.errorDescription; return }
        // Set synchronously so two windows cannot start competing merges.
        busy = true
        cancelledByUser = false
        // Never write tracklists while a merge rewrites the same releases;
        // the backfill restarts after the sync and resumes where it stopped.
        cancelTracklists()
        AppLog.info("Sync", "Gestartet: \(scope.logName)")
        task = Task { await run(scope, container: container, expectedOwner: expectedOwner) }
    }
    func cancel() {
        AppLog.info("Sync", "Vom Nutzer abgebrochen")
        cancelledByUser = true
        task?.cancel(); cancelTracklists()
        // Tracklists stop at their next request; hide the lines right away.
        if !busy { dismissStatus() }
    }
    func run(_ scope: DiscogsSyncScope, container: ModelContainer, expectedOwner: String?) async -> Bool {
        error = nil; summary = nil
        defer { busy = false; task = nil }
        do {
            let snapshot: DiscogsSyncSnapshot
            do {
                snapshot = try await fetch(scope, container: container, expectedOwner: expectedOwner)
            } catch DiscogsError.incompletePagination {
                // Usually the collection changed on Discogs while it was being
                // read (a record added, moved, removed). Nothing was saved; one
                // fresh attempt normally succeeds.
                status = String(localized: "Discogs-Daten haben sich geändert – neuer Versuch")
                try await Task.sleep(for: .seconds(2))
                snapshot = try await fetch(scope, container: container, expectedOwner: expectedOwner)
            }
            try Task.checkCancellation()
            guard try await api.credentialFingerprint() == snapshot.fingerprint else { throw DiscogsError.accountChanged }
            status = String(localized: "Änderungen werden gespeichert")
            let result = try await Self.mergeInBackground(snapshot, container: container)
            summary = result.description(for: scope)
            AppLog.info("Sync", "Gespeichert (\(scope.logName), Konto \(snapshot.username)): \(summary ?? "–")")
            rejectedFingerprint = nil
            // Nothing new: the pages keep their sorted lists, indexes and labels.
            if result.hasChanges { LibraryChanges.shared.syncDidCommit() }
            else { AppLog.info("Sync", "Keine Änderungen, Seiten bleiben unverändert") }
            if scope == .collection || scope == .all || scope == .folder(0) {
                status = String(localized: "Sammlungswert wird aktualisiert")
                do {
                    try await CollectionValueHistoryService.shared.refresh(owner: snapshot.username, container: container, api: api, force: true)
                } catch {
                    // Collection merge is committed. A valuation failure must not roll it back or claim it failed.
                    // The "x" during this step is no failure either (see below).
                    if !cancelledByUser {
                        self.error = String(localized: "Die Sammlung ist aktualisiert, nur der Sammlungswert konnte nicht geladen werden. ") + error.reportedMessage()
                    }
                }
            }
            // The "x" after the merge was committed: nothing to roll back and
            // nothing to report. The tracklists aren't started behind a status
            // that is gone (and couldn't be stopped); the next sync or launch
            // loads them.
            if cancelledByUser {
                AppLog.info("Sync", "Nach dem Speichern abgebrochen, Tracklisten folgen später (\(scope.logName))")
                dismissStatus()
                return true
            }
            // "abgeschlossen" only once the tracklists are through as well.
            startTracklists(container: container)
            return true
        } catch is CancellationError {
            AppLog.info("Sync", "Abgebrochen, nichts gespeichert (\(scope.logName))")
            if cancelledByUser { dismissStatus() }
            else { status = String(localized: "Synchronisierung abgebrochen. Keine Änderungen gespeichert.") }
            return false
        }
        catch {
            // A cancelled request can surface as a network error; the "x" wins.
            if cancelledByUser { dismissStatus(); return false }
            // `reportedMessage` puts the technical detail into the protocol.
            self.error = error.reportedMessage(); status = String(localized: "Synchronisierung fehlgeschlagen")
            if case DiscogsError.unauthorized = error { rejectedFingerprint = try? await api.credentialFingerprint() }
            return false
        }
    }
    func fetch(_ scope: DiscogsSyncScope, container: ModelContainer, expectedOwner: String? = nil) async throws -> DiscogsSyncSnapshot {
        status = String(localized: "Discogs-Konto wird geprüft")
        let fingerprint = try await api.credentialFingerprint()
        let context = ModelContext(container)
        let accounts = try context.fetch(FetchDescriptor<DiscogsAccount>())
        let cached = accounts.first { $0.credentialFingerprint == fingerprint }
        let username: String; let userID: Int?
        if let cached { username = cached.username; userID = cached.userID }
        else { let identity = try await api.identity(); username = identity.username; userID = identity.id }
        if let expectedOwner, expectedOwner != username { throw DiscogsError.accountChanged }
        var snapshot = DiscogsSyncSnapshot(username: username, userID: userID, fingerprint: fingerprint, scope: scope)
        switch scope {
        case .collection, .all, .folder:
            status = String(localized: "Discogs-Ordner werden geladen")
            snapshot.folders = try await api.folders(username: username)
            let folderID: Int
            if case .folder(let id) = scope { folderID = id } else { folderID = 0 }
            status = String(localized: "Collection wird geladen")
            snapshot.collection = try await api.collection(username: username, folderID: folderID)
        default: break
        }
        if let folders = snapshot.folders, let collection = snapshot.collection {
            let folderIDs = Set(folders.map(\.id))
            guard collection.allSatisfy({ folderIDs.contains($0.folder_id) }) else { throw DiscogsError.incompletePagination }
        }
        if scope == .wantlist || scope == .all {
            status = String(localized: "Wantlist wird geladen")
            snapshot.wants = try await api.wants(username: username)
        }
        guard try await api.credentialFingerprint() == fingerprint else { throw DiscogsError.accountChanged }
        return snapshot
    }

}
