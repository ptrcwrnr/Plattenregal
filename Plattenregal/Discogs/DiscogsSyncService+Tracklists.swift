import Foundation
import SwiftData
import Observation
import OSLog

extension DiscogsSyncService {
    // Collection and wantlist endpoints only deliver basic information; tracklists
    // need one release request each (~1 s apart, see DiscogsAPIClient). They
    // are fetched in the background after a sync — and resumed at app launch
    // if a run was interrupted — and stored with `detailsFetchedAt`, so every
    // release is asked once (even if Discogs has no tracklist) and refreshed
    // after `tracklistRefreshAge`, at most `tracklistRefreshesPerRun` per run.

    nonisolated static let tracklistRefreshAge: TimeInterval = 180 * 86400
    nonisolated static let tracklistRefreshesPerRun = 100

    /// `fromSync`: part of a sync — shown right away, "abgeschlossen" at the
    /// end, problems reported. Otherwise (app launch) it stays invisible
    /// unless there is something to load, and fails quietly.
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
            else if fromSync || didWork { finish() }
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

        showsTracklists = true
        tracklistProgress = (0, pending.count)
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
            tracklistProgress = (index + 1, pending.count)
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
}
