import Foundation
import SwiftData
import Observation

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
    private var task: Task<Bool, Never>?
    private var tracklistTask: Task<Void, Never>?
    private var tracklistRun: UUID?
    /// Whether there is anything for `DiscogsSyncStatusView` to show.
    var hasStatus: Bool { isRunning || !status.isEmpty || error != nil || summary != nil }
    /// The sync itself or the tracklist download after it is still running;
    /// only when both are done is the sync reported as finished.
    var isRunning: Bool { busy || (showsTracklists && !cancelledByUser) }
    /// The tracklist download is shown as part of a sync the user started.
    /// Resumed at launch, it runs unseen (see `tracklistsLoading`).
    private var showsTracklists = false
    /// Tracklists are being loaded, shown or not.
    private(set) var tracklistsLoading = false
    /// The sync or a tracklist download is at work, also one nobody sees
    /// (at launch). For pages that hold back their own updates meanwhile.
    var isWorking: Bool { busy || tracklistsLoading }
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
    private func finish() {
        status = Self.completedStatus
        Task {
            try? await Task.sleep(for: .seconds(5))
            if !isRunning, error == nil, status == Self.completedStatus { dismissStatus() }
        }
    }
    private let api: DiscogsAPIClient
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
    private func run(_ scope: DiscogsSyncScope, container: ModelContainer, expectedOwner: String?) async -> Bool {
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

    // MARK: Tracklists
    // Collection and wantlist endpoints only deliver basic information; tracklists
    // need one release request each (~1 s apart, see DiscogsAPIClient). They
    // are fetched in the background after a sync — and resumed at app launch
    // if a run was interrupted — and stored with `detailsFetchedAt`, so every
    // release is asked once (even if Discogs has no tracklist) and refreshed
    // after `tracklistRefreshAge`, at most `tracklistRefreshesPerRun` per run.

    nonisolated static let tracklistRefreshAge: TimeInterval = 180 * 86400
    nonisolated static let tracklistRefreshesPerRun = 100

    /// `fromSync`: part of a sync — shown right away, "abgeschlossen" at the
    /// end, problems reported. Otherwise (app launch) it stays invisible from
    /// start to end and fails quietly.
    func startTracklists(container: ModelContainer, fromSync: Bool = true) {
        if fromSync { showsTracklists = true }
        // A download cancelled by a new sync may still be winding down; queue
        // behind it instead of racing it (it only stops at the next request).
        let previous = tracklistTask
        let run = UUID()
        tracklistRun = run
        tracklistTask = Task {
            await previous?.value
            guard tracklistRun == run else { return }
            let didWork = await loadTracklists(container: container, quiet: !fromSync)
            // A newer download has taken over; leave its state alone.
            guard tracklistRun == run else { return }
            if didWork { AppLog.info("Sync", Task.isCancelled ? "Tracklisten unterbrochen, werden später fortgesetzt" : "Tracklisten geladen") }
            let wasShown = showsTracklists
            tracklistProgress = nil
            showsTracklists = false
            tracklistTask = nil
            if Task.isCancelled { if !busy && wasShown { dismissStatus() } }   // the "x"; a new sync keeps its own status
            else if fromSync { finish() }
        }
    }

    /// At launch: finish an interrupted first run (or due refreshes) without
    /// waiting for the next manual sync.
    func resumeTracklistsIfNeeded(container: ModelContainer) async {
        guard !busy, tracklistTask == nil, (try? await api.credentialFingerprint()) != nil,
              // Asked again after the wait for the client: a sync started
              // meanwhile must not get a download beside its merge – it
              // starts its own afterwards.
              !busy, tracklistTask == nil,
              let accounts = try? ModelContext(container).fetch(FetchDescriptor<DiscogsAccount>()),
              accounts.contains(where: { $0.lastCollectionSync != nil || $0.lastWantlistSync != nil })
        else { return }
        startTracklists(container: container, fromSync: false)
    }

    func cancelTracklists() { tracklistTask?.cancel() }
    /// Cancels the tracklist download and waits until it has let go of its
    /// releases – before something deletes them underneath it.
    func stopTracklists() async {
        guard let running = tracklistTask else { return }
        running.cancel()
        await running.value
    }

    /// Loads and stores the tracklist of a single release right away (popover).
    func loadTracklist(for release: Release, context: ModelContext) async throws {
        let id = release.discogsID
        let dto = try await api.release(id: id)
        guard !release.isDeleted else { return }
        // Not through `PositionService.save`: no place in the shelf changes,
        // so no layout backup and no new shelf labels.
        do { dto.applyDetails(to: release); try context.save() }
        catch { context.rollback(); throw error }
        LibraryChanges.shared.tracksDidChange()
    }

    /// Returns whether anything had to be loaded. Internal for the tests.
    func loadTracklists(container: ModelContainer, quiet: Bool) async -> Bool {
        let context = ModelContext(container)
        let pending: [Release]
        do {
            let due = try await Self.dueTracklists(container: container)
            guard !due.isEmpty else { return false }
            let releases = try context.fetch(FetchDescriptor<Release>(predicate: #Predicate { due.contains($0.persistentModelID) }))
            let byID = Dictionary(releases.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
            pending = due.compactMap { byID[$0] }
        } catch {
            if !quiet { self.error = String(localized: "Die Tracklisten konnten nicht geladen werden. ") + ReadError.wrapping(error).reportedMessage() }
            return false
        }
        guard !pending.isEmpty else { return false }

        tracklistsLoading = true
        defer { tracklistsLoading = false }
        if !quiet {
            showsTracklists = true
            tracklistProgress = (0, pending.count)
        }
        var loaded = 0
        /// A failed batch is rolled back; its releases stay without tracklist
        /// and are simply loaded again next time — but say so after a sync.
        func save() {
            guard context.hasChanges else { return }
            do { try context.save(); LibraryChanges.shared.tracksDidChange() }
            catch {
                context.rollback()
                if !quiet { self.error = String(localized: "Einige Tracklisten konnten nicht gespeichert werden. Sie werden beim nächsten Mal erneut geladen.") }
            }
        }
        for (index, release) in pending.enumerated() {
            guard !Task.isCancelled else { break }
            let id = release.discogsID
            do {
                let dto = try await api.release(id: id)
                if !release.isDeleted { dto.applyDetails(to: release); loaded += 1 }
                // Save in small batches: few UI updates, little lost on quit.
                if loaded % 10 == 0 { save() }
            } catch DiscogsError.notFound {
                // Removed on Discogs: stamped like a release without tracklist,
                // so it isn't asked again at every launch (and the status line
                // doesn't flash up each time), only with the regular refresh.
                if !release.isDeleted { release.detailsFetchedAt = .now }
            } catch DiscogsError.http(let code) where (400...499).contains(code) {
                // Same: specific to this release.
                if !release.isDeleted { release.detailsFetchedAt = .now }
            } catch DiscogsError.forbidden, DiscogsError.invalidResponse {
                // Possibly this release only – or the token or a Discogs outage,
                // which would hit every release: skip without stamping.
            } catch {
                save()
                // Cancelled by the "x" or a new sync: resume next time, no message.
                if Task.isCancelled || error is CancellationError { return true }
                // Offline, token rejected, Discogs limit …: stop, and after a
                // sync say so instead of reporting it complete.
                if !quiet {
                    let missing = pending.count - index
                    self.error = String(localized: "Noch nicht alle Tracklisten geladen – \(missing) fehlen und werden später automatisch nachgeholt. ")
                        + error.reportedMessage()
                }
                return true
            }
            if !quiet { tracklistProgress = (index + 1, pending.count) }
        }
        save()
        return true
    }

    /// The releases to ask Discogs for, in that order. Off the main actor and
    /// with the releases in one fetch: this looks at every record after each
    /// sync and at launch – on the main actor, one release at a time, right
    /// while the sync capsule changes to its next step.
    @concurrent nonisolated private static func dueTracklists(container: ModelContainer) async throws -> [PersistentIdentifier] {
        let context = ModelContext(container); context.autosaveEnabled = false
        var copyDescriptor = FetchDescriptor<RecordCopy>()
        copyDescriptor.relationshipKeyPathsForPrefetching = [\.release]
        var wantDescriptor = FetchDescriptor<WantlistEntry>()
        wantDescriptor.relationshipKeyPathsForPrefetching = [\.release]
        let copies = try context.fetch(copyDescriptor)
        let wants = try context.fetch(wantDescriptor)
        let now = Date()
        var seen = Set<PersistentIdentifier>()
        var missing: [Release] = [], stale: [Release] = []
        // Collection first, then the wantlist (its tracks make search find wanted records too).
        for release in copies.filter(\.discogsActive).compactMap(\.release) + wants.compactMap(\.release)
        where seen.insert(release.persistentModelID).inserted {
            if let fetched = release.detailsFetchedAt {
                if now.timeIntervalSince(fetched) > tracklistRefreshAge { stale.append(release) }
            } else if release.tracks.isEmpty {
                missing.append(release)
            } else {
                // Loaded before details were stamped: date it somewhere in the
                // refresh window, so refreshes trickle in instead of all at once.
                release.detailsFetchedAt = now.addingTimeInterval(-.random(in: 0..<tracklistRefreshAge))
            }
        }
        if context.hasChanges { try? context.save() }
        stale.sort { ($0.detailsFetchedAt ?? now) < ($1.detailsFetchedAt ?? now) }
        return (missing + stale.prefix(tracklistRefreshesPerRun)).map(\.persistentModelID)
    }

    /// Off the main actor; cancelling the sync cancels the merge with it.
    @concurrent nonisolated private static func mergeInBackground(_ snapshot: DiscogsSyncSnapshot, container: ModelContainer) async throws -> DiscogsSyncSummary {
        try merge(snapshot, container: container)
    }

}
