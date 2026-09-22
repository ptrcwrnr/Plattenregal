import Foundation
import SwiftData
import Observation

@MainActor @Observable final class StatisticsViewModel {
    var statistics = CollectionStatistics()
    var copies: [RecordCopy] = []
    var history: [CollectionValueSnapshot] = []
    var prices: [ReleaseMarketValue] = []
    var owners: [String] = []
    var owner = ""
    var busy = false
    var calculating = false
    var error: String?
    private var generation = 0
    @ObservationIgnored private var readContext: ModelContext?
    func reload(container: ModelContainer) async {
        generation += 1; let current = generation
        calculating = true
        defer { if generation == current { calculating = false } }
        do {
            let context = ModelContext(container)
            let accounts = try context.fetch(FetchDescriptor<DiscogsAccount>())
            owners = accounts.map(\.username).sorted()
            let all = try context.fetch(FetchDescriptor<RecordCopy>())
            let selected = all.filter { owner.isEmpty ? $0.discogsActive != false : $0.discogsOwner == owner && $0.discogsActive == true }
            let inputs = selected.map(AnalyticsItem.init)
            let stats = await Task.detached(priority: .userInitiated) { CollectionAnalyticsService.calculate(inputs) }.value
            guard current == generation, !Task.isCancelled else { return }
            // Fetch everything before committing any of it, so a failure here can't leave
            // `copies`/`statistics` reflecting a different owner than `history`/`prices`.
            let newHistory = try context.fetch(FetchDescriptor<CollectionValueSnapshot>(sortBy: [SortDescriptor(\.date)])).filter { $0.owner == owner }
            let newPrices = try context.fetch(FetchDescriptor<ReleaseMarketValue>()).filter { $0.owner == owner }
            readContext = context
            copies = selected; statistics = stats
            history = newHistory; prices = newPrices
        } catch { self.error = error.localizedDescription }
    }
    func initialLoad(container: ModelContainer) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--statistics-demo") {
            owner = "Demo · Beispieldaten"
            await reload(container: container)
            return
        }
        #endif
        do {
            let fingerprint = try await DiscogsAPIClient.shared.credentialFingerprint()
            let accounts = try ModelContext(container).fetch(FetchDescriptor<DiscogsAccount>())
            owner = accounts.first { $0.credentialFingerprint == fingerprint }?.username ?? ""
        } catch { /* Local analytics also work without a token. */ }
        await reload(container: container)
    }
    func refresh(container: ModelContainer, force: Bool = true) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        await reload(container: container)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--statistics-demo") { return }
        #endif
        if !owner.isEmpty {
            do { try await CollectionValueHistoryService.shared.refresh(owner: owner, container: container, force: force) }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription }
        }
        await reload(container: container)
    }
}
