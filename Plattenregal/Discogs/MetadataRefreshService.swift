import Foundation
import Observation
import SwiftData

/// Reloads the Discogs data of single releases right away, fresh or not —
/// for "Discogs-Daten aktualisieren" on selected records. Everything else
/// arrives with the regular sync.
@Observable final class MetadataRefreshService {
    var busy = false
    var error: String?

    func reload(_ releases: [Release], context: ModelContext) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false; LibraryChanges.shared.libraryDidChange() }
        var failed = 0, total = 0
        var reason: String?
        AppLog.info("Discogs", "Release-Daten neu laden: \(releases.count) Release(s)")
        for release in releases {
            let id = release.discogsID
            total += 1
            do {
                let dto = try await DiscogsAPIClient.shared.release(id: id)
                guard !release.isDeleted else { continue }
                try PositionService(context: context).save { dto.apply(to: release) }
            } catch is CancellationError { return }
            catch { failed += 1; reason = error.reportedMessage() }
        }
        AppLog.info("Discogs", failed == 0 ? "Release-Daten neu geladen: \(total) Release(s)"
                    : "Release-Daten neu laden: \(failed) von \(total) fehlgeschlagen")
        // One message for the whole selection, saying how much went through.
        if failed > 0, let reason {
            error = total == 1 ? reason
                : failed == total ? "Keine der \(total) Platten konnte aktualisiert werden. " + reason
                : "\(failed) von \(total) Platten konnten nicht aktualisiert werden, die übrigen schon. " + reason
        }
    }
}
