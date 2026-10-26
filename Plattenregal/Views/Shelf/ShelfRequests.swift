import SwiftUI

/// What other pages ask of the shelf page. An object, not a binding: pages
/// live in separate hosting views (see `PageStack`), and only Observation
/// reaches across.
@Observable final class ShelfRequests {
    /// A record to show: where it stands and between which records, or –
    /// without a shelf – where it belongs.
    var placing: UUID?
    /// One of the round buttons clicked (or ⌘Y), taken by the page: it opens
    /// that button's panel, or closes it if it is the one open.
    var pressed: ShelfButton?
    /// The panel over the shelf page. Here and not in the page, so the round
    /// buttons can show that theirs is open; only the page opens and closes it.
    var panel: ShelfPanel?
}

/// The panel over the shelf page. One value for all of them, so only one
/// can ever be open: opening another one replaces it.
enum ShelfPanel: Identifiable {
    /// "Platte hinzufügen" for a compartment, or rack-wide "Einsortieren".
    case assignment(ShelfAssignmentSession)
    /// "Sortierung prüfen" of a compartment.
    case sortCheck(ShelfSortCheckRequest)
    /// The "Verlauf".
    case history(ShelfHistoryRequest)

    var id: UUID {
        switch self {
        case .assignment(let session): session.id
        case .sortCheck(let request): request.id
        case .history(let request): request.id
        }
    }

    /// The round button this panel opens from, if any.
    var button: ShelfButton? {
        switch self {
        case .assignment(let session): session.isRackWide ? .sortingIn : nil
        case .sortCheck: nil
        case .history: .history
        }
    }
}

/// The shelf page's round buttons. Each opens its panel and, clicked again,
/// closes it; the other one switches straight to its own panel.
enum ShelfButton {
    /// "Verlauf" (also ⌘Y).
    case history
    /// "Einsortieren": every record without a shelf, each to its place.
    case sortingIn
}

/// What is typed into the search field in the toolbar while the shelf page is
/// shown (see `ToolbarSearchField`). An object, read by the page itself: the
/// page is built once (see `PageStack`).
@Observable final class ShelfSearch {
    var text = ""
}
