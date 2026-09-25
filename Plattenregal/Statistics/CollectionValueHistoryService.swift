import Foundation
import SwiftData
import CryptoKit

final class CollectionValueHistoryService {
    static let shared = CollectionValueHistoryService()
    private var pending: Set<String> = []
    static func signature(_ copies: [RecordCopy]) -> String {
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
        let last = try latest(owner: owner, in: context)
        let signature = signature(copies)
        guard shouldStore(last: last, value: value, signature: signature, date: date) else {
            // Keep today's displayed valuation current without adding near-identical history points.
            if let last, last.minimumValue != value.minimum.amount || last.medianValue != value.median.amount || last.maximumValue != value.maximum.amount {
                last.minimumValue = value.minimum.amount; last.medianValue = value.median.amount
                last.maximumValue = value.maximum.amount; last.date = date
                try context.save()
            }
            return false
        }
        context.insert(CollectionValueSnapshot(owner: owner, date: date, value: value, count: copies.count, signature: signature))
        try context.save(); return true
    }
    func refresh(owner: String, container: ModelContainer, api: DiscogsAPIClient = .shared, force: Bool = false) async throws {
        guard !pending.contains(owner) else { return }
        pending.insert(owner); defer { pending.remove(owner) }
        let context = ModelContext(container); context.autosaveEnabled = false
        let fingerprint = try await api.credentialFingerprint()
        let accounts = try context.fetch(FetchDescriptor<DiscogsAccount>())
        guard let account = accounts.first(where: { $0.username == owner && $0.credentialFingerprint == fingerprint }), account.lastCollectionSync != nil else { throw DiscogsError.accountChanged }
        func activeCopies() throws -> [RecordCopy] {
            try context.fetch(FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.discogsOwner == owner && $0.discogsActive == true }))
        }
        let copies = try activeCopies(), signature = Self.signature(copies)
        let last = try Self.latest(owner: owner, in: context)
        if !force, let last, Calendar.current.isDateInToday(last.date), last.collectionSignature == signature { return }
        let value = try await api.fetchCollectionValue(username: owner)
        try Task.checkCancellation()
        guard try await api.credentialFingerprint() == fingerprint, Self.signature(try activeCopies()) == signature else { throw DiscogsError.accountChanged }
        try Self.store(value: value, owner: owner, copies: copies, context: context)
    }
    static func change(current: Decimal, previous: Decimal) -> (amount: Decimal, percent: Decimal?) {
        (current - previous, previous == 0 ? nil : (current - previous) / abs(previous) * 100)
    }
}
