import SwiftUI

struct ShelfStatusControl: View {
    let soldInShelves: Int
    let removeSold: () -> Void

    var body: some View {
        HStack(spacing: AppStyle.tightSpacing) {
            Text("\(soldInShelves) nicht in der Collection").monospacedDigit().foregroundStyle(AppStyle.warningColor)
                .help("Nicht (mehr) in deiner Discogs-Collection – verkauft, verschenkt oder aus einem anderen Konto –, aber noch im Regal")
            Text("·").foregroundStyle(.tertiary)
            Button("Aus Regal nehmen", action: removeSold)
                .appLinkButton()
        }
        .font(.callout)
    }
}

/// Small colored tag beside a record's title ("Gesucht", "Nicht in der
/// Collection", "Als Nächstes"), the same everywhere on the shelf page.
struct StatusTag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, AppStyle.tightSpacing).padding(.vertical, AppStyle.hairSpacing)
            .background(color.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

/// Small tag on a record marked "Gesucht" (table, search, "Platte hinzufügen").
struct MissingBadge: View {
    var body: some View { StatusTag(text: String(localized: "Gesucht"), color: AppStyle.errorColor) }
}

/// Small tag on a record on the "Verkauf" list (compartment grid and table).
struct SaleBadge: View {
    var body: some View {
        StatusTag(text: String(localized: "Verkauf"), color: AppStyle.accent)
            .help("Zum Verkauf vorgemerkt – die Liste steht in den Einstellungen unter „Listen“")
    }
}

/// The records marked "Gesucht" that the app lists (settings tab "Listen")
enum MissingCopies {
    /// Those still standing in a shelf in use (shelf order), then those
    /// waiting to be sorted in (by artist).
    static func listed(_ ids: Set<UUID>, in copies: [RecordCopy], owner: String?, excluding excluded: Set<UUID>) -> [RecordCopy] {
        guard !ids.isEmpty else { return [] }
        let marked = copies.filter { ids.contains($0.id) }
        let placed = marked
            .filter { $0.shelf?.isInUse ?? false }
            .sorted { a, b in
                guard let sa = a.shelf, let sb = b.shelf else { return false }
                if sa.id != sb.id { return Shelf.physicalOrder(sa, sb) }
                return a.positionInShelf < b.positionInShelf
            }
        let waiting = marked.filter { ShelfAssignmentPresentation.isCandidate($0, owner: owner, excluding: excluded) }
        return placed + ShelfAssignmentPresentation.sortedByArtist(waiting)
    }
}
