import Foundation
import Observation
import SwiftData

@MainActor @Observable final class DiscogsSearchModel {
    var query = ""
    var results: [DiscogsSearchResult] = []
    var preview: Release?
    var busy = false
    var error: String?
    var page = 0
    var pages = 0
    var searched = false
    var fetchedAt: Date?
    private var submittedQuery = ""
    var fresh: Bool { fetchedAt.map { Date().timeIntervalSince($0) < 6 * 3600 - 30 } ?? false }
    func search(more: Bool = false) async {
        guard !busy else { return }
        let text = more ? submittedQuery : query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let result = try await DiscogsAPIClient.shared.search(text, page: more ? page + 1 : 1)
            results = more ? results + result.results.filter { new in !results.contains(where: { $0.id == new.id }) } : result.results
            results = results.filter { $0.type == "release" }
            page = result.pagination.page; pages = result.pagination.pages
            submittedQuery = text; searched = true
            // Do not extend the lifetime of earlier pages when loading more.
            if !more { fetchedAt = .now }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    func select(_ result: DiscogsSearchResult) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do { preview = try await DiscogsAPIClient.shared.release(id: result.id).mappedRelease() }
        catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
}

@MainActor @Observable final class MetadataRefreshService {
    var busy = false
    var error: String?
    func refresh(_ releases: [Release], context: ModelContext) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        let synced = releases.filter { !$0.isFresh && $0.basicInformation != nil }
        if !synced.isEmpty {
            DiscogsSyncService.shared.start(.collection, container: context.container)
        }
        for release in releases where !release.isFresh && release.basicInformation == nil {
            guard let id = release.discogsID else { continue }
            do {
                let dto = try await DiscogsAPIClient.shared.release(id: id)
                guard !release.isDeleted else { continue }
                try PositionService(context: context).save { dto.apply(to: release) }
            } catch is CancellationError { return }
            catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor @Observable final class DiscogsSettingsModel {
    var token = ""
    var status = ""
    var busy = false
    var failed = false
    func load() {
        do { token = try KeychainStore.load() ?? "" }
        catch { status = error.localizedDescription; failed = true }
    }
    @discardableResult func save() -> Bool {
        do {
            try KeychainStore.store(token)
            status = token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Token entfernt." : "Token sicher gespeichert."
            failed = false; return true
        } catch { status = error.localizedDescription; failed = true; return false }
    }
    func test() async {
        guard !busy, save() else { return }
        busy = true; defer { busy = false }
        do {
            let name = try await DiscogsAPIClient.shared.testToken()
            status = "Verbunden als \(name)"; failed = false
        } catch { status = error.localizedDescription; failed = true }
    }
}
