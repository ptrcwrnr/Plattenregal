import SwiftUI

/// A record's state as a small colored dot where the record is named – no
/// text tags anywhere. Read out by VoiceOver as `label`; the tooltip says
/// what it means.
struct StatusDot: View {
    let color: Color
    let label: String
    let help: String
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: AppStyle.statusDotSize, height: AppStyle.statusDotSize)
            .accessibilityElement()
            .accessibilityLabel(label)
            .help(help)
    }
}

/// A record's tags as dots, as macOS shows tags, in a fixed order:
/// "Gesucht", "Verkauf", "Nicht in der Collection" (colors fixed per design
/// and mode, `AppStyle.markColor`). Centered in the column "Tags" of the
/// lists (shelf, collection) and behind the title in the shelf search.
struct TagDots: View {
    var missing = false
    var forSale = false
    var sold = false
    /// Where „Wieder gefunden“ and „Aus Fach entfernen“ are a right-click away.
    var offersMenu = true

    var body: some View {
        HStack(spacing: AppStyle.tightSpacing) {
            if missing {
                StatusDot(color: AppStyle.markColor(.missing), label: RecordMark.missing.title,
                          help: offersMenu ? String(localized: "Beim Einsortieren nicht gefunden – Rechtsklick → „Wieder gefunden“, sobald sie auftaucht")
                                           : String(localized: "Gesucht"))
            }
            if forSale {
                StatusDot(color: AppStyle.markColor(.sale), label: RecordMark.sale.title,
                          help: String(localized: "Zum Verkauf vorgemerkt – die Liste steht in den Einstellungen unter „Listen“"))
            }
            if sold {
                StatusDot(color: AppStyle.markColor(.sold), label: RecordMark.sold.title,
                          help: String(localized: "Nicht (mehr) in deiner Discogs-Collection – per Rechtsklick aus dem Fach entfernen"))
            }
        }
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
