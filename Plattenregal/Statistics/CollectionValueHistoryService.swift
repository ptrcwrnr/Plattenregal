import Foundation
import SwiftData
import CryptoKit

final class CollectionValueHistoryService {
    static let shared = CollectionValueHistoryService()
    private var pending: Set<String> = []
    nonisolated static func signature(_ copies: [RecordCopy]) -> String {
        let ids = copies.map { "\($0.discogsInstanceID):\($0.release?.discogsID ?? 0)" }.sorted().joined(separator: "|")
        return SHA256.hash(data: Data(ids.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func latest(owner: String, in context: ModelContext) throws -> CollectionValueSnapshot? {
        var descriptor = FetchDescriptor<CollectionValueSnapshot>(predicate: #Predicate { $0.owner == owner },
                                                                  sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
    static func shouldStore(last: CollectionValueSnapshot?, value: DiscogsCollectionValue, signature: String, date: Date, calendar: Calendar = .current) -> Bool {
        guard let last else { return true }
        if last.currency != value.median.currency || last.collectionSignature != signature || !calendar.isDate(last.date, inSameDayAs: date) { return true }
        func significant(_ old: Decimal, _ new: Decimal) -> Bool { abs(new - old) >= max(1, abs(old) * Decimal(string: "0.01")!) }
        return significant(last.minimumValue, value.minimum.amount) || significant(last.medianValue, value.median.amount) || significant(last.maximumValue, value.maximum.amount)
    }
    @discardableResult static func store(value: DiscogsCollectionValue, owner: String, copies: [RecordCopy], context: ModelContext, date: Date = .now) throws -> Bool {
        try store(value: value, owner: owner, count: copies.count, signature: signature(copies), context: context, date: date)
    }
    @discardableResult static func store(value: DiscogsCollectionValue, owner: String, count: Int, signature: String, context: ModelContext, date: Date = .now) throws -> Bool {
        let last = try latest(owner: owner, in: context)
        guard shouldStore(last: last, value: value, signature: signature, date: date) else {
            // Keep today's displayed valuation current without adding near-identical history points.
            if let last, last.minimumValue != value.minimum.amount || last.medianValue != value.median.amount || last.maximumValue != value.maximum.amount {
                last.minimumValue = value.minimum.amount; last.medianValue = value.median.amount
                last.maximumValue = value.maximum.amount; last.date = date
                try context.save()
            }
            return false
        }
        context.insert(CollectionValueSnapshot(owner: owner, date: date, value: value, count: count, signature: signature))
        try context.save(); return true
    }
    func refresh(owner: String, container: ModelContainer, api: DiscogsAPIClient = .shared, force: Bool = false) async throws {
        guard !pending.contains(owner) else { return }
        pending.insert(owner); defer { pending.remove(owner) }
        let context = ModelContext(container); context.autosaveEnabled = false
        let fingerprint = try await api.credentialFingerprint()
        let accounts = try context.fetch(FetchDescriptor<DiscogsAccount>())
        guard let account = accounts.first(where: { $0.username == owner && $0.credentialFingerprint == fingerprint }) else { throw DiscogsError.accountChanged }
        // Only the wantlist synced so far: no collection to value yet – not a changed token.
        guard account.lastCollectionSync != nil else { return }
        var collection = try await Self.activeCollection(owner: owner, container: container)
        let last = try Self.latest(owner: owner, in: context)
        if !force, let last, Calendar.current.isDateInToday(last.date), last.collectionSignature == collection.signature { return }
        // A sync saving meanwhile changes the collection under the request
        // (and skips its own refresh while this one runs): ask once more for
        // the new collection instead of storing a value that fits neither.
        for attempt in 1...2 {
            let value = try await api.fetchCollectionValue(username: owner)
            try Task.checkCancellation()
            guard try await api.credentialFingerprint() == fingerprint else { throw DiscogsError.accountChanged }
            let now = try await Self.activeCollection(owner: owner, container: container)
            if now.signature == collection.signature {
                try Self.store(value: value, owner: owner, count: collection.count, signature: collection.signature, context: context)
                return
            }
            AppLog.info("Statistik", "Sammlung hat sich beim Laden des Werts geändert\(attempt == 1 ? " – neuer Versuch" : ", Wert diesmal nicht gespeichert")")
            collection = now
        }
    }
    /// What the value belongs to, read off the main actor and with the
    /// releases in one fetch: on the main actor this read every record and,
    /// one by one, its release – twice per sync, while its capsule is shown.
    @concurrent nonisolated private static func activeCollection(owner: String, container: ModelContainer) async throws -> (signature: String, count: Int) {
        var descriptor = FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.discogsOwner == owner && $0.discogsActive == true })
        descriptor.relationshipKeyPathsForPrefetching = [\.release]
        let copies = try ModelContext(container).fetch(descriptor)
        return (signature(copies), copies.count)
    }
    static func change(current: Decimal, previous: Decimal) -> (amount: Decimal, percent: Decimal?) {
        (current - previous, previous == 0 ? nil : (current - previous) / abs(previous) * 100)
    }
}
