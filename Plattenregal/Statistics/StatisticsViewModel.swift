import Foundation
import SwiftData
import Observation

@Observable final class StatisticsViewModel {
    var statistics = CollectionStatistics()
    var copies: [RecordCopy] = []
    var copiesByID: [UUID: RecordCopy] = [:]
    var history: [CollectionValueSnapshot] = []
    var owner = ""
    /// A Discogs token is stored; without one the value can't be fetched.
    var hasToken = false
    var busy = false
    var calculating = false
    var error: String?
    /// Bumped whenever freshly loaded data is committed; views that cache
    /// something derived from `copies` refresh on it.
    private(set) var version = 0
    private var generation = 0

    init() {
        // After "Alles zurücksetzen" `copies` are deleted records: reading
        // one of them, its shelf or release crashes ("backing data could no
        // longer be found"). The reset posts on the main thread before
        // anything is drawn again, so everything is dropped right there; the
        // page reloads on the save that came with it.
        NotificationCenter.default.addObserver(forName: .plattenregalDidReset, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.forget() }
        }
    }

    /// Drops every loaded record; an unfinished `reload` won't commit either.
    func forget() {
        generation += 1; calculating = false
        copies = []; copiesByID = [:]; history = []
        statistics = CollectionStatistics()
        version += 1
    }
    func reload(container: ModelContainer) async {
        generation += 1; let current = generation
        calculating = true
        defer { if generation == current { calculating = false } }
        do {
            let loaded = try await Self.load(container, owner: owner.isEmpty ? nil : owner)
            guard current == generation, !Task.isCancelled else { return }
            // Fetch everything before committing any of it, so a failure here can't leave
            // `copies`/`statistics` reflecting a different owner than `history`.
            let newHistory = try ModelContext(container).fetch(FetchDescriptor<CollectionValueSnapshot>(predicate: #Predicate { $0.owner == owner }, sortBy: [SortDescriptor(\.date)]))
            // The records shown (top artists, latest additions, random pick)
            // are the app's own, already loaded for every page: the same
            // objects the detail panel edits, and gone after a reset.
            let all = Dictionary(LibraryRecords.of(container.mainContext).copies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let selected = loaded.ids.compactMap { all[$0] }
            copies = selected; statistics = loaded.statistics
            copiesByID = Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            history = newHistory
            version += 1
        } catch { self.error = ReadError.wrapping(error).reportedMessage() }
    }
    func initialLoad(container: ModelContainer) async {
        await resolveOwner(container: container)
        await reload(container: container)
    }
    /// The account the collection shows: the one synced most recently, as
    /// everywhere else in the app (`DiscogsAccount.current`). Not only at
    /// launch: the first sync (or one for another account) switches it later,
    /// and value history must follow without restarting the app. Changing
    /// `owner` reloads the page (see StatisticsView). Whether the stored token
    /// still belongs to it is checked when the value is fetched.
    func resolveOwner(container: ModelContainer) async {
        updateTokenState()
        let accounts = (try? ModelContext(container).fetch(FetchDescriptor<DiscogsAccount>())) ?? []
        let resolved = DiscogsAccount.current(in: accounts)?.username ?? ""
        if owner != resolved { owner = resolved }
    }
    /// Re-read when the page is shown: the token is changed in the settings.
    func updateTokenState() {
        // Same rule as everywhere else, demo included.
        let stored = KeychainStore.hasToken
        if hasToken != stored { hasToken = stored }
    }
    func refresh(container: ModelContainer, force: Bool = true) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        await reload(container: container)
        // No Discogs in the demo: recalculating is all a refresh does.
        if DemoMode.isActive { return }
        if !owner.isEmpty {
            do { try await CollectionValueHistoryService.shared.refresh(owner: owner, container: container, force: force) }
            catch is CancellationError { return }
            catch { self.error = error.reportedMessage() }
        }
        await reload(container: container)
    }

    /// Off the main actor, in a context of its own, so large collections
    /// don't stall the UI: reading every record and its release (~0.15 s for
    /// 2 000 after each sync) as well as the calculation, which decodes each
    /// release's Discogs JSON. Same records as the collection (see
    /// `DiscogsAccount.current`), so a number here matches what the
    /// drill-down then shows.
    @concurrent nonisolated private static func load(_ container: ModelContainer, owner: String?) async throws -> (statistics: CollectionStatistics, ids: [UUID]) {
        let context = ModelContext(container)
        // Every release is read right below: in one fetch, not one request per release.
        var descriptor = FetchDescriptor<RecordCopy>()
        descriptor.relationshipKeyPathsForPrefetching = [\.release]
        let selected = try context.fetch(descriptor).filter { $0.isInCurrentCollection(owner: owner) }
        let inputs = selected.map(AnalyticsItem.Raw.init)
        return (CollectionAnalyticsService.calculate(inputs.map(AnalyticsItem.init)), inputs.map(\.id))
    }
}
