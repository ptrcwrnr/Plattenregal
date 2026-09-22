import Foundation
import SwiftData
import Observation

enum MarketPriceSource: String, CaseIterable, Identifiable {
    case priceSuggestion, marketplaceLowestPrice
    var id: String { rawValue }
    var title: String { self == .priceSuggestion ? "Preisvorschläge" : "Günstigste Angebote" }
}
@MainActor @Observable final class MarketValueService {
    static let shared = MarketValueService()
    var busy = false
    var completed = 0
    var total = 0
    var message: String?
    private var task: Task<Void, Never>?
    func cancel() { task?.cancel() }
    static func suggested(_ values: [String: DiscogsPrice]) -> (String, DiscogsPrice)? {
        // Fixed preference order, never pick the most expensive grade.
        for condition in ["Very Good Plus (VG+)", "Very Good (VG)", "Near Mint (NM or M-)", "Good Plus (G+)", "Good (G)", "Mint (M)", "Fair (F)", "Poor (P)"] {
            if let price = values[condition], price.value > 0, price.currency.count == 3 { return (condition, price) }
        }
        return nil
    }
    func start(owner: String, releaseIDs: [Int], source: MarketPriceSource, force: Bool, container: ModelContainer, api: DiscogsAPIClient = .shared) {
        guard !busy else { return }
        busy = true; completed = 0; total = 0; message = nil
        task = Task {
            defer { busy = false; task = nil }
            let context = ModelContext(container); context.autosaveEnabled = false
            do {
                let fingerprint = try await api.credentialFingerprint()
                let accounts = try context.fetch(FetchDescriptor<DiscogsAccount>())
                guard accounts.contains(where: { $0.username == owner && $0.credentialFingerprint == fingerprint }) else { throw DiscogsError.accountChanged }
                let cache = try context.fetch(FetchDescriptor<ReleaseMarketValue>()).filter { $0.owner == owner && $0.source == source.rawValue }
                let indexed = Dictionary(uniqueKeysWithValues: cache.map { ($0.releaseID, $0) })
                let ids = Set(releaseIDs).sorted().filter { force || indexed[$0] == nil || indexed[$0]?.stale == true }
                total = ids.count
                for id in ids {
                    try Task.checkCancellation()
                    var value: Decimal?, currency = "", condition = ""
                    do {
                        switch source {
                        case .priceSuggestion:
                            if let (grade, price) = Self.suggested(try await api.priceSuggestions(releaseID: id)) {
                                value = price.value; currency = price.currency; condition = grade
                            }
                        case .marketplaceLowestPrice:
                            if let price = try await api.marketplaceStats(releaseID: id).lowest_price, price.value > 0, price.currency.count == 3 {
                                value = price.value; currency = price.currency
                            }
                        }
                    } catch DiscogsError.notFound { /* Cache confirmed missing data for seven days too. */ }
                    try Task.checkCancellation()
                    guard try await api.credentialFingerprint() == fingerprint else { throw DiscogsError.accountChanged }
                    let row = indexed[id] ?? ReleaseMarketValue(owner: owner, releaseID: id, value: value, currency: currency, condition: condition, source: source.rawValue)
                    context.insert(row); row.estimatedValue = value; row.currency = currency; row.condition = condition; row.updatedAt = .now
                    completed += 1
                    // Saving after every single network round-trip forces a synchronous
                    // SwiftData write on the main actor each time, stalling the UI during
                    // large batches; flushing every few items keeps progress durable
                    // without paying that cost on every iteration.
                    if completed.isMultiple(of: 5) || completed == total { try context.save() }
                }
                message = ids.isEmpty ? "Alle Preise im Cache sind aktuell." : "\(completed) Preisabfragen abgeschlossen."
            } catch is CancellationError { try? context.save(); message = "Abgebrochen · \(completed) Ergebnisse gespeichert." }
            catch { message = error.localizedDescription + (source == .priceSuggestion ? " Du kannst separat die günstigsten Marketplace-Angebote abrufen." : "") }
        }
    }
}
struct ValuableRelease: Identifiable {
    let copy: RecordCopy
    let price: ReleaseMarketValue
    var id: Int { price.releaseID }
}
enum MarketRanking {
    static func top(copies: [RecordCopy], prices: [ReleaseMarketValue], owner: String, source: MarketPriceSource, currency: String, condition: String) -> [ValuableRelease] {
        var byID: [Int: RecordCopy] = [:]
        for copy in copies { if let id = copy.release?.discogsID, byID[id] == nil { byID[id] = copy } }
        return prices.filter {
            $0.owner == owner && $0.source == source.rawValue && $0.currency == currency &&
            (source != .priceSuggestion || $0.condition == condition) && $0.estimatedValue != nil && byID[$0.releaseID] != nil
        }.sorted {
            $0.estimatedValue == $1.estimatedValue ? $0.releaseID < $1.releaseID : $0.estimatedValue! > $1.estimatedValue!
        }.prefix(10).compactMap { price in byID[price.releaseID].map { ValuableRelease(copy: $0, price: price) } }
    }
}
